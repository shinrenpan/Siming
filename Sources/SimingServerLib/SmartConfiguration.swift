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
    public let keys: JWTKeyCollection

    public static func fromEnvironment(logger: Logger) async throws -> SmartConfiguration? {
        guard let issuer = ProcessInfo.processInfo.environment["SMART_ISSUER"] else {
            return nil
        }
        let audience = ProcessInfo.processInfo.environment["SMART_AUDIENCE"]
        let jwksURL = ProcessInfo.processInfo.environment["SMART_JWKS_URL"]
        let keys = JWTKeyCollection()

        if let urlString = jwksURL, let url = URL(string: urlString) {
            logger.info("SMART: fetching JWKS from \(urlString)")
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let json = String(data: data, encoding: .utf8) else {
                throw SmartConfigError.invalidJWKS("JWKS response is not valid UTF-8")
            }
            try await keys.add(jwksJSON: json)
        } else if let pem = ProcessInfo.processInfo.environment["SMART_PUBLIC_KEY_PEM"] {
            logger.info("SMART: loading RSA public key from SMART_PUBLIC_KEY_PEM")
            let key = try Insecure.RSA.PublicKey(pem: pem)
            await keys.add(rsa: key, digestAlgorithm: .sha256)
        } else {
            logger.warning("SMART: SMART_ISSUER set but no SMART_JWKS_URL or SMART_PUBLIC_KEY_PEM — all tokens will fail verification")
        }

        let audInfo = audience.map { ", audience=\($0)" } ?? ""
        logger.info("SMART: auth enabled, issuer=\(issuer)\(audInfo)")
        return SmartConfiguration(issuer: issuer, audience: audience, jwksURL: jwksURL, keys: keys)
    }
}

public enum SmartConfigError: Error {
    case invalidJWKS(String)
}
