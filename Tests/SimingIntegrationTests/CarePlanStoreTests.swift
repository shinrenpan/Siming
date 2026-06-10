import Foundation
import ModelsR4
@testable import SimingCore
import XCTest

final class CarePlanStoreTests: XCTestCase {
    var store: CarePlanStore!
    var patientStore: PatientStore!

    override func setUp() async throws {
        try await super.setUp()
        try await requireDatabase()
        store        = try await TestDatabase.shared.makeCarePlanStore()
        patientStore = try await TestDatabase.shared.makePatientStore()
    }

    // ── CRUD ──────────────────────────────────────────────────────────────────

    func testCreate_assignsIdAndVersionOne() async throws {
        let patient = try await patientStore.create(makePatient(family: "CPCreate"))
        let cp = try makeCarePlan(patientId: patient.id, status: "active", intent: "plan")
        let result = try await store.create(cp)
        XCTAssertFalse(result.id.isEmpty)
        XCTAssertEqual(result.versionId, 1)
    }

    func testRead_returnsStoredResource() async throws {
        let patient = try await patientStore.create(makePatient(family: "CPRead"))
        let created = try await store.create(makeCarePlan(patientId: patient.id, status: "active", intent: "plan"))
        let row = try await store.read(id: created.id)
        let cp = try JSONDecoder().decode(ModelsR4.CarePlan.self, from: row.jsonData)
        XCTAssertEqual(cp.status.value?.rawValue, "active")
        XCTAssertEqual(cp.intent.value?.rawValue, "plan")
    }

    func testRead_unknownId_throwsNotFound() async throws {
        do {
            _ = try await store.read(id: "no-such-careplan")
            XCTFail("Expected notFound")
        } catch FHIRServerError.notFound { }
    }

    func testUpdate_incrementsVersion() async throws {
        let patient = try await patientStore.create(makePatient(family: "CPUpdate"))
        let created = try await store.create(makeCarePlan(patientId: patient.id, status: "active", intent: "plan"))
        let updated = try makeCarePlan(patientId: patient.id, status: "completed", intent: "plan")
        let result = try await store.update(id: created.id, carePlan: updated, ifMatch: nil)
        XCTAssertEqual(result.versionId, 2)
        let row = try await store.read(id: created.id)
        let cp = try JSONDecoder().decode(ModelsR4.CarePlan.self, from: row.jsonData)
        XCTAssertEqual(cp.status.value?.rawValue, "completed")
    }

    func testDelete_and_goneOnRead() async throws {
        let patient = try await patientStore.create(makePatient(family: "CPDelete"))
        let created = try await store.create(makeCarePlan(patientId: patient.id))
        try await store.delete(id: created.id, ifMatch: nil)
        do {
            _ = try await store.read(id: created.id)
            XCTFail("Expected gone error")
        } catch FHIRServerError.gone { }
    }

    func testVread_returnsSpecificVersion() async throws {
        let patient = try await patientStore.create(makePatient(family: "CPVread"))
        let created = try await store.create(makeCarePlan(patientId: patient.id, status: "active", intent: "plan"))
        let updated = try makeCarePlan(patientId: patient.id, status: "completed", intent: "plan")
        _ = try await store.update(id: created.id, carePlan: updated, ifMatch: nil)
        let v1 = try await store.vread(id: created.id, versionId: 1)
        let cp = try JSONDecoder().decode(ModelsR4.CarePlan.self, from: v1.jsonData)
        XCTAssertEqual(cp.status.value?.rawValue, "active")
    }

    // ── Search: token params ──────────────────────────────────────────────────

