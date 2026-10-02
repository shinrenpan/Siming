import Foundation
import ModelsR4
@testable import SimingCore
import XCTest

final class TaskStoreTests: XCTestCase {
    var store: TaskStore!
    var patientStore: PatientStore!

    override func setUp() async throws {
        try await super.setUp()
        try await requireDatabase()
        store        = try await TestDatabase.shared.makeTaskStore()
        patientStore = try await TestDatabase.shared.makePatientStore()
    }

    private func newPatientRef(_ family: String) async throws -> String {
        "Patient/" + (try await patientStore.create(makePatient(family: family)).id)
    }

    private func ids(_ result: TaskStore.SearchResult) -> Set<String> {
        Set(result.entries.map(\.id))
    }

    // ── CRUD ──────────────────────────────────────────────────────────────────

    func testCreate_assignsIdAndVersionOne() async throws {
        let ref = try await newPatientRef("TaskCreate")
        let result = try await store.create(makeTask(forRef: ref))
        XCTAssertFalse(result.id.isEmpty)
        XCTAssertEqual(result.versionId, 1)
    }

    func testRead_keepsInputAnswers() async throws {
        let ref = try await newPatientRef("TaskRead")
        let created = try await store.create(makeTask(forRef: ref, code: "contact-request"))
        let row = try await store.read(id: created.id)
        let task = try JSONDecoder().decode(ModelsR4.Task.self, from: row.jsonData)
        XCTAssertEqual(task.status.value?.rawValue, "requested")
        XCTAssertEqual(task.`for`?.reference?.value?.string, ref)
        XCTAssertEqual(task.input?.count, 1)
    }

    func testUpdate_requestedToCompleted() async throws {
        let ref = try await newPatientRef("TaskUpdate")
        let created = try await store.create(makeTask(forRef: ref, status: "requested"))
        let result = try await store.update(id: created.id, task: makeTask(forRef: ref, status: "completed"), ifMatch: 1)
        XCTAssertEqual(result.versionId, 2)
        let row = try await store.read(id: created.id)
        let task = try JSONDecoder().decode(ModelsR4.Task.self, from: row.jsonData)
        XCTAssertEqual(task.status.value?.rawValue, "completed")

        // The old status must leave the index — otherwise status=requested keeps matching.
        let stale = try await store.search(query: TaskSearchQuery(status: [.init(system: nil, code: "requested")], patient: ref))
        XCTAssertTrue(stale.entries.isEmpty)
    }

    func testUpdate_staleIfMatch_throws() async throws {
        let ref = try await newPatientRef("TaskIfMatch")
        let created = try await store.create(makeTask(forRef: ref))
        _ = try await store.update(id: created.id, task: makeTask(forRef: ref, status: "accepted"), ifMatch: 1)
        do {
            _ = try await store.update(id: created.id, task: makeTask(forRef: ref, status: "completed"), ifMatch: 1)
            XCTFail("Expected version conflict")
        } catch FHIRServerError.versionConflict { }
    }

    func testDelete_and_goneOnRead() async throws {
        let ref = try await newPatientRef("TaskDelete")
        let created = try await store.create(makeTask(forRef: ref))
        try await store.delete(id: created.id, ifMatch: nil)
        do {
            _ = try await store.read(id: created.id)
            XCTFail("Expected gone error")
        } catch FHIRServerError.gone { }
    }

    // ── Search: the YTLab M06 query ───────────────────────────────────────────

    func testSearch_patientCodeStatus_matchesOnlyOpenContactRequest() async throws {
        let ref   = try await newPatientRef("TaskM06")
        let other = try await newPatientRef("TaskM06Other")
        let open  = try await store.create(makeTask(forRef: ref, code: "contact-request"))
        _ = try await store.create(makeTask(forRef: ref, status: "completed", code: "contact-request"))
        _ = try await store.create(makeTask(forRef: ref, code: "other-type"))
        _ = try await store.create(makeTask(forRef: other, code: "contact-request"))

        let query = TaskSearchQuery(
            status: [.init(system: nil, code: "requested")],
            code: [.init(system: "urn:ytlab:task-type", code: "contact-request")],
            patient: ref, count: 10)
        let result = try await store.search(query: query)
        XCTAssertEqual(ids(result), [open.id])
        XCTAssertEqual(result.total, 1)
    }

    func testSearch_summaryCount_sharesFilters() async throws {
        let ref = try await newPatientRef("TaskCount")
        _ = try await store.create(makeTask(forRef: ref, code: "contact-request"))
        _ = try await store.create(makeTask(forRef: ref, status: "completed", code: "contact-request"))

        let query = TaskSearchQuery(status: [.init(system: nil, code: "requested")], patient: ref, count: 0)
        let result = try await store.search(query: query)
        XCTAssertTrue(result.entries.isEmpty)
        XCTAssertEqual(result.total, 1)
    }

    // ── Search: patient vs subject ────────────────────────────────────────────

    func testSearch_patient_onlyIndexesPatientTypedFor() async throws {
        let groupRef = "Group/\(UUID().uuidString.lowercased())"
        let created = try await store.create(makeTask(forRef: groupRef))

        let bySubject = try await store.search(query: TaskSearchQuery(subject: groupRef))
        XCTAssertEqual(ids(bySubject), [created.id])
        let byPatient = try await store.search(query: TaskSearchQuery(patient: groupRef))
        XCTAssertTrue(byPatient.entries.isEmpty)
    }

