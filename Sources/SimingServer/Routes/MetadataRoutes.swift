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
    CapabilityStatementRest(
        mode: FHIRPrimitive(.server),
        resource: [patientResource(), observationResource()]
    )
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
    CapabilityStatementRestResource(
        documentation: FHIRPrimitive(FHIRString(
            "History-preserving Patient resource. " +
            "Supports read, vread, create, update, delete, history-instance, and search. " +
            "Search supports _sort=±_lastUpdated, _count (1–100), and cursor-based pagination via _cursor."
        )),
        interaction: baselineInteractions,
        readHistory: FHIRPrimitive(FHIRBool(true)),
        searchParam: [
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/Patient-name")),
                documentation: FHIRPrimitive(FHIRString("Case-insensitive substring match across all name fields.")),
                name: FHIRPrimitive(FHIRString("name")),
                type: FHIRPrimitive(.string)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/Patient-identifier")),
                documentation: FHIRPrimitive(FHIRString("Token search. Formats: code, system|code, |code (null system).")),
                name: FHIRPrimitive(FHIRString("identifier")),
                type: FHIRPrimitive(.token)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/Patient-birthdate")),
                documentation: FHIRPrimitive(FHIRString("Date search with prefixes: eq (default), lt, gt, le, ge. Partial dates supported.")),
                name: FHIRPrimitive(FHIRString("birthdate")),
                type: FHIRPrimitive(.date)
            ),
        ],
        type: FHIRPrimitive(.patient),
        versioning: FHIRPrimitive(.versioned)
    )
}

private func observationResource() -> CapabilityStatementRestResource {
    CapabilityStatementRestResource(
        documentation: FHIRPrimitive(FHIRString(
            "Observation resource. " +
            "Supports read, vread, create, update, delete, history-instance, and search. " +
            "Search supports subject, code, status, category, and date."
        )),
        interaction: baselineInteractions,
        readHistory: FHIRPrimitive(FHIRBool(true)),
        searchParam: [
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/Observation-subject")),
                documentation: FHIRPrimitive(FHIRString("Reference to Patient or Group. Formats: Patient/id or bare id.")),
                name: FHIRPrimitive(FHIRString("subject")),
                type: FHIRPrimitive(.reference)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/Observation-code")),
                documentation: FHIRPrimitive(FHIRString("Token search on Observation.code. Formats: code, system|code.")),
                name: FHIRPrimitive(FHIRString("code")),
                type: FHIRPrimitive(.token)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/Observation-status")),
                documentation: FHIRPrimitive(FHIRString("Token search on Observation.status (registered|preliminary|final|amended|corrected|cancelled|entered-in-error|unknown).")),
                name: FHIRPrimitive(FHIRString("status")),
                type: FHIRPrimitive(.token)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/Observation-category")),
                documentation: FHIRPrimitive(FHIRString("Token search on Observation.category. Formats: code, system|code.")),
                name: FHIRPrimitive(FHIRString("category")),
                type: FHIRPrimitive(.token)
            ),
            CapabilityStatementRestResourceSearchParam(
                definition: FHIRPrimitive(Canonical(stringLiteral: "http://hl7.org/fhir/SearchParameter/Observation-date")),
                documentation: FHIRPrimitive(FHIRString("Date search with prefixes: eq (default), lt, gt, le, ge.")),
                name: FHIRPrimitive(FHIRString("date")),
                type: FHIRPrimitive(.date)
            ),
        ],
        type: FHIRPrimitive(.observation),
        versioning: FHIRPrimitive(.versioned)
    )
}
