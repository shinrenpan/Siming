import Foundation
import ModelsR4
@testable import SimingCore
import XCTest

final class ServiceRequestStoreTests: XCTestCase {
    var store: ServiceRequestStore!
    var patientStore: PatientStore!

    override func setUp() async throws {
        try await super.setUp()
        try await requireDatabase()
        store        = try await TestDatabase.shared.makeServiceRequestStore()
        patientStore = try await TestDatabase.shared.makePatientStore()
    }

    // ── CRUD ──────────────────────────────────────────────────────────────────

    func testCreate_assignsIdAndVersionOne() async throws {
        let patient = try await patientStore.create(makePatient(family: "SRCreate"))
        let sr = try makeServiceRequest(patientId: patient.id)
        let result = try await store.create(sr)
        XCTAssertFalse(result.id.isEmpty)
        XCTAssertEqual(result.versionId, 1)
    }

    func testRead_returnsStoredResource() async throws {
        let patient = try await patientStore.create(makePatient(family: "SRRead"))
        let created = try await store.create(makeServiceRequest(patientId: patient.id, status: "active"))
        let row = try await store.read(id: created.id)
        let sr = try JSONDecoder().decode(ModelsR4.ServiceRequest.self, from: row.jsonData)
        XCTAssertEqual(sr.status.value?.rawValue, "active")
    }

    func testRead_unknownId_throwsNotFound() async throws {
        do {
            _ = try await store.read(id: "no-such-sr")
            XCTFail("Expected notFound")
        } catch FHIRServerError.notFound { }
    }

    func testUpdate_incrementsVersion() async throws {
        let patient = try await patientStore.create(makePatient(family: "SRUpdate"))
        let created = try await store.create(makeServiceRequest(patientId: patient.id, status: "active"))
        let updated = try makeServiceRequest(patientId: patient.id, status: "completed")
        let result = try await store.update(id: created.id, sr: updated, ifMatch: nil)
        XCTAssertEqual(result.versionId, 2)
        let row = try await store.read(id: created.id)
        let sr = try JSONDecoder().decode(ModelsR4.ServiceRequest.self, from: row.jsonData)
        XCTAssertEqual(sr.status.value?.rawValue, "completed")
    }

    func testDelete_and_goneOnRead() async throws {
        let patient = try await patientStore.create(makePatient(family: "SRDelete"))
        let created = try await store.create(makeServiceRequest(patientId: patient.id))
        try await store.delete(id: created.id, ifMatch: nil)
        do {
            _ = try await store.read(id: created.id)
            XCTFail("Expected gone error")
        } catch FHIRServerError.gone { }
    }

    func testVread_returnsSpecificVersion() async throws {
        let patient = try await patientStore.create(makePatient(family: "SRVread"))
        let created = try await store.create(makeServiceRequest(patientId: patient.id, status: "active"))
        let updated = try makeServiceRequest(patientId: patient.id, status: "completed")
        _ = try await store.update(id: created.id, sr: updated, ifMatch: nil)
        let v1 = try await store.vread(id: created.id, versionId: 1)
        let sr = try JSONDecoder().decode(ModelsR4.ServiceRequest.self, from: v1.jsonData)
        XCTAssertEqual(sr.status.value?.rawValue, "active")
    }

    // ── Search: token params ──────────────────────────────────────────────────

    func testSearch_byStatus() async throws {
        let patient = try await patientStore.create(makePatient(family: "SRStatus"))
        _ = try await store.create(makeServiceRequest(patientId: patient.id, status: "active"))
        _ = try await store.create(makeServiceRequest(patientId: patient.id, status: "completed"))

        let query = ServiceRequestSearchQuery(
            status: [.init(system: nil, code: "active")], count: 10)
        let result = try await store.search(query: query)
        XCTAssertGreaterThanOrEqual(result.entries.count, 1)
        for entry in result.entries {
            let sr = try JSONDecoder().decode(ModelsR4.ServiceRequest.self, from: entry.jsonWithMeta)
            XCTAssertEqual(sr.status.value?.rawValue, "active")
        }
    }

