import Foundation
import HTTPTypes
import Hummingbird
import Logging
import ModelsR4
import NIOCore
import SimingCore

private let goalMaxCount = 100
private let goalFhirJSON = "application/fhir+json"
private let goalMaxBodyBytes = 4 * 1024 * 1024
private let goalIfNoneExistHeader = HTTPField.Name("If-None-Exist")!
private let goalPreferHeader = HTTPField.Name("Prefer")!

let knownGoalParams: Set<String> = [
    "lifecycle-status", "achievement-status", "category", "identifier",
    "start-date", "target-date",
    "subject", "patient",
    "lifecycle-status:not", "category:not",
    "_id", "_lastUpdated", "_sort", "_count", "_cursor", "_total",
    "_elements", "_format", "_summary", "_include", "_revinclude",
]

public func addGoalRoutes(
    to router: Router<BasicRequestContext>,
    store: GoalStore,
    logger: Logger
) {
    let group = router.group("Goal")

    // POST /Goal — create
    group.post { request, _ in
        try goalRequireFHIRContentType(request)
        let returnMinimal = (request.headers[goalPreferHeader] ?? "").contains("return=minimal")
        var req = request
        let bodyBuffer = try await req.collectBody(upTo: goalMaxBodyBytes)
        let goal = try goalDecodeFHIR(Goal.self, from: bodyBuffer)

        if let ifNoneExist = request.headers[goalIfNoneExistHeader] {
            let pairs = parseQueryString(ifNoneExist)
            var checkQuery = parseGoalQuery(from: pairs)
            checkQuery.count = 2; checkQuery.totalMode = .none; checkQuery.cursor = nil
            let matches = try await store.search(query: checkQuery)
            if matches.entries.count > 1 {
                throw FHIRServerError.multipleMatches(resourceType: "Goal")
            }
            if let existing = matches.entries.first {
                var headers = HTTPFields()
                headers[.contentType]  = goalFhirJSON
                headers[.eTag]         = "W/\"\(existing.versionId)\""
                headers[.lastModified] = httpDate(existing.lastUpdated)
                headers[.location]     = "/Goal/\(existing.id)/_history/\(existing.versionId)"
                return Response(status: .ok, headers: headers,
                                body: returnMinimal ? .init() : ResponseBody(byteBuffer: ByteBuffer(bytes: existing.jsonWithMeta)))
            }
        }

        let result = try await store.create(goal)
        var headers = HTTPFields()
        headers[.contentType]  = goalFhirJSON
        headers[.eTag]         = "W/\"\(result.versionId)\""
        headers[.lastModified] = httpDate(result.lastUpdated)
        headers[.location]     = "/Goal/\(result.id)/_history/\(result.versionId)"
        return Response(status: .created, headers: headers,
                        body: returnMinimal ? .init() : ResponseBody(byteBuffer: ByteBuffer(bytes: result.jsonData)))
    }

    // PUT /Goal?<search> — conditional update
    group.put { request, _ in
        try goalRequireFHIRContentType(request)
        let returnMinimal = (request.headers[goalPreferHeader] ?? "").contains("return=minimal")
        let qpPairs = request.uri.queryParameters.map { (key: $0.key, value: $0.value) }
        guard !qpPairs.isEmpty else {
            throw FHIRRouteError.invalidBody("PUT /Goal requires search parameters for conditional update")
        }
        var req = request
        let bodyBuffer = try await req.collectBody(upTo: goalMaxBodyBytes)
        let goal = try goalDecodeFHIR(Goal.self, from: bodyBuffer)
        let ifMatch = goalParseETag(request.headers[.ifMatch])

        var checkQuery = parseGoalQuery(from: qpPairs)
        checkQuery.count = 2; checkQuery.totalMode = .none; checkQuery.cursor = nil
        let matches = try await store.search(query: checkQuery)

        switch matches.entries.count {
        case 0:
            let result = try await store.create(goal)
            var headers = HTTPFields()
            headers[.contentType]  = goalFhirJSON
            headers[.eTag]         = "W/\"\(result.versionId)\""
            headers[.lastModified] = httpDate(result.lastUpdated)
            headers[.location]     = "/Goal/\(result.id)/_history/\(result.versionId)"
            return Response(status: .created, headers: headers,
                            body: returnMinimal ? .init() : ResponseBody(byteBuffer: ByteBuffer(bytes: result.jsonData)))
        case 1:
            let existingId = matches.entries[0].id
            let result = try await store.update(id: existingId, goal: goal, ifMatch: ifMatch)
            var headers = HTTPFields()
            headers[.contentType]  = goalFhirJSON
            headers[.eTag]         = "W/\"\(result.versionId)\""
            headers[.lastModified] = httpDate(result.lastUpdated)
            headers[.location]     = "/Goal/\(result.id)/_history/\(result.versionId)"
            return Response(status: .ok, headers: headers,
                            body: returnMinimal ? .init() : ResponseBody(byteBuffer: ByteBuffer(bytes: result.jsonData)))
        default:
            throw FHIRServerError.multipleMatches(resourceType: "Goal")
        }
    }

    // GET /Goal/:id — read
    group.get(":id") { request, context in
        let id = context.parameters.get("id") ?? ""
        let result = try await store.read(id: id)
        if let earlyResponse = goalConditionalResponse(request: request, versionId: result.versionId, lastUpdated: result.lastUpdated) {
            return earlyResponse
        }
        let pairs = request.uri.queryParameters.map { (key: $0.key, value: $0.value) }
        let elements = parseElements(from: pairs)
        let summary  = parseSummary(from: pairs)
        var json = result.jsonData
        if let s = summary, s != .false { json = applySummary(json, mode: s, summaryFields: goalSummaryFields) }
        if let elems = elements { json = applyElements(json, elements: elems) }
        var headers = HTTPFields()
        headers[.contentType]  = goalFhirJSON
        headers[.eTag]         = "W/\"\(result.versionId)\""
        headers[.lastModified] = httpDate(result.lastUpdated)
        return Response(status: .ok, headers: headers,
                        body: ResponseBody(byteBuffer: ByteBuffer(bytes: json)))
    }

    // GET /Goal/:id/_history/:vid — vread
    group.get(":id/_history/:vid") { request, context in
        let id  = context.parameters.get("id")  ?? ""
        let vid = context.parameters.get("vid").flatMap { Int64($0) } ?? 0
        let result = try await store.vread(id: id, versionId: vid)
        var headers = HTTPFields()
        headers[.contentType]  = goalFhirJSON
        headers[.eTag]         = "W/\"\(result.versionId)\""
        headers[.lastModified] = httpDate(result.lastUpdated)
        return Response(status: .ok, headers: headers,
                        body: ResponseBody(byteBuffer: ByteBuffer(bytes: result.jsonData)))
    }

    // GET /Goal/:id/_history — instance history
    group.get(":id/_history") { request, context in
        let id = context.parameters.get("id") ?? ""
        let qp = request.uri.queryParameters
        let since: Date? = qp["_since"].flatMap { parseFHIRInstant(String($0)) }
        let count = min(qp["_count"].flatMap { Int($0) } ?? 50, goalMaxCount)
        let entries = try await store.history(id: id, since: since, count: count)
        let baseURL = serverBaseURL(request)
        let bundleData = buildHistoryBundleJSON(entries: entries, baseURL: baseURL)
        var headers = HTTPFields()
        headers[.contentType] = goalFhirJSON
        return Response(status: .ok, headers: headers,
                        body: ResponseBody(byteBuffer: ByteBuffer(bytes: bundleData)))
    }

    // GET /Goal/_history — type history
    group.get("_history") { request, _ in
        let qp = request.uri.queryParameters
        let since: Date? = qp["_since"].flatMap { parseFHIRInstant(String($0)) }
        let count = min(qp["_count"].flatMap { Int($0) } ?? 50, 100)
        let entries = try await store.typeHistory(since: since, count: count)
        let baseURL = serverBaseURL(request)
        let bundleData = buildHistoryBundleJSON(entries: entries, baseURL: baseURL)
        var headers = HTTPFields()
        headers[.contentType] = goalFhirJSON
        return Response(status: .ok, headers: headers,
                        body: ResponseBody(byteBuffer: ByteBuffer(bytes: bundleData)))
    }

    // PUT /Goal/:id — update
    group.put(":id") { request, context in
        try goalRequireFHIRContentType(request)
        let returnMinimal = (request.headers[goalPreferHeader] ?? "").contains("return=minimal")
        let id = context.parameters.get("id") ?? ""
        let ifMatch = goalParseETag(request.headers[.ifMatch])
        var req = request
        let bodyBuffer = try await req.collectBody(upTo: goalMaxBodyBytes)
        let goal = try goalDecodeFHIR(Goal.self, from: bodyBuffer)
        let result = try await store.update(id: id, goal: goal, ifMatch: ifMatch)
        var headers = HTTPFields()
        headers[.contentType]  = goalFhirJSON
        headers[.eTag]         = "W/\"\(result.versionId)\""
        headers[.lastModified] = httpDate(result.lastUpdated)
        headers[.location]     = "/Goal/\(result.id)/_history/\(result.versionId)"
        return Response(status: .ok, headers: headers,
                        body: returnMinimal ? .init() : ResponseBody(byteBuffer: ByteBuffer(bytes: result.jsonData)))
    }

    // PATCH /Goal/:id — JSON Patch (RFC 6902)
    group.patch(":id") { request, context in
        let id = context.parameters.get("id") ?? ""
        let ct = request.headers[.contentType] ?? ""
        guard ct.contains("application/json-patch+json") else {
            throw FHIRRouteError.invalidBody("PATCH requires Content-Type: application/json-patch+json")
        }
        let ifMatch = goalParseETag(request.headers[.ifMatch])
        var req = request
        let bodyBuffer = try await req.collectBody(upTo: goalMaxBodyBytes)
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
        let goal: Goal
        do { goal = try JSONDecoder().decode(Goal.self, from: patchedJSON) }
        catch { throw FHIRRouteError.unprocessableEntity("Patched resource is not valid FHIR: \(error.localizedDescription)") }
        let result = try await store.update(id: id, goal: goal, ifMatch: ifMatch)
        var headers = HTTPFields()
        headers[.contentType]  = goalFhirJSON
        headers[.eTag]         = "W/\"\(result.versionId)\""
        headers[.lastModified] = httpDate(result.lastUpdated)
        return Response(status: .ok, headers: headers,
                        body: ResponseBody(byteBuffer: ByteBuffer(bytes: result.jsonData)))
    }

    // DELETE /Goal/:id — logical delete
    group.delete(":id") { request, context in
        let id = context.parameters.get("id") ?? ""
        let ifMatch = goalParseETag(request.headers[.ifMatch])
        let result = try await store.delete(id: id, ifMatch: ifMatch)
        var headers = HTTPFields()
        headers[.eTag]         = "W/\"\(result.versionId)\""
        headers[.lastModified] = httpDate(result.lastUpdated)
        return Response(status: .noContent, headers: headers, body: .init())
    }

    // DELETE /Goal?<search> — conditional delete
    group.delete { request, _ in
        let qpPairs = request.uri.queryParameters.map { (key: $0.key, value: $0.value) }
        guard !qpPairs.isEmpty else {
            throw FHIRRouteError.invalidBody("DELETE /Goal requires search parameters for conditional delete")
        }
        var checkQuery = parseGoalQuery(from: qpPairs)
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
            throw FHIRServerError.multipleMatches(resourceType: "Goal")
        }
    }

    // GET /Goal — search
    group.get { request, _ in
        let pairs = request.uri.queryParameters.map { (key: $0.key, value: $0.value) }
        if isStrictHandling(request) {
            let bad = unknownParams(in: pairs, known: knownGoalParams)
            if !bad.isEmpty { throw FHIRRouteError.unknownParams(bad) }
        }
        var query = parseGoalQuery(from: pairs)
        let elements = parseElements(from: pairs)
        let summary = parseSummary(from: pairs)
        let includes = parseIncludes(from: pairs)
        let revIncludes = parseRevIncludes(from: pairs)
        if summary == .count { query.count = 0; query.totalMode = .accurate }
        let result = try await store.search(query: query)

        let base = goalSelfURL(request)
        let baseURL = serverBaseURL(request)
        if summary == .count {
            let bundleData = buildBundleJSON(entries: [], total: result.total, selfURL: base, nextURL: nil)
            var headers = HTTPFields()
            headers[.contentType] = goalFhirJSON
            return Response(status: .ok, headers: headers,
                            body: ResponseBody(byteBuffer: ByteBuffer(bytes: bundleData)))
        }
        let nextURL = result.nextCursor.map { nextGoalPageURL(selfURL: base, cursor: $0, count: query.count) }
        let entries = result.entries.map { e -> (fullUrl: String, json: Data) in
            var json = e.jsonWithMeta
            if let s = summary, s != .false { json = applySummary(json, mode: s, summaryFields: goalSummaryFields) }
            if let elems = elements { json = applyElements(json, elements: elems) }
            return ("\(baseURL)/Goal/\(e.id)", json)
        }
        let mainIds = result.entries.map(\.id)
        let resolver = IncludeResolver(client: store.client, logger: logger)
        async let included = resolver.resolve(includes: includes, sourceIds: mainIds)
        async let revIncluded = resolver.resolveRev(revIncludes: revIncludes, mainIds: mainIds)
        let includeEntries = includeEntryTuples(from: try await included + revIncluded, baseURL: baseURL)
        let bundleData = buildBundleJSON(entries: entries, includeEntries: includeEntries,
                                         total: result.total, selfURL: base, nextURL: nextURL)
        var headers = HTTPFields()
        headers[.contentType] = goalFhirJSON
        return Response(status: .ok, headers: headers,
                        body: ResponseBody(byteBuffer: ByteBuffer(bytes: bundleData)))
    }

    // POST /Goal/_search — form-encoded search
    group.post("_search") { request, _ in
        let ct = request.headers[.contentType] ?? ""
        guard ct.contains("application/x-www-form-urlencoded") else {
            throw FHIRRouteError.invalidBody("Content-Type must be application/x-www-form-urlencoded for _search")
        }
        var req = request
        let bodyBuffer = try await req.collectBody(upTo: goalMaxBodyBytes)
        let urlPairs = request.uri.queryParameters.map { (key: $0.key, value: $0.value) }
        let pairs = urlPairs + parseFormPairs(from: bodyBuffer)
        if isStrictHandling(request) {
            let bad = unknownParams(in: pairs, known: knownGoalParams)
            if !bad.isEmpty { throw FHIRRouteError.unknownParams(bad) }
        }
        var query = parseGoalQuery(from: pairs)
        let elements = parseElements(from: pairs)
        let summary = parseSummary(from: pairs)
        let includes = parseIncludes(from: pairs)
        let revIncludes = parseRevIncludes(from: pairs)
        if summary == .count { query.count = 0; query.totalMode = .accurate }
        let result = try await store.search(query: query)

        let base = goalSelfURL(request)
        let baseURL = serverBaseURL(request)
        if summary == .count {
            let bundleData = buildBundleJSON(entries: [], total: result.total, selfURL: base, nextURL: nil)
            var headers = HTTPFields()
            headers[.contentType] = goalFhirJSON
            return Response(status: .ok, headers: headers,
                            body: ResponseBody(byteBuffer: ByteBuffer(bytes: bundleData)))
        }
        let nextURL = result.nextCursor.map { nextGoalPageURL(selfURL: base, cursor: $0, count: query.count) }
        let entries = result.entries.map { e -> (fullUrl: String, json: Data) in
            var json = e.jsonWithMeta
            if let s = summary, s != .false { json = applySummary(json, mode: s, summaryFields: goalSummaryFields) }
            if let elems = elements { json = applyElements(json, elements: elems) }
            return ("\(baseURL)/Goal/\(e.id)", json)
        }
        let mainIds = result.entries.map(\.id)
        let resolver = IncludeResolver(client: store.client, logger: logger)
        async let included = resolver.resolve(includes: includes, sourceIds: mainIds)
        async let revIncluded = resolver.resolveRev(revIncludes: revIncludes, mainIds: mainIds)
        let includeEntries = includeEntryTuples(from: try await included + revIncluded, baseURL: baseURL)
        let bundleData = buildBundleJSON(entries: entries, includeEntries: includeEntries,
                                         total: result.total, selfURL: base, nextURL: nextURL)
        var headers = HTTPFields()
        headers[.contentType] = goalFhirJSON
        return Response(status: .ok, headers: headers,
                        body: ResponseBody(byteBuffer: ByteBuffer(bytes: bundleData)))
    }
}

