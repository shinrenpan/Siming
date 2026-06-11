import Foundation
import Logging

/// Per-IP token-bucket rate limiting configuration.
/// Enabled only when RATE_LIMIT_RPS env var is set and > 0.
public struct RateLimitConfiguration: Sendable {
    public let rps: Double
    public let burst: Int

    public static func from(config: SimingConfig, logger: Logger) -> RateLimitConfiguration? {
        guard let rps = config.rateLimitRPS, rps > 0 else { return nil }
        let burst = config.rateLimitBurst ?? Int(rps * 2)
        let cfg = RateLimitConfiguration(rps: rps, burst: max(burst, 1))
        logger.info("Rate limiting enabled: \(rps) RPS/IP, burst=\(cfg.burst)")
        return cfg
    }
}
