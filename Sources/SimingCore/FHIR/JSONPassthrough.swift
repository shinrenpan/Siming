import Foundation

// Shared formatter — ISO8601DateFormatter is expensive to construct.
private let iso8601: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return f
}()

// RFC 7231 HTTP-date formatter for Last-Modified header.
private let httpDateFormatter: DateFormatter = {
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
    total: Int?,
    selfURL: String,
    nextURL: String?
) -> Data {
    let entryCapacity = entries.reduce(0) { $0 + $1.json.count + 80 }
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

    if !entries.isEmpty {
        s(",\"entry\":[")
        for (i, entry) in entries.enumerated() {
            if i > 0 { s(",") }
            s("{\"fullUrl\":\"\(escapeJSON(entry.fullUrl))\",\"resource\":")
            out.append(entry.json)
            s(",\"search\":{\"mode\":\"match\"}}")
        }
        s("]")
    }

    s("}")
    return out
}

/// One version entry for a FHIR `_history` Bundle.
public struct HistoryRawEntry: Sendable {
    public let id: String        // resource logical id
    public let versionId: Int64
    public let lastUpdated: Date
    public let jsonData: Data?   // nil for delete markers
    public let deleted: Bool

    public init(id: String, versionId: Int64, lastUpdated: Date, jsonData: Data?, deleted: Bool) {
        self.id = id
        self.versionId = versionId
        self.lastUpdated = lastUpdated
        self.jsonData = jsonData
        self.deleted = deleted
    }
}

/// Builds a FHIR `_history` Bundle as raw bytes.
/// Works for both instance history and type-level history — uses `entry.id` per entry.
///
/// - Parameters:
///   - entries: Versions ordered newest-first. `jsonData` is nil for delete-marker versions.
///   - resourceType: e.g. "Patient"
///   - baseURL: Server base URL (no trailing slash), e.g. "http://localhost:8080"
public func buildHistoryBundleJSON(
    entries: [HistoryRawEntry],
    resourceType: String,
    baseURL: String
) -> Data {
    var out = Data()
    out.reserveCapacity(512 + entries.reduce(0) { $0 + ($1.jsonData?.count ?? 0) + 200 })

    func s(_ string: String) { out.append(contentsOf: string.utf8) }

    s("{\"resourceType\":\"Bundle\",\"type\":\"history\",\"total\":\(entries.count)")
    s(",\"entry\":[")

    for (i, entry) in entries.enumerated() {
        if i > 0 { s(",") }
        let fullUrl = "\(baseURL)/\(resourceType)/\(entry.id)/_history/\(entry.versionId)"
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
            requestUrl = "\(resourceType)/\(entry.id)"
        } else if entry.versionId == 1 {
            method = "POST"
            requestUrl = resourceType
        } else {
            method = "PUT"
            requestUrl = "\(resourceType)/\(entry.id)"
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

private func escapeJSON(_ value: String) -> String {
    value
        .replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "\"", with: "\\\"")
}
