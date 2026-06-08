import Foundation
import ModelsR4
@testable import SimingCore
import XCTest

final class ImmunizationStoreTests: XCTestCase {
    var store: ImmunizationStore!
    var patientStore: PatientStore!

    override func setUp() async throws {
        try await super.setUp()
        try await requireDatabase()
        store        = try await TestDatabase.shared.makeImmunizationStore()
        patientStore = try await TestDatabase.shared.makePatientStore()
    }

    // ── Create ────────────────────────────────────────────────────────────────

    func testCreate_assignsIdAndVersionOne() async throws {
        let pid = try await patientStore.create(makePatient(family: "ImmPt1")).id
        let result = try await store.create(makeImmunization(patientId: pid))
        XCTAssertFalse(result.id.isEmpty)
        XCTAssertEqual(result.versionId, 1)
    }

    // ── Read ──────────────────────────────────────────────────────────────────

    func testRead_returnsStoredStatus() async throws {
        let pid = try await patientStore.create(makePatient(family: "ImmPt2")).id
        let created = try await store.create(makeImmunization(patientId: pid, status: "not-done"))
        let read = try await store.read(id: created.id)
        let imm = try JSONDecoder().decode(ModelsR4.Immunization.self, from: read.jsonData)
        XCTAssertEqual(imm.status.value?.rawValue, "not-done")
    }

    func testRead_unknownId_throwsNotFound() async throws {
        do {
            _ = try await store.read(id: "nonexistent-immunization")
            XCTFail("Expected notFound")
        } catch FHIRServerError.notFound { }
    }

    // ── vread ─────────────────────────────────────────────────────────────────

    func testVread_returnsSpecificVersion() async throws {
        let pid = try await patientStore.create(makePatient(family: "ImmVread")).id
        let created = try await store.create(makeImmunization(patientId: pid, status: "not-done"))
        _ = try await store.update(id: created.id,
                                   immunization: makeImmunization(patientId: pid, status: "completed"),
                                   ifMatch: nil)
        let v1 = try await store.vread(id: created.id, versionId: 1)
        let imm = try JSONDecoder().decode(ModelsR4.Immunization.self, from: v1.jsonData)
        XCTAssertEqual(imm.status.value?.rawValue, "not-done")
    }

    // ── Update ────────────────────────────────────────────────────────────────

    func testUpdate_incrementsVersionId() async throws {
        let pid = try await patientStore.create(makePatient(family: "ImmPt3")).id
        let created = try await store.create(makeImmunization(patientId: pid, status: "not-done"))
        let updated = try await store.update(id: created.id,
                                             immunization: makeImmunization(patientId: pid, status: "completed"),
                                             ifMatch: nil)
        XCTAssertEqual(updated.versionId, 2)
    }

    func testUpdate_ifMatch_wrongEtag_throwsPreconditionFailed() async throws {
        let pid = try await patientStore.create(makePatient(family: "ImmIfMatch")).id
        let created = try await store.create(makeImmunization(patientId: pid))
        do {
            _ = try await store.update(id: created.id,
                                       immunization: makeImmunization(patientId: pid),
                                       ifMatch: 999)
            XCTFail("Expected versionConflict")
        } catch FHIRServerError.versionConflict { }
    }

    // ── Delete ────────────────────────────────────────────────────────────────

    func testDelete_subsequentReadThrowsGone() async throws {
        let pid = try await patientStore.create(makePatient(family: "ImmPt4")).id
        let created = try await store.create(makeImmunization(patientId: pid))
        _ = try await store.delete(id: created.id, ifMatch: nil)
        do {
            _ = try await store.read(id: created.id)
            XCTFail("Expected gone")
        } catch FHIRServerError.gone { }
    }

    // ── Search: patient ───────────────────────────────────────────────────────

    func testSearch_byPatient_returnsMatchOnly() async throws {
        let pid1 = try await patientStore.create(makePatient(family: "ImmSubjA")).id
        let pid2 = try await patientStore.create(makePatient(family: "ImmSubjB")).id
        _ = try await store.create(makeImmunization(patientId: pid1))
        _ = try await store.create(makeImmunization(patientId: pid1))
        _ = try await store.create(makeImmunization(patientId: pid2))

        let result = try await store.search(query: ImmunizationSearchQuery(subject: "Patient/\(pid1)"))
        XCTAssertEqual(result.total, 2)
    }

    // ── Search: status ────────────────────────────────────────────────────────

    func testSearch_byStatus_completed_returnsMatchOnly() async throws {
        let pid = try await patientStore.create(makePatient(family: "ImmStatusPt")).id
        _ = try await store.create(makeImmunization(patientId: pid, status: "completed"))
        _ = try await store.create(makeImmunization(patientId: pid, status: "not-done"))

        let result = try await store.search(query: ImmunizationSearchQuery(
            status: [ImmunizationSearchQuery.TokenParam(system: nil, code: "completed")]
        ))
        XCTAssertEqual(result.total, 1)
    }

