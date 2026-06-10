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

private func buildSmartConfigJSON(config: SmartConfiguration) -> Data {
    var obj: [String: Any] = [
        "issuer": config.issuer,
        "capabilities": [
            "permission-v1",
            "permission-patient",
            "context-standalone-patient",
        ],
        "scopes_supported": [
            "openid", "fhirUser", "launch", "launch/patient",
            "patient/*.read", "patient/*.write",
            "user/*.read", "user/*.write",
            "system/*.read", "system/*.write",
            "offline_access",
        ],
        "response_types_supported": ["code"],
        "token_endpoint_auth_methods_supported": ["private_key_jwt", "client_secret_basic"],
    ]
    if let jwksURL = config.jwksURL {
        obj["jwks_uri"] = jwksURL
    }
    return (try? JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys])) ?? Data()
}
