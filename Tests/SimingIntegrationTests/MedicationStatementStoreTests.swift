import Foundation
import ModelsR4
import XCTest
@testable import SimingCore

final class MedicationStatementStoreTests: XCTestCase {
    var store: MedicationStatementStore!

    override func setUp() async throws {
        try await super.setUp()
        try await requireDatabase()
        store = try await TestDatabase.shared.makeMedicationStatementStore()
    }

    // ── CRUD ──────────────────────────────────────────────────────────────────

    func testCreate_assignsIdAndVersionOne() async throws {
        let result = try await store.create(makeMedicationStatement(patientId: "p1"))
        XCTAssertFalse(result.id.isEmpty)
        XCTAssertEqual(result.versionId, 1)
    }

    func testRead_returnsStoredResource() async throws {
        let created = try await store.create(makeMedicationStatement(patientId: "p1", status: "active"))
        let row = try await store.read(id: created.id)
        let ms = try JSONDecoder().decode(ModelsR4.MedicationStatement.self, from: row.jsonData)
        XCTAssertEqual(ms.status.value?.rawValue, "active")
    }

    func testRead_unknownId_throwsNotFound() async throws {
        do {
            _ = try await store.read(id: "no-such-ms")
            XCTFail("Expected notFound")
        } catch FHIRServerError.notFound { }
    }

    func testUpdate_incrementsVersion() async throws {
        let created = try await store.create(makeMedicationStatement(patientId: "p1", status: "active"))
        let updated = try makeMedicationStatement(patientId: "p1", status: "completed")
        let result = try await store.update(id: created.id, medicationStatement: updated, ifMatch: nil)
        XCTAssertEqual(result.versionId, 2)
        let row = try await store.read(id: created.id)
        let ms = try JSONDecoder().decode(ModelsR4.MedicationStatement.self, from: row.jsonData)
        XCTAssertEqual(ms.status.value?.rawValue, "completed")
    }

    func testDelete_and_goneOnRead() async throws {
        let created = try await store.create(makeMedicationStatement(patientId: "p1"))
        try await store.delete(id: created.id, ifMatch: nil)
        do {
            _ = try await store.read(id: created.id)
            XCTFail("Expected gone error")
        } catch FHIRServerError.gone { }
    }

    func testVread_returnsSpecificVersion() async throws {
        let created = try await store.create(makeMedicationStatement(patientId: "p1", status: "active"))
        let updated = try makeMedicationStatement(patientId: "p1", status: "completed")
        _ = try await store.update(id: created.id, medicationStatement: updated, ifMatch: nil)
        let v1 = try await store.vread(id: created.id, versionId: 1)
        let ms = try JSONDecoder().decode(ModelsR4.MedicationStatement.self, from: v1.jsonData)
        XCTAssertEqual(ms.status.value?.rawValue, "active")
    }

    // ── Token search ──────────────────────────────────────────────────────────

    func testSearch_byStatus() async throws {
        _ = try await store.create(makeMedicationStatement(patientId: "p1", status: "active"))
        _ = try await store.create(makeMedicationStatement(patientId: "p1", status: "completed"))

        var q = MedicationStatementSearchQuery()
        q.status = [.init(system: "http://hl7.org/fhir/CodeSystem/medication-statement-status", code: "active")]
        let result = try await store.search(query: q)
        XCTAssertEqual(result.entries.count, 1)
    }

    func testSearch_byStatusNot() async throws {
        _ = try await store.create(makeMedicationStatement(patientId: "p1", status: "active"))
        _ = try await store.create(makeMedicationStatement(patientId: "p1", status: "completed"))

        var q = MedicationStatementSearchQuery()
        q.statusNot = [.init(system: nil, code: "completed")]
        let result = try await store.search(query: q)
        XCTAssertEqual(result.entries.count, 1)
    }

    func testSearch_byCategory() async throws {
        _ = try await store.create(makeMedicationStatement(patientId: "p1", category: "inpatient"))
        _ = try await store.create(makeMedicationStatement(patientId: "p1", category: "outpatient"))

        var q = MedicationStatementSearchQuery()
        q.category = [.init(system: nil, code: "inpatient")]
        let result = try await store.search(query: q)
        XCTAssertEqual(result.entries.count, 1)
    }

    func testSearch_byCategoryNot() async throws {
        _ = try await store.create(makeMedicationStatement(patientId: "p1", category: "inpatient"))
        _ = try await store.create(makeMedicationStatement(patientId: "p1", category: "outpatient"))

        var q = MedicationStatementSearchQuery()
        q.categoryNot = [.init(system: nil, code: "inpatient")]
        let result = try await store.search(query: q)
        XCTAssertEqual(result.entries.count, 1)
    }

    func testSearch_byCode() async throws {
        _ = try await store.create(makeMedicationStatement(patientId: "p1", medicationCode: "1049502"))
        _ = try await store.create(makeMedicationStatement(patientId: "p1", medicationCode: "999999"))

        var q = MedicationStatementSearchQuery()
        q.code = [.init(system: nil, code: "1049502")]
        let result = try await store.search(query: q)
        XCTAssertEqual(result.entries.count, 1)
    }

