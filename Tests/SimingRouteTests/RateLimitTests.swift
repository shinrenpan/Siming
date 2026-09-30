import Foundation
import HTTPTypes
import Hummingbird
import HummingbirdTesting
@testable import SimingServerLib
import Testing

@Suite("Rate-limit client key")
struct RateLimitClientKeyTests {

    private func key(_ peer: String?, _ xff: [String] = [], trusted: [String] = []) throws -> String {
        rateLimitClientKey(peer: peer, forwardedFor: xff, trusted: try TrustedProxies(parsing: trusted))
    }

    // ── No trusted proxies (direct exposure) ─────────────────────────────────

    @Test("keys on the TCP peer when no proxy is trusted")
    func peerWhenNothingTrusted() throws {
        #expect(try key("203.0.113.7") == "203.0.113.7")
    }

    @Test("ignores X-Forwarded-For from an untrusted peer — a client cannot pick its own bucket")
    func spoofedHeaderIgnored() throws {
        #expect(try key("203.0.113.7", ["1.1.1.1"]) == "203.0.113.7")
        #expect(try key("203.0.113.7", ["2.2.2.2"]) == "203.0.113.7")
    }

    @Test("folds IPv4-mapped IPv6 so a dual-stack socket shares the IPv4 bucket")
    func mappedIPv6Folded() throws {
        #expect(try key("::ffff:203.0.113.7") == "203.0.113.7")
    }

    @Test("a peer with no IP (Unix socket) gets one shared key rather than crashing")
    func noPeer() throws {
        #expect(try key(nil, ["1.1.1.1"]) == "unknown")
    }

    // ── Trusted proxies ──────────────────────────────────────────────────────

    @Test("behind a trusted proxy, keys on the address the proxy recorded")
    func trustedProxyEntry() throws {
        #expect(try key("10.0.0.2", ["198.51.100.9"], trusted: ["10.0.0.2"]) == "198.51.100.9")
    }

    @Test("reads right to left: entries the client wrote before the proxy's are ignored")
    func clientPrefixIgnored() throws {
        // Client sent "X-Forwarded-For: 1.1.1.1"; the proxy appended the real address.
        #expect(try key("10.0.0.2", ["1.1.1.1, 198.51.100.9"], trusted: ["10.0.0.2"]) == "198.51.100.9")
    }

    @Test("skips every trusted hop in a chain, matching CIDRs")
    func chainOfTrustedHops() throws {
        let k = try key("172.18.0.3", ["1.1.1.1, 198.51.100.9, 172.18.0.5"], trusted: ["172.16.0.0/12"])
        #expect(k == "198.51.100.9")
    }

    @Test("a proxy may add a second header line instead of extending the first")
    func multipleHeaderLines() throws {
        #expect(try key("10.0.0.2", ["1.1.1.1", "198.51.100.9"], trusted: ["10.0.0.0/8"]) == "198.51.100.9")
    }

    @Test("a trusted proxy that sent no X-Forwarded-For is itself the client")
    func trustedProxyWithoutHeader() throws {
        #expect(try key("10.0.0.2", trusted: ["10.0.0.2"]) == "10.0.0.2")
    }

    @Test("IPv6 CIDR matches only inside its prefix")
    func ipv6CIDR() throws {
        #expect(try key("fd00::1", ["2001:db8::5"], trusted: ["fd00::/8"]) == "2001:db8::/64")
        #expect(try key("fe80::1", ["2001:db8::5"], trusted: ["fd00::/8"]) == "fe80::/64")
    }

    @Test("a /24 does not trust the neighbouring network")
    func cidrBoundary() throws {
        #expect(try key("10.0.1.1", ["198.51.100.9"], trusted: ["10.0.0.0/24"]) == "10.0.1.1")
        #expect(try key("10.0.0.255", ["198.51.100.9"], trusted: ["10.0.0.0/24"]) == "198.51.100.9")
    }

    @Test("groups IPv6 clients by /64 so one host cannot rotate its own addresses")
    func ipv6GroupedBy64() throws {
        #expect(try key("2001:db8:1:2::a") == key("2001:db8:1:2:ffff::b"))
        #expect(try key("2001:db8:1:2::a") != key("2001:db8:1:3::a"))
    }