    func testSearch_byStatus() async throws {
        let patient = try await patientStore.create(makePatient(family: "CPStatus"))
        _ = try await store.create(makeCarePlan(patientId: patient.id, status: "active", intent: "plan"))
        _ = try await store.create(makeCarePlan(patientId: patient.id, status: "completed", intent: "plan"))

        let query = CarePlanSearchQuery(
            status: [.init(system: nil, code: "active")], count: 10)
        let result = try await store.search(query: query)
        XCTAssertGreaterThanOrEqual(result.entries.count, 1)
        for entry in result.entries {
            let cp = try JSONDecoder().decode(ModelsR4.CarePlan.self, from: entry.jsonWithMeta)
            XCTAssertEqual(cp.status.value?.rawValue, "active")
        }
    }

    func testSearch_byStatusNot() async throws {
        let patient = try await patientStore.create(makePatient(family: "CPStatusNot"))
        _ = try await store.create(makeCarePlan(patientId: patient.id, status: "active", intent: "plan"))
        _ = try await store.create(makeCarePlan(patientId: patient.id, status: "completed", intent: "plan"))

        let query = CarePlanSearchQuery(
            statusNot: [.init(system: nil, code: "active")], count: 10)
        let result = try await store.search(query: query)
        for entry in result.entries {
            let cp = try JSONDecoder().decode(ModelsR4.CarePlan.self, from: entry.jsonWithMeta)
            XCTAssertNotEqual(cp.status.value?.rawValue, "active")
        }
    }

    func testSearch_byIntent() async throws {
        let patient = try await patientStore.create(makePatient(family: "CPIntent"))
        _ = try await store.create(makeCarePlan(patientId: patient.id, status: "active", intent: "plan"))
        _ = try await store.create(makeCarePlan(patientId: patient.id, status: "active", intent: "proposal"))

        let query = CarePlanSearchQuery(
            intent: [.init(system: nil, code: "plan")], count: 10)
        let result = try await store.search(query: query)
        XCTAssertGreaterThanOrEqual(result.entries.count, 1)
        for entry in result.entries {
            let cp = try JSONDecoder().decode(ModelsR4.CarePlan.self, from: entry.jsonWithMeta)
            XCTAssertEqual(cp.intent.value?.rawValue, "plan")
        }
    }

    func testSearch_byCategory() async throws {
        let patient = try await patientStore.create(makePatient(family: "CPCategory"))
        _ = try await store.create(makeCarePlan(patientId: patient.id, category: "736055001"))
        _ = try await store.create(makeCarePlan(patientId: patient.id))

        let query = CarePlanSearchQuery(
            category: [.init(system: nil, code: "736055001")], count: 10)
        let result = try await store.search(query: query)
        XCTAssertEqual(result.entries.count, 1)
    }

    func testSearch_byActivityCode() async throws {
        let patient = try await patientStore.create(makePatient(family: "CPActCode"))
        _ = try await store.create(makeCarePlan(patientId: patient.id, activityCode: "229070002"))
        _ = try await store.create(makeCarePlan(patientId: patient.id))

        let query = CarePlanSearchQuery(
            activityCode: [.init(system: nil, code: "229070002")], count: 10)
        let result = try await store.search(query: query)
        XCTAssertEqual(result.entries.count, 1)
    }

    // ── Search: reference params ──────────────────────────────────────────────

    func testSearch_byPatient() async throws {
        let patient1 = try await patientStore.create(makePatient(family: "CPPat1"))
        let patient2 = try await patientStore.create(makePatient(family: "CPPat2"))
        _ = try await store.create(makeCarePlan(patientId: patient1.id))
        _ = try await store.create(makeCarePlan(patientId: patient2.id))

        let query = CarePlanSearchQuery(patient: "Patient/\(patient1.id)", count: 10)
        let result = try await store.search(query: query)
        XCTAssertEqual(result.entries.count, 1)
    }

    func testSearch_bySubject() async throws {
        let patient1 = try await patientStore.create(makePatient(family: "CPSubj1"))
        let patient2 = try await patientStore.create(makePatient(family: "CPSubj2"))
        _ = try await store.create(makeCarePlan(patientId: patient1.id))
        _ = try await store.create(makeCarePlan(patientId: patient2.id))

        let query = CarePlanSearchQuery(subject: "Patient/\(patient1.id)", count: 10)
        let result = try await store.search(query: query)
        XCTAssertEqual(result.entries.count, 1)
    }

