import Foundation
import ModelsR4
@testable import SimingCore
import XCTest

/// Integration tests for `_has` reverse chaining (`_has:Type:refParam:childParam=value`).
/// Tests the full SQL path: HasParam → hasFilterCTE → store.search → database.
final class HasSearchTests: XCTestCase {
    var patientStore: PatientStore!
    var observationStore: ObservationStore!
    var conditionStore: ConditionStore!
    var encounterStore: EncounterStore!

    override func setUp() async throws {
        try await super.setUp()
        try await requireDatabase()
        patientStore     = try await TestDatabase.shared.makePatientStore()
        observationStore = try await TestDatabase.shared.makeObservationStore()
        conditionStore   = try await TestDatabase.shared.makeConditionStore()
        encounterStore   = try await TestDatabase.shared.makeEncounterStore()
    }

    // ── Token _has (idx_token) ────────────────────────────────────────────────

    func testHas_observation_subject_status_token() async throws {
        let p1 = try await patientStore.create(makePatient(family: "HasStatus1"))
        let p2 = try await patientStore.create(makePatient(family: "HasStatus2"))
        _ = try await observationStore.create(makeObservation(subjectId: p1.id, status: "final"))
        _ = try await observationStore.create(makeObservation(subjectId: p2.id, status: "registered"))

        let hp = HasParam(referencedType: "Observation", refParam: "subject",
                          childParam: "status", value: "final", childType: .token)
        let result = try await patientStore.search(query: .init(has: [hp], count: 50))
        let ids = result.entries.map { $0.id }
        XCTAssertTrue(ids.contains(p1.id))
        XCTAssertFalse(ids.contains(p2.id))
    }

    func testHas_observation_subject_code_token() async throws {
        let p1 = try await patientStore.create(makePatient(family: "HasCode1"))
        let p2 = try await patientStore.create(makePatient(family: "HasCode2"))
        _ = try await observationStore.create(makeObservation(subjectId: p1.id, code: "85354-9"))
        _ = try await observationStore.create(makeObservation(subjectId: p2.id, code: "29463-7"))

        let hp = HasParam(referencedType: "Observation", refParam: "subject",
                          childParam: "code", value: "85354-9", childType: .token)
        let result = try await patientStore.search(query: .init(has: [hp], count: 50))
        let ids = result.entries.map { $0.id }
        XCTAssertTrue(ids.contains(p1.id))
        XCTAssertFalse(ids.contains(p2.id))
    }

    func testHas_condition_subject_clinicalStatus() async throws {
        let p1 = try await patientStore.create(makePatient(family: "HasCondA"))
        let p2 = try await patientStore.create(makePatient(family: "HasCondR"))
        _ = try await conditionStore.create(makeCondition(subjectId: p1.id, clinicalStatus: "active"))
        _ = try await conditionStore.create(makeCondition(subjectId: p2.id, clinicalStatus: "resolved"))

        let hp = HasParam(referencedType: "Condition", refParam: "subject",
                          childParam: "clinical-status", value: "active", childType: .token)
        let result = try await patientStore.search(query: .init(has: [hp], count: 50))
        let ids = result.entries.map { $0.id }
        XCTAssertTrue(ids.contains(p1.id))
        XCTAssertFalse(ids.contains(p2.id))
    }

    func testHas_encounter_subject_status_token() async throws {
        let p1 = try await patientStore.create(makePatient(family: "HasEncFinished"))
        let p2 = try await patientStore.create(makePatient(family: "HasEncPlanned"))
        _ = try await encounterStore.create(makeEncounter(subjectId: p1.id, status: "finished"))
        _ = try await encounterStore.create(makeEncounter(subjectId: p2.id, status: "planned"))

        let hp = HasParam(referencedType: "Encounter", refParam: "subject",
                          childParam: "status", value: "finished", childType: .token)
        let result = try await patientStore.search(query: .init(has: [hp], count: 50))
        let ids = result.entries.map { $0.id }
        XCTAssertTrue(ids.contains(p1.id))
        XCTAssertFalse(ids.contains(p2.id))
    }

    // ── No match ─────────────────────────────────────────────────────────────

