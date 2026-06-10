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

/// Global meta search params accepted on every resource (FHIR R4 §3.2.2).
private let knownMetaParams: Set<String> = ["_tag", "_security", "_profile", "_source"]

/// Returns parameter keys not present in `known` (base name before `:` stripped).
/// Chained params (containing `.`) and `_has:` params are always treated as known.
/// Global meta params (`_tag`, `_security`, `_profile`, `_source`) are universally accepted.
/// Used for `Prefer: handling=strict` validation.
func unknownParams(
    in pairs: some Collection<(key: Substring, value: Substring)>,
    known: Set<String>
) -> [String] {
    pairs.compactMap { pair in
        let key = String(pair.key)
        if key.hasPrefix("_has:") { return nil }
        let base = String(pair.key.split(separator: ":").first ?? pair.key)
        if base.contains(".") { return nil }
        if knownMetaParams.contains(base) { return nil }
        return known.contains(base) ? nil : key
    }
}

/// Normalises FHIR reference `:type` modifier — converts `param:ResourceType=id` to
/// `param=ResourceType/id` so existing reference parsers handle both wire formats.
///
/// Rules (all must hold for normalisation to apply):
/// - key does NOT start with `_` (skip `_has`, `_include` etc. — they use colon differently)
/// - key does NOT contain `.`  (skip chained params)
/// - modifier (text after first `:`) starts with an uppercase letter and contains no further `:`
///   (distinguishes resource types from search modifiers like :not, :missing, :contains, :text)
func normalizeReferenceTypeModifiers(
    _ pairs: some Collection<(key: Substring, value: Substring)>
) -> [(key: Substring, value: Substring)] {
    pairs.map { pair in
        let keyStr = String(pair.key)
        guard !keyStr.hasPrefix("_"), !keyStr.contains("."),
              let colonIdx = keyStr.firstIndex(of: ":") else { return pair }
        let modifier = String(keyStr[keyStr.index(after: colonIdx)...])
        guard modifier.first?.isUppercase == true, !modifier.contains(":") else { return pair }
        let base = Substring(keyStr[..<colonIdx])
        let normalizedValue = Substring("\(modifier)/\(pair.value)")
        return (key: base, value: normalizedValue)
    }
}

/// Parses `_tag`, `_tag:not`, `_security`, `_security:not`, `_profile`, `_source` from query params.
func parseMetaSearchParams(from pairs: some Collection<(key: Substring, value: Substring)>) -> MetaSearchParams {
    func all(_ key: String) -> [String] {
        pairs.filter { String($0.key) == key }.map { String($0.value) }
    }
    var meta = MetaSearchParams()
    meta.tag         = all("_tag").flatMap         { MetaSearchParams.TokenParam.parseList($0) }
    meta.tagNot      = all("_tag:not").flatMap      { MetaSearchParams.TokenParam.parseList($0) }
    meta.security    = all("_security").flatMap    { MetaSearchParams.TokenParam.parseList($0) }
    meta.securityNot = all("_security:not").flatMap { MetaSearchParams.TokenParam.parseList($0) }
    meta.profile     = all("_profile")
    meta.source      = all("_source")
    return meta
}

/// Parses all chained search params (keys containing `.`) from query/form pairs.
/// Format: `refParam.childParam=value` or `refParam:Type.childParam:modifier=value`
func parseChainParams(from pairs: some Collection<(key: Substring, value: Substring)>) -> [ChainedParam] {
    pairs.compactMap { pair in
        let key = String(pair.key)
        guard key.contains(".") else { return nil }
        return parseChainKey(key, value: String(pair.value))
    }
}

/// Parses all `_has` modifier params from query/form pairs.
/// Format: `_has:[ReferencedType]:[refParam]:[childParam]=value`
func parseHasParams(from pairs: some Collection<(key: Substring, value: Substring)>) -> [HasParam] {
    pairs.compactMap { pair in
        let key = String(pair.key)
        guard key.hasPrefix("_has:") else { return nil }
        return parseHasKey(key, value: String(pair.value))
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

/// Parses all `_include` and `_include:iterate` values from query/form pairs.
/// Format: `ResourceType:paramName` or `ResourceType:paramName:TargetType`
/// `paramName` may be `*` to follow all reference params of the source type.
func parseIncludes(from pairs: some Collection<(key: Substring, value: Substring)>) -> [IncludeParam] {
    pairs.compactMap { pair in
        let key = String(pair.key)
        let isIterate = key == "_include:iterate"
        guard key == "_include" || isIterate else { return nil }
        return parseOneIncludeParam(String(pair.value), isIterate: isIterate)
    }
}

/// Parses all `_revinclude` and `_revinclude:iterate` values from query/form pairs.
func parseRevIncludes(from pairs: some Collection<(key: Substring, value: Substring)>) -> [IncludeParam] {
    pairs.compactMap { pair in
        let key = String(pair.key)
        let isIterate = key == "_revinclude:iterate"
        guard key == "_revinclude" || isIterate else { return nil }
        return parseOneIncludeParam(String(pair.value), isIterate: isIterate)
    }
}

private func parseOneIncludeParam(_ raw: String, isIterate: Bool = false) -> IncludeParam? {
    let parts = raw.split(separator: ":", maxSplits: 2).map(String.init)
    guard parts.count >= 2, !parts[0].isEmpty, !parts[1].isEmpty else { return nil }
    return IncludeParam(
        sourceType: parts[0],
        paramName: parts[1],
        targetType: parts.count > 2 ? parts[2] : nil,
        isIterate: isIterate
    )
}

/// Builds include entry tuples for bundle building from resolved IncludedResources.
func includeEntryTuples(from resources: [IncludedResource], baseURL: String) -> [(fullUrl: String, json: Data)] {
    resources.map { r in ("\(baseURL)/\(r.resourceType)/\(r.id)", r.jsonWithMeta) }
}