// ── Query parser ──────────────────────────────────────────────────────────────

func parseGoalQuery(from pairs: some Collection<(key: Substring, value: Substring)>) -> GoalSearchQuery {
    func first(_ key: String) -> Substring? {
        pairs.first(where: { $0.key == key[...] })?.value
    }
    func all(_ key: String) -> [Substring] {
        pairs.filter { $0.key == key[...] }.map { $0.value }
    }

    let lifecycleStatus    = all("lifecycle-status").flatMap { GoalSearchQuery.TokenParam.parseList(String($0)) }
    let lifecycleStatusNot = all("lifecycle-status:not").flatMap { GoalSearchQuery.TokenParam.parseList(String($0)) }
    let achievementStatus  = all("achievement-status").flatMap { GoalSearchQuery.TokenParam.parseList(String($0)) }
    let category           = all("category").flatMap { GoalSearchQuery.TokenParam.parseList(String($0)) }
    let categoryNot        = all("category:not").flatMap { GoalSearchQuery.TokenParam.parseList(String($0)) }
    let identifier         = first("identifier").map { GoalSearchQuery.IdentifierParam.parseList(String($0)) } ?? []

    let startDate  = all("start-date").compactMap { GoalSearchQuery.DateParam.parse(String($0)) }
    let targetDate = all("target-date").compactMap { GoalSearchQuery.DateParam.parse(String($0)) }

    let subject = first("subject").map(String.init)
    let patient = first("patient").map(String.init)

    let id          = first("_id").map {
        String($0).split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }
    } ?? []
    let lastUpdated = all("_lastUpdated").compactMap { GoalSearchQuery.DateParam.parse(String($0)) }
    let sort        = GoalSearchQuery.SortOrder.parse(first("_sort").map(String.init) ?? "-_lastUpdated")
    let count       = min(first("_count").flatMap { Int($0) } ?? 20, goalMaxCount)
    let cursor      = first("_cursor").flatMap { GoalSearchQuery.SearchCursor.decode(String($0)) }
    let totalMode   = GoalSearchQuery.TotalMode.parse(first("_total").map(String.init))

    var missing: [String: Bool] = [:]
    for p in ["lifecycle-status", "achievement-status", "category", "identifier",
              "start-date", "target-date", "subject", "patient"] {
        if let v = first("\(p):missing").map(String.init) {
            if v == "true" { missing[p] = true } else if v == "false" { missing[p] = false }
        }
    }

    let chains = parseChainParams(from: pairs)
    let has    = parseHasParams(from: pairs)

    return GoalSearchQuery(
        lifecycleStatus: lifecycleStatus, lifecycleStatusNot: lifecycleStatusNot,
        achievementStatus: achievementStatus,
        category: category, categoryNot: categoryNot,
        identifier: identifier,
        startDate: startDate, targetDate: targetDate,
        subject: subject, patient: patient,
        id: id, lastUpdated: lastUpdated,
        missing: missing, chains: chains, has: has,
        totalMode: totalMode, count: count, sort: sort, cursor: cursor)
}

