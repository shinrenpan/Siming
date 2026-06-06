import Foundation
import ModelsR4
import XCTest
@testable import SimingCore

final class FamilyMemberHistoryStoreTests: XCTestCase {
    var store: FamilyMemberHistoryStore!

    override func setUp() async throws {
        try await super.setUp()
        try await requireDatabase()
        store = try await TestDatabase.shared.makeFamilyMemberHistoryStore()
    }

    // ── CRUD ──────────────────────────────────────────────────────────────────

    func testCreate_assignsIdAndVersionOne() async throws {
        let result = try await store.create(makeFamilyMemberHistory(patientId: "p1"))
        XCTAssertFalse(result.id.isEmpty)
        XCTAssertEqual(result.versionId, 1)
    }

    func testRead_returnsStoredResource() async throws {
        let created = try await store.create(makeFamilyMemberHistory(patientId: "p1", status: "partial"))
        let row = try await store.read(id: created.id)
        let fmh = try JSONDecoder().decode(ModelsR4.FamilyMemberHistory.self, from: row.jsonData)
        XCTAssertEqual(fmh.status.value?.rawValue, "partial")
    }

    func testRead_unknownId_throwsNotFound() async throws {
        do {
            _ = try await store.read(id: "no-such-fmh")
            XCTFail("Expected notFound")
        } catch FHIRServerError.notFound { }
    }

    func testUpdate_incrementsVersion() async throws {
        let created = try await store.create(makeFamilyMemberHistory(patientId: "p1", status: "partial"))
        let updated = try makeFamilyMemberHistory(patientId: "p1", status: "completed")
        let result = try await store.update(id: created.id, familyMemberHistory: updated, ifMatch: nil)
        XCTAssertEqual(result.versionId, 2)
        let row = try await store.read(id: created.id)
        let fmh = try JSONDecoder().decode(ModelsR4.FamilyMemberHistory.self, from: row.jsonData)
        XCTAssertEqual(fmh.status.value?.rawValue, "completed")
    }

    func testDelete_and_goneOnRead() async throws {
        let created = try await store.create(makeFamilyMemberHistory(patientId: "p1"))
        try await store.delete(id: created.id, ifMatch: nil)
        do {
            _ = try await store.read(id: created.id)
            XCTFail("Expected gone error")
        } catch FHIRServerError.gone { }
    }

    func testVread_returnsSpecificVersion() async throws {
        let created = try await store.create(makeFamilyMemberHistory(patientId: "p1", status: "partial"))
        let updated = try makeFamilyMemberHistory(patientId: "p1", status: "completed")
        _ = try await store.update(id: created.id, familyMemberHistory: updated, ifMatch: nil)
        let v1 = try await store.vread(id: created.id, versionId: 1)
        let fmh = try JSONDecoder().decode(ModelsR4.FamilyMemberHistory.self, from: v1.jsonData)
        XCTAssertEqual(fmh.status.value?.rawValue, "partial")
    }

    // ── Token search ──────────────────────────────────────────────────────────

    func testSearch_byStatus() async throws {
        _ = try await store.create(makeFamilyMemberHistory(patientId: "p1", status: "partial"))
        _ = try await store.create(makeFamilyMemberHistory(patientId: "p1", status: "completed"))

        var q = FamilyMemberHistorySearchQuery()
        q.status = [.init(system: "http://hl7.org/fhir/history-status", code: "partial")]
        let result = try await store.search(query: q)
        XCTAssertEqual(result.entries.count, 1)
    }

    func testSearch_byStatusNot() async throws {
        _ = try await store.create(makeFamilyMemberHistory(patientId: "p1", status: "partial"))
        _ = try await store.create(makeFamilyMemberHistory(patientId: "p1", status: "completed"))

        var q = FamilyMemberHistorySearchQuery()
        q.statusNot = [.init(system: nil, code: "completed")]
        let result = try await store.search(query: q)
        XCTAssertEqual(result.entries.count, 1)
    }