    func testSearch_byStatusNot() async throws {
        let patient = try await patientStore.create(makePatient(family: "SRStatusNot"))
        _ = try await store.create(makeServiceRequest(patientId: patient.id, status: "active"))
        _ = try await store.create(makeServiceRequest(patientId: patient.id, status: "completed"))

        let query = ServiceRequestSearchQuery(
            statusNot: [.init(system: nil, code: "active")], count: 10)
        let result = try await store.search(query: query)
        for entry in result.entries {
            let sr = try JSONDecoder().decode(ModelsR4.ServiceRequest.self, from: entry.jsonWithMeta)
            XCTAssertNotEqual(sr.status.value?.rawValue, "active")
        }
    }

    func testSearch_byIntent() async throws {
        let patient = try await patientStore.create(makePatient(family: "SRIntent"))
        _ = try await store.create(makeServiceRequest(patientId: patient.id, intent: "order"))
        _ = try await store.create(makeServiceRequest(patientId: patient.id, intent: "plan"))

        let query = ServiceRequestSearchQuery(
            intent: [.init(system: nil, code: "order")], count: 10)
        let result = try await store.search(query: query)
        XCTAssertGreaterThanOrEqual(result.entries.count, 1)
        for entry in result.entries {
            let sr = try JSONDecoder().decode(ModelsR4.ServiceRequest.self, from: entry.jsonWithMeta)
            XCTAssertEqual(sr.intent.value?.rawValue, "order")
        }
    }

    func testSearch_byCode() async throws {
        let patient = try await patientStore.create(makePatient(family: "SRCode"))
        _ = try await store.create(makeServiceRequest(patientId: patient.id,
                                                       code: "73761001", codeSystem: "http://snomed.info/sct"))
        _ = try await store.create(makeServiceRequest(patientId: patient.id))

        let query = ServiceRequestSearchQuery(
            code: [.init(system: nil, code: "73761001")], count: 10)
        let result = try await store.search(query: query)
        XCTAssertEqual(result.entries.count, 1)
    }

    func testSearch_byCategory() async throws {
        let patient = try await patientStore.create(makePatient(family: "SRCategory"))
        _ = try await store.create(makeServiceRequest(patientId: patient.id,
                                                       category: "103693007", categorySystem: "http://snomed.info/sct"))
        _ = try await store.create(makeServiceRequest(patientId: patient.id))

        let query = ServiceRequestSearchQuery(
            category: [.init(system: nil, code: "103693007")], count: 10)
        let result = try await store.search(query: query)
        XCTAssertEqual(result.entries.count, 1)
    }

    // ── Search: reference params ──────────────────────────────────────────────

    func testSearch_byPatient() async throws {
        let patient1 = try await patientStore.create(makePatient(family: "SRPat1"))
        let patient2 = try await patientStore.create(makePatient(family: "SRPat2"))
        _ = try await store.create(makeServiceRequest(patientId: patient1.id))
        _ = try await store.create(makeServiceRequest(patientId: patient2.id))

        let query = ServiceRequestSearchQuery(patient: "Patient/\(patient1.id)", count: 10)
        let result = try await store.search(query: query)
        XCTAssertEqual(result.entries.count, 1)
    }

    func testSearch_bySubject() async throws {
        let patient1 = try await patientStore.create(makePatient(family: "SRSubj1"))
        let patient2 = try await patientStore.create(makePatient(family: "SRSubj2"))
        _ = try await store.create(makeServiceRequest(patientId: patient1.id))
        _ = try await store.create(makeServiceRequest(patientId: patient2.id))

        let query = ServiceRequestSearchQuery(subject: "Patient/\(patient1.id)", count: 10)
        let result = try await store.search(query: query)
        XCTAssertEqual(result.entries.count, 1)
    }

    func testSearch_byEncounter() async throws {
        let patient = try await patientStore.create(makePatient(family: "SREnc"))
        _ = try await store.create(makeServiceRequest(patientId: patient.id, encounterRef: "Encounter/enc-123"))
        _ = try await store.create(makeServiceRequest(patientId: patient.id))

        let query = ServiceRequestSearchQuery(encounter: "Encounter/enc-123", count: 10)
        let result = try await store.search(query: query)
        XCTAssertEqual(result.entries.count, 1)
    }

    // ── Search: date params ───────────────────────────────────────────────────

