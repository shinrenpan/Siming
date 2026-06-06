import Foundation
import ModelsR4
@testable import SimingCore
import XCTest

final class PractitionerStoreTests: XCTestCase {
    var store: PractitionerStore!

    override func setUp() async throws {
        try await super.setUp()
        try await requireDatabase()
        store = try await TestDatabase.shared.makePractitionerStore()
    }

    // ── Create ────────────────────────────────────────────────────────────────

    func testCreate_assignsIdAndVersionOne() async throws {
        let result = try await store.create(makePractitioner(family: "PracCreate1"))
        XCTAssertFalse(result.id.isEmpty)
        XCTAssertEqual(result.versionId, 1)
    }

    // ── Read ──────────────────────────────────────────────────────────────────

    func testRead_returnsStoredFamily() async throws {
        let created = try await store.create(makePractitioner(family: "ReadFamily"))
        let row = try await store.read(id: created.id)
        let prac = try JSONDecoder().decode(ModelsR4.Practitioner.self, from: row.jsonData)
        XCTAssertEqual(prac.name?.first?.family?.value?.string, "ReadFamily")
    }

    func testRead_unknownId_throwsNotFound() async throws {
        do {
            _ = try await store.read(id: "no-such-practitioner")
            XCTFail("Expected notFound")
        } catch FHIRServerError.notFound { }
    }

    // ── vread ─────────────────────────────────────────────────────────────────

    func testVread_returnsSpecificVersion() async throws {
        let created = try await store.create(makePractitioner(family: "VreadV1"))
        _ = try await store.update(id: created.id,
                                   practitioner: makePractitioner(family: "VreadV2"),
                                   ifMatch: nil)
        let v1 = try await store.vread(id: created.id, versionId: 1)
        let prac = try JSONDecoder().decode(ModelsR4.Practitioner.self, from: v1.jsonData)
        XCTAssertEqual(prac.name?.first?.family?.value?.string, "VreadV1")
    }

    // ── Update ────────────────────────────────────────────────────────────────

    func testUpdate_incrementsVersionId() async throws {
        let created = try await store.create(makePractitioner(family: "UpdateV1"))
        let updated = try await store.update(id: created.id,
                                             practitioner: makePractitioner(family: "UpdateV2"),
                                             ifMatch: nil)
        XCTAssertEqual(updated.versionId, 2)
    }

    func testUpdate_ifMatch_wrongEtag_throwsPreconditionFailed() async throws {
        let created = try await store.create(makePractitioner(family: "IfMatchPrac"))
        do {
            _ = try await store.update(id: created.id,
                                       practitioner: makePractitioner(family: "IfMatchPrac"),
                                       ifMatch: 999)
            XCTFail("Expected versionConflict")
        } catch FHIRServerError.versionConflict { }
    }

    // ── Delete ────────────────────────────────────────────────────────────────

    func testDelete_subsequentReadThrowsGone() async throws {
        let created = try await store.create(makePractitioner(family: "DeletePrac"))
        _ = try await store.delete(id: created.id, ifMatch: nil)
        do {
            _ = try await store.read(id: created.id)
            XCTFail("Expected gone")
        } catch FHIRServerError.gone { }
    }

    // ── Search: name ──────────────────────────────────────────────────────────

    func testSearch_byName_startsWith_returnsMatch() async throws {
        _ = try await store.create(makePractitioner(family: "Yamamoto"))
        _ = try await store.create(makePractitioner(family: "Tanaka"))

        let q = PractitionerSearchQuery(name: .init(value: "Yama", modifier: .startsWith))
        let result = try await store.search(query: q)
        XCTAssertEqual(result.total, 1)
    }

    func testSearch_byFamily_returnsMatch() async throws {
        _ = try await store.create(makePractitioner(family: "Nakamura", given: "Hanako"))
        _ = try await store.create(makePractitioner(family: "Suzuki", given: "Taro"))

        let q = PractitionerSearchQuery(family: .init(value: "Nakamura", modifier: .startsWith))
        let result = try await store.search(query: q)
        XCTAssertEqual(result.total, 1)
    }

    func testSearch_byGiven_returnsMatch() async throws {
        _ = try await store.create(makePractitioner(family: "DocA", given: "Alice"))
        _ = try await store.create(makePractitioner(family: "DocB", given: "Bob"))

        let q = PractitionerSearchQuery(given: .init(value: "Alice", modifier: .startsWith))
        let result = try await store.search(query: q)
        XCTAssertEqual(result.total, 1)
    }

    // ── Search: gender ────────────────────────────────────────────────────────

