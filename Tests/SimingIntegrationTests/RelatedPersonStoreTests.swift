import Foundation
import ModelsR4
@testable import SimingCore
import XCTest

final class RelatedPersonStoreTests: XCTestCase {
    var store: RelatedPersonStore!
    var patientStore: PatientStore!

    override func setUp() async throws {
        try await super.setUp()
        try await requireDatabase()
        store        = try await TestDatabase.shared.makeRelatedPersonStore()
        patientStore = try await TestDatabase.shared.makePatientStore()
    }

    // ── Create ────────────────────────────────────────────────────────────────

    func testCreate_assignsIdAndVersionOne() async throws {
        let patient = try await patientStore.create(makePatient(family: "RPCreate"))
        let result = try await store.create(makeRelatedPerson(patientId: patient.id))
        XCTAssertFalse(result.id.isEmpty)
        XCTAssertEqual(result.versionId, 1)
    }

    // ── Read ──────────────────────────────────────────────────────────────────

    func testRead_returnsStoredResource() async throws {
        let patient = try await patientStore.create(makePatient(family: "RPRead"))
        let created = try await store.create(makeRelatedPerson(patientId: patient.id, family: "Smith"))
        let row = try await store.read(id: created.id)
        let rp = try JSONDecoder().decode(ModelsR4.RelatedPerson.self, from: row.jsonData)
        XCTAssertEqual(rp.name?.first?.family?.value?.string, "Smith")
    }

    func testRead_unknownId_throwsNotFound() async throws {
        do {
            _ = try await store.read(id: "no-such-related-person")
            XCTFail("Expected notFound")
        } catch FHIRServerError.notFound { }
    }

    // ── vread ─────────────────────────────────────────────────────────────────

    func testVread_returnsSpecificVersion() async throws {
        let patient = try await patientStore.create(makePatient(family: "RPVread"))
        let created = try await store.create(makeRelatedPerson(patientId: patient.id, family: "V1Family"))
        let updated = try makeRelatedPerson(patientId: patient.id, family: "V2Family")
        _ = try await store.update(id: created.id, rp: updated, ifMatch: nil)
        let v1 = try await store.vread(id: created.id, versionId: 1)
        let rp = try JSONDecoder().decode(ModelsR4.RelatedPerson.self, from: v1.jsonData)
        XCTAssertEqual(rp.name?.first?.family?.value?.string, "V1Family")
    }

    // ── Update ────────────────────────────────────────────────────────────────

    func testUpdate_incrementsVersionId() async throws {
        let patient = try await patientStore.create(makePatient(family: "RPUpdate"))
        let created = try await store.create(makeRelatedPerson(patientId: patient.id))
        let updated = try await store.update(
            id: created.id,
            rp: makeRelatedPerson(patientId: patient.id, family: "UpdatedFamily"),
            ifMatch: nil
        )
        XCTAssertEqual(updated.versionId, 2)
    }

    func testUpdate_ifMatch_wrongEtag_throwsPreconditionFailed() async throws {
        let patient = try await patientStore.create(makePatient(family: "RPIfMatch"))
        let created = try await store.create(makeRelatedPerson(patientId: patient.id))
        do {
            _ = try await store.update(
                id: created.id,
                rp: makeRelatedPerson(patientId: patient.id),
                ifMatch: 999
            )
            XCTFail("Expected versionConflict")
        } catch FHIRServerError.versionConflict { }
    }

    // ── Delete ────────────────────────────────────────────────────────────────

    func testDelete_subsequentReadThrowsGone() async throws {
        let patient = try await patientStore.create(makePatient(family: "RPDelete"))
        let created = try await store.create(makeRelatedPerson(patientId: patient.id))
        _ = try await store.delete(id: created.id, ifMatch: nil)
        do {
            _ = try await store.read(id: created.id)
            XCTFail("Expected gone")
        } catch FHIRServerError.gone { }
    }

    // ── Search: name ──────────────────────────────────────────────────────────

