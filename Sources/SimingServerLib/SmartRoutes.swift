import Foundation
import Hummingbird
import NIOCore

/// GET /.well-known/smart-configuration — SMART App Launch metadata
/// Only registered when SmartConfiguration is non-nil (SMART_ISSUER is set).
public func addSmartRoutes(to router: Router<BasicRequestContext>, config: SmartConfiguration) {
    router.get(".well-known/smart-configuration") { _, _ in
        var headers = HTTPFields()
        headers[.contentType] = "application/json"
        return Response(
            status: .ok, headers: headers,
            body: ResponseBody(byteBuffer: ByteBuffer(bytes: buildSmartConfigJSON(config: config)))
        )
    }
}

// ── Builder ───────────────────────────────────────────────────────────────────

/// Builds the SMART App Launch discovery document.
///
/// Fields describing the *authorization server* are emitted only when both
/// `authorizeURL` and `tokenURL` are configured — see
/// `SmartConfiguration.advertisesAuthorizationServer`. Without them this server
/// is a plain resource server and must not claim to support standalone launch.
func buildSmartConfigJSON(config: SmartConfiguration) -> Data {
    // Resource-server facts only. Everything describing the authorization server —
    // its endpoints, the grants and client authentication it accepts, and the
    // launch flows built on them — is gated below.
    var capabilities = ["permission-v1", "permission-patient"]
    var obj: [String: Any] = [
        "issuer": config.issuer,
        "scopes_supported": [
            "openid", "fhirUser", "launch", "launch/patient",
            "patient/*.read", "patient/*.write",
            "user/*.read", "user/*.write",
            "system/*.read", "system/*.write",
            "offline_access",
        ],
        "response_types_supported": ["code"],
    ]
    if let jwksURL = config.jwksURL {
        obj["jwks_uri"] = jwksURL
    }
    if let server = config.authorizationServer {
        obj["authorization_endpoint"] = server.authorize
        obj["token_endpoint"] = server.token
        obj["code_challenge_methods_supported"] = ["S256"]
        // REQUIRED by SMART App Launch 2.0 once the endpoints are advertised.
        // refresh_token is listed because offline_access is in scopes_supported,
        // and that scope is redeemed through no other grant.
        obj["grant_types_supported"] = ["authorization_code", "refresh_token"]
        // "none" — public clients (native apps) authenticate with PKCE, not a
        // secret. Describes the token endpoint, so it is emitted only alongside it.
        obj["token_endpoint_auth_methods_supported"] = [
            "none", "private_key_jwt", "client_secret_basic",
        ]
        // context-standalone-patient is patient context *in a standalone launch*;
        // it cannot stand without launch-standalone.
        capabilities.append(contentsOf: [
            "launch-standalone", "client-public", "context-standalone-patient",
        ])
    }
    obj["capabilities"] = capabilities
    return (try? JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys])) ?? Data()
}