    func testSearch_byAuthoredDate() async throws {
        let patient = try await patientStore.create(makePatient(family: "SRAuthored"))
        _ = try await store.create(makeServiceRequest(patientId: patient.id, authoredOn: "2020-01-01"))
        _ = try await store.create(makeServiceRequest(patientId: patient.id, authoredOn: "2024-06-01"))

        let dp = ServiceRequestSearchQuery.DateParam.parse("ge2023-01-01")!
        let query = ServiceRequestSearchQuery(authored: [dp], count: 10)
        let result = try await store.search(query: query)
        XCTAssertEqual(result.entries.count, 1)
        let sr = try JSONDecoder().decode(ModelsR4.ServiceRequest.self, from: result.entries[0].jsonWithMeta)
        XCTAssertEqual(sr.authoredOn?.value?.description, "2024-06-01")
    }

    // ── Search: _id ───────────────────────────────────────────────────────────

    func testSearch_byId() async throws {
        let patient = try await patientStore.create(makePatient(family: "SRId"))
        let created1 = try await store.create(makeServiceRequest(patientId: patient.id))
        _ = try await store.create(makeServiceRequest(patientId: patient.id))

        let query = ServiceRequestSearchQuery(id: [created1.id], count: 10)
        let result = try await store.search(query: query)
        XCTAssertEqual(result.entries.count, 1)
        XCTAssertEqual(result.entries[0].id, created1.id)
    }

    // ── totalMode ─────────────────────────────────────────────────────────────

    func testSearch_totalMode_none_returnsNilTotal() async throws {
        let patient = try await patientStore.create(makePatient(family: "SRTotalNone"))
        _ = try await store.create(makeServiceRequest(patientId: patient.id))

        var query = ServiceRequestSearchQuery()
        query.totalMode = .none
        let result = try await store.search(query: query)
        XCTAssertNil(result.total)
    }

    func testSearch_count0_returnsTotal() async throws {
        let patient = try await patientStore.create(makePatient(family: "SRCount0"))
        _ = try await store.create(makeServiceRequest(patientId: patient.id))
        _ = try await store.create(makeServiceRequest(patientId: patient.id))

        var query = ServiceRequestSearchQuery()
        query.count = 0
        query.totalMode = .accurate
        let result = try await store.search(query: query)
        XCTAssertEqual(result.entries.count, 0)
        XCTAssertGreaterThanOrEqual(result.total ?? 0, 2)
    }

    // ── History ───────────────────────────────────────────────────────────────

    func testHistory_instanceHistory() async throws {
        let patient = try await patientStore.create(makePatient(family: "SRHist"))
        let created = try await store.create(makeServiceRequest(patientId: patient.id, status: "active"))
        let updated = try makeServiceRequest(patientId: patient.id, status: "completed")
        _ = try await store.update(id: created.id, sr: updated, ifMatch: nil)

        let history = try await store.history(id: created.id)
        XCTAssertEqual(history.count, 2)
        XCTAssertEqual(history[0].versionId, 2)
        XCTAssertEqual(history[1].versionId, 1)
    }

    func testTypeHistory_returnsEntries() async throws {
        let patient = try await patientStore.create(makePatient(family: "SRTypeHist"))
        _ = try await store.create(makeServiceRequest(patientId: patient.id))
        _ = try await store.create(makeServiceRequest(patientId: patient.id))

        let history = try await store.typeHistory(since: nil, count: 100)
        XCTAssertGreaterThanOrEqual(history.count, 2)
    }

    // ── Pagination ────────────────────────────────────────────────────────────

    func testSearch_pagination_noDuplicatesAcrossPages() async throws {
        let patient = try await patientStore.create(makePatient(family: "SRPage"))
        for _ in 0..<5 {
            _ = try await store.create(makeServiceRequest(patientId: patient.id))
        }

        var query = ServiceRequestSearchQuery(patient: "Patient/\(patient.id)", count: 2)
        let page1 = try await store.search(query: query)
        XCTAssertEqual(page1.entries.count, 2)
        XCTAssertNotNil(page1.nextCursor)

        query.cursor = page1.nextCursor
        let page2 = try await store.search(query: query)
        XCTAssertEqual(page2.entries.count, 2)

        let ids1 = Set(page1.entries.map(\.id))
        let ids2 = Set(page2.entries.map(\.id))
        XCTAssertTrue(ids1.isDisjoint(with: ids2))
    }

