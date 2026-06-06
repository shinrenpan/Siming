import Foundation
import ModelsR4
import XCTest
@testable import SimingCore

final class GoalStoreTests: XCTestCase {
    var store: GoalStore!

    override func setUp() async throws {
        try await super.setUp()
        try await requireDatabase()
        store = try await TestDatabase.shared.makeGoalStore()
    }

    // ── CRUD ──────────────────────────────────────────────────────────────────

    func testCreate_assignsIdAndVersionOne() async throws {
        let result = try await store.create(makeGoal(patientId: "p1"))
        XCTAssertFalse(result.id.isEmpty)
        XCTAssertEqual(result.versionId, 1)
    }

    func testRead_returnsStoredResource() async throws {
        let created = try await store.create(makeGoal(patientId: "p1", lifecycleStatus: "active"))
        let row = try await store.read(id: created.id)
        let goal = try JSONDecoder().decode(ModelsR4.Goal.self, from: row.jsonData)
        XCTAssertEqual(goal.lifecycleStatus.value?.rawValue, "active")
    }

    func testRead_unknownId_throwsNotFound() async throws {
        do {
            _ = try await store.read(id: "no-such-goal")
            XCTFail("Expected notFound")
        } catch FHIRServerError.notFound { }
    }

    func testUpdate_incrementsVersion() async throws {
        let created = try await store.create(makeGoal(patientId: "p1", lifecycleStatus: "active"))
        let updated = try makeGoal(patientId: "p1", lifecycleStatus: "completed")
        let result = try await store.update(id: created.id, goal: updated, ifMatch: nil)
        XCTAssertEqual(result.versionId, 2)
        let row = try await store.read(id: created.id)
        let goal = try JSONDecoder().decode(ModelsR4.Goal.self, from: row.jsonData)
        XCTAssertEqual(goal.lifecycleStatus.value?.rawValue, "completed")
    }

    func testDelete_and_goneOnRead() async throws {
        let created = try await store.create(makeGoal(patientId: "p1"))
        try await store.delete(id: created.id, ifMatch: nil)
        do {
            _ = try await store.read(id: created.id)
            XCTFail("Expected gone error")
        } catch FHIRServerError.gone { }
    }

    func testVread_returnsSpecificVersion() async throws {
        let created = try await store.create(makeGoal(patientId: "p1", lifecycleStatus: "active"))
        let updated = try makeGoal(patientId: "p1", lifecycleStatus: "completed")
        _ = try await store.update(id: created.id, goal: updated, ifMatch: nil)
        let v1 = try await store.vread(id: created.id, versionId: 1)
        let goal = try JSONDecoder().decode(ModelsR4.Goal.self, from: v1.jsonData)
        XCTAssertEqual(goal.lifecycleStatus.value?.rawValue, "active")
    }

    // ── Token search ──────────────────────────────────────────────────────────

    func testSearch_byLifecycleStatus() async throws {
        _ = try await store.create(makeGoal(patientId: "p1", lifecycleStatus: "active"))
        _ = try await store.create(makeGoal(patientId: "p1", lifecycleStatus: "completed"))

        var q = GoalSearchQuery()
        q.lifecycleStatus = [.init(system: "http://hl7.org/fhir/goal-status", code: "active")]
        let result = try await store.search(query: q)
        XCTAssertEqual(result.entries.count, 1)
    }

    func testSearch_byLifecycleStatusNot() async throws {
        _ = try await store.create(makeGoal(patientId: "p1", lifecycleStatus: "active"))
        _ = try await store.create(makeGoal(patientId: "p1", lifecycleStatus: "completed"))

        var q = GoalSearchQuery()
        q.lifecycleStatusNot = [.init(system: nil, code: "completed")]
        let result = try await store.search(query: q)
        XCTAssertEqual(result.entries.count, 1)
    }

    func testSearch_byCategory() async throws {
        _ = try await store.create(makeGoal(patientId: "p1", category: "dietary"))
        _ = try await store.create(makeGoal(patientId: "p1", category: "exercise"))

        var q = GoalSearchQuery()
        q.category = [.init(system: nil, code: "dietary")]
        let result = try await store.search(query: q)
        XCTAssertEqual(result.entries.count, 1)
    }

    func testSearch_byCategoryNot() async throws {
        _ = try await store.create(makeGoal(patientId: "p1", category: "dietary"))
        _ = try await store.create(makeGoal(patientId: "p1", category: "exercise"))

        var q = GoalSearchQuery()
        q.categoryNot = [.init(system: nil, code: "dietary")]
        let result = try await store.search(query: q)
        XCTAssertEqual(result.entries.count, 1)
    }

