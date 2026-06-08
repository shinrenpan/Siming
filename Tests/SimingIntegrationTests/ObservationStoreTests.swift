import Foundation
import ModelsR4
@testable import SimingCore
import XCTest

final class ObservationStoreTests: XCTestCase {
    var store: ObservationStore!
    var patientStore: PatientStore!

    override func setUp() async throws {
        try await super.setUp()
        try await requireDatabase()
        store = try await TestDatabase.shared.makeObservationStore()
        patientStore = try await TestDatabase.shared.makePatientStore()
    }

    // ── Create / Read ─────────────────────────────────────────────────────────

    func testCreate_assignsId() async throws {
        let patientId = try await patientStore.create(makePatient(family: "Obs-Patient")).id
        let result = try await store.create(makeObservation(subjectId: patientId))
        XCTAssertFalse(result.id.isEmpty)
        XCTAssertEqual(result.versionId, 1)
    }

    func testRead_returnsStoredCode() async throws {
        let patientId = try await patientStore.create(makePatient(family: "ReadObs")).id
        let created = try await store.create(makeObservation(subjectId: patientId, code: "8867-4"))

        let read = try await store.read(id: created.id)
        let obs = try JSONDecoder().decode(ModelsR4.Observation.self, from: read.jsonData)
        let code = obs.code.coding?.first?.code?.value?.string
        XCTAssertEqual(code, "8867-4")
    }

    func testDelete_subsequentReadThrowsGone() async throws {
        let patientId = try await patientStore.create(makePatient(family: "DelObs")).id
        let created = try await store.create(makeObservation(subjectId: patientId))
        try await store.delete(id: created.id, ifMatch: nil)
        do {
            _ = try await store.read(id: created.id)
            XCTFail("Expected gone error")
        } catch FHIRServerError.gone { }
    }

    // ── Update ────────────────────────────────────────────────────────────────

    func testUpdate_incrementsVersionId() async throws {
        let patientId = try await patientStore.create(makePatient(family: "UpdObs")).id
        let created = try await store.create(makeObservation(subjectId: patientId))
        let updated = try await store.update(
            id: created.id,
            observation: makeObservation(subjectId: patientId, code: "8867-4"),
            ifMatch: nil
        )
        XCTAssertEqual(updated.versionId, 2)
    }

    // ── Search ────────────────────────────────────────────────────────────────

    func testSearch_bySubject_returnsMatchOnly() async throws {
        let pid1 = try await patientStore.create(makePatient(family: "SubjA")).id
        let pid2 = try await patientStore.create(makePatient(family: "SubjB")).id
        _ = try await store.create(makeObservation(subjectId: pid1))
        _ = try await store.create(makeObservation(subjectId: pid1))
        _ = try await store.create(makeObservation(subjectId: pid2))

        let result = try await store.search(query: ObservationSearchQuery(
            subject: "Patient/\(pid1)"
        ))
        XCTAssertEqual(result.total, 2)
        XCTAssertTrue(result.entries.allSatisfy { entry in
            (try? JSONDecoder().decode(ModelsR4.Observation.self, from: entry.jsonWithMeta))?
                .subject?.reference?.value?.string == "Patient/\(pid1)"
        })
    }

    func testSearch_byCode_loinc_returnsMatchOnly() async throws {
        let pid = try await patientStore.create(makePatient(family: "CodePt")).id
        _ = try await store.create(makeObservation(subjectId: pid, code: "29463-7"))
        _ = try await store.create(makeObservation(subjectId: pid, code: "8867-4"))

        let result = try await store.search(query: ObservationSearchQuery(
            code: [ObservationSearchQuery.TokenParam(system: "http://loinc.org", code: "29463-7")]
        ))
        XCTAssertEqual(result.total, 1)
    }

    func testSearch_byStatus_final_returnsMatchOnly() async throws {
        let pid = try await patientStore.create(makePatient(family: "StatusPt")).id
        _ = try await store.create(makeObservation(subjectId: pid, status: "final"))
        _ = try await store.create(makeObservation(subjectId: pid, status: "preliminary"))

        let result = try await store.search(query: ObservationSearchQuery(status: ["final"]))
        XCTAssertEqual(result.total, 1)
    }

