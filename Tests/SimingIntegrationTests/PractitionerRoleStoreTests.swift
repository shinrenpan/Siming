import Foundation
import ModelsR4
@testable import SimingCore
import XCTest

final class PractitionerRoleStoreTests: XCTestCase {
    var store: PractitionerRoleStore!
    var practitionerStore: PractitionerStore!

    override func setUp() async throws {
        try await super.setUp()
        try await requireDatabase()
        store = try await TestDatabase.shared.makePractitionerRoleStore()
        practitionerStore = try await TestDatabase.shared.makePractitionerStore()
    }

    // ── Create ────────────────────────────────────────────────────────────────

    func testCreate_assignsIdAndVersionOne() async throws {
        let prac = try await practitionerStore.create(makePractitioner(family: "RoleCreate1"))
        let result = try await store.create(makePractitionerRole(practitionerId: prac.id))
        XCTAssertFalse(result.id.isEmpty)
        XCTAssertEqual(result.versionId, 1)
    }

    // ── Read ──────────────────────────────────────────────────────────────────

    func testRead_returnsRoleDisplay() async throws {
        let prac = try await practitionerStore.create(makePractitioner(family: "RoleRead"))
        let created = try await store.create(
            makePractitionerRole(practitionerId: prac.id, roleDisplay: "主治醫師"))
        let row = try await store.read(id: created.id)
        let role = try JSONDecoder().decode(ModelsR4.PractitionerRole.self, from: row.jsonData)
        XCTAssertEqual(role.code?.first?.coding?.first?.display?.value?.string, "主治醫師")
        XCTAssertEqual(role.practitioner?.reference?.value?.string, "Practitioner/\(prac.id)")
    }

    func testRead_unknownId_throwsNotFound() async throws {
        do {
            _ = try await store.read(id: "no-such-practitioner-role")
            XCTFail("Expected notFound")
        } catch FHIRServerError.notFound { }
    }

    // ── vread ─────────────────────────────────────────────────────────────────

    func testVread_returnsSpecificVersion() async throws {
        let prac = try await practitionerStore.create(makePractitioner(family: "RoleVread"))
        let created = try await store.create(
            makePractitionerRole(practitionerId: prac.id, roleDisplay: "住院醫師"))
        _ = try await store.update(id: created.id,
                                   role: makePractitionerRole(practitionerId: prac.id, roleDisplay: "主治醫師"),
                                   ifMatch: nil)
        let v1 = try await store.vread(id: created.id, versionId: 1)
        let role = try JSONDecoder().decode(ModelsR4.PractitionerRole.self, from: v1.jsonData)
        XCTAssertEqual(role.code?.first?.coding?.first?.display?.value?.string, "住院醫師")
    }

    // ── Update ────────────────────────────────────────────────────────────────

    func testUpdate_incrementsVersionId() async throws {
        let prac = try await practitionerStore.create(makePractitioner(family: "RoleUpdate"))
        let created = try await store.create(makePractitionerRole(practitionerId: prac.id))
        let updated = try await store.update(id: created.id,
                                             role: makePractitionerRole(practitionerId: prac.id),
                                             ifMatch: nil)
        XCTAssertEqual(updated.versionId, 2)
    }

    func testUpdate_ifMatch_wrongEtag_throwsPreconditionFailed() async throws {
        let prac = try await practitionerStore.create(makePractitioner(family: "RoleIfMatch"))
        let created = try await store.create(makePractitionerRole(practitionerId: prac.id))
        do {
            _ = try await store.update(id: created.id,
                                       role: makePractitionerRole(practitionerId: prac.id),
                                       ifMatch: 999)
            XCTFail("Expected versionConflict")
        } catch FHIRServerError.versionConflict { }
    }

    // ── Delete ────────────────────────────────────────────────────────────────

    func testDelete_subsequentReadThrowsGone() async throws {
        let prac = try await practitionerStore.create(makePractitioner(family: "RoleDelete"))
        let created = try await store.create(makePractitionerRole(practitionerId: prac.id))
        _ = try await store.delete(id: created.id, ifMatch: nil)
        do {
            _ = try await store.read(id: created.id)
            XCTFail("Expected gone")
        } catch FHIRServerError.gone { }
    }

    // ── Search: practitioner ──────────────────────────────────────────────────

