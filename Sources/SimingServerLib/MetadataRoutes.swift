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
                   medicationRequestResource(), allergyIntoleranceResource()]
    )
    rest.compartment = [
        FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/CompartmentDefinition/patient"))
    ]
    rest.interaction = [
        CapabilityStatementRestInteraction(code: FHIRPrimitive(.historySystem)),
    ]
    rest.documentation = FHIRPrimitive(FHIRString(
        "Compartments: GET /Patient/:id/{Observation,Encounter,Condition,MedicationRequest,AllergyIntolerance} " +
        "and POST /Patient/:id/{Observation,Encounter,Condition,MedicationRequest,AllergyIntolerance}/_search."
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
    return r
}

private func conditionResource() -> CapabilityStatementRestResource {
    var r = CapabilityStatementRestResource(
        documentation: FHIRPrimitive(FHIRString(
            "Condition resource. " +
            "Supports read, vread, create (conditional via If-None-Exist), update (conditional via PUT /Condition?<search>), delete, history-instance, and search (GET and POST /_search). " +
            "Search: subject, patient, clinical-status, verification-status, category, code, identifier, onset-date, abatement-date, recorded-date; _sort=±_lastUpdated/±date(onset)/±_id; _total (accurate|none); _elements (field filter); _summary (true|text|data|count|false). " +
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
    return r
}

private func allergyIntoleranceResource() -> CapabilityStatementRestResource {
    var r = CapabilityStatementRestResource(
        documentation: FHIRPrimitive(FHIRString(
            "AllergyIntolerance resource. " +
            "Supports read, vread, create (conditional via If-None-Exist), update (conditional via PUT /AllergyIntolerance?<search>), delete, history-instance, and search (GET and POST /_search). " +
            "Search: patient, clinical-status, verification-status, type, category, criticality, code, identifier, date; _sort=±_lastUpdated/±date/±_id; _total (accurate|none); _elements (field filter); _summary (true|text|data|count|false). " +
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
    return r
}
