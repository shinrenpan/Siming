import Foundation
import Hummingbird
import ModelsR4
import NIOCore

func addMetadataRoutes(to router: Router<BasicRequestContext>) {
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
        date: FHIRPrimitive(DateTime(stringLiteral: "2026-06-04")),
        fhirVersion: FHIRPrimitive(FHIRString("4.0.1")),
        format: [FHIRPrimitive(FHIRString("application/fhir+json"))],
        kind: FHIRPrimitive(.instance),
        name: FHIRPrimitive(FHIRString("SimingCapabilityStatement")),
        publisher: FHIRPrimitive(FHIRString("Siming 司命")),
        rest: [serverRest()],
        software: CapabilityStatementSoftware(
            name: FHIRPrimitive(FHIRString("Siming 司命")),
            version: FHIRPrimitive(FHIRString("0.1.0"))
        ),
        status: FHIRPrimitive(.active),
        title: FHIRPrimitive(FHIRString("Siming FHIR R4 Server")),
        version: FHIRPrimitive(FHIRString("0.1.0"))
    )
}

private func serverRest() -> CapabilityStatementRest {
    var rest = CapabilityStatementRest(
        mode: FHIRPrimitive(.server),
        resource: [patientResource(), observationResource()]
    )
    rest.compartment = [
        FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/CompartmentDefinition/patient"))
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
    CapabilityStatementRestResourceInteraction(code: FHIRPrimitive(.searchType)),
]

private func patientResource() -> CapabilityStatementRestResource {
    var r = CapabilityStatementRestResource(
        documentation: FHIRPrimitive(FHIRString(
            "History-preserving Patient resource. " +
            "Supports read, vread, create (conditional via If-None-Exist), update (conditional via PUT /Patient?<search>), delete, history-instance, and search (GET and POST /_search). " +
            "Search supports _sort=±_lastUpdated/±name/±family/±birthdate, _count (0–100; 0=count-only), _total (accurate|none), and cursor-based pagination via _cursor. " +
            "Compartment: GET /Patient/:id/Observation returns Observations scoped to that patient."
        )),
        interaction: baselineInteractions,
        readHistory: FHIRPrimitive(FHIRBool(true)),
        searchParam: [
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/Patient-name")),
                documentation: FHIRPrimitive(FHIRString("Starts-with match across all name fields (family, given, text). Modifiers: :contains, :exact.")),
                name: FHIRPrimitive(FHIRString("name")),
                type: FHIRPrimitive(.string)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/Patient-family")),
                documentation: FHIRPrimitive(FHIRString("Starts-with on family name. Modifiers: :contains, :exact.")),
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
    return r
}

private func observationResource() -> CapabilityStatementRestResource {
    var r = CapabilityStatementRestResource(
        documentation: FHIRPrimitive(FHIRString(
            "Observation resource. " +
            "Supports read, vread, create (conditional via If-None-Exist), update (conditional via PUT /Observation?<search>), delete, history-instance, and search (GET and POST /_search). " +
            "Search supports subject, code, status, category, date, identifier, encounter, performer, component-code, value-quantity. " +
            "_sort supports ±_lastUpdated and ±date. _total: accurate (default) or none."
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
    return r
}
