import Foundation
import ModelsR4
@testable import SimingCore
import XCTest

final class ProcedureStoreTests: XCTestCase {
    var store: ProcedureStore!
    var patientStore: PatientStore!

    override func setUp() async throws {
        try await super.setUp()
        try await requireDatabase()
        store        = try await TestDatabase.shared.makeProcedureStore()
        patientStore = try await TestDatabase.shared.makePatientStore()
    }

    // ── Create ────────────────────────────────────────────────────────────────

    func testCreate_assignsIdAndVersionOne() async throws {
        let pid = try await patientStore.create(makePatient(family: "ProcPt1")).id
        let result = try await store.create(makeProcedure(subjectId: pid))
        XCTAssertFalse(result.id.isEmpty)
        XCTAssertEqual(result.versionId, 1)
    }

    // ── Read ──────────────────────────────────────────────────────────────────

    func testRead_returnsStoredStatus() async throws {
        let pid = try await patientStore.create(makePatient(family: "ProcPt2")).id
        let created = try await store.create(makeProcedure(subjectId: pid, status: "in-progress"))
        let read = try await store.read(id: created.id)
        let proc = try JSONDecoder().decode(ModelsR4.Procedure.self, from: read.jsonData)
        XCTAssertEqual(proc.status.value?.rawValue, "in-progress")
    }

    func testRead_unknownId_throwsNotFound() async throws {
        do {
            _ = try await store.read(id: "nonexistent-procedure")
            XCTFail("Expected notFound")
        } catch FHIRServerError.notFound { }
    }

    // ── vread ─────────────────────────────────────────────────────────────────

    func testVread_returnsSpecificVersion() async throws {
        let pid = try await patientStore.create(makePatient(family: "ProcVread")).id
        let created = try await store.create(makeProcedure(subjectId: pid, status: "in-progress"))
        _ = try await store.update(id: created.id,
                                   procedure: makeProcedure(subjectId: pid, status: "completed"),
                                   ifMatch: nil)
        let v1 = try await store.vread(id: created.id, versionId: 1)
        let proc = try JSONDecoder().decode(ModelsR4.Procedure.self, from: v1.jsonData)
        XCTAssertEqual(proc.status.value?.rawValue, "in-progress")
    }

    // ── Update ────────────────────────────────────────────────────────────────

    func testUpdate_incrementsVersionId() async throws {
        let pid = try await patientStore.create(makePatient(family: "ProcPt3")).id
        let created = try await store.create(makeProcedure(subjectId: pid, status: "in-progress"))
        let updated = try await store.update(id: created.id,
                                             procedure: makeProcedure(subjectId: pid, status: "completed"),
                                             ifMatch: nil)
        XCTAssertEqual(updated.versionId, 2)
    }

    func testUpdate_ifMatch_wrongEtag_throwsPreconditionFailed() async throws {
        let pid = try await patientStore.create(makePatient(family: "ProcIfMatch")).id
        let created = try await store.create(makeProcedure(subjectId: pid))
        do {
            _ = try await store.update(id: created.id,
                                       procedure: makeProcedure(subjectId: pid),
                                       ifMatch: 999)
            XCTFail("Expected preconditionFailed")
        } catch FHIRServerError.versionConflict { }
    }

    // ── Delete ────────────────────────────────────────────────────────────────

    func testDelete_subsequentReadThrowsGone() async throws {
        let pid = try await patientStore.create(makePatient(family: "ProcPt4")).id
        let created = try await store.create(makeProcedure(subjectId: pid))
        _ = try await store.delete(id: created.id, ifMatch: nil)
        do {
            _ = try await store.read(id: created.id)
            XCTFail("Expected gone")
        } catch FHIRServerError.gone { }
    }

    // ── Search: subject/patient ───────────────────────────────────────────────

    func testSearch_byPatient_returnsMatchOnly() async throws {
        let pid1 = try await patientStore.create(makePatient(family: "ProcSubjA")).id
        let pid2 = try await patientStore.create(makePatient(family: "ProcSubjB")).id
        _ = try await store.create(makeProcedure(subjectId: pid1))
        _ = try await store.create(makeProcedure(subjectId: pid1))
        _ = try await store.create(makeProcedure(subjectId: pid2))

        let result = try await store.search(query: ProcedureSearchQuery(subject: "Patient/\(pid1)"))
        XCTAssertEqual(result.total, 2)
    }

    // ── Search: status ────────────────────────────────────────────────────────

    func testSearch_byStatus_completed_returnsMatchOnly() async throws {
        let pid = try await patientStore.create(makePatient(family: "ProcStatusPt")).id
        _ = try await store.create(makeProcedure(subjectId: pid, status: "completed"))
        _ = try await store.create(makeProcedure(subjectId: pid, status: "in-progress"))

        let result = try await store.search(query: ProcedureSearchQuery(
            status: [ProcedureSearchQuery.TokenParam(system: nil, code: "completed")]
        ))
        XCTAssertEqual(result.total, 1)
    }

    func testSearch_byStatusNot_excludesCorrectly() async throws {
        let pid = try await patientStore.create(makePatient(family: "ProcStatusNotPt")).id
        _ = try await store.create(makeProcedure(subjectId: pid, status: "completed"))
        _ = try await store.create(makeProcedure(subjectId: pid, status: "in-progress"))

        let result = try await store.search(query: ProcedureSearchQuery(
            statusNot: [ProcedureSearchQuery.TokenParam(system: nil, code: "completed")]
        ))
        XCTAssertEqual(result.total, 1)
        let proc = try JSONDecoder().decode(ModelsR4.Procedure.self,
                                            from: result.entries[0].jsonWithMeta)
        XCTAssertEqual(proc.status.value?.rawValue, "in-progress")
    }

