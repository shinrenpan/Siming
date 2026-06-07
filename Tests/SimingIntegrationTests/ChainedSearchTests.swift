import Foundation
import ModelsR4
@testable import SimingCore
import XCTest

/// Integration tests for chained search parameter (`refParam.childParam=value`).
/// Tests the full SQL path: ChainedParam → chainFilterCTE → store.search → database.
final class ChainedSearchTests: XCTestCase {
    var patientStore: PatientStore!
    var observationStore: ObservationStore!
    var conditionStore: ConditionStore!

    override func setUp() async throws {
        try await super.setUp()
        try await requireDatabase()
        patientStore     = try await TestDatabase.shared.makePatientStore()
        observationStore = try await TestDatabase.shared.makeObservationStore()
        conditionStore   = try await TestDatabase.shared.makeConditionStore()
    }

    // ── String chain (idx_string) ─────────────────────────────────────────────

    func testChain_string_subject_family_match() async throws {
        let p1 = try await patientStore.create(makePatient(family: "ChainFamily"))
        let p2 = try await patientStore.create(makePatient(family: "ChainFamilyOther"))
        let obs1 = try await observationStore.create(makeObservation(subjectId: p1.id))
        let obs2 = try await observationStore.create(makeObservation(subjectId: p2.id))

        let chain = ChainedParam(refParam: "subject", childParam: "family",
                                 value: "ChainFamily", childType: .string)
        let result = try await observationStore.search(query: .init(chains: [chain], count: 50))
        let ids = result.entries.map { $0.id }
        // obs1's patient matches exactly; obs2's patient "ChainFamilyOther" also starts with
        // "ChainFamily" (default = startsWith) — use exact prefix to distinguish
        XCTAssertTrue(ids.contains(obs1.id))
    }

    func testChain_string_noMatch_returnsEmpty() async throws {
        let p = try await patientStore.create(makePatient(family: "ChainNoMatchFam"))
        _ = try await observationStore.create(makeObservation(subjectId: p.id))

        let chain = ChainedParam(refParam: "subject", childParam: "family",
                                 value: "ZZZNonExistentXYZ", childType: .string)
        let result = try await observationStore.search(query: .init(chains: [chain], count: 50))
        XCTAssertEqual(result.entries.count, 0)
    }

    func testChain_string_modifier_exact() async throws {
        let p1 = try await patientStore.create(makePatient(family: "ChainExact"))
        let p2 = try await patientStore.create(makePatient(family: "ChainExactLonger"))
        let obs1 = try await observationStore.create(makeObservation(subjectId: p1.id))
        let obs2 = try await observationStore.create(makeObservation(subjectId: p2.id))

        let chain = ChainedParam(refParam: "subject", childParam: "family",
                                 value: "ChainExact", modifier: "exact", childType: .string)
        let result = try await observationStore.search(query: .init(chains: [chain], count: 50))
        let ids = result.entries.map { $0.id }
        XCTAssertTrue(ids.contains(obs1.id))
        XCTAssertFalse(ids.contains(obs2.id))
    }

    func testChain_string_modifier_contains() async throws {
        let p = try await patientStore.create(makePatient(family: "ChainContainsName"))
        let obs = try await observationStore.create(makeObservation(subjectId: p.id))

        let chain = ChainedParam(refParam: "subject", childParam: "family",
                                 value: "ainContains", modifier: "contains", childType: .string)
        let result = try await observationStore.search(query: .init(chains: [chain], count: 50))
        XCTAssertTrue(result.entries.map { $0.id }.contains(obs.id))
    }

    // ── Date chain (idx_date) ─────────────────────────────────────────────────

    func testChain_date_subject_birthdate_ge() async throws {
        let young = try await patientStore.create(makePatient(family: "ChainDateYoung", birthYear: 2000))
        let old   = try await patientStore.create(makePatient(family: "ChainDateOld",   birthYear: 1950))
        let obsYoung = try await observationStore.create(makeObservation(subjectId: young.id))
        let obsOld   = try await observationStore.create(makeObservation(subjectId: old.id))

        let chain = ChainedParam(refParam: "subject", childParam: "birthdate",
                                 value: "ge1990-01-01", childType: .date)
        let result = try await observationStore.search(query: .init(chains: [chain], count: 50))
        let ids = result.entries.map { $0.id }
        XCTAssertTrue(ids.contains(obsYoung.id))
        XCTAssertFalse(ids.contains(obsOld.id))
    }

