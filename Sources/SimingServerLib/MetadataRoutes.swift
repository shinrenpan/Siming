import Foundation
import Hummingbird
import ModelsR4
import NIOCore

public func addMetadataRoutes(
    to router: Router<BasicRequestContext>,
    smartConfig: SmartConfiguration? = nil
) {
    // GET /metadata — FHIR CapabilityStatement
    router.get("metadata") { _, _ in
        let cs = buildCapabilityStatement(smartConfig: smartConfig)
        let data = try JSONEncoder().encode(cs)
        var headers = HTTPFields()
        headers[.contentType] = "application/fhir+json"
        return Response(
            status: .ok,
            headers: headers,
            body: ResponseBody(byteBuffer: ByteBuffer(bytes: data))
        )
    }
}

// ── Builder ───────────────────────────────────────────────────────────────────

private func buildCapabilityStatement(smartConfig: SmartConfiguration?) -> CapabilityStatement {
    CapabilityStatement(
        date: FHIRPrimitive(DateTime(stringLiteral: "2026-06-11")),
        fhirVersion: FHIRPrimitive(FHIRString("4.0.1")),
        format: [FHIRPrimitive(FHIRString("application/fhir+json"))],
        instantiates: [FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/CapabilityStatement/base"))],
        kind: FHIRPrimitive(.instance),
        name: FHIRPrimitive(FHIRString("SimingCapabilityStatement")),
        patchFormat: [FHIRPrimitive(FHIRString("application/json-patch+json"))],
        publisher: FHIRPrimitive(FHIRString("Siming 司命")),
        rest: [serverRest(smartConfig: smartConfig)],
        software: CapabilityStatementSoftware(
            name: FHIRPrimitive(FHIRString("Siming 司命")),
            version: FHIRPrimitive(FHIRString("0.84.0"))
        ),
        status: FHIRPrimitive(.active),
        title: FHIRPrimitive(FHIRString("Siming FHIR R4 Server")),
        version: FHIRPrimitive(FHIRString("0.84.0"))
    )
}

private func serverRest(smartConfig: SmartConfiguration?) -> CapabilityStatementRest {
    var rest = CapabilityStatementRest(
        mode: FHIRPrimitive(.server),
        resource: [patientResource(), observationResource(), encounterResource(), conditionResource(),
                   medicationResource(), medicationRequestResource(), allergyIntoleranceResource(),
                   procedureResource(), diagnosticReportResource(), immunizationResource(),
                   practitionerResource(), organizationResource(), locationResource(),
                   relatedPersonResource(), serviceRequestResource(), specimenResource(),
                   documentReferenceResource(), carePlanResource(), goalResource(),
                   medicationStatementResource(), familyMemberHistoryResource(),
                   appointmentResource(), medicationAdministrationResource()]
    )
    rest.compartment = [
        FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/CompartmentDefinition/patient"))
    ]
    if smartConfig != nil {
        let security = CapabilityStatementRestSecurity(
            cors: FHIRPrimitive(FHIRBool(true)),
            description_fhir: FHIRPrimitive(FHIRString("SMART App Launch Framework")),
            service: [
                CodeableConcept(coding: [
                    Coding(
                        code: FHIRPrimitive(FHIRString("SMART-on-FHIR")),
                        display: FHIRPrimitive(FHIRString("SMART-on-FHIR")),
                        system: FHIRPrimitive(FHIRURI(stringLiteral: "http://terminology.hl7.org/CodeSystem/restful-security-service"))
                    )
                ])
            ]
        )
        rest.security = security
    }
    rest.interaction = [
        CapabilityStatementRestInteraction(code: FHIRPrimitive(.transaction)),
        CapabilityStatementRestInteraction(code: FHIRPrimitive(.historySystem)),
    ]
    rest.documentation = FHIRPrimitive(FHIRString(
        "Compartments: GET /Patient/:id/{Observation,Encounter,Condition,MedicationRequest,AllergyIntolerance,Procedure,DiagnosticReport,Immunization} " +
        "and POST /Patient/:id/{...}/_search."
    ))
    rest.searchParam = [
        CapabilityStatementRestResourceSearchParam(
            documentation: FHIRPrimitive(FHIRString("Filter by top-level element names. Mandatory elements (id, meta, resourceType) always returned. SUBSETTED tag added to meta.")),
            name: FHIRPrimitive(FHIRString("_elements")),
            type: FHIRPrimitive(.string)
        ),
        CapabilityStatementRestResourceSearchParam(
            documentation: FHIRPrimitive(FHIRString("Controls response content. Values: true (Σ-marked summary fields), text (text + mandatory), data (all except text), count (total only, no resource payloads), false (all fields, default). SUBSETTED tag added to meta when subsetting.")),
            name: FHIRPrimitive(FHIRString("_summary")),
            type: FHIRPrimitive(.token)
        ),
        CapabilityStatementRestResourceSearchParam(
            definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/Resource-tag")),
            documentation: FHIRPrimitive(FHIRString("Filter by meta.tag token. Supports :not modifier and comma-separated OR list.")),
            name: FHIRPrimitive(FHIRString("_tag")),
            type: FHIRPrimitive(.token)
        ),
        CapabilityStatementRestResourceSearchParam(
            definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/Resource-security")),
            documentation: FHIRPrimitive(FHIRString("Filter by meta.security token. Supports :not modifier and comma-separated OR list.")),
            name: FHIRPrimitive(FHIRString("_security")),
            type: FHIRPrimitive(.token)
        ),
        CapabilityStatementRestResourceSearchParam(
            definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/Resource-profile")),
            documentation: FHIRPrimitive(FHIRString("Filter by meta.profile URI. Exact match against canonical URLs.")),
            name: FHIRPrimitive(FHIRString("_profile")),
            type: FHIRPrimitive(.uri)
        ),
        CapabilityStatementRestResourceSearchParam(
            definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/Resource-source")),
            documentation: FHIRPrimitive(FHIRString("Filter by meta.source URI. Exact match against the source URI stored with the resource.")),
            name: FHIRPrimitive(FHIRString("_source")),
            type: FHIRPrimitive(.uri)
        ),
    ]
    return rest
}

private let baselineInteractions: [CapabilityStatementRestResourceInteraction] = [
    CapabilityStatementRestResourceInteraction(code: FHIRPrimitive(.read)),
    CapabilityStatementRestResourceInteraction(code: FHIRPrimitive(.vread)),
    CapabilityStatementRestResourceInteraction(code: FHIRPrimitive(.create)),
    CapabilityStatementRestResourceInteraction(code: FHIRPrimitive(.update)),
    CapabilityStatementRestResourceInteraction(code: FHIRPrimitive(.patch)),
    CapabilityStatementRestResourceInteraction(code: FHIRPrimitive(.delete)),
    CapabilityStatementRestResourceInteraction(code: FHIRPrimitive(.historyInstance)),
    CapabilityStatementRestResourceInteraction(code: FHIRPrimitive(.historyType)),
    CapabilityStatementRestResourceInteraction(code: FHIRPrimitive(.searchType)),
]

private func patientResource() -> CapabilityStatementRestResource {
    var r = CapabilityStatementRestResource(
        documentation: FHIRPrimitive(FHIRString(
            "History-preserving Patient resource. " +
            "Supports read, vread, create (conditional via If-None-Exist), update (conditional via PUT /Patient?<search>), delete, history-instance, and search (GET and POST /_search). " +
            "Search: _sort=±_lastUpdated/±name/±family/±birthdate/±_id; _count (0–100; 0=count-only); _total (accurate|estimate|none); _elements (field filter); _summary (true|text|data|count|false); cursor pagination via _cursor. " +
            "String modifiers: :contains, :exact, :text (case-insensitive substring); :not, :missing on all params. " +
            "Prefer: return=minimal on write → 201/200 with no body. " +
            "Prefer: handling=strict on search → 400 on unknown params; handling=lenient (default) ignores them. " +
            "Compartments: GET /Patient/:id/{Observation,Encounter,Condition,MedicationRequest,AllergyIntolerance} (POST /_search for Observation/Encounter/Condition)."
        )),
        interaction: baselineInteractions,
        readHistory: FHIRPrimitive(FHIRBool(true)),
        searchParam: [
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/Patient-name")),
                documentation: FHIRPrimitive(FHIRString("Starts-with match across all name fields (family, given, text). Modifiers: :contains, :exact, :text.")),
                name: FHIRPrimitive(FHIRString("name")),
                type: FHIRPrimitive(.string)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/Patient-family")),
                documentation: FHIRPrimitive(FHIRString("Starts-with on family name. Modifiers: :contains, :exact, :text.")),
                name: FHIRPrimitive(FHIRString("family")),
                type: FHIRPrimitive(.string)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/Patient-given")),
                documentation: FHIRPrimitive(FHIRString("Starts-with on given name(s). Modifiers: :contains, :exact.")),
                name: FHIRPrimitive(FHIRString("given")),
                type: FHIRPrimitive(.string)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/Patient-gender")),
                documentation: FHIRPrimitive(FHIRString("Token OR: male|female|other|unknown. Comma-separated for OR (e.g. gender=male,female).")),
                name: FHIRPrimitive(FHIRString("gender")),
                type: FHIRPrimitive(.token)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/Patient-active")),
                documentation: FHIRPrimitive(FHIRString("Boolean: active=true or active=false.")),
                name: FHIRPrimitive(FHIRString("active")),
                type: FHIRPrimitive(.token)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/Patient-address")),
                documentation: FHIRPrimitive(FHIRString("Starts-with across all address sub-fields (line, city, state, postalCode, country, text). Modifiers: :contains, :exact.")),
                name: FHIRPrimitive(FHIRString("address")),
                type: FHIRPrimitive(.string)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/Patient-address-city")),
                documentation: FHIRPrimitive(FHIRString("City field of address. Modifiers: :contains, :exact.")),
                name: FHIRPrimitive(FHIRString("address-city")),
                type: FHIRPrimitive(.string)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/Patient-address-state")),
                documentation: FHIRPrimitive(FHIRString("State/province field of address. Modifiers: :contains, :exact.")),
                name: FHIRPrimitive(FHIRString("address-state")),
                type: FHIRPrimitive(.string)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/Patient-address-postalcode")),
                documentation: FHIRPrimitive(FHIRString("Postal code field of address. Modifiers: :contains, :exact.")),
                name: FHIRPrimitive(FHIRString("address-postalcode")),
                type: FHIRPrimitive(.string)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/Patient-address-country")),
                documentation: FHIRPrimitive(FHIRString("Country field of address. Modifiers: :contains, :exact.")),
                name: FHIRPrimitive(FHIRString("address-country")),
                type: FHIRPrimitive(.string)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/Patient-phone")),
                documentation: FHIRPrimitive(FHIRString("Exact match on telecom.value where system=phone.")),
                name: FHIRPrimitive(FHIRString("phone")),
                type: FHIRPrimitive(.token)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/Patient-email")),
                documentation: FHIRPrimitive(FHIRString("Exact match on telecom.value where system=email.")),
                name: FHIRPrimitive(FHIRString("email")),
                type: FHIRPrimitive(.token)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/Patient-identifier")),
                documentation: FHIRPrimitive(FHIRString("Token search. Formats: code, system|code, |code (null system). Comma-separated for OR.")),
                name: FHIRPrimitive(FHIRString("identifier")),
                type: FHIRPrimitive(.token)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/Patient-birthdate")),
                documentation: FHIRPrimitive(FHIRString("Date search with prefixes: eq (default), lt, gt, le, ge, sa, eb. Partial dates supported.")),
                name: FHIRPrimitive(FHIRString("birthdate")),
                type: FHIRPrimitive(.date)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/Patient-deceased")),
                documentation: FHIRPrimitive(FHIRString("Boolean or code token: deceased=true, deceased=false, or deceased=[date code].")),
                name: FHIRPrimitive(FHIRString("deceased")),
                type: FHIRPrimitive(.token)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/Patient-death-date")),
                documentation: FHIRPrimitive(FHIRString("Date of death. Prefixes: eq, lt, gt, le, ge, sa, eb.")),
                name: FHIRPrimitive(FHIRString("death-date")),
                type: FHIRPrimitive(.date)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/Patient-general-practitioner")),
                documentation: FHIRPrimitive(FHIRString("Patient.generalPractitioner[]. Reference: ResourceType/id or bare id.")),
                name: FHIRPrimitive(FHIRString("general-practitioner")),
                type: FHIRPrimitive(.reference)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/Patient-organization")),
                documentation: FHIRPrimitive(FHIRString("Patient.managingOrganization. Reference: Organization/id or bare id.")),
                name: FHIRPrimitive(FHIRString("organization")),
                type: FHIRPrimitive(.reference)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/Patient-link")),
                documentation: FHIRPrimitive(FHIRString("Patient.link[].other reference.")),
                name: FHIRPrimitive(FHIRString("link")),
                type: FHIRPrimitive(.reference)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/Patient-language")),
                documentation: FHIRPrimitive(FHIRString("Patient.communication[].language. Token: system|code, code. Modifier: :not.")),
                name: FHIRPrimitive(FHIRString("language")),
                type: FHIRPrimitive(.token)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/Resource-id")),
                documentation: FHIRPrimitive(FHIRString("Filter by resource id. Comma-separated for OR.")),
                name: FHIRPrimitive(FHIRString("_id")),
                type: FHIRPrimitive(.token)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/Resource-lastUpdated")),
                documentation: FHIRPrimitive(FHIRString("Filter by last modification time. Prefixes: eq, lt, gt, le, ge.")),
                name: FHIRPrimitive(FHIRString("_lastUpdated")),
                type: FHIRPrimitive(.date)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/Resource-query-total")),
                documentation: FHIRPrimitive(FHIRString("Controls whether Bundle.total is returned. Values: accurate (default), estimate, none.")),
                name: FHIRPrimitive(FHIRString("_total")),
                type: FHIRPrimitive(.token)
            ),
        ],
        type: FHIRPrimitive(.patient),
        versioning: FHIRPrimitive(.versioned)
    )
    r.conditionalCreate = FHIRPrimitive(FHIRBool(true))
    r.conditionalUpdate = FHIRPrimitive(FHIRBool(true))
    r.conditionalDelete = FHIRPrimitive(.single)
    r.conditionalRead = FHIRPrimitive(.fullSupport)
    r.updateCreate = FHIRPrimitive(FHIRBool(true))
    r.searchRevInclude = [
        "Observation:subject", "Observation:patient",
        "Encounter:subject", "Encounter:patient",
        "Condition:subject", "Condition:patient",
        "MedicationRequest:subject", "MedicationRequest:patient",
        "AllergyIntolerance:patient",
    ].map { FHIRPrimitive(FHIRString($0)) }
    return r
}