    func testSearch_byIdentifier() async throws {
        _ = try await store.create(makeGoal(patientId: "p1", identifier: "G001"))
        _ = try await store.create(makeGoal(patientId: "p1", identifier: "G002"))

        var q = GoalSearchQuery()
        q.identifier = [GoalSearchQuery.IdentifierParam.parse("G001")]
        let result = try await store.search(query: q)
        XCTAssertEqual(result.entries.count, 1)
    }

    // ── Date search ───────────────────────────────────────────────────────────

    func testSearch_byStartDate_greaterThan() async throws {
        _ = try await store.create(makeGoal(patientId: "p1", startDate: "2023-01-01"))
        _ = try await store.create(makeGoal(patientId: "p1", startDate: "2024-06-01"))

        var q = GoalSearchQuery()
        q.startDate = [GoalSearchQuery.DateParam.parse("gt2024-01-01")!]
        let result = try await store.search(query: q)
        XCTAssertEqual(result.entries.count, 1)
    }

    func testSearch_byTargetDate_lessThan() async throws {
        _ = try await store.create(makeGoal(patientId: "p1", targetDate: "2023-12-31"))
        _ = try await store.create(makeGoal(patientId: "p1", targetDate: "2025-12-31"))

        var q = GoalSearchQuery()
        q.targetDate = [GoalSearchQuery.DateParam.parse("lt2024-01-01")!]
        let result = try await store.search(query: q)
        XCTAssertEqual(result.entries.count, 1)
    }

    // ── Reference search ──────────────────────────────────────────────────────

    func testSearch_bySubject() async throws {
        _ = try await store.create(makeGoal(patientId: "patA"))
        _ = try await store.create(makeGoal(patientId: "patB"))

        var q = GoalSearchQuery()
        q.subject = "Patient/patA"
        let result = try await store.search(query: q)
        XCTAssertEqual(result.entries.count, 1)
    }

    func testSearch_byPatient() async throws {
        _ = try await store.create(makeGoal(patientId: "patX"))
        _ = try await store.create(makeGoal(patientId: "patY"))

        var q = GoalSearchQuery()
        q.patient = "Patient/patX"
        let result = try await store.search(query: q)
        XCTAssertEqual(result.entries.count, 1)
    }

    // ── System params ─────────────────────────────────────────────────────────

    func testSearch_byId() async throws {
        let e1 = try await store.create(makeGoal(patientId: "p1"))
        _ = try await store.create(makeGoal(patientId: "p1"))

        var q = GoalSearchQuery()
        q.id = [e1.id]
        let result = try await store.search(query: q)
        XCTAssertEqual(result.entries.count, 1)
        XCTAssertEqual(result.entries.first?.id, e1.id)
    }

    func testSearch_totalModeNone() async throws {
        _ = try await store.create(makeGoal(patientId: "p1"))

        var q = GoalSearchQuery()
        q.totalMode = .none
        let result = try await store.search(query: q)
        XCTAssertNil(result.total)
    }

    func testSearch_totalModeAccurate() async throws {
        _ = try await store.create(makeGoal(patientId: "p1"))
        _ = try await store.create(makeGoal(patientId: "p1"))

        var q = GoalSearchQuery()
        q.totalMode = .accurate
        let result = try await store.search(query: q)
        XCTAssertGreaterThanOrEqual(result.total ?? 0, 2)
    }

    // ── History ───────────────────────────────────────────────────────────────

    func testHistory_instance() async throws {
        let created = try await store.create(makeGoal(patientId: "p1"))
        let updated = try makeGoal(patientId: "p1", lifecycleStatus: "completed")
        _ = try await store.update(id: created.id, goal: updated, ifMatch: nil)
        let hist = try await store.history(id: created.id)
        XCTAssertEqual(hist.count, 2)
    }

    func testTypeHistory() async throws {
        _ = try await store.create(makeGoal(patientId: "p1"))
        _ = try await store.create(makeGoal(patientId: "p2"))
        let hist = try await store.typeHistory(since: nil, count: 10)
        XCTAssertGreaterThanOrEqual(hist.count, 2)
    }

    // ── Pagination ────────────────────────────────────────────────────────────

    func testPagination_noOverlap() async throws {
        for i in 1...5 {
            _ = try await store.create(makeGoal(patientId: "pat\(i)"))
        }

        var q = GoalSearchQuery()
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

    func testSearch_missing_startDate() async throws {
        _ = try await store.create(makeGoal(patientId: "p1", startDate: "2024-01-01"))
        _ = try await store.create(makeGoal(patientId: "p1"))

        var q = GoalSearchQuery()
        q.missing = ["start-date": true]
        let result = try await store.search(query: q)
        XCTAssertEqual(result.entries.count, 1)
    }
}
