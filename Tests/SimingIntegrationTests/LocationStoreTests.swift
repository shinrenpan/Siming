import Foundation
import ModelsR4
@testable import SimingCore
import XCTest

final class LocationStoreTests: XCTestCase {
    var store: LocationStore!
    var organizationStore: OrganizationStore!

    override func setUp() async throws {
        try await super.setUp()
        try await requireDatabase()
        store             = try await TestDatabase.shared.makeLocationStore()
        organizationStore = try await TestDatabase.shared.makeOrganizationStore()
    }

    // ── Create ────────────────────────────────────────────────────────────────

    func testCreate_assignsIdAndVersionOne() async throws {
        let result = try await store.create(makeLocation(name: "LocCreate"))
        XCTAssertFalse(result.id.isEmpty)
        XCTAssertEqual(result.versionId, 1)
    }

    // ── Read ──────────────────────────────────────────────────────────────────

    func testRead_returnsStoredName() async throws {
        let created = try await store.create(makeLocation(name: "ReadLoc"))
        let row = try await store.read(id: created.id)
        let loc = try JSONDecoder().decode(ModelsR4.Location.self, from: row.jsonData)
        XCTAssertEqual(loc.name?.value?.string, "ReadLoc")
    }

    func testRead_unknownId_throwsNotFound() async throws {
        do {
            _ = try await store.read(id: "no-such-location")
            XCTFail("Expected notFound")
        } catch FHIRServerError.notFound { }
    }

    // ── vread ─────────────────────────────────────────────────────────────────

    func testVread_returnsSpecificVersion() async throws {
        let created = try await store.create(makeLocation(name: "VreadV1"))
        _ = try await store.update(id: created.id,
                                   location: makeLocation(name: "VreadV2"),
                                   ifMatch: nil)
        let v1 = try await store.vread(id: created.id, versionId: 1)
        let loc = try JSONDecoder().decode(ModelsR4.Location.self, from: v1.jsonData)
        XCTAssertEqual(loc.name?.value?.string, "VreadV1")
    }

    // ── Update ────────────────────────────────────────────────────────────────

    func testUpdate_incrementsVersionId() async throws {
        let created = try await store.create(makeLocation(name: "UpdateV1"))
        let updated = try await store.update(id: created.id,
                                             location: makeLocation(name: "UpdateV2"),
                                             ifMatch: nil)
        XCTAssertEqual(updated.versionId, 2)
    }

    func testUpdate_ifMatch_wrongEtag_throwsPreconditionFailed() async throws {
        let created = try await store.create(makeLocation(name: "IfMatchLoc"))
        do {
            _ = try await store.update(id: created.id,
                                       location: makeLocation(name: "IfMatchLoc"),
                                       ifMatch: 999)
            XCTFail("Expected versionConflict")
        } catch FHIRServerError.versionConflict { }
    }

    // ── Delete ────────────────────────────────────────────────────────────────

    func testDelete_subsequentReadThrowsGone() async throws {
        let created = try await store.create(makeLocation(name: "DeleteLoc"))
        _ = try await store.delete(id: created.id, ifMatch: nil)
        do {
            _ = try await store.read(id: created.id)
            XCTFail("Expected gone")
        } catch FHIRServerError.gone { }
    }

    // ── Search: name ──────────────────────────────────────────────────────────

    func testSearch_byName_startsWith_returnsMatch() async throws {
        _ = try await store.create(makeLocation(name: "General Ward"))
        _ = try await store.create(makeLocation(name: "ICU"))

        let q = LocationSearchQuery(name: .init(value: "General", modifier: .startsWith))
        let result = try await store.search(query: q)
        XCTAssertEqual(result.total, 1)
    }

    func testSearch_byName_contains_returnsMatch() async throws {
        _ = try await store.create(makeLocation(name: "Emergency Department"))
        _ = try await store.create(makeLocation(name: "Radiology"))

        let q = LocationSearchQuery(name: .init(value: "mergency", modifier: .contains))
        let result = try await store.search(query: q)
        XCTAssertEqual(result.total, 1)
    }

    // ── Search: status ────────────────────────────────────────────────────────

    func testSearch_byStatus_returnsMatchOnly() async throws {
        _ = try await store.create(makeLocation(name: "ActiveLoc", status: "active"))
        _ = try await store.create(makeLocation(name: "SuspendedLoc", status: "suspended"))

        let q = LocationSearchQuery(status: [.init(system: nil, code: "active")])
        let result = try await store.search(query: q)
        XCTAssertEqual(result.total, 1)
        let loc = try JSONDecoder().decode(ModelsR4.Location.self, from: result.entries[0].jsonWithMeta)
        XCTAssertEqual(loc.status?.value?.rawValue, "active")
    }

    func testSearch_byStatusNot_excludesCorrectly() async throws {
        _ = try await store.create(makeLocation(name: "ActiveLocNot", status: "active"))
        _ = try await store.create(makeLocation(name: "SuspendedLocNot", status: "suspended"))

        let q = LocationSearchQuery(statusNot: [.init(system: nil, code: "active")])
        let result = try await store.search(query: q)
        XCTAssertEqual(result.total, 1)
        let loc = try JSONDecoder().decode(ModelsR4.Location.self, from: result.entries[0].jsonWithMeta)
        XCTAssertEqual(loc.status?.value?.rawValue, "suspended")
    }

    // ── Search: type ──────────────────────────────────────────────────────────

