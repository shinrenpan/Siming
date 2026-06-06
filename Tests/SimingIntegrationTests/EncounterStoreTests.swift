import Foundation
import ModelsR4
@testable import SimingCore
import XCTest

final class EncounterStoreTests: XCTestCase {
    var store: EncounterStore!
    var patientStore: PatientStore!

    override func setUp() async throws {
        try await super.setUp()
        try await requireDatabase()
        store        = try await TestDatabase.shared.makeEncounterStore()
        patientStore = try await TestDatabase.shared.makePatientStore()
    }

    // ── Create ────────────────────────────────────────────────────────────────

    func testCreate_assignsIdAndVersionOne() async throws {
        let pid = try await patientStore.create(makePatient(family: "EncPt1")).id
        let result = try await store.create(makeEncounter(subjectId: pid))
        XCTAssertFalse(result.id.isEmpty)
        XCTAssertEqual(result.versionId, 1)
    }

    // ── Read ──────────────────────────────────────────────────────────────────

    func testRead_returnsStoredStatus() async throws {
        let pid = try await patientStore.create(makePatient(family: "EncPt2")).id
        let created = try await store.create(makeEncounter(subjectId: pid, status: "in-progress"))
        let read = try await store.read(id: created.id)
        let enc = try JSONDecoder().decode(ModelsR4.Encounter.self, from: read.jsonData)
        XCTAssertEqual(enc.status.value?.rawValue, "in-progress")
    }

    func testRead_unknownId_throwsNotFound() async throws {
        do {
            _ = try await store.read(id: "nonexistent-encounter")
            XCTFail("Expected notFound")
        } catch FHIRServerError.notFound { }
    }

    // ── Update ────────────────────────────────────────────────────────────────

    func testUpdate_incrementsVersionId() async throws {
        let pid = try await patientStore.create(makePatient(family: "EncPt3")).id
        let created = try await store.create(makeEncounter(subjectId: pid, status: "planned"))
        let updated = try await store.update(
            id: created.id,
            encounter: makeEncounter(subjectId: pid, status: "finished"),
            ifMatch: nil
        )
        XCTAssertEqual(updated.versionId, 2)
    }

    // ── Delete ────────────────────────────────────────────────────────────────

    func testDelete_subsequentReadThrowsGone() async throws {
        let pid = try await patientStore.create(makePatient(family: "EncPt4")).id
        let created = try await store.create(makeEncounter(subjectId: pid))
        try await store.delete(id: created.id, ifMatch: nil)
        do {
            _ = try await store.read(id: created.id)
            XCTFail("Expected gone")
        } catch FHIRServerError.gone { }
    }

    // ── Search ────────────────────────────────────────────────────────────────

    func testSearch_bySubject_returnsMatchOnly() async throws {
        let pid1 = try await patientStore.create(makePatient(family: "EncSubjA")).id
        let pid2 = try await patientStore.create(makePatient(family: "EncSubjB")).id
        _ = try await store.create(makeEncounter(subjectId: pid1))
        _ = try await store.create(makeEncounter(subjectId: pid1))
        _ = try await store.create(makeEncounter(subjectId: pid2))

        let result = try await store.search(query: EncounterSearchQuery(subject: "Patient/\(pid1)"))
        XCTAssertEqual(result.total, 2)
    }

    func testSearch_byStatus_returnsMatchOnly() async throws {
        let pid = try await patientStore.create(makePatient(family: "EncStatusPt")).id
        _ = try await store.create(makeEncounter(subjectId: pid, status: "finished"))
        _ = try await store.create(makeEncounter(subjectId: pid, status: "planned"))

        let result = try await store.search(query: EncounterSearchQuery(status: ["finished"]))
        XCTAssertEqual(result.total, 1)
    }

    func testSearch_byStatusNot_excludesCorrectly() async throws {
        let pid = try await patientStore.create(makePatient(family: "EncStatusNotPt")).id
        _ = try await store.create(makeEncounter(subjectId: pid, status: "finished"))
        _ = try await store.create(makeEncounter(subjectId: pid, status: "planned"))

        let result = try await store.search(query: EncounterSearchQuery(statusNot: ["finished"]))
        XCTAssertEqual(result.total, 1)
        let enc = try JSONDecoder().decode(ModelsR4.Encounter.self, from: result.entries[0].jsonWithMeta)
        XCTAssertEqual(enc.status.value?.rawValue, "planned")
    }

    // ── History ───────────────────────────────────────────────────────────────

    func testHistory_tracksAllVersions() async throws {
        let pid = try await patientStore.create(makePatient(family: "EncHistPt")).id
        let created = try await store.create(makeEncounter(subjectId: pid, status: "planned"))
        _ = try await store.update(
            id: created.id,
            encounter: makeEncounter(subjectId: pid, status: "finished"),
            ifMatch: nil
        )
        let entries = try await store.history(id: created.id)
        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(entries[0].versionId, 2)
        XCTAssertEqual(entries[1].versionId, 1)
    }
}
