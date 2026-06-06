import Foundation
import Logging
import ModelsR4
import PostgresNIO
@testable import SimingCore
import XCTest

/// Shared PostgreSQL connection for the integration test process.
/// Set up once; migrations run on first setUp(). Truncate between tests.
actor TestDatabase {
    static let shared = TestDatabase()

    private(set) var isAvailable = false
    private var _client: PostgresClient?
    let logger = Logger(label: "siming.test")

    // Initialise once; subsequent calls are no-ops.
    func setUp() async throws {
        guard _client == nil else { return }
        let env = ProcessInfo.processInfo.environment
        guard env["PGHOST"] != nil || env["DATABASE_URL"] != nil else { return }

        let config = try DatabaseConfiguration.fromEnvironment()
        let c = PostgresClient(
            configuration: config.postgresClientConfiguration,
            backgroundLogger: logger
        )
        _client = c
        // run() drives the connection pool — keep it alive for the whole process.
        Swift.Task { await c.run() }

        let migrationsPath = env["MIGRATIONS_PATH"] ?? "migrations"
        let runner = MigrationRunner(client: c, logger: logger, migrationsPath: migrationsPath)
        try await runner.run()
        isAvailable = true
    }

    func makePatientStore() throws -> PatientStore {
        PatientStore(client: try requiredClient(), logger: logger)
    }

    func makeObservationStore() throws -> ObservationStore {
        ObservationStore(client: try requiredClient(), logger: logger)
    }

    func makeMedicationStore() throws -> MedicationStore {
        MedicationStore(client: try requiredClient(), logger: logger)
    }

    func makeEncounterStore() throws -> EncounterStore {
        EncounterStore(client: try requiredClient(), logger: logger)
    }

    func makeConditionStore() throws -> ConditionStore {
        ConditionStore(client: try requiredClient(), logger: logger)
    }

    func makeMedicationRequestStore() throws -> MedicationRequestStore {
        MedicationRequestStore(client: try requiredClient(), logger: logger)
    }

    func makeAllergyIntoleranceStore() throws -> AllergyIntoleranceStore {
        AllergyIntoleranceStore(client: try requiredClient(), logger: logger)
    }

    func makeProcedureStore() throws -> ProcedureStore {
        ProcedureStore(client: try requiredClient(), logger: logger)
    }

    func makeDiagnosticReportStore() throws -> DiagnosticReportStore {
        DiagnosticReportStore(client: try requiredClient(), logger: logger)
    }

    func makeImmunizationStore() throws -> ImmunizationStore {
        ImmunizationStore(client: try requiredClient(), logger: logger)
    }

    func makePractitionerStore() throws -> PractitionerStore {
        PractitionerStore(client: try requiredClient(), logger: logger)
    }

    func makeOrganizationStore() throws -> OrganizationStore {
        OrganizationStore(client: try requiredClient(), logger: logger)
    }

    func makeLocationStore() throws -> LocationStore {
        LocationStore(client: try requiredClient(), logger: logger)
    }

    func makeRelatedPersonStore() throws -> RelatedPersonStore {
        RelatedPersonStore(client: try requiredClient(), logger: logger)
    }

    func makeServiceRequestStore() throws -> ServiceRequestStore {
        ServiceRequestStore(client: try requiredClient(), logger: logger)
    }

    func makeSpecimenStore() throws -> SpecimenStore {
        SpecimenStore(client: try requiredClient(), logger: logger)
    }

    func makeDocumentReferenceStore() throws -> DocumentReferenceStore {
        DocumentReferenceStore(client: try requiredClient(), logger: logger)
    }

    func truncate() async throws {
        let c = try requiredClient()
        try await c.withConnection { conn in
            _ = try await conn.query(
                "TRUNCATE resources, idx_token, idx_string, idx_date, idx_reference, idx_quantity",
                logger: logger
            )
        }
    }

    private func requiredClient() throws -> PostgresClient {
        guard let c = _client else { throw TestDatabaseError.notInitialised }
        return c
    }
}

enum TestDatabaseError: Error { case notInitialised }

// ── Helpers used in every test class ─────────────────────────────────────────

/// Call at the start of every setUp() async throws.
/// Skips the test (not fails) when no DB is configured.
func requireDatabase() async throws {
    try await TestDatabase.shared.setUp()
    guard await TestDatabase.shared.isAvailable else {
        throw XCTSkip("Integration tests require PostgreSQL — set PGHOST or DATABASE_URL")
    }
    try await TestDatabase.shared.truncate()
}