    func testSearch_byStatusNot_excludesCorrectly() async throws {
        let pid = try await patientStore.create(makePatient(family: "ImmStatusNotPt")).id
        _ = try await store.create(makeImmunization(patientId: pid, status: "completed"))
        _ = try await store.create(makeImmunization(patientId: pid, status: "not-done"))

        let result = try await store.search(query: ImmunizationSearchQuery(
            statusNot: [ImmunizationSearchQuery.TokenParam(system: nil, code: "completed")]
        ))
        XCTAssertEqual(result.total, 1)
        let imm = try JSONDecoder().decode(ModelsR4.Immunization.self,
                                           from: result.entries[0].jsonWithMeta)
        XCTAssertEqual(imm.status.value?.rawValue, "not-done")
    }

    // ── Search: vaccine-code ──────────────────────────────────────────────────

    func testSearch_byVaccineCode_returnsMatchOnly() async throws {
        let pid = try await patientStore.create(makePatient(family: "ImmVaxCodePt")).id
        _ = try await store.create(makeImmunization(patientId: pid, vaccineCode: "207"))
        _ = try await store.create(makeImmunization(patientId: pid, vaccineCode: "208"))

        let result = try await store.search(query: ImmunizationSearchQuery(
            vaccineCode: [ImmunizationSearchQuery.TokenParam(system: nil, code: "207")]
        ))
        XCTAssertEqual(result.total, 1)
    }

    func testSearch_byVaccineCode_withSystem_returnsMatchOnly() async throws {
        let pid = try await patientStore.create(makePatient(family: "ImmVaxSysPt")).id
        _ = try await store.create(makeImmunization(patientId: pid, vaccineCode: "207",
                                                     vaccineSystem: "http://hl7.org/fhir/sid/cvx"))
        _ = try await store.create(makeImmunization(patientId: pid, vaccineCode: "207",
                                                     vaccineSystem: "http://other.system"))

        let result = try await store.search(query: ImmunizationSearchQuery(
            vaccineCode: [ImmunizationSearchQuery.TokenParam(
                system: "http://hl7.org/fhir/sid/cvx", code: "207"
            )]
        ))
        XCTAssertEqual(result.total, 1)
    }

    // ── Search: date ──────────────────────────────────────────────────────────

    func testSearch_byDate_ge_returnsMatchOnly() async throws {
        let pid = try await patientStore.create(makePatient(family: "ImmDatePt")).id
        _ = try await store.create(makeImmunization(patientId: pid, occurrenceDate: "2019-05-20"))
        _ = try await store.create(makeImmunization(patientId: pid, occurrenceDate: "2023-10-05"))

        let param = ImmunizationSearchQuery.DateParam.parse("ge2022-01-01")!
        let result = try await store.search(query: ImmunizationSearchQuery(date: [param]))
        XCTAssertEqual(result.total, 1)
    }

    func testSearch_byDate_lt_returnsMatchOnly() async throws {
        let pid = try await patientStore.create(makePatient(family: "ImmDateLtPt")).id
        _ = try await store.create(makeImmunization(patientId: pid, occurrenceDate: "2019-05-20"))
        _ = try await store.create(makeImmunization(patientId: pid, occurrenceDate: "2023-10-05"))

        let param = ImmunizationSearchQuery.DateParam.parse("lt2022-01-01")!
        let result = try await store.search(query: ImmunizationSearchQuery(date: [param]))
        XCTAssertEqual(result.total, 1)
    }

    // ── Search: lot-number ────────────────────────────────────────────────────

    func testSearch_byLotNumber_returnsMatchOnly() async throws {
        let pid = try await patientStore.create(makePatient(family: "ImmLotPt")).id
        _ = try await store.create(makeImmunization(patientId: pid, lotNumber: "LOT-ABC-123"))
        _ = try await store.create(makeImmunization(patientId: pid, lotNumber: "LOT-XYZ-999"))

        let result = try await store.search(query: ImmunizationSearchQuery(lotNumber: .init(value: "LOT-ABC", modifier: .startsWith)))
        XCTAssertEqual(result.total, 1)
    }

    func testSearch_byLotNumber_exactMatch() async throws {
        let pid = try await patientStore.create(makePatient(family: "ImmLotExact")).id
        _ = try await store.create(makeImmunization(patientId: pid, lotNumber: "BATCH-001"))
        _ = try await store.create(makeImmunization(patientId: pid, lotNumber: "BATCH-001-EXT"))

        // starts-with: "BATCH-001" matches both
        let result1 = try await store.search(query: ImmunizationSearchQuery(lotNumber: .init(value: "BATCH-001", modifier: .startsWith)))
        XCTAssertEqual(result1.total, 2)
    }

