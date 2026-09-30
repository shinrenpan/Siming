import Foundation
import HTTPTypes
import Hummingbird
import NIOCore

/// Per-IP token-bucket rate limiting middleware.
/// Client key: see `rateLimitClientKey` — the TCP peer, or the X-Forwarded-For entry a
/// trusted proxy vouches for.
/// Exempt paths: /health, /metrics (load balancer probes / Prometheus scrape).
public struct RateLimitMiddleware<Context: RemoteAddressRequestContext>: RouterMiddleware {
    let limiter: RateLimiter
    let trustedProxies: TrustedProxies

    public init(config: RateLimitConfiguration) {
        self.limiter = RateLimiter(config: config)
        self.trustedProxies = config.trustedProxies
    }

    public func handle(
        _ request: Request,
        context: Context,
        next: (Request, Context) async throws -> Response
    ) async throws -> Response {
        switch request.uri.path {
        case "/health", "/metrics":
            return try await next(request, context)
        default: break
        }

        let forwardedFor = request.headers[values: .xForwardedFor]
        if trustedProxies.isEmpty, !forwardedFor.isEmpty, await limiter.claimForwardingWarning() {
            // Before 1.4 this header was the key. A proxied deployment upgraded without
            // RATE_LIMIT_TRUSTED_PROXIES now puts every client in the proxy's bucket.
            context.logger.warning("""
                Rate limiting ignores X-Forwarded-For: no trusted proxies are configured, so \
                clients are keyed by TCP peer. Behind a reverse proxy, set \
                RATE_LIMIT_TRUSTED_PROXIES to its address or every client shares one bucket.
                """)
        }
        let key = rateLimitClientKey(
            peer: context.remoteAddress?.ipAddress,
            forwardedFor: forwardedFor,
            trusted: trustedProxies
        )
        let (allowed, retryAfter) = await limiter.check(key: key)

        guard allowed else {
            return tooManyRequestsResponse(retryAfter: retryAfter)
        }

        return try await next(request, context)
    }

    private func tooManyRequestsResponse(retryAfter: Int) -> Response {
        var headers = HTTPFields()
        headers[.retryAfter] = "\(retryAfter)"
        headers[.contentType] = "application/fhir+json"
        return Response(
            status: .tooManyRequests,
            headers: headers,
            body: ResponseBody(byteBuffer: ByteBuffer(bytes: throttledOutcomeJSON()))
        )
    }
}

// ── Token bucket ──────────────────────────────────────────────────────────────

actor RateLimiter {
    private struct Bucket {
        var tokens: Double
        var lastRefill: Date
    }

    private var buckets: [String: Bucket] = [:]
    private var forwardingWarned = false
    private var lastCleanup: Date = Date()
    private let config: RateLimitConfiguration

    init(config: RateLimitConfiguration) {
        self.config = config
    }

    /// True exactly once per process.
    func claimForwardingWarning() -> Bool {
        defer { forwardingWarned = true }
        return !forwardingWarned
    }

    func check(key: String) -> (allowed: Bool, retryAfter: Int) {
        let now = Date()
        periodicCleanup(now: now)

        var bucket = buckets[key] ?? Bucket(tokens: Double(config.burst), lastRefill: now)

        let elapsed = now.timeIntervalSince(bucket.lastRefill)
        bucket.tokens = min(Double(config.burst), bucket.tokens + elapsed * config.rps)
        bucket.lastRefill = now

        if bucket.tokens >= 1.0 {
            bucket.tokens -= 1.0
            buckets[key] = bucket
            return (true, 0)
        }

        buckets[key] = bucket
        let wait = Int(ceil((1.0 - bucket.tokens) / config.rps))
        return (false, max(1, wait))
    }

    private func periodicCleanup(now: Date) {
        guard now.timeIntervalSince(lastCleanup) > 60 else { return }
        let ttl = Double(config.burst) / config.rps * 2
        let cutoff = now.addingTimeInterval(-ttl)
        buckets = buckets.filter { $0.value.lastRefill > cutoff }
        lastCleanup = now
    }
}

// ── OperationOutcome for 429 ──────────────────────────────────────────────────

private func throttledOutcomeJSON() -> Data {
    Data("""
    {"resourceType":"OperationOutcome","issue":[{"severity":"error","code":"throttled","diagnostics":"Too many requests — please slow down and retry after the indicated delay."}]}
    """.utf8)
}

// ── X-Forwarded-For header name (not in swift-http-types predefined set) ─────

extension HTTPField.Name {
    static var xForwardedFor: Self { Self("x-forwarded-for")! }
}
