import Foundation
import Hummingbird
import Logging
import ModelsR4
import NIOCore
import SimingCore

private let maxCount = 100
private let fhirJSON = "application/fhir+json"
private let maxBodyBytes = 4 * 1024 * 1024  // 4 MB

func addObservationRoutes(
    to router: Router<BasicRequestContext>,
    store: ObservationStore,
    logger: Logger
) {
    let group = router.group("Observation")

    // POST /Observation — create
    group.post { request, _ in
        try requireFHIRContentType(request)
        var req = request
        let bodyBuffer = try await req.collectBody(upTo: maxBodyBytes)
        let obs = try decodeFHIR(Observation.self, from: bodyBuffer)
        let result = try await store.create(obs)
        var headers = HTTPFields()
        headers[.contentType] = fhirJSON
        headers[.eTag]        = "W/\"\(result.versionId)\""
        headers[.location]    = "/Observation/\(result.id)/_history/\(result.versionId)"
        return Response(status: .created, headers: headers,
                        body: ResponseBody(byteBuffer: ByteBuffer(bytes: result.jsonData)))
    }

    // GET /Observation/:id — read
    group.get(":id") { request, context in
        let id = context.parameters.get("id") ?? ""
        let result = try await store.read(id: id)
        var headers = HTTPFields()
        headers[.contentType] = fhirJSON
        headers[.eTag]        = "W/\"\(result.versionId)\""
        return Response(status: .ok, headers: headers,
                        body: ResponseBody(byteBuffer: ByteBuffer(bytes: result.jsonData)))
    }

    // PUT /Observation/:id — update
    group.put(":id") { request, context in
        try requireFHIRContentType(request)
        let id = context.parameters.get("id") ?? ""
        let ifMatch = parseETag(request.headers[.ifMatch])
        var req = request
        let bodyBuffer = try await req.collectBody(upTo: maxBodyBytes)
        let obs = try decodeFHIR(Observation.self, from: bodyBuffer)
        let result = try await store.update(id: id, observation: obs, ifMatch: ifMatch)
        var headers = HTTPFields()
        headers[.contentType] = fhirJSON
        headers[.eTag]        = "W/\"\(result.versionId)\""
        headers[.location]    = "/Observation/\(result.id)/_history/\(result.versionId)"
        return Response(status: .ok, headers: headers,
                        body: ResponseBody(byteBuffer: ByteBuffer(bytes: result.jsonData)))
    }

    // GET /Observation — search
    group.get { request, _ in
        let qp = request.uri.queryParameters
        let subject  = qp["subject"].map(String.init) ?? qp["patient"].map(String.init)
        let code     = qp["code"].map { ObservationSearchQuery.TokenParam.parse(String($0)) }
        let status   = qp["status"].map(String.init)
        let category = qp["category"].map { ObservationSearchQuery.TokenParam.parse(String($0)) }
        let dates    = qp[values: "date"].compactMap { ObservationSearchQuery.DateParam.parse(String($0)) }
        let sort     = ObservationSearchQuery.SortOrder.parse(qp["_sort"].map(String.init) ?? "-_lastUpdated")
        let count    = min(qp["_count"].flatMap { Int($0) } ?? 20, maxCount)
        let cursor   = qp["_cursor"].flatMap { ObservationSearchQuery.SearchCursor.decode(String($0)) }

        let query = ObservationSearchQuery(
            subject: subject, code: code, date: dates,
            status: status, category: category,
            count: count, sort: sort, cursor: cursor)
        let result = try await store.search(query: query)

        let base = selfURL(request)
        let nextURL = result.nextCursor.map { nextPageURL(selfURL: base, cursor: $0, count: query.count) }
        let entries = result.entries.map { (fullUrl: "/Observation/\($0.id)", json: $0.jsonWithMeta) }
        let bundleData = buildBundleJSON(entries: entries, total: result.total,
                                         selfURL: base, nextURL: nextURL)
        var headers = HTTPFields()
        headers[.contentType] = fhirJSON
        return Response(status: .ok, headers: headers,
                        body: ResponseBody(byteBuffer: ByteBuffer(bytes: bundleData)))
    }
}

// ── Helpers ───────────────────────────────────────────────────────────────────

private func requireFHIRContentType(_ request: Request) throws {
    let ct = request.headers[.contentType] ?? ""
    guard ct.contains(fhirJSON) || ct.contains("application/json") else {
        throw FHIRRouteError.unsupportedMediaType
    }
}

private func decodeFHIR<T: Decodable>(_ type: T.Type, from buffer: ByteBuffer) throws -> T {
    let data = Data(buffer.readableBytesView)
    do {
        return try JSONDecoder().decode(type, from: data)
    } catch {
        throw FHIRRouteError.invalidBody(error.localizedDescription)
    }
}

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

private func parseETag(_ raw: String?) -> Int64? {
    guard let raw else { return nil }
    let stripped = raw
        .trimmingCharacters(in: .whitespaces)
        .replacingOccurrences(of: "W/", with: "")
        .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
    return Int64(stripped)
}
