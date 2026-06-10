import Foundation
import HTTPTypes
import Hummingbird
import Logging
import ModelsR4
import NIOCore
import SimingCore

private let fmhMaxCount = 100
private let fmhFhirJSON = "application/fhir+json"
private let fmhMaxBodyBytes = 4 * 1024 * 1024
private let fmhIfNoneExistHeader = HTTPField.Name("If-None-Exist")!
private let fmhPreferHeader = HTTPField.Name("Prefer")!

let knownFamilyMemberHistoryParams: Set<String> = [
    "status", "relationship", "sex", "code", "identifier", "date", "patient",
    "instantiates-canonical", "instantiates-uri",
    "status:not", "relationship:not", "sex:not", "code:not",
    "identifier:not",
    "_id", "_lastUpdated", "_sort", "_count", "_cursor", "_total",
    "_elements", "_format", "_summary", "_include", "_revinclude",
]

public func addFamilyMemberHistoryRoutes(
    to router: Router<BasicRequestContext>,
    store: FamilyMemberHistoryStore,
    logger: Logger
) {
    let group = router.group("FamilyMemberHistory")

    // POST /FamilyMemberHistory — create
    group.post { request, _ in
        try fmhRequireFHIRContentType(request)
        let returnMinimal = (request.headers[fmhPreferHeader] ?? "").contains("return=minimal")
        var req = request
        let bodyBuffer = try await req.collectBody(upTo: fmhMaxBodyBytes)
        let fmh = try fmhDecodeFHIR(FamilyMemberHistory.self, from: bodyBuffer)

        if let ifNoneExist = request.headers[fmhIfNoneExistHeader] {
            let pairs = parseQueryString(ifNoneExist)
            var checkQuery = parseFamilyMemberHistoryQuery(from: pairs)
            checkQuery.count = 2; checkQuery.totalMode = .none; checkQuery.cursor = nil
            let matches = try await store.search(query: checkQuery)
            if matches.entries.count > 1 {
                throw FHIRServerError.multipleMatches(resourceType: "FamilyMemberHistory")
            }
            if let existing = matches.entries.first {
                var headers = HTTPFields()
                headers[.contentType]  = fmhFhirJSON
                headers[.eTag]         = "W/\"\(existing.versionId)\""
                headers[.lastModified] = httpDate(existing.lastUpdated)
                headers[.location]     = "/FamilyMemberHistory/\(existing.id)/_history/\(existing.versionId)"
                return Response(status: .ok, headers: headers,
                                body: returnMinimal ? .init() : ResponseBody(byteBuffer: ByteBuffer(bytes: existing.jsonWithMeta)))
            }
        }

        let result = try await store.create(fmh)
        var headers = HTTPFields()
        headers[.contentType]  = fmhFhirJSON
        headers[.eTag]         = "W/\"\(result.versionId)\""
        headers[.lastModified] = httpDate(result.lastUpdated)
        headers[.location]     = "/FamilyMemberHistory/\(result.id)/_history/\(result.versionId)"
        return Response(status: .created, headers: headers,
                        body: returnMinimal ? .init() : ResponseBody(byteBuffer: ByteBuffer(bytes: result.jsonData)))
    }

    // PUT /FamilyMemberHistory?<search> — conditional update
    group.put { request, _ in
        try fmhRequireFHIRContentType(request)
        let returnMinimal = (request.headers[fmhPreferHeader] ?? "").contains("return=minimal")
        let qpPairs = request.uri.queryParameters.map { (key: $0.key, value: $0.value) }
        guard !qpPairs.isEmpty else {
            throw FHIRRouteError.invalidBody("PUT /FamilyMemberHistory requires search parameters for conditional update")
        }
        var req = request
        let bodyBuffer = try await req.collectBody(upTo: fmhMaxBodyBytes)
        let fmh = try fmhDecodeFHIR(FamilyMemberHistory.self, from: bodyBuffer)
        let ifMatch = fmhParseETag(request.headers[.ifMatch])

        var checkQuery = parseFamilyMemberHistoryQuery(from: qpPairs)
        checkQuery.count = 2; checkQuery.totalMode = .none; checkQuery.cursor = nil
        let matches = try await store.search(query: checkQuery)

        switch matches.entries.count {
        case 0:
            let result = try await store.create(fmh)
            var headers = HTTPFields()
            headers[.contentType]  = fmhFhirJSON
            headers[.eTag]         = "W/\"\(result.versionId)\""
            headers[.lastModified] = httpDate(result.lastUpdated)
            headers[.location]     = "/FamilyMemberHistory/\(result.id)/_history/\(result.versionId)"
            return Response(status: .created, headers: headers,
                            body: returnMinimal ? .init() : ResponseBody(byteBuffer: ByteBuffer(bytes: result.jsonData)))
        case 1:
            let existingId = matches.entries[0].id
            let result = try await store.update(id: existingId, familyMemberHistory: fmh, ifMatch: ifMatch)
            var headers = HTTPFields()
            headers[.contentType]  = fmhFhirJSON
            headers[.eTag]         = "W/\"\(result.versionId)\""
            headers[.lastModified] = httpDate(result.lastUpdated)
            headers[.location]     = "/FamilyMemberHistory/\(result.id)/_history/\(result.versionId)"
            return Response(status: .ok, headers: headers,
                            body: returnMinimal ? .init() : ResponseBody(byteBuffer: ByteBuffer(bytes: result.jsonData)))
        default:
            throw FHIRServerError.multipleMatches(resourceType: "FamilyMemberHistory")
        }
    }

    // GET /FamilyMemberHistory/:id — read
    group.get(":id") { request, context in
        let id = context.parameters.get("id") ?? ""
        let result = try await store.read(id: id)
        if let earlyResponse = fmhConditionalResponse(request: request, versionId: result.versionId, lastUpdated: result.lastUpdated) {
            return earlyResponse
        }
        let pairs = request.uri.queryParameters.map { (key: $0.key, value: $0.value) }
        let elements = parseElements(from: pairs)
        let summary  = parseSummary(from: pairs)
        var json = result.jsonData
        if let s = summary, s != .false { json = applySummary(json, mode: s, summaryFields: familyMemberHistorySummaryFields) }
        if let elems = elements { json = applyElements(json, elements: elems) }
        var headers = HTTPFields()
        headers[.contentType]  = fmhFhirJSON
        headers[.eTag]         = "W/\"\(result.versionId)\""
        headers[.lastModified] = httpDate(result.lastUpdated)
        return Response(status: .ok, headers: headers,
                        body: ResponseBody(byteBuffer: ByteBuffer(bytes: json)))
    }

    // GET /FamilyMemberHistory/:id/_history/:vid — vread
    group.get(":id/_history/:vid") { request, context in
        let id  = context.parameters.get("id")  ?? ""
        let vid = context.parameters.get("vid").flatMap { Int64($0) } ?? 0
        let result = try await store.vread(id: id, versionId: vid)
        var headers = HTTPFields()
        headers[.contentType]  = fmhFhirJSON
        headers[.eTag]         = "W/\"\(result.versionId)\""
        headers[.lastModified] = httpDate(result.lastUpdated)
        return Response(status: .ok, headers: headers,
                        body: ResponseBody(byteBuffer: ByteBuffer(bytes: result.jsonData)))
    }

    // GET /FamilyMemberHistory/:id/_history — instance history
    group.get(":id/_history") { request, context in
        let id = context.parameters.get("id") ?? ""
        let qp = request.uri.queryParameters
        let since: Date? = qp["_since"].flatMap { parseFHIRInstant(String($0)) }
        let count = min(qp["_count"].flatMap { Int($0) } ?? 50, fmhMaxCount)
        let entries = try await store.history(id: id, since: since, count: count)
        let baseURL = serverBaseURL(request)
        let bundleData = buildHistoryBundleJSON(entries: entries, baseURL: baseURL)
        var headers = HTTPFields()
        headers[.contentType] = fmhFhirJSON
        return Response(status: .ok, headers: headers,
                        body: ResponseBody(byteBuffer: ByteBuffer(bytes: bundleData)))
    }

    // GET /FamilyMemberHistory/_history — type history
    group.get("_history") { request, _ in
        let qp = request.uri.queryParameters
        let since: Date? = qp["_since"].flatMap { parseFHIRInstant(String($0)) }
        let count = min(qp["_count"].flatMap { Int($0) } ?? 50, 100)
        let entries = try await store.typeHistory(since: since, count: count)
        let baseURL = serverBaseURL(request)
        let bundleData = buildHistoryBundleJSON(entries: entries, baseURL: baseURL)
        var headers = HTTPFields()
        headers[.contentType] = fmhFhirJSON
        return Response(status: .ok, headers: headers,
                        body: ResponseBody(byteBuffer: ByteBuffer(bytes: bundleData)))
    }

    // PUT /FamilyMemberHistory/:id — update
    group.put(":id") { request, context in
        try fmhRequireFHIRContentType(request)
        let returnMinimal = (request.headers[fmhPreferHeader] ?? "").contains("return=minimal")
        let id = context.parameters.get("id") ?? ""
        let ifMatch = fmhParseETag(request.headers[.ifMatch])
        var req = request
        let bodyBuffer = try await req.collectBody(upTo: fmhMaxBodyBytes)
        let fmh = try fmhDecodeFHIR(FamilyMemberHistory.self, from: bodyBuffer)
        let result = try await store.update(id: id, familyMemberHistory: fmh, ifMatch: ifMatch)
        var headers = HTTPFields()
        headers[.contentType]  = fmhFhirJSON
        headers[.eTag]         = "W/\"\(result.versionId)\""
        headers[.lastModified] = httpDate(result.lastUpdated)
        headers[.location]     = "/FamilyMemberHistory/\(result.id)/_history/\(result.versionId)"
        return Response(status: .ok, headers: headers,
                        body: returnMinimal ? .init() : ResponseBody(byteBuffer: ByteBuffer(bytes: result.jsonData)))
    }

    // PATCH /FamilyMemberHistory/:id — JSON Patch (RFC 6902)
    group.patch(":id") { request, context in
        let id = context.parameters.get("id") ?? ""
        let ct = request.headers[.contentType] ?? ""
        guard ct.contains("application/json-patch+json") else {
            throw FHIRRouteError.invalidBody("PATCH requires Content-Type: application/json-patch+json")
        }
        let ifMatch = fmhParseETag(request.headers[.ifMatch])
        var req = request
        let bodyBuffer = try await req.collectBody(upTo: fmhMaxBodyBytes)
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
        let familyMemberHistory: FamilyMemberHistory
        do { familyMemberHistory = try JSONDecoder().decode(FamilyMemberHistory.self, from: patchedJSON) }
        catch { throw FHIRRouteError.unprocessableEntity("Patched resource is not valid FHIR: \(error.localizedDescription)") }
        let result = try await store.update(id: id, familyMemberHistory: familyMemberHistory, ifMatch: ifMatch)
        var headers = HTTPFields()
        headers[.contentType]  = fmhFhirJSON
        headers[.eTag]         = "W/\"\(result.versionId)\""
        headers[.lastModified] = httpDate(result.lastUpdated)
        return Response(status: .ok, headers: headers,
                        body: ResponseBody(byteBuffer: ByteBuffer(bytes: result.jsonData)))
    }

    // DELETE /FamilyMemberHistory/:id — logical delete
    group.delete(":id") { request, context in
        let id = context.parameters.get("id") ?? ""
        let ifMatch = fmhParseETag(request.headers[.ifMatch])
        let result = try await store.delete(id: id, ifMatch: ifMatch)
        var headers = HTTPFields()
        headers[.eTag]         = "W/\"\(result.versionId)\""
        headers[.lastModified] = httpDate(result.lastUpdated)
        return Response(status: .noContent, headers: headers, body: .init())
    }

    // DELETE /FamilyMemberHistory?<search> — conditional delete
    group.delete { request, _ in
        let qpPairs = request.uri.queryParameters.map { (key: $0.key, value: $0.value) }
        guard !qpPairs.isEmpty else {
            throw FHIRRouteError.invalidBody("DELETE /FamilyMemberHistory requires search parameters for conditional delete")
        }
        var checkQuery = parseFamilyMemberHistoryQuery(from: qpPairs)
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
            throw FHIRServerError.multipleMatches(resourceType: "FamilyMemberHistory")
        }
    }

    // GET /FamilyMemberHistory — search
    group.get { request, _ in
        let pairs = request.uri.queryParameters.map { (key: $0.key, value: $0.value) }
        if isStrictHandling(request) {
            let bad = unknownParams(in: pairs, known: knownFamilyMemberHistoryParams)
            if !bad.isEmpty { throw FHIRRouteError.unknownParams(bad) }
        }
        var query = parseFamilyMemberHistoryQuery(from: pairs)
        let elements = parseElements(from: pairs)
        let summary = parseSummary(from: pairs)
        let includes = parseIncludes(from: pairs)
        let revIncludes = parseRevIncludes(from: pairs)
        if summary == .count { query.count = 0; query.totalMode = .accurate }
        let result = try await store.search(query: query)

        let base = fmhSelfURL(request)
        let baseURL = serverBaseURL(request)
        if summary == .count {
            let bundleData = buildBundleJSON(entries: [], total: result.total, selfURL: base, nextURL: nil)
            var headers = HTTPFields()
            headers[.contentType] = fmhFhirJSON
            return Response(status: .ok, headers: headers,
                            body: ResponseBody(byteBuffer: ByteBuffer(bytes: bundleData)))
        }
        let nextURL = result.nextCursor.map { nextFamilyMemberHistoryPageURL(selfURL: base, cursor: $0, count: query.count) }
        let entries = result.entries.map { e -> (fullUrl: String, json: Data) in
            var json = e.jsonWithMeta
            if let s = summary, s != .false { json = applySummary(json, mode: s, summaryFields: familyMemberHistorySummaryFields) }
            if let elems = elements { json = applyElements(json, elements: elems) }
            return ("\(baseURL)/FamilyMemberHistory/\(e.id)", json)
        }
        let mainIds = result.entries.map(\.id)
        let resolver = IncludeResolver(client: store.client, logger: logger)
        async let included = resolver.resolve(includes: includes, sourceIds: mainIds)
        async let revIncluded = resolver.resolveRev(revIncludes: revIncludes, mainIds: mainIds)
        let includeEntries = includeEntryTuples(from: try await included + revIncluded, baseURL: baseURL)
        let bundleData = buildBundleJSON(entries: entries, includeEntries: includeEntries,
                                         total: result.total, selfURL: base, nextURL: nextURL)
        var headers = HTTPFields()
        headers[.contentType] = fmhFhirJSON
        return Response(status: .ok, headers: headers,
                        body: ResponseBody(byteBuffer: ByteBuffer(bytes: bundleData)))
    }

    // POST /FamilyMemberHistory/_search — form-encoded search
    group.post("_search") { request, _ in
        let ct = request.headers[.contentType] ?? ""
        guard ct.contains("application/x-www-form-urlencoded") else {
            throw FHIRRouteError.invalidBody("Content-Type must be application/x-www-form-urlencoded for _search")
        }
        var req = request
        let bodyBuffer = try await req.collectBody(upTo: fmhMaxBodyBytes)
        let urlPairs = request.uri.queryParameters.map { (key: $0.key, value: $0.value) }
        let pairs = urlPairs + parseFormPairs(from: bodyBuffer)
        if isStrictHandling(request) {
            let bad = unknownParams(in: pairs, known: knownFamilyMemberHistoryParams)
            if !bad.isEmpty { throw FHIRRouteError.unknownParams(bad) }
        }
        var query = parseFamilyMemberHistoryQuery(from: pairs)
        let elements = parseElements(from: pairs)
        let summary = parseSummary(from: pairs)
        let includes = parseIncludes(from: pairs)
        let revIncludes = parseRevIncludes(from: pairs)
        if summary == .count { query.count = 0; query.totalMode = .accurate }
        let result = try await store.search(query: query)

        let base = fmhSelfURL(request)
        let baseURL = serverBaseURL(request)
        if summary == .count {
            let bundleData = buildBundleJSON(entries: [], total: result.total, selfURL: base, nextURL: nil)
            var headers = HTTPFields()
            headers[.contentType] = fmhFhirJSON
            return Response(status: .ok, headers: headers,
                            body: ResponseBody(byteBuffer: ByteBuffer(bytes: bundleData)))
        }
        let nextURL = result.nextCursor.map { nextFamilyMemberHistoryPageURL(selfURL: base, cursor: $0, count: query.count) }
        let entries = result.entries.map { e -> (fullUrl: String, json: Data) in
            var json = e.jsonWithMeta
            if let s = summary, s != .false { json = applySummary(json, mode: s, summaryFields: familyMemberHistorySummaryFields) }
            if let elems = elements { json = applyElements(json, elements: elems) }
            return ("\(baseURL)/FamilyMemberHistory/\(e.id)", json)
        }
        let mainIds = result.entries.map(\.id)
        let resolver = IncludeResolver(client: store.client, logger: logger)
        async let included = resolver.resolve(includes: includes, sourceIds: mainIds)
        async let revIncluded = resolver.resolveRev(revIncludes: revIncludes, mainIds: mainIds)
        let includeEntries = includeEntryTuples(from: try await included + revIncluded, baseURL: baseURL)
        let bundleData = buildBundleJSON(entries: entries, includeEntries: includeEntries,
                                         total: result.total, selfURL: base, nextURL: nextURL)
        var headers = HTTPFields()
        headers[.contentType] = fmhFhirJSON
        return Response(status: .ok, headers: headers,
                        body: ResponseBody(byteBuffer: ByteBuffer(bytes: bundleData)))
    }
}