    func testSearch_byName_startsWith_returnsMatch() async throws {
        let patient = try await patientStore.create(makePatient(family: "RPNameSrch"))
        _ = try await store.create(makeRelatedPerson(patientId: patient.id, family: "Johnson"))
        _ = try await store.create(makeRelatedPerson(patientId: patient.id, family: "Williams"))

        let q = RelatedPersonSearchQuery(name: .init(value: "Johns", modifier: .startsWith))
        let result = try await store.search(query: q)
        XCTAssertEqual(result.total, 1)
    }

    func testSearch_byName_contains_returnsMatch() async throws {
        let patient = try await patientStore.create(makePatient(family: "RPNameContains"))
        _ = try await store.create(makeRelatedPerson(patientId: patient.id, family: "Robertson"))
        _ = try await store.create(makeRelatedPerson(patientId: patient.id, family: "Torres"))

        let q = RelatedPersonSearchQuery(name: .init(value: "ober", modifier: .contains))
        let result = try await store.search(query: q)
        XCTAssertEqual(result.total, 1)
    }

    // ── Search: gender ────────────────────────────────────────────────────────

    func testSearch_byGender_returnsMatchOnly() async throws {
        let patient = try await patientStore.create(makePatient(family: "RPGender"))
        _ = try await store.create(makeRelatedPerson(patientId: patient.id, family: "FemaleRP", gender: "female"))
        _ = try await store.create(makeRelatedPerson(patientId: patient.id, family: "MaleRP", gender: "male"))

        let q = RelatedPersonSearchQuery(gender: [.init(system: nil, code: "female")])
        let result = try await store.search(query: q)
        XCTAssertEqual(result.total, 1)
        let rp = try JSONDecoder().decode(ModelsR4.RelatedPerson.self, from: result.entries[0].jsonWithMeta)
        XCTAssertEqual(rp.gender?.value?.rawValue, "female")
    }

    func testSearch_byGenderNot_excludesCorrectly() async throws {
        let patient = try await patientStore.create(makePatient(family: "RPGenderNot"))
        _ = try await store.create(makeRelatedPerson(patientId: patient.id, family: "FemaleRPN", gender: "female"))
        _ = try await store.create(makeRelatedPerson(patientId: patient.id, family: "MaleRPN", gender: "male"))

        let q = RelatedPersonSearchQuery(genderNot: [.init(system: nil, code: "female")])
        let result = try await store.search(query: q)
        XCTAssertEqual(result.total, 1)
        let rp = try JSONDecoder().decode(ModelsR4.RelatedPerson.self, from: result.entries[0].jsonWithMeta)
        XCTAssertEqual(rp.gender?.value?.rawValue, "male")
    }

    // ── Search: relationship ──────────────────────────────────────────────────

    func testSearch_byRelationship_returnsMatchOnly() async throws {
        let patient = try await patientStore.create(makePatient(family: "RPRelship"))
        _ = try await store.create(makeRelatedPerson(patientId: patient.id, family: "SpouseRP", relationship: "SPS"))
        _ = try await store.create(makeRelatedPerson(patientId: patient.id, family: "ParentRP", relationship: "PRN"))

        let q = RelatedPersonSearchQuery(relationship: [.init(system: nil, code: "SPS")])
        let result = try await store.search(query: q)
        XCTAssertEqual(result.total, 1)
    }

    // ── Search: patient reference ─────────────────────────────────────────────

    func testSearch_byPatient_returnsMatchOnly() async throws {
        let patient1 = try await patientStore.create(makePatient(family: "RPPatSrch1"))
        let patient2 = try await patientStore.create(makePatient(family: "RPPatSrch2"))
        _ = try await store.create(makeRelatedPerson(patientId: patient1.id))
        _ = try await store.create(makeRelatedPerson(patientId: patient2.id))

        let q = RelatedPersonSearchQuery(patient: "Patient/\(patient1.id)")
        let result = try await store.search(query: q)
        XCTAssertEqual(result.total, 1)
        let rp = try JSONDecoder().decode(ModelsR4.RelatedPerson.self, from: result.entries[0].jsonWithMeta)
        let patRef = rp.patient.reference?.value?.string ?? ""
        XCTAssertTrue(patRef.contains(patient1.id))
    }

    // ── Search: birthdate ─────────────────────────────────────────────────────

