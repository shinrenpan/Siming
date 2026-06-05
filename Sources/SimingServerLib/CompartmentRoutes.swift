import Foundation
import Hummingbird
import Logging
import NIOCore
import SimingCore

private let maxCount = 100
private let fhirJSON = "application/fhir+json"

/// GET /Patient/:patientId/Observation — Patient compartment search.
/// Forces subject=Patient/:patientId; delegates to ObservationStore.search().
public func addCompartmentRoutes(
    to router: Router<BasicRequestContext>,
    observationStore: ObservationStore,
    logger: Logger
) {
    let group = router.group("Patient")

    group.get(":id/Observation") { request, context in
        let patientId = context.parameters.get("id") ?? ""
        let pairs = request.uri.queryParameters.map { (key: $0.key, value: $0.value) }
        if isStrictHandling(request) {
            let bad = unknownParams(in: pairs, known: knownObservationParams)
            if !bad.isEmpty { throw FHIRRouteError.unknownParams(bad) }
        }
        var query = parseObservationQuery(from: pairs)
        query.subject = "Patient/\(patientId)"
        let elements = parseElements(from: pairs)
        let result = try await observationStore.search(query: query)

        let base = selfURL(request)
        let nextURL = result.nextCursor.map { nextPageURL(selfURL: base, cursor: $0, count: query.count) }
        let baseURL = serverBaseURL(request)
        let entries = result.entries.map { e -> (fullUrl: String, json: Data) in
            let json = elements.map { applyElements(e.jsonWithMeta, elements: $0) } ?? e.jsonWithMeta
            return ("\(baseURL)/Observation/\(e.id)", json)
        }
        let bundleData = buildBundleJSON(entries: entries, total: result.total,
                                         selfURL: base, nextURL: nextURL)
        var headers = HTTPFields()
        headers[.contentType] = fhirJSON
        return Response(status: .ok, headers: headers,
                        body: ResponseBody(byteBuffer: ByteBuffer(bytes: bundleData)))
    }

    // POST /Patient/:patientId/Observation/_search — compartment form-encoded search
    group.post(":id/Observation/_search") { request, context in
        let patientId = context.parameters.get("id") ?? ""
        let ct = request.headers[.contentType] ?? ""
        guard ct.contains("application/x-www-form-urlencoded") else {
            throw FHIRRouteError.invalidBody("Content-Type must be application/x-www-form-urlencoded for _search")
        }
        var req = request
        let bodyBuffer = try await req.collectBody(upTo: 1 * 1024 * 1024)
        let urlPairs = request.uri.queryParameters.map { (key: $0.key, value: $0.value) }
        let pairs = urlPairs + parseFormPairs(from: bodyBuffer)
        if isStrictHandling(request) {
            let bad = unknownParams(in: pairs, known: knownObservationParams)
            if !bad.isEmpty { throw FHIRRouteError.unknownParams(bad) }
        }
        var query = parseObservationQuery(from: pairs)
        query.subject = "Patient/\(patientId)"
        let elements = parseElements(from: pairs)
        let result = try await observationStore.search(query: query)

        let base = selfURL(request)
        let nextURL = result.nextCursor.map { nextPageURL(selfURL: base, cursor: $0, count: query.count) }
        let baseURL = serverBaseURL(request)
        let entries = result.entries.map { e -> (fullUrl: String, json: Data) in
            let json = elements.map { applyElements(e.jsonWithMeta, elements: $0) } ?? e.jsonWithMeta
            return ("\(baseURL)/Observation/\(e.id)", json)
        }
        let bundleData = buildBundleJSON(entries: entries, total: result.total,
                                         selfURL: base, nextURL: nextURL)
        var headers = HTTPFields()
        headers[.contentType] = fhirJSON
        return Response(status: .ok, headers: headers,
                        body: ResponseBody(byteBuffer: ByteBuffer(bytes: bundleData)))
    }
}

// ── Helpers ───────────────────────────────────────────────────────────────────

private func selfURL(_ request: Request) -> String {
    let authority = request.head.authority ?? "localhost"
    return "http://\(authority)\(request.uri)"
}

private func nextPageURL(selfURL: String, cursor: ObservationSearchQuery.SearchCursor, count: Int) -> String {
    guard let urlComponents = URLComponents(string: selfURL) else { return selfURL }
    var components = urlComponents
    var items = (components.queryItems ?? []).filter { $0.name != "_cursor" }
    items.append(URLQueryItem(name: "_cursor", value: cursor.encode()))
    if !items.contains(where: { $0.name == "_count" }) {
        items.append(URLQueryItem(name: "_count", value: String(count)))
    }
    components.queryItems = items
    return components.string ?? selfURL
}
