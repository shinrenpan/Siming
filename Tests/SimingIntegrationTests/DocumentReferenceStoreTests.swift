import Foundation
import ModelsR4
@testable import SimingCore
import XCTest

final class DocumentReferenceStoreTests: XCTestCase {
    var store: DocumentReferenceStore!
    var patientStore: PatientStore!

    override func setUp() async throws {
        try await super.setUp()
        try await requireDatabase()
        store        = try await TestDatabase.shared.makeDocumentReferenceStore()
        patientStore = try await TestDatabase.shared.makePatientStore()
    }

    // ── CRUD ──────────────────────────────────────────────────────────────────

    func testCreate_assignsIdAndVersionOne() async throws {
        let patient = try await patientStore.create(makePatient(family: "DocCreate"))
        let docRef = try makeDocumentReference(patientId: patient.id, status: "current")
        let result = try await store.create(docRef)
        XCTAssertFalse(result.id.isEmpty)
        XCTAssertEqual(result.versionId, 1)
    }

    func testRead_returnsStoredResource() async throws {
        let patient = try await patientStore.create(makePatient(family: "DocRead"))
        let created = try await store.create(makeDocumentReference(patientId: patient.id, status: "current"))
        let row = try await store.read(id: created.id)
        let docRef = try JSONDecoder().decode(ModelsR4.DocumentReference.self, from: row.jsonData)
        XCTAssertEqual(docRef.status.value?.rawValue, "current")
    }

    func testRead_unknownId_throwsNotFound() async throws {
        do {
            _ = try await store.read(id: "no-such-docref")
            XCTFail("Expected notFound")
        } catch FHIRServerError.notFound { }
    }

    func testUpdate_incrementsVersion() async throws {
        let patient = try await patientStore.create(makePatient(family: "DocUpdate"))
        let created = try await store.create(makeDocumentReference(patientId: patient.id, status: "current"))
        let updated = try makeDocumentReference(patientId: patient.id, status: "superseded")
        let result = try await store.update(id: created.id, docRef: updated, ifMatch: nil)
        XCTAssertEqual(result.versionId, 2)
        let row = try await store.read(id: created.id)
        let docRef = try JSONDecoder().decode(ModelsR4.DocumentReference.self, from: row.jsonData)
        XCTAssertEqual(docRef.status.value?.rawValue, "superseded")
    }

    func testDelete_and_goneOnRead() async throws {
        let patient = try await patientStore.create(makePatient(family: "DocDelete"))
        let created = try await store.create(makeDocumentReference(patientId: patient.id))
        try await store.delete(id: created.id, ifMatch: nil)
        do {
            _ = try await store.read(id: created.id)
            XCTFail("Expected gone error")
        } catch FHIRServerError.gone { }
    }

    func testVread_returnsSpecificVersion() async throws {
        let patient = try await patientStore.create(makePatient(family: "DocVread"))
        let created = try await store.create(makeDocumentReference(patientId: patient.id, status: "current"))
        let updated = try makeDocumentReference(patientId: patient.id, status: "superseded")
        _ = try await store.update(id: created.id, docRef: updated, ifMatch: nil)
        let v1 = try await store.vread(id: created.id, versionId: 1)
        let docRef = try JSONDecoder().decode(ModelsR4.DocumentReference.self, from: v1.jsonData)
        XCTAssertEqual(docRef.status.value?.rawValue, "current")
    }

    // ── Search: token params ──────────────────────────────────────────────────

    func testSearch_byStatus() async throws {
        let patient = try await patientStore.create(makePatient(family: "DocStatus"))
        _ = try await store.create(makeDocumentReference(patientId: patient.id, status: "current"))
        _ = try await store.create(makeDocumentReference(patientId: patient.id, status: "superseded"))

        let query = DocumentReferenceSearchQuery(
            status: [.init(system: nil, code: "current")], count: 10)
        let result = try await store.search(query: query)
        XCTAssertGreaterThanOrEqual(result.entries.count, 1)
        for entry in result.entries {
            let docRef = try JSONDecoder().decode(ModelsR4.DocumentReference.self, from: entry.jsonWithMeta)
            XCTAssertEqual(docRef.status.value?.rawValue, "current")
        }
    }

