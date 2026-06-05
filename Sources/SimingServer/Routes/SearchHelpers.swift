import Foundation
import NIOCore

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
