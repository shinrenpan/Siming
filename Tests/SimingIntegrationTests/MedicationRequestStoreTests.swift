import Foundation
import ModelsR4
@testable import SimingCore
import XCTest

final class MedicationRequestStoreTests: XCTestCase {
    var store: MedicationRequestStore!
    var patientStore: PatientStore!

    override func setUp() async throws {
        try await super.setUp()
        try await requireDatabase()
        store        = try await TestDatabase.shared.makeMedicationRequestStore()
        patientStore = try await TestDatabase.shared.makePatientStore()
    }

    // ── Create ────────────────────────────────────────────────────────────────

    func testCreate_assignsIdAndVersionOne() async throws {
        let pid = try await patientStore.create(makePatient(family: "MedPt1")).id
        let result = try await store.create(makeMedicationRequest(subjectId: pid))
        XCTAssertFalse(result.id.isEmpty)
        XCTAssertEqual(result.versionId, 1)
    }

    // ── Read ──────────────────────────────────────────────────────────────────

    func testRead_returnsStoredStatus() async throws {
        let pid = try await patientStore.create(makePatient(family: "MedPt2")).id
        let created = try await store.create(makeMedicationRequest(subjectId: pid, status: "completed"))
        let read = try await store.read(id: created.id)
        let med = try JSONDecoder().decode(ModelsR4.MedicationRequest.self, from: read.jsonData)
        XCTAssertEqual(med.status.value?.rawValue, "completed")
    }

    func testRead_unknownId_throwsNotFound() async throws {
        do {
            _ = try await store.read(id: "nonexistent-medrx")
            XCTFail("Expected notFound")
        } catch FHIRServerError.notFound { }
    }

    // ── Update ────────────────────────────────────────────────────────────────

    func testUpdate_incrementsVersionId() async throws {
        let pid = try await patientStore.create(makePatient(family: "MedPt3")).id
        let created = try await store.create(makeMedicationRequest(subjectId: pid, status: "active"))
        let updated = try await store.update(
            id: created.id,
            medicationRequest: makeMedicationRequest(subjectId: pid, status: "completed"),
            ifMatch: nil
        )
        XCTAssertEqual(updated.versionId, 2)
    }

    // ── Delete ────────────────────────────────────────────────────────────────

    func testDelete_subsequentReadThrowsGone() async throws {
        let pid = try await patientStore.create(makePatient(family: "MedPt4")).id
        let created = try await store.create(makeMedicationRequest(subjectId: pid))
        try await store.delete(id: created.id, ifMatch: nil)
        do {
            _ = try await store.read(id: created.id)
            XCTFail("Expected gone")
        } catch FHIRServerError.gone { }
    }

    // ── Search ────────────────────────────────────────────────────────────────

    func testSearch_bySubject_returnsMatchOnly() async throws {
        let pid1 = try await patientStore.create(makePatient(family: "MedSubjA")).id
        let pid2 = try await patientStore.create(makePatient(family: "MedSubjB")).id
        _ = try await store.create(makeMedicationRequest(subjectId: pid1))
        _ = try await store.create(makeMedicationRequest(subjectId: pid1))
        _ = try await store.create(makeMedicationRequest(subjectId: pid2))

        let result = try await store.search(query: MedicationRequestSearchQuery(subject: "Patient/\(pid1)"))
        XCTAssertEqual(result.total, 2)
    }

    func testSearch_byStatus_active_returnsMatchOnly() async throws {
        let pid = try await patientStore.create(makePatient(family: "MedStatusPt")).id
        _ = try await store.create(makeMedicationRequest(subjectId: pid, status: "active"))
        _ = try await store.create(makeMedicationRequest(subjectId: pid, status: "completed"))

        let result = try await store.search(query: MedicationRequestSearchQuery(
            status: [MedicationRequestSearchQuery.TokenParam(system: nil, code: "active")]
        ))
        XCTAssertEqual(result.total, 1)
    }

    func testSearch_byIntent_order_returnsMatchOnly() async throws {
        let pid = try await patientStore.create(makePatient(family: "MedIntentPt")).id
        _ = try await store.create(makeMedicationRequest(subjectId: pid, intent: "order"))
        _ = try await store.create(makeMedicationRequest(subjectId: pid, intent: "plan"))

        let result = try await store.search(query: MedicationRequestSearchQuery(
            intent: [MedicationRequestSearchQuery.TokenParam(system: nil, code: "order")]
        ))
        XCTAssertEqual(result.total, 1)
    }

    func testSearch_byAuthoredOn_ge_returnsMatchOnly() async throws {
        let pid = try await patientStore.create(makePatient(family: "MedDatePt")).id
        _ = try await store.create(makeMedicationRequest(subjectId: pid, authoredOn: "2020-03-15"))
        _ = try await store.create(makeMedicationRequest(subjectId: pid, authoredOn: "2024-11-01"))

        let param = MedicationRequestSearchQuery.DateParam.parse("ge2023-01-01")!
        let result = try await store.search(query: MedicationRequestSearchQuery(authoredOn: [param]))
        XCTAssertEqual(result.total, 1)
    }