func makePatient(
    family: String,
    given: String = "Test",
    birthYear: Int? = nil,
    birthMonth: Int? = nil,
    birthDay: Int? = nil
) throws -> ModelsR4.Patient {
    var json = #"{"resourceType":"Patient","name":[{"family":"\#(family)","given":["\#(given)"]}]"#
    if let y = birthYear {
        if let m = birthMonth {
            if let d = birthDay {
                json += #","birthDate":"\#(y)-\#(String(format:"%02d",m))-\#(String(format:"%02d",d))""#
            } else {
                json += #","birthDate":"\#(y)-\#(String(format:"%02d",m))""#
            }
        } else {
            json += #","birthDate":"\#(y)""#
        }
    }
    json += "}"
    return try JSONDecoder().decode(ModelsR4.Patient.self, from: Data(json.utf8))
}

func makeMedication(
    code: String = "1049502",
    codeSystem: String = "http://www.nlm.nih.gov/research/umls/rxnorm",
    status: String = "active",
    lotNumber: String? = nil,
    expirationDate: String? = nil
) throws -> ModelsR4.Medication {
    var json = #"""
    {"resourceType":"Medication","status":"\#(status)",
     "code":{"coding":[{"system":"\#(codeSystem)","code":"\#(code)","display":"Hydrocodone"}]}
    """#
    if lotNumber != nil || expirationDate != nil {
        json += #","batch":{"#
        var batchParts: [String] = []
        if let ln = lotNumber { batchParts.append(#""lotNumber":"\#(ln)""#) }
        if let ed = expirationDate { batchParts.append(#""expirationDate":"\#(ed)""#) }
        json += batchParts.joined(separator: ",") + "}"
    }
    json += "}"
    return try JSONDecoder().decode(ModelsR4.Medication.self, from: Data(json.utf8))
}

func makeObservation(subjectId: String, code: String = "29463-7", status: String = "final") throws -> ModelsR4.Observation {
    let json = #"""
    {"resourceType":"Observation","status":"\#(status)",
     "code":{"coding":[{"system":"http://loinc.org","code":"\#(code)"}]},
     "subject":{"reference":"Patient/\#(subjectId)"}}
    """#
    return try JSONDecoder().decode(ModelsR4.Observation.self, from: Data(json.utf8))
}

func makeEncounter(subjectId: String, status: String = "finished") throws -> ModelsR4.Encounter {
    let json = #"""
    {"resourceType":"Encounter","status":"\#(status)",
     "class":{"system":"http://terminology.hl7.org/CodeSystem/v3-ActCode","code":"AMB"},
     "subject":{"reference":"Patient/\#(subjectId)"}}
    """#
    return try JSONDecoder().decode(ModelsR4.Encounter.self, from: Data(json.utf8))
}

func makeCondition(subjectId: String, clinicalStatus: String = "active", onsetDate: String? = nil) throws -> ModelsR4.Condition {
    var json = #"""
    {"resourceType":"Condition",
     "clinicalStatus":{"coding":[{"system":"http://terminology.hl7.org/CodeSystem/condition-clinical","code":"\#(clinicalStatus)"}]},
     "code":{"coding":[{"system":"http://snomed.info/sct","code":"73211009","display":"Diabetes mellitus"}]},
     "subject":{"reference":"Patient/\#(subjectId)"}
    """#
    if let d = onsetDate { json += #","onsetDateTime":"\#(d)""# }
    json += "}"
    return try JSONDecoder().decode(ModelsR4.Condition.self, from: Data(json.utf8))
}

func makeMedicationRequest(subjectId: String, status: String = "active", intent: String = "order", authoredOn: String? = nil) throws -> ModelsR4.MedicationRequest {
    var json = #"""
    {"resourceType":"MedicationRequest","status":"\#(status)","intent":"\#(intent)",
     "medicationCodeableConcept":{"coding":[{"system":"http://www.nlm.nih.gov/research/umls/rxnorm","code":"1049502"}]},
     "subject":{"reference":"Patient/\#(subjectId)"}
    """#
    if let d = authoredOn { json += #","authoredOn":"\#(d)""# }
    json += "}"
    return try JSONDecoder().decode(ModelsR4.MedicationRequest.self, from: Data(json.utf8))
}

func makeProcedure(
    subjectId: String,
    status: String = "completed",
    code: String = "73761001",
    codeSystem: String = "http://snomed.info/sct",
    performedDate: String? = nil
) throws -> ModelsR4.Procedure {
    var json = #"""
    {"resourceType":"Procedure","status":"\#(status)",
     "code":{"coding":[{"system":"\#(codeSystem)","code":"\#(code)","display":"Colonoscopy"}]},
     "subject":{"reference":"Patient/\#(subjectId)"}
    """#
    if let d = performedDate { json += #","performedDateTime":"\#(d)""# }
    json += "}"
    return try JSONDecoder().decode(ModelsR4.Procedure.self, from: Data(json.utf8))
}

func makeDiagnosticReport(
    subjectId: String,
    status: String = "final",
    code: String = "58410-2",
    codeSystem: String = "http://loinc.org",
    effectiveDate: String? = nil,
    issued: String? = nil
) throws -> ModelsR4.DiagnosticReport {
    var json = #"""
    {"resourceType":"DiagnosticReport","status":"\#(status)",
     "code":{"coding":[{"system":"\#(codeSystem)","code":"\#(code)","display":"CBC panel"}]},
     "subject":{"reference":"Patient/\#(subjectId)"}
    """#
    if let d = effectiveDate { json += #","effectiveDateTime":"\#(d)""# }
    if let i = issued { json += #","issued":"\#(i)""# }
    json += "}"
    return try JSONDecoder().decode(ModelsR4.DiagnosticReport.self, from: Data(json.utf8))
}

func makeImmunization(
    patientId: String,
    status: String = "completed",
    vaccineCode: String = "207",
    vaccineSystem: String = "http://hl7.org/fhir/sid/cvx",
    occurrenceDate: String = "2021-01-15",
    lotNumber: String? = nil
) throws -> ModelsR4.Immunization {
    var json = #"""
    {"resourceType":"Immunization","status":"\#(status)",
     "vaccineCode":{"coding":[{"system":"\#(vaccineSystem)","code":"\#(vaccineCode)","display":"COVID-19 mRNA"}]},
     "patient":{"reference":"Patient/\#(patientId)"},
     "occurrenceDateTime":"\#(occurrenceDate)"
    """#
    if let ln = lotNumber { json += #","lotNumber":"\#(ln)""# }
    json += "}"
    return try JSONDecoder().decode(ModelsR4.Immunization.self, from: Data(json.utf8))
}

func makePractitioner(
    family: String,
    given: String = "Test",
    gender: String? = nil,
    identifier: String? = nil,
    identifierSystem: String = "http://hl7.org/fhir/sid/us-npi"
) throws -> ModelsR4.Practitioner {
    var json = #"{"resourceType":"Practitioner","name":[{"family":"\#(family)","given":["\#(given)"]}]"#
    if let g = gender { json += #","gender":"\#(g)""# }
    if let id = identifier {
        json += #","identifier":[{"system":"\#(identifierSystem)","value":"\#(id)"}]"#
    }
    json += "}"
    return try JSONDecoder().decode(ModelsR4.Practitioner.self, from: Data(json.utf8))
}

func makeOrganization(
    name: String,
    active: Bool = true,
    type: String? = nil,
    typeSystem: String = "http://terminology.hl7.org/CodeSystem/organization-type",
    identifier: String? = nil,
    identifierSystem: String = "http://hl7.org/fhir/sid/us-npi"
) throws -> ModelsR4.Organization {
    var json = #"{"resourceType":"Organization","name":"\#(name)","active":\#(active)"#
    if let t = type {
        json += #","type":[{"coding":[{"system":"\#(typeSystem)","code":"\#(t)"}]}]"#
    }
    if let id = identifier {
        json += #","identifier":[{"system":"\#(identifierSystem)","value":"\#(id)"}]"#
    }
    json += "}"
    return try JSONDecoder().decode(ModelsR4.Organization.self, from: Data(json.utf8))
}

func makeLocation(
    name: String,
    status: String = "active",
    type: String? = nil,
    typeSystem: String = "http://terminology.hl7.org/CodeSystem/v3-RoleCode",
    city: String? = nil,
    managingOrganizationId: String? = nil
) throws -> ModelsR4.Location {
    var json = #"{"resourceType":"Location","name":"\#(name)","status":"\#(status)""#
    if let t = type {
        json += #","type":[{"coding":[{"system":"\#(typeSystem)","code":"\#(t)"}]}]"#
    }
    if let c = city {
        json += #","address":{"city":"\#(c)"}"#
    }
    if let orgId = managingOrganizationId {
        json += #","managingOrganization":{"reference":"Organization/\#(orgId)"}"#
    }
    json += "}"
    return try JSONDecoder().decode(ModelsR4.Location.self, from: Data(json.utf8))
}

func makeRelatedPerson(
    patientId: String,
    family: String = "Smith",
    given: String = "Jane",
    relationship: String = "spouse",
    relationshipSystem: String = "http://terminology.hl7.org/CodeSystem/v3-RoleCode",
    gender: String? = nil,
    birthDate: String? = nil,
    active: Bool? = nil
) throws -> ModelsR4.RelatedPerson {
    var json = #"""
    {"resourceType":"RelatedPerson",
     "patient":{"reference":"Patient/\#(patientId)"},
     "relationship":[{"coding":[{"system":"\#(relationshipSystem)","code":"\#(relationship)"}]}],
     "name":[{"family":"\#(family)","given":["\#(given)"]}]
    """#
    if let g = gender { json += #","gender":"\#(g)""# }
    if let bd = birthDate { json += #","birthDate":"\#(bd)""# }
    if let a = active { json += #","active":\#(a)"# }
    json += "}"
    return try JSONDecoder().decode(ModelsR4.RelatedPerson.self, from: Data(json.utf8))
}

func makeServiceRequest(
    patientId: String,
    status: String = "active",
    intent: String = "order",
    priority: String? = nil,
    code: String? = nil,
    codeSystem: String = "http://snomed.info/sct",
    category: String? = nil,
    categorySystem: String = "http://snomed.info/sct",
    authoredOn: String? = nil,
    encounterRef: String? = nil
) throws -> ModelsR4.ServiceRequest {
    var json = #"""
    {"resourceType":"ServiceRequest",
     "status":"\#(status)",
     "intent":"\#(intent)",
     "subject":{"reference":"Patient/\#(patientId)"}
    """#
    if let p = priority { json += #","priority":"\#(p)""# }
    if let c = code {
        json += #","code":{"coding":[{"system":"\#(codeSystem)","code":"\#(c)"}]}"#
    }
    if let c = category {
        json += #","category":[{"coding":[{"system":"\#(categorySystem)","code":"\#(c)"}]}]"#
    }
    if let a = authoredOn { json += #","authoredOn":"\#(a)""# }
    if let e = encounterRef { json += #","encounter":{"reference":"\#(e)"}"# }
    json += "}"
    return try JSONDecoder().decode(ModelsR4.ServiceRequest.self, from: Data(json.utf8))
}

func makeSpecimen(
    patientId: String,
    status: String? = nil,
    specimenType: String? = nil,
    typeSystem: String = "http://snomed.info/sct",
    collectedDate: String? = nil,
    accession: String? = nil,
    accessionSystem: String? = nil
) throws -> ModelsR4.Specimen {
    var json = #"{"resourceType":"Specimen","subject":{"reference":"Patient/\#(patientId)"}"#
    if let s = status { json += #","status":"\#(s)""# }
    if let t = specimenType {
        json += #","type":{"coding":[{"system":"\#(typeSystem)","code":"\#(t)"}]}"#
    }
    if let d = collectedDate {
        json += #","collection":{"collectedDateTime":"\#(d)"}"#
    }
    if let acc = accession {
        var accJSON = #","accessionIdentifier":{"value":"\#(acc)""#
        if let sys = accessionSystem { accJSON += #","system":"\#(sys)""# }
        accJSON += "}"
        json += accJSON
    }
    json += "}"
    return try JSONDecoder().decode(ModelsR4.Specimen.self, from: Data(json.utf8))
}

func makeDocumentReference(
    patientId: String,
    status: String = "current",
    docType: String? = nil,
    typeSystem: String = "http://loinc.org",
    category: String? = nil,
    categorySystem: String = "http://loinc.org",
    date: String? = nil,
    description: String? = nil,
    encounterId: String? = nil
) throws -> ModelsR4.DocumentReference {
    var json = #"""
    {"resourceType":"DocumentReference",
     "status":"\#(status)",
     "subject":{"reference":"Patient/\#(patientId)"},
     "content":[{"attachment":{"contentType":"text/plain","url":"http://example.com/doc"}}]
    """#
    if let t = docType {
        json += #","type":{"coding":[{"system":"\#(typeSystem)","code":"\#(t)"}]}"#
    }
    if let c = category {
        json += #","category":[{"coding":[{"system":"\#(categorySystem)","code":"\#(c)"}]}]"#
    }
    if let d = date { json += #","date":"\#(d)""# }
    if let desc = description { json += #","description":"\#(desc)""# }
    if let encId = encounterId {
        json += #","context":{"encounter":[{"reference":"Encounter/\#(encId)"}]}"#
    }
    json += "}"
    return try JSONDecoder().decode(ModelsR4.DocumentReference.self, from: Data(json.utf8))
}

func makeAllergyIntolerance(patientId: String, clinicalStatus: String = "active", recordedDate: String? = nil) throws -> ModelsR4.AllergyIntolerance {
    var json = #"""
    {"resourceType":"AllergyIntolerance",
     "clinicalStatus":{"coding":[{"system":"http://terminology.hl7.org/CodeSystem/allergyintolerance-clinical","code":"\#(clinicalStatus)"}]},
     "verificationStatus":{"coding":[{"system":"http://terminology.hl7.org/CodeSystem/allergyintolerance-verification","code":"confirmed"}]},
     "code":{"coding":[{"system":"http://www.nlm.nih.gov/research/umls/rxnorm","code":"7982","display":"Penicillin"}]},
     "patient":{"reference":"Patient/\#(patientId)"}
    """#
    if let d = recordedDate { json += #","recordedDate":"\#(d)""# }
    json += "}"
    return try JSONDecoder().decode(ModelsR4.AllergyIntolerance.self, from: Data(json.utf8))
}
