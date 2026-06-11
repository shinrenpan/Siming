import Foundation
import HTTPTypes
import Hummingbird
import NIOCore

/// Per-IP token-bucket rate limiting middleware.
/// Client key: first IP in X-Forwarded-For header, or "global" if absent.
/// Exempt paths: /health, /metrics (load balancer probes / Prometheus scrape).
public struct RateLimitMiddleware<Context: RequestContext>: RouterMiddleware {
    let limiter: RateLimiter

    public init(config: RateLimitConfiguration) {
        self.limiter = RateLimiter(config: config)
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

        let key = clientKey(from: request)
        let (allowed, retryAfter) = await limiter.check(key: key)

        guard allowed else {
            return tooManyRequestsResponse(retryAfter: retryAfter)
        }

        return try await next(request, context)
    }

    private func clientKey(from request: Request) -> String {
        guard let forwarded = request.headers[.xForwardedFor] else { return "global" }
        return forwarded.components(separatedBy: ",").first?
            .trimmingCharacters(in: .whitespaces) ?? "global"
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
    private var lastCleanup: Date = Date()
    private let config: RateLimitConfiguration

    init(config: RateLimitConfiguration) {
        self.config = config
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
