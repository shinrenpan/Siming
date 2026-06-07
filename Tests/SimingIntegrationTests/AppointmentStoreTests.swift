import Foundation
import ModelsR4
@testable import SimingCore
import XCTest

final class AppointmentStoreTests: XCTestCase {
    var store: AppointmentStore!
    var patientStore: PatientStore!

    override func setUp() async throws {
        try await super.setUp()
        try await requireDatabase()
        store        = try await TestDatabase.shared.makeAppointmentStore()
        patientStore = try await TestDatabase.shared.makePatientStore()
    }

    // ── CRUD ──────────────────────────────────────────────────────────────────

    func testCreate_assignsIdAndVersionOne() async throws {
        let patient = try await patientStore.create(makePatient(family: "ApptCreate"))
        let appt = try makeAppointment(patientId: patient.id)
        let result = try await store.create(appt)
        XCTAssertFalse(result.id.isEmpty)
        XCTAssertEqual(result.versionId, 1)
    }

    func testRead_returnsStoredResource() async throws {
        let patient = try await patientStore.create(makePatient(family: "ApptRead"))
        let created = try await store.create(makeAppointment(patientId: patient.id, status: "booked"))
        let row = try await store.read(id: created.id)
        let appt = try JSONDecoder().decode(ModelsR4.Appointment.self, from: row.jsonData)
        XCTAssertEqual(appt.status.value?.rawValue, "booked")
    }

    func testRead_unknownId_throwsNotFound() async throws {
        do {
            _ = try await store.read(id: "no-such-appointment")
            XCTFail("Expected notFound")
        } catch FHIRServerError.notFound { }
    }

    func testUpdate_incrementsVersion() async throws {
        let patient = try await patientStore.create(makePatient(family: "ApptUpdate"))
        let created = try await store.create(makeAppointment(patientId: patient.id, status: "booked"))
        let updated = try makeAppointment(patientId: patient.id, status: "fulfilled")
        let result = try await store.update(id: created.id, appointment: updated, ifMatch: nil)
        XCTAssertEqual(result.versionId, 2)
        let row = try await store.read(id: created.id)
        let appt = try JSONDecoder().decode(ModelsR4.Appointment.self, from: row.jsonData)
        XCTAssertEqual(appt.status.value?.rawValue, "fulfilled")
    }

    func testDelete_subsequentReadThrowsGone() async throws {
        let patient = try await patientStore.create(makePatient(family: "ApptDelete"))
        let created = try await store.create(makeAppointment(patientId: patient.id))
        try await store.delete(id: created.id, ifMatch: nil)
        do {
            _ = try await store.read(id: created.id)
            XCTFail("Expected gone error")
        } catch FHIRServerError.gone { }
    }

    func testVread_returnsSpecificVersion() async throws {
        let patient = try await patientStore.create(makePatient(family: "ApptVread"))
        let created = try await store.create(makeAppointment(patientId: patient.id, status: "booked"))
        let updated = try makeAppointment(patientId: patient.id, status: "fulfilled")
        _ = try await store.update(id: created.id, appointment: updated, ifMatch: nil)
        let v1 = try await store.vread(id: created.id, versionId: 1)
        let appt = try JSONDecoder().decode(ModelsR4.Appointment.self, from: v1.jsonData)
        XCTAssertEqual(appt.status.value?.rawValue, "booked")
    }

    // ── Search: token params ──────────────────────────────────────────────────

    func testSearch_byStatus() async throws {
        let patient = try await patientStore.create(makePatient(family: "ApptStatus"))
        _ = try await store.create(makeAppointment(patientId: patient.id, status: "booked"))
        _ = try await store.create(makeAppointment(patientId: patient.id, status: "fulfilled"))

        let query = AppointmentSearchQuery(
            status: [.init(system: nil, code: "booked")], count: 10)
        let result = try await store.search(query: query)
        XCTAssertGreaterThanOrEqual(result.entries.count, 1)
        for entry in result.entries {
            let appt = try JSONDecoder().decode(ModelsR4.Appointment.self, from: entry.jsonWithMeta)
            XCTAssertEqual(appt.status.value?.rawValue, "booked")
        }
    }

    func testSearch_byStatusNot() async throws {
        let patient = try await patientStore.create(makePatient(family: "ApptStatusNot"))
        _ = try await store.create(makeAppointment(patientId: patient.id, status: "booked"))
        _ = try await store.create(makeAppointment(patientId: patient.id, status: "fulfilled"))

        let query = AppointmentSearchQuery(
            statusNot: [.init(system: nil, code: "booked")], count: 10)
        let result = try await store.search(query: query)
        for entry in result.entries {
            let appt = try JSONDecoder().decode(ModelsR4.Appointment.self, from: entry.jsonWithMeta)
            XCTAssertNotEqual(appt.status.value?.rawValue, "booked")
        }
    }

    func testSearch_byServiceType() async throws {
        let patient = try await patientStore.create(makePatient(family: "ApptSvcType"))
        _ = try await store.create(makeAppointment(patientId: patient.id, serviceTypeCode: "11429006"))
        _ = try await store.create(makeAppointment(patientId: patient.id))

        let query = AppointmentSearchQuery(
            serviceType: [.init(system: nil, code: "11429006")], count: 10)
        let result = try await store.search(query: query)
        XCTAssertEqual(result.entries.count, 1)
    }