    func testSearch_byRelationship() async throws {
        _ = try await store.create(makeFamilyMemberHistory(patientId: "p1", relationship: "FAMMEMB"))
        _ = try await store.create(makeFamilyMemberHistory(patientId: "p1", relationship: "SIS"))

        var q = FamilyMemberHistorySearchQuery()
        q.relationship = [.init(system: nil, code: "FAMMEMB")]
        let result = try await store.search(query: q)
        XCTAssertEqual(result.entries.count, 1)
    }

    func testSearch_byRelationshipNot() async throws {
        _ = try await store.create(makeFamilyMemberHistory(patientId: "p1", relationship: "FAMMEMB"))
        _ = try await store.create(makeFamilyMemberHistory(patientId: "p1", relationship: "SIS"))

        var q = FamilyMemberHistorySearchQuery()
        q.relationshipNot = [.init(system: nil, code: "FAMMEMB")]
        let result = try await store.search(query: q)
        XCTAssertEqual(result.entries.count, 1)
    }

    func testSearch_bySex() async throws {
        _ = try await store.create(makeFamilyMemberHistory(patientId: "p1", sex: "male"))
        _ = try await store.create(makeFamilyMemberHistory(patientId: "p1", sex: "female"))

        var q = FamilyMemberHistorySearchQuery()
        q.sex = [.init(system: nil, code: "male")]
        let result = try await store.search(query: q)
        XCTAssertEqual(result.entries.count, 1)
    }

    func testSearch_byCode() async throws {
        _ = try await store.create(makeFamilyMemberHistory(patientId: "p1", conditionCode: "44054006"))
        _ = try await store.create(makeFamilyMemberHistory(patientId: "p1", conditionCode: "38341003"))

        var q = FamilyMemberHistorySearchQuery()
        q.code = [.init(system: nil, code: "44054006")]
        let result = try await store.search(query: q)
        XCTAssertEqual(result.entries.count, 1)
    }

    func testSearch_byCodeNot() async throws {
        _ = try await store.create(makeFamilyMemberHistory(patientId: "p1", conditionCode: "44054006"))
        _ = try await store.create(makeFamilyMemberHistory(patientId: "p1", conditionCode: "38341003"))

        var q = FamilyMemberHistorySearchQuery()
        q.codeNot = [.init(system: nil, code: "44054006")]
        let result = try await store.search(query: q)
        XCTAssertEqual(result.entries.count, 1)
    }

    func testSearch_byIdentifier() async throws {
        _ = try await store.create(makeFamilyMemberHistory(patientId: "p1", identifier: "FMH001"))
        _ = try await store.create(makeFamilyMemberHistory(patientId: "p1", identifier: "FMH002"))

        var q = FamilyMemberHistorySearchQuery()
        q.identifier = [FamilyMemberHistorySearchQuery.IdentifierParam.parse("FMH001")]
        let result = try await store.search(query: q)
        XCTAssertEqual(result.entries.count, 1)
    }

    // ── Date search ───────────────────────────────────────────────────────────

    func testSearch_byDate_greaterThan() async throws {
        _ = try await store.create(makeFamilyMemberHistory(patientId: "p1", date: "2023-01-01T00:00:00Z"))
        _ = try await store.create(makeFamilyMemberHistory(patientId: "p1", date: "2024-06-01T00:00:00Z"))

        var q = FamilyMemberHistorySearchQuery()
        q.date = [FamilyMemberHistorySearchQuery.DateParam.parse("gt2024-01-01")!]
        let result = try await store.search(query: q)
        XCTAssertEqual(result.entries.count, 1)
    }

    func testSearch_byDate_lessThan() async throws {
        _ = try await store.create(makeFamilyMemberHistory(patientId: "p1", date: "2023-01-01T00:00:00Z"))
        _ = try await store.create(makeFamilyMemberHistory(patientId: "p1", date: "2024-06-01T00:00:00Z"))

        var q = FamilyMemberHistorySearchQuery()
        q.date = [FamilyMemberHistorySearchQuery.DateParam.parse("lt2024-01-01")!]
        let result = try await store.search(query: q)
        XCTAssertEqual(result.entries.count, 1)
    }