private func observationResource() -> CapabilityStatementRestResource {
    var r = CapabilityStatementRestResource(
        documentation: FHIRPrimitive(FHIRString(
            "Observation resource. " +
            "Supports read, vread, create (conditional via If-None-Exist), update (conditional via PUT /Observation?<search>), delete, history-instance, and search (GET and POST /_search). " +
            "Search: subject, code, status, category, date, identifier, encounter, performer, component-code, value-quantity; _sort=±_lastUpdated/±date/±_id; _total (accurate|estimate|none); _elements (field filter); _summary (true|text|data|count|false). " +
            ":not and :missing modifiers supported. " +
            "Prefer: return=minimal on write → 201/200 with no body. " +
            "Prefer: handling=strict on search → 400 on unknown params; handling=lenient (default) ignores them."
        )),
        interaction: baselineInteractions,
        readHistory: FHIRPrimitive(FHIRBool(true)),
        searchParam: [
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/Observation-subject")),
                documentation: FHIRPrimitive(FHIRString("Reference to subject. Formats: Patient/id or bare id.")),
                name: FHIRPrimitive(FHIRString("subject")),
                type: FHIRPrimitive(.reference)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/Observation-patient")),
                documentation: FHIRPrimitive(FHIRString("Alias for subject constrained to Patient. Formats: Patient/id or bare id.")),
                name: FHIRPrimitive(FHIRString("patient")),
                type: FHIRPrimitive(.reference)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/Observation-code")),
                documentation: FHIRPrimitive(FHIRString("Token OR on Observation.code. Formats: code, system|code, system|. Modifier: :not.")),
                name: FHIRPrimitive(FHIRString("code")),
                type: FHIRPrimitive(.token)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/Observation-status")),
                documentation: FHIRPrimitive(FHIRString("Token OR on Observation.status. Comma-separated for OR. Modifier: :not.")),
                name: FHIRPrimitive(FHIRString("status")),
                type: FHIRPrimitive(.token)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/Observation-category")),
                documentation: FHIRPrimitive(FHIRString("Token OR on Observation.category. Formats: code, system|code, system|. Modifier: :not.")),
                name: FHIRPrimitive(FHIRString("category")),
                type: FHIRPrimitive(.token)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/Observation-identifier")),
                documentation: FHIRPrimitive(FHIRString("Token OR on Observation.identifier. Formats: code, system|code, system|.")),
                name: FHIRPrimitive(FHIRString("identifier")),
                type: FHIRPrimitive(.token)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/Observation-encounter")),
                documentation: FHIRPrimitive(FHIRString("Reference to Encounter. Formats: Encounter/id or bare id.")),
                name: FHIRPrimitive(FHIRString("encounter")),
                type: FHIRPrimitive(.reference)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/Observation-performer")),
                documentation: FHIRPrimitive(FHIRString("Reference to performer. Formats: ResourceType/id or bare id.")),
                name: FHIRPrimitive(FHIRString("performer")),
                type: FHIRPrimitive(.reference)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/Observation-component-code")),
                documentation: FHIRPrimitive(FHIRString("Token OR on Observation.component.code. Formats: code, system|code, system|.")),
                name: FHIRPrimitive(FHIRString("component-code")),
                type: FHIRPrimitive(.token)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/Observation-date")),
                documentation: FHIRPrimitive(FHIRString("Date search with prefixes: eq (default), lt, gt, le, ge, sa, eb. Partial dates supported.")),
                name: FHIRPrimitive(FHIRString("date")),
                type: FHIRPrimitive(.date)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/Observation-value-quantity")),
                documentation: FHIRPrimitive(FHIRString("Quantity search on Observation.valueQuantity. Format: [prefix][value][|system][|code]. Prefixes: eq (default), lt, gt, le, ge, ne, ap (±10%). Comma-separated for OR.")),
                name: FHIRPrimitive(FHIRString("value-quantity")),
                type: FHIRPrimitive(.quantity)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/Observation-based-on")),
                documentation: FHIRPrimitive(FHIRString("Observation.basedOn[]. Reference: ResourceType/id or bare id.")),
                name: FHIRPrimitive(FHIRString("based-on")),
                type: FHIRPrimitive(.reference)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/Observation-derived-from")),
                documentation: FHIRPrimitive(FHIRString("Observation.derivedFrom[]. Reference: ResourceType/id or bare id.")),
                name: FHIRPrimitive(FHIRString("derived-from")),
                type: FHIRPrimitive(.reference)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/Observation-device")),
                documentation: FHIRPrimitive(FHIRString("Observation.device. Reference: Device/id or bare id.")),
                name: FHIRPrimitive(FHIRString("device")),
                type: FHIRPrimitive(.reference)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/Observation-focus")),
                documentation: FHIRPrimitive(FHIRString("Observation.focus[]. Reference: ResourceType/id or bare id.")),
                name: FHIRPrimitive(FHIRString("focus")),
                type: FHIRPrimitive(.reference)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/Observation-has-member")),
                documentation: FHIRPrimitive(FHIRString("Observation.hasMember[]. Reference: ResourceType/id or bare id.")),
                name: FHIRPrimitive(FHIRString("has-member")),
                type: FHIRPrimitive(.reference)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/Observation-part-of")),
                documentation: FHIRPrimitive(FHIRString("Observation.partOf[]. Reference: ResourceType/id or bare id.")),
                name: FHIRPrimitive(FHIRString("part-of")),
                type: FHIRPrimitive(.reference)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/Observation-specimen")),
                documentation: FHIRPrimitive(FHIRString("Observation.specimen. Reference: Specimen/id or bare id.")),
                name: FHIRPrimitive(FHIRString("specimen")),
                type: FHIRPrimitive(.reference)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/Observation-method")),
                documentation: FHIRPrimitive(FHIRString("Observation.method. Token: system|code. Modifier: :not.")),
                name: FHIRPrimitive(FHIRString("method")),
                type: FHIRPrimitive(.token)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/Observation-value-concept")),
                documentation: FHIRPrimitive(FHIRString("Observation.valueCodeableConcept. Token: system|code. Modifier: :not.")),
                name: FHIRPrimitive(FHIRString("value-concept")),
                type: FHIRPrimitive(.token)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/Observation-value-date")),
                documentation: FHIRPrimitive(FHIRString("Observation.valueDateTime. Prefixes: eq, lt, gt, le, ge.")),
                name: FHIRPrimitive(FHIRString("value-date")),
                type: FHIRPrimitive(.date)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/Observation-value-string")),
                documentation: FHIRPrimitive(FHIRString("Observation.valueString. Prefix/contains/exact match.")),
                name: FHIRPrimitive(FHIRString("value-string")),
                type: FHIRPrimitive(.string)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/Observation-combo-code")),
                documentation: FHIRPrimitive(FHIRString("Observation.code AND Observation.component[].code (OR). Modifier: :not.")),
                name: FHIRPrimitive(FHIRString("combo-code")),
                type: FHIRPrimitive(.token)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/Observation-combo-value-concept")),
                documentation: FHIRPrimitive(FHIRString("Observation.valueCodeableConcept AND component[].valueCodeableConcept (OR). Modifier: :not.")),
                name: FHIRPrimitive(FHIRString("combo-value-concept")),
                type: FHIRPrimitive(.token)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/Observation-combo-value-quantity")),
                documentation: FHIRPrimitive(FHIRString("Observation.valueQuantity and component[].valueQuantity. Prefixes: eq, lt, gt, le, ge, ne, ap. Modifier: :not.")),
                name: FHIRPrimitive(FHIRString("combo-value-quantity")),
                type: FHIRPrimitive(.quantity)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/Observation-component-value-quantity")),
                documentation: FHIRPrimitive(FHIRString("Observation.component[].valueQuantity. Prefixes: eq, lt, gt, le, ge, ne, ap.")),
                name: FHIRPrimitive(FHIRString("component-value-quantity")),
                type: FHIRPrimitive(.quantity)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/Observation-component-value-concept")),
                documentation: FHIRPrimitive(FHIRString("Observation.component[].valueCodeableConcept. Token: system|code. Modifier: :not.")),
                name: FHIRPrimitive(FHIRString("component-value-concept")),
                type: FHIRPrimitive(.token)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/Observation-component-data-absent-reason")),
                documentation: FHIRPrimitive(FHIRString("Observation.component[].dataAbsentReason. Token: system|code. Modifier: :not.")),
                name: FHIRPrimitive(FHIRString("component-data-absent-reason")),
                type: FHIRPrimitive(.token)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/Observation-data-absent-reason")),
                documentation: FHIRPrimitive(FHIRString("Observation.dataAbsentReason. Token: system|code. Modifier: :not.")),
                name: FHIRPrimitive(FHIRString("data-absent-reason")),
                type: FHIRPrimitive(.token)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/Observation-combo-data-absent-reason")),
                documentation: FHIRPrimitive(FHIRString("Observation.dataAbsentReason AND component[].dataAbsentReason (OR). Modifier: :not.")),
                name: FHIRPrimitive(FHIRString("combo-data-absent-reason")),
                type: FHIRPrimitive(.token)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/Observation-code-value-quantity")),
                documentation: FHIRPrimitive(FHIRString("Composite: code$value-quantity. Format: code-value-quantity=system|code$[prefix]value[|system][|code].")),
                name: FHIRPrimitive(FHIRString("code-value-quantity")),
                type: FHIRPrimitive(.composite)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/Observation-code-value-string")),
                documentation: FHIRPrimitive(FHIRString("Composite: code$value-string. Format: code-value-string=system|code$string-value.")),
                name: FHIRPrimitive(FHIRString("code-value-string")),
                type: FHIRPrimitive(.composite)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/Observation-code-value-concept")),
                documentation: FHIRPrimitive(FHIRString("Composite: code$value-concept. Format: code-value-concept=system|code$system|code.")),
                name: FHIRPrimitive(FHIRString("code-value-concept")),
                type: FHIRPrimitive(.composite)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/Observation-code-value-date")),
                documentation: FHIRPrimitive(FHIRString("Composite: code$value-date. Format: code-value-date=system|code$date.")),
                name: FHIRPrimitive(FHIRString("code-value-date")),
                type: FHIRPrimitive(.composite)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/Observation-component-code-value-quantity")),
                documentation: FHIRPrimitive(FHIRString("Composite on component: component-code$component-value-quantity. Uses idx_composite.")),
                name: FHIRPrimitive(FHIRString("component-code-value-quantity")),
                type: FHIRPrimitive(.composite)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/Observation-component-code-value-concept")),
                documentation: FHIRPrimitive(FHIRString("Composite on component: component-code$component-value-concept. Uses idx_composite.")),
                name: FHIRPrimitive(FHIRString("component-code-value-concept")),
                type: FHIRPrimitive(.composite)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/Observation-combo-code-value-quantity")),
                documentation: FHIRPrimitive(FHIRString("Composite combining code and value-quantity or component-code and component-value-quantity. Uses idx_composite.")),
                name: FHIRPrimitive(FHIRString("combo-code-value-quantity")),
                type: FHIRPrimitive(.composite)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/Observation-combo-code-value-concept")),
                documentation: FHIRPrimitive(FHIRString("Composite combining code and value-concept or component variants. Uses idx_composite.")),
                name: FHIRPrimitive(FHIRString("combo-code-value-concept")),
                type: FHIRPrimitive(.composite)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/Resource-id")),
                documentation: FHIRPrimitive(FHIRString("Filter by resource id. Comma-separated for OR.")),
                name: FHIRPrimitive(FHIRString("_id")),
                type: FHIRPrimitive(.token)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/Resource-lastUpdated")),
                documentation: FHIRPrimitive(FHIRString("Filter by last modification time. Prefixes: eq, lt, gt, le, ge.")),
                name: FHIRPrimitive(FHIRString("_lastUpdated")),
                type: FHIRPrimitive(.date)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/Resource-query-total")),
                documentation: FHIRPrimitive(FHIRString("Controls whether Bundle.total is returned. Values: accurate (default), estimate, none.")),
                name: FHIRPrimitive(FHIRString("_total")),
                type: FHIRPrimitive(.token)
            ),
        ],
        type: FHIRPrimitive(.observation),
        versioning: FHIRPrimitive(.versioned)
    )
    r.conditionalCreate = FHIRPrimitive(FHIRBool(true))
    r.conditionalUpdate = FHIRPrimitive(FHIRBool(true))
    r.conditionalDelete = FHIRPrimitive(.single)
    r.conditionalRead = FHIRPrimitive(.fullSupport)
    r.updateCreate = FHIRPrimitive(FHIRBool(true))
    r.searchInclude = [
        "Observation:subject", "Observation:patient", "Observation:encounter",
    ].map { FHIRPrimitive(FHIRString($0)) }
    return r
}

private func encounterResource() -> CapabilityStatementRestResource {
    var r = CapabilityStatementRestResource(
        documentation: FHIRPrimitive(FHIRString(
            "Encounter resource. " +
            "Supports read, vread, create (conditional via If-None-Exist), update (conditional via PUT /Encounter?<search>), delete, history-instance, and search (GET and POST /_search). " +
            "Search: subject, patient, status, class, type, date, identifier; _sort=±_lastUpdated/±date/±_id; _total (accurate|estimate|none); _elements (field filter); _summary (true|text|data|count|false). " +
            ":not and :missing modifiers supported. " +
            "Compartment: GET /Patient/:id/Encounter and POST /Patient/:id/Encounter/_search."
        )),
        interaction: baselineInteractions,
        readHistory: FHIRPrimitive(FHIRBool(true)),
        searchParam: [
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/Encounter-subject")),
                documentation: FHIRPrimitive(FHIRString("Reference to subject. Formats: Patient/id or bare id.")),
                name: FHIRPrimitive(FHIRString("subject")),
                type: FHIRPrimitive(.reference)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/Encounter-patient")),
                documentation: FHIRPrimitive(FHIRString("Alias for subject constrained to Patient.")),
                name: FHIRPrimitive(FHIRString("patient")),
                type: FHIRPrimitive(.reference)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/Encounter-status")),
                documentation: FHIRPrimitive(FHIRString("Token OR on Encounter.status. Comma-separated for OR. Modifier: :not.")),
                name: FHIRPrimitive(FHIRString("status")),
                type: FHIRPrimitive(.token)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/Encounter-class")),
                documentation: FHIRPrimitive(FHIRString("Token OR on Encounter.class (encounter class coding). Formats: code, system|code. Modifier: :not.")),
                name: FHIRPrimitive(FHIRString("class")),
                type: FHIRPrimitive(.token)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/Encounter-type")),
                documentation: FHIRPrimitive(FHIRString("Token OR on Encounter.type CodeableConcept. Formats: code, system|code, system|. Modifier: :not.")),
                name: FHIRPrimitive(FHIRString("type")),
                type: FHIRPrimitive(.token)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/Encounter-date")),
                documentation: FHIRPrimitive(FHIRString("Date search on Encounter.period. Prefixes: eq (overlap), lt/le/gt/ge (bound), sa (starts-after), eb (ends-before). Multiple values AND-combined.")),
                name: FHIRPrimitive(FHIRString("date")),
                type: FHIRPrimitive(.date)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/Encounter-identifier")),
                documentation: FHIRPrimitive(FHIRString("Token OR on Encounter.identifier. Formats: code, system|code, system|.")),
                name: FHIRPrimitive(FHIRString("identifier")),
                type: FHIRPrimitive(.token)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/Encounter-account")),
                documentation: FHIRPrimitive(FHIRString("Encounter.account[]. Reference: Account/id or bare id.")),
                name: FHIRPrimitive(FHIRString("account")),
                type: FHIRPrimitive(.reference)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/Encounter-appointment")),
                documentation: FHIRPrimitive(FHIRString("Encounter.appointment[]. Reference: Appointment/id or bare id.")),
                name: FHIRPrimitive(FHIRString("appointment")),
                type: FHIRPrimitive(.reference)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/Encounter-based-on")),
                documentation: FHIRPrimitive(FHIRString("Encounter.basedOn[]. Reference: ServiceRequest/id or bare id.")),
                name: FHIRPrimitive(FHIRString("based-on")),
                type: FHIRPrimitive(.reference)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/Encounter-diagnosis")),
                documentation: FHIRPrimitive(FHIRString("Encounter.diagnosis[].condition. Reference: ResourceType/id or bare id.")),
                name: FHIRPrimitive(FHIRString("diagnosis")),
                type: FHIRPrimitive(.reference)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/Encounter-episode-of-care")),
                documentation: FHIRPrimitive(FHIRString("Encounter.episodeOfCare[]. Reference: EpisodeOfCare/id or bare id.")),
                name: FHIRPrimitive(FHIRString("episode-of-care")),
                type: FHIRPrimitive(.reference)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/Encounter-length")),
                documentation: FHIRPrimitive(FHIRString("Encounter.length (Duration). Prefixes: eq (sig-figs range), lt, gt, le, ge, ne, ap (±10%).")),
                name: FHIRPrimitive(FHIRString("length")),
                type: FHIRPrimitive(.quantity)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/Encounter-location")),
                documentation: FHIRPrimitive(FHIRString("Encounter.location[].location. Reference: Location/id or bare id.")),
                name: FHIRPrimitive(FHIRString("location")),
                type: FHIRPrimitive(.reference)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/Encounter-location-period")),
                documentation: FHIRPrimitive(FHIRString("Encounter.location[].period. Date range on location period.")),
                name: FHIRPrimitive(FHIRString("location-period")),
                type: FHIRPrimitive(.date)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/Encounter-part-of")),
                documentation: FHIRPrimitive(FHIRString("Encounter.partOf. Reference: Encounter/id or bare id.")),
                name: FHIRPrimitive(FHIRString("part-of")),
                type: FHIRPrimitive(.reference)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/Encounter-participant")),
                documentation: FHIRPrimitive(FHIRString("Encounter.participant[].individual. Reference: ResourceType/id or bare id.")),
                name: FHIRPrimitive(FHIRString("participant")),
                type: FHIRPrimitive(.reference)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/Encounter-participant-type")),
                documentation: FHIRPrimitive(FHIRString("Encounter.participant[].type. Token: system|code. Modifier: :not.")),
                name: FHIRPrimitive(FHIRString("participant-type")),
                type: FHIRPrimitive(.token)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/Encounter-practitioner")),
                documentation: FHIRPrimitive(FHIRString("Encounter.participant[].individual where type=Practitioner. Reference: Practitioner/id or bare id.")),
                name: FHIRPrimitive(FHIRString("practitioner")),
                type: FHIRPrimitive(.reference)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/Encounter-reason-code")),
                documentation: FHIRPrimitive(FHIRString("Encounter.reasonCode[].coding. Token: system|code. Modifier: :not.")),
                name: FHIRPrimitive(FHIRString("reason-code")),
                type: FHIRPrimitive(.token)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/Encounter-reason-reference")),
                documentation: FHIRPrimitive(FHIRString("Encounter.reasonReference[]. Reference: ResourceType/id or bare id.")),
                name: FHIRPrimitive(FHIRString("reason-reference")),
                type: FHIRPrimitive(.reference)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/Encounter-service-provider")),
                documentation: FHIRPrimitive(FHIRString("Encounter.serviceProvider. Reference: Organization/id or bare id.")),
                name: FHIRPrimitive(FHIRString("service-provider")),
                type: FHIRPrimitive(.reference)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/Encounter-special-arrangement")),
                documentation: FHIRPrimitive(FHIRString("Encounter.hospitalization.specialArrangement. Token: system|code. Modifier: :not.")),
                name: FHIRPrimitive(FHIRString("special-arrangement")),
                type: FHIRPrimitive(.token)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/Resource-id")),
                documentation: FHIRPrimitive(FHIRString("Filter by resource id. Comma-separated for OR.")),
                name: FHIRPrimitive(FHIRString("_id")),
                type: FHIRPrimitive(.token)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/Resource-lastUpdated")),
                documentation: FHIRPrimitive(FHIRString("Filter by last modification time. Prefixes: eq, lt, gt, le, ge.")),
                name: FHIRPrimitive(FHIRString("_lastUpdated")),
                type: FHIRPrimitive(.date)
            ),
        ],
        type: FHIRPrimitive(.encounter),
        versioning: FHIRPrimitive(.versioned)
    )
    r.conditionalCreate = FHIRPrimitive(FHIRBool(true))
    r.conditionalUpdate = FHIRPrimitive(FHIRBool(true))
    r.conditionalDelete = FHIRPrimitive(.single)
    r.conditionalRead = FHIRPrimitive(.fullSupport)
    r.updateCreate = FHIRPrimitive(FHIRBool(true))
    r.searchInclude = [
        "Encounter:subject", "Encounter:patient",
    ].map { FHIRPrimitive(FHIRString($0)) }
    r.searchRevInclude = [
        "Observation:encounter", "Condition:encounter", "MedicationRequest:encounter",
    ].map { FHIRPrimitive(FHIRString($0)) }
    return r
}

