import Foundation
import ModelsR4
@testable import SimingCore
import XCTest

final class DiagnosticReportStoreTests: XCTestCase {
    var store: DiagnosticReportStore!
    var patientStore: PatientStore!

    override func setUp() async throws {
        try await super.setUp()
        try await requireDatabase()
        store        = try await TestDatabase.shared.makeDiagnosticReportStore()
        patientStore = try await TestDatabase.shared.makePatientStore()
    }

    // ── Create ────────────────────────────────────────────────────────────────

    func testCreate_assignsIdAndVersionOne() async throws {
        let pid = try await patientStore.create(makePatient(family: "DrPt1")).id
        let result = try await store.create(makeDiagnosticReport(subjectId: pid))
        XCTAssertFalse(result.id.isEmpty)
        XCTAssertEqual(result.versionId, 1)
    }

    // ── Read ──────────────────────────────────────────────────────────────────

    func testRead_returnsStoredStatus() async throws {
        let pid = try await patientStore.create(makePatient(family: "DrPt2")).id
        let created = try await store.create(makeDiagnosticReport(subjectId: pid, status: "preliminary"))
        let read = try await store.read(id: created.id)
        let dr = try JSONDecoder().decode(ModelsR4.DiagnosticReport.self, from: read.jsonData)
        XCTAssertEqual(dr.status.value?.rawValue, "preliminary")
    }

    func testRead_unknownId_throwsNotFound() async throws {
        do {
            _ = try await store.read(id: "nonexistent-dr")
            XCTFail("Expected notFound")
        } catch FHIRServerError.notFound { }
    }

    // ── vread ─────────────────────────────────────────────────────────────────

    func testVread_returnsSpecificVersion() async throws {
        let pid = try await patientStore.create(makePatient(family: "DrVread")).id
        let created = try await store.create(makeDiagnosticReport(subjectId: pid, status: "preliminary"))
        _ = try await store.update(id: created.id,
                                   diagnosticReport: makeDiagnosticReport(subjectId: pid, status: "final"),
                                   ifMatch: nil)
        let v1 = try await store.vread(id: created.id, versionId: 1)
        let dr = try JSONDecoder().decode(ModelsR4.DiagnosticReport.self, from: v1.jsonData)
        XCTAssertEqual(dr.status.value?.rawValue, "preliminary")
    }

    // ── Update ────────────────────────────────────────────────────────────────

    func testUpdate_incrementsVersionId() async throws {
        let pid = try await patientStore.create(makePatient(family: "DrPt3")).id
        let created = try await store.create(makeDiagnosticReport(subjectId: pid, status: "preliminary"))
        let updated = try await store.update(id: created.id,
                                             diagnosticReport: makeDiagnosticReport(subjectId: pid, status: "final"),
                                             ifMatch: nil)
        XCTAssertEqual(updated.versionId, 2)
    }

    func testUpdate_ifMatch_wrongEtag_throwsPreconditionFailed() async throws {
        let pid = try await patientStore.create(makePatient(family: "DrIfMatch")).id
        let created = try await store.create(makeDiagnosticReport(subjectId: pid))
        do {
            _ = try await store.update(id: created.id,
                                       diagnosticReport: makeDiagnosticReport(subjectId: pid),
                                       ifMatch: 999)
            XCTFail("Expected preconditionFailed")
        } catch FHIRServerError.versionConflict { }
    }

    // ── Delete ────────────────────────────────────────────────────────────────

    func testDelete_subsequentReadThrowsGone() async throws {
        let pid = try await patientStore.create(makePatient(family: "DrPt4")).id
        let created = try await store.create(makeDiagnosticReport(subjectId: pid))
        _ = try await store.delete(id: created.id, ifMatch: nil)
        do {
            _ = try await store.read(id: created.id)
            XCTFail("Expected gone")
        } catch FHIRServerError.gone { }
    }

    // ── Search: subject/patient ───────────────────────────────────────────────

    func testSearch_byPatient_returnsMatchOnly() async throws {
        let pid1 = try await patientStore.create(makePatient(family: "DrSubjA")).id
        let pid2 = try await patientStore.create(makePatient(family: "DrSubjB")).id
        _ = try await store.create(makeDiagnosticReport(subjectId: pid1))
        _ = try await store.create(makeDiagnosticReport(subjectId: pid1))
        _ = try await store.create(makeDiagnosticReport(subjectId: pid2))

        let result = try await store.search(query: DiagnosticReportSearchQuery(subject: "Patient/\(pid1)"))
        XCTAssertEqual(result.total, 2)
    }

    // ── Search: status ────────────────────────────────────────────────────────

    func testSearch_byStatus_final_returnsMatchOnly() async throws {
        let pid = try await patientStore.create(makePatient(family: "DrStatusPt")).id
        _ = try await store.create(makeDiagnosticReport(subjectId: pid, status: "final"))
        _ = try await store.create(makeDiagnosticReport(subjectId: pid, status: "preliminary"))

        let result = try await store.search(query: DiagnosticReportSearchQuery(
            status: [DiagnosticReportSearchQuery.TokenParam(system: nil, code: "final")]
        ))
        XCTAssertEqual(result.total, 1)
    }

