import Foundation
import Hummingbird
import NIOCore

// ── Supported resource types (server capability — order preserved in CS) ──────

private let supportedResourceTypes: [String] = [
    "Patient", "Observation", "Encounter", "Condition",
    "Medication", "MedicationRequest", "AllergyIntolerance",
    "Procedure", "DiagnosticReport", "Immunization",
    "Practitioner", "Organization", "Location",
    "RelatedPerson", "ServiceRequest", "Specimen",
    "DocumentReference", "CarePlan", "Goal",
    "MedicationStatement", "FamilyMemberHistory",
    "Appointment", "MedicationAdministration",
]

// ── Route registration ────────────────────────────────────────────────────────

public func addMetadataRoutes(
    to router: Router<BasicRequestContext>,
    smartConfig: SmartConfiguration? = nil,
    packagesDir: String = ProcessInfo.processInfo.environment["PACKAGES_DIR"] ?? "packages"
) {
    let igData = loadIG(packagesDir: packagesDir, resourceTypes: supportedResourceTypes)
    let csData = buildCapabilityStatementJSON(smartConfig: smartConfig, igData: igData)

    router.get("metadata") { _, _ in
        var headers = HTTPFields()
        headers[.contentType] = "application/fhir+json"
        return Response(
            status: .ok,
            headers: headers,
            body: ResponseBody(byteBuffer: ByteBuffer(bytes: csData))
        )
    }
}

// ── CapabilityStatement JSON builder ─────────────────────────────────────────

private let serverVersion = "0.92.0"

private func buildCapabilityStatementJSON(
    smartConfig: SmartConfiguration?,
    igData: IGData
) -> Data {
    var cs: [String: Any] = [
        "resourceType": "CapabilityStatement",
        "id": "siming",
        "status": "active",
        "kind": "instance",
        "date": isoDate(),
        "name": "SimingCapabilityStatement",
        "title": "Siming FHIR R4 Server",
        "publisher": "Siming 司命",
        "version": serverVersion,
        "fhirVersion": "4.0.1",
        "format": ["application/fhir+json"],
        "patchFormat": ["application/json-patch+json"],
        "instantiates": ["http://hl7.org/fhir/CapabilityStatement/base"],
        "software": [
            "name": "Siming 司命",
            "version": serverVersion,
        ],
        "implementation": [
            "description": "Siming FHIR R4 Server",
        ],
        "rest": [buildRest(smartConfig: smartConfig, igData: igData)],
    ]

    if !igData.implementationGuides.isEmpty {
        cs["implementationGuide"] = igData.implementationGuides
    }

    return (try? JSONSerialization.data(withJSONObject: cs, options: .sortedKeys)) ?? Data()
}

private func isoDate() -> String {
    let f = DateFormatter()
    f.dateFormat = "yyyy-MM-dd"
    f.timeZone = TimeZone(identifier: "UTC")
    return f.string(from: Date())
}

// ── REST section ──────────────────────────────────────────────────────────────

private func buildRest(smartConfig: SmartConfiguration?, igData: IGData) -> [String: Any] {
    var rest: [String: Any] = [
        "mode": "server",
        "resource": supportedResourceTypes.map { buildResource(type: $0, igData: igData) },
        "interaction": [
            ["code": "transaction"],
            ["code": "history-system"],
        ],
        "compartment": ["http://hl7.org/fhir/CompartmentDefinition/patient"],
        "searchParam": globalSearchParams(),
    ]

    if smartConfig != nil {
        rest["security"] = [
            "cors": true,
            "description": "SMART App Launch Framework",
            "service": [[
                "coding": [[
                    "system": "http://terminology.hl7.org/CodeSystem/restful-security-service",
                    "code": "SMART-on-FHIR",
                    "display": "SMART-on-FHIR",
                ]],
            ]],
        ]
    }

    return rest
}

private func globalSearchParams() -> [[String: Any]] {
    [
        ["name": "_id", "type": "token",
         "definition": "http://hl7.org/fhir/SearchParameter/Resource-id",
         "documentation": "Filter by resource logical id. Supports comma-separated OR."],
        ["name": "_lastUpdated", "type": "date",
         "definition": "http://hl7.org/fhir/SearchParameter/Resource-lastUpdated",
         "documentation": "Filter by last write time. Supports date prefixes eq/lt/gt/le/ge/sa/eb/ap."],
        ["name": "_elements", "type": "string",
         "documentation": "Field projection — return only named top-level elements. SUBSETTED tag added to meta."],
        ["name": "_summary", "type": "token",
         "documentation": "Summary mode: true|text|data|count|false."],
        ["name": "_tag", "type": "token",
         "definition": "http://hl7.org/fhir/SearchParameter/Resource-tag",
         "documentation": "Filter by meta.tag. Supports :not and comma-separated OR."],
        ["name": "_security", "type": "token",
         "definition": "http://hl7.org/fhir/SearchParameter/Resource-security",
         "documentation": "Filter by meta.security. Supports :not and comma-separated OR."],
        ["name": "_profile", "type": "uri",
         "definition": "http://hl7.org/fhir/SearchParameter/Resource-profile",
         "documentation": "Filter by meta.profile canonical URL."],
        ["name": "_source", "type": "uri",
         "definition": "http://hl7.org/fhir/SearchParameter/Resource-source",
         "documentation": "Filter by meta.source URI."],
    ]
}

// ── Per-resource builder ──────────────────────────────────────────────────────

private nonisolated(unsafe) let baselineInteractions: [[String: Any]] = [
    ["code": "read"], ["code": "vread"], ["code": "create"],
    ["code": "update"], ["code": "patch"], ["code": "delete"],
    ["code": "history-instance"], ["code": "history-type"], ["code": "search-type"],
]

private func buildResource(type resourceType: String, igData: IGData) -> [String: Any] {
    let params = igData.searchParams[resourceType] ?? []

    // searchInclude: reference-type params on this resource
    let includes: [String] = params
        .filter { $0.type == "reference" }
        .map { "\(resourceType):\($0.code)" }

    // searchRevInclude: other resources' reference params whose targets include this type
    let revIncludes: [String] = supportedResourceTypes
        .filter { $0 != resourceType }
        .flatMap { other -> [String] in
            (igData.searchParams[other] ?? [])
                .filter { $0.type == "reference" && $0.targets.contains(resourceType) }
                .map { "\(other):\($0.code)" }
        }
        .sorted()

    let searchParams: [[String: Any]] = params.map { p in
        var sp: [String: Any] = ["name": p.code, "type": p.type]
        if let url = p.url { sp["definition"] = url }
        return sp
    }

    var r: [String: Any] = [
        "type": resourceType,
        "interaction": baselineInteractions,
        "versioning": "versioned",
        "readHistory": true,
        "updateCreate": true,
        "conditionalCreate": true,
        "conditionalRead": "full-support",
        "conditionalUpdate": true,
        "conditionalDelete": "single",
    ]

    let profileURLs = igData.profiles[resourceType] ?? []
    if profileURLs.count == 1 {
        r["profile"] = profileURLs[0]
    } else if profileURLs.count > 1 {
        r["supportedProfile"] = profileURLs
    }
    if !searchParams.isEmpty { r["searchParam"] = searchParams }
    if !includes.isEmpty    { r["searchInclude"] = includes }
    if !revIncludes.isEmpty { r["searchRevInclude"] = revIncludes }

    return r
}
