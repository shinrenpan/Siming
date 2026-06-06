import Foundation

// Shared formatter — ISO8601DateFormatter is expensive to construct.
// nonisolated(unsafe): initialized once, read-only after that.
nonisolated(unsafe) private let iso8601: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return f
}()

// RFC 7231 HTTP-date formatter for Last-Modified header.
nonisolated(unsafe) private let httpDateFormatter: DateFormatter = {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.timeZone = TimeZone(abbreviation: "GMT")
    f.dateFormat = "EEE, dd MMM yyyy HH:mm:ss 'GMT'"
    return f
}()

/// Formats a Date as an RFC 7231 HTTP-date string for use in `Last-Modified` headers.
public func httpDate(_ date: Date) -> String {
    httpDateFormatter.string(from: date)
}

/// Parses an RFC 7231 HTTP-date string from an `If-Modified-Since` header value.
/// Returns nil if the string cannot be parsed.
public func parseHTTPDate(_ value: String) -> Date? {
    httpDateFormatter.date(from: value.trimmingCharacters(in: .whitespaces))
}

/// A FHIR resource row ready for wire: raw JSON bytes with meta already injected.
public struct RawEntry: Sendable {
    public let id: String
    public let versionId: Int64
    public let lastUpdated: Date
    public let jsonWithMeta: Data
}

/// Injects FHIR meta (versionId + lastUpdated) into stored compact JSON.
///
/// Stored content is produced by JSONEncoder (compact, no trailing whitespace,
/// ends with '}'). Meta is absent because it is stripped on write.
/// Injection appends before the final '}' — O(n) single copy, zero parse.
public func injectMeta(into content: String, versionId: Int64, lastUpdated: Date) -> Data {
    let ts = iso8601.string(from: lastUpdated)
    let suffix = ",\"meta\":{\"versionId\":\"\(versionId)\",\"lastUpdated\":\"\(ts)\"}"
    var out = Data()
    out.reserveCapacity(content.utf8.count + suffix.utf8.count + 1)
    out.append(contentsOf: content.utf8.dropLast())   // drop trailing '}'
    out.append(contentsOf: suffix.utf8)
    out.append(UInt8(ascii: "}"))
    return out
}

/// Builds a FHIR searchset Bundle as raw bytes — no FHIRModels types involved.
///
/// Each entry's `json` field is already complete JSON (resource + meta injected).
/// It is embedded directly without re-parsing.
public func buildBundleJSON(
    entries: [(fullUrl: String, json: Data)],
    includeEntries: [(fullUrl: String, json: Data)] = [],
    total: Int?,
    selfURL: String,
    nextURL: String?
) -> Data {
    let entryCapacity = (entries + includeEntries).reduce(0) { $0 + $1.json.count + 80 }
    var out = Data()
    out.reserveCapacity(300 + entryCapacity)

    func s(_ string: String) { out.append(contentsOf: string.utf8) }

    if let total {
        s("{\"resourceType\":\"Bundle\",\"type\":\"searchset\",\"total\":\(total)")
    } else {
        s("{\"resourceType\":\"Bundle\",\"type\":\"searchset\"")
    }
    s(",\"link\":[{\"relation\":\"self\",\"url\":\"\(escapeJSON(selfURL))\"}")
    if let next = nextURL {
        s(",{\"relation\":\"next\",\"url\":\"\(escapeJSON(next))\"}")
    }
    s("]")

    if !entries.isEmpty || !includeEntries.isEmpty {
        s(",\"entry\":[")
        var first = true
        for entry in entries {
            if !first { s(",") }; first = false
            s("{\"fullUrl\":\"\(escapeJSON(entry.fullUrl))\",\"resource\":")
            out.append(entry.json)
            s(",\"search\":{\"mode\":\"match\"}}")
        }
        for entry in includeEntries {
            if !first { s(",") }; first = false
            s("{\"fullUrl\":\"\(escapeJSON(entry.fullUrl))\",\"resource\":")
            out.append(entry.json)
            s(",\"search\":{\"mode\":\"include\"}}")
        }
        s("]")
    }

    s("}")
    return out
}

/// One version entry for a FHIR `_history` Bundle.
public struct HistoryRawEntry: Sendable {
    public let resourceType: String  // e.g. "Patient", "Observation"
    public let id: String            // resource logical id
    public let versionId: Int64
    public let lastUpdated: Date
    public let jsonData: Data?       // nil for delete markers
    public let deleted: Bool