    func testSearch_bySpecialty() async throws {
        let patient = try await patientStore.create(makePatient(family: "ApptSpecialty"))
        _ = try await store.create(makeAppointment(patientId: patient.id, specialtyCode: "394814009"))
        _ = try await store.create(makeAppointment(patientId: patient.id))

        let query = AppointmentSearchQuery(
            specialty: [.init(system: nil, code: "394814009")], count: 10)
        let result = try await store.search(query: query)
        XCTAssertEqual(result.entries.count, 1)
    }

    func testSearch_byIdentifier() async throws {
        let patient = try await patientStore.create(makePatient(family: "ApptIdent"))
        _ = try await store.create(makeAppointment(patientId: patient.id, identifier: "APPT-001"))
        _ = try await store.create(makeAppointment(patientId: patient.id))

        let query = AppointmentSearchQuery(
            identifier: [.parse("APPT-001")], count: 10)
        let result = try await store.search(query: query)
        XCTAssertEqual(result.entries.count, 1)
    }

    // ── Search: reference params ──────────────────────────────────────────────

    func testSearch_byPatient() async throws {
        let patient1 = try await patientStore.create(makePatient(family: "ApptPat1"))
        let patient2 = try await patientStore.create(makePatient(family: "ApptPat2"))
        _ = try await store.create(makeAppointment(patientId: patient1.id))
        _ = try await store.create(makeAppointment(patientId: patient2.id))

        let query = AppointmentSearchQuery(patient: "Patient/\(patient1.id)", count: 10)
        let result = try await store.search(query: query)
        XCTAssertEqual(result.entries.count, 1)
    }

    // ── Search: date params ───────────────────────────────────────────────────

    func testSearch_byDate_ge() async throws {
        let patient = try await patientStore.create(makePatient(family: "ApptDate"))
        _ = try await store.create(makeAppointment(patientId: patient.id, start: "2023-01-15T09:00:00Z"))
        _ = try await store.create(makeAppointment(patientId: patient.id, start: "2025-01-15T09:00:00Z"))

        let dp = AppointmentSearchQuery.DateParam.parse("ge2024-01-01")!
        let query = AppointmentSearchQuery(date: [dp], count: 10)
        let result = try await store.search(query: query)
        XCTAssertEqual(result.entries.count, 1)
    }

    // ── Search: _id ───────────────────────────────────────────────────────────

    func testSearch_byId() async throws {
        let patient = try await patientStore.create(makePatient(family: "ApptId"))
        let created1 = try await store.create(makeAppointment(patientId: patient.id))
        _ = try await store.create(makeAppointment(patientId: patient.id))

        let query = AppointmentSearchQuery(id: [created1.id], count: 10)
        let result = try await store.search(query: query)
        XCTAssertEqual(result.entries.count, 1)
    }

    // ── History ───────────────────────────────────────────────────────────────

    func testHistory_tracksAllVersions() async throws {
        let patient = try await patientStore.create(makePatient(family: "ApptHist"))
        let created = try await store.create(makeAppointment(patientId: patient.id, status: "booked"))
        let updated = try makeAppointment(patientId: patient.id, status: "fulfilled")
        _ = try await store.update(id: created.id, appointment: updated, ifMatch: nil)
        let entries = try await store.history(id: created.id)
        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(entries[0].versionId, 2)
        XCTAssertEqual(entries[1].versionId, 1)
    }

    func testHistory_withSince_filtersVersions() async throws {
        let patient = try await patientStore.create(makePatient(family: "ApptHistSince"))
        let created = try await store.create(makeAppointment(patientId: patient.id, status: "booked"))
        let afterCreate = Date()
        let updated = try makeAppointment(patientId: patient.id, status: "fulfilled")
        _ = try await store.update(id: created.id, appointment: updated, ifMatch: nil)
        let entries = try await store.history(id: created.id, since: afterCreate)
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].versionId, 2)
    }

    func testHistory_withCount_limitsResults() async throws {
        let patient = try await patientStore.create(makePatient(family: "ApptHistCount"))
        let created = try await store.create(makeAppointment(patientId: patient.id, status: "booked"))
        _ = try await store.update(id: created.id, appointment: makeAppointment(patientId: patient.id, status: "arrived"), ifMatch: nil)
        _ = try await store.update(id: created.id, appointment: makeAppointment(patientId: patient.id, status: "fulfilled"), ifMatch: nil)
        let entries = try await store.history(id: created.id, count: 2)
        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(entries[0].versionId, 3)
    }

    func testIfMatch_conflict_throwsVersionConflict() async throws {
        let patient = try await patientStore.create(makePatient(family: "ApptIfMatch"))
        let created = try await store.create(makeAppointment(patientId: patient.id))
        do {
            _ = try await store.update(id: created.id,
                                       appointment: makeAppointment(patientId: patient.id, status: "fulfilled"),
                                       ifMatch: 999)
            XCTFail("Expected versionConflict")
        } catch FHIRServerError.versionConflict { }
    }
}
