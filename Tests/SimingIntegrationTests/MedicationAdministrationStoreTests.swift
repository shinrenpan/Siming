import Foundation
import ModelsR4
@testable import SimingCore
import XCTest

final class MedicationAdministrationStoreTests: XCTestCase {
    var store: MedicationAdministrationStore!
    var patientStore: PatientStore!

    override func setUp() async throws {
        try await super.setUp()
        try await requireDatabase()
        store        = try await TestDatabase.shared.makeMedicationAdministrationStore()
        patientStore = try await TestDatabase.shared.makePatientStore()
    }

    // ── CRUD ──────────────────────────────────────────────────────────────────

    func testCreate_assignsIdAndVersionOne() async throws {
        let patient = try await patientStore.create(makePatient(family: "MACreate"))
        let ma = try makeMedicationAdministration(patientId: patient.id)
        let result = try await store.create(ma)
        XCTAssertFalse(result.id.isEmpty)
        XCTAssertEqual(result.versionId, 1)
    }

    func testRead_returnsStoredResource() async throws {
        let patient = try await patientStore.create(makePatient(family: "MARead"))
        let created = try await store.create(makeMedicationAdministration(patientId: patient.id, status: "completed"))
        let row = try await store.read(id: created.id)
        let ma = try JSONDecoder().decode(ModelsR4.MedicationAdministration.self, from: row.jsonData)
        XCTAssertEqual(ma.status.value?.rawValue, "completed")
    }

    func testRead_unknownId_throwsNotFound() async throws {
        do {
            _ = try await store.read(id: "no-such-med-admin")
            XCTFail("Expected notFound")
        } catch FHIRServerError.notFound { }
    }

    func testUpdate_incrementsVersion() async throws {
        let patient = try await patientStore.create(makePatient(family: "MAUpdate"))
        let created = try await store.create(makeMedicationAdministration(patientId: patient.id, status: "in-progress"))
        let updated = try makeMedicationAdministration(patientId: patient.id, status: "completed")
        let result = try await store.update(id: created.id, medicationAdministration: updated, ifMatch: nil)
        XCTAssertEqual(result.versionId, 2)
        let row = try await store.read(id: created.id)
        let ma = try JSONDecoder().decode(ModelsR4.MedicationAdministration.self, from: row.jsonData)
        XCTAssertEqual(ma.status.value?.rawValue, "completed")
    }

    func testDelete_subsequentReadThrowsGone() async throws {
        let patient = try await patientStore.create(makePatient(family: "MADelete"))
        let created = try await store.create(makeMedicationAdministration(patientId: patient.id))
        try await store.delete(id: created.id, ifMatch: nil)
        do {
            _ = try await store.read(id: created.id)
            XCTFail("Expected gone error")
        } catch FHIRServerError.gone { }
    }

    func testVread_returnsSpecificVersion() async throws {
        let patient = try await patientStore.create(makePatient(family: "MAVread"))
        let created = try await store.create(makeMedicationAdministration(patientId: patient.id, status: "in-progress"))
        let updated = try makeMedicationAdministration(patientId: patient.id, status: "completed")
        _ = try await store.update(id: created.id, medicationAdministration: updated, ifMatch: nil)
        let v1 = try await store.vread(id: created.id, versionId: 1)
        let ma = try JSONDecoder().decode(ModelsR4.MedicationAdministration.self, from: v1.jsonData)
        XCTAssertEqual(ma.status.value?.rawValue, "in-progress")
    }

    // ── Search: token params ──────────────────────────────────────────────────

    func testSearch_byStatus() async throws {
        let patient = try await patientStore.create(makePatient(family: "MAStatus"))
        _ = try await store.create(makeMedicationAdministration(patientId: patient.id, status: "completed"))
        _ = try await store.create(makeMedicationAdministration(patientId: patient.id, status: "in-progress"))

        let query = MedicationAdministrationSearchQuery(
            status: [.init(system: nil, code: "completed")], count: 10)
        let result = try await store.search(query: query)
        XCTAssertGreaterThanOrEqual(result.entries.count, 1)
        for entry in result.entries {
            let ma = try JSONDecoder().decode(ModelsR4.MedicationAdministration.self, from: entry.jsonWithMeta)
            XCTAssertEqual(ma.status.value?.rawValue, "completed")
        }
    }