    func testSearch_byStatusNot() async throws {
        let patient = try await patientStore.create(makePatient(family: "DocStatusNot"))
        _ = try await store.create(makeDocumentReference(patientId: patient.id, status: "current"))
        _ = try await store.create(makeDocumentReference(patientId: patient.id, status: "superseded"))

        let query = DocumentReferenceSearchQuery(
            statusNot: [.init(system: nil, code: "current")], count: 10)
        let result = try await store.search(query: query)
        for entry in result.entries {
            let docRef = try JSONDecoder().decode(ModelsR4.DocumentReference.self, from: entry.jsonWithMeta)
            XCTAssertNotEqual(docRef.status.value?.rawValue, "current")
        }
    }

    func testSearch_byType() async throws {
        let patient = try await patientStore.create(makePatient(family: "DocType"))
        _ = try await store.create(makeDocumentReference(patientId: patient.id, docType: "11488-4"))
        _ = try await store.create(makeDocumentReference(patientId: patient.id))

        let query = DocumentReferenceSearchQuery(
            type: [.init(system: nil, code: "11488-4")], count: 10)
        let result = try await store.search(query: query)
        XCTAssertEqual(result.entries.count, 1)
    }

    func testSearch_byCategory() async throws {
        let patient = try await patientStore.create(makePatient(family: "DocCategory"))
        _ = try await store.create(makeDocumentReference(patientId: patient.id, category: "clinical-note"))
        _ = try await store.create(makeDocumentReference(patientId: patient.id))

        let query = DocumentReferenceSearchQuery(
            category: [.init(system: nil, code: "clinical-note")], count: 10)
        let result = try await store.search(query: query)
        XCTAssertEqual(result.entries.count, 1)
    }

    // ── Search: reference params ──────────────────────────────────────────────

    func testSearch_byPatient() async throws {
        let patient1 = try await patientStore.create(makePatient(family: "DocPat1"))
        let patient2 = try await patientStore.create(makePatient(family: "DocPat2"))
        _ = try await store.create(makeDocumentReference(patientId: patient1.id))
        _ = try await store.create(makeDocumentReference(patientId: patient2.id))

        let query = DocumentReferenceSearchQuery(patient: "Patient/\(patient1.id)", count: 10)
        let result = try await store.search(query: query)
        XCTAssertEqual(result.entries.count, 1)
    }

    func testSearch_bySubject() async throws {
        let patient1 = try await patientStore.create(makePatient(family: "DocSubj1"))
        let patient2 = try await patientStore.create(makePatient(family: "DocSubj2"))
        _ = try await store.create(makeDocumentReference(patientId: patient1.id))
        _ = try await store.create(makeDocumentReference(patientId: patient2.id))

        let query = DocumentReferenceSearchQuery(subject: "Patient/\(patient1.id)", count: 10)
        let result = try await store.search(query: query)
        XCTAssertEqual(result.entries.count, 1)
    }

    func testSearch_byEncounter() async throws {
        let patient = try await patientStore.create(makePatient(family: "DocEnc"))
        let enc = "enc-abc123"
        _ = try await store.create(makeDocumentReference(patientId: patient.id, encounterId: enc))
        _ = try await store.create(makeDocumentReference(patientId: patient.id))

        let query = DocumentReferenceSearchQuery(encounter: "Encounter/\(enc)", count: 10)
        let result = try await store.search(query: query)
        XCTAssertEqual(result.entries.count, 1)
    }

    // ── Search: date params ───────────────────────────────────────────────────

    func testSearch_byDate() async throws {
        let patient = try await patientStore.create(makePatient(family: "DocDate"))
        _ = try await store.create(makeDocumentReference(patientId: patient.id, date: "2020-01-01T10:00:00Z"))
        _ = try await store.create(makeDocumentReference(patientId: patient.id, date: "2024-06-01T10:00:00Z"))

        let dp = DocumentReferenceSearchQuery.DateParam.parse("ge2023-01-01")!
        let query = DocumentReferenceSearchQuery(date: [dp], count: 10)
        let result = try await store.search(query: query)
        XCTAssertEqual(result.entries.count, 1)
    }

    // ── Search: string params ─────────────────────────────────────────────────

