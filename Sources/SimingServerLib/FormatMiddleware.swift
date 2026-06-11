import Foundation
import Hummingbird
import NIOCore

private let jsonMediaTypes: Set<String> = [
    "*/*", "application/*", "json", "application/json", "application/fhir+json", "text/json",
]

private let fhirJSON = "application/fhir+json"

private let notAcceptableBody = Data("""
{"resourceType":"OperationOutcome","issue":[{"severity":"error","code":"not-supported",\
"diagnostics":"This server only supports application/fhir+json. Use Accept: application/fhir+json or _format=application/fhir+json."}]}
""".utf8)

/// Validates `_format` query param and `Accept` header on every request.
/// Returns 406 Not Acceptable when neither accepts JSON.
public struct FormatMiddleware<Context: RequestContext>: RouterMiddleware {
    public init() {}

    public func handle(
        _ request: Request,
        context: Context,
        next: (Request, Context) async throws -> Response
    ) async throws -> Response {
        // _format takes precedence over Accept (FHIR R4 §3.1.0.1)
        if let fmt = request.uri.queryParameters["_format"].map(String.init) {
            guard jsonMediaTypes.contains(fmt.lowercased()) else {
                return notAcceptableResponse()
            }
        } else if let accept = request.headers[.accept] {
            guard acceptsJSON(accept) else {
                return notAcceptableResponse()
            }
        }
        return try await next(request, context)
    }

    private func notAcceptableResponse() -> Response {
        var headers = HTTPFields()
        headers[.contentType] = fhirJSON
        return Response(
            status: .notAcceptable,
            headers: headers,
            body: ResponseBody(byteBuffer: ByteBuffer(bytes: notAcceptableBody))
        )
    }
}

/// Returns true when the Accept header value includes at least one JSON-compatible media type.
private func acceptsJSON(_ accept: String) -> Bool {
    accept.split(separator: ",").contains { part in
        let mediaType = part.split(separator: ";").first?
            .trimmingCharacters(in: .whitespaces).lowercased() ?? ""
        return jsonMediaTypes.contains(mediaType)
    }
}