    public init(resourceType: String, id: String, versionId: Int64, lastUpdated: Date, jsonData: Data?, deleted: Bool) {
        self.resourceType = resourceType
        self.id = id
        self.versionId = versionId
        self.lastUpdated = lastUpdated
        self.jsonData = jsonData
        self.deleted = deleted
    }
}

/// Builds a FHIR `_history` Bundle as raw bytes.
/// Works for instance, type-level, and system-level history — uses `entry.resourceType`/`entry.id` per entry.
///
/// - Parameters:
///   - entries: Versions ordered newest-first. `jsonData` is nil for delete-marker versions.
///   - baseURL: Server base URL (no trailing slash), e.g. "http://localhost:8080"
public func buildHistoryBundleJSON(
    entries: [HistoryRawEntry],
    baseURL: String
) -> Data {
    var out = Data()
    out.reserveCapacity(512 + entries.reduce(0) { $0 + ($1.jsonData?.count ?? 0) + 200 })

    func s(_ string: String) { out.append(contentsOf: string.utf8) }

    s("{\"resourceType\":\"Bundle\",\"type\":\"history\",\"total\":\(entries.count)")
    s(",\"entry\":[")

    for (i, entry) in entries.enumerated() {
        if i > 0 { s(",") }
        let rt = entry.resourceType
        let fullUrl = "\(baseURL)/\(rt)/\(entry.id)/_history/\(entry.versionId)"
        let ts = iso8601.string(from: entry.lastUpdated)

        s("{\"fullUrl\":\"\(escapeJSON(fullUrl))\"")

        if let data = entry.jsonData {
            s(",\"resource\":")
            out.append(data)
        }

        // request element: infer method from version and deleted flag
        let method: String
        let requestUrl: String
        if entry.deleted {
            method = "DELETE"
            requestUrl = "\(rt)/\(entry.id)"
        } else if entry.versionId == 1 {
            method = "POST"
            requestUrl = rt
        } else {
            method = "PUT"
            requestUrl = "\(rt)/\(entry.id)"
        }
        s(",\"request\":{\"method\":\"\(method)\",\"url\":\"\(escapeJSON(requestUrl))\"}")

        // response element
        if entry.deleted {
            s(",\"response\":{\"status\":\"204 No Content\"}")
        } else if entry.versionId == 1 {
            s(",\"response\":{\"status\":\"201 Created\",\"etag\":\"W/\\\"\(entry.versionId)\\\"\",\"lastModified\":\"\(ts)\"}")
        } else {
            s(",\"response\":{\"status\":\"200 OK\",\"etag\":\"W/\\\"\(entry.versionId)\\\"\",\"lastModified\":\"\(ts)\"}")
        }

        s("}")
    }

    s("]}")
    return out
}

/// FHIR R4 §3.3.3 `_summary` parameter values.
public enum SummaryMode: String, Sendable {
    case `true`  = "true"
    case text    = "text"
    case data    = "data"
    case count   = "count"
    case `false` = "false"
}

/// Patient Σ-marked elements per FHIR R4 §10.1 (excluding mandatory id/meta/resourceType).
public let patientSummaryFields: Set<String> = [
    "identifier", "active", "name", "telecom", "gender",
    "birthDate", "deceasedBoolean", "deceasedDateTime",
    "address", "managingOrganization", "link",
]

/// Encounter Σ-marked elements per FHIR R4 §11.14 (excluding mandatory id/meta/resourceType).
public let encounterSummaryFields: Set<String> = [
    "identifier", "status", "class", "type", "serviceType", "priority",
    "subject", "episodeOfCare", "basedOn", "participant", "appointment",
    "period", "length", "reasonCode", "reasonReference",
    "hospitalization", "location", "serviceProvider", "partOf",
]

/// Condition Σ-marked elements per FHIR R4 §9.2 (excluding mandatory id/meta/resourceType).
public let conditionSummaryFields: Set<String> = [
    "identifier", "clinicalStatus", "verificationStatus", "category",
    "severity", "code", "bodySite", "subject", "encounter",
    "onsetDateTime", "onsetAge", "onsetPeriod", "onsetRange", "onsetString",
    "abatementDateTime", "abatementAge", "abatementPeriod", "abatementRange", "abatementString",
    "recordedDate", "recorder", "asserter", "stage", "evidence", "note",
]