    func testChain_date_subject_birthdate_lt() async throws {
        let young = try await patientStore.create(makePatient(family: "ChainDateLtY", birthYear: 2000))
        let old   = try await patientStore.create(makePatient(family: "ChainDateLtO", birthYear: 1950))
        let obsYoung = try await observationStore.create(makeObservation(subjectId: young.id))
        let obsOld   = try await observationStore.create(makeObservation(subjectId: old.id))

        let chain = ChainedParam(refParam: "subject", childParam: "birthdate",
                                 value: "lt1980-01-01", childType: .date)
        let result = try await observationStore.search(query: .init(chains: [chain], count: 50))
        let ids = result.entries.map { $0.id }
        XCTAssertTrue(ids.contains(obsOld.id))
        XCTAssertFalse(ids.contains(obsYoung.id))
    }

    // ── Token chain (idx_token) ───────────────────────────────────────────────

    func testChain_token_subject_gender() async throws {
        let female = try await patientStore.create(makePatient(family: "ChainGenderF", gender: "female"))
        let male   = try await patientStore.create(makePatient(family: "ChainGenderM", gender: "male"))
        let obsF = try await observationStore.create(makeObservation(subjectId: female.id))
        let obsM = try await observationStore.create(makeObservation(subjectId: male.id))

        let chain = ChainedParam(refParam: "subject", childParam: "gender",
                                 value: "female", childType: .token)
        let result = try await observationStore.search(query: .init(chains: [chain], count: 50))
        let ids = result.entries.map { $0.id }
        XCTAssertTrue(ids.contains(obsF.id))
        XCTAssertFalse(ids.contains(obsM.id))
    }

    // ── TargetType restriction ────────────────────────────────────────────────

    func testChain_targetType_patient_matches() async throws {
        let p = try await patientStore.create(makePatient(family: "ChainTargetPat"))
        let obs = try await observationStore.create(makeObservation(subjectId: p.id))

        let chain = ChainedParam(refParam: "subject", targetType: "Patient",
                                 childParam: "family", value: "ChainTargetPat", childType: .string)
        let result = try await observationStore.search(query: .init(chains: [chain], count: 50))
        XCTAssertTrue(result.entries.map { $0.id }.contains(obs.id))
    }

    func testChain_targetType_wrong_type_returnsEmpty() async throws {
        let p = try await patientStore.create(makePatient(family: "ChainTargetGroup"))
        let obs = try await observationStore.create(makeObservation(subjectId: p.id))

        // subject:Group.family — observation's subject is a Patient, not a Group
        let chain = ChainedParam(refParam: "subject", targetType: "Group",
                                 childParam: "family", value: "ChainTargetGroup", childType: .string)
        let result = try await observationStore.search(query: .init(chains: [chain], count: 50))
        XCTAssertFalse(result.entries.map { $0.id }.contains(obs.id))
    }

    // ── Multiple chains (AND logic) ───────────────────────────────────────────

    func testChain_multiple_AND_logic() async throws {
        // obs1 → patient with family "ChainAnd1" born 2000 — matches both
        // obs2 → patient with family "ChainAnd1" born 1950 — matches only family
        // obs3 → patient with family "ChainAnd2" born 2000 — matches only date
        let p1 = try await patientStore.create(makePatient(family: "ChainAnd1", birthYear: 2000))
        let p2 = try await patientStore.create(makePatient(family: "ChainAnd1", birthYear: 1950))
        let p3 = try await patientStore.create(makePatient(family: "ChainAnd2", birthYear: 2000))
        let obs1 = try await observationStore.create(makeObservation(subjectId: p1.id))
        let obs2 = try await observationStore.create(makeObservation(subjectId: p2.id))
        let obs3 = try await observationStore.create(makeObservation(subjectId: p3.id))

        let c1 = ChainedParam(refParam: "subject", childParam: "family",
                               value: "ChainAnd1", modifier: "exact", childType: .string)
        let c2 = ChainedParam(refParam: "subject", childParam: "birthdate",
                               value: "ge1990-01-01", childType: .date)
        let result = try await observationStore.search(query: .init(chains: [c1, c2], count: 50))
        let ids = result.entries.map { $0.id }
        XCTAssertTrue(ids.contains(obs1.id))
        XCTAssertFalse(ids.contains(obs2.id))
        XCTAssertFalse(ids.contains(obs3.id))
    }

    // ── Different resource type ───────────────────────────────────────────────

    func testChain_condition_subject_family() async throws {
        let p1 = try await patientStore.create(makePatient(family: "ChainCond1"))
        let p2 = try await patientStore.create(makePatient(family: "ChainCond2"))
        let cond1 = try await conditionStore.create(makeCondition(subjectId: p1.id))
        let cond2 = try await conditionStore.create(makeCondition(subjectId: p2.id))

        let chain = ChainedParam(refParam: "subject", childParam: "family",
                                 value: "ChainCond1", modifier: "exact", childType: .string)
        let result = try await conditionStore.search(query: .init(chains: [chain], count: 50))
        let ids = result.entries.map { $0.id }
        XCTAssertTrue(ids.contains(cond1.id))
        XCTAssertFalse(ids.contains(cond2.id))
    }
}
