import Foundation
import HTTPTypes
import Hummingbird
import HummingbirdTesting
import Logging
@testable import SimingServerLib
import Testing

@Suite("SMART discovery document")
struct SmartConfigTests {

    private func makeApp(_ config: SmartConfiguration) -> some ApplicationProtocol {
        let router = Router(context: SimingRequestContext.self)
        addSmartRoutes(to: router, config: config)
        return Application(responder: router.buildResponder())
    }

    private func fetch(_ config: SmartConfiguration) async throws -> [String: Any] {
        try await makeApp(config).test(.router) { client in
            try await client.execute(uri: "/.well-known/smart-configuration", method: .get) { res in
                #expect(res.status == .ok)
                let obj = try JSONSerialization.jsonObject(
                    with: Data(buffer: res.body)
                ) as? [String: Any]
                return try #require(obj)
            }
        }
    }

    // ── Resource-server-only deployment ───────────────────────────────────────

    @Test("omits authorization-server fields when no endpoints are configured")
    func resourceServerOnly() async throws {
        let obj = try await fetch(SmartConfiguration(issuer: "https://idp.example.com"))

        #expect(obj["authorization_endpoint"] == nil)
        #expect(obj["token_endpoint"] == nil)
        #expect(obj["code_challenge_methods_supported"] == nil)

        #expect(obj["grant_types_supported"] == nil)
        #expect(obj["token_endpoint_auth_methods_supported"] == nil)

        let caps = try #require(obj["capabilities"] as? [String])
        #expect(!caps.contains("launch-standalone"))
        #expect(!caps.contains("client-public"))
        // Patient context in a standalone launch cannot stand without the launch.
        #expect(!caps.contains("context-standalone-patient"))
    }

    // ── Paired with an authorization server ───────────────────────────────────

    @Test("emits the three fields a standalone-launch client decodes")
    func standaloneLaunchFields() async throws {
        let obj = try await fetch(
            SmartConfiguration(
                issuer: "https://idp.example.com",
                authorizeURL: "https://idp.example.com/auth",
                tokenURL: "https://idp.example.com/token"
            )
        )

        #expect(obj["authorization_endpoint"] as? String == "https://idp.example.com/auth")
        #expect(obj["token_endpoint"] as? String == "https://idp.example.com/token")
        #expect(obj["code_challenge_methods_supported"] as? [String] == ["S256"])
    }

    @Test("declares launch-standalone and client-public alongside the endpoints")
    func standaloneLaunchCapabilities() async throws {
        let obj = try await fetch(
            SmartConfiguration(
                issuer: "https://idp.example.com",
                authorizeURL: "https://idp.example.com/auth",
                tokenURL: "https://idp.example.com/token"
            )
        )

        let caps = try #require(obj["capabilities"] as? [String])
        #expect(caps.contains("launch-standalone"))
        #expect(caps.contains("client-public"))
        #expect(caps.contains("context-standalone-patient"))
        #expect(caps.contains("permission-v1"))
    }

    @Test("advertises 'none' auth for PKCE public clients")
    func publicClientAuthMethod() async throws {
        let obj = try await fetch(
            SmartConfiguration(
                issuer: "https://idp.example.com",
                authorizeURL: "https://idp.example.com/auth",
                tokenURL: "https://idp.example.com/token"
            )
        )
        let methods = try #require(obj["token_endpoint_auth_methods_supported"] as? [String])
        #expect(methods.contains("none"))
    }

    @Test("emits grant_types_supported required by SMART 2.0")
    func grantTypes() async throws {
        let obj = try await fetch(
            SmartConfiguration(
                issuer: "https://idp.example.com",
                authorizeURL: "https://idp.example.com/auth",
                tokenURL: "https://idp.example.com/token"
            )
        )
        let grants = try #require(obj["grant_types_supported"] as? [String])
        #expect(grants.contains("authorization_code"))
        // offline_access is advertised in scopes_supported; refresh_token redeems it.
        #expect(grants.contains("refresh_token"))
    }

    // ── Empty environment variables ───────────────────────────────────────────
    // Unset values render as "" in compose / Helm / k8s manifests, so "" must not
    // read as "set" anywhere the both-or-neither rule or an emit site looks.

