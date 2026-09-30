import Foundation
import Logging

/// Per-IP token-bucket rate limiting configuration.
/// Enabled when rps > 0 (RATE_LIMIT_RPS or security.rateLimit.rps in config.yml).
public struct RateLimitConfiguration: Sendable {
    public let rps: Double
    public let burst: Int
    public let trustedProxies: TrustedProxies

    public init(rps: Double, burst: Int, trustedProxies: TrustedProxies = .none) {
        self.rps = rps
        self.burst = burst
        self.trustedProxies = trustedProxies
    }

    public static func from(config: SimingConfig, logger: Logger) throws -> RateLimitConfiguration? {
        guard let rps = config.rateLimitRPS, rps > 0 else { return nil }
        let burst = config.rateLimitBurst ?? Int(rps * 2)
        let trusted = try TrustedProxies(parsing: config.rateLimitTrustedProxies)
        let cfg = RateLimitConfiguration(rps: rps, burst: max(burst, 1), trustedProxies: trusted)
        logger.info("Rate limiting enabled: \(rps) RPS/IP, burst=\(cfg.burst), trusted proxies=\(trusted.count)")
        return cfg
    }
}
