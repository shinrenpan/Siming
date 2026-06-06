import Foundation
import ModelsR4
@testable import SimingCore
import XCTest

final class AllergyIntoleranceStoreTests: XCTestCase {
    var store: AllergyIntoleranceStore!
    var patientStore: PatientStore!

    override func setUp() async throws {
        try await super.setUp()
        try await requireDatabase()
        store        = try await TestDatabase.shared.makeAllergyIntoleranceStore()
        patientStore = try await TestDatabase.shared.makePatientStore()
    }

    // ── Create ────────────────────────────────────────────────────────────────

    func testCreate_assignsIdAndVersionOne() async throws {
        let pid = try await patientStore.create(makePatient(family: "AlgPt1")).id
        let result = try await store.create(makeAllergyIntolerance(patientId: pid))
        XCTAssertFalse(result.id.isEmpty)
        XCTAssertEqual(result.versionId, 1)
    }

    // ── Read ──────────────────────────────────────────────────────────────────

    func testRead_returnsStoredClinicalStatus() async throws {
        let pid = try await patientStore.create(makePatient(family: "AlgPt2")).id
        let created = try await store.create(makeAllergyIntolerance(patientId: pid, clinicalStatus: "inactive"))
        let read = try await store.read(id: created.id)
        let alg = try JSONDecoder().decode(ModelsR4.AllergyIntolerance.self, from: read.jsonData)
        XCTAssertEqual(alg.clinicalStatus?.coding?.first?.code?.value?.string, "inactive")
    }

    func testRead_unknownId_throwsNotFound() async throws {
        do {
            _ = try await store.read(id: "nonexistent-allergy")
            XCTFail("Expected notFound")
        } catch FHIRServerError.notFound { }
    }

    // ── Update ────────────────────────────────────────────────────────────────

    func testUpdate_incrementsVersionId() async throws {
        let pid = try await patientStore.create(makePatient(family: "AlgPt3")).id
        let created = try await store.create(makeAllergyIntolerance(patientId: pid, clinicalStatus: "active"))
        let updated = try await store.update(
            id: created.id,
            allergyIntolerance: makeAllergyIntolerance(patientId: pid, clinicalStatus: "resolved"),
            ifMatch: nil
        )
        XCTAssertEqual(updated.versionId, 2)
    }

    // ── Delete ────────────────────────────────────────────────────────────────

    func testDelete_subsequentReadThrowsGone() async throws {
        let pid = try await patientStore.create(makePatient(family: "AlgPt4")).id
        let created = try await store.create(makeAllergyIntolerance(patientId: pid))
        try await store.delete(id: created.id, ifMatch: nil)
        do {
            _ = try await store.read(id: created.id)
            XCTFail("Expected gone")
        } catch FHIRServerError.gone { }
    }

    // ── Search ────────────────────────────────────────────────────────────────

    func testSearch_byPatient_returnsMatchOnly() async throws {
        let pid1 = try await patientStore.create(makePatient(family: "AlgSubjA")).id
        let pid2 = try await patientStore.create(makePatient(family: "AlgSubjB")).id
        _ = try await store.create(makeAllergyIntolerance(patientId: pid1))
        _ = try await store.create(makeAllergyIntolerance(patientId: pid1))
        _ = try await store.create(makeAllergyIntolerance(patientId: pid2))

        let result = try await store.search(query: AllergyIntoleranceSearchQuery(subject: "Patient/\(pid1)"))
        XCTAssertEqual(result.total, 2)
    }

    func testSearch_byClinicalStatus_active_returnsMatchOnly() async throws {
        let pid = try await patientStore.create(makePatient(family: "AlgStatusPt")).id
        _ = try await store.create(makeAllergyIntolerance(patientId: pid, clinicalStatus: "active"))
        _ = try await store.create(makeAllergyIntolerance(patientId: pid, clinicalStatus: "resolved"))

        let result = try await store.search(query: AllergyIntoleranceSearchQuery(
            clinicalStatus: [AllergyIntoleranceSearchQuery.TokenParam(system: nil, code: "active")]
        ))
        XCTAssertEqual(result.total, 1)
    }

    func testSearch_byClinicalStatusNot_excludesCorrectly() async throws {
        let pid = try await patientStore.create(makePatient(family: "AlgStatusNotPt")).id
        _ = try await store.create(makeAllergyIntolerance(patientId: pid, clinicalStatus: "active"))
        _ = try await store.create(makeAllergyIntolerance(patientId: pid, clinicalStatus: "resolved"))

        let result = try await store.search(query: AllergyIntoleranceSearchQuery(
            clinicalStatusNot: [AllergyIntoleranceSearchQuery.TokenParam(system: nil, code: "active")]
        ))
        XCTAssertEqual(result.total, 1)
        let alg = try JSONDecoder().decode(
            ModelsR4.AllergyIntolerance.self,
            from: result.entries[0].jsonWithMeta
        )
        XCTAssertEqual(alg.clinicalStatus?.coding?.first?.code?.value?.string, "resolved")
    }

    func testSearch_byRecordedDate_ge_returnsMatchOnly() async throws {
        let pid = try await patientStore.create(makePatient(family: "AlgDatePt")).id
        _ = try await store.create(makeAllergyIntolerance(patientId: pid, recordedDate: "2019-05-10"))
        _ = try await store.create(makeAllergyIntolerance(patientId: pid, recordedDate: "2024-09-20"))

        let param = AllergyIntoleranceSearchQuery.DateParam.parse("ge2022-01-01")!
        let result = try await store.search(query: AllergyIntoleranceSearchQuery(date: [param]))
        XCTAssertEqual(result.total, 1)
    }

    // ── History ───────────────────────────────────────────────────────────────

    func testHistory_tracksAllVersions() async throws {
        let pid = try await patientStore.create(makePatient(family: "AlgHistPt")).id
        let created = try await store.create(makeAllergyIntolerance(patientId: pid, clinicalStatus: "active"))
        _ = try await store.update(
            id: created.id,
            allergyIntolerance: makeAllergyIntolerance(patientId: pid, clinicalStatus: "resolved"),
            ifMatch: nil
        )
        let entries = try await store.history(id: created.id)
        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(entries[0].versionId, 2)
        XCTAssertEqual(entries[1].versionId, 1)
    }
}