    func testSearch_byStatusNot_excludesCorrectly() async throws {
        let pid = try await patientStore.create(makePatient(family: "StatusNotPt")).id
        _ = try await store.create(makeObservation(subjectId: pid, status: "final"))
        _ = try await store.create(makeObservation(subjectId: pid, status: "preliminary"))

        let result = try await store.search(query: ObservationSearchQuery(statusNot: ["final"]))
        XCTAssertEqual(result.total, 1)
        let obs = try JSONDecoder().decode(
            ModelsR4.Observation.self,
            from: result.entries[0].jsonWithMeta
        )
        XCTAssertEqual(obs.status.value?.rawValue, "preliminary")
    }

    // ── History ───────────────────────────────────────────────────────────────

    func testHistory_tracksAllVersions() async throws {
        let patientId = try await patientStore.create(makePatient(family: "HistObs")).id
        let created = try await store.create(makeObservation(subjectId: patientId))
        _ = try await store.update(
            id: created.id,
            observation: makeObservation(subjectId: patientId, code: "8867-4"),
            ifMatch: nil
        )

        let entries = try await store.history(id: created.id)
        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(entries[0].versionId, 2)
        XCTAssertEqual(entries[1].versionId, 1)
    }

    // ── _lastUpdated search filter ────────────────────────────────────────────

    func testSearch_lastUpdated_ge_pastDate_includesCreated() async throws {
        let patientId = try await patientStore.create(makePatient(family: "ObsLUPast")).id
        let obs = try await store.create(makeObservation(subjectId: patientId))
        let past = ObservationSearchQuery.DateParam.parse("ge2000-01-01")!
        let result = try await store.search(query: ObservationSearchQuery(lastUpdated: [past], count: 100))
        XCTAssertTrue(result.entries.map(\.id).contains(obs.id))
    }

    func testSearch_lastUpdated_ge_futureDate_returnsEmpty() async throws {
        let patientId = try await patientStore.create(makePatient(family: "ObsLUFuture")).id
        _ = try await store.create(makeObservation(subjectId: patientId))
        let future = ObservationSearchQuery.DateParam.parse("ge2099-01-01")!
        let result = try await store.search(query: ObservationSearchQuery(lastUpdated: [future], count: 100))
        XCTAssertEqual(result.entries.count, 0)
    }

    // ── New search parameters (Round 50) ──────────────────────────────────────

    func testSearch_bySpecimen() async throws {
        let pid = try await patientStore.create(makePatient(family: "SpecimenPt")).id
        let specimenId = "specimen-abc"
        _ = try await store.create(makeObservation(subjectId: pid, specimenId: specimenId))
        _ = try await store.create(makeObservation(subjectId: pid))

        let result = try await store.search(query: ObservationSearchQuery(specimen: "Specimen/\(specimenId)"))
        XCTAssertEqual(result.total, 1)
    }

    func testSearch_byHasMember() async throws {
        let pid = try await patientStore.create(makePatient(family: "HasMemberPt")).id
        let memberId = "obs-member-xyz"
        _ = try await store.create(makeObservation(subjectId: pid, hasMemberId: memberId))
        _ = try await store.create(makeObservation(subjectId: pid))

        let result = try await store.search(query: ObservationSearchQuery(hasMember: "Observation/\(memberId)"))
        XCTAssertEqual(result.total, 1)
    }

    func testSearch_byPartOf() async throws {
        let pid = try await patientStore.create(makePatient(family: "PartOfPt")).id
        let parentId = "obs-parent-abc"
        _ = try await store.create(makeObservation(subjectId: pid, partOfId: parentId))
        _ = try await store.create(makeObservation(subjectId: pid))

        let result = try await store.search(query: ObservationSearchQuery(partOf: "Observation/\(parentId)"))
        XCTAssertEqual(result.total, 1)
    }

    func testSearch_byMethod() async throws {
        let pid = try await patientStore.create(makePatient(family: "MethodPt")).id
        _ = try await store.create(makeObservation(subjectId: pid, methodCode: "129265001"))
        _ = try await store.create(makeObservation(subjectId: pid))

        let tok = ObservationSearchQuery.TokenParam(system: "http://snomed.info/sct", code: "129265001")
        let result = try await store.search(query: ObservationSearchQuery(method: [tok]))
        XCTAssertEqual(result.total, 1)
    }