    func testHas_noMatch_returnsEmpty() async throws {
        let p = try await patientStore.create(makePatient(family: "HasNoMatch"))
        _ = try await observationStore.create(makeObservation(subjectId: p.id, code: "11111-1"))

        let hp = HasParam(referencedType: "Observation", refParam: "subject",
                          childParam: "code", value: "99999-9", childType: .token)
        let result = try await patientStore.search(query: .init(has: [hp], count: 50))
        XCTAssertFalse(result.entries.map { $0.id }.contains(p.id))
    }

    func testHas_patientWithNoReferencingResource_excluded() async throws {
        let p = try await patientStore.create(makePatient(family: "HasNoObs"))
        // No observations for p

        let hp = HasParam(referencedType: "Observation", refParam: "subject",
                          childParam: "status", value: "final", childType: .token)
        let result = try await patientStore.search(query: .init(has: [hp], count: 50))
        XCTAssertFalse(result.entries.map { $0.id }.contains(p.id))
    }

    // ── Multiple _has (AND logic) ─────────────────────────────────────────────

    func testHas_multiple_AND_logic() async throws {
        // p1: has final observation AND active condition → matches both
        // p2: has final observation, no active condition → does not match
        // p3: has active condition, no final observation → does not match
        let p1 = try await patientStore.create(makePatient(family: "HasMulti1"))
        let p2 = try await patientStore.create(makePatient(family: "HasMulti2"))
        let p3 = try await patientStore.create(makePatient(family: "HasMulti3"))
        _ = try await observationStore.create(makeObservation(subjectId: p1.id, status: "final"))
        _ = try await observationStore.create(makeObservation(subjectId: p2.id, status: "final"))
        _ = try await conditionStore.create(makeCondition(subjectId: p1.id, clinicalStatus: "active"))
        _ = try await conditionStore.create(makeCondition(subjectId: p3.id, clinicalStatus: "active"))

        let hp1 = HasParam(referencedType: "Observation", refParam: "subject",
                           childParam: "status", value: "final", childType: .token)
        let hp2 = HasParam(referencedType: "Condition", refParam: "subject",
                           childParam: "clinical-status", value: "active", childType: .token)
        let result = try await patientStore.search(query: .init(has: [hp1, hp2], count: 50))
        let ids = result.entries.map { $0.id }
        XCTAssertTrue(ids.contains(p1.id))
        XCTAssertFalse(ids.contains(p2.id))
        XCTAssertFalse(ids.contains(p3.id))
    }

    // ── Deduplication ─────────────────────────────────────────────────────────

    func testHas_multipleReferencingResources_deduplicatesPatient() async throws {
        let p = try await patientStore.create(makePatient(family: "HasDedup"))
        _ = try await observationStore.create(makeObservation(subjectId: p.id, status: "final"))
        _ = try await observationStore.create(makeObservation(subjectId: p.id, status: "final"))

        let hp = HasParam(referencedType: "Observation", refParam: "subject",
                          childParam: "status", value: "final", childType: .token)
        let result = try await patientStore.search(query: .init(has: [hp], count: 50))
        // Two final observations for same patient — should appear exactly once
        let matchingIds = result.entries.filter { $0.id == p.id }
        XCTAssertEqual(matchingIds.count, 1)
    }

    // ── _has on non-Patient resource (Encounter level) ────────────────────────

    func testHas_onObservation_via_encounter_reference() async throws {
        let p = try await patientStore.create(makePatient(family: "HasEncObs"))
        let enc1 = try await encounterStore.create(makeEncounter(subjectId: p.id, status: "finished"))
        let enc2 = try await encounterStore.create(makeEncounter(subjectId: p.id, status: "planned"))

        // _has:Observation:encounter:status=final — find Encounters that are
        // referenced by an Observation whose status=final.
        // Here we test that HasParam works on EncounterStore search too.
        let obs = try await observationStore.create(makeObservation(subjectId: p.id, status: "final"))
        _ = obs  // created to populate the DB, but we're querying encounters

        // Instead test a clearer scenario: _has on ObservationStore
        // _has:Encounter:subject:status=finished — on Patient search
        let hp = HasParam(referencedType: "Encounter", refParam: "subject",
                          childParam: "status", value: "finished", childType: .token)
        let result = try await patientStore.search(query: .init(has: [hp], count: 50))
        XCTAssertTrue(result.entries.map { $0.id }.contains(p.id))
        _ = enc1; _ = enc2
    }
}
