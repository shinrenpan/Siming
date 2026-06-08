import Foundation
import ModelsR4
@testable import SimingCore
import XCTest

final class EncounterStoreTests: XCTestCase {
    var store: EncounterStore!
    var patientStore: PatientStore!
    var practitionerStore: PractitionerStore!
    var organizationStore: OrganizationStore!
    var locationStore: LocationStore!

    override func setUp() async throws {
        try await super.setUp()
        try await requireDatabase()
        store             = try await TestDatabase.shared.makeEncounterStore()
        patientStore      = try await TestDatabase.shared.makePatientStore()
        practitionerStore = try await TestDatabase.shared.makePractitionerStore()
        organizationStore = try await TestDatabase.shared.makeOrganizationStore()
        locationStore     = try await TestDatabase.shared.makeLocationStore()
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

    // ── Search: participant ───────────────────────────────────────────────────

    func testSearch_byParticipant_returnsMatchOnly() async throws {
        let pid = try await patientStore.create(makePatient(family: "EncParticPt")).id
        let prac = try await practitionerStore.create(makePractitioner(family: "EncParticPrac")).id
        _ = try await store.create(makeEncounter(subjectId: pid, participantId: prac))
        _ = try await store.create(makeEncounter(subjectId: pid))

        let result = try await store.search(query: EncounterSearchQuery(
            participant: "Practitioner/\(prac)"
        ))
        XCTAssertEqual(result.total, 1)
    }

    // ── Search: practitioner ──────────────────────────────────────────────────

    func testSearch_byPractitioner_returnsMatchOnly() async throws {
        let pid = try await patientStore.create(makePatient(family: "EncPracPt")).id
        let prac = try await practitionerStore.create(makePractitioner(family: "EncPracPrac")).id
        _ = try await store.create(makeEncounter(subjectId: pid, practitionerId: prac))
        _ = try await store.create(makeEncounter(subjectId: pid))

        let result = try await store.search(query: EncounterSearchQuery(
            practitioner: "Practitioner/\(prac)"
        ))
        XCTAssertEqual(result.total, 1)
    }

    // ── Search: reason-code ───────────────────────────────────────────────────

    func testSearch_byReasonCode_returnsMatchOnly() async throws {
        let pid = try await patientStore.create(makePatient(family: "EncRsnPt")).id
        _ = try await store.create(makeEncounter(subjectId: pid, reasonCode: "385093006"))
        _ = try await store.create(makeEncounter(subjectId: pid))

        let result = try await store.search(query: EncounterSearchQuery(
            reasonCode: [.init(system: nil, code: "385093006")]
        ))
        XCTAssertEqual(result.total, 1)
    }

    // ── Search: part-of ───────────────────────────────────────────────────────

    func testSearch_byPartOf_returnsMatchOnly() async throws {
        let pid = try await patientStore.create(makePatient(family: "EncPartOfPt")).id
        let parent = try await store.create(makeEncounter(subjectId: pid))
        _ = try await store.create(makeEncounter(subjectId: pid, partOfId: parent.id))
        _ = try await store.create(makeEncounter(subjectId: pid))

        let result = try await store.search(query: EncounterSearchQuery(
            partOf: "Encounter/\(parent.id)"
        ))
        XCTAssertEqual(result.total, 1)
    }

    // ── Search: service-provider ──────────────────────────────────────────────

    func testSearch_byServiceProvider_returnsMatchOnly() async throws {
        let pid = try await patientStore.create(makePatient(family: "EncSvcPt")).id
        let org = try await organizationStore.create(makeOrganization(name: "EncSvcOrg")).id
        _ = try await store.create(makeEncounter(subjectId: pid, serviceProviderId: org))
        _ = try await store.create(makeEncounter(subjectId: pid))

        let result = try await store.search(query: EncounterSearchQuery(
            serviceProvider: "Organization/\(org)"
        ))
        XCTAssertEqual(result.total, 1)
    }

    // ── Search: based-on ──────────────────────────────────────────────────────

    func testSearch_byBasedOn_returnsMatchOnly() async throws {
        let pid = try await patientStore.create(makePatient(family: "EncBasedOnPt")).id
        let srId = "sr-abc-\(UUID().uuidString.prefix(8))"
        _ = try await store.create(makeEncounter(subjectId: pid, basedOnId: srId))
        _ = try await store.create(makeEncounter(subjectId: pid))

        let result = try await store.search(query: EncounterSearchQuery(
            basedOn: "ServiceRequest/\(srId)"
        ))
        XCTAssertEqual(result.total, 1)
    }

    // ── Search: location ──────────────────────────────────────────────────────

    func testSearch_byLocation_returnsMatchOnly() async throws {
        let pid = try await patientStore.create(makePatient(family: "EncLocPt")).id
        let loc = try await locationStore.create(makeLocation(name: "EncTestLoc")).id
        _ = try await store.create(makeEncounter(subjectId: pid, locationId: loc))
        _ = try await store.create(makeEncounter(subjectId: pid))

        let result = try await store.search(query: EncounterSearchQuery(
            location: "Location/\(loc)"
        ))
        XCTAssertEqual(result.total, 1)
    }

    // ── Search: diagnosis ─────────────────────────────────────────────────────

    func testSearch_byDiagnosis_returnsMatchOnly() async throws {
        let pid = try await patientStore.create(makePatient(family: "EncDiagPt")).id
        let condId = "cond-diag-\(UUID().uuidString.prefix(8))"
        _ = try await store.create(makeEncounter(subjectId: pid, diagnosisId: condId))
        _ = try await store.create(makeEncounter(subjectId: pid))

        let result = try await store.search(query: EncounterSearchQuery(
            diagnosis: "Condition/\(condId)"
        ))
        XCTAssertEqual(result.total, 1)
    }

    // ── Search: account ───────────────────────────────────────────────────────

    func testSearch_byAccount_returnsMatchOnly() async throws {
        let pid = try await patientStore.create(makePatient(family: "EncAccPt")).id
        let accId = "acc-\(UUID().uuidString.prefix(8))"
        _ = try await store.create(makeEncounter(subjectId: pid, accountId: accId))
        _ = try await store.create(makeEncounter(subjectId: pid))

        let result = try await store.search(query: EncounterSearchQuery(
            account: "Account/\(accId)"
        ))
        XCTAssertEqual(result.total, 1)
    }

    // ── Search: appointment ───────────────────────────────────────────────────

    func testSearch_byAppointment_returnsMatchOnly() async throws {
        let pid = try await patientStore.create(makePatient(family: "EncApptPt")).id
        let apptId = "appt-\(UUID().uuidString.prefix(8))"
        _ = try await store.create(makeEncounter(subjectId: pid, appointmentId: apptId))
        _ = try await store.create(makeEncounter(subjectId: pid))

        let result = try await store.search(query: EncounterSearchQuery(
            appointment: "Appointment/\(apptId)"
        ))
        XCTAssertEqual(result.total, 1)
    }

    // ── Search: episode-of-care ───────────────────────────────────────────────

    func testSearch_byEpisodeOfCare_returnsMatchOnly() async throws {
        let pid = try await patientStore.create(makePatient(family: "EncEocPt")).id
        let eocId = "eoc-\(UUID().uuidString.prefix(8))"
        _ = try await store.create(makeEncounter(subjectId: pid, episodeOfCareId: eocId))
        _ = try await store.create(makeEncounter(subjectId: pid))

        let result = try await store.search(query: EncounterSearchQuery(
            episodeOfCare: "EpisodeOfCare/\(eocId)"
        ))
        XCTAssertEqual(result.total, 1)
    }

    // ── Search: reason-reference ──────────────────────────────────────────────

    func testSearch_byReasonReference_returnsMatchOnly() async throws {
        let pid = try await patientStore.create(makePatient(family: "EncRsnRefPt")).id
        let condId = "cond-rsn-\(UUID().uuidString.prefix(8))"
        _ = try await store.create(makeEncounter(subjectId: pid, reasonReferenceId: condId))
        _ = try await store.create(makeEncounter(subjectId: pid))

        let result = try await store.search(query: EncounterSearchQuery(
            reasonReference: "Condition/\(condId)"
        ))
        XCTAssertEqual(result.total, 1)
    }

    // ── Search: location-period ───────────────────────────────────────────────

    func testSearch_byLocationPeriod_ge_returnsMatchOnly() async throws {
        let pid = try await patientStore.create(makePatient(family: "EncLocPerPt")).id
        // period 2020-01-01 to 2022-12-31 — ends before the filter date
        _ = try await store.create(makeEncounter(subjectId: pid, locationPeriodStart: "2020-01-01", locationPeriodEnd: "2022-12-31"))
        // period starting 2025-06-01, no end — extends beyond filter date
        _ = try await store.create(makeEncounter(subjectId: pid, locationPeriodStart: "2025-06-01"))

        let param = EncounterSearchQuery.DateParam.parse("ge2023-01-01")!
        let result = try await store.search(query: EncounterSearchQuery(locationPeriod: [param]))
        XCTAssertEqual(result.total, 1)
    }

    // ── Search: participant-type ──────────────────────────────────────────────

    func testSearch_byParticipantType_returnsMatchOnly() async throws {
        let pid = try await patientStore.create(makePatient(family: "EncPTypePt")).id
        _ = try await store.create(makeEncounter(subjectId: pid, participantTypeCode: "PART"))
        _ = try await store.create(makeEncounter(subjectId: pid))

        let result = try await store.search(query: EncounterSearchQuery(
            participantType: [.init(system: nil, code: "PART")]
        ))
        XCTAssertEqual(result.total, 1)
    }

    func testSearch_byParticipantTypeNot_excludesCorrectly() async throws {
        let pid = try await patientStore.create(makePatient(family: "EncPTypeNotPt")).id
        _ = try await store.create(makeEncounter(subjectId: pid, participantTypeCode: "PART"))
        _ = try await store.create(makeEncounter(subjectId: pid, participantTypeCode: "ADM"))

        let result = try await store.search(query: EncounterSearchQuery(
            participantTypeNot: [.init(system: nil, code: "PART")]
        ))
        XCTAssertEqual(result.total, 1)
    }

    // ── Search: special-arrangement ───────────────────────────────────────────

    func testSearch_bySpecialArrangement_returnsMatchOnly() async throws {
        let pid = try await patientStore.create(makePatient(family: "EncSpcArrPt")).id
        _ = try await store.create(makeEncounter(subjectId: pid, specialArrangementCode: "wheel"))
        _ = try await store.create(makeEncounter(subjectId: pid))

        let result = try await store.search(query: EncounterSearchQuery(
            specialArrangement: [.init(system: nil, code: "wheel")]
        ))
        XCTAssertEqual(result.total, 1)
    }

    func testSearch_bySpecialArrangementNot_excludesCorrectly() async throws {
        let pid = try await patientStore.create(makePatient(family: "EncSpcArrNotPt")).id
        _ = try await store.create(makeEncounter(subjectId: pid, specialArrangementCode: "wheel"))
        _ = try await store.create(makeEncounter(subjectId: pid, specialArrangementCode: "add-bed"))

        let result = try await store.search(query: EncounterSearchQuery(
            specialArrangementNot: [.init(system: nil, code: "wheel")]
        ))
        XCTAssertEqual(result.total, 1)
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
