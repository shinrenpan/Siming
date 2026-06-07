import Foundation
import Logging
import ModelsR4
@testable import SimingCore
import XCTest

final class IncludeResolverTests: XCTestCase {
    var patientStore: PatientStore!
    var observationStore: ObservationStore!
    var encounterStore: EncounterStore!
    var resolver: IncludeResolver!

    override func setUp() async throws {
        try await super.setUp()
        try await requireDatabase()
        patientStore     = try await TestDatabase.shared.makePatientStore()
        observationStore = try await TestDatabase.shared.makeObservationStore()
        encounterStore   = try await TestDatabase.shared.makeEncounterStore()
        var logger = Logger(label: "test.include")
        logger.logLevel = .critical
        resolver = IncludeResolver(client: patientStore.client, logger: logger)
    }

    // ── _include ──────────────────────────────────────────────────────────────

    func testInclude_observation_subject_returnsPatient() async throws {
        let patient = try await patientStore.create(makePatient(family: "IncPat"))
        _ = try await observationStore.create(makeObservation(subjectId: patient.id))

        let includes = [IncludeParam(sourceType: "Observation", paramName: "subject")]
        // Simulate a search result: one Observation whose subject is the Patient
        let obs2 = try await observationStore.create(makeObservation(subjectId: patient.id))

        let included = try await resolver.resolve(includes: includes, sourceIds: [obs2.id])
        XCTAssertEqual(included.count, 1)
        XCTAssertEqual(included[0].resourceType, "Patient")
        XCTAssertEqual(included[0].id, patient.id)
    }

    func testInclude_with_targetType_restricts_result() async throws {
        let patient = try await patientStore.create(makePatient(family: "IncTarget"))
        let obs = try await observationStore.create(makeObservation(subjectId: patient.id))

        // targetType = "Patient" — should still find the patient
        let includes = [IncludeParam(sourceType: "Observation", paramName: "subject", targetType: "Patient")]
        let included = try await resolver.resolve(includes: includes, sourceIds: [obs.id])
        XCTAssertEqual(included.count, 1)
        XCTAssertEqual(included[0].resourceType, "Patient")

        // targetType = "Group" — should find nothing (no Group references)
        let includesGroup = [IncludeParam(sourceType: "Observation", paramName: "subject", targetType: "Group")]
        let includedGroup = try await resolver.resolve(includes: includesGroup, sourceIds: [obs.id])
        XCTAssertEqual(includedGroup.count, 0)
    }

    func testInclude_empty_sourceIds_returnsEmpty() async throws {
        let includes = [IncludeParam(sourceType: "Observation", paramName: "subject")]
        let included = try await resolver.resolve(includes: includes, sourceIds: [])
        XCTAssertEqual(included.count, 0)
    }

    func testInclude_empty_params_returnsEmpty() async throws {
        let patient = try await patientStore.create(makePatient(family: "IncEmpty"))
        let obs = try await observationStore.create(makeObservation(subjectId: patient.id))
        let included = try await resolver.resolve(includes: [], sourceIds: [obs.id])
        XCTAssertEqual(included.count, 0)
    }

    func testInclude_deduplication_sameResourceReferencedTwice() async throws {
        let patient = try await patientStore.create(makePatient(family: "IncDedup"))
        let obs1 = try await observationStore.create(makeObservation(subjectId: patient.id))
        let obs2 = try await observationStore.create(makeObservation(subjectId: patient.id))

        let includes = [IncludeParam(sourceType: "Observation", paramName: "subject")]
        let included = try await resolver.resolve(includes: includes, sourceIds: [obs1.id, obs2.id])
        // Both observations reference the same patient — result should deduplicate to 1
        let patientResults = included.filter { $0.resourceType == "Patient" && $0.id == patient.id }
        XCTAssertEqual(patientResults.count, 1)
    }

    func testInclude_multipleSourceIds_multiplePatients() async throws {
        let p1 = try await patientStore.create(makePatient(family: "IncMulti1"))
        let p2 = try await patientStore.create(makePatient(family: "IncMulti2"))
        let obs1 = try await observationStore.create(makeObservation(subjectId: p1.id))
        let obs2 = try await observationStore.create(makeObservation(subjectId: p2.id))

        let includes = [IncludeParam(sourceType: "Observation", paramName: "subject")]
        let included = try await resolver.resolve(includes: includes, sourceIds: [obs1.id, obs2.id])
        let patientIds = Set(included.filter { $0.resourceType == "Patient" }.map { $0.id })
        XCTAssertEqual(patientIds, [p1.id, p2.id])
    }

