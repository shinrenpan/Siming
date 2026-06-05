import Foundation
import ModelsR4
@testable import SimingCore
import XCTest

final class PatientStoreTests: XCTestCase {
    var store: PatientStore!

    override func setUp() async throws {
        try await super.setUp()
        try await requireDatabase()
        store = try await TestDatabase.shared.makePatientStore()
    }

    // ── Create ────────────────────────────────────────────────────────────────

    func testCreate_assignsIdAndVersionOne() async throws {
        let result = try await store.create(makePatient(family: "Smith"))
        XCTAssertFalse(result.id.isEmpty)
        XCTAssertEqual(result.versionId, 1)
    }

    // ── Read ──────────────────────────────────────────────────────────────────

    func testRead_returnsStoredFamily() async throws {
        let created = try await store.create(makePatient(family: "Tanaka"))
        let read = try await store.read(id: created.id)
        let patient = try JSONDecoder().decode(ModelsR4.Patient.self, from: read.jsonData)
        XCTAssertEqual(patient.name?.first?.family?.value?.string, "Tanaka")
    }

    func testRead_unknownId_throwsNotFound() async throws {
        do {
            _ = try await store.read(id: "nonexistent-id")
            XCTFail("Expected notFound error")
        } catch FHIRServerError.notFound { }
    }

    // ── Update ────────────────────────────────────────────────────────────────

    func testUpdate_incrementsVersionId() async throws {
        let created = try await store.create(makePatient(family: "Lee"))
        let updated = try await store.update(
            id: created.id,
            patient: makePatient(family: "Lee-Updated"),
            ifMatch: nil
        )
        XCTAssertEqual(updated.id, created.id)
        XCTAssertEqual(updated.versionId, 2)
    }

    // ── Delete ────────────────────────────────────────────────────────────────

    func testDelete_subsequentReadThrowsGone() async throws {
        let created = try await store.create(makePatient(family: "Park"))
        try await store.delete(id: created.id, ifMatch: nil)
        do {
            _ = try await store.read(id: created.id)
            XCTFail("Expected gone error")
        } catch FHIRServerError.gone { }
    }

    // ── Search ────────────────────────────────────────────────────────────────

    func testSearch_byFamily_returnsMatchOnly() async throws {
        _ = try await store.create(makePatient(family: "Adams"))
        _ = try await store.create(makePatient(family: "Brown"))

        let result = try await store.search(query: PatientSearchQuery(
            family: PatientSearchQuery.StringParam(value: "Adams", modifier: .startsWith)
        ))
        XCTAssertEqual(result.entries.count, 1)
        XCTAssertEqual(result.total, 1)
    }

    func testSearch_byBirthdate_respects_ge_prefix() async throws {
        _ = try await store.create(makePatient(family: "Old", birthYear: 1970))
        _ = try await store.create(makePatient(family: "Young", birthYear: 2000))

        let cutoff = PatientSearchQuery.BirthdateParam.parse("ge1990-01-01")!
        let result = try await store.search(query: PatientSearchQuery(birthdate: [cutoff]))
        XCTAssertEqual(result.total, 1)
        let patient = try JSONDecoder().decode(ModelsR4.Patient.self, from: result.entries[0].jsonWithMeta)
        XCTAssertEqual(patient.name?.first?.family?.value?.string, "Young")
    }

    func testSearch_pagination_cursorAdvances() async throws {
        for i in 1...5 { _ = try await store.create(makePatient(family: "Page\(i)")) }

        let page1 = try await store.search(query: PatientSearchQuery(count: 2))
        XCTAssertEqual(page1.entries.count, 2)
        XCTAssertNotNil(page1.nextCursor)

        let page2 = try await store.search(query: PatientSearchQuery(
            count: 2, cursor: page1.nextCursor
        ))
        XCTAssertEqual(page2.entries.count, 2)
        // IDs must not overlap
        let ids1 = Set(page1.entries.map(\.id))
        let ids2 = Set(page2.entries.map(\.id))
        XCTAssertTrue(ids1.isDisjoint(with: ids2))
    }

    func testSearch_byFamily_text_modifier_isSubstringMatch() async throws {
        _ = try await store.create(makePatient(family: "Nakamura"))
        _ = try await store.create(makePatient(family: "Adams"))

        let result = try await store.search(query: PatientSearchQuery(
            family: PatientSearchQuery.StringParam(value: "mur", modifier: .text)
        ))
        XCTAssertEqual(result.total, 1)
        let p = try JSONDecoder().decode(ModelsR4.Patient.self, from: result.entries[0].jsonWithMeta)
        XCTAssertEqual(p.name?.first?.family?.value?.string, "Nakamura")
    }

    func testSearch_sort_by_id_ascending() async throws {
        for i in 1...4 { _ = try await store.create(makePatient(family: "IdSort\(i)")) }

        let result = try await store.search(query: PatientSearchQuery(
            sort: PatientSearchQuery.SortOrder.parse("_id"),
            count: 10
        ))
        XCTAssertGreaterThanOrEqual(result.entries.count, 4)
        let ids = result.entries.map(\.id)
        XCTAssertEqual(ids, ids.sorted())
    }

    // ── History ───────────────────────────────────────────────────────────────

    func testHistory_tracksAllVersions() async throws {
        let created = try await store.create(makePatient(family: "Hist"))
        _ = try await store.update(id: created.id, patient: makePatient(family: "Hist-v2"), ifMatch: nil)

        let entries = try await store.history(id: created.id)
        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(entries[0].versionId, 2)  // newest first
        XCTAssertEqual(entries[1].versionId, 1)
    }
}
