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
        let obs = try JSONDecoder().decode(Observation.self, from: read.jsonData)
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
            (try? JSONDecoder().decode(Observation.self, from: entry.jsonWithMeta))?
                .subject?.reference?.value?.string == "Patient/\(pid1)"
        })
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
}
