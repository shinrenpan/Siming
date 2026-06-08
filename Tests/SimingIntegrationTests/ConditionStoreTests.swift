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

    // ── Search: asserter ──────────────────────────────────────────────────────

    func testSearch_byAsserter_returnsMatchOnly() async throws {
        let pid = try await patientStore.create(makePatient(family: "ConAsserterPt")).id
        let pracId = "prac-asserter-\(UUID().uuidString.prefix(8))"
        _ = try await store.create(makeCondition(subjectId: pid, asserterId: pracId))
        _ = try await store.create(makeCondition(subjectId: pid))

        let result = try await store.search(query: ConditionSearchQuery(
            asserter: "Practitioner/\(pracId)"
        ))
        XCTAssertEqual(result.total, 1)
    }

    // ── Search: body-site ─────────────────────────────────────────────────────

    func testSearch_byBodySite_returnsMatchOnly() async throws {
        let pid = try await patientStore.create(makePatient(family: "ConBodySitePt")).id
        _ = try await store.create(makeCondition(subjectId: pid, bodySiteCode: "368209003"))
        _ = try await store.create(makeCondition(subjectId: pid))

        let result = try await store.search(query: ConditionSearchQuery(
            bodySite: [.init(system: nil, code: "368209003")]
        ))
        XCTAssertEqual(result.total, 1)
    }

    func testSearch_byBodySiteNot_excludesCorrectly() async throws {
        let pid = try await patientStore.create(makePatient(family: "ConBodySiteNotPt")).id
        _ = try await store.create(makeCondition(subjectId: pid, bodySiteCode: "368209003"))
        _ = try await store.create(makeCondition(subjectId: pid, bodySiteCode: "362508005"))

        let result = try await store.search(query: ConditionSearchQuery(
            bodySiteNot: [.init(system: nil, code: "368209003")]
        ))
        XCTAssertEqual(result.total, 1)
    }

    // ── Search: evidence ─────────────────────────────────────────────────────

    func testSearch_byEvidence_returnsMatchOnly() async throws {
        let pid = try await patientStore.create(makePatient(family: "ConEvidencePt")).id
        _ = try await store.create(makeCondition(subjectId: pid, evidenceCode: "271872005"))
        _ = try await store.create(makeCondition(subjectId: pid))

        let result = try await store.search(query: ConditionSearchQuery(
            evidence: [.init(system: nil, code: "271872005")]
        ))
        XCTAssertEqual(result.total, 1)
    }

    func testSearch_byEvidenceNot_excludesCorrectly() async throws {
        let pid = try await patientStore.create(makePatient(family: "ConEvidenceNotPt")).id
        _ = try await store.create(makeCondition(subjectId: pid, evidenceCode: "271872005"))
        _ = try await store.create(makeCondition(subjectId: pid, evidenceCode: "404684003"))

        let result = try await store.search(query: ConditionSearchQuery(
            evidenceNot: [.init(system: nil, code: "271872005")]
        ))
        XCTAssertEqual(result.total, 1)
    }

    // ── Search: evidence-detail ───────────────────────────────────────────────

    func testSearch_byEvidenceDetail_returnsMatchOnly() async throws {
        let pid = try await patientStore.create(makePatient(family: "ConEvDetPt")).id
        let drId = "dr-ev-\(UUID().uuidString.prefix(8))"
        _ = try await store.create(makeCondition(subjectId: pid, evidenceDetailId: drId))
        _ = try await store.create(makeCondition(subjectId: pid))

        let result = try await store.search(query: ConditionSearchQuery(
            evidenceDetail: "DiagnosticReport/\(drId)"
        ))
        XCTAssertEqual(result.total, 1)
    }

    // ── Search: severity ──────────────────────────────────────────────────────

    func testSearch_bySeverity_returnsMatchOnly() async throws {
        let pid = try await patientStore.create(makePatient(family: "ConSeverityPt")).id
        _ = try await store.create(makeCondition(subjectId: pid, severityCode: "24484000"))
        _ = try await store.create(makeCondition(subjectId: pid))

        let result = try await store.search(query: ConditionSearchQuery(
            severity: [.init(system: nil, code: "24484000")]
        ))
        XCTAssertEqual(result.total, 1)
    }

    // ── Search: stage ─────────────────────────────────────────────────────────

    func testSearch_byStage_returnsMatchOnly() async throws {
        let pid = try await patientStore.create(makePatient(family: "ConStagePt")).id
        _ = try await store.create(makeCondition(subjectId: pid, stageCode: "1306401001"))
        _ = try await store.create(makeCondition(subjectId: pid))

        let result = try await store.search(query: ConditionSearchQuery(
            stage: [.init(system: nil, code: "1306401001")]
        ))
        XCTAssertEqual(result.total, 1)
    }

    // ── Search: onset-info ────────────────────────────────────────────────────

    func testSearch_byOnsetInfo_returnsMatchOnly() async throws {
        let pid = try await patientStore.create(makePatient(family: "ConOnsetInfoPt")).id
        _ = try await store.create(makeCondition(subjectId: pid, onsetString: "childhood"))
        _ = try await store.create(makeCondition(subjectId: pid))

        let result = try await store.search(query: ConditionSearchQuery(onsetInfo: .init(value: "child", modifier: .startsWith)))
        XCTAssertEqual(result.total, 1)
    }

    // ── Search: abatement-string ──────────────────────────────────────────────

    func testSearch_byAbatementString_returnsMatchOnly() async throws {
        let pid = try await patientStore.create(makePatient(family: "ConAbatePt")).id
        _ = try await store.create(makeCondition(subjectId: pid, abatementString: "resolved spontaneously"))
        _ = try await store.create(makeCondition(subjectId: pid))

        let result = try await store.search(query: ConditionSearchQuery(abatementString: .init(value: "resolved", modifier: .startsWith)))
        XCTAssertEqual(result.total, 1)
    }

    // ── Search: onset-age ────────────────────────────────────────────────────

    func testSearch_byOnsetAge_lt_returnsMatchOnly() async throws {
        let pid = try await patientStore.create(makePatient(family: "ConOnsetAgePt")).id
        _ = try await store.create(makeCondition(subjectId: pid, onsetAgeValue: 40))
        _ = try await store.create(makeCondition(subjectId: pid, onsetAgeValue: 70))
        _ = try await store.create(makeCondition(subjectId: pid))

        let param = ConditionSearchQuery.QuantityParam.parse("lt50")!
        let result = try await store.search(query: ConditionSearchQuery(onsetAge: [param]))
        XCTAssertEqual(result.total, 1)
    }

    // ── Search: abatement-age ────────────────────────────────────────────────

    func testSearch_byAbatementAge_ge_returnsMatchOnly() async throws {
        let pid = try await patientStore.create(makePatient(family: "ConAbatAgePt")).id
        _ = try await store.create(makeCondition(subjectId: pid, abatementAgeValue: 75))
        _ = try await store.create(makeCondition(subjectId: pid, abatementAgeValue: 45))
        _ = try await store.create(makeCondition(subjectId: pid))

        let param = ConditionSearchQuery.QuantityParam.parse("ge70")!
        let result = try await store.search(query: ConditionSearchQuery(abatementAge: [param]))
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