    func testSearch_byType_returnsMatchOnly() async throws {
        _ = try await store.create(makeLocation(name: "WardLoc", type: "WARD"))
        _ = try await store.create(makeLocation(name: "LabLoc", type: "LAB"))

        let q = LocationSearchQuery(type: [.init(system: nil, code: "WARD")])
        let result = try await store.search(query: q)
        XCTAssertEqual(result.total, 1)
    }

    func testSearch_byTypeNot_excludesCorrectly() async throws {
        _ = try await store.create(makeLocation(name: "WardLocNot", type: "WARD"))
        _ = try await store.create(makeLocation(name: "LabLocNot", type: "LAB"))

        let q = LocationSearchQuery(typeNot: [.init(system: nil, code: "WARD")])
        let result = try await store.search(query: q)
        XCTAssertEqual(result.total, 1)
    }

    // ── Search: address-city ──────────────────────────────────────────────────

    func testSearch_byAddressCity_returnsMatchOnly() async throws {
        _ = try await store.create(makeLocation(name: "Taipei Loc", city: "Taipei"))
        _ = try await store.create(makeLocation(name: "Kaohsiung Loc", city: "Kaohsiung"))

        let q = LocationSearchQuery(addressCity: .init(value: "Taipei", modifier: .startsWith))
        let result = try await store.search(query: q)
        XCTAssertEqual(result.total, 1)
    }

    // ── Search: organization ──────────────────────────────────────────────────

    func testSearch_byOrganization_returnsMatchOnly() async throws {
        let org = try await organizationStore.create(makeOrganization(name: "HospOrg"))
        let locJSON = #"""
        {"resourceType":"Location","name":"HospLoc","status":"active",
         "managingOrganization":{"reference":"Organization/\#(org.id)"}}
        """#
        _ = try await store.create(try JSONDecoder().decode(ModelsR4.Location.self, from: Data(locJSON.utf8)))
        _ = try await store.create(makeLocation(name: "UnrelatedLoc"))

        let q = LocationSearchQuery(organization: "Organization/\(org.id)")
        let result = try await store.search(query: q)
        XCTAssertEqual(result.total, 1)
        let loc = try JSONDecoder().decode(ModelsR4.Location.self, from: result.entries[0].jsonWithMeta)
        XCTAssertEqual(loc.name?.value?.string, "HospLoc")
    }

    // ── Search: partof ────────────────────────────────────────────────────────

    func testSearch_byPartof_returnsMatchOnly() async throws {
        let parent = try await store.create(makeLocation(name: "BuildingA"))
        let childJSON = #"""
        {"resourceType":"Location","name":"RoomA101","status":"active",
         "partOf":{"reference":"Location/\#(parent.id)"}}
        """#
        _ = try await store.create(try JSONDecoder().decode(ModelsR4.Location.self, from: Data(childJSON.utf8)))
        _ = try await store.create(makeLocation(name: "UnrelatedRoom"))

        let q = LocationSearchQuery(partof: "Location/\(parent.id)")
        let result = try await store.search(query: q)
        XCTAssertEqual(result.total, 1)
        let loc = try JSONDecoder().decode(ModelsR4.Location.self, from: result.entries[0].jsonWithMeta)
        XCTAssertEqual(loc.name?.value?.string, "RoomA101")
    }

    // ── Search: _id ───────────────────────────────────────────────────────────

    func testSearch_byId_returnsMatchOnly() async throws {
        let created = try await store.create(makeLocation(name: "IdSearchLoc"))
        _ = try await store.create(makeLocation(name: "IdSearchLoc2"))

        let q = LocationSearchQuery(id: [created.id])
        let result = try await store.search(query: q)
        XCTAssertEqual(result.total, 1)
        XCTAssertEqual(result.entries[0].id, created.id)
    }

    // ── Search: totalMode=none ────────────────────────────────────────────────

    func testSearch_totalModeNone_returnsNilTotal() async throws {
        _ = try await store.create(makeLocation(name: "TotalNoneLoc"))

        var q = LocationSearchQuery()
        q.name = .init(value: "TotalNoneLoc", modifier: .startsWith)
        q.totalMode = .none
        let result = try await store.search(query: q)
        XCTAssertNil(result.total)
    }

    // ── History ───────────────────────────────────────────────────────────────

    func testHistory_tracksAllVersions() async throws {
        let created = try await store.create(makeLocation(name: "HistV1"))
        _ = try await store.update(id: created.id,
                                   location: makeLocation(name: "HistV2"),
                                   ifMatch: nil)
        let entries = try await store.history(id: created.id)
        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(entries[0].versionId, 2)
        XCTAssertEqual(entries[1].versionId, 1)
    }

    func testTypeHistory_includesAllLocations() async throws {
        _ = try await store.create(makeLocation(name: "TypeHistLocA"))
        _ = try await store.create(makeLocation(name: "TypeHistLocB"))
        let entries = try await store.typeHistory(since: nil, count: 50)
        XCTAssertGreaterThanOrEqual(entries.count, 2)
        XCTAssertTrue(entries.allSatisfy { $0.resourceType == "Location" })
    }

    // ── Pagination ────────────────────────────────────────────────────────────

    func testSearch_pagination_returnsCorrectPage() async throws {
        for i in 0..<5 { _ = try await store.create(makeLocation(name: "PageLoc\(i)")) }

        var q = LocationSearchQuery()
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

    func testSearch_byEndpoint() async throws {
        let epId = "loc-ep-xyz"
        _ = try await store.create(makeLocation(name: "EndpointLoc", endpointId: epId))
        _ = try await store.create(makeLocation(name: "NoEndpointLoc"))

        let result = try await store.search(query: LocationSearchQuery(
            endpoint: "Endpoint/\(epId)"
        ))
        XCTAssertEqual(result.total, 1)
    }
}
