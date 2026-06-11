import HTTPTypes
import Hummingbird

/// CORS middleware — required for browser-based Inferno / Touchstone testing.
/// OPTIONS preflight → 204 No Content + CORS headers.
/// All other requests → pass through, then append CORS headers to response.
public struct CORSMiddleware<Context: RequestContext>: RouterMiddleware {
    public init() {}

    public func handle(
        _ request: Request,
        context: Context,
        next: (Request, Context) async throws -> Response
    ) async throws -> Response {
        if request.method == .options {
            var headers = HTTPFields()
            addCORSHeaders(origin: request.headers[.origin], to: &headers)
            return Response(status: .noContent, headers: headers)
        }

        var response = try await next(request, context)
        addCORSHeaders(origin: request.headers[.origin], to: &response.headers)
        // FHIR R4 §3.1.0.3 — include fhirVersion in Content-Type for FHIR responses
        if response.headers[.contentType] == "application/fhir+json" {
            response.headers[.contentType] = "application/fhir+json; fhirVersion=4.0"
        }
        return response
    }

    private func addCORSHeaders(origin: String?, to headers: inout HTTPFields) {
        headers[.accessControlAllowOrigin] = origin ?? "*"
        headers[.accessControlAllowMethods] = "GET, POST, PUT, PATCH, DELETE, OPTIONS"
        headers[.accessControlAllowHeaders] =
            "Authorization, Content-Type, Accept, Prefer, " +
            "If-Match, If-None-Match, If-Modified-Since, If-None-Exist, X-Request-ID"
        headers[.accessControlExposeHeaders] =
            "ETag, Location, Content-Location, Last-Modified, X-Request-ID"
        if origin != nil {
            headers[.accessControlAllowCredentials] = "true"
        }
        headers[.accessControlMaxAge] = "86400"
    }
}