    // ── Search: code ──────────────────────────────────────────────────────────

    func testSearch_byCode_returnsMatchOnly() async throws {
        let pid = try await patientStore.create(makePatient(family: "ProcCodePt")).id
        _ = try await store.create(makeProcedure(subjectId: pid, code: "73761001"))
        _ = try await store.create(makeProcedure(subjectId: pid, code: "12345678"))

        let result = try await store.search(query: ProcedureSearchQuery(
            code: [ProcedureSearchQuery.TokenParam(system: nil, code: "73761001")]
        ))
        XCTAssertEqual(result.total, 1)
    }

    func testSearch_byCode_withSystem_returnsMatchOnly() async throws {
        let pid = try await patientStore.create(makePatient(family: "ProcCodeSysPt")).id
        _ = try await store.create(makeProcedure(subjectId: pid, code: "73761001",
                                                  codeSystem: "http://snomed.info/sct"))
        _ = try await store.create(makeProcedure(subjectId: pid, code: "73761001",
                                                  codeSystem: "http://other.system"))

        let result = try await store.search(query: ProcedureSearchQuery(
            code: [ProcedureSearchQuery.TokenParam(system: "http://snomed.info/sct", code: "73761001")]
        ))
        XCTAssertEqual(result.total, 1)
    }

    // ── Search: date ──────────────────────────────────────────────────────────

    func testSearch_byDate_ge_returnsMatchOnly() async throws {
        let pid = try await patientStore.create(makePatient(family: "ProcDatePt")).id
        _ = try await store.create(makeProcedure(subjectId: pid, performedDate: "2019-06-15"))
        _ = try await store.create(makeProcedure(subjectId: pid, performedDate: "2023-11-01"))

        let param = ProcedureSearchQuery.DateParam.parse("ge2022-01-01")!
        let result = try await store.search(query: ProcedureSearchQuery(date: [param]))
        XCTAssertEqual(result.total, 1)
    }

    func testSearch_byDate_lt_returnsMatchOnly() async throws {
        let pid = try await patientStore.create(makePatient(family: "ProcDateLtPt")).id
        _ = try await store.create(makeProcedure(subjectId: pid, performedDate: "2019-06-15"))
        _ = try await store.create(makeProcedure(subjectId: pid, performedDate: "2023-11-01"))

        let param = ProcedureSearchQuery.DateParam.parse("lt2022-01-01")!
        let result = try await store.search(query: ProcedureSearchQuery(date: [param]))
        XCTAssertEqual(result.total, 1)
    }

    // ── Search: _id ───────────────────────────────────────────────────────────

    func testSearch_byId_returnsMatchOnly() async throws {
        let pid = try await patientStore.create(makePatient(family: "ProcIdPt")).id
        let created = try await store.create(makeProcedure(subjectId: pid))
        _ = try await store.create(makeProcedure(subjectId: pid))

        let result = try await store.search(query: ProcedureSearchQuery(id: [created.id]))
        XCTAssertEqual(result.total, 1)
        XCTAssertEqual(result.entries[0].id, created.id)
    }

    // ── Search: totalMode=none ────────────────────────────────────────────────

    func testSearch_totalModeNone_returnsNilTotal() async throws {
        let pid = try await patientStore.create(makePatient(family: "ProcTotalNone")).id
        _ = try await store.create(makeProcedure(subjectId: pid))

        let result = try await store.search(query: ProcedureSearchQuery(
            subject: "Patient/\(pid)", totalMode: .none
        ))
        XCTAssertNil(result.total)
    }

    // ── History ───────────────────────────────────────────────────────────────

    func testHistory_tracksAllVersions() async throws {
        let pid = try await patientStore.create(makePatient(family: "ProcHistPt")).id
        let created = try await store.create(makeProcedure(subjectId: pid, status: "in-progress"))
        _ = try await store.update(id: created.id,
                                   procedure: makeProcedure(subjectId: pid, status: "completed"),
                                   ifMatch: nil)
        let entries = try await store.history(id: created.id)
        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(entries[0].versionId, 2)
        XCTAssertEqual(entries[1].versionId, 1)
    }

    func testTypeHistory_includesAllProcedures() async throws {
        let pid = try await patientStore.create(makePatient(family: "ProcTypeHist")).id
        _ = try await store.create(makeProcedure(subjectId: pid))
        _ = try await store.create(makeProcedure(subjectId: pid))
        let entries = try await store.typeHistory(since: nil, count: 50)
        XCTAssertGreaterThanOrEqual(entries.count, 2)
        XCTAssertTrue(entries.allSatisfy { $0.resourceType == "Procedure" })
    }

    // ── Pagination ────────────────────────────────────────────────────────────

    func testSearch_pagination_returnsCorrectPage() async throws {
        let pid = try await patientStore.create(makePatient(family: "ProcPagePt")).id
        for _ in 0..<5 { _ = try await store.create(makeProcedure(subjectId: pid)) }

        var q = ProcedureSearchQuery(subject: "Patient/\(pid)")
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