    // ── Search: intended-dispenser ────────────────────────────────────────────

    func testSearch_byIntendedDispenser_returnsMatchOnly() async throws {
        let pid = try await patientStore.create(makePatient(family: "MedDispPt")).id
        let orgId = "org-disp-\(UUID().uuidString.prefix(8))"
        _ = try await store.create(makeMedicationRequest(subjectId: pid, intendedDispenserId: orgId))
        _ = try await store.create(makeMedicationRequest(subjectId: pid))

        let result = try await store.search(query: MedicationRequestSearchQuery(
            intendedDispenser: "Organization/\(orgId)"
        ))
        XCTAssertEqual(result.total, 1)
    }

    // ── Search: intended-performer ────────────────────────────────────────────

    func testSearch_byIntendedPerformer_returnsMatchOnly() async throws {
        let pid = try await patientStore.create(makePatient(family: "MedPerfPt")).id
        let pracId = "prac-perf-\(UUID().uuidString.prefix(8))"
        _ = try await store.create(makeMedicationRequest(subjectId: pid, intendedPerformerId: pracId))
        _ = try await store.create(makeMedicationRequest(subjectId: pid))

        let result = try await store.search(query: MedicationRequestSearchQuery(
            intendedPerformer: "Practitioner/\(pracId)"
        ))
        XCTAssertEqual(result.total, 1)
    }

    // ── Search: intended-performertype ────────────────────────────────────────

    func testSearch_byIntendedPerformerType_returnsMatchOnly() async throws {
        let pid = try await patientStore.create(makePatient(family: "MedPerfTypePt")).id
        _ = try await store.create(makeMedicationRequest(subjectId: pid, intendedPerformerTypeCode: "310158004"))
        _ = try await store.create(makeMedicationRequest(subjectId: pid))

        let result = try await store.search(query: MedicationRequestSearchQuery(
            intendedPerformerType: [.init(system: nil, code: "310158004")]
        ))
        XCTAssertEqual(result.total, 1)
    }

    func testSearch_byIntendedPerformerTypeNot_excludesCorrectly() async throws {
        let pid = try await patientStore.create(makePatient(family: "MedPerfTypeNotPt")).id
        _ = try await store.create(makeMedicationRequest(subjectId: pid, intendedPerformerTypeCode: "310158004"))
        _ = try await store.create(makeMedicationRequest(subjectId: pid, intendedPerformerTypeCode: "46255001"))

        let result = try await store.search(query: MedicationRequestSearchQuery(
            intendedPerformerTypeNot: [.init(system: nil, code: "310158004")]
        ))
        XCTAssertEqual(result.total, 1)
    }

    // ── Search: medication (as reference) ─────────────────────────────────────

    func testSearch_byMedicationReference_returnsMatchOnly() async throws {
        let pid = try await patientStore.create(makePatient(family: "MedRefPt")).id
        let medId = "med-\(UUID().uuidString.prefix(8))"
        _ = try await store.create(makeMedicationRequest(subjectId: pid, medicationReferenceId: medId))
        _ = try await store.create(makeMedicationRequest(subjectId: pid))

        let result = try await store.search(query: MedicationRequestSearchQuery(
            medication: "Medication/\(medId)"
        ))
        XCTAssertEqual(result.total, 1)
    }

    // ── Search: date (dosage timing event) ───────────────────────────────────

    func testSearch_byDate_ge_returnsMatchOnly() async throws {
        let pid = try await patientStore.create(makePatient(family: "MedDatePt")).id
        _ = try await store.create(makeMedicationRequest(subjectId: pid, dosageTimingEvent: "2024-06-01"))
        _ = try await store.create(makeMedicationRequest(subjectId: pid, dosageTimingEvent: "2022-01-01"))
        _ = try await store.create(makeMedicationRequest(subjectId: pid))

        let param = MedicationRequestSearchQuery.DateParam.parse("ge2023-01-01")!
        let result = try await store.search(query: MedicationRequestSearchQuery(date: [param]))
        XCTAssertEqual(result.total, 1)
    }

    // ── History ───────────────────────────────────────────────────────────────

    func testHistory_tracksAllVersions() async throws {
        let pid = try await patientStore.create(makePatient(family: "MedHistPt")).id
        let created = try await store.create(makeMedicationRequest(subjectId: pid, status: "active"))
        _ = try await store.update(
            id: created.id,
            medicationRequest: makeMedicationRequest(subjectId: pid, status: "completed"),
            ifMatch: nil
        )
        let entries = try await store.history(id: created.id)
        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(entries[0].versionId, 2)
        XCTAssertEqual(entries[1].versionId, 1)
    }
}
