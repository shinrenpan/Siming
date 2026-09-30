import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import JWTKit
import Logging

/// Environment variables that are set-but-empty are indistinguishable from unset in
/// docker-compose, Helm and k8s manifests, where an unset value routinely renders as "".
/// An empty endpoint is exactly the half-built document the both-or-neither rule rejects,
/// so empty is treated as absent everywhere in this file.
private extension String {
    var nonEmptyOrNil: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

/// SMART on FHIR resource-server configuration.
/// Enabled only when SMART_ISSUER env var is set; nil means auth is disabled (pass-through).
public struct SmartConfiguration: Sendable {
    public let issuer: String
    public let audience: String?
    /// Where *this server* fetches the key set from — a container-internal address in
    /// a split-horizon deployment.
    public let jwksURL: String?
    /// What the discovery document publishes as `jwks_uri`, for clients that fetch the
    /// key set themselves. Defaults to `jwksURL`, which is correct whenever one address
    /// reaches the authorization server from both sides. It is not correct in a
    /// container: `http://keycloak:8080/...` resolves for this server and for nobody else.
    public let advertisedJWKSURL: String?
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
        advertisedJWKSURL: String? = nil,
        authorizeURL: String? = nil,
        tokenURL: String? = nil,
        keys: JWTKeyCollection = JWTKeyCollection()
    ) {
        self.issuer = issuer
        self.audience = audience?.nonEmptyOrNil
        self.jwksURL = jwksURL?.nonEmptyOrNil
        // Resolve the fallback here, so the published value is right at every read site
        // rather than at whichever ones remember to apply it.
        self.advertisedJWKSURL = advertisedJWKSURL?.nonEmptyOrNil ?? jwksURL?.nonEmptyOrNil
        self.authorizeURL = authorizeURL?.nonEmptyOrNil
        self.tokenURL = tokenURL?.nonEmptyOrNil
        self.keys = keys
    }

    /// The single derivation of "is an authorization server advertised". Both emit
    /// sites — the discovery document and the CapabilityStatement oauth-uris
    /// extension — must go through this rather than re-deriving the condition, or
    /// tightening the gate here silently leaves them emitting the old value.
    public var authorizationServer: (authorize: String, token: String)? {
        guard let authorizeURL, let tokenURL else { return nil }
        return (authorizeURL, tokenURL)
    }

    /// Convenience over ``authorizationServer``; gates every authorization-server
    /// claim in the discovery document — advertising `launch-standalone` without an
    /// authorize endpoint would be a false claim.
    public var advertisesAuthorizationServer: Bool { authorizationServer != nil }

    /// Every URL here is either fetched by this server or published for a client to
    /// fetch. A typo in one that is only published fails nowhere near the deployment
    /// that caused it — the document is well-formed, the server logs nothing, and only
    /// the client breaks — so reject it at startup like the other misconfigurations.
    private static func validatedURL(_ value: String, _ variable: String) throws -> URL {
        guard let url = URL(string: value),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              url.host?.isEmpty == false
        else {
            throw SmartConfigError.invalidURL("\(variable) is not a valid http(s) URL: \(value)")
        }
        return url
    }

    public static func fromEnvironment(logger: Logger) async throws -> SmartConfiguration? {
        try await from(environment: ProcessInfo.processInfo.environment, logger: logger)
    }

    /// Environment is a parameter so the both-or-neither rule below is reachable
    /// from tests without mutating the process environment.
    static func from(environment: [String: String], logger: Logger) async throws -> SmartConfiguration? {
        guard let rawIssuer = environment["SMART_ISSUER"] else {
            return nil
        }
        // An explicitly empty SMART_ISSUER must not disable auth: that fails open,
        // serving FHIR with no authentication because of a typo. Absent disables;
        // empty is a misconfiguration.
        guard let issuer = rawIssuer.nonEmptyOrNil else {
            throw SmartConfigError.emptyIssuer(
                "SMART_ISSUER is set but empty — unset it to disable SMART, or give it a value"
            )
        }
        // Normalise before the both-or-neither rule, or SMART_AUTHORIZE_URL="" reads
        // as "set" and publishes an empty authorization_endpoint.
        let audience = environment["SMART_AUDIENCE"]?.nonEmptyOrNil
        let jwksURL = environment["SMART_JWKS_URL"]?.nonEmptyOrNil
        let advertisedJWKSURL = environment["SMART_ADVERTISED_JWKS_URL"]?.nonEmptyOrNil
        let authorizeURL = environment["SMART_AUTHORIZE_URL"]?.nonEmptyOrNil
        let tokenURL = environment["SMART_TOKEN_URL"]?.nonEmptyOrNil

        let jwksFetchURL = try jwksURL.map { try validatedURL($0, "SMART_JWKS_URL") }
        _ = try advertisedJWKSURL.map { try validatedURL($0, "SMART_ADVERTISED_JWKS_URL") }
        _ = try authorizeURL.map { try validatedURL($0, "SMART_AUTHORIZE_URL") }
        _ = try tokenURL.map { try validatedURL($0, "SMART_TOKEN_URL") }

        // Both-or-neither. A half-configured pair yields a discovery document that
        // fails client-side decoding far away from the actual misconfiguration,
        // so reject it at startup instead.
        if (authorizeURL == nil) != (tokenURL == nil) {
            throw SmartConfigError.incompleteAuthorizationServer(
                "SMART_AUTHORIZE_URL and SMART_TOKEN_URL must be set together"
            )
        }

        let keys = JWTKeyCollection()

        if let url = jwksFetchURL {
            logger.info("SMART: fetching JWKS from \(url.absoluteString)")
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let json = String(data: data, encoding: .utf8) else {
                throw SmartConfigError.invalidJWKS("JWKS response is not valid UTF-8")
            }
            try await keys.add(jwksJSON: json)
        } else if let pem = environment["SMART_PUBLIC_KEY_PEM"]?.nonEmptyOrNil {
            logger.info("SMART: loading RSA public key from SMART_PUBLIC_KEY_PEM")
            // A PEM never contains a literal backslash-n; one arriving here came through an
            // env file or shell that did not expand the escape (unquoted, or bash `source`).
            let key = try Insecure.RSA.PublicKey(pem: pem.replacingOccurrences(of: "\\n", with: "\n"))
            await keys.add(rsa: key, digestAlgorithm: .sha256)
        } else {
            logger.warning("SMART: SMART_ISSUER set but no SMART_JWKS_URL or SMART_PUBLIC_KEY_PEM — all tokens will fail verification")
        }

        let audInfo = audience.map { ", audience=\($0)" } ?? ""
        logger.info("SMART: auth enabled, issuer=\(issuer)\(audInfo)")
        if let advertisedJWKSURL, advertisedJWKSURL != jwksURL {
            logger.info("SMART: advertising jwks_uri=\(advertisedJWKSURL) (fetching from \(jwksURL ?? "-"))")
        }
        if let authorizeURL, let tokenURL {
            logger.info("SMART: advertising authorization server, authorize=\(authorizeURL), token=\(tokenURL)")
        } else {
            logger.info("SMART: no authorization server configured — resource server only")
        }
        return SmartConfiguration(
            issuer: issuer,
            audience: audience,
            jwksURL: jwksURL,
            advertisedJWKSURL: advertisedJWKSURL,
            authorizeURL: authorizeURL,
            tokenURL: tokenURL,
            keys: keys
        )
    }
}

public enum SmartConfigError: Error {
    case invalidJWKS(String)
    case incompleteAuthorizationServer(String)
    case emptyIssuer(String)
    case invalidURL(String)
}
