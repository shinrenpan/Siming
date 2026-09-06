import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import JWTKit
import Logging

/// SMART on FHIR resource-server configuration.
/// Enabled only when SMART_ISSUER env var is set; nil means auth is disabled (pass-through).
public struct SmartConfiguration: Sendable {
    public let issuer: String
    public let audience: String?
    public let jwksURL: String?
    /// SMART `authorization_endpoint` — the paired authorization server, not this server.
    /// Always set together with `tokenURL`; both nil means no authorization server is
    /// advertised and this deployment acts purely as a resource server.
    public let authorizeURL: String?
    /// SMART `token_endpoint`. See `authorizeURL`.
    public let tokenURL: String?
    public let keys: JWTKeyCollection

    public init(
        issuer: String,
        audience: String? = nil,
        jwksURL: String? = nil,
        authorizeURL: String? = nil,
        tokenURL: String? = nil,
        keys: JWTKeyCollection = JWTKeyCollection()
    ) {
        self.issuer = issuer
        self.audience = audience
        self.jwksURL = jwksURL
        self.authorizeURL = authorizeURL
        self.tokenURL = tokenURL
        self.keys = keys
    }

    /// True when both authorization-server endpoints are configured. Gates every
    /// authorization-server claim in the discovery document — advertising
    /// `launch-standalone` without an authorize endpoint would be a false claim.
    public var advertisesAuthorizationServer: Bool {
        authorizeURL != nil && tokenURL != nil
    }

    public static func fromEnvironment(logger: Logger) async throws -> SmartConfiguration? {
        try await from(environment: ProcessInfo.processInfo.environment, logger: logger)
    }

    /// Environment is a parameter so the both-or-neither rule below is reachable
    /// from tests without mutating the process environment.
    static func from(environment: [String: String], logger: Logger) async throws -> SmartConfiguration? {
        guard let issuer = environment["SMART_ISSUER"] else {
            return nil
        }
        let audience = environment["SMART_AUDIENCE"]
        let jwksURL = environment["SMART_JWKS_URL"]
        let authorizeURL = environment["SMART_AUTHORIZE_URL"]
        let tokenURL = environment["SMART_TOKEN_URL"]

        // Both-or-neither. A half-configured pair yields a discovery document that
        // fails client-side decoding far away from the actual misconfiguration,
        // so reject it at startup instead.
        if (authorizeURL == nil) != (tokenURL == nil) {
            throw SmartConfigError.incompleteAuthorizationServer(
                "SMART_AUTHORIZE_URL and SMART_TOKEN_URL must be set together"
            )
        }

        let keys = JWTKeyCollection()

        if let urlString = jwksURL, let url = URL(string: urlString) {
            logger.info("SMART: fetching JWKS from \(urlString)")
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let json = String(data: data, encoding: .utf8) else {
                throw SmartConfigError.invalidJWKS("JWKS response is not valid UTF-8")
            }
            try await keys.add(jwksJSON: json)
        } else if let pem = environment["SMART_PUBLIC_KEY_PEM"] {
            logger.info("SMART: loading RSA public key from SMART_PUBLIC_KEY_PEM")
            let key = try Insecure.RSA.PublicKey(pem: pem)
            await keys.add(rsa: key, digestAlgorithm: .sha256)
        } else {
            logger.warning("SMART: SMART_ISSUER set but no SMART_JWKS_URL or SMART_PUBLIC_KEY_PEM — all tokens will fail verification")
        }

        let audInfo = audience.map { ", audience=\($0)" } ?? ""
        logger.info("SMART: auth enabled, issuer=\(issuer)\(audInfo)")
        if let authorizeURL, let tokenURL {
            logger.info("SMART: advertising authorization server, authorize=\(authorizeURL), token=\(tokenURL)")
        } else {
            logger.info("SMART: no authorization server configured — resource server only")
        }
        return SmartConfiguration(
            issuer: issuer,
            audience: audience,
            jwksURL: jwksURL,
            authorizeURL: authorizeURL,
            tokenURL: tokenURL,
            keys: keys
        )
    }
}

public enum SmartConfigError: Error {
    case invalidJWKS(String)
    case incompleteAuthorizationServer(String)
}