    func testInclude_unknownParam_returnsEmpty() async throws {
        let patient = try await patientStore.create(makePatient(family: "IncUnknown"))
        let obs = try await observationStore.create(makeObservation(subjectId: patient.id))
        let includes = [IncludeParam(sourceType: "Observation", paramName: "non-existent-param")]
        let included = try await resolver.resolve(includes: includes, sourceIds: [obs.id])
        XCTAssertEqual(included.count, 0)
    }

    // ── _revinclude ───────────────────────────────────────────────────────────

    func testRevInclude_observation_subject_fromPatient() async throws {
        let patient = try await patientStore.create(makePatient(family: "RevPat"))
        let obs1 = try await observationStore.create(makeObservation(subjectId: patient.id))
        let obs2 = try await observationStore.create(makeObservation(subjectId: patient.id))
        // Another patient's observation — must NOT appear
        let otherPatient = try await patientStore.create(makePatient(family: "RevOther"))
        _ = try await observationStore.create(makeObservation(subjectId: otherPatient.id))

        let revIncludes = [IncludeParam(sourceType: "Observation", paramName: "subject")]
        let included = try await resolver.resolveRev(revIncludes: revIncludes, mainIds: [patient.id])
        let obsIds = Set(included.filter { $0.resourceType == "Observation" }.map { $0.id })
        XCTAssertEqual(obsIds, [obs1.id, obs2.id])
    }

    func testRevInclude_empty_mainIds_returnsEmpty() async throws {
        let revIncludes = [IncludeParam(sourceType: "Observation", paramName: "subject")]
        let included = try await resolver.resolveRev(revIncludes: revIncludes, mainIds: [])
        XCTAssertEqual(included.count, 0)
    }

    func testRevInclude_deduplication_multipleReferences() async throws {
        let patient = try await patientStore.create(makePatient(family: "RevDedup"))
        let obs = try await observationStore.create(makeObservation(subjectId: patient.id))

        let revIncludes = [IncludeParam(sourceType: "Observation", paramName: "subject")]
        let included = try await resolver.resolveRev(revIncludes: revIncludes, mainIds: [patient.id])
        let obsResults = included.filter { $0.resourceType == "Observation" && $0.id == obs.id }
        XCTAssertEqual(obsResults.count, 1)
    }

    func testRevInclude_multiple_resourceTypes_simultaneously() async throws {
        let patient = try await patientStore.create(makePatient(family: "RevMulti"))
        let obs = try await observationStore.create(makeObservation(subjectId: patient.id))
        let enc = try await encounterStore.create(makeEncounter(subjectId: patient.id))

        let revIncludes = [
            IncludeParam(sourceType: "Observation", paramName: "subject"),
            IncludeParam(sourceType: "Encounter",   paramName: "subject"),
        ]
        let included = try await resolver.resolveRev(revIncludes: revIncludes, mainIds: [patient.id])
        let types = Set(included.map { $0.resourceType })
        XCTAssertTrue(types.contains("Observation"))
        XCTAssertTrue(types.contains("Encounter"))
        XCTAssertTrue(included.contains { $0.id == obs.id })
        XCTAssertTrue(included.contains { $0.id == enc.id })
    }

    func testRevInclude_includedResourceHasMetaInjected() async throws {
        let patient = try await patientStore.create(makePatient(family: "RevMeta"))
        _ = try await observationStore.create(makeObservation(subjectId: patient.id))

        let revIncludes = [IncludeParam(sourceType: "Observation", paramName: "subject")]
        let included = try await resolver.resolveRev(revIncludes: revIncludes, mainIds: [patient.id])
        XCTAssertEqual(included.count, 1)
        // Meta injection means the JSON should contain "id" and "versionId"
        let json = try JSONSerialization.jsonObject(with: included[0].jsonWithMeta) as! [String: Any]
        let meta = json["meta"] as? [String: Any]
        XCTAssertNotNil(json["id"])
        XCTAssertNotNil(meta?["versionId"])
    }
}
