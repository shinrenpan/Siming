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

        let caps = try #require(obj["capabilities"] as? [String])
        #expect(!caps.contains("launch-standalone"))
        #expect(!caps.contains("client-public"))
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
        #expect(caps.contains("permission-v1"))
    }

    @Test("advertises 'none' auth for PKCE public clients")
    func publicClientAuthMethod() async throws {
        let obj = try await fetch(SmartConfiguration(issuer: "https://idp.example.com"))
        let methods = try #require(obj["token_endpoint_auth_methods_supported"] as? [String])
        #expect(methods.contains("none"))
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