    // ── Reference search ──────────────────────────────────────────────────────

    func testSearch_byPatient() async throws {
        _ = try await store.create(makeFamilyMemberHistory(patientId: "patA"))
        _ = try await store.create(makeFamilyMemberHistory(patientId: "patB"))

        var q = FamilyMemberHistorySearchQuery()
        q.patient = "Patient/patA"
        let result = try await store.search(query: q)
        XCTAssertEqual(result.entries.count, 1)
    }

    // ── System params ─────────────────────────────────────────────────────────

    func testSearch_byId() async throws {
        let e1 = try await store.create(makeFamilyMemberHistory(patientId: "p1"))
        _ = try await store.create(makeFamilyMemberHistory(patientId: "p1"))

        var q = FamilyMemberHistorySearchQuery()
        q.id = [e1.id]
        let result = try await store.search(query: q)
        XCTAssertEqual(result.entries.count, 1)
        XCTAssertEqual(result.entries.first?.id, e1.id)
    }

    func testSearch_totalModeNone() async throws {
        _ = try await store.create(makeFamilyMemberHistory(patientId: "p1"))

        var q = FamilyMemberHistorySearchQuery()
        q.totalMode = .none
        let result = try await store.search(query: q)
        XCTAssertNil(result.total)
    }

    func testSearch_totalModeAccurate() async throws {
        _ = try await store.create(makeFamilyMemberHistory(patientId: "p1"))
        _ = try await store.create(makeFamilyMemberHistory(patientId: "p1"))

        var q = FamilyMemberHistorySearchQuery()
        q.totalMode = .accurate
        let result = try await store.search(query: q)
        XCTAssertGreaterThanOrEqual(result.total ?? 0, 2)
    }

    // ── History ───────────────────────────────────────────────────────────────

    func testHistory_instance() async throws {
        let created = try await store.create(makeFamilyMemberHistory(patientId: "p1", status: "partial"))
        let updated = try makeFamilyMemberHistory(patientId: "p1", status: "completed")
        _ = try await store.update(id: created.id, familyMemberHistory: updated, ifMatch: nil)
        let hist = try await store.history(id: created.id)
        XCTAssertEqual(hist.count, 2)
    }

    func testTypeHistory() async throws {
        _ = try await store.create(makeFamilyMemberHistory(patientId: "p1"))
        _ = try await store.create(makeFamilyMemberHistory(patientId: "p2"))
        let hist = try await store.typeHistory(since: nil, count: 10)
        XCTAssertGreaterThanOrEqual(hist.count, 2)
    }

    // ── Pagination ────────────────────────────────────────────────────────────

    func testPagination_noOverlap() async throws {
        for i in 1...5 {
            _ = try await store.create(makeFamilyMemberHistory(patientId: "pat\(i)"))
        }

        var q = FamilyMemberHistorySearchQuery()
        q.count = 2
        let page1 = try await store.search(query: q)
        XCTAssertEqual(page1.entries.count, 2)
        XCTAssertNotNil(page1.nextCursor)

        q.cursor = page1.nextCursor
        let page2 = try await store.search(query: q)
        XCTAssertEqual(page2.entries.count, 2)

        let ids1 = Set(page1.entries.map(\.id))
        let ids2 = Set(page2.entries.map(\.id))
        XCTAssertTrue(ids1.isDisjoint(with: ids2))
    }

    // ── Missing modifier ──────────────────────────────────────────────────────

    func testSearch_missing_date() async throws {
        _ = try await store.create(makeFamilyMemberHistory(patientId: "p1", date: "2024-01-01T00:00:00Z"))
        _ = try await store.create(makeFamilyMemberHistory(patientId: "p1"))

        var q = FamilyMemberHistorySearchQuery()
        q.missing = ["date": true]
        let result = try await store.search(query: q)
        XCTAssertEqual(result.entries.count, 1)
    }
}
