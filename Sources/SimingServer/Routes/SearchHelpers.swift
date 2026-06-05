import Foundation
import Hummingbird
import NIOCore

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
///
/// Handles `+`-as-space and percent-decoding for both keys and values.
/// Returns the same `[(key: Substring, value: Substring)]` shape as URI query parameters
/// so callers can pass the result directly to the same query-building helpers.
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