/// Observation Σ-marked elements per FHIR R4 §11.1 (excluding mandatory id/meta/resourceType).
public let observationSummaryFields: Set<String> = [
    "identifier", "basedOn", "partOf", "status", "category", "code",
    "subject", "focus", "encounter",
    "effectiveDateTime", "effectivePeriod", "effectiveTiming", "effectiveInstant",
    "issued", "performer",
    "valueQuantity", "valueCodeableConcept", "valueString", "valueBoolean",
    "valueInteger", "valueRange", "valueRatio", "valueSampledData",
    "valueTime", "valueDateTime", "valuePeriod",
    "dataAbsentReason", "interpretation", "hasMember", "derivedFrom", "component",
]

/// MedicationRequest Σ-marked elements per FHIR R4.
public let medicationRequestSummaryFields: Set<String> = [
    "identifier", "status", "intent", "category", "priority",
    "medicationCodeableConcept", "medicationReference",
    "subject", "encounter", "supportingInformation",
    "authoredOn", "requester", "performer", "performerType",
    "recorder", "reasonCode", "reasonReference",
    "instantiatesCanonical", "instantiatesUri", "basedOn",
    "groupIdentifier", "courseOfTherapyType", "insurance",
    "dosageInstruction", "dispenseRequest", "substitution",
]

/// Procedure Σ-marked elements per FHIR R4 §9.3 (excluding mandatory id/meta/resourceType).
public let procedureSummaryFields: Set<String> = [
    "identifier", "instantiatesCanonical", "instantiatesUri", "basedOn", "partOf",
    "status", "statusReason", "category", "code", "subject", "encounter",
    "performedDateTime", "performedPeriod", "performedString", "performedAge", "performedRange",
    "recorder", "asserter", "performer", "location", "reasonCode", "reasonReference",
    "bodySite", "outcome", "report", "complication", "followUp", "note", "focalDevice", "usedReference", "usedCode",
]

/// DiagnosticReport Σ-marked elements per FHIR R4 §9.4 (excluding mandatory id/meta/resourceType).
public let diagnosticReportSummaryFields: Set<String> = [
    "identifier", "basedOn", "status", "category", "code",
    "subject", "encounter", "effectiveDateTime", "effectivePeriod",
    "issued", "performer", "resultsInterpreter", "specimen",
    "result", "imagingStudy", "media", "conclusion", "conclusionCode", "presentedForm",
]

/// Immunization Σ-marked elements per FHIR R4 §11.17 (excluding mandatory id/meta/resourceType).
public let immunizationSummaryFields: Set<String> = [
    "identifier", "status", "statusReason", "vaccineCode",
    "patient", "encounter", "occurrenceDateTime", "occurrenceString",
    "recorded", "primarySource", "reportOrigin", "location", "manufacturer",
    "lotNumber", "expirationDate", "site", "route", "doseQuantity",
    "performer", "note", "reasonCode", "reasonReference",
    "isSubpotent", "subpotentReason", "education", "programEligibility",
    "fundingSource", "reaction", "protocolApplied",
]

/// AllergyIntolerance Σ-marked elements per FHIR R4.
public let allergyIntoleranceSummaryFields: Set<String> = [
    "identifier", "clinicalStatus", "verificationStatus",
    "type", "category", "criticality",
    "code", "patient", "encounter", "onsetDateTime", "onsetAge",
    "onsetPeriod", "onsetRange", "onsetString",
    "recordedDate", "recorder", "asserter",
    "lastOccurrence", "note", "reaction",
]

/// Practitioner Σ-marked elements per FHIR R4 §12.1 (excluding mandatory id/meta/resourceType).
public let practitionerSummaryFields: Set<String> = [
    "identifier", "active", "name", "telecom", "address",
    "gender", "birthDate", "photo", "qualification", "communication",
]

/// Medication Σ-marked elements per FHIR R4 §11.3 (excluding mandatory id/meta/resourceType).
public let medicationSummaryFields: Set<String> = [
    "identifier", "code", "status", "manufacturer", "form",
    "amount", "ingredient", "batch",
]

/// Organization Σ-marked elements per FHIR R4 §12.8 (excluding mandatory id/meta/resourceType).
public let organizationSummaryFields: Set<String> = [
    "identifier", "active", "type", "name", "alias",
    "telecom", "address", "partOf", "contact", "endpoint",
]