private func conditionResource() -> CapabilityStatementRestResource {
    var r = CapabilityStatementRestResource(
        documentation: FHIRPrimitive(FHIRString(
            "Condition resource. " +
            "Supports read, vread, create (conditional via If-None-Exist), update (conditional via PUT /Condition?<search>), delete, history-instance, and search (GET and POST /_search). " +
            "Search: subject, patient, encounter, clinical-status, verification-status, category, code, identifier, onset-date, abatement-date, recorded-date; _sort=±_lastUpdated/±date(onset)/±_id; _total (accurate|estimate|none); _elements (field filter); _summary (true|text|data|count|false). " +
            ":not and :missing modifiers supported. " +
            "Compartment: GET /Patient/:id/Condition and POST /Patient/:id/Condition/_search."
        )),
        interaction: baselineInteractions,
        readHistory: FHIRPrimitive(FHIRBool(true)),
        searchParam: [
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/Condition-subject")),
                documentation: FHIRPrimitive(FHIRString("Reference to subject. Formats: Patient/id or bare id.")),
                name: FHIRPrimitive(FHIRString("subject")),
                type: FHIRPrimitive(.reference)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/Condition-patient")),
                documentation: FHIRPrimitive(FHIRString("Alias for subject constrained to Patient.")),
                name: FHIRPrimitive(FHIRString("patient")),
                type: FHIRPrimitive(.reference)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/Condition-encounter")),
                documentation: FHIRPrimitive(FHIRString("Reference to Encounter in which condition was first asserted.")),
                name: FHIRPrimitive(FHIRString("encounter")),
                type: FHIRPrimitive(.reference)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/Condition-clinical-status")),
                documentation: FHIRPrimitive(FHIRString("Token OR on Condition.clinicalStatus. Modifier: :not.")),
                name: FHIRPrimitive(FHIRString("clinical-status")),
                type: FHIRPrimitive(.token)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/Condition-verification-status")),
                documentation: FHIRPrimitive(FHIRString("Token OR on Condition.verificationStatus. Modifier: :not.")),
                name: FHIRPrimitive(FHIRString("verification-status")),
                type: FHIRPrimitive(.token)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/Condition-category")),
                documentation: FHIRPrimitive(FHIRString("Token OR on Condition.category CodeableConcept. Modifier: :not.")),
                name: FHIRPrimitive(FHIRString("category")),
                type: FHIRPrimitive(.token)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/Condition-code")),
                documentation: FHIRPrimitive(FHIRString("Token OR on Condition.code CodeableConcept. Modifier: :not.")),
                name: FHIRPrimitive(FHIRString("code")),
                type: FHIRPrimitive(.token)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/Condition-identifier")),
                documentation: FHIRPrimitive(FHIRString("Token OR on Condition.identifier.")),
                name: FHIRPrimitive(FHIRString("identifier")),
                type: FHIRPrimitive(.token)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/Condition-onset-date")),
                documentation: FHIRPrimitive(FHIRString("Date search on Condition.onset[x] (dateTime or Period). Prefixes: eq, lt, gt, le, ge, sa, eb.")),
                name: FHIRPrimitive(FHIRString("onset-date")),
                type: FHIRPrimitive(.date)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/Condition-abatement-date")),
                documentation: FHIRPrimitive(FHIRString("Date search on Condition.abatement[x] (dateTime or Period). Prefixes: eq, lt, gt, le, ge, sa, eb.")),
                name: FHIRPrimitive(FHIRString("abatement-date")),
                type: FHIRPrimitive(.date)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/Condition-recorded-date")),
                documentation: FHIRPrimitive(FHIRString("Date search on Condition.recordedDate. Prefixes: eq, lt, gt, le, ge.")),
                name: FHIRPrimitive(FHIRString("recorded-date")),
                type: FHIRPrimitive(.date)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/Condition-asserter")),
                documentation: FHIRPrimitive(FHIRString("Condition.asserter. Reference: ResourceType/id or bare id.")),
                name: FHIRPrimitive(FHIRString("asserter")),
                type: FHIRPrimitive(.reference)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/Condition-evidence-detail")),
                documentation: FHIRPrimitive(FHIRString("Condition.evidence[].detail[]. Reference: ResourceType/id or bare id.")),
                name: FHIRPrimitive(FHIRString("evidence-detail")),
                type: FHIRPrimitive(.reference)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/Condition-body-site")),
                documentation: FHIRPrimitive(FHIRString("Condition.bodySite[].coding. Token: system|code. Modifier: :not.")),
                name: FHIRPrimitive(FHIRString("body-site")),
                type: FHIRPrimitive(.token)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/Condition-evidence")),
                documentation: FHIRPrimitive(FHIRString("Condition.evidence[].code[].coding. Token: system|code. Modifier: :not.")),
                name: FHIRPrimitive(FHIRString("evidence")),
                type: FHIRPrimitive(.token)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/Condition-severity")),
                documentation: FHIRPrimitive(FHIRString("Condition.severity.coding. Token: system|code. Modifier: :not.")),
                name: FHIRPrimitive(FHIRString("severity")),
                type: FHIRPrimitive(.token)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/Condition-stage")),
                documentation: FHIRPrimitive(FHIRString("Condition.stage[].summary.coding. Token: system|code. Modifier: :not.")),
                name: FHIRPrimitive(FHIRString("stage")),
                type: FHIRPrimitive(.token)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/Condition-onset-info")),
                documentation: FHIRPrimitive(FHIRString("Condition.onsetString. Prefix/contains/exact match.")),
                name: FHIRPrimitive(FHIRString("onset-info")),
                type: FHIRPrimitive(.string)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/Condition-abatement-string")),
                documentation: FHIRPrimitive(FHIRString("Condition.abatementString. Prefix/contains/exact match.")),
                name: FHIRPrimitive(FHIRString("abatement-string")),
                type: FHIRPrimitive(.string)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/Condition-onset-age")),
                documentation: FHIRPrimitive(FHIRString("Condition.onsetAge. Prefixes: eq (sig-figs range), lt, gt, le, ge, ne, ap.")),
                name: FHIRPrimitive(FHIRString("onset-age")),
                type: FHIRPrimitive(.quantity)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/Condition-abatement-age")),
                documentation: FHIRPrimitive(FHIRString("Condition.abatementAge. Prefixes: eq (sig-figs range), lt, gt, le, ge, ne, ap.")),
                name: FHIRPrimitive(FHIRString("abatement-age")),
                type: FHIRPrimitive(.quantity)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/Resource-id")),
                documentation: FHIRPrimitive(FHIRString("Filter by resource id. Comma-separated for OR.")),
                name: FHIRPrimitive(FHIRString("_id")),
                type: FHIRPrimitive(.token)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/Resource-lastUpdated")),
                documentation: FHIRPrimitive(FHIRString("Filter by last modification time. Prefixes: eq, lt, gt, le, ge.")),
                name: FHIRPrimitive(FHIRString("_lastUpdated")),
                type: FHIRPrimitive(.date)
            ),
        ],
        type: FHIRPrimitive(.condition),
        versioning: FHIRPrimitive(.versioned)
    )
    r.conditionalCreate = FHIRPrimitive(FHIRBool(true))
    r.conditionalUpdate = FHIRPrimitive(FHIRBool(true))
    r.conditionalDelete = FHIRPrimitive(.single)
    r.conditionalRead = FHIRPrimitive(.fullSupport)
    r.updateCreate = FHIRPrimitive(FHIRBool(true))
    r.searchInclude = [
        "Condition:subject", "Condition:patient", "Condition:encounter",
    ].map { FHIRPrimitive(FHIRString($0)) }
    return r
}

private func medicationResource() -> CapabilityStatementRestResource {
    var r = CapabilityStatementRestResource(
        documentation: FHIRPrimitive(FHIRString(
            "Medication resource. Search params: code, status, form, identifier, lot-number, " +
            "ingredient-code, manufacturer, ingredient, expiration-date, _id, _lastUpdated."
        )),
        interaction: baselineInteractions,
        readHistory: FHIRPrimitive(FHIRBool(true)),
        searchParam: [
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/Medication-code")),
                documentation: FHIRPrimitive(FHIRString("Token: medication code.")),
                name: FHIRPrimitive(FHIRString("code")),
                type: FHIRPrimitive(.token)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/Medication-status")),
                documentation: FHIRPrimitive(FHIRString("Token: active|inactive|entered-in-error.")),
                name: FHIRPrimitive(FHIRString("status")),
                type: FHIRPrimitive(.token)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/Medication-form")),
                documentation: FHIRPrimitive(FHIRString("Token: powder|tablets|capsules|...")),
                name: FHIRPrimitive(FHIRString("form")),
                type: FHIRPrimitive(.token)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/Medication-identifier")),
                name: FHIRPrimitive(FHIRString("identifier")),
                type: FHIRPrimitive(.token)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/Medication-lot-number")),
                documentation: FHIRPrimitive(FHIRString("Token: batch lot number.")),
                name: FHIRPrimitive(FHIRString("lot-number")),
                type: FHIRPrimitive(.token)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/Medication-ingredient-code")),
                documentation: FHIRPrimitive(FHIRString("Token: ingredient as CodeableConcept.")),
                name: FHIRPrimitive(FHIRString("ingredient-code")),
                type: FHIRPrimitive(.token)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/Medication-expiration-date")),
                documentation: FHIRPrimitive(FHIRString("Date: batch expiration date. Prefixes: eq|lt|gt|le|ge|sa|eb.")),
                name: FHIRPrimitive(FHIRString("expiration-date")),
                type: FHIRPrimitive(.date)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/Medication-manufacturer")),
                documentation: FHIRPrimitive(FHIRString("Reference to manufacturer Organization.")),
                name: FHIRPrimitive(FHIRString("manufacturer")),
                type: FHIRPrimitive(.reference)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/Medication-ingredient")),
                documentation: FHIRPrimitive(FHIRString("Reference to ingredient substance/medication.")),
                name: FHIRPrimitive(FHIRString("ingredient")),
                type: FHIRPrimitive(.reference)
            ),
            CapabilityStatementRestResourceSearchParam(
                name: FHIRPrimitive(FHIRString("_id")),
                type: FHIRPrimitive(.token)
            ),
            CapabilityStatementRestResourceSearchParam(
                name: FHIRPrimitive(FHIRString("_lastUpdated")),
                type: FHIRPrimitive(.date)
            ),
        ],
        type: FHIRPrimitive(.medication),
        versioning: FHIRPrimitive(.versioned)
    )
    r.conditionalCreate = FHIRPrimitive(FHIRBool(true))
    r.conditionalUpdate = FHIRPrimitive(FHIRBool(true))
    r.conditionalDelete = FHIRPrimitive(.single)
    r.conditionalRead = FHIRPrimitive(.fullSupport)
    r.updateCreate = FHIRPrimitive(FHIRBool(true))
    r.searchInclude = [
        "Medication:manufacturer",
        "Medication:ingredient",
    ].map { FHIRPrimitive(FHIRString($0)) }
    return r
}

private func medicationRequestResource() -> CapabilityStatementRestResource {
    var r = CapabilityStatementRestResource(
        documentation: FHIRPrimitive(FHIRString(
            "MedicationRequest resource. " +
            "Supports read, vread, create (conditional via If-None-Exist), update (conditional via PUT /MedicationRequest?<search>), delete, history-instance, and search (GET and POST /_search). " +
            "Search: subject, patient, status, intent, category, code, priority, identifier, authoredon, encounter, requester; _sort=±_lastUpdated/±authoredon/±_id; _total (accurate|estimate|none); _elements (field filter); _summary (true|text|data|count|false). " +
            ":not and :missing modifiers supported. " +
            "Compartment: GET /Patient/:id/MedicationRequest."
        )),
        interaction: baselineInteractions,
        readHistory: FHIRPrimitive(FHIRBool(true)),
        searchParam: [
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/MedicationRequest-subject")),
                documentation: FHIRPrimitive(FHIRString("Reference to subject. Formats: Patient/id or bare id.")),
                name: FHIRPrimitive(FHIRString("subject")),
                type: FHIRPrimitive(.reference)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/MedicationRequest-patient")),
                documentation: FHIRPrimitive(FHIRString("Alias for subject constrained to Patient.")),
                name: FHIRPrimitive(FHIRString("patient")),
                type: FHIRPrimitive(.reference)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/MedicationRequest-status")),
                documentation: FHIRPrimitive(FHIRString("Token OR on MedicationRequest.status. Modifier: :not.")),
                name: FHIRPrimitive(FHIRString("status")),
                type: FHIRPrimitive(.token)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/MedicationRequest-intent")),
                documentation: FHIRPrimitive(FHIRString("Token OR on MedicationRequest.intent. Modifier: :not.")),
                name: FHIRPrimitive(FHIRString("intent")),
                type: FHIRPrimitive(.token)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/MedicationRequest-category")),
                documentation: FHIRPrimitive(FHIRString("Token OR on MedicationRequest.category CodeableConcept. Modifier: :not.")),
                name: FHIRPrimitive(FHIRString("category")),
                type: FHIRPrimitive(.token)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/MedicationRequest-code")),
                documentation: FHIRPrimitive(FHIRString("Token OR on MedicationRequest.medication when CodeableConcept. Modifier: :not.")),
                name: FHIRPrimitive(FHIRString("code")),
                type: FHIRPrimitive(.token)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/MedicationRequest-priority")),
                documentation: FHIRPrimitive(FHIRString("Token OR on MedicationRequest.priority. Modifier: :not.")),
                name: FHIRPrimitive(FHIRString("priority")),
                type: FHIRPrimitive(.token)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/MedicationRequest-identifier")),
                documentation: FHIRPrimitive(FHIRString("Token OR on MedicationRequest.identifier.")),
                name: FHIRPrimitive(FHIRString("identifier")),
                type: FHIRPrimitive(.token)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/MedicationRequest-authoredon")),
                documentation: FHIRPrimitive(FHIRString("Date search on MedicationRequest.authoredOn. Prefixes: eq, lt, gt, le, ge, sa, eb.")),
                name: FHIRPrimitive(FHIRString("authoredon")),
                type: FHIRPrimitive(.date)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/MedicationRequest-encounter")),
                documentation: FHIRPrimitive(FHIRString("Reference to Encounter. Formats: Encounter/id or bare id.")),
                name: FHIRPrimitive(FHIRString("encounter")),
                type: FHIRPrimitive(.reference)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/MedicationRequest-requester")),
                documentation: FHIRPrimitive(FHIRString("Reference to requester. Formats: ResourceType/id or bare id.")),
                name: FHIRPrimitive(FHIRString("requester")),
                type: FHIRPrimitive(.reference)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/MedicationRequest-date")),
                documentation: FHIRPrimitive(FHIRString("MedicationRequest.authoredOn. Prefixes: eq, lt, gt, le, ge, sa, eb.")),
                name: FHIRPrimitive(FHIRString("date")),
                type: FHIRPrimitive(.date)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/MedicationRequest-intended-dispenser")),
                documentation: FHIRPrimitive(FHIRString("MedicationRequest.dispenseRequest.performer. Reference: Organization/id or bare id.")),
                name: FHIRPrimitive(FHIRString("intended-dispenser")),
                type: FHIRPrimitive(.reference)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/MedicationRequest-intended-performer")),
                documentation: FHIRPrimitive(FHIRString("MedicationRequest.performer. Reference: ResourceType/id or bare id.")),
                name: FHIRPrimitive(FHIRString("intended-performer")),
                type: FHIRPrimitive(.reference)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/MedicationRequest-intended-performertype")),
                documentation: FHIRPrimitive(FHIRString("MedicationRequest.performerType.coding. Token: system|code. Modifier: :not.")),
                name: FHIRPrimitive(FHIRString("intended-performertype")),
                type: FHIRPrimitive(.token)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/MedicationRequest-medication")),
                documentation: FHIRPrimitive(FHIRString("MedicationRequest.medicationReference. Reference: Medication/id or bare id.")),
                name: FHIRPrimitive(FHIRString("medication")),
                type: FHIRPrimitive(.reference)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/Resource-id")),
                documentation: FHIRPrimitive(FHIRString("Filter by resource id. Comma-separated for OR.")),
                name: FHIRPrimitive(FHIRString("_id")),
                type: FHIRPrimitive(.token)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/Resource-lastUpdated")),
                documentation: FHIRPrimitive(FHIRString("Filter by last modification time. Prefixes: eq, lt, gt, le, ge.")),
                name: FHIRPrimitive(FHIRString("_lastUpdated")),
                type: FHIRPrimitive(.date)
            ),
        ],
        type: FHIRPrimitive(.medicationRequest),
        versioning: FHIRPrimitive(.versioned)
    )
    r.conditionalCreate = FHIRPrimitive(FHIRBool(true))
    r.conditionalUpdate = FHIRPrimitive(FHIRBool(true))
    r.conditionalDelete = FHIRPrimitive(.single)
    r.conditionalRead = FHIRPrimitive(.fullSupport)
    r.updateCreate = FHIRPrimitive(FHIRBool(true))
    r.searchInclude = [
        "MedicationRequest:subject", "MedicationRequest:patient", "MedicationRequest:encounter",
    ].map { FHIRPrimitive(FHIRString($0)) }
    return r
}

