import Foundation
import Hummingbird
import NIOCore

private let jsonFormats: Set<String> = [
    "json", "application/json", "application/fhir+json", "text/json",
]

private let fhirJSON = "application/fhir+json"

private let unsupportedFormatBody = Data("""
{"resourceType":"OperationOutcome","issue":[{"severity":"error","code":"not-supported",\
"diagnostics":"Unsupported _format value; this server only supports application/fhir+json"}]}
""".utf8)

/// Validates the FHIR _format query parameter on every request.
/// If _format is present and not a JSON variant, returns 406 Not Acceptable.
public struct FormatMiddleware<Context: RequestContext>: RouterMiddleware {
    public init() {}

    public func handle(
        _ request: Request,
        context: Context,
        next: (Request, Context) async throws -> Response
    ) async throws -> Response {
        if let fmt = request.uri.queryParameters["_format"].map(String.init) {
            guard jsonFormats.contains(fmt.lowercased()) else {
                var headers = HTTPFields()
                headers[.contentType] = fhirJSON
                return Response(
                    status: .notAcceptable,
                    headers: headers,
                    body: ResponseBody(byteBuffer: ByteBuffer(bytes: unsupportedFormatBody))
                )
            }
        }
        return try await next(request, context)
    }
}