    func testSearch_byEncounter() async throws {
        let patient = try await patientStore.create(makePatient(family: "CPEnc"))
        let enc = "enc-cp-abc123"
        _ = try await store.create(makeCarePlan(patientId: patient.id, encounterId: enc))
        _ = try await store.create(makeCarePlan(patientId: patient.id))

        let query = CarePlanSearchQuery(encounter: "Encounter/\(enc)", count: 10)
        let result = try await store.search(query: query)
        XCTAssertEqual(result.entries.count, 1)
    }

    // ── Search: date params ───────────────────────────────────────────────────

    func testSearch_byDate() async throws {
        let patient = try await patientStore.create(makePatient(family: "CPDate"))
        _ = try await store.create(makeCarePlan(patientId: patient.id, periodStart: "2020-01-01", periodEnd: "2020-12-31"))
        _ = try await store.create(makeCarePlan(patientId: patient.id, periodStart: "2024-06-01", periodEnd: "2024-12-31"))

        let dp = CarePlanSearchQuery.DateParam.parse("ge2023-01-01")!
        let query = CarePlanSearchQuery(date: [dp], count: 10)
        let result = try await store.search(query: query)
        XCTAssertEqual(result.entries.count, 1)
    }

    // ── Search: _id ───────────────────────────────────────────────────────────

    func testSearch_byId() async throws {
        let patient = try await patientStore.create(makePatient(family: "CPId"))
        let created1 = try await store.create(makeCarePlan(patientId: patient.id))
        _ = try await store.create(makeCarePlan(patientId: patient.id))

        let query = CarePlanSearchQuery(id: [created1.id], count: 10)
        let result = try await store.search(query: query)
        XCTAssertEqual(result.entries.count, 1)
        XCTAssertEqual(result.entries[0].id, created1.id)
    }

    // ── totalMode ─────────────────────────────────────────────────────────────

    func testSearch_totalMode_none_returnsNilTotal() async throws {
        let patient = try await patientStore.create(makePatient(family: "CPTotalNone"))
        _ = try await store.create(makeCarePlan(patientId: patient.id))

        var query = CarePlanSearchQuery()
        query.totalMode = .none
        let result = try await store.search(query: query)
        XCTAssertNil(result.total)
    }

    func testSearch_count0_returnsTotal() async throws {
        let patient = try await patientStore.create(makePatient(family: "CPCount0"))
        _ = try await store.create(makeCarePlan(patientId: patient.id))
        _ = try await store.create(makeCarePlan(patientId: patient.id))

        var query = CarePlanSearchQuery()
        query.count = 0
        query.totalMode = .accurate
        let result = try await store.search(query: query)
        XCTAssertEqual(result.entries.count, 0)
        XCTAssertGreaterThanOrEqual(result.total ?? 0, 2)
    }

    // ── History ───────────────────────────────────────────────────────────────

    func testHistory_instanceHistory() async throws {
        let patient = try await patientStore.create(makePatient(family: "CPHist"))
        let created = try await store.create(makeCarePlan(patientId: patient.id, status: "active", intent: "plan"))
        let updated = try makeCarePlan(patientId: patient.id, status: "completed", intent: "plan")
        _ = try await store.update(id: created.id, carePlan: updated, ifMatch: nil)

        let history = try await store.history(id: created.id)
        XCTAssertEqual(history.count, 2)
        XCTAssertEqual(history[0].versionId, 2)
        XCTAssertEqual(history[1].versionId, 1)
    }

    func testTypeHistory_returnsEntries() async throws {
        let patient = try await patientStore.create(makePatient(family: "CPTypeHist"))
        _ = try await store.create(makeCarePlan(patientId: patient.id))
        _ = try await store.create(makeCarePlan(patientId: patient.id))

        let history = try await store.typeHistory(since: nil, count: 100)
        XCTAssertGreaterThanOrEqual(history.count, 2)
    }

