import Foundation
import ModelsR4
@testable import SimingCore
import XCTest

final class MedicationStoreTests: XCTestCase {
    var store: MedicationStore!

    override func setUp() async throws {
        try await super.setUp()
        try await requireDatabase()
        store = try await TestDatabase.shared.makeMedicationStore()
    }

    // ── Create ────────────────────────────────────────────────────────────────

    func testCreate_assignsIdAndVersionOne() async throws {
        let result = try await store.create(makeMedication())
        XCTAssertFalse(result.id.isEmpty)
        XCTAssertEqual(result.versionId, 1)
    }

    // ── Read ──────────────────────────────────────────────────────────────────

    func testRead_returnsStoredCode() async throws {
        let created = try await store.create(makeMedication(code: "READ-001"))
        let row = try await store.read(id: created.id)
        let med = try JSONDecoder().decode(ModelsR4.Medication.self, from: row.jsonData)
        XCTAssertEqual(med.code?.coding?.first?.code?.value?.string, "READ-001")
    }

    func testRead_unknownId_throwsNotFound() async throws {
        do {
            _ = try await store.read(id: "no-such-medication")
            XCTFail("Expected notFound")
        } catch FHIRServerError.notFound { }
    }

    // ── vread ─────────────────────────────────────────────────────────────────

    func testVread_returnsSpecificVersion() async throws {
        let created = try await store.create(makeMedication(code: "VREAD-V1"))
        _ = try await store.update(id: created.id,
                                   medication: makeMedication(code: "VREAD-V2"),
                                   ifMatch: nil)
        let v1 = try await store.vread(id: created.id, versionId: 1)
        let med = try JSONDecoder().decode(ModelsR4.Medication.self, from: v1.jsonData)
        XCTAssertEqual(med.code?.coding?.first?.code?.value?.string, "VREAD-V1")
    }

    // ── Update ────────────────────────────────────────────────────────────────

    func testUpdate_incrementsVersionId() async throws {
        let created = try await store.create(makeMedication())
        let updated = try await store.update(id: created.id,
                                             medication: makeMedication(status: "inactive"),
                                             ifMatch: nil)
        XCTAssertEqual(updated.versionId, 2)
    }

    func testUpdate_ifMatch_wrongEtag_throwsPreconditionFailed() async throws {
        let created = try await store.create(makeMedication())
        do {
            _ = try await store.update(id: created.id,
                                       medication: makeMedication(),
                                       ifMatch: 999)
            XCTFail("Expected versionConflict")
        } catch FHIRServerError.versionConflict { }
    }

    // ── Delete ────────────────────────────────────────────────────────────────

    func testDelete_subsequentReadThrowsGone() async throws {
        let created = try await store.create(makeMedication())
        _ = try await store.delete(id: created.id, ifMatch: nil)
        do {
            _ = try await store.read(id: created.id)
            XCTFail("Expected gone")
        } catch FHIRServerError.gone { }
    }

    // ── Search: code ──────────────────────────────────────────────────────────

    func testSearch_byCode_returnsMatchOnly() async throws {
        _ = try await store.create(makeMedication(code: "1049502"))
        _ = try await store.create(makeMedication(code: "7980"))

        let q = MedicationSearchQuery(code: [.init(system: nil, code: "1049502")])
        let result = try await store.search(query: q)
        XCTAssertEqual(result.total, 1)
    }

    func testSearch_byCodeNot_excludesCorrectly() async throws {
        _ = try await store.create(makeMedication(code: "CODE-A"))
        _ = try await store.create(makeMedication(code: "CODE-B"))

        let q = MedicationSearchQuery(codeNot: [.init(system: nil, code: "CODE-A")])
        let result = try await store.search(query: q)
        XCTAssertEqual(result.total, 1)
        let med = try JSONDecoder().decode(ModelsR4.Medication.self, from: result.entries[0].jsonWithMeta)
        XCTAssertEqual(med.code?.coding?.first?.code?.value?.string, "CODE-B")
    }

    // ── Search: status ────────────────────────────────────────────────────────

    func testSearch_byStatus_returnsMatchOnly() async throws {
        _ = try await store.create(makeMedication(status: "active"))
        _ = try await store.create(makeMedication(status: "inactive"))

        let q = MedicationSearchQuery(status: [.init(system: nil, code: "active")])
        let result = try await store.search(query: q)
        XCTAssertEqual(result.total, 1)
        let med = try JSONDecoder().decode(ModelsR4.Medication.self, from: result.entries[0].jsonWithMeta)
        XCTAssertEqual(med.status?.value?.rawValue, "active")
    }