private func allergyIntoleranceResource() -> CapabilityStatementRestResource {
    var r = CapabilityStatementRestResource(
        documentation: FHIRPrimitive(FHIRString(
            "AllergyIntolerance resource. " +
            "Supports read, vread, create (conditional via If-None-Exist), update (conditional via PUT /AllergyIntolerance?<search>), delete, history-instance, and search (GET and POST /_search). " +
            "Search: patient, clinical-status, verification-status, type, category, criticality, code, identifier, date, manifestation, severity, route, last-date, onset; _sort=±_lastUpdated/±date/±_id; _total (accurate|estimate|none); _elements (field filter); _summary (true|text|data|count|false). " +
            ":not and :missing modifiers supported. " +
            "Compartment: GET /Patient/:id/AllergyIntolerance."
        )),
        interaction: baselineInteractions,
        readHistory: FHIRPrimitive(FHIRBool(true)),
        searchParam: [
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/AllergyIntolerance-patient")),
                documentation: FHIRPrimitive(FHIRString("Reference to patient. Formats: Patient/id or bare id.")),
                name: FHIRPrimitive(FHIRString("patient")),
                type: FHIRPrimitive(.reference)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/AllergyIntolerance-clinical-status")),
                documentation: FHIRPrimitive(FHIRString("Token OR on AllergyIntolerance.clinicalStatus CodeableConcept. Modifier: :not.")),
                name: FHIRPrimitive(FHIRString("clinical-status")),
                type: FHIRPrimitive(.token)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/AllergyIntolerance-verification-status")),
                documentation: FHIRPrimitive(FHIRString("Token OR on AllergyIntolerance.verificationStatus CodeableConcept. Modifier: :not.")),
                name: FHIRPrimitive(FHIRString("verification-status")),
                type: FHIRPrimitive(.token)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/AllergyIntolerance-type")),
                documentation: FHIRPrimitive(FHIRString("Token OR on AllergyIntolerance.type enum. Modifier: :not.")),
                name: FHIRPrimitive(FHIRString("type")),
                type: FHIRPrimitive(.token)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/AllergyIntolerance-category")),
                documentation: FHIRPrimitive(FHIRString("Token OR on AllergyIntolerance.category array of enum. Modifier: :not.")),
                name: FHIRPrimitive(FHIRString("category")),
                type: FHIRPrimitive(.token)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/AllergyIntolerance-criticality")),
                documentation: FHIRPrimitive(FHIRString("Token OR on AllergyIntolerance.criticality enum. Modifier: :not.")),
                name: FHIRPrimitive(FHIRString("criticality")),
                type: FHIRPrimitive(.token)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/AllergyIntolerance-code")),
                documentation: FHIRPrimitive(FHIRString("Token OR on AllergyIntolerance.code CodeableConcept. Modifier: :not.")),
                name: FHIRPrimitive(FHIRString("code")),
                type: FHIRPrimitive(.token)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/AllergyIntolerance-identifier")),
                documentation: FHIRPrimitive(FHIRString("Token OR on AllergyIntolerance.identifier.")),
                name: FHIRPrimitive(FHIRString("identifier")),
                type: FHIRPrimitive(.token)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/AllergyIntolerance-date")),
                documentation: FHIRPrimitive(FHIRString("Date search on AllergyIntolerance.recordedDate. Prefixes: eq, lt, gt, le, ge, sa, eb.")),
                name: FHIRPrimitive(FHIRString("date")),
                type: FHIRPrimitive(.date)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/AllergyIntolerance-manifestation")),
                documentation: FHIRPrimitive(FHIRString("Token OR on reaction.manifestation CodeableConcept. Modifier: :not.")),
                name: FHIRPrimitive(FHIRString("manifestation")),
                type: FHIRPrimitive(.token)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/AllergyIntolerance-severity")),
                documentation: FHIRPrimitive(FHIRString("Token OR on reaction.severity enum. Modifier: :not.")),
                name: FHIRPrimitive(FHIRString("severity")),
                type: FHIRPrimitive(.token)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/AllergyIntolerance-route")),
                documentation: FHIRPrimitive(FHIRString("Token OR on reaction.exposureRoute CodeableConcept. Modifier: :not.")),
                name: FHIRPrimitive(FHIRString("route")),
                type: FHIRPrimitive(.token)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/AllergyIntolerance-last-date")),
                documentation: FHIRPrimitive(FHIRString("Date search on AllergyIntolerance.lastOccurrence. Prefixes: eq, lt, gt, le, ge, sa, eb.")),
                name: FHIRPrimitive(FHIRString("last-date")),
                type: FHIRPrimitive(.date)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/AllergyIntolerance-onset")),
                documentation: FHIRPrimitive(FHIRString("Date search on reaction.onset DateTime. Prefixes: eq, lt, gt, le, ge, sa, eb.")),
                name: FHIRPrimitive(FHIRString("onset")),
                type: FHIRPrimitive(.date)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/AllergyIntolerance-asserter")),
                documentation: FHIRPrimitive(FHIRString("AllergyIntolerance.asserter. Reference: ResourceType/id or bare id.")),
                name: FHIRPrimitive(FHIRString("asserter")),
                type: FHIRPrimitive(.reference)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/AllergyIntolerance-recorder")),
                documentation: FHIRPrimitive(FHIRString("AllergyIntolerance.recorder. Reference: ResourceType/id or bare id.")),
                name: FHIRPrimitive(FHIRString("recorder")),
                type: FHIRPrimitive(.reference)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/Resource-id")),
                documentation: FHIRPrimitive(FHIRString("Filter by resource id. Comma-separated for OR.")),
                name: FHIRPrimitive(FHIRString("_id")),
                type: FHIRPrimitive(.token)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/Resource-lastUpdated")),
                documentation: FHIRPrimitive(FHIRString("Filter by last modification time. Prefixes: eq, lt, gt, le, ge.")),
                name: FHIRPrimitive(FHIRString("_lastUpdated")),
                type: FHIRPrimitive(.date)
            ),
        ],
        type: FHIRPrimitive(.allergyIntolerance),
        versioning: FHIRPrimitive(.versioned)
    )
    r.conditionalCreate = FHIRPrimitive(FHIRBool(true))
    r.conditionalUpdate = FHIRPrimitive(FHIRBool(true))
    r.conditionalDelete = FHIRPrimitive(.single)
    r.conditionalRead = FHIRPrimitive(.fullSupport)
    r.updateCreate = FHIRPrimitive(FHIRBool(true))
    r.searchInclude = [
        "AllergyIntolerance:patient",
    ].map { FHIRPrimitive(FHIRString($0)) }
    return r
}

private func procedureResource() -> CapabilityStatementRestResource {
    var r = CapabilityStatementRestResource(
        documentation: FHIRPrimitive(FHIRString(
            "Procedure resource. " +
            "Supports read, vread, create (conditional via If-None-Exist), update (conditional via PUT /Procedure?<search>), delete, history-instance, and search (GET and POST /_search). " +
            "Search: subject, patient, encounter, performer, status, code, category, identifier, date; _sort=±_lastUpdated/±date/±_id; _total (accurate|estimate|none); _elements (field filter); _summary (true|text|data|count|false). " +
            ":not and :missing modifiers supported. " +
            "Compartment: GET /Patient/:id/Procedure and POST /Patient/:id/Procedure/_search."
        )),
        interaction: baselineInteractions,
        readHistory: FHIRPrimitive(FHIRBool(true)),
        searchParam: [
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/Procedure-subject")),
                documentation: FHIRPrimitive(FHIRString("Reference to subject. Formats: Patient/id or bare id.")),
                name: FHIRPrimitive(FHIRString("subject")),
                type: FHIRPrimitive(.reference)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/Procedure-patient")),
                documentation: FHIRPrimitive(FHIRString("Alias for subject constrained to Patient.")),
                name: FHIRPrimitive(FHIRString("patient")),
                type: FHIRPrimitive(.reference)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/Procedure-status")),
                documentation: FHIRPrimitive(FHIRString("Token OR on Procedure.status. Modifier: :not.")),
                name: FHIRPrimitive(FHIRString("status")),
                type: FHIRPrimitive(.token)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/Procedure-code")),
                documentation: FHIRPrimitive(FHIRString("Token OR on Procedure.code CodeableConcept. Modifier: :not.")),
                name: FHIRPrimitive(FHIRString("code")),
                type: FHIRPrimitive(.token)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/Procedure-category")),
                documentation: FHIRPrimitive(FHIRString("Token OR on Procedure.category CodeableConcept. Modifier: :not.")),
                name: FHIRPrimitive(FHIRString("category")),
                type: FHIRPrimitive(.token)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/Procedure-identifier")),
                documentation: FHIRPrimitive(FHIRString("Token OR on Procedure.identifier.")),
                name: FHIRPrimitive(FHIRString("identifier")),
                type: FHIRPrimitive(.token)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/Procedure-encounter")),
                documentation: FHIRPrimitive(FHIRString("Reference to Encounter. Formats: Encounter/id or bare id.")),
                name: FHIRPrimitive(FHIRString("encounter")),
                type: FHIRPrimitive(.reference)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/Procedure-performer")),
                documentation: FHIRPrimitive(FHIRString("Reference to performer actor. Formats: ResourceType/id or bare id.")),
                name: FHIRPrimitive(FHIRString("performer")),
                type: FHIRPrimitive(.reference)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/Procedure-date")),
                documentation: FHIRPrimitive(FHIRString("Date search on Procedure.performed[x]. Prefixes: eq, lt, gt, le, ge, sa, eb.")),
                name: FHIRPrimitive(FHIRString("date")),
                type: FHIRPrimitive(.date)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/Procedure-based-on")),
                documentation: FHIRPrimitive(FHIRString("Procedure.basedOn[]. Reference: ResourceType/id or bare id.")),
                name: FHIRPrimitive(FHIRString("based-on")),
                type: FHIRPrimitive(.reference)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/Procedure-instantiates-canonical")),
                documentation: FHIRPrimitive(FHIRString("Procedure.instantiatesCanonical[]. URI match.")),
                name: FHIRPrimitive(FHIRString("instantiates-canonical")),
                type: FHIRPrimitive(.uri)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/Procedure-instantiates-uri")),
                documentation: FHIRPrimitive(FHIRString("Procedure.instantiatesUri[]. URI match.")),
                name: FHIRPrimitive(FHIRString("instantiates-uri")),
                type: FHIRPrimitive(.uri)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/Procedure-location")),
                documentation: FHIRPrimitive(FHIRString("Procedure.location. Reference: Location/id or bare id.")),
                name: FHIRPrimitive(FHIRString("location")),
                type: FHIRPrimitive(.reference)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/Procedure-part-of")),
                documentation: FHIRPrimitive(FHIRString("Procedure.partOf[]. Reference: ResourceType/id or bare id.")),
                name: FHIRPrimitive(FHIRString("part-of")),
                type: FHIRPrimitive(.reference)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/Procedure-reason-code")),
                documentation: FHIRPrimitive(FHIRString("Procedure.reasonCode[].coding. Token: system|code. Modifier: :not.")),
                name: FHIRPrimitive(FHIRString("reason-code")),
                type: FHIRPrimitive(.token)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/Procedure-reason-reference")),
                documentation: FHIRPrimitive(FHIRString("Procedure.reasonReference[]. Reference: ResourceType/id or bare id.")),
                name: FHIRPrimitive(FHIRString("reason-reference")),
                type: FHIRPrimitive(.reference)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/Resource-id")),
                documentation: FHIRPrimitive(FHIRString("Filter by resource id. Comma-separated for OR.")),
                name: FHIRPrimitive(FHIRString("_id")),
                type: FHIRPrimitive(.token)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/Resource-lastUpdated")),
                documentation: FHIRPrimitive(FHIRString("Filter by last modification time. Prefixes: eq, lt, gt, le, ge.")),
                name: FHIRPrimitive(FHIRString("_lastUpdated")),
                type: FHIRPrimitive(.date)
            ),
        ],
        type: FHIRPrimitive(.procedure),
        versioning: FHIRPrimitive(.versioned)
    )
    r.conditionalCreate = FHIRPrimitive(FHIRBool(true))
    r.conditionalUpdate = FHIRPrimitive(FHIRBool(true))
    r.conditionalDelete = FHIRPrimitive(.single)
    r.conditionalRead = FHIRPrimitive(.fullSupport)
    r.updateCreate = FHIRPrimitive(FHIRBool(true))
    r.searchInclude = [
        "Procedure:subject", "Procedure:patient", "Procedure:encounter",
    ].map { FHIRPrimitive(FHIRString($0)) }
    return r
}

private func diagnosticReportResource() -> CapabilityStatementRestResource {
    var r = CapabilityStatementRestResource(
        documentation: FHIRPrimitive(FHIRString(
            "DiagnosticReport resource. " +
            "Supports read, vread, create (conditional via If-None-Exist), update (conditional via PUT /DiagnosticReport?<search>), delete, history-instance, and search (GET and POST /_search). " +
            "Search: subject, patient, encounter, performer, status, code, category, identifier, date, issued; _sort=±_lastUpdated/±date/±_id; _total (accurate|estimate|none); _elements (field filter); _summary (true|text|data|count|false). " +
            ":not and :missing modifiers supported. " +
            "Compartment: GET /Patient/:id/DiagnosticReport and POST /Patient/:id/DiagnosticReport/_search."
        )),
        interaction: baselineInteractions,
        readHistory: FHIRPrimitive(FHIRBool(true)),
        searchParam: [
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/DiagnosticReport-subject")),
                documentation: FHIRPrimitive(FHIRString("Reference to subject. Formats: Patient/id or bare id.")),
                name: FHIRPrimitive(FHIRString("subject")),
                type: FHIRPrimitive(.reference)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/DiagnosticReport-patient")),
                documentation: FHIRPrimitive(FHIRString("Alias for subject constrained to Patient.")),
                name: FHIRPrimitive(FHIRString("patient")),
                type: FHIRPrimitive(.reference)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/DiagnosticReport-status")),
                documentation: FHIRPrimitive(FHIRString("Token OR on DiagnosticReport.status. Modifier: :not.")),
                name: FHIRPrimitive(FHIRString("status")),
                type: FHIRPrimitive(.token)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/DiagnosticReport-code")),
                documentation: FHIRPrimitive(FHIRString("Token OR on DiagnosticReport.code CodeableConcept. Modifier: :not.")),
                name: FHIRPrimitive(FHIRString("code")),
                type: FHIRPrimitive(.token)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/DiagnosticReport-category")),
                documentation: FHIRPrimitive(FHIRString("Token OR on DiagnosticReport.category array of CodeableConcept. Modifier: :not.")),
                name: FHIRPrimitive(FHIRString("category")),
                type: FHIRPrimitive(.token)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/DiagnosticReport-identifier")),
                documentation: FHIRPrimitive(FHIRString("Token OR on DiagnosticReport.identifier.")),
                name: FHIRPrimitive(FHIRString("identifier")),
                type: FHIRPrimitive(.token)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/DiagnosticReport-encounter")),
                documentation: FHIRPrimitive(FHIRString("Reference to Encounter. Formats: Encounter/id or bare id.")),
                name: FHIRPrimitive(FHIRString("encounter")),
                type: FHIRPrimitive(.reference)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/DiagnosticReport-performer")),
                documentation: FHIRPrimitive(FHIRString("Reference to performer. Formats: ResourceType/id or bare id.")),
                name: FHIRPrimitive(FHIRString("performer")),
                type: FHIRPrimitive(.reference)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/DiagnosticReport-date")),
                documentation: FHIRPrimitive(FHIRString("Date search on DiagnosticReport.effective[x]. Prefixes: eq, lt, gt, le, ge, sa, eb.")),
                name: FHIRPrimitive(FHIRString("date")),
                type: FHIRPrimitive(.date)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/DiagnosticReport-issued")),
                documentation: FHIRPrimitive(FHIRString("Date search on DiagnosticReport.issued (instant). Prefixes: eq, lt, gt, le, ge, sa, eb.")),
                name: FHIRPrimitive(FHIRString("issued")),
                type: FHIRPrimitive(.date)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/DiagnosticReport-based-on")),
                documentation: FHIRPrimitive(FHIRString("DiagnosticReport.basedOn[]. Reference: ResourceType/id or bare id.")),
                name: FHIRPrimitive(FHIRString("based-on")),
                type: FHIRPrimitive(.reference)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/DiagnosticReport-conclusion")),
                documentation: FHIRPrimitive(FHIRString("DiagnosticReport.conclusionCode[].coding. Token: system|code. Modifier: :not.")),
                name: FHIRPrimitive(FHIRString("conclusion")),
                type: FHIRPrimitive(.token)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/DiagnosticReport-media")),
                documentation: FHIRPrimitive(FHIRString("DiagnosticReport.media[].link. Reference: Media/id or bare id.")),
                name: FHIRPrimitive(FHIRString("media")),
                type: FHIRPrimitive(.reference)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/DiagnosticReport-result")),
                documentation: FHIRPrimitive(FHIRString("DiagnosticReport.result[]. Reference: Observation/id or bare id.")),
                name: FHIRPrimitive(FHIRString("result")),
                type: FHIRPrimitive(.reference)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/DiagnosticReport-results-interpreter")),
                documentation: FHIRPrimitive(FHIRString("DiagnosticReport.resultsInterpreter[]. Reference: ResourceType/id or bare id.")),
                name: FHIRPrimitive(FHIRString("results-interpreter")),
                type: FHIRPrimitive(.reference)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/DiagnosticReport-specimen")),
                documentation: FHIRPrimitive(FHIRString("DiagnosticReport.specimen[]. Reference: Specimen/id or bare id.")),
                name: FHIRPrimitive(FHIRString("specimen")),
                type: FHIRPrimitive(.reference)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/Resource-id")),
                documentation: FHIRPrimitive(FHIRString("Filter by resource id. Comma-separated for OR.")),
                name: FHIRPrimitive(FHIRString("_id")),
                type: FHIRPrimitive(.token)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/Resource-lastUpdated")),
                documentation: FHIRPrimitive(FHIRString("Filter by last modification time. Prefixes: eq, lt, gt, le, ge.")),
                name: FHIRPrimitive(FHIRString("_lastUpdated")),
                type: FHIRPrimitive(.date)
            ),
        ],
        type: FHIRPrimitive(.diagnosticReport),
        versioning: FHIRPrimitive(.versioned)
    )
    r.conditionalCreate = FHIRPrimitive(FHIRBool(true))
    r.conditionalUpdate = FHIRPrimitive(FHIRBool(true))
    r.conditionalDelete = FHIRPrimitive(.single)
    r.conditionalRead = FHIRPrimitive(.fullSupport)
    r.updateCreate = FHIRPrimitive(FHIRBool(true))
    r.searchInclude = [
        "DiagnosticReport:subject", "DiagnosticReport:patient", "DiagnosticReport:encounter",
    ].map { FHIRPrimitive(FHIRString($0)) }
    return r
}