    // ── Search: _id ───────────────────────────────────────────────────────────

    func testSearch_byId_returnsMatchOnly() async throws {
        let pid = try await patientStore.create(makePatient(family: "ImmIdPt")).id
        let created = try await store.create(makeImmunization(patientId: pid))
        _ = try await store.create(makeImmunization(patientId: pid))

        let result = try await store.search(query: ImmunizationSearchQuery(id: [created.id]))
        XCTAssertEqual(result.total, 1)
        XCTAssertEqual(result.entries[0].id, created.id)
    }

    // ── Search: totalMode=none ────────────────────────────────────────────────

    func testSearch_totalModeNone_returnsNilTotal() async throws {
        let pid = try await patientStore.create(makePatient(family: "ImmTotalNone")).id
        _ = try await store.create(makeImmunization(patientId: pid))

        let result = try await store.search(query: ImmunizationSearchQuery(
            subject: "Patient/\(pid)", totalMode: .none
        ))
        XCTAssertNil(result.total)
    }

    // ── Search: location ─────────────────────────────────────────────────────

    func testSearch_byLocation_returnsMatchOnly() async throws {
        let pid = try await patientStore.create(makePatient(family: "ImmLocPt")).id
        let locId = "loc-imm-\(UUID().uuidString.prefix(8))"
        _ = try await store.create(makeImmunization(patientId: pid, locationId: locId))
        _ = try await store.create(makeImmunization(patientId: pid))
        let result = try await store.search(query: ImmunizationSearchQuery(location: "Location/\(locId)"))
        XCTAssertEqual(result.total, 1)
    }

    // ── Search: manufacturer ─────────────────────────────────────────────────

    func testSearch_byManufacturer_returnsMatchOnly() async throws {
        let pid = try await patientStore.create(makePatient(family: "ImmMfrPt")).id
        let mfrId = "mfr-imm-\(UUID().uuidString.prefix(8))"
        _ = try await store.create(makeImmunization(patientId: pid, manufacturerId: mfrId))
        _ = try await store.create(makeImmunization(patientId: pid))
        let result = try await store.search(query: ImmunizationSearchQuery(manufacturer: "Organization/\(mfrId)"))
        XCTAssertEqual(result.total, 1)
    }

    // ── Search: reaction ─────────────────────────────────────────────────────

    func testSearch_byReaction_returnsMatchOnly() async throws {
        let pid = try await patientStore.create(makePatient(family: "ImmRxnPt")).id
        let obsId = "obs-rxn-\(UUID().uuidString.prefix(8))"
        _ = try await store.create(makeImmunization(patientId: pid, reactionDetailId: obsId))
        _ = try await store.create(makeImmunization(patientId: pid))
        let result = try await store.search(query: ImmunizationSearchQuery(reaction: "Observation/\(obsId)"))
        XCTAssertEqual(result.total, 1)
    }

    // ── Search: reaction-date ─────────────────────────────────────────────────

    func testSearch_byReactionDate_ge_returnsMatchOnly() async throws {
        let pid = try await patientStore.create(makePatient(family: "ImmRxnDatePt")).id
        _ = try await store.create(makeImmunization(patientId: pid, reactionDate: "2021-03-10"))
        _ = try await store.create(makeImmunization(patientId: pid, reactionDate: "2019-07-05"))
        _ = try await store.create(makeImmunization(patientId: pid))
        let param = ImmunizationSearchQuery.DateParam.parse("ge2020-01-01")!
        let result = try await store.search(query: ImmunizationSearchQuery(reactionDate: [param]))
        XCTAssertEqual(result.total, 1)
    }

    // ── Search: reason-code ───────────────────────────────────────────────────

    func testSearch_byReasonCode_returnsMatchOnly() async throws {
        let pid = try await patientStore.create(makePatient(family: "ImmReasonCodePt")).id
        _ = try await store.create(makeImmunization(patientId: pid, reasonCode: "429060002"))
        _ = try await store.create(makeImmunization(patientId: pid, reasonCode: "281040007"))
        _ = try await store.create(makeImmunization(patientId: pid))
        let result = try await store.search(query: ImmunizationSearchQuery(
            reasonCode: [ImmunizationSearchQuery.TokenParam(system: nil, code: "429060002")]
        ))
        XCTAssertEqual(result.total, 1)
    }

    // ── Search: reason-reference ──────────────────────────────────────────────