    @Test("an empty endpoint does not slip past the both-or-neither rule")
    func emptyAuthorizeURLRejected() async {
        await #expect(throws: SmartConfigError.self) {
            try await SmartConfiguration.from(
                environment: [
                    "SMART_ISSUER": "https://idp.example.com",
                    "SMART_AUTHORIZE_URL": "",
                    "SMART_TOKEN_URL": "https://idp.example.com/token",
                ],
                logger: quietLogger
            )
        }
    }

    @Test("two empty endpoints are a resource-server-only deployment, not a broken one")
    func bothEndpointsEmpty() async throws {
        let config = try await SmartConfiguration.from(
            environment: [
                "SMART_ISSUER": "https://idp.example.com",
                "SMART_AUTHORIZE_URL": "",
                "SMART_TOKEN_URL": "   ",
            ],
            logger: quietLogger
        )
        let unwrapped = try #require(config)
        #expect(unwrapped.authorizationServer == nil)

        let obj = try await fetch(unwrapped)
        #expect(obj["authorization_endpoint"] == nil)
    }

    @Test("an empty endpoint never reaches the document as an empty string")
    func emptyEndpointNotPublished() async throws {
        let obj = try await fetch(
            SmartConfiguration(
                issuer: "https://idp.example.com",
                authorizeURL: "",
                tokenURL: "https://idp.example.com/token"
            )
        )
        #expect(obj["authorization_endpoint"] == nil)
        #expect(obj["token_endpoint"] == nil)
        let caps = try #require(obj["capabilities"] as? [String])
        #expect(!caps.contains("launch-standalone"))
    }

    // ── Split-horizon JWKS ────────────────────────────────────────────────────
    // The address this server fetches keys from and the address it tells clients to
    // fetch from are the same string only when one address reaches the authorization
    // server from both sides. In a container it does not.

    @Test("jwks_uri falls back to the fetch address when no advertised one is set")
    func advertisedJWKSDefaultsToFetchURL() async throws {
        let obj = try await fetch(
            SmartConfiguration(
                issuer: "https://idp.example.com",
                jwksURL: "https://idp.example.com/certs"
            )
        )
        #expect(obj["jwks_uri"] as? String == "https://idp.example.com/certs")
    }

    @Test("jwks_uri publishes the advertised address, not the container-internal one")
    func advertisedJWKSOverridesFetchURL() async throws {
        let config = SmartConfiguration(
            issuer: "https://idp.example.com",
            jwksURL: "http://keycloak:8080/realms/siming/protocol/openid-connect/certs",
            advertisedJWKSURL: "http://localhost:8081/realms/siming/protocol/openid-connect/certs"
        )
        // The server still fetches from the internal address.
        #expect(config.jwksURL == "http://keycloak:8080/realms/siming/protocol/openid-connect/certs")

        let obj = try await fetch(config)
        #expect(obj["jwks_uri"] as? String
            == "http://localhost:8081/realms/siming/protocol/openid-connect/certs")
    }

    @Test("an advertised address alone is published without a fetch address")
    func advertisedJWKSWithoutFetchURL() async throws {
        let obj = try await fetch(
            SmartConfiguration(
                issuer: "https://idp.example.com",
                advertisedJWKSURL: "https://idp.example.com/certs"
            )
        )
        #expect(obj["jwks_uri"] as? String == "https://idp.example.com/certs")
    }

    /// Asserted on the initialiser rather than through `from(environment:)`, which
    /// fetches the key set over the network when SMART_JWKS_URL is present.
    @Test("an empty advertised address falls back rather than publishing nothing")
    func emptyAdvertisedJWKSFallsBack() {
        let config = SmartConfiguration(
            issuer: "https://idp.example.com",
            jwksURL: "https://idp.example.com/certs",
            advertisedJWKSURL: "  "
        )
        #expect(config.advertisedJWKSURL == "https://idp.example.com/certs")
    }

    // ── URL validation ────────────────────────────────────────────────────────
    // A published URL is fetched by someone else, so a typo in one fails far from the
    // deployment that caused it. Reject at startup instead.

    @Test("a malformed advertised JWKS URL fails at startup", arguments: [
        "htp://localhost:8081/certs",   // typo'd scheme
        "localhost:8081/certs",         // no scheme
        "https://",                     // no host
    ])
    func malformedAdvertisedJWKSRejected(_ value: String) async {
        await #expect(throws: SmartConfigError.self) {
            try await SmartConfiguration.from(
                environment: [
                    "SMART_ISSUER": "https://idp.example.com",
                    "SMART_ADVERTISED_JWKS_URL": value,
                ],
                logger: quietLogger
            )
        }
    }

    @Test("a malformed authorize URL fails at startup")
    func malformedAuthorizeURLRejected() async {
        await #expect(throws: SmartConfigError.self) {
            try await SmartConfiguration.from(
                environment: [
                    "SMART_ISSUER": "https://idp.example.com",
                    "SMART_AUTHORIZE_URL": "htp://idp.example.com/auth",
                    "SMART_TOKEN_URL": "https://idp.example.com/token",
                ],
                logger: quietLogger
            )
        }
    }

    /// Previously this fell through to the PEM branch and then to the
    /// "all tokens will fail verification" warning, so the server booted and 401'd
    /// every request instead of refusing to start.
    @Test("a malformed SMART_JWKS_URL fails rather than degrading to no keys")
    func malformedJWKSURLRejected() async {
        await #expect(throws: SmartConfigError.self) {
            try await SmartConfiguration.from(
                environment: [
                    "SMART_ISSUER": "https://idp.example.com",
                    "SMART_JWKS_URL": "not a url",
                ],
                logger: quietLogger
            )
        }
    }

    // ── The second emit site ──────────────────────────────────────────────────

    /// CapabilityStatement carries the same endpoints via the oauth-uris extension.
    /// It is a separate emit site, so it needs its own assertion — a fix applied to
    /// the discovery document alone would leave this one publishing the old value.
    private func fetchMetadataSecurity(_ config: SmartConfiguration?) async throws -> [String: Any]? {
        let router = Router(context: SimingRequestContext.self)
        addMetadataRoutes(to: router, smartConfig: config)
        return try await Application(responder: router.buildResponder()).test(.router) { client in
            try await client.execute(uri: "/metadata", method: .get) { res in
                let cs = try JSONSerialization.jsonObject(with: Data(buffer: res.body)) as? [String: Any]
                let rest = try #require(cs?["rest"] as? [[String: Any]])
                return rest[0]["security"] as? [String: Any]
            }
        }
    }

    @Test("oauth-uris carries the endpoints when they are configured")
    func metadataOAuthURIs() async throws {
        let security = try await fetchMetadataSecurity(
            SmartConfiguration(
                issuer: "https://idp.example.com",
                authorizeURL: "https://idp.example.com/auth",
                tokenURL: "https://idp.example.com/token"
            )
        )
        let ext = try #require(security?["extension"] as? [[String: Any]])
        let inner = try #require(ext[0]["extension"] as? [[String: Any]])
        #expect(inner.contains { $0["url"] as? String == "authorize"
            && $0["valueUri"] as? String == "https://idp.example.com/auth" })
        #expect(inner.contains { $0["url"] as? String == "token"
            && $0["valueUri"] as? String == "https://idp.example.com/token" })
    }

    @Test("oauth-uris is absent rather than empty when an endpoint is empty")
    func metadataOAuthURIsNotEmpty() async throws {
        let security = try await fetchMetadataSecurity(
            SmartConfiguration(
                issuer: "https://idp.example.com",
                authorizeURL: "",
                tokenURL: "https://idp.example.com/token"
            )
        )
        #expect(security?["extension"] == nil)
    }

    @Test("an empty SMART_ISSUER fails rather than silently disabling auth")
    func emptyIssuerFailsClosed() async {
        await #expect(throws: SmartConfigError.self) {
            try await SmartConfiguration.from(
                environment: ["SMART_ISSUER": "  "],
                logger: quietLogger
            )
        }
    }

    @Test("scopes a standalone client requests are all supported")
    func requiredScopes() async throws {
        let obj = try await fetch(SmartConfiguration(issuer: "https://idp.example.com"))
        let scopes = try #require(obj["scopes_supported"] as? [String])
        for scope in ["openid", "fhirUser", "user/*.read", "offline_access"] {
            #expect(scopes.contains(scope))
        }
    }

    // ── Configuration validation ──────────────────────────────────────────────

    /// A logger that discards everything — fromEnvironment logs on every path.
    private var quietLogger: Logger {
        var l = Logger(label: "test")
        l.logLevel = .critical
        return l
    }

    @Test("setting only SMART_AUTHORIZE_URL fails at startup")
    func authorizeWithoutToken() async {
        await #expect(throws: SmartConfigError.self) {
            try await SmartConfiguration.from(
                environment: [
                    "SMART_ISSUER": "https://idp.example.com",
                    "SMART_AUTHORIZE_URL": "https://idp.example.com/auth",
                ],
                logger: quietLogger
            )
        }
    }

    @Test("setting only SMART_TOKEN_URL fails at startup")
    func tokenWithoutAuthorize() async {
        await #expect(throws: SmartConfigError.self) {
            try await SmartConfiguration.from(
                environment: [
                    "SMART_ISSUER": "https://idp.example.com",
                    "SMART_TOKEN_URL": "https://idp.example.com/token",
                ],
                logger: quietLogger
            )
        }
    }

    @Test("setting both endpoints is accepted")
    func bothEndpointsAccepted() async throws {
        let config = try await SmartConfiguration.from(
            environment: [
                "SMART_ISSUER": "https://idp.example.com",
                "SMART_AUTHORIZE_URL": "https://idp.example.com/auth",
                "SMART_TOKEN_URL": "https://idp.example.com/token",
            ],
            logger: quietLogger
        )
        let unwrapped = try #require(config)
        #expect(unwrapped.advertisesAuthorizationServer)
    }

    @Test("setting neither endpoint is accepted as a resource-server-only deployment")
    func neitherEndpointAccepted() async throws {
        let config = try await SmartConfiguration.from(
            environment: ["SMART_ISSUER": "https://idp.example.com"],
            logger: quietLogger
        )
        let unwrapped = try #require(config)
        #expect(!unwrapped.advertisesAuthorizationServer)
    }

    @Test("SMART is disabled entirely when SMART_ISSUER is absent")
    func smartDisabledWithoutIssuer() async throws {
        let config = try await SmartConfiguration.from(
            environment: ["SMART_AUDIENCE": "https://fhir.example.com"],
            logger: quietLogger
        )
        #expect(config == nil)
    }

    @Test("advertisesAuthorizationServer requires both endpoints")
    func bothEndpointsRequired() {
        let base = SmartConfiguration(issuer: "https://idp.example.com")
        #expect(!base.advertisesAuthorizationServer)
        #expect(
            !SmartConfiguration(
                issuer: "https://idp.example.com",
                authorizeURL: "https://idp.example.com/auth"
            ).advertisesAuthorizationServer
        )
        #expect(
            SmartConfiguration(
                issuer: "https://idp.example.com",
                authorizeURL: "https://idp.example.com/auth",
                tokenURL: "https://idp.example.com/token"
            ).advertisesAuthorizationServer
        )
    }

    // ── SMART_PUBLIC_KEY_PEM ─────────────────────────────────────────────────

    /// Throwaway 2048-bit RSA public key, test-only.
    private static let testPEMLiteralEscapes = "-----BEGIN PUBLIC KEY-----\\nMIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEA+DPmtxZNCNw0nveja729\\nqihBurN6DDO4DKBlFjk8Nojl1ZMpUx3obYbdRGWePkzs6jgQY6Xt9PTrIRSC0KG0\\nUm+69mf9UVauTrUPLPWndKY3/g85+6ze5/ptM9iJXE1Ur32RKzopue1Rvl8GbutS\\narPKPUJHasurmaA8N2kmMnNhQ0G16SVRa4jR/D4EzS2r+a3QzRfnuHDQVfeigs/L\\nNcCHnMM3/vhna7vR6MDN43m810OdIkmcqCx2Mh8Hw3n3wXlyVIMb0+0YUrWtI2nd\\nttZJodbJIdNGtPcyl5Gcg5HKJu2fu88aBhxj8IpvLnFgAgDVpYcxe+BqfiNGmUKT\\nqQIDAQAB\\n-----END PUBLIC KEY-----\\n"

    @Test("a PEM with literal \\n escapes (unquoted env file, bash source) still loads")
    func pemWithLiteralEscapes() async throws {
        #expect(Self.testPEMLiteralEscapes.contains("\\n"))
        #expect(!Self.testPEMLiteralEscapes.contains("\n"))
        let config = try await SmartConfiguration.from(
            environment: [
                "SMART_ISSUER": "https://idp.example.com",
                "SMART_PUBLIC_KEY_PEM": Self.testPEMLiteralEscapes,
            ],
            logger: quietLogger
        )
        #expect(config != nil)
    }
}