private func immunizationResource() -> CapabilityStatementRestResource {
    var r = CapabilityStatementRestResource(
        documentation: FHIRPrimitive(FHIRString(
            "Immunization resource. " +
            "Supports read, vread, create (conditional via If-None-Exist), update (conditional via PUT /Immunization?<search>), delete, history-instance, and search (GET and POST /_search). " +
            "Search: patient, status, vaccine-code, identifier, date, performer, lot-number; _sort=±_lastUpdated/±date/±_id; _total (accurate|estimate|none); _elements (field filter); _summary (true|text|data|count|false). " +
            ":not and :missing modifiers supported. " +
            "Compartment: GET /Patient/:id/Immunization and POST /Patient/:id/Immunization/_search."
        )),
        interaction: baselineInteractions,
        readHistory: FHIRPrimitive(FHIRBool(true)),
        searchParam: [
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/Immunization-patient")),
                documentation: FHIRPrimitive(FHIRString("Reference to patient. Formats: Patient/id or bare id.")),
                name: FHIRPrimitive(FHIRString("patient")),
                type: FHIRPrimitive(.reference)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/Immunization-status")),
                documentation: FHIRPrimitive(FHIRString("Token OR on Immunization.status. Modifier: :not.")),
                name: FHIRPrimitive(FHIRString("status")),
                type: FHIRPrimitive(.token)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/Immunization-vaccine-code")),
                documentation: FHIRPrimitive(FHIRString("Token OR on Immunization.vaccineCode CodeableConcept. Modifier: :not.")),
                name: FHIRPrimitive(FHIRString("vaccine-code")),
                type: FHIRPrimitive(.token)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/Immunization-identifier")),
                documentation: FHIRPrimitive(FHIRString("Token OR on Immunization.identifier.")),
                name: FHIRPrimitive(FHIRString("identifier")),
                type: FHIRPrimitive(.token)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/Immunization-date")),
                documentation: FHIRPrimitive(FHIRString("Date search on Immunization.occurrence[x] (dateTime). Prefixes: eq, lt, gt, le, ge, sa, eb.")),
                name: FHIRPrimitive(FHIRString("date")),
                type: FHIRPrimitive(.date)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/Immunization-performer")),
                documentation: FHIRPrimitive(FHIRString("Reference to performer actor. Formats: ResourceType/id or bare id.")),
                name: FHIRPrimitive(FHIRString("performer")),
                type: FHIRPrimitive(.reference)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/Immunization-lot-number")),
                documentation: FHIRPrimitive(FHIRString("Starts-with on Immunization.lotNumber. Modifiers: :contains, :exact.")),
                name: FHIRPrimitive(FHIRString("lot-number")),
                type: FHIRPrimitive(.string)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/Immunization-location")),
                documentation: FHIRPrimitive(FHIRString("Immunization.location. Reference: Location/id or bare id.")),
                name: FHIRPrimitive(FHIRString("location")),
                type: FHIRPrimitive(.reference)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/Immunization-manufacturer")),
                documentation: FHIRPrimitive(FHIRString("Immunization.manufacturer. Reference: Organization/id or bare id.")),
                name: FHIRPrimitive(FHIRString("manufacturer")),
                type: FHIRPrimitive(.reference)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/Immunization-reaction")),
                documentation: FHIRPrimitive(FHIRString("Immunization.reaction[].detail. Reference: Observation/id or bare id.")),
                name: FHIRPrimitive(FHIRString("reaction")),
                type: FHIRPrimitive(.reference)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/Immunization-reaction-date")),
                documentation: FHIRPrimitive(FHIRString("Immunization.reaction[].date. Date range.")),
                name: FHIRPrimitive(FHIRString("reaction-date")),
                type: FHIRPrimitive(.date)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/Immunization-reason-code")),
                documentation: FHIRPrimitive(FHIRString("Immunization.reasonCode[].coding. Token: system|code. Modifier: :not.")),
                name: FHIRPrimitive(FHIRString("reason-code")),
                type: FHIRPrimitive(.token)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/Immunization-reason-reference")),
                documentation: FHIRPrimitive(FHIRString("Immunization.reasonReference[]. Reference: ResourceType/id or bare id.")),
                name: FHIRPrimitive(FHIRString("reason-reference")),
                type: FHIRPrimitive(.reference)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/Immunization-series")),
                documentation: FHIRPrimitive(FHIRString("Immunization.protocolApplied[].series. Prefix/contains/exact.")),
                name: FHIRPrimitive(FHIRString("series")),
                type: FHIRPrimitive(.string)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/Immunization-status-reason")),
                documentation: FHIRPrimitive(FHIRString("Immunization.statusReason.coding. Token: system|code. Modifier: :not.")),
                name: FHIRPrimitive(FHIRString("status-reason")),
                type: FHIRPrimitive(.token)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/Immunization-target-disease")),
                documentation: FHIRPrimitive(FHIRString("Immunization.protocolApplied[].targetDisease[].coding. Token: system|code. Modifier: :not.")),
                name: FHIRPrimitive(FHIRString("target-disease")),
                type: FHIRPrimitive(.token)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/Resource-id")),
                documentation: FHIRPrimitive(FHIRString("Filter by resource id. Comma-separated for OR.")),
                name: FHIRPrimitive(FHIRString("_id")),
                type: FHIRPrimitive(.token)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/Resource-lastUpdated")),
                documentation: FHIRPrimitive(FHIRString("Filter by last modification time. Prefixes: eq, lt, gt, le, ge.")),
                name: FHIRPrimitive(FHIRString("_lastUpdated")),
                type: FHIRPrimitive(.date)
            ),
        ],
        type: FHIRPrimitive(.immunization),
        versioning: FHIRPrimitive(.versioned)
    )
    r.conditionalCreate = FHIRPrimitive(FHIRBool(true))
    r.conditionalUpdate = FHIRPrimitive(FHIRBool(true))
    r.conditionalDelete = FHIRPrimitive(.single)
    r.conditionalRead = FHIRPrimitive(.fullSupport)
    r.updateCreate = FHIRPrimitive(FHIRBool(true))
    r.searchInclude = [
        "Immunization:patient",
    ].map { FHIRPrimitive(FHIRString($0)) }
    return r
}

private func practitionerResource() -> CapabilityStatementRestResource {
    var r = CapabilityStatementRestResource(
        documentation: FHIRPrimitive(FHIRString(
            "Practitioner resource. Supports CRUD, history, and search. " +
            "Search: name, family, given, identifier, active, gender, address variants, phone, email, communication. " +
            "_sort: ±name/±family/±_lastUpdated/±_id."
        )),
        interaction: baselineInteractions,
        readHistory: FHIRPrimitive(FHIRBool(true)),
        searchParam: [
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/Practitioner-name")),
                documentation: FHIRPrimitive(FHIRString("Starts-with on name (family + given + text). Modifiers: :contains, :exact.")),
                name: FHIRPrimitive(FHIRString("name")),
                type: FHIRPrimitive(.string)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/Practitioner-family")),
                documentation: FHIRPrimitive(FHIRString("Starts-with on family name.")),
                name: FHIRPrimitive(FHIRString("family")),
                type: FHIRPrimitive(.string)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/Practitioner-given")),
                documentation: FHIRPrimitive(FHIRString("Starts-with on given name(s).")),
                name: FHIRPrimitive(FHIRString("given")),
                type: FHIRPrimitive(.string)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/Practitioner-identifier")),
                documentation: FHIRPrimitive(FHIRString("Token: system|code.")),
                name: FHIRPrimitive(FHIRString("identifier")),
                type: FHIRPrimitive(.token)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/Practitioner-active")),
                documentation: FHIRPrimitive(FHIRString("Boolean: active=true or active=false.")),
                name: FHIRPrimitive(FHIRString("active")),
                type: FHIRPrimitive(.token)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/Practitioner-gender")),
                documentation: FHIRPrimitive(FHIRString("Token OR: male|female|other|unknown.")),
                name: FHIRPrimitive(FHIRString("gender")),
                type: FHIRPrimitive(.token)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/Practitioner-address")),
                documentation: FHIRPrimitive(FHIRString("String across all address fields.")),
                name: FHIRPrimitive(FHIRString("address")),
                type: FHIRPrimitive(.string)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/Practitioner-address-city")),
                name: FHIRPrimitive(FHIRString("address-city")),
                type: FHIRPrimitive(.string)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/Practitioner-address-state")),
                name: FHIRPrimitive(FHIRString("address-state")),
                type: FHIRPrimitive(.string)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/Practitioner-address-postalcode")),
                name: FHIRPrimitive(FHIRString("address-postalcode")),
                type: FHIRPrimitive(.string)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/Practitioner-address-country")),
                name: FHIRPrimitive(FHIRString("address-country")),
                type: FHIRPrimitive(.string)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/Practitioner-phone")),
                documentation: FHIRPrimitive(FHIRString("Telecom phone value.")),
                name: FHIRPrimitive(FHIRString("phone")),
                type: FHIRPrimitive(.token)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/Practitioner-email")),
                documentation: FHIRPrimitive(FHIRString("Telecom email value.")),
                name: FHIRPrimitive(FHIRString("email")),
                type: FHIRPrimitive(.token)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/Practitioner-communication")),
                documentation: FHIRPrimitive(FHIRString("Token: language code.")),
                name: FHIRPrimitive(FHIRString("communication")),
                type: FHIRPrimitive(.token)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/Practitioner-address-use")),
                documentation: FHIRPrimitive(FHIRString("Practitioner.address[].use. Token: home|work|temp|old|billing.")),
                name: FHIRPrimitive(FHIRString("address-use")),
                type: FHIRPrimitive(.token)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/Practitioner-phonetic")),
                documentation: FHIRPrimitive(FHIRString("Practitioner.name phonetic match (same as :contains on name).")),
                name: FHIRPrimitive(FHIRString("phonetic")),
                type: FHIRPrimitive(.string)
            ),
            CapabilityStatementRestResourceSearchParam(
                name: FHIRPrimitive(FHIRString("_id")),
                type: FHIRPrimitive(.token)
            ),
            CapabilityStatementRestResourceSearchParam(
                name: FHIRPrimitive(FHIRString("_lastUpdated")),
                type: FHIRPrimitive(.date)
            ),
        ],
        type: FHIRPrimitive(.practitioner),
        versioning: FHIRPrimitive(.versioned)
    )
    r.conditionalCreate = FHIRPrimitive(FHIRBool(true))
    r.conditionalUpdate = FHIRPrimitive(FHIRBool(true))
    r.conditionalDelete = FHIRPrimitive(.single)
    r.conditionalRead = FHIRPrimitive(.fullSupport)
    r.updateCreate = FHIRPrimitive(FHIRBool(true))
    return r
}

private func organizationResource() -> CapabilityStatementRestResource {
    var r = CapabilityStatementRestResource(
        documentation: FHIRPrimitive(FHIRString(
            "Organization resource. Supports CRUD, history, and search. " +
            "Search: name, identifier, active, type, address variants, partof. " +
            "_sort: ±name/±_lastUpdated/±_id."
        )),
        interaction: baselineInteractions,
        readHistory: FHIRPrimitive(FHIRBool(true)),
        searchParam: [
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/Organization-name")),
                documentation: FHIRPrimitive(FHIRString("Starts-with on name and alias. Modifiers: :contains, :exact.")),
                name: FHIRPrimitive(FHIRString("name")),
                type: FHIRPrimitive(.string)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/Organization-identifier")),
                documentation: FHIRPrimitive(FHIRString("Token: system|code.")),
                name: FHIRPrimitive(FHIRString("identifier")),
                type: FHIRPrimitive(.token)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/Organization-active")),
                documentation: FHIRPrimitive(FHIRString("Boolean: active=true or active=false.")),
                name: FHIRPrimitive(FHIRString("active")),
                type: FHIRPrimitive(.token)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/Organization-type")),
                documentation: FHIRPrimitive(FHIRString("Token OR: organization type code.")),
                name: FHIRPrimitive(FHIRString("type")),
                type: FHIRPrimitive(.token)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/Organization-address")),
                documentation: FHIRPrimitive(FHIRString("String across all address fields.")),
                name: FHIRPrimitive(FHIRString("address")),
                type: FHIRPrimitive(.string)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/Organization-address-city")),
                name: FHIRPrimitive(FHIRString("address-city")),
                type: FHIRPrimitive(.string)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/Organization-address-state")),
                name: FHIRPrimitive(FHIRString("address-state")),
                type: FHIRPrimitive(.string)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/Organization-address-postalcode")),
                name: FHIRPrimitive(FHIRString("address-postalcode")),
                type: FHIRPrimitive(.string)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/Organization-address-country")),
                name: FHIRPrimitive(FHIRString("address-country")),
                type: FHIRPrimitive(.string)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/Organization-partof")),
                documentation: FHIRPrimitive(FHIRString("Reference to parent Organization.")),
                name: FHIRPrimitive(FHIRString("partof")),
                type: FHIRPrimitive(.reference)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/Organization-address-use")),
                documentation: FHIRPrimitive(FHIRString("Organization.address[].use. Token: home|work|temp|old|billing.")),
                name: FHIRPrimitive(FHIRString("address-use")),
                type: FHIRPrimitive(.token)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/Organization-endpoint")),
                documentation: FHIRPrimitive(FHIRString("Organization.endpoint[]. Reference: Endpoint/id or bare id.")),
                name: FHIRPrimitive(FHIRString("endpoint")),
                type: FHIRPrimitive(.reference)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/Organization-phonetic")),
                documentation: FHIRPrimitive(FHIRString("Organization.name phonetic match (same as :contains on name).")),
                name: FHIRPrimitive(FHIRString("phonetic")),
                type: FHIRPrimitive(.string)
            ),
            CapabilityStatementRestResourceSearchParam(
                name: FHIRPrimitive(FHIRString("_id")),
                type: FHIRPrimitive(.token)
            ),
            CapabilityStatementRestResourceSearchParam(
                name: FHIRPrimitive(FHIRString("_lastUpdated")),
                type: FHIRPrimitive(.date)
            ),
        ],
        type: FHIRPrimitive(.organization),
        versioning: FHIRPrimitive(.versioned)
    )
    r.conditionalCreate = FHIRPrimitive(FHIRBool(true))
    r.conditionalUpdate = FHIRPrimitive(FHIRBool(true))
    r.conditionalDelete = FHIRPrimitive(.single)
    r.conditionalRead = FHIRPrimitive(.fullSupport)
    r.updateCreate = FHIRPrimitive(FHIRBool(true))
    r.searchInclude = [
        "Organization:partof",
    ].map { FHIRPrimitive(FHIRString($0)) }
    return r
}

private func locationResource() -> CapabilityStatementRestResource {
    var r = CapabilityStatementRestResource(
        documentation: FHIRPrimitive(FHIRString(
            "Location resource. Supports CRUD, history, and search. " +
            "Search: name, identifier, status, type, operational-status, address variants, organization, partof. " +
            "_sort: ±name/±_lastUpdated/±_id. near (geospatial) not supported."
        )),
        interaction: baselineInteractions,
        readHistory: FHIRPrimitive(FHIRBool(true)),
        searchParam: [
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/Location-name")),
                documentation: FHIRPrimitive(FHIRString("Starts-with on name and alias. Modifiers: :contains, :exact.")),
                name: FHIRPrimitive(FHIRString("name")),
                type: FHIRPrimitive(.string)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/Location-identifier")),
                documentation: FHIRPrimitive(FHIRString("Token: system|code.")),
                name: FHIRPrimitive(FHIRString("identifier")),
                type: FHIRPrimitive(.token)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/Location-status")),
                documentation: FHIRPrimitive(FHIRString("Token: active|suspended|inactive.")),
                name: FHIRPrimitive(FHIRString("status")),
                type: FHIRPrimitive(.token)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/Location-type")),
                documentation: FHIRPrimitive(FHIRString("Token OR: location type code.")),
                name: FHIRPrimitive(FHIRString("type")),
                type: FHIRPrimitive(.token)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/Location-operational-status")),
                documentation: FHIRPrimitive(FHIRString("Token: operational status code.")),
                name: FHIRPrimitive(FHIRString("operational-status")),
                type: FHIRPrimitive(.token)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/Location-address")),
                documentation: FHIRPrimitive(FHIRString("String across all address fields.")),
                name: FHIRPrimitive(FHIRString("address")),
                type: FHIRPrimitive(.string)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/Location-address-city")),
                name: FHIRPrimitive(FHIRString("address-city")),
                type: FHIRPrimitive(.string)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/Location-address-state")),
                name: FHIRPrimitive(FHIRString("address-state")),
                type: FHIRPrimitive(.string)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/Location-address-postalcode")),
                name: FHIRPrimitive(FHIRString("address-postalcode")),
                type: FHIRPrimitive(.string)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/Location-address-country")),
                name: FHIRPrimitive(FHIRString("address-country")),
                type: FHIRPrimitive(.string)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/Location-organization")),
                documentation: FHIRPrimitive(FHIRString("Reference to managing Organization.")),
                name: FHIRPrimitive(FHIRString("organization")),
                type: FHIRPrimitive(.reference)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/Location-partof")),
                documentation: FHIRPrimitive(FHIRString("Reference to parent Location.")),
                name: FHIRPrimitive(FHIRString("partof")),
                type: FHIRPrimitive(.reference)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/Location-address-use")),
                documentation: FHIRPrimitive(FHIRString("Location.address.use. Token: home|work|temp|old|billing.")),
                name: FHIRPrimitive(FHIRString("address-use")),
                type: FHIRPrimitive(.token)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/Location-endpoint")),
                documentation: FHIRPrimitive(FHIRString("Location.endpoint[]. Reference: Endpoint/id or bare id.")),
                name: FHIRPrimitive(FHIRString("endpoint")),
                type: FHIRPrimitive(.reference)
            ),
            CapabilityStatementRestResourceSearchParam(
                name: FHIRPrimitive(FHIRString("_id")),
                type: FHIRPrimitive(.token)
            ),
            CapabilityStatementRestResourceSearchParam(
                name: FHIRPrimitive(FHIRString("_lastUpdated")),
                type: FHIRPrimitive(.date)
            ),
        ],
        type: FHIRPrimitive(.location),
        versioning: FHIRPrimitive(.versioned)
    )
    r.conditionalCreate = FHIRPrimitive(FHIRBool(true))
    r.conditionalUpdate = FHIRPrimitive(FHIRBool(true))
    r.conditionalDelete = FHIRPrimitive(.single)
    r.conditionalRead = FHIRPrimitive(.fullSupport)
    r.updateCreate = FHIRPrimitive(FHIRBool(true))
    r.searchInclude = [
        "Location:organization",
        "Location:partof",
    ].map { FHIRPrimitive(FHIRString($0)) }
    return r
}

