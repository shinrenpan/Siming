import Foundation
import ModelsR4
@testable import SimingCore
import XCTest

/// Integration tests for the PATCH flow: read → JSONPatch.apply → decode → store.update.
/// This mirrors exactly what PatientRoutes PATCH handler does, exercising the full chain
/// against a real database (including If-Match, version increment, index re-extraction).
final class PatchStoreTests: XCTestCase {
    var store: PatientStore!

    override func setUp() async throws {
        try await super.setUp()
        try await requireDatabase()
        store = try await TestDatabase.shared.makePatientStore()
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

    private func patch(id: String, ops: [[String: Any]], ifMatch: Int64? = nil) async throws -> PatientStore.WriteResult {
        let current = try await store.read(id: id)
        let patchData = try JSONSerialization.data(withJSONObject: ops)
        let patchedJSON = try JSONPatch.apply(patchData, to: current.jsonData)
        let patient = try JSONDecoder().decode(Patient.self, from: patchedJSON)
        return try await store.update(id: id, patient: patient, ifMatch: ifMatch)
    }

    // ── replace ───────────────────────────────────────────────────────────────

    func testPatch_replace_familyName() async throws {
        let created = try await store.create(makePatient(family: "BeforePatch"))

        let result = try await patch(id: created.id, ops: [
            ["op": "replace", "path": "/name/0/family", "value": "AfterPatch"]
        ])
        XCTAssertEqual(result.versionId, 2)

        let row = try await store.read(id: created.id)
        let patient = try JSONDecoder().decode(Patient.self, from: row.jsonData)
        XCTAssertEqual(patient.name?.first?.family?.value?.string, "AfterPatch")
    }

    func testPatch_replace_increments_version() async throws {
        let created = try await store.create(makePatient(family: "VersionCheck"))
        let r1 = try await patch(id: created.id, ops: [
            ["op": "replace", "path": "/name/0/family", "value": "V2"]
        ])
        let r2 = try await patch(id: created.id, ops: [
            ["op": "replace", "path": "/name/0/family", "value": "V3"]
        ])
        XCTAssertEqual(r1.versionId, 2)
        XCTAssertEqual(r2.versionId, 3)
    }

    // ── add ───────────────────────────────────────────────────────────────────

    func testPatch_add_newField() async throws {
        let created = try await store.create(makePatient(family: "AddField", given: "Before"))

        _ = try await patch(id: created.id, ops: [
            ["op": "add", "path": "/gender", "value": "female"]
        ])

        let row = try await store.read(id: created.id)
        let patient = try JSONDecoder().decode(Patient.self, from: row.jsonData)
        XCTAssertEqual(patient.gender?.value?.rawValue, "female")
    }

    func testPatch_add_arrayElement() async throws {
        let created = try await store.create(makePatient(family: "AddArr"))

        _ = try await patch(id: created.id, ops: [
            ["op": "add", "path": "/name/-", "value": [
                "use": "nickname", "text": "Bobby"
            ]]
        ])

        let row = try await store.read(id: created.id)
        let patient = try JSONDecoder().decode(Patient.self, from: row.jsonData)
        XCTAssertGreaterThanOrEqual(patient.name?.count ?? 0, 2)
    }

    // ── remove ────────────────────────────────────────────────────────────────

    func testPatch_remove_field() async throws {
        let created = try await store.create(makePatient(family: "RemoveField", birthYear: 1990))

        _ = try await patch(id: created.id, ops: [
            ["op": "remove", "path": "/birthDate"]
        ])

        let row = try await store.read(id: created.id)
        let patient = try JSONDecoder().decode(Patient.self, from: row.jsonData)
        XCTAssertNil(patient.birthDate)
    }

    // ── test op ───────────────────────────────────────────────────────────────

    func testPatch_testOp_passes_when_value_matches() async throws {
        let created = try await store.create(makePatient(family: "TestPass"))

        // test op should pass (family is "TestPass"), then replace succeeds
        let result = try await patch(id: created.id, ops: [
            ["op": "test",    "path": "/name/0/family", "value": "TestPass"],
            ["op": "replace", "path": "/name/0/family", "value": "Changed"]
        ])
        XCTAssertEqual(result.versionId, 2)
    }

    func testPatch_testOp_fails_throws_testFailed() async throws {
        let created = try await store.create(makePatient(family: "TestFail"))

        let patchData = try JSONSerialization.data(withJSONObject: [
            ["op": "test",    "path": "/name/0/family", "value": "WrongValue"],
            ["op": "replace", "path": "/name/0/family", "value": "Changed"]
        ])
        let current = try await store.read(id: created.id)
        XCTAssertThrowsError(try JSONPatch.apply(patchData, to: current.jsonData)) { error in
            guard case JSONPatchError.testFailed = error else {
                XCTFail("Expected testFailed, got \(error)")
                return
            }
        }
        // Version must remain 1 — store was never called
        let row = try await store.read(id: created.id)
        XCTAssertEqual(row.versionId, 1)
    }

    // ── invalid patch / path ──────────────────────────────────────────────────

    func testPatch_missingPath_throws_pathNotFound() async throws {
        let created = try await store.create(makePatient(family: "PathMissing"))
        let current = try await store.read(id: created.id)

        let patchData = try JSONSerialization.data(withJSONObject: [
            ["op": "replace", "path": "/nonExistentField/deep/path", "value": "x"]
        ])
        XCTAssertThrowsError(try JSONPatch.apply(patchData, to: current.jsonData)) { error in
            guard case JSONPatchError.pathNotFound = error else {
                XCTFail("Expected pathNotFound, got \(error)")
                return
            }
        }
    }

    func testPatch_invalid_op_throws_invalidPatch() async throws {
        let created = try await store.create(makePatient(family: "BadOp"))
        let current = try await store.read(id: created.id)

        let patchData = try JSONSerialization.data(withJSONObject: [
            ["op": "frobnicate", "path": "/name/0/family", "value": "x"]
        ])
        XCTAssertThrowsError(try JSONPatch.apply(patchData, to: current.jsonData)) { error in
            guard case JSONPatchError.invalidPatch = error else {
                XCTFail("Expected invalidPatch, got \(error)")
                return
            }
        }
    }

    func testPatch_result_invalid_fhir_throws_decodingError() async throws {
        let created = try await store.create(makePatient(family: "InvalidFHIR"))
        let current = try await store.read(id: created.id)

        // Replace name (expects [HumanName] array) with a plain string to force a type-mismatch DecodingError
        let patchData = try JSONSerialization.data(withJSONObject: [
            ["op": "replace", "path": "/name", "value": "not-an-array"]
        ])
        let patchedJSON = try JSONPatch.apply(patchData, to: current.jsonData)
        XCTAssertThrowsError(try JSONDecoder().decode(Patient.self, from: patchedJSON))
    }

    // ── If-Match in PATCH flow ────────────────────────────────────────────────

    func testPatch_ifMatch_success() async throws {
        let created = try await store.create(makePatient(family: "PatchIfMatch"))

        let result = try await patch(id: created.id, ops: [
            ["op": "replace", "path": "/name/0/family", "value": "AfterPatch"]
        ], ifMatch: 1)
        XCTAssertEqual(result.versionId, 2)
    }

    func testPatch_ifMatch_conflict_throws_versionConflict() async throws {
        let created = try await store.create(makePatient(family: "PatchConflict"))
        let current = try await store.read(id: created.id)

        let patchData = try JSONSerialization.data(withJSONObject: [
            ["op": "replace", "path": "/name/0/family", "value": "AfterPatch"]
        ])
        let patchedJSON = try JSONPatch.apply(patchData, to: current.jsonData)
        let patient = try JSONDecoder().decode(Patient.self, from: patchedJSON)

        do {
            _ = try await store.update(id: created.id, patient: patient, ifMatch: 999)
            XCTFail("Expected versionConflict")
        } catch FHIRServerError.versionConflict { }
    }

    // ── Index re-extraction after PATCH ──────────────────────────────────────

    func testPatch_search_reflects_patched_value() async throws {
        let created = try await store.create(makePatient(family: "SearchBefore"))

        _ = try await patch(id: created.id, ops: [
            ["op": "replace", "path": "/name/0/family", "value": "SearchAfter"]
        ])

        let query = PatientSearchQuery(
            family: .init(value: "SearchAfter", modifier: .startsWith))
        let result = try await store.search(query: query)
        let ids = result.entries.map { $0.id }
        XCTAssertTrue(ids.contains(created.id))

        // old value must no longer match
        let oldQuery = PatientSearchQuery(
            family: .init(value: "SearchBefore", modifier: .startsWith))
        let oldResult = try await store.search(query: oldQuery)
        XCTAssertFalse(oldResult.entries.map { $0.id }.contains(created.id))
    }
}