    func testSearch_byStatusNot_excludesCorrectly() async throws {
        _ = try await store.create(makeMedication(status: "active"))
        _ = try await store.create(makeMedication(status: "inactive"))

        let q = MedicationSearchQuery(statusNot: [.init(system: nil, code: "active")])
        let result = try await store.search(query: q)
        XCTAssertEqual(result.total, 1)
        let med = try JSONDecoder().decode(ModelsR4.Medication.self, from: result.entries[0].jsonWithMeta)
        XCTAssertEqual(med.status?.value?.rawValue, "inactive")
    }

    // ── Search: lot-number ────────────────────────────────────────────────────

    func testSearch_byLotNumber_returnsMatchOnly() async throws {
        _ = try await store.create(makeMedication(lotNumber: "LOT-123"))
        _ = try await store.create(makeMedication(lotNumber: "LOT-456"))

        let q = MedicationSearchQuery(lotNumber: [.init(system: nil, code: "LOT-123")])
        let result = try await store.search(query: q)
        XCTAssertEqual(result.total, 1)
    }

    // ── Search: expiration-date ───────────────────────────────────────────────

    func testSearch_byExpirationDate_ge_returnsMatchOnly() async throws {
        _ = try await store.create(makeMedication(expirationDate: "2028-01-01"))
        _ = try await store.create(makeMedication(expirationDate: "2024-01-01"))

        let dp = MedicationSearchQuery.DateParam.parse("ge2027-01-01")!
        let q  = MedicationSearchQuery(expirationDate: [dp])
        let result = try await store.search(query: q)
        XCTAssertEqual(result.total, 1)
    }

    // ── Search: identifier ────────────────────────────────────────────────────

    func testSearch_byIdentifier_returnsMatch() async throws {
        let medJSON = #"""
        {"resourceType":"Medication","status":"active",
         "code":{"coding":[{"system":"http://example.org","code":"MED-ID-A"}]},
         "identifier":[{"system":"http://example.org/med","value":"MED-ID-A"}]}
        """#
        _ = try await store.create(try JSONDecoder().decode(ModelsR4.Medication.self, from: Data(medJSON.utf8)))
        _ = try await store.create(makeMedication())

        let q = MedicationSearchQuery(identifier: [.parse("MED-ID-A")])
        let result = try await store.search(query: q)
        XCTAssertEqual(result.total, 1)
    }

    // ── Search: _id ───────────────────────────────────────────────────────────

    func testSearch_byId_returnsMatchOnly() async throws {
        let created = try await store.create(makeMedication())
        _ = try await store.create(makeMedication())

        let q = MedicationSearchQuery(id: [created.id])
        let result = try await store.search(query: q)
        XCTAssertEqual(result.total, 1)
        XCTAssertEqual(result.entries[0].id, created.id)
    }

    // ── Search: totalMode=none ────────────────────────────────────────────────

    func testSearch_totalModeNone_returnsNilTotal() async throws {
        _ = try await store.create(makeMedication(status: "active"))

        var q = MedicationSearchQuery()
        q.status = [.init(system: nil, code: "active")]
        q.totalMode = .none
        let result = try await store.search(query: q)
        XCTAssertNil(result.total)
    }

    // ── History ───────────────────────────────────────────────────────────────

    func testHistory_tracksAllVersions() async throws {
        let created = try await store.create(makeMedication(status: "active"))
        _ = try await store.update(id: created.id,
                                   medication: makeMedication(status: "inactive"),
                                   ifMatch: nil)
        let entries = try await store.history(id: created.id)
        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(entries[0].versionId, 2)
        XCTAssertEqual(entries[1].versionId, 1)
    }

    func testTypeHistory_includesAllMedications() async throws {
        _ = try await store.create(makeMedication(code: "TypeHistA"))
        _ = try await store.create(makeMedication(code: "TypeHistB"))
        let entries = try await store.typeHistory(since: nil, count: 50)
        XCTAssertGreaterThanOrEqual(entries.count, 2)
        XCTAssertTrue(entries.allSatisfy { $0.resourceType == "Medication" })
    }

    // ── Pagination ────────────────────────────────────────────────────────────

    func testSearch_pagination_returnsCorrectPage() async throws {
        for i in 0..<5 { _ = try await store.create(makeMedication(code: "PAGE-\(i)")) }

        var q = MedicationSearchQuery()
        q.count = 2
        let page1 = try await store.search(query: q)
        XCTAssertEqual(page1.entries.count, 2)
        XCTAssertNotNil(page1.nextCursor)

        q.cursor = page1.nextCursor
        let page2 = try await store.search(query: q)
        XCTAssertGreaterThan(page2.entries.count, 0)
        let page1Ids = Set(page1.entries.map(\.id))
        let page2Ids = Set(page2.entries.map(\.id))
        XCTAssertTrue(page1Ids.isDisjoint(with: page2Ids))
    }
}
