import Foundation
import ModelsR4
@testable import SimingCore
import XCTest

final class OrganizationStoreTests: XCTestCase {
    var store: OrganizationStore!

    override func setUp() async throws {
        try await super.setUp()
        try await requireDatabase()
        store = try await TestDatabase.shared.makeOrganizationStore()
    }

    // ── Create ────────────────────────────────────────────────────────────────

    func testCreate_assignsIdAndVersionOne() async throws {
        let result = try await store.create(makeOrganization(name: "OrgCreate1"))
        XCTAssertFalse(result.id.isEmpty)
        XCTAssertEqual(result.versionId, 1)
    }

    // ── Read ──────────────────────────────────────────────────────────────────

    func testRead_returnsStoredName() async throws {
        let created = try await store.create(makeOrganization(name: "ReadOrg"))
        let row = try await store.read(id: created.id)
        let org = try JSONDecoder().decode(ModelsR4.Organization.self, from: row.jsonData)
        XCTAssertEqual(org.name?.value?.string, "ReadOrg")
    }

    func testRead_unknownId_throwsNotFound() async throws {
        do {
            _ = try await store.read(id: "no-such-org")
            XCTFail("Expected notFound")
        } catch FHIRServerError.notFound { }
    }

    // ── vread ─────────────────────────────────────────────────────────────────

    func testVread_returnsSpecificVersion() async throws {
        let created = try await store.create(makeOrganization(name: "OrgV1"))
        _ = try await store.update(id: created.id,
                                   organization: makeOrganization(name: "OrgV2"),
                                   ifMatch: nil)
        let v1 = try await store.vread(id: created.id, versionId: 1)
        let org = try JSONDecoder().decode(ModelsR4.Organization.self, from: v1.jsonData)
        XCTAssertEqual(org.name?.value?.string, "OrgV1")
    }

    // ── Update ────────────────────────────────────────────────────────────────

    func testUpdate_incrementsVersionId() async throws {
        let created = try await store.create(makeOrganization(name: "UpdateOrg"))
        let updated = try await store.update(id: created.id,
                                             organization: makeOrganization(name: "UpdateOrgV2"),
                                             ifMatch: nil)
        XCTAssertEqual(updated.versionId, 2)
    }

    func testUpdate_ifMatch_wrongEtag_throwsPreconditionFailed() async throws {
        let created = try await store.create(makeOrganization(name: "IfMatchOrg"))
        do {
            _ = try await store.update(id: created.id,
                                       organization: makeOrganization(name: "IfMatchOrg"),
                                       ifMatch: 999)
            XCTFail("Expected versionConflict")
        } catch FHIRServerError.versionConflict { }
    }

    // ── Delete ────────────────────────────────────────────────────────────────

    func testDelete_subsequentReadThrowsGone() async throws {
        let created = try await store.create(makeOrganization(name: "DeleteOrg"))
        _ = try await store.delete(id: created.id, ifMatch: nil)
        do {
            _ = try await store.read(id: created.id)
            XCTFail("Expected gone")
        } catch FHIRServerError.gone { }
    }

    // ── Search: name ──────────────────────────────────────────────────────────

    func testSearch_byName_startsWith_returnsMatch() async throws {
        _ = try await store.create(makeOrganization(name: "General Hospital"))
        _ = try await store.create(makeOrganization(name: "City Clinic"))

        let q = OrganizationSearchQuery(name: .init(value: "General", modifier: .startsWith))
        let result = try await store.search(query: q)
        XCTAssertEqual(result.total, 1)
    }

    func testSearch_byName_contains_returnsMatch() async throws {
        _ = try await store.create(makeOrganization(name: "St. Mary Medical Center"))
        _ = try await store.create(makeOrganization(name: "Community Clinic"))

        let q = OrganizationSearchQuery(name: .init(value: "Medical", modifier: .contains))
        let result = try await store.search(query: q)
        XCTAssertEqual(result.total, 1)
    }

    // ── Search: type ──────────────────────────────────────────────────────────

    func testSearch_byType_returnsMatchOnly() async throws {
        _ = try await store.create(makeOrganization(name: "TypeHosp", type: "hosp"))
        _ = try await store.create(makeOrganization(name: "TypeProv", type: "prov"))

        let q = OrganizationSearchQuery(type: [.init(system: nil, code: "hosp")])
        let result = try await store.search(query: q)
        XCTAssertEqual(result.total, 1)
    }