    func testSearch_byStatusNot() async throws {
        let patient = try await patientStore.create(makePatient(family: "MAStatusNot"))
        _ = try await store.create(makeMedicationAdministration(patientId: patient.id, status: "completed"))
        _ = try await store.create(makeMedicationAdministration(patientId: patient.id, status: "in-progress"))

        let query = MedicationAdministrationSearchQuery(
            statusNot: [.init(system: nil, code: "completed")], count: 10)
        let result = try await store.search(query: query)
        for entry in result.entries {
            let ma = try JSONDecoder().decode(ModelsR4.MedicationAdministration.self, from: entry.jsonWithMeta)
            XCTAssertNotEqual(ma.status.value?.rawValue, "completed")
        }
    }

    func testSearch_byCode() async throws {
        let patient = try await patientStore.create(makePatient(family: "MACode"))
        _ = try await store.create(makeMedicationAdministration(patientId: patient.id, medicationCode: "1049502"))
        _ = try await store.create(makeMedicationAdministration(patientId: patient.id, medicationCode: "1049999"))

        let query = MedicationAdministrationSearchQuery(
            code: [.init(system: nil, code: "1049502")], count: 10)
        let result = try await store.search(query: query)
        XCTAssertEqual(result.entries.count, 1)
    }

    func testSearch_byIdentifier() async throws {
        let patient = try await patientStore.create(makePatient(family: "MAIdent"))
        _ = try await store.create(makeMedicationAdministration(patientId: patient.id, identifier: "MA-001"))
        _ = try await store.create(makeMedicationAdministration(patientId: patient.id))

        let query = MedicationAdministrationSearchQuery(
            identifier: [.parse("MA-001")], count: 10)
        let result = try await store.search(query: query)
        XCTAssertEqual(result.entries.count, 1)
    }

    func testSearch_byReasonGiven() async throws {
        let patient = try await patientStore.create(makePatient(family: "MAReasonGiven"))
        _ = try await store.create(makeMedicationAdministration(patientId: patient.id, reasonGivenCode: "182992009"))
        _ = try await store.create(makeMedicationAdministration(patientId: patient.id))

        let query = MedicationAdministrationSearchQuery(
            reasonGiven: [.init(system: nil, code: "182992009")], count: 10)
        let result = try await store.search(query: query)
        XCTAssertEqual(result.entries.count, 1)
    }

    // ── Search: reference params ──────────────────────────────────────────────

    func testSearch_byPatient() async throws {
        let patient1 = try await patientStore.create(makePatient(family: "MAPat1"))
        let patient2 = try await patientStore.create(makePatient(family: "MAPat2"))
        _ = try await store.create(makeMedicationAdministration(patientId: patient1.id))
        _ = try await store.create(makeMedicationAdministration(patientId: patient2.id))

        let query = MedicationAdministrationSearchQuery(patient: "Patient/\(patient1.id)", count: 10)
        let result = try await store.search(query: query)
        XCTAssertEqual(result.entries.count, 1)
    }

    func testSearch_bySubject() async throws {
        let patient1 = try await patientStore.create(makePatient(family: "MASubj1"))
        let patient2 = try await patientStore.create(makePatient(family: "MASubj2"))
        _ = try await store.create(makeMedicationAdministration(patientId: patient1.id))
        _ = try await store.create(makeMedicationAdministration(patientId: patient2.id))

        let query = MedicationAdministrationSearchQuery(subject: "Patient/\(patient1.id)", count: 10)
        let result = try await store.search(query: query)
        XCTAssertEqual(result.entries.count, 1)
    }