private func relatedPersonResource() -> CapabilityStatementRestResource {
    var r = CapabilityStatementRestResource(
        documentation: FHIRPrimitive(FHIRString(
            "RelatedPerson resource. Supports CRUD, history, and search. " +
            "In Patient compartment: GET /Patient/:id/RelatedPerson (POST /_search). " +
            "Search: name, identifier, patient, relationship, gender, active, birthdate, " +
            "address variants, phone, email, telecom, address-use. " +
            ":not modifier on active, gender, relationship. " +
            "_sort: ±_lastUpdated/±_id."
        )),
        interaction: baselineInteractions,
        readHistory: FHIRPrimitive(FHIRBool(true)),
        searchParam: [
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/RelatedPerson-name")),
                documentation: FHIRPrimitive(FHIRString("Starts-with on family, given, and text. Modifiers: :contains, :exact.")),
                name: FHIRPrimitive(FHIRString("name")),
                type: FHIRPrimitive(.string)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/RelatedPerson-phonetic")),
                documentation: FHIRPrimitive(FHIRString("Alias for name (same index). Modifiers: :contains, :exact.")),
                name: FHIRPrimitive(FHIRString("phonetic")),
                type: FHIRPrimitive(.string)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/RelatedPerson-identifier")),
                documentation: FHIRPrimitive(FHIRString("Token search. Formats: code, system|code, |code. Comma-separated for OR.")),
                name: FHIRPrimitive(FHIRString("identifier")),
                type: FHIRPrimitive(.token)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/RelatedPerson-patient")),
                documentation: FHIRPrimitive(FHIRString("Reference to patient. Formats: Patient/id or bare id.")),
                name: FHIRPrimitive(FHIRString("patient")),
                type: FHIRPrimitive(.reference)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/RelatedPerson-relationship")),
                documentation: FHIRPrimitive(FHIRString("Token OR on relationship codes. Modifier: :not.")),
                name: FHIRPrimitive(FHIRString("relationship")),
                type: FHIRPrimitive(.token)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/RelatedPerson-gender")),
                documentation: FHIRPrimitive(FHIRString("Token: male|female|other|unknown. Modifier: :not.")),
                name: FHIRPrimitive(FHIRString("gender")),
                type: FHIRPrimitive(.token)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/RelatedPerson-active")),
                documentation: FHIRPrimitive(FHIRString("Boolean: active=true or active=false. Modifier: :not.")),
                name: FHIRPrimitive(FHIRString("active")),
                type: FHIRPrimitive(.token)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/RelatedPerson-birthdate")),
                documentation: FHIRPrimitive(FHIRString("Date search with prefixes: eq, lt, gt, le, ge, sa, eb.")),
                name: FHIRPrimitive(FHIRString("birthdate")),
                type: FHIRPrimitive(.date)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/RelatedPerson-address")),
                documentation: FHIRPrimitive(FHIRString("Starts-with across all address sub-fields. Modifiers: :contains, :exact.")),
                name: FHIRPrimitive(FHIRString("address")),
                type: FHIRPrimitive(.string)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/RelatedPerson-address-city")),
                name: FHIRPrimitive(FHIRString("address-city")),
                type: FHIRPrimitive(.string)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/RelatedPerson-address-state")),
                name: FHIRPrimitive(FHIRString("address-state")),
                type: FHIRPrimitive(.string)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/RelatedPerson-address-postalcode")),
                name: FHIRPrimitive(FHIRString("address-postalcode")),
                type: FHIRPrimitive(.string)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/RelatedPerson-address-country")),
                name: FHIRPrimitive(FHIRString("address-country")),
                type: FHIRPrimitive(.string)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/RelatedPerson-address-use")),
                documentation: FHIRPrimitive(FHIRString("Token: home|work|temp|old|billing.")),
                name: FHIRPrimitive(FHIRString("address-use")),
                type: FHIRPrimitive(.token)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/RelatedPerson-phone")),
                documentation: FHIRPrimitive(FHIRString("Token on telecom where system=phone.")),
                name: FHIRPrimitive(FHIRString("phone")),
                type: FHIRPrimitive(.token)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/RelatedPerson-email")),
                documentation: FHIRPrimitive(FHIRString("Token on telecom where system=email.")),
                name: FHIRPrimitive(FHIRString("email")),
                type: FHIRPrimitive(.token)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/RelatedPerson-telecom")),
                documentation: FHIRPrimitive(FHIRString("Token across all telecom entries.")),
                name: FHIRPrimitive(FHIRString("telecom")),
                type: FHIRPrimitive(.token)
            ),
            CapabilityStatementRestResourceSearchParam(
                name: FHIRPrimitive(FHIRString("_id")),
                type: FHIRPrimitive(.token)
            ),
            CapabilityStatementRestResourceSearchParam(
                name: FHIRPrimitive(FHIRString("_lastUpdated")),
                type: FHIRPrimitive(.date)
            ),
        ],
        type: FHIRPrimitive(.relatedPerson),
        versioning: FHIRPrimitive(.versioned)
    )
    r.conditionalCreate = FHIRPrimitive(FHIRBool(true))
    r.conditionalUpdate = FHIRPrimitive(FHIRBool(true))
    r.conditionalDelete = FHIRPrimitive(.single)
    r.conditionalRead = FHIRPrimitive(.fullSupport)
    r.updateCreate = FHIRPrimitive(FHIRBool(true))
    r.searchInclude = [
        "RelatedPerson:patient",
    ].map { FHIRPrimitive(FHIRString($0)) }
    return r
}

private func serviceRequestResource() -> CapabilityStatementRestResource {
    var r = CapabilityStatementRestResource(
        documentation: FHIRPrimitive(FHIRString(
            "ServiceRequest resource. Supports CRUD, history, and search. " +
            "In Patient compartment: GET /Patient/:id/ServiceRequest (POST /_search). " +
            "Search: status, intent, priority, code, category, body-site, performer-type, " +
            "requisition, identifier, authored, occurrence, subject, patient, encounter, " +
            "requester, performer, based-on, replaces, specimen. " +
            ":not modifier on status, intent, priority, code, category. " +
            "_sort: ±authored (mapped to date), ±_lastUpdated, ±_id."
        )),
        interaction: baselineInteractions,
        readHistory: FHIRPrimitive(FHIRBool(true)),
        searchParam: [
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/ServiceRequest-status")),
                documentation: FHIRPrimitive(FHIRString("Token: active|on-hold|revoked|completed|entered-in-error|draft|unknown. Modifier: :not.")),
                name: FHIRPrimitive(FHIRString("status")),
                type: FHIRPrimitive(.token)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/ServiceRequest-intent")),
                documentation: FHIRPrimitive(FHIRString("Token: proposal|plan|directive|order|original-order|reflex-order|filler-order|instance-order|option. Modifier: :not.")),
                name: FHIRPrimitive(FHIRString("intent")),
                type: FHIRPrimitive(.token)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/ServiceRequest-priority")),
                documentation: FHIRPrimitive(FHIRString("Token: routine|urgent|asap|stat. Modifier: :not.")),
                name: FHIRPrimitive(FHIRString("priority")),
                type: FHIRPrimitive(.token)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/ServiceRequest-code")),
                documentation: FHIRPrimitive(FHIRString("Token OR on ServiceRequest.code codings. Modifier: :not.")),
                name: FHIRPrimitive(FHIRString("code")),
                type: FHIRPrimitive(.token)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/ServiceRequest-category")),
                documentation: FHIRPrimitive(FHIRString("Token OR on category codings. Modifier: :not.")),
                name: FHIRPrimitive(FHIRString("category")),
                type: FHIRPrimitive(.token)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/ServiceRequest-body-site")),
                documentation: FHIRPrimitive(FHIRString("Token OR on bodySite codings.")),
                name: FHIRPrimitive(FHIRString("body-site")),
                type: FHIRPrimitive(.token)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/ServiceRequest-performer-type")),
                documentation: FHIRPrimitive(FHIRString("Token OR on performerType codings.")),
                name: FHIRPrimitive(FHIRString("performer-type")),
                type: FHIRPrimitive(.token)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/ServiceRequest-requisition")),
                documentation: FHIRPrimitive(FHIRString("Token on requisition identifier.")),
                name: FHIRPrimitive(FHIRString("requisition")),
                type: FHIRPrimitive(.token)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/ServiceRequest-identifier")),
                documentation: FHIRPrimitive(FHIRString("Token search on identifier. Formats: code, system|code.")),
                name: FHIRPrimitive(FHIRString("identifier")),
                type: FHIRPrimitive(.token)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/ServiceRequest-authored")),
                documentation: FHIRPrimitive(FHIRString("Date search with prefixes: eq, lt, gt, le, ge, sa, eb.")),
                name: FHIRPrimitive(FHIRString("authored")),
                type: FHIRPrimitive(.date)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/ServiceRequest-occurrence")),
                documentation: FHIRPrimitive(FHIRString("Date search on occurrence[x] (dateTime or Period). Prefixes: eq, lt, gt, le, ge, sa, eb.")),
                name: FHIRPrimitive(FHIRString("occurrence")),
                type: FHIRPrimitive(.date)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/ServiceRequest-subject")),
                documentation: FHIRPrimitive(FHIRString("Reference to subject (any resource type).")),
                name: FHIRPrimitive(FHIRString("subject")),
                type: FHIRPrimitive(.reference)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/ServiceRequest-patient")),
                documentation: FHIRPrimitive(FHIRString("Reference to patient subject. Formats: Patient/id or bare id.")),
                name: FHIRPrimitive(FHIRString("patient")),
                type: FHIRPrimitive(.reference)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/ServiceRequest-encounter")),
                name: FHIRPrimitive(FHIRString("encounter")),
                type: FHIRPrimitive(.reference)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/ServiceRequest-requester")),
                name: FHIRPrimitive(FHIRString("requester")),
                type: FHIRPrimitive(.reference)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/ServiceRequest-performer")),
                name: FHIRPrimitive(FHIRString("performer")),
                type: FHIRPrimitive(.reference)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/ServiceRequest-based-on")),
                name: FHIRPrimitive(FHIRString("based-on")),
                type: FHIRPrimitive(.reference)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/ServiceRequest-replaces")),
                name: FHIRPrimitive(FHIRString("replaces")),
                type: FHIRPrimitive(.reference)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/ServiceRequest-specimen")),
                name: FHIRPrimitive(FHIRString("specimen")),
                type: FHIRPrimitive(.reference)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/ServiceRequest-instantiates-canonical")),
                documentation: FHIRPrimitive(FHIRString("ServiceRequest.instantiatesCanonical[]. URI match.")),
                name: FHIRPrimitive(FHIRString("instantiates-canonical")),
                type: FHIRPrimitive(.uri)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/ServiceRequest-instantiates-uri")),
                documentation: FHIRPrimitive(FHIRString("ServiceRequest.instantiatesUri[]. URI match.")),
                name: FHIRPrimitive(FHIRString("instantiates-uri")),
                type: FHIRPrimitive(.uri)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/ServiceRequest-order-detail")),
                documentation: FHIRPrimitive(FHIRString("ServiceRequest.orderDetail[].coding. Token: system|code. Modifier: :not.")),
                name: FHIRPrimitive(FHIRString("order-detail")),
                type: FHIRPrimitive(.token)
            ),
            CapabilityStatementRestResourceSearchParam(
                name: FHIRPrimitive(FHIRString("_id")),
                type: FHIRPrimitive(.token)
            ),
            CapabilityStatementRestResourceSearchParam(
                name: FHIRPrimitive(FHIRString("_lastUpdated")),
                type: FHIRPrimitive(.date)
            ),
        ],
        type: FHIRPrimitive(.serviceRequest),
        versioning: FHIRPrimitive(.versioned)
    )
    r.conditionalCreate = FHIRPrimitive(FHIRBool(true))
    r.conditionalUpdate = FHIRPrimitive(FHIRBool(true))
    r.conditionalDelete = FHIRPrimitive(.single)
    r.conditionalRead = FHIRPrimitive(.fullSupport)
    r.updateCreate = FHIRPrimitive(FHIRBool(true))
    r.searchInclude = [
        "ServiceRequest:patient", "ServiceRequest:subject",
        "ServiceRequest:encounter", "ServiceRequest:requester",
        "ServiceRequest:performer",
    ].map { FHIRPrimitive(FHIRString($0)) }
    return r
}

private func specimenResource() -> CapabilityStatementRestResource {
    var r = CapabilityStatementRestResource(
        documentation: FHIRPrimitive(FHIRString(
            "Specimen resource. Supports CRUD, history, and search. " +
            "In Patient compartment: GET /Patient/:id/Specimen (POST /_search). " +
            "Search: status, type, accession, identifier, bodysite, container, container-id, " +
            "collected, subject, patient, collector, parent. " +
            ":not modifier on status, type, accession, container, container-id. " +
            "_sort: ±collected (mapped to date), ±_lastUpdated, ±_id."
        )),
        interaction: baselineInteractions,
        readHistory: FHIRPrimitive(FHIRBool(true)),
        searchParam: [
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/Specimen-status")),
                documentation: FHIRPrimitive(FHIRString("Token: available|unavailable|unsatisfactory|entered-in-error. Modifier: :not.")),
                name: FHIRPrimitive(FHIRString("status")),
                type: FHIRPrimitive(.token)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/Specimen-type")),
                documentation: FHIRPrimitive(FHIRString("Token OR on Specimen.type codings. Modifier: :not.")),
                name: FHIRPrimitive(FHIRString("type")),
                type: FHIRPrimitive(.token)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/Specimen-accession")),
                documentation: FHIRPrimitive(FHIRString("Token on Specimen.accessionIdentifier. Modifier: :not.")),
                name: FHIRPrimitive(FHIRString("accession")),
                type: FHIRPrimitive(.token)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/Specimen-identifier")),
                documentation: FHIRPrimitive(FHIRString("Token search on identifier. Formats: code, system|code.")),
                name: FHIRPrimitive(FHIRString("identifier")),
                type: FHIRPrimitive(.token)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/Specimen-bodysite")),
                documentation: FHIRPrimitive(FHIRString("Token OR on collection.bodySite codings.")),
                name: FHIRPrimitive(FHIRString("bodysite")),
                type: FHIRPrimitive(.token)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/Specimen-container")),
                documentation: FHIRPrimitive(FHIRString("Token OR on container.type codings. Modifier: :not.")),
                name: FHIRPrimitive(FHIRString("container")),
                type: FHIRPrimitive(.token)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/Specimen-container-id")),
                documentation: FHIRPrimitive(FHIRString("Token OR on container.identifier. Modifier: :not.")),
                name: FHIRPrimitive(FHIRString("container-id")),
                type: FHIRPrimitive(.token)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/Specimen-collected")),
                documentation: FHIRPrimitive(FHIRString("Date search on collection.collected[x] (dateTime or Period). Prefixes: eq, lt, gt, le, ge, sa, eb.")),
                name: FHIRPrimitive(FHIRString("collected")),
                type: FHIRPrimitive(.date)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/Specimen-subject")),
                documentation: FHIRPrimitive(FHIRString("Reference to subject (any resource type).")),
                name: FHIRPrimitive(FHIRString("subject")),
                type: FHIRPrimitive(.reference)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/Specimen-patient")),
                documentation: FHIRPrimitive(FHIRString("Reference to patient subject. Formats: Patient/id or bare id.")),
                name: FHIRPrimitive(FHIRString("patient")),
                type: FHIRPrimitive(.reference)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/Specimen-collector")),
                documentation: FHIRPrimitive(FHIRString("Reference to collector (Practitioner/PractitionerRole).")),
                name: FHIRPrimitive(FHIRString("collector")),
                type: FHIRPrimitive(.reference)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/Specimen-parent")),
                documentation: FHIRPrimitive(FHIRString("Reference to parent Specimen.")),
                name: FHIRPrimitive(FHIRString("parent")),
                type: FHIRPrimitive(.reference)
            ),
            CapabilityStatementRestResourceSearchParam(
                name: FHIRPrimitive(FHIRString("_id")),
                type: FHIRPrimitive(.token)
            ),
            CapabilityStatementRestResourceSearchParam(
                name: FHIRPrimitive(FHIRString("_lastUpdated")),
                type: FHIRPrimitive(.date)
            ),
        ],
        type: FHIRPrimitive(.specimen),
        versioning: FHIRPrimitive(.versioned)
    )
    r.conditionalCreate = FHIRPrimitive(FHIRBool(true))
    r.conditionalUpdate = FHIRPrimitive(FHIRBool(true))
    r.conditionalDelete = FHIRPrimitive(.single)
    r.conditionalRead = FHIRPrimitive(.fullSupport)
    r.updateCreate = FHIRPrimitive(FHIRBool(true))
    r.searchInclude = [
        "Specimen:subject", "Specimen:patient", "Specimen:collector", "Specimen:parent",
    ].map { FHIRPrimitive(FHIRString($0)) }
    return r
}

