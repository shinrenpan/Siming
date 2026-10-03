import Foundation
import HTTPTypes
import Hummingbird
import Logging
import ModelsR4
import NIOCore
import SimingCore

private let qrMaxCount = 100
private let qrFhirJSON = "application/fhir+json"
private let qrMaxBodyBytes = 4 * 1024 * 1024
private let qrIfNoneExistHeader = HTTPField.Name("If-None-Exist")!
private let qrPreferHeader = HTTPField.Name("Prefer")!

let knownQuestionnaireResponseParams: Set<String> = [
    "status", "identifier", "questionnaire", "authored",
    "subject", "patient", "author", "encounter", "source", "based-on", "part-of", "item-subject",
    "status:not", "identifier:not",
    "_id", "_lastUpdated", "_sort", "_count", "_cursor", "_total",
    "_elements", "_format", "_summary", "_include", "_revinclude",
]

public func addQuestionnaireResponseRoutes(
    to router: Router<SimingRequestContext>,
    store: QuestionnaireResponseStore,
    logger: Logger
) {
    let group = router.group("QuestionnaireResponse")

    // POST /QuestionnaireResponse — create
    group.post { request, _ in
        try qrRequireFHIRContentType(request)
        let preferReturn = parsePreferReturn(request.headers[qrPreferHeader])
        var req = request
        let bodyBuffer = try await req.collectBody(upTo: qrMaxBodyBytes)
        try validateResourceType("QuestionnaireResponse", from: Data(bodyBuffer.readableBytesView))
        let questionnaireResponse = try qrDecodeFHIR(QuestionnaireResponse.self, from: bodyBuffer)

        if let ifNoneExist = request.headers[qrIfNoneExistHeader] {
            let pairs = parseQueryString(ifNoneExist)
            var checkQuery = try parseQuestionnaireResponseQuery(from: pairs)
            checkQuery.count = 2; checkQuery.totalMode = .none; checkQuery.cursor = nil
            let matches = try await store.search(query: checkQuery)
            if matches.entries.count > 1 {
                throw FHIRServerError.multipleMatches(resourceType: "QuestionnaireResponse")
            }
            if let existing = matches.entries.first {
                var headers = HTTPFields()
                headers[.contentType]  = qrFhirJSON
                headers[.eTag]         = "W/\"\(existing.versionId)\""
                headers[.lastModified] = httpDate(existing.lastUpdated)
                headers[.location] = "\(serverBaseURL(request))/QuestionnaireResponse/\(existing.id)/_history/\(existing.versionId)"
                return Response(status: .ok, headers: headers,
                                body: preferBody(preferReturn, resource: existing.jsonWithMeta))
            }
        }

        let result = try await store.create(questionnaireResponse)
        var headers = HTTPFields()
        headers[.contentType]  = qrFhirJSON
        headers[.eTag]         = "W/\"\(result.versionId)\""
        headers[.lastModified] = httpDate(result.lastUpdated)
        headers[.location] = "\(serverBaseURL(request))/QuestionnaireResponse/\(result.id)/_history/\(result.versionId)"
        return Response(status: .created, headers: headers,
                        body: preferBody(preferReturn, resource: result.jsonData))
    }

    // PUT /QuestionnaireResponse?<search> — conditional update
    group.put { request, _ in
        try qrRequireFHIRContentType(request)
        let preferReturn = parsePreferReturn(request.headers[qrPreferHeader])
        let qpPairs = request.uri.queryParameters.map { (key: $0.key, value: $0.value) }
        guard !qpPairs.isEmpty else {
            throw FHIRRouteError.invalidBody("PUT /QuestionnaireResponse requires search parameters for conditional update")
        }
        var req = request
        let bodyBuffer = try await req.collectBody(upTo: qrMaxBodyBytes)
        try validateResourceType("QuestionnaireResponse", from: Data(bodyBuffer.readableBytesView))
        let questionnaireResponse = try qrDecodeFHIR(QuestionnaireResponse.self, from: bodyBuffer)
        let ifMatch = qrParseETag(request.headers[.ifMatch])

        var checkQuery = try parseQuestionnaireResponseQuery(from: qpPairs)
        checkQuery.count = 2; checkQuery.totalMode = .none; checkQuery.cursor = nil
        let matches = try await store.search(query: checkQuery)

        switch matches.entries.count {
        case 0:
            let result = try await store.create(questionnaireResponse)
            var headers = HTTPFields()
            headers[.contentType]  = qrFhirJSON
            headers[.eTag]         = "W/\"\(result.versionId)\""
            headers[.lastModified] = httpDate(result.lastUpdated)
            headers[.location] = "\(serverBaseURL(request))/QuestionnaireResponse/\(result.id)/_history/\(result.versionId)"
            return Response(status: .created, headers: headers,
                            body: preferBody(preferReturn, resource: result.jsonData))
        case 1:
            let existingId = matches.entries[0].id
            let result = try await store.update(id: existingId, questionnaireResponse: questionnaireResponse, ifMatch: ifMatch)
            var headers = HTTPFields()
            headers[.contentType]  = qrFhirJSON
            headers[.eTag]         = "W/\"\(result.versionId)\""
            headers[.lastModified] = httpDate(result.lastUpdated)
            headers[.location] = "\(serverBaseURL(request))/QuestionnaireResponse/\(result.id)/_history/\(result.versionId)"
            return Response(status: .ok, headers: headers,
                            body: preferBody(preferReturn, resource: result.jsonData))
        default:
            throw FHIRServerError.multipleMatches(resourceType: "QuestionnaireResponse")
        }
    }

    // GET /QuestionnaireResponse/:id — read
    group.get(":id") { request, context in
        let id = context.parameters.get("id") ?? ""
        let result = try await store.read(id: id)
        if let earlyResponse = qrConditionalResponse(request: request, versionId: result.versionId, lastUpdated: result.lastUpdated) {
            return earlyResponse
        }
        let pairs = request.uri.queryParameters.map { (key: $0.key, value: $0.value) }
        let elements = parseElements(from: pairs)
        let summary  = parseSummary(from: pairs)
        var json = result.jsonData
        if let s = summary, s != .false { json = applySummary(json, mode: s, summaryFields: questionnaireResponseSummaryFields) }
        if let elems = elements { json = applyElements(json, elements: elems) }
        var headers = HTTPFields()
        headers[.contentType]  = qrFhirJSON
        headers[.eTag]         = "W/\"\(result.versionId)\""
        headers[.lastModified] = httpDate(result.lastUpdated)
        headers[.contentLocation] = contentLocation(request, versionId: result.versionId)
        return Response(status: .ok, headers: headers,
                        body: ResponseBody(byteBuffer: ByteBuffer(bytes: json)))
    }

    // GET /QuestionnaireResponse/:id/_history/:vid — vread
    group.get(":id/_history/:vid") { request, context in
        let id  = context.parameters.get("id")  ?? ""
        let vid = context.parameters.get("vid").flatMap { Int64($0) } ?? 0
        let result = try await store.vread(id: id, versionId: vid)
        var headers = HTTPFields()
        headers[.contentType]  = qrFhirJSON
        headers[.eTag]         = "W/\"\(result.versionId)\""
        headers[.lastModified] = httpDate(result.lastUpdated)
        headers[.contentLocation] = contentLocation(request, versionId: result.versionId)
        return Response(status: .ok, headers: headers,
                        body: ResponseBody(byteBuffer: ByteBuffer(bytes: result.jsonData)))
    }

    // GET /QuestionnaireResponse/:id/_history — instance history
    group.get(":id/_history") { request, context in
        let id = context.parameters.get("id") ?? ""
        let qp = request.uri.queryParameters
        let since: Date? = qp["_since"].flatMap { parseFHIRInstant(String($0)) }
        let count = min(qp["_count"].flatMap { Int($0) } ?? 50, qrMaxCount)
        let entries = try await store.history(id: id, since: since, count: count)
        let baseURL = serverBaseURL(request)
        let bundleData = buildHistoryBundleJSON(entries: entries, baseURL: baseURL, selfURL: selfURL(request))
        var headers = HTTPFields()
        headers[.contentType] = qrFhirJSON
        return Response(status: .ok, headers: headers,
                        body: ResponseBody(byteBuffer: ByteBuffer(bytes: bundleData)))
    }

    // GET /QuestionnaireResponse/_history — type history
    group.get("_history") { request, _ in
        let qp = request.uri.queryParameters
        let since: Date? = qp["_since"].flatMap { parseFHIRInstant(String($0)) }
        let count = min(qp["_count"].flatMap { Int($0) } ?? 50, 100)
        let entries = try await store.typeHistory(since: since, count: count)
        let baseURL = serverBaseURL(request)
        let bundleData = buildHistoryBundleJSON(entries: entries, baseURL: baseURL, selfURL: selfURL(request))
        var headers = HTTPFields()
        headers[.contentType] = qrFhirJSON
        return Response(status: .ok, headers: headers,
                        body: ResponseBody(byteBuffer: ByteBuffer(bytes: bundleData)))
    }

    // PUT /QuestionnaireResponse/:id — update
    group.put(":id") { request, context in
        try qrRequireFHIRContentType(request)
        let preferReturn = parsePreferReturn(request.headers[qrPreferHeader])
        let id = context.parameters.get("id") ?? ""
        let ifMatch = qrParseETag(request.headers[.ifMatch])
        var req = request
        let bodyBuffer = try await req.collectBody(upTo: qrMaxBodyBytes)
        try validateResourceType("QuestionnaireResponse", from: Data(bodyBuffer.readableBytesView))
        let questionnaireResponse = try qrDecodeFHIR(QuestionnaireResponse.self, from: bodyBuffer)
        let result = try await store.update(id: id, questionnaireResponse: questionnaireResponse, ifMatch: ifMatch)
        var headers = HTTPFields()
        headers[.contentType]  = qrFhirJSON
        headers[.eTag]         = "W/\"\(result.versionId)\""
        headers[.lastModified] = httpDate(result.lastUpdated)
        headers[.location] = "\(serverBaseURL(request))/QuestionnaireResponse/\(result.id)/_history/\(result.versionId)"
        return Response(status: .ok, headers: headers,
                        body: preferBody(preferReturn, resource: result.jsonData))
    }

    // PATCH /QuestionnaireResponse/:id — JSON Patch (RFC 6902)
    group.patch(":id") { request, context in
        let id = context.parameters.get("id") ?? ""
        let ct = request.headers[.contentType] ?? ""
        guard ct.contains("application/json-patch+json") else {
            throw FHIRRouteError.invalidBody("PATCH requires Content-Type: application/json-patch+json")
        }
        let ifMatch = qrParseETag(request.headers[.ifMatch])
        var req = request
        let bodyBuffer = try await req.collectBody(upTo: qrMaxBodyBytes)
        let patchData  = Data(bodyBuffer.readableBytesView)
        let current    = try await store.read(id: id)
        let patchedJSON: Data
        do {
            patchedJSON = try JSONPatch.apply(patchData, to: current.jsonData)
        } catch let e as JSONPatchError {
            switch e {
            case .invalidPatch(let m), .pathNotFound(let m): throw FHIRRouteError.invalidBody(m)
            case .testFailed(let m): throw FHIRRouteError.unprocessableEntity(m)
            }
        }
        let questionnaireResponse: QuestionnaireResponse
        do { questionnaireResponse = try JSONDecoder().decode(QuestionnaireResponse.self, from: patchedJSON) }
        catch { throw FHIRRouteError.unprocessableEntity("Patched resource is not valid FHIR: \(error.localizedDescription)") }
        let result = try await store.update(id: id, questionnaireResponse: questionnaireResponse, ifMatch: ifMatch)
        var headers = HTTPFields()
        headers[.contentType]  = qrFhirJSON
        headers[.eTag]         = "W/\"\(result.versionId)\""
        headers[.lastModified] = httpDate(result.lastUpdated)
        return Response(status: .ok, headers: headers,
                        body: ResponseBody(byteBuffer: ByteBuffer(bytes: result.jsonData)))
    }

    // DELETE /QuestionnaireResponse/:id — logical delete
    group.delete(":id") { request, context in
        let id = context.parameters.get("id") ?? ""
        let ifMatch = qrParseETag(request.headers[.ifMatch])
        let result = try await store.delete(id: id, ifMatch: ifMatch)
        var headers = HTTPFields()
        headers[.eTag]         = "W/\"\(result.versionId)\""
        headers[.lastModified] = httpDate(result.lastUpdated)
        return Response(status: .noContent, headers: headers, body: .init())
    }

    // DELETE /QuestionnaireResponse?<search> — conditional delete
    group.delete { request, _ in
        let qpPairs = request.uri.queryParameters.map { (key: $0.key, value: $0.value) }
        guard !qpPairs.isEmpty else {
            throw FHIRRouteError.invalidBody("DELETE /QuestionnaireResponse requires search parameters for conditional delete")
        }
        var checkQuery = try parseQuestionnaireResponseQuery(from: qpPairs)
        checkQuery.count = 2; checkQuery.totalMode = .none; checkQuery.cursor = nil
        let matches = try await store.search(query: checkQuery)
        switch matches.entries.count {
        case 0:
            return Response(status: .noContent, headers: HTTPFields(), body: .init())
        case 1:
            let result = try await store.delete(id: matches.entries[0].id, ifMatch: nil)
            var headers = HTTPFields()
            headers[.eTag]         = "W/\"\(result.versionId)\""
            headers[.lastModified] = httpDate(result.lastUpdated)
            return Response(status: .noContent, headers: headers, body: .init())
        default:
            throw FHIRServerError.multipleMatches(resourceType: "QuestionnaireResponse")
        }
    }

    // GET /QuestionnaireResponse — search
    group.get { request, _ in
        let pairs = request.uri.queryParameters.map { (key: $0.key, value: $0.value) }
        if isStrictHandling(request) {
            let bad = unknownParams(in: pairs, known: knownQuestionnaireResponseParams)
            if !bad.isEmpty { throw FHIRRouteError.unknownParams(bad) }
        }
        var query = try parseQuestionnaireResponseQuery(from: pairs)
        let elements = parseElements(from: pairs)
        let summary = parseSummary(from: pairs)
        let includes = parseIncludes(from: pairs)
        let revIncludes = parseRevIncludes(from: pairs)
        if summary == .count { query.count = 0; query.totalMode = .accurate }
        let result = try await store.search(query: query)

        let base = selfURL(request)
        let baseURL = serverBaseURL(request)
        if summary == .count {
            let bundleData = buildBundleJSON(entries: [], total: result.total, selfURL: base, nextURL: nil)
            var headers = HTTPFields()
            headers[.contentType] = qrFhirJSON
            return Response(status: .ok, headers: headers,
                            body: ResponseBody(byteBuffer: ByteBuffer(bytes: bundleData)))
        }
        let nextURL = result.nextCursor.map { nextQuestionnaireResponsePageURL(selfURL: base, cursor: $0, count: query.count) }
        let entries = result.entries.map { e -> (fullUrl: String, json: Data) in
            var json = e.jsonWithMeta
            if let s = summary, s != .false { json = applySummary(json, mode: s, summaryFields: questionnaireResponseSummaryFields) }
            if let elems = elements { json = applyElements(json, elements: elems) }
            return ("\(baseURL)/QuestionnaireResponse/\(e.id)", json)
        }
        let mainIds = result.entries.map(\.id)
        let resolver = IncludeResolver(client: store.client, logger: logger)
        async let included = resolver.resolve(includes: includes, sourceIds: mainIds)
        async let revIncluded = resolver.resolveRev(revIncludes: revIncludes, mainIds: mainIds)
        let includeEntries = includeEntryTuples(from: try await included + revIncluded, baseURL: baseURL)
        let bundleData = buildBundleJSON(entries: entries, includeEntries: includeEntries,
                                         total: result.total, selfURL: base, nextURL: nextURL)
        var headers = HTTPFields()
        headers[.contentType] = qrFhirJSON
        return Response(status: .ok, headers: headers,
                        body: ResponseBody(byteBuffer: ByteBuffer(bytes: bundleData)))
    }

    // POST /QuestionnaireResponse/_search — form-encoded search
    group.post("_search") { request, _ in
        let ct = request.headers[.contentType] ?? ""
        guard ct.contains("application/x-www-form-urlencoded") else {
            throw FHIRRouteError.invalidBody("Content-Type must be application/x-www-form-urlencoded for _search")
        }
        var req = request
        let bodyBuffer = try await req.collectBody(upTo: qrMaxBodyBytes)
        let urlPairs = request.uri.queryParameters.map { (key: $0.key, value: $0.value) }
        let pairs = urlPairs + parseFormPairs(from: bodyBuffer)
        if isStrictHandling(request) {
            let bad = unknownParams(in: pairs, known: knownQuestionnaireResponseParams)
            if !bad.isEmpty { throw FHIRRouteError.unknownParams(bad) }
        }
        var query = try parseQuestionnaireResponseQuery(from: pairs)
        let elements = parseElements(from: pairs)
        let summary = parseSummary(from: pairs)
        let includes = parseIncludes(from: pairs)
        let revIncludes = parseRevIncludes(from: pairs)
        if summary == .count { query.count = 0; query.totalMode = .accurate }
        let result = try await store.search(query: query)

        let base = selfURL(request)
        let baseURL = serverBaseURL(request)
        if summary == .count {
            let bundleData = buildBundleJSON(entries: [], total: result.total, selfURL: base, nextURL: nil)
            var headers = HTTPFields()
            headers[.contentType] = qrFhirJSON
            return Response(status: .ok, headers: headers,
                            body: ResponseBody(byteBuffer: ByteBuffer(bytes: bundleData)))
        }
        let nextURL = result.nextCursor.map { nextQuestionnaireResponsePageURL(selfURL: base, cursor: $0, count: query.count) }
        let entries = result.entries.map { e -> (fullUrl: String, json: Data) in
            var json = e.jsonWithMeta
            if let s = summary, s != .false { json = applySummary(json, mode: s, summaryFields: questionnaireResponseSummaryFields) }
            if let elems = elements { json = applyElements(json, elements: elems) }
            return ("\(baseURL)/QuestionnaireResponse/\(e.id)", json)
        }
        let mainIds = result.entries.map(\.id)
        let resolver = IncludeResolver(client: store.client, logger: logger)
        async let included = resolver.resolve(includes: includes, sourceIds: mainIds)
        async let revIncluded = resolver.resolveRev(revIncludes: revIncludes, mainIds: mainIds)
        let includeEntries = includeEntryTuples(from: try await included + revIncluded, baseURL: baseURL)
        let bundleData = buildBundleJSON(entries: entries, includeEntries: includeEntries,
                                         total: result.total, selfURL: base, nextURL: nextURL)
        var headers = HTTPFields()
        headers[.contentType] = qrFhirJSON
        return Response(status: .ok, headers: headers,
                        body: ResponseBody(byteBuffer: ByteBuffer(bytes: bundleData)))
    }
}

