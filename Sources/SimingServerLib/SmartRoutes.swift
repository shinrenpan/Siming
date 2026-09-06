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
    var capabilities = [
        "permission-v1",
        "permission-patient",
        "context-standalone-patient",
    ]
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
        // "none" — public clients (native apps) authenticate with PKCE, not a secret.
        "token_endpoint_auth_methods_supported": ["none", "private_key_jwt", "client_secret_basic"],
    ]
    if let jwksURL = config.jwksURL {
        obj["jwks_uri"] = jwksURL
    }
    if let authorizeURL = config.authorizeURL, let tokenURL = config.tokenURL {
        obj["authorization_endpoint"] = authorizeURL
        obj["token_endpoint"] = tokenURL
        obj["code_challenge_methods_supported"] = ["S256"]
        capabilities.append(contentsOf: ["launch-standalone", "client-public"])
    }
    obj["capabilities"] = capabilities
    return (try? JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys])) ?? Data()
}