    func testSearch_missingPatient() async throws {
        let owner = "Practitioner/\(UUID().uuidString.lowercased())"
        let noFor = try await store.create(makeTask(forRef: nil, owner: owner))
        _ = try await store.create(makeTask(forRef: try await newPatientRef("TaskMissing"), owner: owner))

        let result = try await store.search(query: TaskSearchQuery(owner: owner, missing: ["patient": true]))
        XCTAssertEqual(ids(result), [noFor.id])
    }

    // ── Search: other params ──────────────────────────────────────────────────

    func testSearch_intentAndStatusNot() async throws {
        let ref = try await newPatientRef("TaskIntent")
        let proposal = try await store.create(makeTask(forRef: ref, intent: "proposal"))
        _ = try await store.create(makeTask(forRef: ref, intent: "order"))
        _ = try await store.create(makeTask(forRef: ref, status: "cancelled", intent: "proposal"))

        let query = TaskSearchQuery(
            statusNot: [.init(system: nil, code: "cancelled")],
            intent: [.init(system: nil, code: "proposal")], patient: ref)
        let queryResult = try await store.search(query: query)
        XCTAssertEqual(ids(queryResult), [proposal.id])
    }

    func testSearch_intentWithSystem() async throws {
        let ref = try await newPatientRef("TaskIntentSys")
        let order = try await store.create(makeTask(forRef: ref, intent: "order"))
        let unknown = try await store.create(makeTask(forRef: ref, intent: "unknown"))

        let byRequest = TaskSearchQuery(intent: [.init(system: "http://hl7.org/fhir/request-intent", code: "order")], patient: ref)
        let byRequestResult = try await store.search(query: byRequest)
        XCTAssertEqual(ids(byRequestResult), [order.id])
        let byTask = TaskSearchQuery(intent: [.init(system: "http://hl7.org/fhir/task-intent", code: "unknown")], patient: ref)
        let byTaskResult = try await store.search(query: byTask)
        XCTAssertEqual(ids(byTaskResult), [unknown.id])
    }

    func testSearch_businessStatus() async throws {
        let ref = try await newPatientRef("TaskBiz")
        let called = try await store.create(makeTask(forRef: ref, businessStatus: "called-back"))
        _ = try await store.create(makeTask(forRef: ref, businessStatus: "waiting"))

        let query = TaskSearchQuery(businessStatus: [.init(system: "urn:test:biz", code: "called-back")], patient: ref)
        let queryResult = try await store.search(query: query)
        XCTAssertEqual(ids(queryResult), [called.id])
    }

    func testSearch_authoredOnAndModified() async throws {
        let ref = try await newPatientRef("TaskDates")
        let recent = try await store.create(makeTask(forRef: ref, authoredOn: "2026-09-20T10:00:00Z", lastModified: "2026-09-21T10:00:00Z"))
        _ = try await store.create(makeTask(forRef: ref, authoredOn: "2025-01-01T10:00:00Z", lastModified: "2025-01-02T10:00:00Z"))

        let byAuthored = TaskSearchQuery(authoredOn: [try XCTUnwrap(.parse("ge2026-01-01"))], patient: ref)
        let byAuthoredResult = try await store.search(query: byAuthored)
        XCTAssertEqual(ids(byAuthoredResult), [recent.id])
        let byModified = TaskSearchQuery(modified: [try XCTUnwrap(.parse("ge2026-01-01"))], patient: ref)
        let byModifiedResult = try await store.search(query: byModified)
        XCTAssertEqual(ids(byModifiedResult), [recent.id])
    }

    func testSearch_period() async throws {
        let ref = try await newPatientRef("TaskPeriod")
        let inside = try await store.create(makeTask(forRef: ref, periodStart: "2026-03-01", periodEnd: "2026-03-10"))
        _ = try await store.create(makeTask(forRef: ref, periodStart: "2026-05-01", periodEnd: "2026-05-10"))

        let query = TaskSearchQuery(period: [try XCTUnwrap(.parse("lt2026-04-01"))], patient: ref)
        let queryResult = try await store.search(query: query)
        XCTAssertEqual(ids(queryResult), [inside.id])
    }

    func testSearch_sortByAuthoredOn() async throws {
        let ref = try await newPatientRef("TaskSort")
        let older = try await store.create(makeTask(forRef: ref, authoredOn: "2024-01-01"))
        let newer = try await store.create(makeTask(forRef: ref, authoredOn: "2026-01-01"))

        let query = TaskSearchQuery(patient: ref, count: 10, sortKeys: TaskSearchQuery.parseSortKeys("-authored-on"))
        let result = try await store.search(query: query)
        XCTAssertEqual(result.entries.map(\.id), [newer.id, older.id])
    }

    func testSearch_pagination_noDuplicatesAcrossPages() async throws {
        let ref = try await newPatientRef("TaskPage")
        for _ in 0..<5 { _ = try await store.create(makeTask(forRef: ref)) }

        var query = TaskSearchQuery(patient: ref, count: 2)
        let page1 = try await store.search(query: query)
        XCTAssertEqual(page1.entries.count, 2)
        XCTAssertNotNil(page1.nextCursor)
        query.cursor = page1.nextCursor
        let page2 = try await store.search(query: query)
        XCTAssertEqual(page2.entries.count, 2)
        XCTAssertTrue(ids(page1).isDisjoint(with: ids(page2)))
    }

    // ── History ───────────────────────────────────────────────────────────────

    func testHistory_instanceHistory() async throws {
        let ref = try await newPatientRef("TaskHist")
        let created = try await store.create(makeTask(forRef: ref))
        _ = try await store.update(id: created.id, task: makeTask(forRef: ref, status: "completed"), ifMatch: nil)

        let history = try await store.history(id: created.id)
        XCTAssertEqual(history.map(\.versionId), [2, 1])
    }
}