/// Location Σ-marked elements per FHIR R4 §12.10 (excluding mandatory id/meta/resourceType).
public let locationSummaryFields: Set<String> = [
    "identifier", "status", "operationalStatus", "name", "alias", "mode",
    "type", "telecom", "address", "physicalType", "position",
    "managingOrganization", "partOf",
]

/// ServiceRequest Σ-marked elements per FHIR R4 (excluding mandatory id/meta/resourceType).
public let serviceRequestSummaryFields: Set<String> = [
    "identifier", "instantiatesCanonical", "instantiatesUri", "basedOn", "replaces",
    "requisition", "status", "intent", "category", "priority", "doNotPerform",
    "code", "subject", "encounter", "occurrence", "authoredOn",
    "requester", "performerType", "performer",
]

/// Specimen Σ-marked elements per FHIR R4 §12.16 (excluding mandatory id/meta/resourceType).
public let specimenSummaryFields: Set<String> = [
    "identifier", "accessionIdentifier", "status", "type", "subject",
    "receivedTime", "parent", "request", "collection", "processing",
    "container", "condition", "note",
]

/// DocumentReference Σ-marked elements per FHIR R4 §11.2 (excluding mandatory id/meta/resourceType).
public let documentReferenceSummaryFields: Set<String> = [
    "masterIdentifier", "identifier", "status", "docStatus", "type", "category",
    "subject", "date", "author", "authenticator", "custodian", "relatesTo",
    "description", "securityLabel", "content", "context",
]

/// RelatedPerson Σ-marked elements per FHIR R4 §12.30 (excluding mandatory id/meta/resourceType).
public let relatedPersonSummaryFields: Set<String> = [
    "identifier", "active", "patient", "relationship", "name",
    "telecom", "gender", "birthDate", "address", "photo", "period",
    "communication",
]

/// Applies `_summary` filtering to a resource's JSON bytes.
/// - `.true`:  keeps `summaryFields` + mandatory elements; adds SUBSETTED tag.
/// - `.text`:  keeps only `text` + mandatory elements; adds SUBSETTED tag.
/// - `.data`:  removes `text`; adds SUBSETTED tag.
/// - `.false`/`.count`: returns input unchanged (`.count` is handled at route level).
public func applySummary(_ jsonData: Data, mode: SummaryMode, summaryFields: Set<String>) -> Data {
    switch mode {
    case .false, .count:
        return jsonData
    case .true:
        return applyElements(jsonData, elements: summaryFields)
    case .text:
        return applyElements(jsonData, elements: ["text"])
    case .data:
        guard var obj = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            return jsonData
        }
        obj.removeValue(forKey: "text")
        var meta = (obj["meta"] as? [String: Any]) ?? [:]
        var tags = (meta["tag"] as? [[String: Any]]) ?? []
        if !tags.contains(where: { ($0["code"] as? String) == "SUBSETTED" }) {
            tags.append([
                "system": "http://terminology.hl7.org/CodeSystem/v3-ObservationValue",
                "code": "SUBSETTED",
            ])
        }
        meta["tag"] = tags
        obj["meta"] = meta
        return (try? JSONSerialization.data(withJSONObject: obj)) ?? jsonData
    }
}

/// Filters a resource's JSON to only the requested top-level elements.
///
/// Mandatory elements (`id`, `meta`, `resourceType`) are always included.
/// Marks the result with the SUBSETTED security tag per FHIR R4 §3.3.
public func applyElements(_ jsonData: Data, elements: Set<String>) -> Data {
    guard var obj = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
        return jsonData
    }
    let mandatory: Set<String> = ["id", "meta", "resourceType"]
    let keep = elements.union(mandatory)
    obj = obj.filter { keep.contains($0.key) }

    var meta = (obj["meta"] as? [String: Any]) ?? [:]
    var tags = (meta["tag"] as? [[String: Any]]) ?? []
    if !tags.contains(where: { ($0["code"] as? String) == "SUBSETTED" }) {
        tags.append([
            "system": "http://terminology.hl7.org/CodeSystem/v3-ObservationValue",
            "code": "SUBSETTED"
        ])
    }
    meta["tag"] = tags
    obj["meta"] = meta

    return (try? JSONSerialization.data(withJSONObject: obj)) ?? jsonData
}

private func escapeJSON(_ value: String) -> String {
    value
        .replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "\"", with: "\\\"")
}
