import Foundation
import ModelsR4
@testable import SimingCore
import XCTest

final class QuestionnaireResponseStoreTests: XCTestCase {
    var store: QuestionnaireResponseStore!
    var patientStore: PatientStore!

    override func setUp() async throws {
        try await super.setUp()
        try await requireDatabase()
        store        = try await TestDatabase.shared.makeQuestionnaireResponseStore()
        patientStore = try await TestDatabase.shared.makePatientStore()
    }

    private func newPatientRef(_ family: String) async throws -> String {
        "Patient/" + (try await patientStore.create(makePatient(family: family)).id)
    }

    /// Unique per run — the test database is not wiped between runs.
    private func formURL() -> String { "urn:test:form:" + UUID().uuidString.lowercased() }

    private func ids(_ result: QuestionnaireResponseStore.SearchResult) -> Set<String> {
        Set(result.entries.map(\.id))
    }

    // ── CRUD ──────────────────────────────────────────────────────────────────

    func testCreate_keepsNestedItems() async throws {
        let ref = try await newPatientRef("QRCreate")
        let created = try await store.create(makeQuestionnaireResponse(subject: ref))
        XCTAssertEqual(created.versionId, 1)
        let row = try await store.read(id: created.id)
        let qr = try JSONDecoder().decode(QuestionnaireResponse.self, from: row.jsonData)
        XCTAssertEqual(qr.item?.first?.item?.count, 2)
        XCTAssertEqual(qr.item?.first?.item?.last?.linkId.value?.string, "symptoms.note")
    }

    func testUpdate_inProgressToCompleted() async throws {
        let ref = try await newPatientRef("QRUpdate")
        let created = try await store.create(makeQuestionnaireResponse(subject: ref, status: "in-progress"))
        let result = try await store.update(id: created.id,
                                            questionnaireResponse: makeQuestionnaireResponse(subject: ref, status: "completed"),
                                            ifMatch: 1)
        XCTAssertEqual(result.versionId, 2)
        let stale = try await store.search(query: QuestionnaireResponseSearchQuery(
            status: [.init(system: nil, code: "in-progress")], patient: ref))
        XCTAssertTrue(stale.entries.isEmpty)
    }

    func testDelete_and_goneOnRead() async throws {
        let ref = try await newPatientRef("QRDelete")
        let created = try await store.create(makeQuestionnaireResponse(subject: ref))
        try await store.delete(id: created.id, ifMatch: nil)
        do {
            _ = try await store.read(id: created.id)
            XCTFail("Expected gone error")
        } catch FHIRServerError.gone { }
    }

    // ── Search ────────────────────────────────────────────────────────────────

    func testSearch_patientOnlyMatchesPatientSubject() async throws {
        let ref = try await newPatientRef("QRPatient")
        let forPatient = try await store.create(makeQuestionnaireResponse(subject: ref))
        let groupRef = "Group/" + UUID().uuidString.lowercased()
        let forGroup = try await store.create(makeQuestionnaireResponse(subject: groupRef))

        let byPatient = try await store.search(query: QuestionnaireResponseSearchQuery(patient: ref))
        XCTAssertEqual(ids(byPatient), [forPatient.id])
        let byGroupPatient = try await store.search(query: QuestionnaireResponseSearchQuery(patient: groupRef))
        XCTAssertTrue(byGroupPatient.entries.isEmpty)
        let bySubject = try await store.search(query: QuestionnaireResponseSearchQuery(subject: groupRef))
        XCTAssertEqual(ids(bySubject), [forGroup.id])
    }

    func testSearch_questionnaire_unversionedMatchesEveryVersion() async throws {
        let ref = try await newPatientRef("QRCanonical")
        let url = formURL()
        let v1 = try await store.create(makeQuestionnaireResponse(subject: ref, questionnaire: "\(url)|1.0"))
        let v2 = try await store.create(makeQuestionnaireResponse(subject: ref, questionnaire: "\(url)|2.0"))
        let bare = try await store.create(makeQuestionnaireResponse(subject: ref, questionnaire: url))

        let all = try await store.search(query: QuestionnaireResponseSearchQuery(questionnaire: [url]))
        XCTAssertEqual(ids(all), [v1.id, v2.id, bare.id])
        let onlyV1 = try await store.search(query: QuestionnaireResponseSearchQuery(questionnaire: ["\(url)|1.0"]))
        XCTAssertEqual(ids(onlyV1), [v1.id])
    }

    func testSearch_authoredRange() async throws {
        let ref = try await newPatientRef("QRAuthored")
        let early = try await store.create(makeQuestionnaireResponse(subject: ref, authored: "2026-09-01T09:00:00+08:00"))
        let late  = try await store.create(makeQuestionnaireResponse(subject: ref, authored: "2026-10-01T09:00:00+08:00"))
        let ge = try XCTUnwrap(QuestionnaireResponseSearchQuery.DateParam.parse("ge2026-09-15"))
        let result = try await store.search(query: QuestionnaireResponseSearchQuery(authored: [ge], patient: ref))
        XCTAssertEqual(ids(result), [late.id])
        XCTAssertFalse(ids(result).contains(early.id))
    }

    func testSearch_identifierAndAuthor() async throws {
        let ref = try await newPatientRef("QRIdent")
        let code = UUID().uuidString.lowercased()
        let created = try await store.create(makeQuestionnaireResponse(subject: ref, author: ref, identifier: code))
        let byIdent = try await store.search(query: QuestionnaireResponseSearchQuery(
            identifier: QuestionnaireResponseSearchQuery.IdentifierParam.parseList("urn:test:qr|\(code)")))
        XCTAssertEqual(ids(byIdent), [created.id])
        let byAuthor = try await store.search(query: QuestionnaireResponseSearchQuery(author: ref))
        XCTAssertEqual(ids(byAuthor), [created.id])
    }

    func testSearch_itemSubject() async throws {
        let ref = try await newPatientRef("QRItemSubject")
        let about = try await newPatientRef("QRItemSubjectAbout")
        let created = try await store.create(makeQuestionnaireResponse(subject: ref, itemSubject: about))
        _ = try await store.create(makeQuestionnaireResponse(subject: ref))
        let result = try await store.search(query: QuestionnaireResponseSearchQuery(itemSubject: about))
        XCTAssertEqual(ids(result), [created.id])
    }

    func testSearch_countOnly() async throws {
        let ref = try await newPatientRef("QRCount")
        _ = try await store.create(makeQuestionnaireResponse(subject: ref))
        _ = try await store.create(makeQuestionnaireResponse(subject: ref))
        let result = try await store.search(query: QuestionnaireResponseSearchQuery(patient: ref, count: 0))
        XCTAssertEqual(result.total, 2)
        XCTAssertTrue(result.entries.isEmpty)
    }

    func testTransactionPrepare_acceptsQuestionnaireResponse() throws {
        let data = try JSONEncoder().encode(makeQuestionnaireResponse(subject: "Patient/x"))
        XCTAssertNoThrow(try prepareEntryForWrite(resourceType: "QuestionnaireResponse", id: "qr-tx-1",
                                                  data: data, terminology: .empty))
    }
}
