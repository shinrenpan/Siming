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

    func makeCarePlanStore() throws -> CarePlanStore {
        CarePlanStore(client: try requiredClient(), logger: logger)
    }

    func makeGoalStore() throws -> GoalStore {
        GoalStore(client: try requiredClient(), logger: logger)
    }

    func makeMedicationStatementStore() throws -> MedicationStatementStore {
        MedicationStatementStore(client: try requiredClient(), logger: logger)
    }

    func makeFamilyMemberHistoryStore() throws -> FamilyMemberHistoryStore {
        FamilyMemberHistoryStore(client: try requiredClient(), logger: logger)
    }

    func makeAppointmentStore() throws -> AppointmentStore {
        AppointmentStore(client: try requiredClient(), logger: logger)
    }

    func makeMedicationAdministrationStore() throws -> MedicationAdministrationStore {
        MedicationAdministrationStore(client: try requiredClient(), logger: logger)
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
    gender: String? = nil,
    birthYear: Int? = nil,
    birthMonth: Int? = nil,
    birthDay: Int? = nil,
    deceasedBoolean: Bool? = nil,
    deceasedDateTime: String? = nil
) throws -> ModelsR4.Patient {
    var json = #"{"resourceType":"Patient","name":[{"family":"\#(family)","given":["\#(given)"]}]"#
    if let g = gender { json += #","gender":"\#(g)""# }
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
    if let db = deceasedBoolean   { json += #","deceasedBoolean":\#(db)"# }
    if let dd = deceasedDateTime  { json += #","deceasedDateTime":"\#(dd)""# }
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

func makeObservation(
    subjectId: String,
    code: String = "29463-7",
    status: String = "final",
    specimenId: String? = nil,
    hasMemberId: String? = nil,
    partOfId: String? = nil,
    methodCode: String? = nil,
    valueQuantity: Double? = nil,
    valueConcept: String? = nil,
    valueString: String? = nil,
    valueDateTime: String? = nil,
    componentCode: String? = nil,
    dataAbsentReasonCode: String? = nil,
    componentValueConceptCode: String? = nil,
    componentDataAbsentReasonCode: String? = nil
) throws -> ModelsR4.Observation {
    var json = #"""
    {"resourceType":"Observation","status":"\#(status)",
     "code":{"coding":[{"system":"http://loinc.org","code":"\#(code)"}]},
     "subject":{"reference":"Patient/\#(subjectId)"}
    """#
    if let sid = specimenId { json += #","specimen":{"reference":"Specimen/\#(sid)"}"# }
    if let hid = hasMemberId { json += #","hasMember":[{"reference":"Observation/\#(hid)"}]"# }
    if let pid = partOfId { json += #","partOf":[{"reference":"Observation/\#(pid)"}]"# }
    if let m = methodCode { json += #","method":{"coding":[{"system":"http://snomed.info/sct","code":"\#(m)"}]}"# }
    if let vq = valueQuantity { json += #","valueQuantity":{"value":\#(vq),"system":"http://unitsofmeasure.org","code":"kg"}"# }
    if let vc = valueConcept { json += #","valueCodeableConcept":{"coding":[{"system":"http://snomed.info/sct","code":"\#(vc)"}]}"# }
    if let vs = valueString { json += #","valueString":"\#(vs)""# }
    if let vd = valueDateTime { json += #","valueDateTime":"\#(vd)""# }
    if let dar = dataAbsentReasonCode {
        json += #","dataAbsentReason":{"coding":[{"system":"http://terminology.hl7.org/CodeSystem/data-absent-reason","code":"\#(dar)"}]}"#
    }
    if let cc = componentCode {
        if let cvc = componentValueConceptCode {
            json += #","component":[{"code":{"coding":[{"system":"http://loinc.org","code":"\#(cc)"}]},"valueCodeableConcept":{"coding":[{"system":"http://snomed.info/sct","code":"\#(cvc)"}]}}]"#
        } else if let cdar = componentDataAbsentReasonCode {
            json += #","component":[{"code":{"coding":[{"system":"http://loinc.org","code":"\#(cc)"}]},"dataAbsentReason":{"coding":[{"system":"http://terminology.hl7.org/CodeSystem/data-absent-reason","code":"\#(cdar)"}]}}]"#
        } else {
            json += #","component":[{"code":{"coding":[{"system":"http://loinc.org","code":"\#(cc)"}]},"valueQuantity":{"value":1,"unit":"mmHg"}}]"#
        }
    } else if let cdar = componentDataAbsentReasonCode {
        json += #","component":[{"code":{"coding":[{"system":"http://loinc.org","code":"unknown"}]},"dataAbsentReason":{"coding":[{"system":"http://terminology.hl7.org/CodeSystem/data-absent-reason","code":"\#(cdar)"}]}}]"#
    }
    json += "}"
    return try JSONDecoder().decode(ModelsR4.Observation.self, from: Data(json.utf8))
}

func makeEncounter(
    subjectId: String,
    status: String = "finished",
    participantId: String? = nil,
    practitionerId: String? = nil,
    participantTypeCode: String? = nil,
    reasonCode: String? = nil,
    partOfId: String? = nil,
    serviceProviderId: String? = nil,
    basedOnId: String? = nil,
    locationId: String? = nil,
    locationPeriodStart: String? = nil,
    locationPeriodEnd: String? = nil,
    diagnosisId: String? = nil,
    accountId: String? = nil,
    appointmentId: String? = nil,
    episodeOfCareId: String? = nil,
    reasonReferenceId: String? = nil,
    specialArrangementCode: String? = nil,
    lengthValue: Double? = nil
) throws -> ModelsR4.Encounter {
    var json = #"""
    {"resourceType":"Encounter","status":"\#(status)",
     "class":{"system":"http://terminology.hl7.org/CodeSystem/v3-ActCode","code":"AMB"},
     "subject":{"reference":"Patient/\#(subjectId)"}
    """#
    if let pid = participantId {
        if let tc = participantTypeCode {
            json += #","participant":[{"type":[{"coding":[{"system":"http://terminology.hl7.org/CodeSystem/v3-ParticipationType","code":"\#(tc)"}]}],"individual":{"reference":"Practitioner/\#(pid)"}}]"#
        } else {
            json += #","participant":[{"individual":{"reference":"Practitioner/\#(pid)"}}]"#
        }
    } else if let pid = practitionerId {
        if let tc = participantTypeCode {
            json += #","participant":[{"type":[{"coding":[{"system":"http://terminology.hl7.org/CodeSystem/v3-ParticipationType","code":"\#(tc)"}]}],"individual":{"reference":"Practitioner/\#(pid)"}}]"#
        } else {
            json += #","participant":[{"individual":{"reference":"Practitioner/\#(pid)"}}]"#
        }
    } else if let tc = participantTypeCode {
        json += #","participant":[{"type":[{"coding":[{"system":"http://terminology.hl7.org/CodeSystem/v3-ParticipationType","code":"\#(tc)"}]}]}]"#
    }
    if let rc = reasonCode {
        json += #","reasonCode":[{"coding":[{"system":"http://snomed.info/sct","code":"\#(rc)"}]}]"#
    }
    if let pid = partOfId {
        json += #","partOf":{"reference":"Encounter/\#(pid)"}"#
    }
    if let oid = serviceProviderId {
        json += #","serviceProvider":{"reference":"Organization/\#(oid)"}"#
    }
    if let bid = basedOnId {
        json += #","basedOn":[{"reference":"ServiceRequest/\#(bid)"}]"#
    }
    if let lid = locationId {
        if let ps = locationPeriodStart {
            if let pe = locationPeriodEnd {
                json += #","location":[{"location":{"reference":"Location/\#(lid)"},"period":{"start":"\#(ps)","end":"\#(pe)"}}]"#
            } else {
                json += #","location":[{"location":{"reference":"Location/\#(lid)"},"period":{"start":"\#(ps)"}}]"#
            }
        } else {
            json += #","location":[{"location":{"reference":"Location/\#(lid)"}}]"#
        }
    } else if let ps = locationPeriodStart {
        if let pe = locationPeriodEnd {
            json += #","location":[{"location":{"reference":"Location/unknown"},"period":{"start":"\#(ps)","end":"\#(pe)"}}]"#
        } else {
            json += #","location":[{"location":{"reference":"Location/unknown"},"period":{"start":"\#(ps)"}}]"#
        }
    }
    if let did = diagnosisId {
        json += #","diagnosis":[{"condition":{"reference":"Condition/\#(did)"},"use":{"coding":[{"code":"CC"}]}}]"#
    }
    if let aid = accountId {
        json += #","account":[{"reference":"Account/\#(aid)"}]"#
    }
    if let aid = appointmentId {
        json += #","appointment":[{"reference":"Appointment/\#(aid)"}]"#
    }
    if let eid = episodeOfCareId {
        json += #","episodeOfCare":[{"reference":"EpisodeOfCare/\#(eid)"}]"#
    }
    if let rid = reasonReferenceId {
        json += #","reasonReference":[{"reference":"Condition/\#(rid)"}]"#
    }
    if let sc = specialArrangementCode {
        json += #","hospitalization":{"specialArrangement":[{"coding":[{"system":"http://terminology.hl7.org/CodeSystem/v3-EncounterSpecialCourtesy","code":"\#(sc)"}]}]}"#
    }
    if let lv = lengthValue {
        json += #","length":{"value":\#(lv),"system":"http://unitsofmeasure.org","code":"min"}"#
    }
    json += "}"
    return try JSONDecoder().decode(ModelsR4.Encounter.self, from: Data(json.utf8))
}

func makeCondition(
    subjectId: String,
    clinicalStatus: String = "active",
    onsetDate: String? = nil,
    asserterId: String? = nil,
    bodySiteCode: String? = nil,
    evidenceCode: String? = nil,
    evidenceDetailId: String? = nil,
    severityCode: String? = nil,
    stageCode: String? = nil,
    onsetString: String? = nil,
    abatementString: String? = nil,
    onsetAgeValue: Double? = nil,
    abatementAgeValue: Double? = nil
) throws -> ModelsR4.Condition {
    var json = #"""
    {"resourceType":"Condition",
     "clinicalStatus":{"coding":[{"system":"http://terminology.hl7.org/CodeSystem/condition-clinical","code":"\#(clinicalStatus)"}]},
     "code":{"coding":[{"system":"http://snomed.info/sct","code":"73211009","display":"Diabetes mellitus"}]},
     "subject":{"reference":"Patient/\#(subjectId)"}
    """#
    if let d = onsetDate        { json += #","onsetDateTime":"\#(d)""# }
    if let s = onsetString      { json += #","onsetString":"\#(s)""# }
    if let a = onsetAgeValue    { json += #","onsetAge":{"value":\#(a),"system":"http://unitsofmeasure.org","code":"a"}"# }
    if let a = abatementString  { json += #","abatementString":"\#(a)""# }
    if let a = abatementAgeValue { json += #","abatementAge":{"value":\#(a),"system":"http://unitsofmeasure.org","code":"a"}"# }
    if let aid = asserterId     { json += #","asserter":{"reference":"Practitioner/\#(aid)"}"# }
    if let bc = bodySiteCode    { json += #","bodySite":[{"coding":[{"system":"http://snomed.info/sct","code":"\#(bc)"}]}]"# }
    if let ec = evidenceCode    { json += #","evidence":[{"code":[{"coding":[{"system":"http://snomed.info/sct","code":"\#(ec)"}]}]}]"# }
    if let eid = evidenceDetailId { json += #","evidence":[{"detail":[{"reference":"DiagnosticReport/\#(eid)"}]}]"# }
    if let sc = severityCode    { json += #","severity":{"coding":[{"system":"http://snomed.info/sct","code":"\#(sc)"}]}"# }
    if let stc = stageCode      { json += #","stage":[{"summary":{"coding":[{"system":"http://snomed.info/sct","code":"\#(stc)"}]}}]"# }
    json += "}"
    return try JSONDecoder().decode(ModelsR4.Condition.self, from: Data(json.utf8))
}

func makeMedicationRequest(
    subjectId: String,
    status: String = "active",
    intent: String = "order",
    authoredOn: String? = nil,
    intendedDispenserId: String? = nil,
    intendedPerformerId: String? = nil,
    intendedPerformerTypeCode: String? = nil,
    medicationReferenceId: String? = nil
) throws -> ModelsR4.MedicationRequest {
    let medField: String
    if let mid = medicationReferenceId {
        medField = #""medicationReference":{"reference":"Medication/\#(mid)"}"#
    } else {
        medField = #""medicationCodeableConcept":{"coding":[{"system":"http://www.nlm.nih.gov/research/umls/rxnorm","code":"1049502"}]}"#
    }
    var json = #"""
    {"resourceType":"MedicationRequest","status":"\#(status)","intent":"\#(intent)",
     \#(medField),
     "subject":{"reference":"Patient/\#(subjectId)"}
    """#
    if let d = authoredOn             { json += #","authoredOn":"\#(d)""# }
    if let did = intendedDispenserId  { json += #","dispenseRequest":{"performer":{"reference":"Organization/\#(did)"}}"# }
    if let pid = intendedPerformerId  { json += #","performer":{"reference":"Practitioner/\#(pid)"}"# }
    if let tc = intendedPerformerTypeCode {
        json += #","performerType":{"coding":[{"system":"http://snomed.info/sct","code":"\#(tc)"}]}"#
    }
    json += "}"
    return try JSONDecoder().decode(ModelsR4.MedicationRequest.self, from: Data(json.utf8))
}

func makeProcedure(
    subjectId: String,
    status: String = "completed",
    code: String = "73761001",
    codeSystem: String = "http://snomed.info/sct",
    performedDate: String? = nil,
    basedOnId: String? = nil,
    locationId: String? = nil,
    partOfId: String? = nil,
    reasonCode: String? = nil,
    reasonReferenceId: String? = nil,
    instantiatesCanonical: String? = nil,
    instantiatesUri: String? = nil
) throws -> ModelsR4.Procedure {
    var json = #"""
    {"resourceType":"Procedure","status":"\#(status)",
     "code":{"coding":[{"system":"\#(codeSystem)","code":"\#(code)","display":"Colonoscopy"}]},
     "subject":{"reference":"Patient/\#(subjectId)"}
    """#
    if let d = performedDate   { json += #","performedDateTime":"\#(d)""# }
    if let b = basedOnId       { json += #","basedOn":[{"reference":"ServiceRequest/\#(b)"}]"# }
    if let l = locationId      { json += #","location":{"reference":"Location/\#(l)"}"# }
    if let p = partOfId        { json += #","partOf":[{"reference":"Procedure/\#(p)"}]"# }
    if let r = reasonCode      { json += #","reasonCode":[{"coding":[{"system":"http://snomed.info/sct","code":"\#(r)"}]}]"# }
    if let rr = reasonReferenceId { json += #","reasonReference":[{"reference":"Condition/\#(rr)"}]"# }
    if let ic = instantiatesCanonical { json += #","instantiatesCanonical":["\#(ic)"]"# }
    if let iu = instantiatesUri       { json += #","instantiatesUri":["\#(iu)"]"# }
    json += "}"
    return try JSONDecoder().decode(ModelsR4.Procedure.self, from: Data(json.utf8))
}

func makeDiagnosticReport(
    subjectId: String,
    status: String = "final",
    code: String = "58410-2",
    codeSystem: String = "http://loinc.org",
    effectiveDate: String? = nil,
    issued: String? = nil,
    basedOnId: String? = nil,
    specimenId: String? = nil,
    resultId: String? = nil,
    mediaId: String? = nil,
    conclusionCode: String? = nil,
    resultsInterpreterId: String? = nil
) throws -> ModelsR4.DiagnosticReport {
    var json = #"""
    {"resourceType":"DiagnosticReport","status":"\#(status)",
     "code":{"coding":[{"system":"\#(codeSystem)","code":"\#(code)","display":"CBC panel"}]},
     "subject":{"reference":"Patient/\#(subjectId)"}
    """#
    if let d = effectiveDate       { json += #","effectiveDateTime":"\#(d)""# }
    if let i = issued              { json += #","issued":"\#(i)""# }
    if let b = basedOnId           { json += #","basedOn":[{"reference":"ServiceRequest/\#(b)"}]"# }
    if let s = specimenId          { json += #","specimen":[{"reference":"Specimen/\#(s)"}]"# }
    if let r = resultId            { json += #","result":[{"reference":"Observation/\#(r)"}]"# }
    if let m = mediaId             { json += #","media":[{"link":{"reference":"Media/\#(m)"}}]"# }
    if let c = conclusionCode      { json += #","conclusionCode":[{"coding":[{"system":"http://snomed.info/sct","code":"\#(c)"}]}]"# }
    if let ri = resultsInterpreterId { json += #","resultsInterpreter":[{"reference":"Practitioner/\#(ri)"}]"# }
    json += "}"
    return try JSONDecoder().decode(ModelsR4.DiagnosticReport.self, from: Data(json.utf8))
}

func makeImmunization(
    patientId: String,
    status: String = "completed",
    vaccineCode: String = "207",
    vaccineSystem: String = "http://hl7.org/fhir/sid/cvx",
    occurrenceDate: String = "2021-01-15",
    lotNumber: String? = nil,
    locationId: String? = nil,
    manufacturerId: String? = nil,
    reactionDetailId: String? = nil,
    reactionDate: String? = nil,
    reasonCode: String? = nil,
    reasonReferenceId: String? = nil,
    series: String? = nil,
    statusReasonCode: String? = nil,
    targetDiseaseCode: String? = nil
) throws -> ModelsR4.Immunization {
    var json = #"""
    {"resourceType":"Immunization","status":"\#(status)",
     "vaccineCode":{"coding":[{"system":"\#(vaccineSystem)","code":"\#(vaccineCode)","display":"COVID-19 mRNA"}]},
     "patient":{"reference":"Patient/\#(patientId)"},
     "occurrenceDateTime":"\#(occurrenceDate)"
    """#
    if let ln = lotNumber         { json += #","lotNumber":"\#(ln)""# }
    if let loc = locationId       { json += #","location":{"reference":"Location/\#(loc)"}"# }
    if let mfr = manufacturerId   { json += #","manufacturer":{"reference":"Organization/\#(mfr)"}"# }
    if let rd = reactionDetailId, let rxDate = reactionDate {
        json += #","reaction":[{"date":"\#(rxDate)","detail":{"reference":"Observation/\#(rd)"}}]"#
    } else if let rd = reactionDetailId {
        json += #","reaction":[{"detail":{"reference":"Observation/\#(rd)"}}]"#
    } else if let rxDate = reactionDate {
        json += #","reaction":[{"date":"\#(rxDate)"}]"#
    }
    if let rc = reasonCode        { json += #","reasonCode":[{"coding":[{"system":"http://snomed.info/sct","code":"\#(rc)"}]}]"# }
    if let rr = reasonReferenceId { json += #","reasonReference":[{"reference":"Condition/\#(rr)"}]"# }
    if let s = series             { json += #","protocolApplied":[{"series":"\#(s)","doseNumberPositiveInt":1}]"# }
    else if let td = targetDiseaseCode { json += #","protocolApplied":[{"targetDisease":[{"coding":[{"system":"http://snomed.info/sct","code":"\#(td)"}]}],"doseNumberPositiveInt":1}]"# }
    if let sr = statusReasonCode  { json += #","statusReason":{"coding":[{"system":"http://terminology.hl7.org/CodeSystem/v3-ActReason","code":"\#(sr)"}]}"# }
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
    identifierSystem: String = "http://hl7.org/fhir/sid/us-npi",
    endpointId: String? = nil
) throws -> ModelsR4.Organization {
    var json = #"{"resourceType":"Organization","name":"\#(name)","active":\#(active)"#
    if let t = type {
        json += #","type":[{"coding":[{"system":"\#(typeSystem)","code":"\#(t)"}]}]"#
    }
    if let id = identifier {
        json += #","identifier":[{"system":"\#(identifierSystem)","value":"\#(id)"}]"#
    }
    if let ep = endpointId {
        json += #","endpoint":[{"reference":"Endpoint/\#(ep)"}]"#
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
    managingOrganizationId: String? = nil,
    endpointId: String? = nil
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
    if let ep = endpointId {
        json += #","endpoint":[{"reference":"Endpoint/\#(ep)"}]"#
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
    encounterRef: String? = nil,
    instantiatesUri: String? = nil,
    orderDetailCode: String? = nil
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
    if let u = instantiatesUri { json += #","instantiatesUri":["\#(u)"]"# }
    if let od = orderDetailCode {
        json += #","orderDetail":[{"coding":[{"system":"http://snomed.info/sct","code":"\#(od)"}]}]"#
    }
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
    encounterId: String? = nil,
    relatesToTarget: String? = nil,
    relatesToCode: String = "replaces",
    relatedRef: String? = nil
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
    if let encId = encounterId, relatedRef == nil {
        json += #","context":{"encounter":[{"reference":"Encounter/\#(encId)"}]}"#
    } else if let encId = encounterId, let rr = relatedRef {
        json += #","context":{"encounter":[{"reference":"Encounter/\#(encId)"}],"related":[{"reference":"\#(rr)"}]}"#
    } else if let rr = relatedRef {
        json += #","context":{"related":[{"reference":"\#(rr)"}]}"#
    }
    if let target = relatesToTarget {
        json += #","relatesTo":[{"code":"\#(relatesToCode)","target":{"reference":"\#(target)"}}]"#
    }
    json += "}"
    return try JSONDecoder().decode(ModelsR4.DocumentReference.self, from: Data(json.utf8))
}

func makeCarePlan(
    patientId: String,
    status: String = "active",
    intent: String = "plan",
    category: String? = nil,
    categorySystem: String = "http://hl7.org/fhir/us/core/CodeSystem/careplan-category",
    periodStart: String? = nil,
    periodEnd: String? = nil,
    encounterId: String? = nil,
    activityCode: String? = nil,
    activityCodeSystem: String = "http://snomed.info/sct",
    activityDateStart: String? = nil,
    activityDateEnd: String? = nil,
    instantiatesCanonical: String? = nil,
    instantiatesUri: String? = nil
) throws -> ModelsR4.CarePlan {
    var json = #"""
    {"resourceType":"CarePlan",
     "status":"\#(status)",
     "intent":"\#(intent)",
     "subject":{"reference":"Patient/\#(patientId)"}
    """#
    if let c = category {
        json += #","category":[{"coding":[{"system":"\#(categorySystem)","code":"\#(c)"}]}]"#
    }
    if periodStart != nil || periodEnd != nil {
        json += #","period":{"#
        var parts: [String] = []
        if let s = periodStart { parts.append(#""start":"\#(s)""#) }
        if let e = periodEnd   { parts.append(#""end":"\#(e)""#) }
        json += parts.joined(separator: ",") + "}"
    }
    if let encId = encounterId {
        json += #","encounter":{"reference":"Encounter/\#(encId)"}"#
    }
    if let code = activityCode {
        let schedPart: String
        if let ds = activityDateStart {
            let de = activityDateEnd ?? ds
            schedPart = #","scheduledPeriod":{"start":"\#(ds)","end":"\#(de)"}"#
        } else { schedPart = "" }
        json += #","activity":[{"detail":{"status":"not-started","code":{"coding":[{"system":"\#(activityCodeSystem)","code":"\#(code)"}]}\#(schedPart)}}]"#
    } else if let ds = activityDateStart {
        let de = activityDateEnd ?? ds
        json += #","activity":[{"detail":{"status":"not-started","scheduledPeriod":{"start":"\#(ds)","end":"\#(de)"}}}]"#
    }
    if let ic = instantiatesCanonical {
        json += #","instantiatesCanonical":["\#(ic)"]"#
    }
    if let iu = instantiatesUri {
        json += #","instantiatesUri":["\#(iu)"]"#
    }
    json += "}"
    return try JSONDecoder().decode(ModelsR4.CarePlan.self, from: Data(json.utf8))
}

func makeGoal(
    patientId: String,
    lifecycleStatus: String = "active",
    category: String? = nil,
    categorySystem: String = "http://hl7.org/fhir/us/core/CodeSystem/goal-category",
    startDate: String? = nil,
    targetDate: String? = nil,
    identifier: String? = nil,
    identifierSystem: String = "http://example.org"
) throws -> ModelsR4.Goal {
    var json = #"""
    {"resourceType":"Goal",
     "lifecycleStatus":"\#(lifecycleStatus)",
     "description":{"text":"Goal"},
     "subject":{"reference":"Patient/\#(patientId)"}
    """#
    if let c = category {
        json += #","category":[{"coding":[{"system":"\#(categorySystem)","code":"\#(c)"}]}]"#
    }
    if let sd = startDate {
        json += #","startDate":"\#(sd)""#
    }
    if let td = targetDate {
        json += #","target":[{"dueDate":"\#(td)"}]"#
    }
    if let id = identifier {
        json += #","identifier":[{"system":"\#(identifierSystem)","value":"\#(id)"}]"#
    }
    json += "}"
    return try JSONDecoder().decode(ModelsR4.Goal.self, from: Data(json.utf8))
}

func makeMedicationStatement(
    patientId: String,
    status: String = "active",
    medicationCode: String = "1049502",
    medicationSystem: String = "http://www.nlm.nih.gov/research/umls/rxnorm",
    category: String? = nil,
    categorySystem: String = "http://terminology.hl7.org/CodeSystem/medication-statement-category",
    effectiveDateTime: String? = nil,
    identifier: String? = nil,
    identifierSystem: String = "http://example.org"
) throws -> ModelsR4.MedicationStatement {
    var json = #"""
    {"resourceType":"MedicationStatement",
     "status":"\#(status)",
     "medicationCodeableConcept":{"coding":[{"system":"\#(medicationSystem)","code":"\#(medicationCode)"}]},
     "subject":{"reference":"Patient/\#(patientId)"}
    """#
    if let c = category {
        json += #","category":{"coding":[{"system":"\#(categorySystem)","code":"\#(c)"}]}"#
    }
    if let dt = effectiveDateTime {
        json += #","effectiveDateTime":"\#(dt)""#
    }
    if let id = identifier {
        json += #","identifier":[{"system":"\#(identifierSystem)","value":"\#(id)"}]"#
    }
    json += "}"
    return try JSONDecoder().decode(ModelsR4.MedicationStatement.self, from: Data(json.utf8))
}

func makeFamilyMemberHistory(
    patientId: String,
    status: String = "partial",
    relationship: String = "FAMMEMB",
    relationshipSystem: String = "http://terminology.hl7.org/CodeSystem/v3-RoleCode",
    sex: String? = nil,
    sexSystem: String = "http://hl7.org/fhir/administrative-gender",
    conditionCode: String? = nil,
    conditionCodeSystem: String = "http://snomed.info/sct",
    date: String? = nil,
    identifier: String? = nil,
    identifierSystem: String = "http://example.org",
    instantiatesCanonical: String? = nil,
    instantiatesUri: String? = nil
) throws -> ModelsR4.FamilyMemberHistory {
    var json = #"""
    {"resourceType":"FamilyMemberHistory",
     "status":"\#(status)",
     "patient":{"reference":"Patient/\#(patientId)"},
     "relationship":{"coding":[{"system":"\#(relationshipSystem)","code":"\#(relationship)"}]}
    """#
    if let s = sex {
        json += #","sex":{"coding":[{"system":"\#(sexSystem)","code":"\#(s)"}]}"#
    }
    if let cc = conditionCode {
        json += #","condition":[{"code":{"coding":[{"system":"\#(conditionCodeSystem)","code":"\#(cc)"}]}}]"#
    }
    if let d = date {
        json += #","date":"\#(d)""#
    }
    if let id = identifier {
        json += #","identifier":[{"system":"\#(identifierSystem)","value":"\#(id)"}]"#
    }
    if let ic = instantiatesCanonical {
        json += #","instantiatesCanonical":["\#(ic)"]"#
    }
    if let iu = instantiatesUri {
        json += #","instantiatesUri":["\#(iu)"]"#
    }
    json += "}"
    return try JSONDecoder().decode(ModelsR4.FamilyMemberHistory.self, from: Data(json.utf8))
}

func makeAllergyIntolerance(
    patientId: String,
    clinicalStatus: String = "active",
    recordedDate: String? = nil,
    asserterId: String? = nil,
    recorderId: String? = nil
) throws -> ModelsR4.AllergyIntolerance {
    var json = #"""
    {"resourceType":"AllergyIntolerance",
     "clinicalStatus":{"coding":[{"system":"http://terminology.hl7.org/CodeSystem/allergyintolerance-clinical","code":"\#(clinicalStatus)"}]},
     "verificationStatus":{"coding":[{"system":"http://terminology.hl7.org/CodeSystem/allergyintolerance-verification","code":"confirmed"}]},
     "code":{"coding":[{"system":"http://www.nlm.nih.gov/research/umls/rxnorm","code":"7982","display":"Penicillin"}]},
     "patient":{"reference":"Patient/\#(patientId)"}
    """#
    if let d = recordedDate  { json += #","recordedDate":"\#(d)""# }
    if let a = asserterId    { json += #","asserter":{"reference":"Practitioner/\#(a)"}"# }
    if let r = recorderId    { json += #","recorder":{"reference":"Practitioner/\#(r)"}"# }
    json += "}"
    return try JSONDecoder().decode(ModelsR4.AllergyIntolerance.self, from: Data(json.utf8))
}

func makeAppointment(
    patientId: String,
    status: String = "booked",
    start: String? = "2024-06-01T09:00:00Z",
    end: String? = "2024-06-01T09:30:00Z",
    serviceTypeCode: String? = nil,
    specialtyCode: String? = nil,
    identifier: String? = nil,
    identifierSystem: String = "http://example.org",
    supportingInfoRef: String? = nil
) throws -> ModelsR4.Appointment {
    var json = #"""
    {"resourceType":"Appointment",
     "status":"\#(status)",
     "participant":[{"actor":{"reference":"Patient/\#(patientId)"},"status":"accepted"}]
    """#
    if let s = start { json += #","start":"\#(s)""# }
    if let e = end   { json += #","end":"\#(e)""# }
    if let code = serviceTypeCode {
        json += #","serviceType":[{"coding":[{"system":"http://terminology.hl7.org/CodeSystem/service-type","code":"\#(code)"}]}]"#
    }
    if let code = specialtyCode {
        json += #","specialty":[{"coding":[{"system":"http://snomed.info/sct","code":"\#(code)"}]}]"#
    }
    if let id = identifier {
        json += #","identifier":[{"system":"\#(identifierSystem)","value":"\#(id)"}]"#
    }
    if let ref = supportingInfoRef {
        json += #","supportingInformation":[{"reference":"\#(ref)"}]"#
    }
    json += "}"
    return try JSONDecoder().decode(ModelsR4.Appointment.self, from: Data(json.utf8))
}

func makeMedicationAdministration(
    patientId: String,
    status: String = "completed",
    medicationCode: String = "1049502",
    medicationSystem: String = "http://www.nlm.nih.gov/research/umls/rxnorm",
    effectiveDateTime: String? = "2024-06-01T09:00:00Z",
    requestId: String? = nil,
    reasonGivenCode: String? = nil,
    identifier: String? = nil,
    identifierSystem: String = "http://example.org"
) throws -> ModelsR4.MedicationAdministration {
    var json = #"""
    {"resourceType":"MedicationAdministration",
     "status":"\#(status)",
     "medicationCodeableConcept":{"coding":[{"system":"\#(medicationSystem)","code":"\#(medicationCode)"}]},
     "subject":{"reference":"Patient/\#(patientId)"}
    """#
    if let dt = effectiveDateTime {
        json += #","effectiveDateTime":"\#(dt)""#
    }
    if let rid = requestId {
        json += #","request":{"reference":"MedicationRequest/\#(rid)"}"#
    }
    if let code = reasonGivenCode {
        json += #","reasonCode":[{"coding":[{"system":"http://snomed.info/sct","code":"\#(code)"}]}]"#
    }
    if let id = identifier {
        json += #","identifier":[{"system":"\#(identifierSystem)","value":"\#(id)"}]"#
    }
    json += "}"
    return try JSONDecoder().decode(ModelsR4.MedicationAdministration.self, from: Data(json.utf8))
}
