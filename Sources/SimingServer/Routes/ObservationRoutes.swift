import Foundation
import HTTPTypes
import Hummingbird
import Logging
import ModelsR4
import NIOCore
import SimingCore

private let maxCount = 100
private let fhirJSON = "application/fhir+json"
private let maxBodyBytes = 4 * 1024 * 1024  // 4 MB
private let ifNoneExistHeader = HTTPField.Name("If-None-Exist")!

func addObservationRoutes(
    to router: Router<BasicRequestContext>,
    store: ObservationStore,
    logger: Logger
) {
    let group = router.group("Observation")

    // POST /Observation — create (with optional If-None-Exist conditional create)
    group.post { request, _ in
        try requireFHIRContentType(request)
        var req = request
        let bodyBuffer = try await req.collectBody(upTo: maxBodyBytes)
        let obs = try decodeFHIR(Observation.self, from: bodyBuffer)

        if let ifNoneExist = request.headers[ifNoneExistHeader] {
            let pairs = parseQueryString(ifNoneExist)
            var checkQuery = parseObservationQuery(from: pairs)
            checkQuery.count = 2
            checkQuery.totalMode = .none
            checkQuery.cursor = nil
            let matches = try await store.search(query: checkQuery)
            if matches.entries.count > 1 {
                throw FHIRServerError.multipleMatches(resourceType: "Observation")
            }
            if let existing = matches.entries.first {
                var headers = HTTPFields()
                headers[.contentType]  = fhirJSON
                headers[.eTag]         = "W/\"\(existing.versionId)\""
                headers[.lastModified] = httpDate(existing.lastUpdated)
                headers[.location]     = "/Observation/\(existing.id)/_history/\(existing.versionId)"
                return Response(status: .ok, headers: headers,
                                body: ResponseBody(byteBuffer: ByteBuffer(bytes: existing.jsonWithMeta)))
            }
            // 0 matches — fall through to normal create
        }

        let result = try await store.create(obs)
        var headers = HTTPFields()
        headers[.contentType]  = fhirJSON
        headers[.eTag]         = "W/\"\(result.versionId)\""
        headers[.lastModified] = httpDate(result.lastUpdated)
        headers[.location]     = "/Observation/\(result.id)/_history/\(result.versionId)"
        return Response(status: .created, headers: headers,
                        body: ResponseBody(byteBuffer: ByteBuffer(bytes: result.jsonData)))
    }

    // PUT /Observation?<search> — conditional update (no id in URL)
    group.put { request, _ in
        try requireFHIRContentType(request)
        let qpPairs = request.uri.queryParameters.map { (key: $0.key, value: $0.value) }
        guard !qpPairs.isEmpty else {
            throw FHIRRouteError.invalidBody("PUT /Observation requires search parameters for conditional update")
        }
        var req = request
        let bodyBuffer = try await req.collectBody(upTo: maxBodyBytes)
        let obs = try decodeFHIR(Observation.self, from: bodyBuffer)
        let ifMatch = parseETag(request.headers[.ifMatch])

        var checkQuery = parseObservationQuery(from: qpPairs)
        checkQuery.count = 2
        checkQuery.totalMode = .none
        checkQuery.cursor = nil
        let matches = try await store.search(query: checkQuery)

        switch matches.entries.count {
        case 0:
            let result = try await store.create(obs)
            var headers = HTTPFields()
            headers[.contentType]  = fhirJSON
            headers[.eTag]         = "W/\"\(result.versionId)\""
            headers[.lastModified] = httpDate(result.lastUpdated)
            headers[.location]     = "/Observation/\(result.id)/_history/\(result.versionId)"
            return Response(status: .created, headers: headers,
                            body: ResponseBody(byteBuffer: ByteBuffer(bytes: result.jsonData)))
        case 1:
            let existingId = matches.entries[0].id
            let result = try await store.update(id: existingId, observation: obs, ifMatch: ifMatch)
            var headers = HTTPFields()
            headers[.contentType]  = fhirJSON
            headers[.eTag]         = "W/\"\(result.versionId)\""
            headers[.lastModified] = httpDate(result.lastUpdated)
            headers[.location]     = "/Observation/\(result.id)/_history/\(result.versionId)"
            return Response(status: .ok, headers: headers,
                            body: ResponseBody(byteBuffer: ByteBuffer(bytes: result.jsonData)))
        default:
            throw FHIRServerError.multipleMatches(resourceType: "Observation")
        }
    }

    // GET /Observation/:id/_history/:vid — vread
    group.get(":id/_history/:vid") { request, context in
        let id = context.parameters.get("id") ?? ""
        guard let vid = context.parameters.get("vid").flatMap(Int64.init) else {
            throw FHIRRouteError.invalidBody("_history version id must be an integer")
        }
        let result = try await store.vread(id: id, versionId: vid)
        if let r = conditionalResponse(request: request, versionId: result.versionId, lastUpdated: result.lastUpdated) { return r }
        var headers = HTTPFields()
        headers[.contentType]  = fhirJSON
        headers[.eTag]         = "W/\"\(result.versionId)\""
        headers[.lastModified] = httpDate(result.lastUpdated)
        return Response(status: .ok, headers: headers,
                        body: ResponseBody(byteBuffer: ByteBuffer(bytes: result.jsonData)))
    }

    // GET /Observation/_history — type-level history; optional _since and _count
    group.get("_history") { request, _ in
        let qp = request.uri.queryParameters
        let since: Date? = qp["_since"].flatMap { parseFHIRInstant(String($0)) }
        let count = min(qp["_count"].flatMap { Int($0) } ?? 50, maxCount)
        let entries = try await store.typeHistory(since: since, count: count)
        let authority = request.head.authority ?? "localhost"
        let baseURL = "http://\(authority)"
        let bundleData = buildHistoryBundleJSON(entries: entries, resourceType: "Observation", baseURL: baseURL)
        var headers = HTTPFields()
        headers[.contentType] = fhirJSON
        return Response(status: .ok, headers: headers,
                        body: ResponseBody(byteBuffer: ByteBuffer(bytes: bundleData)))
    }

    // GET /Observation/:id/_history — instance history
    group.get(":id/_history") { request, context in
        let id = context.parameters.get("id") ?? ""
        let entries = try await store.history(id: id)
        let authority = request.head.authority ?? "localhost"
        let baseURL = "http://\(authority)"
        let bundleData = buildHistoryBundleJSON(
            entries: entries, resourceType: "Observation", baseURL: baseURL)
        var headers = HTTPFields()
        headers[.contentType] = fhirJSON
        return Response(status: .ok, headers: headers,
                        body: ResponseBody(byteBuffer: ByteBuffer(bytes: bundleData)))
    }

    // GET /Observation/:id — read
    group.get(":id") { request, context in
        let id = context.parameters.get("id") ?? ""
        let result = try await store.read(id: id)
        if let r = conditionalResponse(request: request, versionId: result.versionId, lastUpdated: result.lastUpdated) { return r }
        var headers = HTTPFields()
        headers[.contentType]  = fhirJSON
        headers[.eTag]         = "W/\"\(result.versionId)\""
        headers[.lastModified] = httpDate(result.lastUpdated)
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
        headers[.contentType]  = fhirJSON
        headers[.eTag]         = "W/\"\(result.versionId)\""
        headers[.lastModified] = httpDate(result.lastUpdated)
        headers[.location]     = "/Observation/\(result.id)/_history/\(result.versionId)"
        return Response(status: .ok, headers: headers,
                        body: ResponseBody(byteBuffer: ByteBuffer(bytes: result.jsonData)))
    }

    // DELETE /Observation/:id — logical delete
    group.delete(":id") { request, context in
        let id = context.parameters.get("id") ?? ""
        let ifMatch = parseETag(request.headers[.ifMatch])
        let result = try await store.delete(id: id, ifMatch: ifMatch)
        var headers = HTTPFields()
        headers[.eTag]         = "W/\"\(result.versionId)\""
        headers[.lastModified] = httpDate(result.lastUpdated)
        return Response(status: .noContent, headers: headers, body: .init())
    }

    // GET /Observation — search
    group.get { request, _ in
        let pairs = request.uri.queryParameters.map { (key: $0.key, value: $0.value) }
        let query = parseObservationQuery(from: pairs)
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

    // POST /Observation/_search — form-encoded search (FHIR R4 §3.1.1.7)
    group.post("_search") { request, _ in
        let ct = request.headers[.contentType] ?? ""
        guard ct.contains("application/x-www-form-urlencoded") else {
            throw FHIRRouteError.invalidBody("Content-Type must be application/x-www-form-urlencoded for _search")
        }
        var req = request
        let bodyBuffer = try await req.collectBody(upTo: maxBodyBytes)
        let pairs = parseFormPairs(from: bodyBuffer)
        let query = parseObservationQuery(from: pairs)
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

// ── Query parser (shared by GET and POST /_search) ────────────────────────────

func parseObservationQuery(from pairs: some Collection<(key: Substring, value: Substring)>) -> ObservationSearchQuery {
    func first(_ key: String) -> Substring? {
        pairs.first(where: { $0.key == key[...] })?.value
    }
    func all(_ key: String) -> [Substring] {
        pairs.filter { $0.key == key[...] }.map { $0.value }
    }

    let subject       = first("subject").map(String.init) ?? first("patient").map(String.init)
    let code          = first("code").map     { ObservationSearchQuery.TokenParam.parseList(String($0)) } ?? []
    let codeNot       = first("code:not").map { ObservationSearchQuery.TokenParam.parseList(String($0)) } ?? []
    let status        = first("status").map   { String($0).split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) } } ?? []
    let statusNot     = first("status:not").map { String($0).split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) } } ?? []
    let category      = first("category").map { ObservationSearchQuery.TokenParam.parseList(String($0)) } ?? []
    let categoryNot   = first("category:not").map { ObservationSearchQuery.TokenParam.parseList(String($0)) } ?? []
    let identifier    = first("identifier").map { ObservationSearchQuery.IdentifierParam.parseList(String($0)) } ?? []
    let encounter     = first("encounter").map(String.init)
    let performer     = first("performer").map(String.init)
    let componentCode = first("component-code").map { ObservationSearchQuery.TokenParam.parseList(String($0)) } ?? []
    let valueQuantity = first("value-quantity").map { ObservationSearchQuery.QuantityParam.parseList(String($0)) } ?? []
    let dates         = all("date").compactMap { ObservationSearchQuery.DateParam.parse(String($0)) }
    let id            = first("_id").map {
        String($0).split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }
    } ?? []
    let lastUpdated   = all("_lastUpdated").compactMap { ObservationSearchQuery.DateParam.parse(String($0)) }
    let sort          = ObservationSearchQuery.SortOrder.parse(first("_sort").map(String.init) ?? "-_lastUpdated")
    let count         = min(first("_count").flatMap { Int($0) } ?? 20, maxCount)
    let cursor        = first("_cursor").flatMap { ObservationSearchQuery.SearchCursor.decode(String($0)) }
    let totalMode     = ObservationSearchQuery.TotalMode.parse(first("_total").map(String.init))
    var missing: [String: Bool] = [:]
    for p in ["subject","patient","code","status","category","date","value-quantity",
              "identifier","encounter","performer","component-code"] {
        if let v = first("\(p):missing").map(String.init) {
            if v == "true" { missing[p] = true } else if v == "false" { missing[p] = false }
        }
    }
    return ObservationSearchQuery(
        subject: subject, code: code, codeNot: codeNot, date: dates,
        status: status, statusNot: statusNot,
        category: category, categoryNot: categoryNot,
        identifier: identifier, encounter: encounter, performer: performer,
        componentCode: componentCode, valueQuantity: valueQuantity,
        id: id, lastUpdated: lastUpdated, missing: missing,
        totalMode: totalMode, count: count, sort: sort, cursor: cursor)
}

// ── Helpers ───────────────────────────────────────────────────────────────────

private func conditionalResponse(request: Request, versionId: Int64, lastUpdated: Date) -> Response? {
    let etag = "W/\"\(versionId)\""
    if let inm = request.headers[.ifNoneMatch] {
        let tag = inm.trimmingCharacters(in: .whitespaces)
        guard tag != etag && tag != "*" else {
            var h = HTTPFields()
            h[.eTag]         = etag
            h[.lastModified] = httpDate(lastUpdated)
            return Response(status: .notModified, headers: h, body: .init())
        }
        return nil
    }
    if let ims = request.headers[.ifModifiedSince],
       let since = parseHTTPDate(ims) {
        let truncated = Date(timeIntervalSince1970: lastUpdated.timeIntervalSince1970.rounded(.down))
        if truncated <= since {
            var h = HTTPFields()
            h[.eTag]         = etag
            h[.lastModified] = httpDate(lastUpdated)
            return Response(status: .notModified, headers: h, body: .init())
        }
    }
    return nil
}

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