    func testSearch_byPractitionerTypedReference_matchesOnlyThatPractitioner() async throws {
        let a = try await practitionerStore.create(makePractitioner(family: "RoleSearchA"))
        let b = try await practitionerStore.create(makePractitioner(family: "RoleSearchB"))
        _ = try await store.create(makePractitionerRole(practitionerId: a.id, roleDisplay: "主治醫師"))
        _ = try await store.create(makePractitionerRole(practitionerId: b.id, roleDisplay: "護理師"))

        let result = try await store.search(
            query: PractitionerRoleSearchQuery(practitioner: "Practitioner/\(a.id)"))
        XCTAssertEqual(result.total, 1)
        let role = try JSONDecoder().decode(
            ModelsR4.PractitionerRole.self, from: result.entries[0].jsonWithMeta)
        XCTAssertEqual(role.code?.first?.coding?.first?.display?.value?.string, "主治醫師")
    }

    func testSearch_byBarePractitionerId_matches() async throws {
        let prac = try await practitionerStore.create(makePractitioner(family: "RoleBareId"))
        _ = try await store.create(makePractitionerRole(practitionerId: prac.id))

        let result = try await store.search(
            query: PractitionerRoleSearchQuery(practitioner: prac.id))
        XCTAssertEqual(result.total, 1)
    }

    func testSearch_deletedRoleIsExcluded() async throws {
        let prac = try await practitionerStore.create(makePractitioner(family: "RoleDeletedSearch"))
        let created = try await store.create(makePractitionerRole(practitionerId: prac.id))
        _ = try await store.delete(id: created.id, ifMatch: nil)

        let result = try await store.search(
            query: PractitionerRoleSearchQuery(practitioner: "Practitioner/\(prac.id)"))
        XCTAssertEqual(result.total, 0)
    }

    func testSearch_practitionerMissingTrue_matchesRoleWithoutPractitioner() async throws {
        let prac = try await practitionerStore.create(makePractitioner(family: "RoleMissing"))
        _ = try await store.create(makePractitionerRole(practitionerId: prac.id))
        let orphan = try JSONDecoder().decode(
            ModelsR4.PractitionerRole.self,
            from: Data(#"{"resourceType":"PractitionerRole","code":[{"text":"unassigned"}]}"#.utf8))
        let created = try await store.create(orphan)

        var q = PractitionerRoleSearchQuery()
        q.missing = ["practitioner": true]
        let result = try await store.search(query: q)
        XCTAssertTrue(result.entries.contains { $0.id == created.id })
    }

    // ── Search: _total modes ──────────────────────────────────────────────────

    func testSearch_totalNone_omitsTotal() async throws {
        let prac = try await practitionerStore.create(makePractitioner(family: "RoleTotalNone"))
        _ = try await store.create(makePractitionerRole(practitionerId: prac.id))

        var q = PractitionerRoleSearchQuery(practitioner: "Practitioner/\(prac.id)")
        q.totalMode = .none
        let result = try await store.search(query: q)
        XCTAssertNil(result.total)
    }

    // ── History ───────────────────────────────────────────────────────────────

    func testHistory_tracksAllVersions() async throws {
        let prac = try await practitionerStore.create(makePractitioner(family: "RoleHist"))
        let created = try await store.create(makePractitionerRole(practitionerId: prac.id))
        _ = try await store.update(id: created.id,
                                   role: makePractitionerRole(practitionerId: prac.id),
                                   ifMatch: nil)
        let entries = try await store.history(id: created.id)
        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(entries[0].versionId, 2)
        XCTAssertEqual(entries[1].versionId, 1)
    }

    func testTypeHistory_includesAllPractitionerRoles() async throws {
        let prac = try await practitionerStore.create(makePractitioner(family: "RoleTypeHist"))
        _ = try await store.create(makePractitionerRole(practitionerId: prac.id, roleCode: "doctor"))
        _ = try await store.create(makePractitionerRole(practitionerId: prac.id, roleCode: "nurse"))
        let entries = try await store.typeHistory(since: nil, count: 50)
        XCTAssertGreaterThanOrEqual(entries.count, 2)
        XCTAssertTrue(entries.allSatisfy { $0.resourceType == "PractitionerRole" })
    }

    // ── Pagination ────────────────────────────────────────────────────────────

    func testSearch_pagination_returnsCorrectPage() async throws {
        let prac = try await practitionerStore.create(makePractitioner(family: "RolePagination"))
        for i in 0..<5 {
            _ = try await store.create(
                makePractitionerRole(practitionerId: prac.id, roleDisplay: "Role\(i)"))
        }

        var q = PractitionerRoleSearchQuery(practitioner: "Practitioner/\(prac.id)")
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