    func testSearch_byIdentifier() async throws {
        _ = try await store.create(makeMedicationStatement(patientId: "p1", identifier: "MS001"))
        _ = try await store.create(makeMedicationStatement(patientId: "p1", identifier: "MS002"))

        var q = MedicationStatementSearchQuery()
        q.identifier = [MedicationStatementSearchQuery.IdentifierParam.parse("MS001")]
        let result = try await store.search(query: q)
        XCTAssertEqual(result.entries.count, 1)
    }

    // ── Date search ───────────────────────────────────────────────────────────

    func testSearch_byEffective_greaterThan() async throws {
        _ = try await store.create(makeMedicationStatement(patientId: "p1", effectiveDateTime: "2023-01-01T00:00:00Z"))
        _ = try await store.create(makeMedicationStatement(patientId: "p1", effectiveDateTime: "2024-06-01T00:00:00Z"))

        var q = MedicationStatementSearchQuery()
        q.effective = [MedicationStatementSearchQuery.DateParam.parse("gt2024-01-01")!]
        let result = try await store.search(query: q)
        XCTAssertEqual(result.entries.count, 1)
    }

    func testSearch_byEffective_lessThan() async throws {
        _ = try await store.create(makeMedicationStatement(patientId: "p1", effectiveDateTime: "2023-01-01T00:00:00Z"))
        _ = try await store.create(makeMedicationStatement(patientId: "p1", effectiveDateTime: "2024-06-01T00:00:00Z"))

        var q = MedicationStatementSearchQuery()
        q.effective = [MedicationStatementSearchQuery.DateParam.parse("lt2024-01-01")!]
        let result = try await store.search(query: q)
        XCTAssertEqual(result.entries.count, 1)
    }

    // ── Reference search ──────────────────────────────────────────────────────

    func testSearch_bySubject() async throws {
        _ = try await store.create(makeMedicationStatement(patientId: "patA"))
        _ = try await store.create(makeMedicationStatement(patientId: "patB"))

        var q = MedicationStatementSearchQuery()
        q.subject = "Patient/patA"
        let result = try await store.search(query: q)
        XCTAssertEqual(result.entries.count, 1)
    }

    func testSearch_byPatient() async throws {
        _ = try await store.create(makeMedicationStatement(patientId: "patX"))
        _ = try await store.create(makeMedicationStatement(patientId: "patY"))

        var q = MedicationStatementSearchQuery()
        q.patient = "Patient/patX"
        let result = try await store.search(query: q)
        XCTAssertEqual(result.entries.count, 1)
    }

    // ── System params ─────────────────────────────────────────────────────────

    func testSearch_byId() async throws {
        let e1 = try await store.create(makeMedicationStatement(patientId: "p1"))
        _ = try await store.create(makeMedicationStatement(patientId: "p1"))

        var q = MedicationStatementSearchQuery()
        q.id = [e1.id]
        let result = try await store.search(query: q)
        XCTAssertEqual(result.entries.count, 1)
        XCTAssertEqual(result.entries.first?.id, e1.id)
    }

    func testSearch_totalModeNone() async throws {
        _ = try await store.create(makeMedicationStatement(patientId: "p1"))

        var q = MedicationStatementSearchQuery()
        q.totalMode = .none
        let result = try await store.search(query: q)
        XCTAssertNil(result.total)
    }

    func testSearch_totalModeAccurate() async throws {
        _ = try await store.create(makeMedicationStatement(patientId: "p1"))
        _ = try await store.create(makeMedicationStatement(patientId: "p1"))

        var q = MedicationStatementSearchQuery()
        q.totalMode = .accurate
        let result = try await store.search(query: q)
        XCTAssertGreaterThanOrEqual(result.total ?? 0, 2)
    }

    // ── History ───────────────────────────────────────────────────────────────

    func testHistory_instance() async throws {
        let created = try await store.create(makeMedicationStatement(patientId: "p1", status: "active"))
        let updated = try makeMedicationStatement(patientId: "p1", status: "completed")
        _ = try await store.update(id: created.id, medicationStatement: updated, ifMatch: nil)
        let hist = try await store.history(id: created.id)
        XCTAssertEqual(hist.count, 2)
    }

    func testTypeHistory() async throws {
        _ = try await store.create(makeMedicationStatement(patientId: "p1"))
        _ = try await store.create(makeMedicationStatement(patientId: "p2"))
        let hist = try await store.typeHistory(since: nil, count: 10)
        XCTAssertGreaterThanOrEqual(hist.count, 2)
    }

    // ── Pagination ────────────────────────────────────────────────────────────

    func testPagination_noOverlap() async throws {
        for i in 1...5 {
            _ = try await store.create(makeMedicationStatement(patientId: "pat\(i)"))
        }

        var q = MedicationStatementSearchQuery()
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

    func testSearch_missing_effective() async throws {
        _ = try await store.create(makeMedicationStatement(patientId: "p1", effectiveDateTime: "2024-01-01T00:00:00Z"))
        _ = try await store.create(makeMedicationStatement(patientId: "p1"))

        var q = MedicationStatementSearchQuery()
        q.missing = ["effective": true]
        let result = try await store.search(query: q)
        XCTAssertEqual(result.entries.count, 1)
    }
}
