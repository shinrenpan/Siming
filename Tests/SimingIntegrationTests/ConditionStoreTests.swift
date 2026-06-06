import Foundation
import ModelsR4
@testable import SimingCore
import XCTest

final class ConditionStoreTests: XCTestCase {
    var store: ConditionStore!
    var patientStore: PatientStore!

    override func setUp() async throws {
        try await super.setUp()
        try await requireDatabase()
        store        = try await TestDatabase.shared.makeConditionStore()
        patientStore = try await TestDatabase.shared.makePatientStore()
    }

    // ── Create ────────────────────────────────────────────────────────────────

    func testCreate_assignsIdAndVersionOne() async throws {
        let pid = try await patientStore.create(makePatient(family: "ConPt1")).id
        let result = try await store.create(makeCondition(subjectId: pid))
        XCTAssertFalse(result.id.isEmpty)
        XCTAssertEqual(result.versionId, 1)
    }

    // ── Read ──────────────────────────────────────────────────────────────────

    func testRead_returnsStoredClinicalStatus() async throws {
        let pid = try await patientStore.create(makePatient(family: "ConPt2")).id
        let created = try await store.create(makeCondition(subjectId: pid, clinicalStatus: "remission"))
        let read = try await store.read(id: created.id)
        let cond = try JSONDecoder().decode(ModelsR4.Condition.self, from: read.jsonData)
        let statusCode = cond.clinicalStatus?.coding?.first?.code?.value?.string
        XCTAssertEqual(statusCode, "remission")
    }

    func testRead_unknownId_throwsNotFound() async throws {
        do {
            _ = try await store.read(id: "nonexistent-condition")
            XCTFail("Expected notFound")
        } catch FHIRServerError.notFound { }
    }

    // ── Update ────────────────────────────────────────────────────────────────

    func testUpdate_incrementsVersionId() async throws {
        let pid = try await patientStore.create(makePatient(family: "ConPt3")).id
        let created = try await store.create(makeCondition(subjectId: pid, clinicalStatus: "active"))
        let updated = try await store.update(
            id: created.id,
            condition: makeCondition(subjectId: pid, clinicalStatus: "resolved"),
            ifMatch: nil
        )
        XCTAssertEqual(updated.versionId, 2)
    }

    // ── Delete ────────────────────────────────────────────────────────────────

    func testDelete_subsequentReadThrowsGone() async throws {
        let pid = try await patientStore.create(makePatient(family: "ConPt4")).id
        let created = try await store.create(makeCondition(subjectId: pid))
        try await store.delete(id: created.id, ifMatch: nil)
        do {
            _ = try await store.read(id: created.id)
            XCTFail("Expected gone")
        } catch FHIRServerError.gone { }
    }

    // ── Search ────────────────────────────────────────────────────────────────

    func testSearch_bySubject_returnsMatchOnly() async throws {
        let pid1 = try await patientStore.create(makePatient(family: "ConSubjA")).id
        let pid2 = try await patientStore.create(makePatient(family: "ConSubjB")).id
        _ = try await store.create(makeCondition(subjectId: pid1))
        _ = try await store.create(makeCondition(subjectId: pid1))
        _ = try await store.create(makeCondition(subjectId: pid2))

        let result = try await store.search(query: ConditionSearchQuery(subject: "Patient/\(pid1)"))
        XCTAssertEqual(result.total, 2)
    }

    func testSearch_byClinicalStatus_active_returnsMatchOnly() async throws {
        let pid = try await patientStore.create(makePatient(family: "ConStatusPt")).id
        _ = try await store.create(makeCondition(subjectId: pid, clinicalStatus: "active"))
        _ = try await store.create(makeCondition(subjectId: pid, clinicalStatus: "resolved"))

        let result = try await store.search(query: ConditionSearchQuery(
            clinicalStatus: [ConditionSearchQuery.TokenParam(system: nil, code: "active")]
        ))
        XCTAssertEqual(result.total, 1)
        let cond = try JSONDecoder().decode(ModelsR4.Condition.self, from: result.entries[0].jsonWithMeta)
        XCTAssertEqual(cond.clinicalStatus?.coding?.first?.code?.value?.string, "active")
    }

    func testSearch_byClinicalStatusNot_excludesCorrectly() async throws {
        let pid = try await patientStore.create(makePatient(family: "ConStatusNotPt")).id
        _ = try await store.create(makeCondition(subjectId: pid, clinicalStatus: "active"))
        _ = try await store.create(makeCondition(subjectId: pid, clinicalStatus: "resolved"))

        let result = try await store.search(query: ConditionSearchQuery(
            clinicalStatusNot: [ConditionSearchQuery.TokenParam(system: nil, code: "active")]
        ))
        XCTAssertEqual(result.total, 1)
        let cond = try JSONDecoder().decode(ModelsR4.Condition.self, from: result.entries[0].jsonWithMeta)
        XCTAssertEqual(cond.clinicalStatus?.coding?.first?.code?.value?.string, "resolved")
    }

    func testSearch_byOnsetDate_ge_returnsMatchOnly() async throws {
        let pid = try await patientStore.create(makePatient(family: "ConOnsetPt")).id
        _ = try await store.create(makeCondition(subjectId: pid, onsetDate: "2020-01-01"))
        _ = try await store.create(makeCondition(subjectId: pid, onsetDate: "2024-06-01"))

        let param = ConditionSearchQuery.DateParam.parse("ge2023-01-01")!
        let result = try await store.search(query: ConditionSearchQuery(onsetDate: [param]))
        XCTAssertEqual(result.total, 1)
    }

    // ── History ───────────────────────────────────────────────────────────────

    func testHistory_tracksAllVersions() async throws {
        let pid = try await patientStore.create(makePatient(family: "ConHistPt")).id
        let created = try await store.create(makeCondition(subjectId: pid, clinicalStatus: "active"))
        _ = try await store.update(
            id: created.id,
            condition: makeCondition(subjectId: pid, clinicalStatus: "resolved"),
            ifMatch: nil
        )
        let entries = try await store.history(id: created.id)
        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(entries[0].versionId, 2)
        XCTAssertEqual(entries[1].versionId, 1)
    }
}
