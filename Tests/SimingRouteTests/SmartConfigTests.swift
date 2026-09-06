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
        let router = Router<BasicRequestContext>()
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

    // ── The second emit site ──────────────────────────────────────────────────

    /// CapabilityStatement carries the same endpoints via the oauth-uris extension.
    /// It is a separate emit site, so it needs its own assertion — a fix applied to
    /// the discovery document alone would leave this one publishing the old value.
    private func fetchMetadataSecurity(_ config: SmartConfiguration?) async throws -> [String: Any]? {
        let router = Router<BasicRequestContext>()
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
}
