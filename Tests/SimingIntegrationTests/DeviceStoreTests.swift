import Foundation
import Logging
import ModelsR4
@testable import SimingCore
import XCTest

final class DeviceStoreTests: XCTestCase {
    var store: DeviceStore!
    var patientStore: PatientStore!
    var observationStore: ObservationStore!

    override func setUp() async throws {
        try await super.setUp()
        try await requireDatabase()
        store            = try await TestDatabase.shared.makeDeviceStore()
        patientStore     = try await TestDatabase.shared.makePatientStore()
        observationStore = try await TestDatabase.shared.makeObservationStore()
    }

    /// Unique per run — the test database is not wiped between runs.
    private func serial() -> String { "SN-" + UUID().uuidString.prefix(8) }

    private func ids(_ result: DeviceStore.SearchResult) -> Set<String> {
        Set(result.entries.map(\.id))
    }

    // ── CRUD ──────────────────────────────────────────────────────────────────

    func testCreate_withoutPatient_assignsIdAndVersionOne() async throws {
        let result = try await store.create(makeDevice(serial: serial(), name: "Omron HEM-7600T"))
        XCTAssertFalse(result.id.isEmpty)
        XCTAssertEqual(result.versionId, 1)
        let row = try await store.read(id: result.id)
        let device = try JSONDecoder().decode(Device.self, from: row.jsonData)
        XCTAssertEqual(device.deviceName?.first?.name.value?.string, "Omron HEM-7600T")
        XCTAssertNil(device.patient)
    }

    func testUpdate_statusChangeLeavesIndex() async throws {
        let sn = serial()
        let created = try await store.create(makeDevice(serial: sn, status: "active"))
        let result = try await store.update(id: created.id, device: makeDevice(serial: sn, status: "inactive"), ifMatch: 1)
        XCTAssertEqual(result.versionId, 2)

        let ident = DeviceSearchQuery.IdentifierParam.parseList("urn:test:device-serial|\(sn)")
        let stale = try await store.search(query: DeviceSearchQuery(status: [.init(system: nil, code: "active")], identifier: ident))
        XCTAssertTrue(stale.entries.isEmpty)
        let current = try await store.search(query: DeviceSearchQuery(status: [.init(system: nil, code: "inactive")], identifier: ident))
        XCTAssertEqual(ids(current), [created.id])
    }

    func testDelete_and_goneOnRead() async throws {
        let created = try await store.create(makeDevice(serial: serial()))
        try await store.delete(id: created.id, ifMatch: nil)
        do {
            _ = try await store.read(id: created.id)
            XCTFail("Expected gone error")
        } catch FHIRServerError.gone { }
    }

    // ── Search ────────────────────────────────────────────────────────────────

    func testSearch_identifier() async throws {
        let sn = serial()
        let created = try await store.create(makeDevice(serial: sn))
        _ = try await store.create(makeDevice(serial: serial()))
        let result = try await store.search(query: DeviceSearchQuery(
            identifier: DeviceSearchQuery.IdentifierParam.parseList("urn:test:device-serial|\(sn)")))
        XCTAssertEqual(ids(result), [created.id])
    }

    func testSearch_deviceName_matchesNameAndTypeDisplay() async throws {
        let tag = "Dn" + UUID().uuidString.prefix(6)
        let byName = try await store.create(makeDevice(serial: serial(), name: "\(tag) cuff"))
        let byType = try await store.create(makeDevice(serial: serial(), typeCode: "258057004", typeDisplay: "\(tag) monitor"))
        let result = try await store.search(query: DeviceSearchQuery(
            deviceName: .init(value: tag, modifier: .startsWith)))
        XCTAssertEqual(ids(result), [byName.id, byType.id])
    }