    func testSearch_byMethodNot() async throws {
        let pid = try await patientStore.create(makePatient(family: "MethodNotPt")).id
        _ = try await store.create(makeObservation(subjectId: pid, methodCode: "129265001"))
        _ = try await store.create(makeObservation(subjectId: pid))

        let tok = ObservationSearchQuery.TokenParam(system: "http://snomed.info/sct", code: "129265001")
        let result = try await store.search(query: ObservationSearchQuery(
            subject: "Patient/\(pid)", methodNot: [tok]
        ))
        XCTAssertEqual(result.total, 1)
    }

    func testSearch_byValueConcept() async throws {
        let pid = try await patientStore.create(makePatient(family: "ValConPt")).id
        _ = try await store.create(makeObservation(subjectId: pid, valueConcept: "260385009"))
        _ = try await store.create(makeObservation(subjectId: pid))

        let tok = ObservationSearchQuery.TokenParam(system: "http://snomed.info/sct", code: "260385009")
        let result = try await store.search(query: ObservationSearchQuery(valueConcept: [tok]))
        XCTAssertEqual(result.total, 1)
    }

    func testSearch_byValueString() async throws {
        let pid = try await patientStore.create(makePatient(family: "ValStrPt")).id
        _ = try await store.create(makeObservation(subjectId: pid, valueString: "Positive result"))
        _ = try await store.create(makeObservation(subjectId: pid))

        let result = try await store.search(query: ObservationSearchQuery(
            subject: "Patient/\(pid)", valueString: ["Positive"]
        ))
        XCTAssertEqual(result.total, 1)
    }

    func testSearch_byValueDate() async throws {
        let pid = try await patientStore.create(makePatient(family: "ValDatePt")).id
        _ = try await store.create(makeObservation(subjectId: pid, valueDateTime: "2024-06-15"))
        _ = try await store.create(makeObservation(subjectId: pid))

        let dp = ObservationSearchQuery.DateParam.parse("eq2024-06-15")!
        let result = try await store.search(query: ObservationSearchQuery(
            subject: "Patient/\(pid)", valueDate: [dp]
        ))
        XCTAssertEqual(result.total, 1)
    }

    func testSearch_byComboCode_matchesComponentCode() async throws {
        let pid = try await patientStore.create(makePatient(family: "ComboPt")).id
        _ = try await store.create(makeObservation(subjectId: pid, componentCode: "8480-6"))
        _ = try await store.create(makeObservation(subjectId: pid))

        let tok = ObservationSearchQuery.TokenParam(system: "http://loinc.org", code: "8480-6")
        let result = try await store.search(query: ObservationSearchQuery(comboCode: [tok]))
        XCTAssertEqual(result.total, 1)
    }

    func testSearch_byComboCode_matchesObsCode() async throws {
        let pid = try await patientStore.create(makePatient(family: "ComboMainPt")).id
        _ = try await store.create(makeObservation(subjectId: pid, code: "55284-4"))
        _ = try await store.create(makeObservation(subjectId: pid, code: "29463-7"))

        let tok = ObservationSearchQuery.TokenParam(system: "http://loinc.org", code: "55284-4")
        let result = try await store.search(query: ObservationSearchQuery(comboCode: [tok]))
        XCTAssertEqual(result.total, 1)
    }

    // ── Search: data-absent-reason ────────────────────────────────────────────

    func testSearch_byDataAbsentReason_returnsMatchOnly() async throws {
        let pid = try await patientStore.create(makePatient(family: "DARPt")).id
        _ = try await store.create(makeObservation(subjectId: pid, dataAbsentReasonCode: "unknown"))
        _ = try await store.create(makeObservation(subjectId: pid))

        let result = try await store.search(query: ObservationSearchQuery(
            subject: "Patient/\(pid)",
            dataAbsentReason: [.init(system: nil, code: "unknown")]
        ))
        XCTAssertEqual(result.total, 1)
    }

