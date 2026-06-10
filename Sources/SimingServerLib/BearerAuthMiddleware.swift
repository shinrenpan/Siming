import Foundation
import Hummingbird
import JWTKit
import Logging
import NIOCore

/// SMART on FHIR Resource Server bearer token validation middleware.
/// Validates JWT Bearer tokens against the configured issuer and key set.
/// Paths /health, /metadata, /metrics, /.well-known/smart-configuration are exempt.
public struct BearerAuthMiddleware<Context: RequestContext>: RouterMiddleware {
    let config: SmartConfiguration
    let logger: Logger

    public init(config: SmartConfiguration, logger: Logger) {
        self.config = config
        self.logger = logger
    }

    public func handle(
        _ request: Request,
        context: Context,
        next: (Request, Context) async throws -> Response
    ) async throws -> Response {
        let path = request.uri.path
        switch path {
        case "/health", "/metadata", "/metrics", "/.well-known/smart-configuration":
            return try await next(request, context)
        default: break
        }

        guard let authHeader = request.headers[.authorization],
              authHeader.hasPrefix("Bearer ") else {
            return makeUnauthorized(error: "invalid_token", description: "Bearer token required")
        }

        let token = String(authHeader.dropFirst("Bearer ".count))

        do {
            let payload = try await config.keys.verify(token, as: SMARTClaims.self)

            guard payload.iss.value == config.issuer else {
                return makeUnauthorized(error: "invalid_token", description: "Invalid issuer")
            }

            if let expectedAud = config.audience {
                guard let aud = payload.aud else {
                    return makeUnauthorized(error: "invalid_token", description: "Missing aud claim")
                }
                try aud.verifyIntendedAudience(includes: expectedAud)
            }

            logger.debug(
                "SMART: accepted sub=\(payload.sub?.value ?? "-") scope=\(payload.scope ?? "-")"
            )
        } catch {
            return makeUnauthorized(error: "invalid_token", description: "Token verification failed")
        }

        return try await next(request, context)
    }

    private func makeUnauthorized(error: String, description: String) -> Response {
        let wwwAuth =
            "Bearer realm=\"\(config.issuer)\", error=\"\(error)\", error_description=\"\(description)\""
        var headers = HTTPFields()
        headers[.wwwAuthenticate] = wwwAuth
        headers[.contentType] = "application/fhir+json"
        return Response(
            status: .unauthorized, headers: headers,
            body: ResponseBody(byteBuffer: ByteBuffer(bytes: unauthorizedOutcomeJSON(description: description)))
        )
    }
}

// ── JWT claims ────────────────────────────────────────────────────────────────

private struct SMARTClaims: JWTPayload {
    var iss: IssuerClaim
    var exp: ExpirationClaim
    var sub: SubjectClaim?
    var aud: AudienceClaim?
    var scope: String?
    var fhirUser: String?
    var patient: String?

    func verify(using algorithm: some JWTAlgorithm) throws {
        try exp.verifyNotExpired()
    }
}

// ── OperationOutcome for 401 ──────────────────────────────────────────────────

private func unauthorizedOutcomeJSON(description: String) -> Data {
    let esc = description
        .replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "\"", with: "\\\"")
    return Data(
        """
        {"resourceType":"OperationOutcome","issue":[{"severity":"error","code":"security","diagnostics":"\(esc)"}]}
        """.utf8
    )
}