    func testSearch_byReasonReference_returnsMatchOnly() async throws {
        let pid = try await patientStore.create(makePatient(family: "ImmReasonRefPt")).id
        let condId = "cond-imm-\(UUID().uuidString.prefix(8))"
        _ = try await store.create(makeImmunization(patientId: pid, reasonReferenceId: condId))
        _ = try await store.create(makeImmunization(patientId: pid))
        let result = try await store.search(query: ImmunizationSearchQuery(reasonReference: "Condition/\(condId)"))
        XCTAssertEqual(result.total, 1)
    }

    // ── Search: series ────────────────────────────────────────────────────────

    func testSearch_bySeries_returnsMatchOnly() async throws {
        let pid = try await patientStore.create(makePatient(family: "ImmSeriesPt")).id
        _ = try await store.create(makeImmunization(patientId: pid, series: "Dose1"))
        _ = try await store.create(makeImmunization(patientId: pid, series: "Dose2"))
        _ = try await store.create(makeImmunization(patientId: pid))
        let result = try await store.search(query: ImmunizationSearchQuery(series: .init(value: "Dose1", modifier: .startsWith)))
        XCTAssertEqual(result.total, 1)
    }

    // ── Search: status-reason ─────────────────────────────────────────────────

    func testSearch_byStatusReason_returnsMatchOnly() async throws {
        let pid = try await patientStore.create(makePatient(family: "ImmStatusReasonPt")).id
        _ = try await store.create(makeImmunization(patientId: pid, status: "not-done", statusReasonCode: "IMMUNE"))
        _ = try await store.create(makeImmunization(patientId: pid, status: "not-done", statusReasonCode: "MEDPREC"))
        _ = try await store.create(makeImmunization(patientId: pid))
        let result = try await store.search(query: ImmunizationSearchQuery(
            statusReason: [ImmunizationSearchQuery.TokenParam(system: nil, code: "IMMUNE")]
        ))
        XCTAssertEqual(result.total, 1)
    }

    // ── Search: target-disease ────────────────────────────────────────────────

    func testSearch_byTargetDisease_returnsMatchOnly() async throws {
        let pid = try await patientStore.create(makePatient(family: "ImmTargetDiseasePt")).id
        _ = try await store.create(makeImmunization(patientId: pid, targetDiseaseCode: "840539006"))
        _ = try await store.create(makeImmunization(patientId: pid, targetDiseaseCode: "6142004"))
        _ = try await store.create(makeImmunization(patientId: pid))
        let result = try await store.search(query: ImmunizationSearchQuery(
            targetDisease: [ImmunizationSearchQuery.TokenParam(system: nil, code: "840539006")]
        ))
        XCTAssertEqual(result.total, 1)
    }

    // ── History ───────────────────────────────────────────────────────────────

    func testHistory_tracksAllVersions() async throws {
        let pid = try await patientStore.create(makePatient(family: "ImmHistPt")).id
        let created = try await store.create(makeImmunization(patientId: pid, status: "not-done"))
        _ = try await store.update(id: created.id,
                                   immunization: makeImmunization(patientId: pid, status: "completed"),
                                   ifMatch: nil)
        let entries = try await store.history(id: created.id)
        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(entries[0].versionId, 2)
        XCTAssertEqual(entries[1].versionId, 1)
    }

    func testTypeHistory_includesAllImmunizations() async throws {
        let pid = try await patientStore.create(makePatient(family: "ImmTypeHist")).id
        _ = try await store.create(makeImmunization(patientId: pid))
        _ = try await store.create(makeImmunization(patientId: pid))
        let entries = try await store.typeHistory(since: nil, count: 50)
        XCTAssertGreaterThanOrEqual(entries.count, 2)
        XCTAssertTrue(entries.allSatisfy { $0.resourceType == "Immunization" })
    }

    // ── Pagination ────────────────────────────────────────────────────────────

    func testSearch_pagination_returnsCorrectPage() async throws {
        let pid = try await patientStore.create(makePatient(family: "ImmPagePt")).id
        for _ in 0..<5 { _ = try await store.create(makeImmunization(patientId: pid)) }

        var q = ImmunizationSearchQuery(subject: "Patient/\(pid)")
        q.count = 2
        let page1 = try await store.search(query: q)
        XCTAssertEqual(page1.entries.count, 2)
        XCTAssertEqual(page1.total, 5)
        XCTAssertNotNil(page1.nextCursor)

        q.cursor = page1.nextCursor
        let page2 = try await store.search(query: q)
        XCTAssertGreaterThan(page2.entries.count, 0)
        let page1Ids = Set(page1.entries.map(\.id))
        let page2Ids = Set(page2.entries.map(\.id))
        XCTAssertTrue(page1Ids.isDisjoint(with: page2Ids))
    }
}
