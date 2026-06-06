import Foundation
import Hummingbird
import ModelsR4
import NIOCore

public func addMetadataRoutes(to router: Router<BasicRequestContext>) {
    // GET /metadata — FHIR CapabilityStatement
    router.get("metadata") { _, _ in
        let cs = buildCapabilityStatement()
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

private func buildCapabilityStatement() -> CapabilityStatement {
    CapabilityStatement(
        date: FHIRPrimitive(DateTime(stringLiteral: "2026-06-06")),
        fhirVersion: FHIRPrimitive(FHIRString("4.0.1")),
        format: [FHIRPrimitive(FHIRString("application/fhir+json"))],
        kind: FHIRPrimitive(.instance),
        name: FHIRPrimitive(FHIRString("SimingCapabilityStatement")),
        publisher: FHIRPrimitive(FHIRString("Siming 司命")),
        rest: [serverRest()],
        software: CapabilityStatementSoftware(
            name: FHIRPrimitive(FHIRString("Siming 司命")),
            version: FHIRPrimitive(FHIRString("0.9.0"))
        ),
        status: FHIRPrimitive(.active),
        title: FHIRPrimitive(FHIRString("Siming FHIR R4 Server")),
        version: FHIRPrimitive(FHIRString("0.9.0"))
    )
}

private func serverRest() -> CapabilityStatementRest {
    var rest = CapabilityStatementRest(
        mode: FHIRPrimitive(.server),
        resource: [patientResource(), observationResource(), encounterResource(), conditionResource(),
                   medicationResource(), medicationRequestResource(), allergyIntoleranceResource(),
                   procedureResource(), diagnosticReportResource(), immunizationResource(),
                   practitionerResource(), organizationResource(), locationResource(),
                   relatedPersonResource(), serviceRequestResource()]
    )
    rest.compartment = [
        FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/CompartmentDefinition/patient"))
    ]
    rest.interaction = [
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
            "Search: _sort=±_lastUpdated/±name/±family/±birthdate/±_id; _count (0–100; 0=count-only); _total (accurate|none); _elements (field filter); _summary (true|text|data|count|false); cursor pagination via _cursor. " +
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
                documentation: FHIRPrimitive(FHIRString("Controls whether Bundle.total is returned. Values: accurate (default), none.")),
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
            "Search: subject, code, status, category, date, identifier, encounter, performer, component-code, value-quantity; _sort=±_lastUpdated/±date/±_id; _total (accurate|none); _elements (field filter); _summary (true|text|data|count|false). " +
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
                documentation: FHIRPrimitive(FHIRString("Controls whether Bundle.total is returned. Values: accurate (default), none.")),
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
            "Search: subject, patient, status, class, type, date, identifier; _sort=±_lastUpdated/±date/±_id; _total (accurate|none); _elements (field filter); _summary (true|text|data|count|false). " +
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
            "Search: subject, patient, encounter, clinical-status, verification-status, category, code, identifier, onset-date, abatement-date, recorded-date; _sort=±_lastUpdated/±date(onset)/±_id; _total (accurate|none); _elements (field filter); _summary (true|text|data|count|false). " +
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
            "Search: subject, patient, status, intent, category, code, priority, identifier, authoredon, encounter, requester; _sort=±_lastUpdated/±authoredon/±_id; _total (accurate|none); _elements (field filter); _summary (true|text|data|count|false). " +
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
            "Search: patient, clinical-status, verification-status, type, category, criticality, code, identifier, date, manifestation, severity, route, last-date, onset; _sort=±_lastUpdated/±date/±_id; _total (accurate|none); _elements (field filter); _summary (true|text|data|count|false). " +
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
            "Search: subject, patient, encounter, performer, status, code, category, identifier, date; _sort=±_lastUpdated/±date/±_id; _total (accurate|none); _elements (field filter); _summary (true|text|data|count|false). " +
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
            "Search: subject, patient, encounter, performer, status, code, category, identifier, date, issued; _sort=±_lastUpdated/±date/±_id; _total (accurate|none); _elements (field filter); _summary (true|text|data|count|false). " +
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
            "Search: patient, status, vaccine-code, identifier, date, performer, lot-number; _sort=±_lastUpdated/±date/±_id; _total (accurate|none); _elements (field filter); _summary (true|text|data|count|false). " +
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
    r.searchInclude = [
        "ServiceRequest:patient", "ServiceRequest:subject",
        "ServiceRequest:encounter", "ServiceRequest:requester",
        "ServiceRequest:performer",
    ].map { FHIRPrimitive(FHIRString($0)) }
    return r
}