    // ── Sort ──────────────────────────────────────────────────────────────────

    func testSearch_sortByAuthored() async throws {
        let patient = try await patientStore.create(makePatient(family: "SRSort"))
        _ = try await store.create(makeServiceRequest(patientId: patient.id, authoredOn: "2022-01-01"))
        _ = try await store.create(makeServiceRequest(patientId: patient.id, authoredOn: "2024-01-01"))

        let query = ServiceRequestSearchQuery(
            patient: "Patient/\(patient.id)",
            count: 10, sortKeys: ServiceRequestSearchQuery.parseSortKeys("-authored"))
        let result = try await store.search(query: query)
        guard result.entries.count >= 2 else { return }
        let sr0 = try JSONDecoder().decode(ModelsR4.ServiceRequest.self, from: result.entries[0].jsonWithMeta)
        let sr1 = try JSONDecoder().decode(ModelsR4.ServiceRequest.self, from: result.entries[1].jsonWithMeta)
        XCTAssertEqual(sr0.authoredOn?.value?.description, "2024-01-01")
        XCTAssertEqual(sr1.authoredOn?.value?.description, "2022-01-01")
    }

    // ── Search: instantiates-uri ──────────────────────────────────────────────

    func testSearch_byInstantiatesUri_returnsMatchOnly() async throws {
        let pid = try await patientStore.create(makePatient(family: "SRInstUriPt")).id
        let uri = "http://example.com/protocol/\(UUID().uuidString.prefix(8))"
        _ = try await store.create(makeServiceRequest(patientId: pid, instantiatesUri: uri))
        _ = try await store.create(makeServiceRequest(patientId: pid))

        let result = try await store.search(query: ServiceRequestSearchQuery(
            instantiatesUri: [uri]
        ))
        XCTAssertEqual(result.total, 1)
    }

    // ── Search: instantiates-canonical ───────────────────────────────────────

    func testSearch_byInstantiatesCanonical_returnsMatchOnly() async throws {
        let pid = try await patientStore.create(makePatient(family: "SRInstCanPt")).id
        let url = "http://example.com/plandefinition/\(UUID().uuidString.prefix(8))"
        _ = try await store.create(makeServiceRequest(patientId: pid, instantiatesCanonical: url))
        _ = try await store.create(makeServiceRequest(patientId: pid))

        let result = try await store.search(query: ServiceRequestSearchQuery(
            instantiatesCanonical: [url]
        ))
        XCTAssertEqual(result.total, 1)
    }

    // ── Search: order-detail ──────────────────────────────────────────────────

    func testSearch_byOrderDetail_returnsMatchOnly() async throws {
        let pid = try await patientStore.create(makePatient(family: "SROrdDetPt")).id
        _ = try await store.create(makeServiceRequest(patientId: pid, orderDetailCode: "PROC001"))
        _ = try await store.create(makeServiceRequest(patientId: pid))

        let result = try await store.search(query: ServiceRequestSearchQuery(
            orderDetail: [.init(system: nil, code: "PROC001")]
        ))
        XCTAssertEqual(result.total, 1)
    }

    func testSearch_byOrderDetailNot_excludesCorrectly() async throws {
        let pid = try await patientStore.create(makePatient(family: "SROrdDetNotPt")).id
        _ = try await store.create(makeServiceRequest(patientId: pid, orderDetailCode: "PROC001"))
        _ = try await store.create(makeServiceRequest(patientId: pid, orderDetailCode: "PROC002"))

        let result = try await store.search(query: ServiceRequestSearchQuery(
            orderDetailNot: [.init(system: nil, code: "PROC001")]
        ))
        XCTAssertEqual(result.total, 1)
    }
}

// ── Helpers ───────────────────────────────────────────────────────────────────

private func makePatient(family: String) throws -> ModelsR4.Patient {
    let json = #"{"resourceType":"Patient","name":[{"family":"\#(family)","given":["Test"]}]}"#
    return try JSONDecoder().decode(ModelsR4.Patient.self, from: Data(json.utf8))
}
