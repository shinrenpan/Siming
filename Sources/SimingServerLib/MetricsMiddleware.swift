import Foundation
import HTTPTypes
import Hummingbird
import Logging
import Metrics

private let xRequestIDName = HTTPField.Name("X-Request-ID")!

private let fhirResourceTypes: Set<String> = [
    "Patient", "Observation", "Encounter", "Condition", "Medication",
    "MedicationRequest", "DiagnosticReport", "Procedure", "AllergyIntolerance",
    "Immunization", "ServiceRequest", "Practitioner", "Organization", "Location",
]

public struct MetricsMiddleware<Context: RequestContext>: RouterMiddleware {
    public init() {}

    public func handle(
        _ request: Request,
        context: Context,
        next: (Request, Context) async throws -> Response
    ) async throws -> Response {
        let requestId = request.headers[xRequestIDName] ?? UUID().uuidString.lowercased()
        let path = normalizePath(request.uri.path)
        let method = "\(request.method)"

        var logger = context.logger
        logger[metadataKey: "requestId"] = "\(requestId)"
        logger.info("→ \(method) \(request.uri.path)")

        let start = Date()
        do {
            var response = try await next(request, context)
            let elapsed = Date().timeIntervalSince(start)
            let status = "\(response.status.code)"

            logger.info("← \(status) \(method) \(path)", metadata: ["ms": "\(Int(elapsed * 1000))"])
            record(method: method, path: path, status: status, seconds: elapsed)

            response.headers[xRequestIDName] = requestId
            return response
        } catch {
            let elapsed = Date().timeIntervalSince(start)
            logger.error("← error \(method) \(path): \(error)", metadata: ["ms": "\(Int(elapsed * 1000))"])
            record(method: method, path: path, status: "500", seconds: elapsed)
            throw error
        }
    }

    private func record(method: String, path: String, status: String, seconds: Double) {
        Counter(label: "http_requests_total", dimensions: [
            ("method", method), ("path", path), ("status", status),
        ]).increment()
        Timer(label: "http_request_duration_seconds", dimensions: [
            ("method", method), ("path", path),
        ]).recordSeconds(seconds)
    }

    // /Patient/abc/_history/1 → /Patient/:id/_history/:vid
    private func normalizePath(_ path: String) -> String {
        let parts = path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        var result: [String] = []
        for (i, part) in parts.enumerated() {
            if i > 0 && fhirResourceTypes.contains(parts[i - 1]) {
                result.append(":id")
            } else if i > 1 && parts[i - 1] == "_history" {
                result.append(":vid")
            } else {
                result.append(part)
            }
        }
        return "/" + result.joined(separator: "/")
    }
}