// ── Query parser ──────────────────────────────────────────────────────────────

func parseFamilyMemberHistoryQuery(from pairs: some Collection<(key: Substring, value: Substring)>) -> FamilyMemberHistorySearchQuery {
    let pairs = normalizeReferenceTypeModifiers(pairs)
    func first(_ key: String) -> Substring? {
        pairs.first(where: { $0.key == key[...] })?.value
    }
    func all(_ key: String) -> [Substring] {
        pairs.filter { $0.key == key[...] }.map { $0.value }
    }

    let status          = all("status").flatMap { FamilyMemberHistorySearchQuery.TokenParam.parseList(String($0)) }
    let statusNot       = all("status:not").flatMap { FamilyMemberHistorySearchQuery.TokenParam.parseList(String($0)) }
    let relationship    = all("relationship").flatMap { FamilyMemberHistorySearchQuery.TokenParam.parseList(String($0)) }
    let relationshipNot = all("relationship:not").flatMap { FamilyMemberHistorySearchQuery.TokenParam.parseList(String($0)) }
    let sex             = all("sex").flatMap { FamilyMemberHistorySearchQuery.TokenParam.parseList(String($0)) }
    let sexNot          = all("sex:not").flatMap { FamilyMemberHistorySearchQuery.TokenParam.parseList(String($0)) }
    let code            = all("code").flatMap { FamilyMemberHistorySearchQuery.TokenParam.parseList(String($0)) }
    let codeNot         = all("code:not").flatMap { FamilyMemberHistorySearchQuery.TokenParam.parseList(String($0)) }
    let identifier      = first("identifier").map { FamilyMemberHistorySearchQuery.IdentifierParam.parseList(String($0)) } ?? []
    let identifierNot   = first("identifier:not").map { FamilyMemberHistorySearchQuery.IdentifierParam.parseList(String($0)) } ?? []

    let date                  = all("date").compactMap { FamilyMemberHistorySearchQuery.DateParam.parse(String($0)) }
    let instantiatesCanonical = all("instantiates-canonical").map(String.init)
    let instantiatesUri       = all("instantiates-uri").map(String.init)
    let patient               = first("patient").map(String.init)

    let id          = first("_id").map {
        String($0).split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }
    } ?? []
    let lastUpdated = all("_lastUpdated").compactMap { FamilyMemberHistorySearchQuery.DateParam.parse(String($0)) }
    let sort        = FamilyMemberHistorySearchQuery.SortOrder.parse(first("_sort").map(String.init) ?? "-_lastUpdated")
    let count       = min(first("_count").flatMap { Int($0) } ?? 20, fmhMaxCount)
    let cursor      = first("_cursor").flatMap { FamilyMemberHistorySearchQuery.SearchCursor.decode(String($0)) }
    let totalMode   = FamilyMemberHistorySearchQuery.TotalMode.parse(first("_total").map(String.init))

    var missing: [String: Bool] = [:]
    for p in ["status", "relationship", "sex", "code", "identifier", "date", "patient",
              "instantiates-canonical", "instantiates-uri"] {
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

    var query = FamilyMemberHistorySearchQuery(
        patient: patient,
        status: status, statusNot: statusNot,
        relationship: relationship, relationshipNot: relationshipNot,
        sex: sex, sexNot: sexNot,
        code: code, codeNot: codeNot,
        identifier: identifier, identifierNot: identifierNot,
        date: date,
        instantiatesCanonical: instantiatesCanonical,
        instantiatesUri: instantiatesUri,
        id: id, lastUpdated: lastUpdated,
        tokenTexts: tokenTexts,
        missing: missing, chains: chains, has: has,
        totalMode: totalMode, count: count, sort: sort, cursor: cursor)
    query.meta = parseMetaSearchParams(from: pairs)
    return query
}