    func testSearch_byGender_returnsMatchOnly() async throws {
        _ = try await store.create(makePractitioner(family: "GenderM", gender: "male"))
        _ = try await store.create(makePractitioner(family: "GenderF", gender: "female"))

        let q = PractitionerSearchQuery(gender: ["male"])
        let result = try await store.search(query: q)
        XCTAssertEqual(result.total, 1)
        let prac = try JSONDecoder().decode(ModelsR4.Practitioner.self,
                                            from: result.entries[0].jsonWithMeta)
        XCTAssertEqual(prac.gender?.value?.rawValue, "male")
    }

    func testSearch_byGenderNot_excludesCorrectly() async throws {
        _ = try await store.create(makePractitioner(family: "GenderNotM", gender: "male"))
        _ = try await store.create(makePractitioner(family: "GenderNotF", gender: "female"))

        let q = PractitionerSearchQuery(genderNot: ["male"])
        let result = try await store.search(query: q)
        XCTAssertEqual(result.total, 1)
        let prac = try JSONDecoder().decode(ModelsR4.Practitioner.self,
                                            from: result.entries[0].jsonWithMeta)
        XCTAssertEqual(prac.gender?.value?.rawValue, "female")
    }

    // ── Search: identifier ────────────────────────────────────────────────────

    func testSearch_byIdentifier_returnsMatch() async throws {
        _ = try await store.create(makePractitioner(family: "IdPracA", identifier: "NPI-001"))
        _ = try await store.create(makePractitioner(family: "IdPracB", identifier: "NPI-002"))

        let q = PractitionerSearchQuery(identifier: [.parse("NPI-001")])
        let result = try await store.search(query: q)
        XCTAssertEqual(result.total, 1)
    }

    // ── Search: active ────────────────────────────────────────────────────────

    func testSearch_byActive_returnsMatchOnly() async throws {
        let activeJSON = #"{"resourceType":"Practitioner","active":true,"name":[{"family":"ActivePrac"}]}"#
        let inactiveJSON = #"{"resourceType":"Practitioner","active":false,"name":[{"family":"InactivePrac"}]}"#
        _ = try await store.create(try JSONDecoder().decode(ModelsR4.Practitioner.self, from: Data(activeJSON.utf8)))
        _ = try await store.create(try JSONDecoder().decode(ModelsR4.Practitioner.self, from: Data(inactiveJSON.utf8)))

        let q = PractitionerSearchQuery(active: true)
        let result = try await store.search(query: q)
        XCTAssertEqual(result.total, 1)
    }

    // ── Search: _id ───────────────────────────────────────────────────────────

    func testSearch_byId_returnsMatchOnly() async throws {
        let created = try await store.create(makePractitioner(family: "IdSearchPrac"))
        _ = try await store.create(makePractitioner(family: "IdSearchPrac2"))

        let q = PractitionerSearchQuery(id: [created.id])
        let result = try await store.search(query: q)
        XCTAssertEqual(result.total, 1)
        XCTAssertEqual(result.entries[0].id, created.id)
    }

    // ── Search: totalMode=none ────────────────────────────────────────────────

    func testSearch_totalModeNone_returnsNilTotal() async throws {
        _ = try await store.create(makePractitioner(family: "TotalNonePrac"))

        var q = PractitionerSearchQuery()
        q.name = .init(value: "TotalNonePrac", modifier: .startsWith)
        q.totalMode = .none
        let result = try await store.search(query: q)
        XCTAssertNil(result.total)
    }

    // ── History ───────────────────────────────────────────────────────────────

    func testHistory_tracksAllVersions() async throws {
        let created = try await store.create(makePractitioner(family: "HistV1"))
        _ = try await store.update(id: created.id,
                                   practitioner: makePractitioner(family: "HistV2"),
                                   ifMatch: nil)
        let entries = try await store.history(id: created.id)
        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(entries[0].versionId, 2)
        XCTAssertEqual(entries[1].versionId, 1)
    }

    func testTypeHistory_includesAllPractitioners() async throws {
        _ = try await store.create(makePractitioner(family: "TypeHistA"))
        _ = try await store.create(makePractitioner(family: "TypeHistB"))
        let entries = try await store.typeHistory(since: nil, count: 50)
        XCTAssertGreaterThanOrEqual(entries.count, 2)
        XCTAssertTrue(entries.allSatisfy { $0.resourceType == "Practitioner" })
    }

    // ── Pagination ────────────────────────────────────────────────────────────

    func testSearch_pagination_returnsCorrectPage() async throws {
        for i in 0..<5 { _ = try await store.create(makePractitioner(family: "PagePrac\(i)")) }

        var q = PractitionerSearchQuery()
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