// ── Query parser ──────────────────────────────────────────────────────────────

func parseQuestionnaireResponseQuery(from pairs: some Collection<(key: Substring, value: Substring)>) throws -> QuestionnaireResponseSearchQuery {
    let pairs = normalizeReferenceTypeModifiers(pairs)
    func first(_ key: String) -> Substring? {
        pairs.first(where: { $0.key == key[...] })?.value
    }
    func all(_ key: String) -> [Substring] {
        pairs.filter { $0.key == key[...] }.map { $0.value }
    }

    let status        = all("status").flatMap { QuestionnaireResponseSearchQuery.TokenParam.parseList(String($0)) }
    let statusNot     = all("status:not").flatMap { QuestionnaireResponseSearchQuery.TokenParam.parseList(String($0)) }
    let identifier    = first("identifier").map { QuestionnaireResponseSearchQuery.IdentifierParam.parseList(String($0)) } ?? []
    let identifierNot = first("identifier:not").map { QuestionnaireResponseSearchQuery.IdentifierParam.parseList(String($0)) } ?? []
    let questionnaire = all("questionnaire").map(String.init)

    let authored = try parseDateParams(all("authored"), "authored", QuestionnaireResponseSearchQuery.DateParam.parse)

    let subject     = first("subject").map(String.init)
    let patient     = first("patient").map(String.init)
    let author      = first("author").map(String.init)
    let encounter   = first("encounter").map(String.init)
    let source      = first("source").map(String.init)
    let basedOn     = first("based-on").map(String.init)
    let partOf      = first("part-of").map(String.init)
    let itemSubject = first("item-subject").map(String.init)

    let id          = first("_id").map {
        String($0).split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }
    } ?? []
    let lastUpdated = try parseDateParams(all("_lastUpdated"), "_lastUpdated", QuestionnaireResponseSearchQuery.DateParam.parse)
    let sortKeys = QuestionnaireResponseSearchQuery.parseSortKeys(first("_sort").map(String.init) ?? "-_lastUpdated")
    let count       = min(first("_count").flatMap { Int($0) } ?? 20, qrMaxCount)
    let cursor      = first("_cursor").flatMap { SearchCursor.decode(String($0)) }
    let totalMode   = QuestionnaireResponseSearchQuery.TotalMode.parse(first("_total").map(String.init))

    var missing: [String: Bool] = [:]
    for p in ["status", "identifier", "questionnaire", "authored", "subject", "patient", "author",
              "encounter", "source", "based-on", "part-of", "item-subject"] {
        if let v = first("\(p):missing").map(String.init) {
            if v == "true" { missing[p] = true } else if v == "false" { missing[p] = false }
        }
    }

    let tokenTexts = pairs.compactMap { pair -> TokenTextParam? in
        let key = String(pair.key)
        guard key.hasSuffix(":text") else { return nil }
        let paramName = String(key.dropLast(5))
        return TokenTextParam(paramName: paramName, value: String(pair.value))
    }
    let chains = parseChainParams(from: pairs)
    let has    = parseHasParams(from: pairs)

    var query = QuestionnaireResponseSearchQuery(
        status: status, statusNot: statusNot,
        identifier: identifier, identifierNot: identifierNot,
        questionnaire: questionnaire, authored: authored,
        subject: subject, patient: patient, author: author,
        encounter: encounter, source: source,
        basedOn: basedOn, partOf: partOf, itemSubject: itemSubject,
        id: id, lastUpdated: lastUpdated,
        tokenTexts: tokenTexts,
        missing: missing, chains: chains, has: has,
        totalMode: totalMode, count: count, sortKeys: sortKeys, cursor: cursor)
    query.meta = parseMetaSearchParams(from: pairs)
    return query
}

// ── Helpers ───────────────────────────────────────────────────────────────────

private func qrConditionalResponse(request: Request, versionId: Int64, lastUpdated: Date) -> Response? {
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
    if let ims = request.headers[.ifModifiedSince], let since = parseHTTPDate(ims) {
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

private func qrRequireFHIRContentType(_ request: Request) throws {
    let ct = request.headers[.contentType] ?? ""
    guard ct.contains(qrFhirJSON) || ct.contains("application/json") else {
        throw FHIRRouteError.unsupportedMediaType
    }
}

private func qrDecodeFHIR<T: Decodable>(_ type: T.Type, from buffer: ByteBuffer) throws -> T {
    let data = Data(buffer.readableBytesView)
    do { return try JSONDecoder().decode(type, from: data) }
    catch { throw FHIRRouteError.invalidBody(error.localizedDescription) }
}

func nextQuestionnaireResponsePageURL(selfURL: String, cursor: SearchCursor, count: Int) -> String {
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

private func qrParseETag(_ raw: String?) -> Int64? {
    guard let raw else { return nil }
    let stripped = raw
        .trimmingCharacters(in: .whitespaces)
        .replacingOccurrences(of: "W/", with: "")
        .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
    return Int64(stripped)
}