private func carePlanResource() -> CapabilityStatementRestResource {
    var r = CapabilityStatementRestResource(
        documentation: FHIRPrimitive(FHIRString(
            "CarePlan resource. Supports CRUD, history, and search. " +
            "In Patient compartment: GET /Patient/:id/CarePlan (POST /_search). " +
            "Search: status, intent, category, identifier, activity-code, date (period), " +
            "subject, patient, encounter, care-team, condition, goal, based-on, part-of, replaces, performer, activity-reference. " +
            ":not modifier on status, intent, category. " +
            "_sort: ±date (mapped to CarePlan.period), ±_lastUpdated, ±_id."
        )),
        interaction: baselineInteractions,
        readHistory: FHIRPrimitive(FHIRBool(true)),
        searchParam: [
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/CarePlan-status")),
                documentation: FHIRPrimitive(FHIRString("Token: draft|active|on-hold|revoked|completed|entered-in-error|unknown. Modifier: :not.")),
                name: FHIRPrimitive(FHIRString("status")),
                type: FHIRPrimitive(.token)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/CarePlan-intent")),
                documentation: FHIRPrimitive(FHIRString("Token: proposal|plan|order|option. Modifier: :not.")),
                name: FHIRPrimitive(FHIRString("intent")),
                type: FHIRPrimitive(.token)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/CarePlan-category")),
                documentation: FHIRPrimitive(FHIRString("Token OR on CarePlan.category codings. Modifier: :not.")),
                name: FHIRPrimitive(FHIRString("category")),
                type: FHIRPrimitive(.token)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/clinical-identifier")),
                documentation: FHIRPrimitive(FHIRString("Token on CarePlan.identifier.")),
                name: FHIRPrimitive(FHIRString("identifier")),
                type: FHIRPrimitive(.token)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/CarePlan-activity-code")),
                documentation: FHIRPrimitive(FHIRString("Token on CarePlan.activity.detail.code codings.")),
                name: FHIRPrimitive(FHIRString("activity-code")),
                type: FHIRPrimitive(.token)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/clinical-date")),
                documentation: FHIRPrimitive(FHIRString("Date range on CarePlan.period. Prefixes: eq/lt/gt/le/ge/sa/eb.")),
                name: FHIRPrimitive(FHIRString("date")),
                type: FHIRPrimitive(.date)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/CarePlan-subject")),
                documentation: FHIRPrimitive(FHIRString("Reference to CarePlan.subject (any resource type).")),
                name: FHIRPrimitive(FHIRString("subject")),
                type: FHIRPrimitive(.reference)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/clinical-patient")),
                documentation: FHIRPrimitive(FHIRString("Reference to CarePlan.subject restricted to Patient.")),
                name: FHIRPrimitive(FHIRString("patient")),
                type: FHIRPrimitive(.reference)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/CarePlan-encounter")),
                documentation: FHIRPrimitive(FHIRString("Reference to CarePlan.encounter (Encounter).")),
                name: FHIRPrimitive(FHIRString("encounter")),
                type: FHIRPrimitive(.reference)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/CarePlan-care-team")),
                documentation: FHIRPrimitive(FHIRString("Reference to CarePlan.careTeam (CareTeam).")),
                name: FHIRPrimitive(FHIRString("care-team")),
                type: FHIRPrimitive(.reference)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/CarePlan-condition")),
                documentation: FHIRPrimitive(FHIRString("Reference to CarePlan.addresses (Condition).")),
                name: FHIRPrimitive(FHIRString("condition")),
                type: FHIRPrimitive(.reference)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/CarePlan-goal")),
                documentation: FHIRPrimitive(FHIRString("Reference to CarePlan.goal (Goal).")),
                name: FHIRPrimitive(FHIRString("goal")),
                type: FHIRPrimitive(.reference)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/CarePlan-based-on")),
                documentation: FHIRPrimitive(FHIRString("Reference to CarePlan.basedOn.")),
                name: FHIRPrimitive(FHIRString("based-on")),
                type: FHIRPrimitive(.reference)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/CarePlan-part-of")),
                documentation: FHIRPrimitive(FHIRString("Reference to CarePlan.partOf.")),
                name: FHIRPrimitive(FHIRString("part-of")),
                type: FHIRPrimitive(.reference)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/CarePlan-replaces")),
                documentation: FHIRPrimitive(FHIRString("Reference to CarePlan.replaces.")),
                name: FHIRPrimitive(FHIRString("replaces")),
                type: FHIRPrimitive(.reference)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/CarePlan-performer")),
                documentation: FHIRPrimitive(FHIRString("Reference to CarePlan.activity.detail.performer.")),
                name: FHIRPrimitive(FHIRString("performer")),
                type: FHIRPrimitive(.reference)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/CarePlan-activity-reference")),
                documentation: FHIRPrimitive(FHIRString("Reference to CarePlan.activity.reference.")),
                name: FHIRPrimitive(FHIRString("activity-reference")),
                type: FHIRPrimitive(.reference)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/CarePlan-activity-date")),
                documentation: FHIRPrimitive(FHIRString("CarePlan.activity[].detail.scheduledTiming/Period. Date range.")),
                name: FHIRPrimitive(FHIRString("activity-date")),
                type: FHIRPrimitive(.date)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/CarePlan-instantiates-canonical")),
                documentation: FHIRPrimitive(FHIRString("CarePlan.instantiatesCanonical[]. URI match.")),
                name: FHIRPrimitive(FHIRString("instantiates-canonical")),
                type: FHIRPrimitive(.uri)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/CarePlan-instantiates-uri")),
                documentation: FHIRPrimitive(FHIRString("CarePlan.instantiatesUri[]. URI match.")),
                name: FHIRPrimitive(FHIRString("instantiates-uri")),
                type: FHIRPrimitive(.uri)
            ),
            CapabilityStatementRestResourceSearchParam(
                name: FHIRPrimitive(FHIRString("_id")),
                type: FHIRPrimitive(.token)
            ),
            CapabilityStatementRestResourceSearchParam(
                name: FHIRPrimitive(FHIRString("_lastUpdated")),
                type: FHIRPrimitive(.date)
            ),
        ],
        type: FHIRPrimitive(.carePlan),
        versioning: FHIRPrimitive(.versioned)
    )
    r.conditionalCreate = FHIRPrimitive(FHIRBool(true))
    r.conditionalUpdate = FHIRPrimitive(FHIRBool(true))
    r.conditionalDelete = FHIRPrimitive(.single)
    r.conditionalRead = FHIRPrimitive(.fullSupport)
    r.updateCreate = FHIRPrimitive(FHIRBool(true))
    r.searchInclude = [
        "CarePlan:subject", "CarePlan:patient", "CarePlan:encounter",
        "CarePlan:care-team", "CarePlan:condition", "CarePlan:goal",
    ].map { FHIRPrimitive(FHIRString($0)) }
    return r
}

private func documentReferenceResource() -> CapabilityStatementRestResource {
    var r = CapabilityStatementRestResource(
        documentation: FHIRPrimitive(FHIRString(
            "DocumentReference resource. Supports CRUD, history, and search. " +
            "In Patient compartment: GET /Patient/:id/DocumentReference (POST /_search). " +
            "Search: status, type, category, identifier, security-label, facility, event, description, " +
            "date, period, subject, patient, author, encounter. " +
            ":not modifier on status, type, category, security-label. " +
            "_sort: ±date (mapped to DocumentReference.date), ±_lastUpdated, ±_id."
        )),
        interaction: baselineInteractions,
        readHistory: FHIRPrimitive(FHIRBool(true)),
        searchParam: [
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/DocumentReference-status")),
                documentation: FHIRPrimitive(FHIRString("Token: current|superseded|entered-in-error. Modifier: :not.")),
                name: FHIRPrimitive(FHIRString("status")),
                type: FHIRPrimitive(.token)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/DocumentReference-type")),
                documentation: FHIRPrimitive(FHIRString("Token OR on DocumentReference.type codings (LOINC). Modifier: :not.")),
                name: FHIRPrimitive(FHIRString("type")),
                type: FHIRPrimitive(.token)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/DocumentReference-category")),
                documentation: FHIRPrimitive(FHIRString("Token OR on DocumentReference.category codings. Modifier: :not.")),
                name: FHIRPrimitive(FHIRString("category")),
                type: FHIRPrimitive(.token)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/DocumentReference-identifier")),
                documentation: FHIRPrimitive(FHIRString("Token on masterIdentifier or identifier. Formats: code, system|code.")),
                name: FHIRPrimitive(FHIRString("identifier")),
                type: FHIRPrimitive(.token)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/DocumentReference-security-label")),
                documentation: FHIRPrimitive(FHIRString("Token OR on securityLabel codings. Modifier: :not.")),
                name: FHIRPrimitive(FHIRString("security-label")),
                type: FHIRPrimitive(.token)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/DocumentReference-facility")),
                documentation: FHIRPrimitive(FHIRString("Token OR on context.facilityType codings.")),
                name: FHIRPrimitive(FHIRString("facility")),
                type: FHIRPrimitive(.token)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/DocumentReference-event")),
                documentation: FHIRPrimitive(FHIRString("Token OR on context.event codings.")),
                name: FHIRPrimitive(FHIRString("event")),
                type: FHIRPrimitive(.token)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/DocumentReference-description")),
                documentation: FHIRPrimitive(FHIRString("String ILIKE on description_fhir.")),
                name: FHIRPrimitive(FHIRString("description")),
                type: FHIRPrimitive(.string)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/DocumentReference-date")),
                documentation: FHIRPrimitive(FHIRString("Date on DocumentReference.date (Instant). Prefixes: eq, lt, gt, le, ge, sa, eb.")),
                name: FHIRPrimitive(FHIRString("date")),
                type: FHIRPrimitive(.date)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/DocumentReference-period")),
                documentation: FHIRPrimitive(FHIRString("Date on context.period (Period). Prefixes: eq, lt, gt, le, ge, sa, eb.")),
                name: FHIRPrimitive(FHIRString("period")),
                type: FHIRPrimitive(.date)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/DocumentReference-subject")),
                documentation: FHIRPrimitive(FHIRString("Reference to subject (any resource type).")),
                name: FHIRPrimitive(FHIRString("subject")),
                type: FHIRPrimitive(.reference)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/DocumentReference-patient")),
                documentation: FHIRPrimitive(FHIRString("Reference to Patient subject. Formats: Patient/id or bare id.")),
                name: FHIRPrimitive(FHIRString("patient")),
                type: FHIRPrimitive(.reference)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/DocumentReference-author")),
                documentation: FHIRPrimitive(FHIRString("Reference to author (Practitioner, Organization, Patient, etc.).")),
                name: FHIRPrimitive(FHIRString("author")),
                type: FHIRPrimitive(.reference)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/DocumentReference-encounter")),
                documentation: FHIRPrimitive(FHIRString("Reference to context.encounter (Encounter).")),
                name: FHIRPrimitive(FHIRString("encounter")),
                type: FHIRPrimitive(.reference)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/DocumentReference-authenticator")),
                documentation: FHIRPrimitive(FHIRString("DocumentReference.authenticator. Reference: ResourceType/id or bare id.")),
                name: FHIRPrimitive(FHIRString("authenticator")),
                type: FHIRPrimitive(.reference)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/DocumentReference-custodian")),
                documentation: FHIRPrimitive(FHIRString("DocumentReference.custodian. Reference: Organization/id or bare id.")),
                name: FHIRPrimitive(FHIRString("custodian")),
                type: FHIRPrimitive(.reference)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/DocumentReference-location")),
                documentation: FHIRPrimitive(FHIRString("DocumentReference.content[].attachment.url. URI match.")),
                name: FHIRPrimitive(FHIRString("location")),
                type: FHIRPrimitive(.uri)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/DocumentReference-related")),
                documentation: FHIRPrimitive(FHIRString("DocumentReference.context.related[]. Reference: ResourceType/id or bare id.")),
                name: FHIRPrimitive(FHIRString("related")),
                type: FHIRPrimitive(.reference)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/DocumentReference-relatesto")),
                documentation: FHIRPrimitive(FHIRString("DocumentReference.relatesTo[].target. Reference: DocumentReference/id or bare id.")),
                name: FHIRPrimitive(FHIRString("relatesto")),
                type: FHIRPrimitive(.reference)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/DocumentReference-relation")),
                documentation: FHIRPrimitive(FHIRString("DocumentReference.relatesTo[].code. Token: system|code.")),
                name: FHIRPrimitive(FHIRString("relation")),
                type: FHIRPrimitive(.token)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/DocumentReference-relationship")),
                documentation: FHIRPrimitive(FHIRString("Composite: relatesto$relation.")),
                name: FHIRPrimitive(FHIRString("relationship")),
                type: FHIRPrimitive(.composite)
            ),
            CapabilityStatementRestResourceSearchParam(
                name: FHIRPrimitive(FHIRString("_id")),
                type: FHIRPrimitive(.token)
            ),
            CapabilityStatementRestResourceSearchParam(
                name: FHIRPrimitive(FHIRString("_lastUpdated")),
                type: FHIRPrimitive(.date)
            ),
        ],
        type: FHIRPrimitive(.documentReference),
        versioning: FHIRPrimitive(.versioned)
    )
    r.conditionalCreate = FHIRPrimitive(FHIRBool(true))
    r.conditionalUpdate = FHIRPrimitive(FHIRBool(true))
    r.conditionalDelete = FHIRPrimitive(.single)
    r.conditionalRead = FHIRPrimitive(.fullSupport)
    r.updateCreate = FHIRPrimitive(FHIRBool(true))
    r.searchInclude = [
        "DocumentReference:subject", "DocumentReference:patient",
        "DocumentReference:author", "DocumentReference:encounter",
    ].map { FHIRPrimitive(FHIRString($0)) }
    return r
}

private func goalResource() -> CapabilityStatementRestResource {
    var r = CapabilityStatementRestResource(
        documentation: FHIRPrimitive(FHIRString(
            "Goal resource. Supports CRUD, history, and search. " +
            "In Patient compartment: GET /Patient/:id/Goal (POST /_search). " +
            "Search: lifecycle-status, achievement-status, category, identifier, start-date, target-date, subject, patient. " +
            ":not modifier on lifecycle-status, category. " +
            "_sort: ±_lastUpdated, ±_id."
        )),
        interaction: baselineInteractions,
        readHistory: FHIRPrimitive(FHIRBool(true)),
        searchParam: [
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/Goal-lifecycle-status")),
                documentation: FHIRPrimitive(FHIRString("Token: proposed|planned|accepted|active|on-hold|completed|cancelled|entered-in-error|rejected. Modifier: :not.")),
                name: FHIRPrimitive(FHIRString("lifecycle-status")),
                type: FHIRPrimitive(.token)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/Goal-achievement-status")),
                documentation: FHIRPrimitive(FHIRString("Token OR on Goal.achievementStatus CodeableConcept. Formats: code, system|code.")),
                name: FHIRPrimitive(FHIRString("achievement-status")),
                type: FHIRPrimitive(.token)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/Goal-category")),
                documentation: FHIRPrimitive(FHIRString("Token OR on Goal.category CodeableConcept array. Modifier: :not.")),
                name: FHIRPrimitive(FHIRString("category")),
                type: FHIRPrimitive(.token)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/Goal-identifier")),
                documentation: FHIRPrimitive(FHIRString("Token on Goal.identifier. Formats: code, system|code, system|.")),
                name: FHIRPrimitive(FHIRString("identifier")),
                type: FHIRPrimitive(.token)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/Goal-start-date")),
                documentation: FHIRPrimitive(FHIRString("Date on Goal.start[x] (when StartDate). Prefixes: eq, lt, gt, le, ge, sa, eb.")),
                name: FHIRPrimitive(FHIRString("start-date")),
                type: FHIRPrimitive(.date)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/Goal-target-date")),
                documentation: FHIRPrimitive(FHIRString("Date on Goal.target.due[x] (when DueDate). Prefixes: eq, lt, gt, le, ge, sa, eb.")),
                name: FHIRPrimitive(FHIRString("target-date")),
                type: FHIRPrimitive(.date)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/Goal-subject")),
                documentation: FHIRPrimitive(FHIRString("Reference to Goal.subject (any resource type).")),
                name: FHIRPrimitive(FHIRString("subject")),
                type: FHIRPrimitive(.reference)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/Goal-patient")),
                documentation: FHIRPrimitive(FHIRString("Reference to Goal.subject restricted to Patient.")),
                name: FHIRPrimitive(FHIRString("patient")),
                type: FHIRPrimitive(.reference)
            ),
            CapabilityStatementRestResourceSearchParam(
                name: FHIRPrimitive(FHIRString("_id")),
                type: FHIRPrimitive(.token)
            ),
            CapabilityStatementRestResourceSearchParam(
                name: FHIRPrimitive(FHIRString("_lastUpdated")),
                type: FHIRPrimitive(.date)
            ),
        ],
        type: FHIRPrimitive(.goal),
        versioning: FHIRPrimitive(.versioned)
    )
    r.conditionalCreate = FHIRPrimitive(FHIRBool(true))
    r.conditionalUpdate = FHIRPrimitive(FHIRBool(true))
    r.conditionalDelete = FHIRPrimitive(.single)
    r.conditionalRead = FHIRPrimitive(.fullSupport)
    r.updateCreate = FHIRPrimitive(FHIRBool(true))
    r.searchInclude = [
        "Goal:subject", "Goal:patient",
    ].map { FHIRPrimitive(FHIRString($0)) }
    return r
}