// ── Helpers ───────────────────────────────────────────────────────────────────

private func goalConditionalResponse(request: Request, versionId: Int64, lastUpdated: Date) -> Response? {
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

private func goalRequireFHIRContentType(_ request: Request) throws {
    let ct = request.headers[.contentType] ?? ""
    guard ct.contains(goalFhirJSON) || ct.contains("application/json") else {
        throw FHIRRouteError.unsupportedMediaType
    }
}

private func goalDecodeFHIR<T: Decodable>(_ type: T.Type, from buffer: ByteBuffer) throws -> T {
    let data = Data(buffer.readableBytesView)
    do { return try JSONDecoder().decode(type, from: data) }
    catch { throw FHIRRouteError.invalidBody(error.localizedDescription) }
}

private func goalSelfURL(_ request: Request) -> String {
    let authority = request.head.authority ?? "localhost"
    return "http://\(authority)\(request.uri)"
}

func nextGoalPageURL(selfURL: String, cursor: GoalSearchQuery.SearchCursor, count: Int) -> String {
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

private func goalParseETag(_ raw: String?) -> Int64? {
    guard let raw else { return nil }
    let stripped = raw
        .trimmingCharacters(in: .whitespaces)
        .replacingOccurrences(of: "W/", with: "")
        .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
    return Int64(stripped)
}