    func testSearch_byTypeNot_excludesCorrectly() async throws {
        _ = try await store.create(makeOrganization(name: "TypeNotHosp", type: "hosp"))
        _ = try await store.create(makeOrganization(name: "TypeNotProv", type: "prov"))

        let q = OrganizationSearchQuery(typeNot: [.init(system: nil, code: "hosp")])
        let result = try await store.search(query: q)
        XCTAssertEqual(result.total, 1)
        let org = try JSONDecoder().decode(ModelsR4.Organization.self,
                                           from: result.entries[0].jsonWithMeta)
        let code = org.type?.first?.coding?.first?.code?.value?.string
        XCTAssertEqual(code, "prov")
    }

    // ── Search: identifier ────────────────────────────────────────────────────

    func testSearch_byIdentifier_returnsMatch() async throws {
        _ = try await store.create(makeOrganization(name: "OrgIdA", identifier: "ORG-001"))
        _ = try await store.create(makeOrganization(name: "OrgIdB", identifier: "ORG-002"))

        let q = OrganizationSearchQuery(identifier: [.init(system: nil, code: "ORG-001")])
        let result = try await store.search(query: q)
        XCTAssertEqual(result.total, 1)
    }

    // ── Search: active ────────────────────────────────────────────────────────

    func testSearch_byActive_returnsMatchOnly() async throws {
        _ = try await store.create(makeOrganization(name: "ActiveOrg", active: true))
        _ = try await store.create(makeOrganization(name: "InactiveOrg", active: false))

        let q = OrganizationSearchQuery(active: true)
        let result = try await store.search(query: q)
        XCTAssertEqual(result.total, 1)
        let org = try JSONDecoder().decode(ModelsR4.Organization.self,
                                           from: result.entries[0].jsonWithMeta)
        XCTAssertEqual(org.active?.value?.bool, true)
    }

    // ── Search: partof ────────────────────────────────────────────────────────

    func testSearch_byPartof_returnsMatchOnly() async throws {
        let parent = try await store.create(makeOrganization(name: "ParentOrg"))
        let childJSON = #"""
        {"resourceType":"Organization","name":"ChildOrg",
         "partOf":{"reference":"Organization/\#(parent.id)"}}
        """#
        _ = try await store.create(try JSONDecoder().decode(ModelsR4.Organization.self,
                                                            from: Data(childJSON.utf8)))
        _ = try await store.create(makeOrganization(name: "UnrelatedOrg"))

        let q = OrganizationSearchQuery(partof: "Organization/\(parent.id)")
        let result = try await store.search(query: q)
        XCTAssertEqual(result.total, 1)
        let org = try JSONDecoder().decode(ModelsR4.Organization.self,
                                           from: result.entries[0].jsonWithMeta)
        XCTAssertEqual(org.name?.value?.string, "ChildOrg")
    }

    // ── Search: _id ───────────────────────────────────────────────────────────

    func testSearch_byId_returnsMatchOnly() async throws {
        let created = try await store.create(makeOrganization(name: "IdSearchOrg"))
        _ = try await store.create(makeOrganization(name: "IdSearchOrg2"))

        let q = OrganizationSearchQuery(id: [created.id])
        let result = try await store.search(query: q)
        XCTAssertEqual(result.total, 1)
        XCTAssertEqual(result.entries[0].id, created.id)
    }

    // ── Search: totalMode=none ────────────────────────────────────────────────

    func testSearch_totalModeNone_returnsNilTotal() async throws {
        _ = try await store.create(makeOrganization(name: "TotalNoneOrg"))

        var q = OrganizationSearchQuery()
        q.name = .init(value: "TotalNoneOrg", modifier: .startsWith)
        q.totalMode = .none
        let result = try await store.search(query: q)
        XCTAssertNil(result.total)
    }

    // ── History ───────────────────────────────────────────────────────────────

    func testHistory_tracksAllVersions() async throws {
        let created = try await store.create(makeOrganization(name: "OrgHistV1"))
        _ = try await store.update(id: created.id,
                                   organization: makeOrganization(name: "OrgHistV2"),
                                   ifMatch: nil)
        let entries = try await store.history(id: created.id)
        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(entries[0].versionId, 2)
        XCTAssertEqual(entries[1].versionId, 1)
    }

    func testTypeHistory_includesAllOrganizations() async throws {
        _ = try await store.create(makeOrganization(name: "TypeHistOrgA"))
        _ = try await store.create(makeOrganization(name: "TypeHistOrgB"))
        let entries = try await store.typeHistory(since: nil, count: 50)
        XCTAssertGreaterThanOrEqual(entries.count, 2)
        XCTAssertTrue(entries.allSatisfy { $0.resourceType == "Organization" })
    }

    // ── Pagination ────────────────────────────────────────────────────────────

    func testSearch_pagination_returnsCorrectPage() async throws {
        for i in 0..<5 { _ = try await store.create(makeOrganization(name: "PageOrg\(i)")) }

        var q = OrganizationSearchQuery()
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