    func testSearch_byRequest() async throws {
        let patient = try await patientStore.create(makePatient(family: "MARequest"))
        let reqId = "mr-test-123"
        _ = try await store.create(makeMedicationAdministration(patientId: patient.id, requestId: reqId))
        _ = try await store.create(makeMedicationAdministration(patientId: patient.id))

        let query = MedicationAdministrationSearchQuery(request: "MedicationRequest/\(reqId)", count: 10)
        let result = try await store.search(query: query)
        XCTAssertEqual(result.entries.count, 1)
    }

    // ── Search: date params ───────────────────────────────────────────────────

    func testSearch_byEffectiveTime_ge() async throws {
        let patient = try await patientStore.create(makePatient(family: "MADate"))
        _ = try await store.create(makeMedicationAdministration(patientId: patient.id, effectiveDateTime: "2023-01-15T09:00:00Z"))
        _ = try await store.create(makeMedicationAdministration(patientId: patient.id, effectiveDateTime: "2025-01-15T09:00:00Z"))

        let dp = MedicationAdministrationSearchQuery.DateParam.parse("ge2024-01-01")!
        let query = MedicationAdministrationSearchQuery(effectiveTime: [dp], count: 10)
        let result = try await store.search(query: query)
        XCTAssertEqual(result.entries.count, 1)
    }

    // ── Search: _id ───────────────────────────────────────────────────────────

    func testSearch_byId() async throws {
        let patient = try await patientStore.create(makePatient(family: "MASearchId"))
        let created1 = try await store.create(makeMedicationAdministration(patientId: patient.id))
        _ = try await store.create(makeMedicationAdministration(patientId: patient.id))

        let query = MedicationAdministrationSearchQuery(id: [created1.id], count: 10)
        let result = try await store.search(query: query)
        XCTAssertEqual(result.entries.count, 1)
    }

    // ── History ───────────────────────────────────────────────────────────────

    func testHistory_tracksAllVersions() async throws {
        let patient = try await patientStore.create(makePatient(family: "MAHist"))
        let created = try await store.create(makeMedicationAdministration(patientId: patient.id, status: "in-progress"))
        let updated = try makeMedicationAdministration(patientId: patient.id, status: "completed")
        _ = try await store.update(id: created.id, medicationAdministration: updated, ifMatch: nil)
        let entries = try await store.history(id: created.id)
        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(entries[0].versionId, 2)
        XCTAssertEqual(entries[1].versionId, 1)
    }

    func testHistory_withSince_filtersVersions() async throws {
        let patient = try await patientStore.create(makePatient(family: "MAHistSince"))
        let created = try await store.create(makeMedicationAdministration(patientId: patient.id, status: "in-progress"))
        let afterCreate = Date()
        let updated = try makeMedicationAdministration(patientId: patient.id, status: "completed")
        _ = try await store.update(id: created.id, medicationAdministration: updated, ifMatch: nil)
        let entries = try await store.history(id: created.id, since: afterCreate)
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].versionId, 2)
    }

    func testHistory_withCount_limitsResults() async throws {
        let patient = try await patientStore.create(makePatient(family: "MAHistCount"))
        let created = try await store.create(makeMedicationAdministration(patientId: patient.id, status: "in-progress"))
        _ = try await store.update(id: created.id, medicationAdministration: makeMedicationAdministration(patientId: patient.id, status: "on-hold"), ifMatch: nil)
        _ = try await store.update(id: created.id, medicationAdministration: makeMedicationAdministration(patientId: patient.id, status: "completed"), ifMatch: nil)
        let entries = try await store.history(id: created.id, count: 2)
        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(entries[0].versionId, 3)
    }

    func testIfMatch_conflict_throwsVersionConflict() async throws {
        let patient = try await patientStore.create(makePatient(family: "MAIfMatch"))
        let created = try await store.create(makeMedicationAdministration(patientId: patient.id))
        do {
            _ = try await store.update(id: created.id,
                                       medicationAdministration: makeMedicationAdministration(patientId: patient.id, status: "completed"),
                                       ifMatch: 999)
            XCTFail("Expected versionConflict")
        } catch FHIRServerError.versionConflict { }
    }
}