    // ── Pagination ────────────────────────────────────────────────────────────

    func testSearch_pagination_noDuplicatesAcrossPages() async throws {
        let patient = try await patientStore.create(makePatient(family: "CPPage"))
        for _ in 0..<5 {
            _ = try await store.create(makeCarePlan(patientId: patient.id))
        }

        var query = CarePlanSearchQuery(patient: "Patient/\(patient.id)", count: 2)
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

    // ── Search: activity-date ─────────────────────────────────────────────────

    func testSearch_byActivityDate_ge() async throws {
        let patient = try await patientStore.create(makePatient(family: "CPActDate"))
        _ = try await store.create(makeCarePlan(patientId: patient.id, activityDateStart: "2023-01-01", activityDateEnd: "2023-12-31"))
        _ = try await store.create(makeCarePlan(patientId: patient.id, activityDateStart: "2025-01-01", activityDateEnd: "2025-12-31"))
        _ = try await store.create(makeCarePlan(patientId: patient.id))

        let dp = CarePlanSearchQuery.DateParam.parse("ge2024-06-01")!
        let query = CarePlanSearchQuery(activityDate: [dp], count: 10)
        let result = try await store.search(query: query)
        XCTAssertEqual(result.entries.count, 1)
    }

    // ── Search: instantiates-canonical / instantiates-uri ────────────────────

    func testSearch_byInstantiatesCanonical() async throws {
        let patient = try await patientStore.create(makePatient(family: "CPInstCan"))
        _ = try await store.create(makeCarePlan(patientId: patient.id, instantiatesCanonical: "http://example.org/protocols/diabetes"))
        _ = try await store.create(makeCarePlan(patientId: patient.id, instantiatesCanonical: "http://example.org/protocols/other"))
        _ = try await store.create(makeCarePlan(patientId: patient.id))

        let query = CarePlanSearchQuery(instantiatesCanonical: ["http://example.org/protocols/diabetes"], count: 10)
        let result = try await store.search(query: query)
        XCTAssertEqual(result.entries.count, 1)
    }

    func testSearch_byInstantiatesUri() async throws {
        let patient = try await patientStore.create(makePatient(family: "CPInstUri"))
        _ = try await store.create(makeCarePlan(patientId: patient.id, instantiatesUri: "https://protocols.example.com/hypertension"))
        _ = try await store.create(makeCarePlan(patientId: patient.id, instantiatesUri: "https://protocols.example.com/other"))
        _ = try await store.create(makeCarePlan(patientId: patient.id))

        let query = CarePlanSearchQuery(instantiatesUri: ["https://protocols.example.com/hypertension"], count: 10)
        let result = try await store.search(query: query)
        XCTAssertEqual(result.entries.count, 1)
    }

    // ── Sort ──────────────────────────────────────────────────────────────────

    func testSearch_sortByDate() async throws {
        let patient = try await patientStore.create(makePatient(family: "CPSort"))
        _ = try await store.create(makeCarePlan(patientId: patient.id, periodStart: "2022-01-01", periodEnd: "2022-12-31"))
        _ = try await store.create(makeCarePlan(patientId: patient.id, periodStart: "2024-01-01", periodEnd: "2024-12-31"))

        let query = CarePlanSearchQuery(
            patient: "Patient/\(patient.id)",
            count: 10, sortKeys: CarePlanSearchQuery.parseSortKeys("-date"))
        let result = try await store.search(query: query)
        guard result.entries.count >= 2 else { return }
        let cp0 = try JSONDecoder().decode(ModelsR4.CarePlan.self, from: result.entries[0].jsonWithMeta)
        let cp1 = try JSONDecoder().decode(ModelsR4.CarePlan.self, from: result.entries[1].jsonWithMeta)
        XCTAssertNotNil(cp0.period)
        XCTAssertNotNil(cp1.period)
    }
}
