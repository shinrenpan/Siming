import Foundation
#if canImport(Glibc)
import Glibc
#elseif canImport(Darwin)
import Darwin
#endif

/// An IPv4 or IPv6 address as raw bytes (4 or 16). IPv4-mapped IPv6 (`::ffff:a.b.c.d`)
/// is folded to IPv4 so a dual-stack socket and an IPv4 CIDR compare equal.
struct IPAddressBytes: Hashable, CustomStringConvertible {
    let bytes: [UInt8]

    init(bytes: [UInt8]) { self.bytes = bytes }

    init?(_ text: some StringProtocol) {
        let s = String(text)
        var v4 = in_addr()
        if inet_pton(AF_INET, s, &v4) == 1 {
            bytes = withUnsafeBytes(of: &v4) { Array($0) }
            return
        }
        var v6 = in6_addr()
        guard inet_pton(AF_INET6, s, &v6) == 1 else { return nil }
        let raw = withUnsafeBytes(of: &v6) { Array($0) }
        if raw[0..<10].allSatisfy({ $0 == 0 }) && raw[10] == 0xff && raw[11] == 0xff {
            bytes = Array(raw[12..<16])
        } else {
            bytes = raw
        }
    }

    /// Parses an X-Forwarded-For entry, which some proxies (IIS ARR, Azure App Gateway)
    /// write with a port: `198.51.100.9:51234`, `[2001:db8::1]:443`.
    init?(forwardedEntry text: String) {
        if let ip = IPAddressBytes(text) { self = ip; return }
        if text.hasPrefix("["), let close = text.firstIndex(of: "]") {
            self.init(text[text.index(after: text.startIndex)..<close])
        } else if text.filter({ $0 == ":" }).count == 1, let colon = text.firstIndex(of: ":") {
            self.init(text[..<colon])
        } else {
            return nil
        }
    }

    /// Canonical text form — one bucket per address however the client spelled it.
    var description: String {
        var buf = [CChar](repeating: 0, count: Int(INET6_ADDRSTRLEN))
        var raw = bytes
        let family = bytes.count == 4 ? AF_INET : AF_INET6
        guard inet_ntop(family, &raw, &buf, socklen_t(buf.count)) != nil else { return "?" }
        return String(decoding: buf.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }
}

/// Addresses whose `X-Forwarded-For` entries are believed. Each entry is an IP or a CIDR
/// (`10.0.0.5`, `172.16.0.0/12`, `fd00::/8`).
public struct TrustedProxies: Sendable {
    private struct Network: Sendable {
        let base: [UInt8]
        let prefix: Int

        func contains(_ ip: IPAddressBytes) -> Bool {
            guard ip.bytes.count == base.count else { return false }
            var remaining = prefix
            for i in 0..<base.count where remaining > 0 {
                let bits = min(8, remaining)
                let mask: UInt8 = bits == 8 ? 0xff : ~(0xff >> UInt8(bits))
                if ip.bytes[i] & mask != base[i] & mask { return false }
                remaining -= bits
            }
            return true
        }
    }

    private let networks: [Network]

    public static let none = TrustedProxies(networks: [])

    private init(networks: [Network]) { self.networks = networks }

    /// Throws on any malformed entry: a typo here silently re-opens the spoofing hole
    /// the setting exists to close, so it fails at startup instead.
    public init(parsing specs: [String]) throws {
        networks = try specs.compactMap { raw in
            let spec = raw.trimmingCharacters(in: .whitespaces)
            if spec.isEmpty { return nil }
            let parts = spec.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false)
            guard let ip = IPAddressBytes(parts[0]) else {
                throw RateLimitConfigError.invalidTrustedProxy(spec)
            }
            let maxPrefix = ip.bytes.count * 8
            var prefix = maxPrefix
            if parts.count == 2 {
                guard let p = Int(parts[1]), (0...maxPrefix).contains(p) else {
                    throw RateLimitConfigError.invalidTrustedProxy(spec)
                }
                prefix = p
            }
            return Network(base: ip.bytes, prefix: prefix)
        }
    }

    public var isEmpty: Bool { networks.isEmpty }
    public var count: Int { networks.count }

    func contains(_ ip: IPAddressBytes) -> Bool {
        networks.contains { $0.contains(ip) }
    }
}

public enum RateLimitConfigError: Error, CustomStringConvertible {
    case invalidTrustedProxy(String)

    public var description: String {
        switch self {
        case .invalidTrustedProxy(let s):
            return "Trusted proxy '\(s)' is not an IP address or CIDR "
                + "(RATE_LIMIT_TRUSTED_PROXIES or security.rateLimit.trustedProxies)"
        }
    }
}

/// The address a request is rate-limited under.
///
/// The TCP peer is the client unless it is a trusted proxy. Only then is `X-Forwarded-For`
/// read, right to left, skipping trusted hops: each entry was written by the hop to its
/// right, so the first untrusted one is the address the outermost trusted proxy saw.
/// Everything left of it was written by the client and is never believed — reading the
/// leftmost entry lets a client pick a fresh bucket per request.
///
/// `forwardedFor` is every `X-Forwarded-For` field value in order; a proxy may append a
/// second header line rather than extend the first.
func rateLimitClientKey(peer: String?, forwardedFor: [String], trusted: TrustedProxies) -> String {
    guard let peerText = peer else { return "unknown" }   // e.g. Unix socket
    guard let peerIP = IPAddressBytes(peerText) else { return peerText }
    guard trusted.contains(peerIP) else { return bucketKey(peerIP) }

    let hops = forwardedFor
        .flatMap { $0.split(separator: ",") }
        .map { $0.trimmingCharacters(in: .whitespaces) }
        .filter { !$0.isEmpty }

    var vouchedBy = peerIP
    for hop in hops.reversed() {
        // A trusted proxy wrote something that is not an address. Never key on raw text —
        // it would be a client-chosen bucket — so charge the proxy that wrote it.
        guard let ip = IPAddressBytes(forwardedEntry: hop) else { return bucketKey(vouchedBy) }
        if !trusted.contains(ip) { return bucketKey(ip) }
        vouchedBy = ip
    }
    // Every entry is inside the trusted network. Entries further left may still be the
    // client's own (a trusted-range host can send the header), so stop at the one the
    // peer vouched for rather than the leftmost.
    return bucketKey(hops.last.flatMap { IPAddressBytes(forwardedEntry: $0) } ?? peerIP)
}

/// IPv4 per address; IPv6 per /64 — the standard end-site allocation, so one host
/// cannot rotate through its own addresses for fresh buckets.
private func bucketKey(_ ip: IPAddressBytes) -> String {
    guard ip.bytes.count == 16 else { return ip.description }
    return IPAddressBytes(bytes: Array(ip.bytes[0..<8]) + Array(repeating: 0, count: 8)).description + "/64"
}