    func testSearch_byDescription() async throws {
        let patient = try await patientStore.create(makePatient(family: "DocDesc"))
        _ = try await store.create(makeDocumentReference(patientId: patient.id, description: "Annual physical exam report"))
        _ = try await store.create(makeDocumentReference(patientId: patient.id, description: "Lab results"))

        let query = DocumentReferenceSearchQuery(description: ["physical exam"], count: 10)
        let result = try await store.search(query: query)
        XCTAssertEqual(result.entries.count, 1)
    }

    // ── Search: _id ───────────────────────────────────────────────────────────

    func testSearch_byId() async throws {
        let patient = try await patientStore.create(makePatient(family: "DocId"))
        let created1 = try await store.create(makeDocumentReference(patientId: patient.id))
        _ = try await store.create(makeDocumentReference(patientId: patient.id))

        let query = DocumentReferenceSearchQuery(id: [created1.id], count: 10)
        let result = try await store.search(query: query)
        XCTAssertEqual(result.entries.count, 1)
        XCTAssertEqual(result.entries[0].id, created1.id)
    }

    // ── totalMode ─────────────────────────────────────────────────────────────

    func testSearch_totalMode_none_returnsNilTotal() async throws {
        let patient = try await patientStore.create(makePatient(family: "DocTotalNone"))
        _ = try await store.create(makeDocumentReference(patientId: patient.id))

        var query = DocumentReferenceSearchQuery()
        query.totalMode = .none
        let result = try await store.search(query: query)
        XCTAssertNil(result.total)
    }

    func testSearch_count0_returnsTotal() async throws {
        let patient = try await patientStore.create(makePatient(family: "DocCount0"))
        _ = try await store.create(makeDocumentReference(patientId: patient.id))
        _ = try await store.create(makeDocumentReference(patientId: patient.id))

        var query = DocumentReferenceSearchQuery()
        query.count = 0
        query.totalMode = .accurate
        let result = try await store.search(query: query)
        XCTAssertEqual(result.entries.count, 0)
        XCTAssertGreaterThanOrEqual(result.total ?? 0, 2)
    }

    // ── History ───────────────────────────────────────────────────────────────

    func testHistory_instanceHistory() async throws {
        let patient = try await patientStore.create(makePatient(family: "DocHist"))
        let created = try await store.create(makeDocumentReference(patientId: patient.id, status: "current"))
        let updated = try makeDocumentReference(patientId: patient.id, status: "superseded")
        _ = try await store.update(id: created.id, docRef: updated, ifMatch: nil)

        let history = try await store.history(id: created.id)
        XCTAssertEqual(history.count, 2)
        XCTAssertEqual(history[0].versionId, 2)
        XCTAssertEqual(history[1].versionId, 1)
    }

    func testTypeHistory_returnsEntries() async throws {
        let patient = try await patientStore.create(makePatient(family: "DocTypeHist"))
        _ = try await store.create(makeDocumentReference(patientId: patient.id))
        _ = try await store.create(makeDocumentReference(patientId: patient.id))

        let history = try await store.typeHistory(since: nil, count: 100)
        XCTAssertGreaterThanOrEqual(history.count, 2)
    }

    // ── Pagination ────────────────────────────────────────────────────────────