private func medicationStatementResource() -> CapabilityStatementRestResource {
    var r = CapabilityStatementRestResource(
        documentation: FHIRPrimitive(FHIRString(
            "MedicationStatement resource. Supports CRUD, history, and search. " +
            "In Patient compartment: GET /Patient/:id/MedicationStatement (POST /_search). " +
            "Search: status, category, code, identifier, effective, subject, patient, context, source, medication, part-of. " +
            ":not modifier on status, category, code. " +
            "_sort: ±_lastUpdated, ±_id."
        )),
        interaction: baselineInteractions,
        readHistory: FHIRPrimitive(FHIRBool(true)),
        searchParam: [
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/MedicationStatement-status")),
                documentation: FHIRPrimitive(FHIRString("Token: active|completed|entered-in-error|intended|stopped|on-hold|unknown|not-taken. Modifier: :not.")),
                name: FHIRPrimitive(FHIRString("status")),
                type: FHIRPrimitive(.token)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/MedicationStatement-category")),
                documentation: FHIRPrimitive(FHIRString("Token OR on MedicationStatement.category CodeableConcept. Modifier: :not.")),
                name: FHIRPrimitive(FHIRString("category")),
                type: FHIRPrimitive(.token)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/medications-code")),
                documentation: FHIRPrimitive(FHIRString("Token on medication when CodeableConcept. Modifier: :not.")),
                name: FHIRPrimitive(FHIRString("code")),
                type: FHIRPrimitive(.token)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/MedicationStatement-identifier")),
                documentation: FHIRPrimitive(FHIRString("Token on MedicationStatement.identifier. Formats: code, system|code, system|.")),
                name: FHIRPrimitive(FHIRString("identifier")),
                type: FHIRPrimitive(.token)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/MedicationStatement-effective")),
                documentation: FHIRPrimitive(FHIRString("Date on effective[x] (dateTime or Period). Prefixes: eq, lt, gt, le, ge, sa, eb.")),
                name: FHIRPrimitive(FHIRString("effective")),
                type: FHIRPrimitive(.date)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/MedicationStatement-subject")),
                documentation: FHIRPrimitive(FHIRString("Reference to MedicationStatement.subject.")),
                name: FHIRPrimitive(FHIRString("subject")),
                type: FHIRPrimitive(.reference)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/medications-patient")),
                documentation: FHIRPrimitive(FHIRString("Reference to MedicationStatement.subject restricted to Patient.")),
                name: FHIRPrimitive(FHIRString("patient")),
                type: FHIRPrimitive(.reference)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/MedicationStatement-context")),
                documentation: FHIRPrimitive(FHIRString("Reference to MedicationStatement.context (Encounter).")),
                name: FHIRPrimitive(FHIRString("context")),
                type: FHIRPrimitive(.reference)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/MedicationStatement-source")),
                documentation: FHIRPrimitive(FHIRString("Reference to MedicationStatement.informationSource.")),
                name: FHIRPrimitive(FHIRString("source")),
                type: FHIRPrimitive(.reference)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/medications-medication")),
                documentation: FHIRPrimitive(FHIRString("Reference when medication is a Reference.")),
                name: FHIRPrimitive(FHIRString("medication")),
                type: FHIRPrimitive(.reference)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/MedicationStatement-part-of")),
                documentation: FHIRPrimitive(FHIRString("Reference to MedicationStatement.partOf.")),
                name: FHIRPrimitive(FHIRString("part-of")),
                type: FHIRPrimitive(.reference)
            ),
            CapabilityStatementRestResourceSearchParam(
                name: FHIRPrimitive(FHIRString("_id")),
                type: FHIRPrimitive(.token)
            ),
            CapabilityStatementRestResourceSearchParam(
                name: FHIRPrimitive(FHIRString("_lastUpdated")),
                type: FHIRPrimitive(.date)
            ),
        ],
        type: FHIRPrimitive(.medicationStatement),
        versioning: FHIRPrimitive(.versioned)
    )
    r.conditionalCreate = FHIRPrimitive(FHIRBool(true))
    r.conditionalUpdate = FHIRPrimitive(FHIRBool(true))
    r.conditionalDelete = FHIRPrimitive(.single)
    r.conditionalRead = FHIRPrimitive(.fullSupport)
    r.updateCreate = FHIRPrimitive(FHIRBool(true))
    r.searchInclude = [
        "MedicationStatement:subject", "MedicationStatement:patient",
        "MedicationStatement:context", "MedicationStatement:medication",
    ].map { FHIRPrimitive(FHIRString($0)) }
    return r
}

private func familyMemberHistoryResource() -> CapabilityStatementRestResource {
    var r = CapabilityStatementRestResource(
        documentation: FHIRPrimitive(FHIRString(
            "FamilyMemberHistory resource. Supports CRUD, history, and search. " +
            "In Patient compartment: GET /Patient/:id/FamilyMemberHistory (POST /_search). " +
            "Search: status, relationship, sex, code, identifier, date, patient. " +
            ":not modifier on status, relationship, sex, code. " +
            "_sort: ±_lastUpdated, ±_id."
        )),
        interaction: baselineInteractions,
        readHistory: FHIRPrimitive(FHIRBool(true)),
        searchParam: [
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/FamilyMemberHistory-status")),
                documentation: FHIRPrimitive(FHIRString("Token: partial|completed|entered-in-error|health-unknown. System: http://hl7.org/fhir/history-status. Modifier: :not.")),
                name: FHIRPrimitive(FHIRString("status")),
                type: FHIRPrimitive(.token)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/FamilyMemberHistory-relationship")),
                documentation: FHIRPrimitive(FHIRString("Token OR on FamilyMemberHistory.relationship CodeableConcept. Modifier: :not.")),
                name: FHIRPrimitive(FHIRString("relationship")),
                type: FHIRPrimitive(.token)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/FamilyMemberHistory-sex")),
                documentation: FHIRPrimitive(FHIRString("Token OR on FamilyMemberHistory.sex CodeableConcept. Modifier: :not.")),
                name: FHIRPrimitive(FHIRString("sex")),
                type: FHIRPrimitive(.token)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/FamilyMemberHistory-code")),
                documentation: FHIRPrimitive(FHIRString("Token on condition[].code. Modifier: :not.")),
                name: FHIRPrimitive(FHIRString("code")),
                type: FHIRPrimitive(.token)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/FamilyMemberHistory-identifier")),
                documentation: FHIRPrimitive(FHIRString("Token on FamilyMemberHistory.identifier. Formats: code, system|code, system|.")),
                name: FHIRPrimitive(FHIRString("identifier")),
                type: FHIRPrimitive(.token)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/FamilyMemberHistory-date")),
                documentation: FHIRPrimitive(FHIRString("Date when history was recorded. Prefixes: eq, lt, gt, le, ge, sa, eb.")),
                name: FHIRPrimitive(FHIRString("date")),
                type: FHIRPrimitive(.date)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/FamilyMemberHistory-patient")),
                documentation: FHIRPrimitive(FHIRString("Reference to FamilyMemberHistory.patient.")),
                name: FHIRPrimitive(FHIRString("patient")),
                type: FHIRPrimitive(.reference)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/FamilyMemberHistory-instantiates-canonical")),
                documentation: FHIRPrimitive(FHIRString("FamilyMemberHistory.instantiatesCanonical[]. URI match.")),
                name: FHIRPrimitive(FHIRString("instantiates-canonical")),
                type: FHIRPrimitive(.uri)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/FamilyMemberHistory-instantiates-uri")),
                documentation: FHIRPrimitive(FHIRString("FamilyMemberHistory.instantiatesUri[]. URI match.")),
                name: FHIRPrimitive(FHIRString("instantiates-uri")),
                type: FHIRPrimitive(.uri)
            ),
            CapabilityStatementRestResourceSearchParam(
                name: FHIRPrimitive(FHIRString("_id")),
                type: FHIRPrimitive(.token)
            ),
            CapabilityStatementRestResourceSearchParam(
                name: FHIRPrimitive(FHIRString("_lastUpdated")),
                type: FHIRPrimitive(.date)
            ),
        ],
        type: FHIRPrimitive(.familyMemberHistory),
        versioning: FHIRPrimitive(.versioned)
    )
    r.conditionalCreate = FHIRPrimitive(FHIRBool(true))
    r.conditionalUpdate = FHIRPrimitive(FHIRBool(true))
    r.conditionalDelete = FHIRPrimitive(.single)
    r.conditionalRead = FHIRPrimitive(.fullSupport)
    r.updateCreate = FHIRPrimitive(FHIRBool(true))
    r.searchInclude = [
        "FamilyMemberHistory:patient",
    ].map { FHIRPrimitive(FHIRString($0)) }
    return r
}

private func appointmentResource() -> CapabilityStatementRestResource {
    var r = CapabilityStatementRestResource(
        documentation: FHIRPrimitive(FHIRString(
            "Appointment resource. Supports CRUD, history, and search. " +
            "In Patient compartment: GET /Patient/:id/Appointment (POST /_search). " +
            "Search: patient, actor, practitioner, location, status, service-type, appointment-type, specialty, reason-code, service-category, part-status, identifier, date. " +
            ":not modifier on status, service-type, appointment-type, specialty, reason-code, service-category, part-status. " +
            "_sort: ±_lastUpdated, ±date, ±status, ±_id."
        )),
        interaction: baselineInteractions,
        readHistory: FHIRPrimitive(FHIRBool(true)),
        searchParam: [
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/Appointment-patient")),
                documentation: FHIRPrimitive(FHIRString("Reference to participant.actor where actor is a Patient.")),
                name: FHIRPrimitive(FHIRString("patient")),
                type: FHIRPrimitive(.reference)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/Appointment-actor")),
                documentation: FHIRPrimitive(FHIRString("Any participant.actor reference.")),
                name: FHIRPrimitive(FHIRString("actor")),
                type: FHIRPrimitive(.reference)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/Appointment-practitioner")),
                documentation: FHIRPrimitive(FHIRString("Reference to participant.actor where actor is a Practitioner.")),
                name: FHIRPrimitive(FHIRString("practitioner")),
                type: FHIRPrimitive(.reference)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/Appointment-location")),
                documentation: FHIRPrimitive(FHIRString("Reference to participant.actor where actor is a Location.")),
                name: FHIRPrimitive(FHIRString("location")),
                type: FHIRPrimitive(.reference)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/Appointment-status")),
                documentation: FHIRPrimitive(FHIRString("Token OR on Appointment.status. Modifier: :not.")),
                name: FHIRPrimitive(FHIRString("status")),
                type: FHIRPrimitive(.token)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/Appointment-service-type")),
                documentation: FHIRPrimitive(FHIRString("Token OR on Appointment.serviceType CodeableConcept. Modifier: :not.")),
                name: FHIRPrimitive(FHIRString("service-type")),
                type: FHIRPrimitive(.token)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/Appointment-appointment-type")),
                documentation: FHIRPrimitive(FHIRString("Token OR on Appointment.appointmentType CodeableConcept. Modifier: :not.")),
                name: FHIRPrimitive(FHIRString("appointment-type")),
                type: FHIRPrimitive(.token)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/Appointment-specialty")),
                documentation: FHIRPrimitive(FHIRString("Token OR on Appointment.specialty CodeableConcept. Modifier: :not.")),
                name: FHIRPrimitive(FHIRString("specialty")),
                type: FHIRPrimitive(.token)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/Appointment-reason-code")),
                documentation: FHIRPrimitive(FHIRString("Token OR on Appointment.reasonCode CodeableConcept. Modifier: :not.")),
                name: FHIRPrimitive(FHIRString("reason-code")),
                type: FHIRPrimitive(.token)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/Appointment-service-category")),
                documentation: FHIRPrimitive(FHIRString("Token OR on Appointment.serviceCategory CodeableConcept. Modifier: :not.")),
                name: FHIRPrimitive(FHIRString("service-category")),
                type: FHIRPrimitive(.token)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/Appointment-part-status")),
                documentation: FHIRPrimitive(FHIRString("Token OR on participant.status. Modifier: :not.")),
                name: FHIRPrimitive(FHIRString("part-status")),
                type: FHIRPrimitive(.token)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/Appointment-identifier")),
                documentation: FHIRPrimitive(FHIRString("Token on Appointment.identifier. Formats: code, system|code, system|.")),
                name: FHIRPrimitive(FHIRString("identifier")),
                type: FHIRPrimitive(.token)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/Appointment-date")),
                documentation: FHIRPrimitive(FHIRString("Date search on Appointment.start. Prefixes: eq, lt, gt, le, ge, sa, eb.")),
                name: FHIRPrimitive(FHIRString("date")),
                type: FHIRPrimitive(.date)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/Appointment-based-on")),
                documentation: FHIRPrimitive(FHIRString("Appointment.basedOn[]. Reference: ServiceRequest/id or bare id.")),
                name: FHIRPrimitive(FHIRString("based-on")),
                type: FHIRPrimitive(.reference)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/Appointment-reason-reference")),
                documentation: FHIRPrimitive(FHIRString("Appointment.reasonReference[]. Reference: ResourceType/id or bare id.")),
                name: FHIRPrimitive(FHIRString("reason-reference")),
                type: FHIRPrimitive(.reference)
            ),
            CapabilityStatementRestResourceSearchParam(
                name: FHIRPrimitive(FHIRString("_id")),
                type: FHIRPrimitive(.token)
            ),
            CapabilityStatementRestResourceSearchParam(
                name: FHIRPrimitive(FHIRString("_lastUpdated")),
                type: FHIRPrimitive(.date)
            ),
        ],
        type: FHIRPrimitive(.appointment),
        versioning: FHIRPrimitive(.versioned)
    )
    r.conditionalCreate = FHIRPrimitive(FHIRBool(true))
    r.conditionalUpdate = FHIRPrimitive(FHIRBool(true))
    r.conditionalDelete = FHIRPrimitive(.single)
    r.conditionalRead = FHIRPrimitive(.fullSupport)
    r.updateCreate = FHIRPrimitive(FHIRBool(true))
    r.searchInclude = [
        "Appointment:patient", "Appointment:practitioner", "Appointment:location", "Appointment:actor",
    ].map { FHIRPrimitive(FHIRString($0)) }
    return r
}

private func medicationAdministrationResource() -> CapabilityStatementRestResource {
    var r = CapabilityStatementRestResource(
        documentation: FHIRPrimitive(FHIRString(
            "MedicationAdministration resource. Supports CRUD, history, and search. " +
            "In Patient compartment: GET /Patient/:id/MedicationAdministration (POST /_search). " +
            "Search: subject, patient, status, code, identifier, reason-given, reason-not-given, " +
            "effective-time, context, request, performer, device, medication. " +
            ":not modifier on status, code, reason-given, reason-not-given. " +
            "_sort: ±_lastUpdated, ±date (effective-time), ±status, ±code, ±_id."
        )),
        interaction: baselineInteractions,
        readHistory: FHIRPrimitive(FHIRBool(true)),
        searchParam: [
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/MedicationAdministration-subject")),
                documentation: FHIRPrimitive(FHIRString("Reference to MedicationAdministration.subject.")),
                name: FHIRPrimitive(FHIRString("subject")),
                type: FHIRPrimitive(.reference)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/MedicationAdministration-patient")),
                documentation: FHIRPrimitive(FHIRString("Reference to subject where subject is a Patient. Used for compartment injection.")),
                name: FHIRPrimitive(FHIRString("patient")),
                type: FHIRPrimitive(.reference)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/MedicationAdministration-status")),
                documentation: FHIRPrimitive(FHIRString("Token OR on MedicationAdministration.status. Modifier: :not.")),
                name: FHIRPrimitive(FHIRString("status")),
                type: FHIRPrimitive(.token)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/MedicationAdministration-code")),
                documentation: FHIRPrimitive(FHIRString("Token OR on medication as CodeableConcept. Modifier: :not.")),
                name: FHIRPrimitive(FHIRString("code")),
                type: FHIRPrimitive(.token)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/MedicationAdministration-identifier")),
                documentation: FHIRPrimitive(FHIRString("Token on MedicationAdministration.identifier. Formats: code, system|code, system|.")),
                name: FHIRPrimitive(FHIRString("identifier")),
                type: FHIRPrimitive(.token)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/MedicationAdministration-reason-given")),
                documentation: FHIRPrimitive(FHIRString("Token OR on reasonCode. Modifier: :not.")),
                name: FHIRPrimitive(FHIRString("reason-given")),
                type: FHIRPrimitive(.token)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/MedicationAdministration-reason-not-given")),
                documentation: FHIRPrimitive(FHIRString("Token OR on statusReason. Modifier: :not.")),
                name: FHIRPrimitive(FHIRString("reason-not-given")),
                type: FHIRPrimitive(.token)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/MedicationAdministration-effective-time")),
                documentation: FHIRPrimitive(FHIRString("Date/period search on effective[x]. Prefixes: eq, lt, gt, le, ge, sa, eb.")),
                name: FHIRPrimitive(FHIRString("effective-time")),
                type: FHIRPrimitive(.date)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/MedicationAdministration-context")),
                documentation: FHIRPrimitive(FHIRString("Reference to MedicationAdministration.context (Encounter/EpisodeOfCare).")),
                name: FHIRPrimitive(FHIRString("context")),
                type: FHIRPrimitive(.reference)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/MedicationAdministration-request")),
                documentation: FHIRPrimitive(FHIRString("Reference to the MedicationRequest that authorized the administration.")),
                name: FHIRPrimitive(FHIRString("request")),
                type: FHIRPrimitive(.reference)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/MedicationAdministration-performer")),
                documentation: FHIRPrimitive(FHIRString("Reference to performer[].actor.")),
                name: FHIRPrimitive(FHIRString("performer")),
                type: FHIRPrimitive(.reference)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/MedicationAdministration-device")),
                documentation: FHIRPrimitive(FHIRString("Reference to device[].")),
                name: FHIRPrimitive(FHIRString("device")),
                type: FHIRPrimitive(.reference)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/MedicationAdministration-medication")),
                documentation: FHIRPrimitive(FHIRString("Reference to medication as Reference.")),
                name: FHIRPrimitive(FHIRString("medication")),
                type: FHIRPrimitive(.reference)
            ),
            CapabilityStatementRestResourceSearchParam(
                name: FHIRPrimitive(FHIRString("_id")),
                type: FHIRPrimitive(.token)
            ),
            CapabilityStatementRestResourceSearchParam(
                name: FHIRPrimitive(FHIRString("_lastUpdated")),
                type: FHIRPrimitive(.date)
            ),
        ],
        type: FHIRPrimitive(.medicationAdministration),
        versioning: FHIRPrimitive(.versioned)
    )
    r.conditionalCreate = FHIRPrimitive(FHIRBool(true))
    r.conditionalUpdate = FHIRPrimitive(FHIRBool(true))
    r.conditionalDelete = FHIRPrimitive(.single)
    r.conditionalRead = FHIRPrimitive(.fullSupport)
    r.updateCreate = FHIRPrimitive(FHIRBool(true))
    r.searchInclude = [
        "MedicationAdministration:subject", "MedicationAdministration:patient",
        "MedicationAdministration:context", "MedicationAdministration:request",
        "MedicationAdministration:performer", "MedicationAdministration:medication",
    ].map { FHIRPrimitive(FHIRString($0)) }
    return r
}
