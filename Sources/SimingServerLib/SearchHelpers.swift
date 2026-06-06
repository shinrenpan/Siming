import Foundation
import HTTPTypes
import Hummingbird
import NIOCore
import SimingCore

/// Returns the server base URL (scheme + authority only), e.g. "http://localhost:8080".
func serverBaseURL(_ request: Request) -> String {
    "http://\(request.head.authority ?? "localhost")"
}

/// Parses a FHIR instant string (ISO 8601) into a Date. Accepts e.g. "2023-01-01T00:00:00Z".
func parseFHIRInstant(_ raw: String) -> Date? {
    iso8601Instant.date(from: raw) ?? iso8601InstantMs.date(from: raw)
}

nonisolated(unsafe) private let iso8601Instant: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime]
    return f
}()

nonisolated(unsafe) private let iso8601InstantMs: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return f
}()

/// Parses a URL query string (e.g., from an If-None-Exist header) into key-value pairs.
func parseQueryString(_ raw: String) -> [(key: Substring, value: Substring)] {
    raw.split(separator: "&", omittingEmptySubsequences: true).compactMap { pair in
        let parts = pair.split(separator: "=", maxSplits: 1)
        guard parts.count == 2 else { return nil }
        let k = formDecode(parts[0])
        let v = formDecode(parts[1])
        guard !k.isEmpty else { return nil }
        return (key: k[k.startIndex...], value: v[v.startIndex...])
    }
}

/// Parses an `application/x-www-form-urlencoded` body into key-value pairs.
func parseFormPairs(from buffer: ByteBuffer) -> [(key: Substring, value: Substring)] {
    guard let raw = buffer.getString(at: buffer.readerIndex, length: buffer.readableBytes) else {
        return []
    }
    return raw.split(separator: "&", omittingEmptySubsequences: true).compactMap { pair in
        let parts = pair.split(separator: "=", maxSplits: 1)
        guard parts.count == 2 else { return nil }
        let k = formDecode(parts[0])
        let v = formDecode(parts[1])
        guard !k.isEmpty else { return nil }
        return (key: k[k.startIndex...], value: v[v.startIndex...])
    }
}

private func formDecode(_ s: Substring) -> String {
    String(s).replacingOccurrences(of: "+", with: " ").removingPercentEncoding ?? String(s)
}

/// Parses `_elements=a,b,c` from query/form pairs into a Set, or nil if absent.
func parseElements(from pairs: some Collection<(key: Substring, value: Substring)>) -> Set<String>? {
    guard let raw = pairs.first(where: { String($0.key) == "_elements" })?.value else { return nil }
    let names = String(raw).split(separator: ",")
        .map { $0.trimmingCharacters(in: .whitespaces) }
        .filter { !$0.isEmpty }
    return names.isEmpty ? nil : Set(names)
}

/// Returns parameter keys not present in `known` (base name before `:` stripped).
/// Used for `Prefer: handling=strict` validation.
func unknownParams(
    in pairs: some Collection<(key: Substring, value: Substring)>,
    known: Set<String>
) -> [String] {
    pairs.compactMap { pair in
        let base = String(pair.key.split(separator: ":").first ?? pair.key)
        return known.contains(base) ? nil : String(pair.key)
    }
}

/// Parses `_summary` from query/form pairs, or nil if absent or unrecognized.
func parseSummary(from pairs: some Collection<(key: Substring, value: Substring)>) -> SummaryMode? {
    guard let raw = pairs.first(where: { String($0.key) == "_summary" })?.value else { return nil }
    return SummaryMode(rawValue: String(raw))
}

/// Returns true when the request carries `Prefer: handling=strict`.
func isStrictHandling(_ request: Request) -> Bool {
    (request.headers[HTTPField.Name("Prefer")!] ?? "").contains("handling=strict")
}

/// Parses all `_include` values from query/form pairs into IncludeParam list.
/// Format: `ResourceType:paramName` or `ResourceType:paramName:TargetType`
func parseIncludes(from pairs: some Collection<(key: Substring, value: Substring)>) -> [IncludeParam] {
    pairs.compactMap { pair in
        guard String(pair.key) == "_include" else { return nil }
        return parseOneIncludeParam(String(pair.value))
    }
}

/// Parses all `_revinclude` values from query/form pairs into IncludeParam list.
func parseRevIncludes(from pairs: some Collection<(key: Substring, value: Substring)>) -> [IncludeParam] {
    pairs.compactMap { pair in
        guard String(pair.key) == "_revinclude" else { return nil }
        return parseOneIncludeParam(String(pair.value))
    }
}

private func parseOneIncludeParam(_ raw: String) -> IncludeParam? {
    let parts = raw.split(separator: ":", maxSplits: 2).map(String.init)
    guard parts.count >= 2, !parts[0].isEmpty, !parts[1].isEmpty else { return nil }
    return IncludeParam(sourceType: parts[0], paramName: parts[1], targetType: parts.count > 2 ? parts[2] : nil)
}

/// Builds include entry tuples for bundle building from resolved IncludedResources.
func includeEntryTuples(from resources: [IncludedResource], baseURL: String) -> [(fullUrl: String, json: Data)] {
    resources.map { r in ("\(baseURL)/\(r.resourceType)/\(r.id)", r.jsonWithMeta) }
}