    func testSearch_byBirthdate_returnsMatchOnly() async throws {
        let patient = try await patientStore.create(makePatient(family: "RPBirthdate"))
        _ = try await store.create(makeRelatedPerson(patientId: patient.id, family: "BornEarly", birthDate: "1980-01-01"))
        _ = try await store.create(makeRelatedPerson(patientId: patient.id, family: "BornLate",  birthDate: "2000-06-15"))

        // Use le<year> to avoid timezone boundary issues at day precision
        let q = RelatedPersonSearchQuery(birthdate: [RelatedPersonSearchQuery.DateParam.parse("le1990")!])
        let result = try await store.search(query: q)
        XCTAssertEqual(result.total, 1)
        guard !result.entries.isEmpty else { XCTFail("No entries returned"); return }
        let rp = try JSONDecoder().decode(ModelsR4.RelatedPerson.self, from: result.entries[0].jsonWithMeta)
        XCTAssertEqual(rp.name?.first?.family?.value?.string, "BornEarly")
    }

    // ── Search: identifier ────────────────────────────────────────────────────

    func testSearch_byIdentifier_returnsMatchOnly() async throws {
        let patient = try await patientStore.create(makePatient(family: "RPIdent"))
        let rpWithIdJSON = #"""
        {"resourceType":"RelatedPerson",
         "patient":{"reference":"Patient/\#(patient.id)"},
         "relationship":[{"coding":[{"system":"http://terminology.hl7.org/CodeSystem/v3-RoleCode","code":"spouse"}]}],
         "name":[{"family":"IdentRP","given":["Jane"]}],
         "identifier":[{"system":"http://example.org","value":"RPID-001"}]}
        """#
        _ = try await store.create(try JSONDecoder().decode(ModelsR4.RelatedPerson.self, from: Data(rpWithIdJSON.utf8)))
        _ = try await store.create(makeRelatedPerson(patientId: patient.id, family: "NoIdRP"))

        let q = RelatedPersonSearchQuery(identifier: [RelatedPersonSearchQuery.IdentifierParam.parse("http://example.org|RPID-001")])
        let result = try await store.search(query: q)
        XCTAssertEqual(result.total, 1)
        let rp = try JSONDecoder().decode(ModelsR4.RelatedPerson.self, from: result.entries[0].jsonWithMeta)
        XCTAssertEqual(rp.name?.first?.family?.value?.string, "IdentRP")
    }

    // ── Search: active ────────────────────────────────────────────────────────

    func testSearch_byActive_returnsMatchOnly() async throws {
        let patient = try await patientStore.create(makePatient(family: "RPActive"))
        _ = try await store.create(makeRelatedPerson(patientId: patient.id, family: "ActiveRP", active: true))
        _ = try await store.create(makeRelatedPerson(patientId: patient.id, family: "InactiveRP", active: false))

        let q = RelatedPersonSearchQuery(active: [.init(system: nil, code: "true")])
        let result = try await store.search(query: q)
        XCTAssertEqual(result.total, 1)
        let rp = try JSONDecoder().decode(ModelsR4.RelatedPerson.self, from: result.entries[0].jsonWithMeta)
        XCTAssertEqual(rp.active?.value?.bool, true)
    }

    // ── Search: address-city ──────────────────────────────────────────────────

    func testSearch_byAddressCity_returnsMatchOnly() async throws {
        let patient = try await patientStore.create(makePatient(family: "RPAddrCity"))
        let rpTaipeiJSON = #"""
        {"resourceType":"RelatedPerson",
         "patient":{"reference":"Patient/\#(patient.id)"},
         "relationship":[{"coding":[{"system":"http://terminology.hl7.org/CodeSystem/v3-RoleCode","code":"spouse"}]}],
         "name":[{"family":"TaipeiRP","given":["Jane"]}],
         "address":[{"city":"Taipei"}]}
        """#
        let rpKHJSON = #"""
        {"resourceType":"RelatedPerson",
         "patient":{"reference":"Patient/\#(patient.id)"},
         "relationship":[{"coding":[{"system":"http://terminology.hl7.org/CodeSystem/v3-RoleCode","code":"spouse"}]}],
         "name":[{"family":"KaohsiungRP","given":["Jane"]}],
         "address":[{"city":"Kaohsiung"}]}
        """#
        _ = try await store.create(try JSONDecoder().decode(ModelsR4.RelatedPerson.self, from: Data(rpTaipeiJSON.utf8)))
        _ = try await store.create(try JSONDecoder().decode(ModelsR4.RelatedPerson.self, from: Data(rpKHJSON.utf8)))

        let q = RelatedPersonSearchQuery(addressCity: .init(value: "Taipei", modifier: .startsWith))
        let result = try await store.search(query: q)
        XCTAssertEqual(result.total, 1)
        let rp = try JSONDecoder().decode(ModelsR4.RelatedPerson.self, from: result.entries[0].jsonWithMeta)
        XCTAssertEqual(rp.name?.first?.family?.value?.string, "TaipeiRP")
    }

    // ── Search: _id ───────────────────────────────────────────────────────────

    func testSearch_byId_returnsMatchOnly() async throws {
        let patient = try await patientStore.create(makePatient(family: "RPIdSrch"))
        let created = try await store.create(makeRelatedPerson(patientId: patient.id, family: "IdSrchRP"))
        _ = try await store.create(makeRelatedPerson(patientId: patient.id, family: "OtherRP"))

        let q = RelatedPersonSearchQuery(id: [created.id])
        let result = try await store.search(query: q)
        XCTAssertEqual(result.total, 1)
        XCTAssertEqual(result.entries[0].id, created.id)
    }

    // ── Search: totalMode=none ────────────────────────────────────────────────

    func testSearch_totalModeNone_returnsNilTotal() async throws {
        let patient = try await patientStore.create(makePatient(family: "RPTotalNone"))
        _ = try await store.create(makeRelatedPerson(patientId: patient.id))

        var q = RelatedPersonSearchQuery(patient: "Patient/\(patient.id)")
        q.totalMode = .none
        let result = try await store.search(query: q)
        XCTAssertNil(result.total)
    }

    // ── History ───────────────────────────────────────────────────────────────

    func testHistory_tracksAllVersions() async throws {
        let patient = try await patientStore.create(makePatient(family: "RPHist"))
        let created = try await store.create(makeRelatedPerson(patientId: patient.id, family: "HistV1"))
        _ = try await store.update(
            id: created.id,
            rp: makeRelatedPerson(patientId: patient.id, family: "HistV2"),
            ifMatch: nil
        )
        let entries = try await store.history(id: created.id)
        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(entries[0].versionId, 2)
        XCTAssertEqual(entries[1].versionId, 1)
    }

    func testTypeHistory_includesAllRelatedPersons() async throws {
        let patient = try await patientStore.create(makePatient(family: "RPTypeHist"))
        _ = try await store.create(makeRelatedPerson(patientId: patient.id, family: "TypeHistRPA"))
        _ = try await store.create(makeRelatedPerson(patientId: patient.id, family: "TypeHistRPB"))
        let entries = try await store.typeHistory(since: nil, count: 50)
        XCTAssertGreaterThanOrEqual(entries.count, 2)
        XCTAssertTrue(entries.allSatisfy { $0.resourceType == "RelatedPerson" })
    }

    // ── Pagination ────────────────────────────────────────────────────────────

    func testSearch_pagination_returnsCorrectPage() async throws {
        let patient = try await patientStore.create(makePatient(family: "RPPagination"))
        for i in 0..<5 {
            _ = try await store.create(makeRelatedPerson(patientId: patient.id, family: "PageRP\(i)"))
        }

        var q = RelatedPersonSearchQuery(patient: "Patient/\(patient.id)")
        q.count = 2
        let page1 = try await store.search(query: q)
        XCTAssertEqual(page1.entries.count, 2)
        XCTAssertNotNil(page1.nextCursor)

        q.cursor = page1.nextCursor
        let page2 = try await store.search(query: q)
        XCTAssertGreaterThan(page2.entries.count, 0)
        let page1Ids = Set(page1.entries.map(\.id))
        let page2Ids = Set(page2.entries.map(\.id))
        XCTAssertTrue(page1Ids.isDisjoint(with: page2Ids))
    }
}