    // ── Search: combo-data-absent-reason ──────────────────────────────────────

    func testSearch_byComboDataAbsentReason_matchesObsLevel() async throws {
        let pid = try await patientStore.create(makePatient(family: "ComboDARPt")).id
        _ = try await store.create(makeObservation(subjectId: pid, dataAbsentReasonCode: "masked"))
        _ = try await store.create(makeObservation(subjectId: pid))

        let result = try await store.search(query: ObservationSearchQuery(
            subject: "Patient/\(pid)",
            comboDataAbsentReason: [.init(system: nil, code: "masked")]
        ))
        XCTAssertEqual(result.total, 1)
    }

    func testSearch_byComboDataAbsentReason_matchesComponentLevel() async throws {
        let pid = try await patientStore.create(makePatient(family: "ComboDARCompPt")).id
        _ = try await store.create(makeObservation(subjectId: pid, componentDataAbsentReasonCode: "not-performed"))
        _ = try await store.create(makeObservation(subjectId: pid))

        let result = try await store.search(query: ObservationSearchQuery(
            subject: "Patient/\(pid)",
            comboDataAbsentReason: [.init(system: nil, code: "not-performed")]
        ))
        XCTAssertEqual(result.total, 1)
    }

    // ── Search: component-data-absent-reason ──────────────────────────────────

    func testSearch_byComponentDataAbsentReason_returnsMatchOnly() async throws {
        let pid = try await patientStore.create(makePatient(family: "CompDARPt")).id
        _ = try await store.create(makeObservation(subjectId: pid, componentDataAbsentReasonCode: "error"))
        _ = try await store.create(makeObservation(subjectId: pid))

        let result = try await store.search(query: ObservationSearchQuery(
            subject: "Patient/\(pid)",
            componentDataAbsentReason: [.init(system: nil, code: "error")]
        ))
        XCTAssertEqual(result.total, 1)
    }

    // ── Search: component-value-concept ───────────────────────────────────────

    func testSearch_byComponentValueConcept_returnsMatchOnly() async throws {
        let pid = try await patientStore.create(makePatient(family: "CompValConPt")).id
        _ = try await store.create(makeObservation(subjectId: pid,
            componentCode: "8480-6", componentValueConceptCode: "260385009"))
        _ = try await store.create(makeObservation(subjectId: pid))

        let result = try await store.search(query: ObservationSearchQuery(
            subject: "Patient/\(pid)",
            componentValueConcept: [.init(system: nil, code: "260385009")]
        ))
        XCTAssertEqual(result.total, 1)
    }

    // ── Search: component-value-quantity ─────────────────────────────────────

    func testSearch_byComponentValueQuantity_ge_returnsMatchOnly() async throws {
        let pid = try await patientStore.create(makePatient(family: "CompValQtyPt")).id
        _ = try await store.create(makeObservation(subjectId: pid, componentCode: "8480-6", componentQuantityValue: 120))
        _ = try await store.create(makeObservation(subjectId: pid, componentCode: "8480-6", componentQuantityValue: 70))
        _ = try await store.create(makeObservation(subjectId: pid))

        let param = ObservationSearchQuery.QuantityParam.parse("ge100")!
        let result = try await store.search(query: ObservationSearchQuery(
            subject: "Patient/\(pid)",
            componentValueQuantity: [param]
        ))
        XCTAssertEqual(result.total, 1)
    }

    // ── Search: combo-value-quantity ──────────────────────────────────────────

    func testSearch_byComboValueQuantity_ge_returnsMatchOnly() async throws {
        let pid = try await patientStore.create(makePatient(family: "ComboVQtyPt")).id
        _ = try await store.create(makeObservation(subjectId: pid, valueQuantity: 75.0))
        _ = try await store.create(makeObservation(subjectId: pid, valueQuantity: 40.0))
        _ = try await store.create(makeObservation(subjectId: pid))

        let param = ObservationSearchQuery.QuantityParam.parse("ge60")!
        let result = try await store.search(query: ObservationSearchQuery(
            subject: "Patient/\(pid)",
            comboValueQuantity: [param]
        ))
        XCTAssertEqual(result.total, 1)
    }
}