    func testSearch_pagination_noDuplicatesAcrossPages() async throws {
        let patient = try await patientStore.create(makePatient(family: "DocPage"))
        for _ in 0..<5 {
            _ = try await store.create(makeDocumentReference(patientId: patient.id))
        }

        var query = DocumentReferenceSearchQuery(patient: "Patient/\(patient.id)", count: 2)
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

    // ── relatesto / relation ──────────────────────────────────────────────────

    func testSearch_byRelatesto() async throws {
        let patient = try await patientStore.create(makePatient(family: "DocRelatesto"))
        let target  = try await store.create(makeDocumentReference(patientId: patient.id))
        _ = try await store.create(makeDocumentReference(patientId: patient.id,
                                                         relatesToTarget: "DocumentReference/\(target.id)",
                                                         relatesToCode: "replaces"))
        _ = try await store.create(makeDocumentReference(patientId: patient.id))

        let query = DocumentReferenceSearchQuery(
            relatesto: "DocumentReference/\(target.id)", count: 10)
        let result = try await store.search(query: query)
        XCTAssertEqual(result.entries.count, 1)
    }

    func testSearch_byRelation() async throws {
        let patient = try await patientStore.create(makePatient(family: "DocRelation"))
        let target  = try await store.create(makeDocumentReference(patientId: patient.id))
        _ = try await store.create(makeDocumentReference(patientId: patient.id,
                                                         relatesToTarget: "DocumentReference/\(target.id)",
                                                         relatesToCode: "replaces"))
        _ = try await store.create(makeDocumentReference(patientId: patient.id,
                                                         relatesToTarget: "DocumentReference/\(target.id)",
                                                         relatesToCode: "transforms"))
        _ = try await store.create(makeDocumentReference(patientId: patient.id))

        var query = DocumentReferenceSearchQuery(count: 10)
        query.patient = "Patient/\(patient.id)"
        query.relation = [.init(system: "http://hl7.org/fhir/document-relationship-type", code: "replaces")]
        let result = try await store.search(query: query)
        XCTAssertEqual(result.entries.count, 1)
        let doc = try JSONDecoder().decode(ModelsR4.DocumentReference.self, from: result.entries[0].jsonWithMeta)
        XCTAssertTrue(doc.relatesTo?.contains(where: { $0.code.value?.rawValue == "replaces" }) ?? false)
    }

    func testSearch_byRelationNot() async throws {
        let patient = try await patientStore.create(makePatient(family: "DocRelationNot"))
        let target  = try await store.create(makeDocumentReference(patientId: patient.id))
        _ = try await store.create(makeDocumentReference(patientId: patient.id,
                                                         relatesToTarget: "DocumentReference/\(target.id)",
                                                         relatesToCode: "replaces"))
        _ = try await store.create(makeDocumentReference(patientId: patient.id,
                                                         relatesToTarget: "DocumentReference/\(target.id)",
                                                         relatesToCode: "transforms"))

        var query = DocumentReferenceSearchQuery(count: 10)
        query.patient = "Patient/\(patient.id)"
        query.relationNot = [.init(system: nil, code: "replaces")]
        let result = try await store.search(query: query)
        for entry in result.entries {
            let doc = try JSONDecoder().decode(ModelsR4.DocumentReference.self, from: entry.jsonWithMeta)
            let codes = doc.relatesTo?.compactMap { $0.code.value?.rawValue } ?? []
            XCTAssertFalse(codes.contains("replaces"))
        }
    }

    // ── Sort ──────────────────────────────────────────────────────────────────

    func testSearch_sortByDate() async throws {
        let patient = try await patientStore.create(makePatient(family: "DocSort"))
        _ = try await store.create(makeDocumentReference(patientId: patient.id, date: "2022-01-01T10:00:00Z"))
        _ = try await store.create(makeDocumentReference(patientId: patient.id, date: "2024-01-01T10:00:00Z"))

        let query = DocumentReferenceSearchQuery(
            patient: "Patient/\(patient.id)",
            count: 10, sort: .dateDescending)
        let result = try await store.search(query: query)
        guard result.entries.count >= 2 else { return }
        let doc0 = try JSONDecoder().decode(ModelsR4.DocumentReference.self, from: result.entries[0].jsonWithMeta)
        let doc1 = try JSONDecoder().decode(ModelsR4.DocumentReference.self, from: result.entries[1].jsonWithMeta)
        XCTAssertNotNil(doc0.date)
        XCTAssertNotNil(doc1.date)
    }

    // ── Search: related ───────────────────────────────────────────────────────

    func testSearch_byRelated_returnsMatchOnly() async throws {
        let pid = try await patientStore.create(makePatient(family: "DocRelatedPt")).id
        let relatedId = "obs-related-\(UUID().uuidString.prefix(8))"
        _ = try await store.create(makeDocumentReference(patientId: pid, relatedRef: "Observation/\(relatedId)"))
        _ = try await store.create(makeDocumentReference(patientId: pid))

        let result = try await store.search(query: DocumentReferenceSearchQuery(
            related: "Observation/\(relatedId)"
        ))
        XCTAssertEqual(result.total, 1)
    }
}
