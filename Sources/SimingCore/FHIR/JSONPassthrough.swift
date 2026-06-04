import Foundation

// Shared formatter — ISO8601DateFormatter is expensive to construct.
private let iso8601: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return f
}()

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
    total: Int,
    selfURL: String,
    nextURL: String?
) -> Data {
    let entryCapacity = entries.reduce(0) { $0 + $1.json.count + 80 }
    var out = Data()
    out.reserveCapacity(300 + entryCapacity)

    func s(_ string: String) { out.append(contentsOf: string.utf8) }

    s("{\"resourceType\":\"Bundle\",\"type\":\"searchset\",\"total\":\(total)")
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

private func escapeJSON(_ value: String) -> String {
    value
        .replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "\"", with: "\\\"")
}