    func testSearch_manufacturerModelUdi() async throws {
        let tag = "Mf" + UUID().uuidString.prefix(6)
        let udi = "0" + String(UUID().uuidString.filter(\.isNumber).prefix(13))
        let created = try await store.create(makeDevice(serial: serial(), manufacturer: "\(tag) Corp",
                                                        model: "\(tag)-M1", udiDI: udi))
        let byMfr = try await store.search(query: DeviceSearchQuery(manufacturer: .init(value: tag, modifier: .startsWith)))
        XCTAssertEqual(ids(byMfr), [created.id])
        let byModel = try await store.search(query: DeviceSearchQuery(model: .init(value: "\(tag)-M1", modifier: .exact)))
        XCTAssertEqual(ids(byModel), [created.id])
        let byDI = try await store.search(query: DeviceSearchQuery(udiDi: .init(value: udi, modifier: .exact)))
        XCTAssertEqual(ids(byDI), [created.id])
    }

    func testSearch_patientAndOrganization() async throws {
        let patientId = try await patientStore.create(makePatient(family: "DevicePatient")).id
        let withPatient = try await store.create(makeDevice(serial: serial(), patient: "Patient/\(patientId)"))
        _ = try await store.create(makeDevice(serial: serial()))
        let byPatient = try await store.search(query: DeviceSearchQuery(patient: "Patient/\(patientId)"))
        XCTAssertEqual(ids(byPatient), [withPatient.id])

        let orgId = UUID().uuidString.lowercased()
        let owned = try await store.create(makeDevice(serial: serial(), owner: "Organization/\(orgId)"))
        let byOrg = try await store.search(query: DeviceSearchQuery(organization: "Organization/\(orgId)"))
        XCTAssertEqual(ids(byOrg), [owned.id])
    }

    func testSearch_missingPatient() async throws {
        let sn = serial()
        let created = try await store.create(makeDevice(serial: sn))
        let ident = DeviceSearchQuery.IdentifierParam.parseList("urn:test:device-serial|\(sn)")
        let missing = try await store.search(query: DeviceSearchQuery(identifier: ident, missing: ["patient": true]))
        XCTAssertEqual(ids(missing), [created.id])
        let present = try await store.search(query: DeviceSearchQuery(identifier: ident, missing: ["patient": false]))
        XCTAssertTrue(present.entries.isEmpty)
    }

    func testSearch_countOnly() async throws {
        let tag = "Ct" + UUID().uuidString.prefix(6)
        _ = try await store.create(makeDevice(serial: serial(), manufacturer: tag))
        _ = try await store.create(makeDevice(serial: serial(), manufacturer: tag))
        let result = try await store.search(query: DeviceSearchQuery(
            manufacturer: .init(value: tag, modifier: .exact), count: 0))
        XCTAssertEqual(result.total, 2)
        XCTAssertTrue(result.entries.isEmpty)
    }

    // ── Observation.device — the downstream use ──────────────────────────────

    func testObservationDevice_searchAndInclude() async throws {
        let patientId = try await patientStore.create(makePatient(family: "DeviceObs")).id
        let device = try await store.create(makeDevice(serial: serial(), name: "Home BP cuff"))
        let obsJSON = #"""
        {"resourceType":"Observation","status":"final",
         "code":{"coding":[{"system":"http://loinc.org","code":"85354-9"}]},
         "subject":{"reference":"Patient/\#(patientId)"},
         "device":{"reference":"Device/\#(device.id)"}}
        """#
        let obs = try await observationStore.create(
            JSONDecoder().decode(Observation.self, from: Data(obsJSON.utf8)))

        let byDevice = try await observationStore.search(query: ObservationSearchQuery(device: "Device/\(device.id)"))
        XCTAssertEqual(Set(byDevice.entries.map(\.id)), [obs.id])

        let resolver = IncludeResolver(client: store.client, logger: Logger(label: "test"))
        let included = try await resolver.resolve(
            includes: [IncludeParam(sourceType: "Observation", paramName: "device", targetType: nil)],
            sourceIds: [obs.id])
        XCTAssertEqual(included.map { "\($0.resourceType)/\($0.id)" }, ["Device/\(device.id)"])
    }

    func testTransactionPrepare_acceptsDevice() throws {
        let data = try JSONEncoder().encode(makeDevice(serial: serial()))
        XCTAssertNoThrow(try prepareEntryForWrite(resourceType: "Device", id: "dev-tx-1", data: data, terminology: .empty))
    }
}