    @Test("strips a port a proxy wrote into the entry, IPv4 and bracketed IPv6")
    func entryWithPort() throws {
        #expect(try key("10.0.0.2", ["198.51.100.9:51234"], trusted: ["10.0.0.2"]) == "198.51.100.9")
        #expect(try key("10.0.0.2", ["[2001:db8::1]:443"], trusted: ["10.0.0.2"]) == "2001:db8::/64")
    }

    @Test("a non-address entry is charged to the proxy that wrote it, never used as a key")
    func garbageEntry() throws {
        #expect(try key("10.0.0.2", ["unknown"], trusted: ["10.0.0.2"]) == "10.0.0.2")
        #expect(try key("10.0.0.2", ["_hidden, 10.0.0.7"], trusted: ["10.0.0.0/24"]) == "10.0.0.7")
    }

    @Test("when every entry is trusted, the client-written leftmost is not the key")
    func allTrustedUsesVouchedEntry() throws {
        // A host inside the trusted range sent its own header; the proxy appended its real address.
        let a = try key("172.18.0.3", ["172.20.1.1, 172.18.0.9"], trusted: ["172.16.0.0/12"])
        let b = try key("172.18.0.3", ["172.20.2.2, 172.18.0.9"], trusted: ["172.16.0.0/12"])
        #expect(a == "172.18.0.9")
        #expect(a == b)
    }

    // ── Configuration ────────────────────────────────────────────────────────

    @Test("rejects malformed trusted-proxy entries at startup",
          arguments: ["10.0.0", "10.0.0.0/33", "fd00::/129", "proxy.local", "10.0.0.0/x", "10.0.0.0/"])
    func malformedRejected(_ spec: String) {
        #expect(throws: RateLimitConfigError.self) { try TrustedProxies(parsing: [spec]) }
    }

    @Test("tolerates whitespace and empty items from a comma-separated env var")
    func envListParsed() throws {
        let t = try TrustedProxies(parsing: " 10.0.0.1 , ,172.16.0.0/12".components(separatedBy: ","))
        #expect(t.count == 2)
    }
}

@Suite("Rate-limit middleware over a real socket")
struct RateLimitMiddlewareTests {

    private func makeApp(trusted: [String]) throws -> some ApplicationProtocol {
        let router = Router(context: SimingRequestContext.self)
        let cfg = RateLimitConfiguration(rps: 0.001, burst: 1, trustedProxies: try TrustedProxies(parsing: trusted))
        router.middlewares.add(RateLimitMiddleware(config: cfg))
        router.get("ping") { _, _ in HTTPResponse.Status.ok }
        return Application(router: router)
    }

    @Test("rotating X-Forwarded-For does not buy a fresh bucket")
    func spoofingDoesNotBypass() async throws {
        try await makeApp(trusted: []).test(.live) { client in
            try await client.execute(uri: "/ping", method: .get,
                                     headers: [HTTPField.Name("x-forwarded-for")!: "1.1.1.1"]) { res in
                #expect(res.status == .ok)
            }
            try await client.execute(uri: "/ping", method: .get,
                                     headers: [HTTPField.Name("x-forwarded-for")!: "2.2.2.2"]) { res in
                #expect(res.status == .tooManyRequests)
            }
        }
    }

    @Test("behind a trusted proxy, forwarded clients get separate buckets")
    func trustedProxySeparatesClients() async throws {
        try await makeApp(trusted: ["127.0.0.1", "::1"]).test(.live) { client in
            for ip in ["198.51.100.1", "198.51.100.2"] {
                try await client.execute(uri: "/ping", method: .get,
                                         headers: [HTTPField.Name("x-forwarded-for")!: ip]) { res in
                    #expect(res.status == .ok)
                }
            }
            try await client.execute(uri: "/ping", method: .get,
                                     headers: [HTTPField.Name("x-forwarded-for")!: "198.51.100.1"]) { res in
                #expect(res.status == .tooManyRequests)
            }
        }
    }
}