    func testSearch_byStatusNot_excludesCorrectly() async throws {
        let pid = try await patientStore.create(makePatient(family: "DrStatusNotPt")).id
        _ = try await store.create(makeDiagnosticReport(subjectId: pid, status: "final"))
        _ = try await store.create(makeDiagnosticReport(subjectId: pid, status: "preliminary"))

        let result = try await store.search(query: DiagnosticReportSearchQuery(
            statusNot: [DiagnosticReportSearchQuery.TokenParam(system: nil, code: "final")]
        ))
        XCTAssertEqual(result.total, 1)
        let dr = try JSONDecoder().decode(ModelsR4.DiagnosticReport.self,
                                          from: result.entries[0].jsonWithMeta)
        XCTAssertEqual(dr.status.value?.rawValue, "preliminary")
    }

    // ── Search: code ──────────────────────────────────────────────────────────

    func testSearch_byCode_returnsMatchOnly() async throws {
        let pid = try await patientStore.create(makePatient(family: "DrCodePt")).id
        _ = try await store.create(makeDiagnosticReport(subjectId: pid, code: "58410-2"))
        _ = try await store.create(makeDiagnosticReport(subjectId: pid, code: "2093-3"))

        let result = try await store.search(query: DiagnosticReportSearchQuery(
            code: [DiagnosticReportSearchQuery.TokenParam(system: nil, code: "58410-2")]
        ))
        XCTAssertEqual(result.total, 1)
    }

    // ── Search: date (effective) ──────────────────────────────────────────────

    func testSearch_byDate_ge_returnsMatchOnly() async throws {
        let pid = try await patientStore.create(makePatient(family: "DrDatePt")).id
        _ = try await store.create(makeDiagnosticReport(subjectId: pid, effectiveDate: "2020-03-10"))
        _ = try await store.create(makeDiagnosticReport(subjectId: pid, effectiveDate: "2024-08-22"))

        let param = DiagnosticReportSearchQuery.DateParam.parse("ge2023-01-01")!
        let result = try await store.search(query: DiagnosticReportSearchQuery(date: [param]))
        XCTAssertEqual(result.total, 1)
    }

    // ── Search: issued ────────────────────────────────────────────────────────

    func testSearch_byIssued_ge_returnsMatchOnly() async throws {
        let pid = try await patientStore.create(makePatient(family: "DrIssuedPt")).id
        _ = try await store.create(makeDiagnosticReport(subjectId: pid,
                                                         issued: "2020-06-01T10:00:00Z"))
        _ = try await store.create(makeDiagnosticReport(subjectId: pid,
                                                         issued: "2024-09-15T14:30:00Z"))

        let param = DiagnosticReportSearchQuery.DateParam.parse("ge2023-01-01")!
        let result = try await store.search(query: DiagnosticReportSearchQuery(issued: [param]))
        XCTAssertEqual(result.total, 1)
    }

    // ── Search: _id ───────────────────────────────────────────────────────────

    func testSearch_byId_returnsMatchOnly() async throws {
        let pid = try await patientStore.create(makePatient(family: "DrIdPt")).id
        let created = try await store.create(makeDiagnosticReport(subjectId: pid))
        _ = try await store.create(makeDiagnosticReport(subjectId: pid))

        let result = try await store.search(query: DiagnosticReportSearchQuery(id: [created.id]))
        XCTAssertEqual(result.total, 1)
        XCTAssertEqual(result.entries[0].id, created.id)
    }

    // ── History ───────────────────────────────────────────────────────────────

    func testHistory_tracksAllVersions() async throws {
        let pid = try await patientStore.create(makePatient(family: "DrHistPt")).id
        let created = try await store.create(makeDiagnosticReport(subjectId: pid, status: "preliminary"))
        _ = try await store.update(id: created.id,
                                   diagnosticReport: makeDiagnosticReport(subjectId: pid, status: "final"),
                                   ifMatch: nil)
        let entries = try await store.history(id: created.id)
        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(entries[0].versionId, 2)
        XCTAssertEqual(entries[1].versionId, 1)
    }

    func testTypeHistory_includesAllDiagnosticReports() async throws {
        let pid = try await patientStore.create(makePatient(family: "DrTypeHist")).id
        _ = try await store.create(makeDiagnosticReport(subjectId: pid))
        _ = try await store.create(makeDiagnosticReport(subjectId: pid))
        let entries = try await store.typeHistory(since: nil, count: 50)
        XCTAssertGreaterThanOrEqual(entries.count, 2)
        XCTAssertTrue(entries.allSatisfy { $0.resourceType == "DiagnosticReport" })
    }

    // ── Pagination ────────────────────────────────────────────────────────────

    func testSearch_pagination_returnsCorrectPage() async throws {
        let pid = try await patientStore.create(makePatient(family: "DrPagePt")).id
        for _ in 0..<5 { _ = try await store.create(makeDiagnosticReport(subjectId: pid)) }

        var q = DiagnosticReportSearchQuery(subject: "Patient/\(pid)")
        q.count = 2
        let page1 = try await store.search(query: q)
        XCTAssertEqual(page1.entries.count, 2)
        XCTAssertEqual(page1.total, 5)
        XCTAssertNotNil(page1.nextCursor)

        q.cursor = page1.nextCursor
        let page2 = try await store.search(query: q)
        XCTAssertGreaterThan(page2.entries.count, 0)
        let page1Ids = Set(page1.entries.map(\.id))
        let page2Ids = Set(page2.entries.map(\.id))
        XCTAssertTrue(page1Ids.isDisjoint(with: page2Ids))
    }
}