// ── Helpers ───────────────────────────────────────────────────────────────────

private func fmhConditionalResponse(request: Request, versionId: Int64, lastUpdated: Date) -> Response? {
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

private func fmhRequireFHIRContentType(_ request: Request) throws {
    let ct = request.headers[.contentType] ?? ""
    guard ct.contains(fmhFhirJSON) || ct.contains("application/json") else {
        throw FHIRRouteError.unsupportedMediaType
    }
}

private func fmhDecodeFHIR<T: Decodable>(_ type: T.Type, from buffer: ByteBuffer) throws -> T {
    let data = Data(buffer.readableBytesView)
    do { return try JSONDecoder().decode(type, from: data) }
    catch { throw FHIRRouteError.invalidBody(error.localizedDescription) }
}

private func fmhSelfURL(_ request: Request) -> String {
    let authority = request.head.authority ?? "localhost"
    return "http://\(authority)\(request.uri)"
}

func nextFamilyMemberHistoryPageURL(selfURL: String, cursor: FamilyMemberHistorySearchQuery.SearchCursor, count: Int) -> String {
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

private func fmhParseETag(_ raw: String?) -> Int64? {
    guard let raw else { return nil }
    let stripped = raw
        .trimmingCharacters(in: .whitespaces)
        .replacingOccurrences(of: "W/", with: "")
        .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
    return Int64(stripped)
}
