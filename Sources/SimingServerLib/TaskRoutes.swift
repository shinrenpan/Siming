import Foundation
import HTTPTypes
import Hummingbird
import Logging
import ModelsR4
import NIOCore
import SimingCore

private let taskMaxCount = 100
private let taskFhirJSON = "application/fhir+json"
private let taskMaxBodyBytes = 4 * 1024 * 1024
private let taskIfNoneExistHeader = HTTPField.Name("If-None-Exist")!
private let taskPreferHeader = HTTPField.Name("Prefer")!

let knownTaskParams: Set<String> = [
    "status", "intent", "priority", "code", "business-status", "performer",
    "identifier", "group-identifier",
    "authored-on", "modified", "period",
    "subject", "patient", "encounter", "focus", "owner", "requester",
    "based-on", "part-of",
    "status:not", "intent:not", "priority:not", "code:not",
    "business-status:not", "performer:not", "identifier:not",
    "_id", "_lastUpdated", "_sort", "_count", "_cursor", "_total",
    "_elements", "_format", "_summary", "_include", "_revinclude",
]

public func addTaskRoutes(
    to router: Router<SimingRequestContext>,
    store: TaskStore,
    logger: Logger
) {
    let group = router.group("Task")

    // POST /Task — create
    group.post { request, _ in
        try taskRequireFHIRContentType(request)
        let preferReturn = parsePreferReturn(request.headers[taskPreferHeader])
        var req = request
        let bodyBuffer = try await req.collectBody(upTo: taskMaxBodyBytes)
        try validateResourceType("Task", from: Data(bodyBuffer.readableBytesView))
        let task = try taskDecodeFHIR(ModelsR4.Task.self, from: bodyBuffer)

        if let ifNoneExist = request.headers[taskIfNoneExistHeader] {
            let pairs = parseQueryString(ifNoneExist)
            var checkQuery = try parseTaskQuery(from: pairs)
            checkQuery.count = 2; checkQuery.totalMode = .none; checkQuery.cursor = nil
            let matches = try await store.search(query: checkQuery)
            if matches.entries.count > 1 {
                throw FHIRServerError.multipleMatches(resourceType: "Task")
            }
            if let existing = matches.entries.first {
                var headers = HTTPFields()
                headers[.contentType]  = taskFhirJSON
                headers[.eTag]         = "W/\"\(existing.versionId)\""
                headers[.lastModified] = httpDate(existing.lastUpdated)
                headers[.location] = "\(serverBaseURL(request))/Task/\(existing.id)/_history/\(existing.versionId)"
                return Response(status: .ok, headers: headers,
                                body: preferBody(preferReturn, resource: existing.jsonWithMeta))
            }
        }

        let result = try await store.create(task)
        var headers = HTTPFields()
        headers[.contentType]  = taskFhirJSON
        headers[.eTag]         = "W/\"\(result.versionId)\""
        headers[.lastModified] = httpDate(result.lastUpdated)
        headers[.location] = "\(serverBaseURL(request))/Task/\(result.id)/_history/\(result.versionId)"
        return Response(status: .created, headers: headers,
                        body: preferBody(preferReturn, resource: result.jsonData))
    }

    // PUT /Task?<search> — conditional update
    group.put { request, _ in
        try taskRequireFHIRContentType(request)
        let preferReturn = parsePreferReturn(request.headers[taskPreferHeader])
        let qpPairs = request.uri.queryParameters.map { (key: $0.key, value: $0.value) }
        guard !qpPairs.isEmpty else {
            throw FHIRRouteError.invalidBody("PUT /Task requires search parameters for conditional update")
        }
        var req = request
        let bodyBuffer = try await req.collectBody(upTo: taskMaxBodyBytes)
        try validateResourceType("Task", from: Data(bodyBuffer.readableBytesView))
        let task = try taskDecodeFHIR(ModelsR4.Task.self, from: bodyBuffer)
        let ifMatch = taskParseETag(request.headers[.ifMatch])

        var checkQuery = try parseTaskQuery(from: qpPairs)
        checkQuery.count = 2; checkQuery.totalMode = .none; checkQuery.cursor = nil
        let matches = try await store.search(query: checkQuery)

        switch matches.entries.count {
        case 0:
            let result = try await store.create(task)
            var headers = HTTPFields()
            headers[.contentType]  = taskFhirJSON
            headers[.eTag]         = "W/\"\(result.versionId)\""
            headers[.lastModified] = httpDate(result.lastUpdated)
            headers[.location] = "\(serverBaseURL(request))/Task/\(result.id)/_history/\(result.versionId)"
            return Response(status: .created, headers: headers,
                            body: preferBody(preferReturn, resource: result.jsonData))
        case 1:
            let existingId = matches.entries[0].id
            let result = try await store.update(id: existingId, task: task, ifMatch: ifMatch)
            var headers = HTTPFields()
            headers[.contentType]  = taskFhirJSON
            headers[.eTag]         = "W/\"\(result.versionId)\""
            headers[.lastModified] = httpDate(result.lastUpdated)
            headers[.location] = "\(serverBaseURL(request))/Task/\(result.id)/_history/\(result.versionId)"
            return Response(status: .ok, headers: headers,
                            body: preferBody(preferReturn, resource: result.jsonData))
        default:
            throw FHIRServerError.multipleMatches(resourceType: "Task")
        }
    }

    // GET /Task/:id — read
    group.get(":id") { request, context in
        let id = context.parameters.get("id") ?? ""
        let result = try await store.read(id: id)
        if let earlyResponse = taskConditionalResponse(request: request, versionId: result.versionId, lastUpdated: result.lastUpdated) {
            return earlyResponse
        }
        let pairs = request.uri.queryParameters.map { (key: $0.key, value: $0.value) }
        let elements = parseElements(from: pairs)
        let summary  = parseSummary(from: pairs)
        var json = result.jsonData
        if let s = summary, s != .false { json = applySummary(json, mode: s, summaryFields: taskSummaryFields) }
        if let elems = elements { json = applyElements(json, elements: elems) }
        var headers = HTTPFields()
        headers[.contentType]  = taskFhirJSON
        headers[.eTag]         = "W/\"\(result.versionId)\""
        headers[.lastModified] = httpDate(result.lastUpdated)
        headers[.contentLocation] = contentLocation(request, versionId: result.versionId)
        return Response(status: .ok, headers: headers,
                        body: ResponseBody(byteBuffer: ByteBuffer(bytes: json)))
    }

    // GET /Task/:id/_history/:vid — vread
    group.get(":id/_history/:vid") { request, context in
        let id  = context.parameters.get("id")  ?? ""
        let vid = context.parameters.get("vid").flatMap { Int64($0) } ?? 0
        let result = try await store.vread(id: id, versionId: vid)
        var headers = HTTPFields()
        headers[.contentType]  = taskFhirJSON
        headers[.eTag]         = "W/\"\(result.versionId)\""
        headers[.lastModified] = httpDate(result.lastUpdated)
        headers[.contentLocation] = contentLocation(request, versionId: result.versionId)
        return Response(status: .ok, headers: headers,
                        body: ResponseBody(byteBuffer: ByteBuffer(bytes: result.jsonData)))
    }

    // GET /Task/:id/_history — instance history
    group.get(":id/_history") { request, context in
        let id = context.parameters.get("id") ?? ""
        let qp = request.uri.queryParameters
        let since: Date? = qp["_since"].flatMap { parseFHIRInstant(String($0)) }
        let count = min(qp["_count"].flatMap { Int($0) } ?? 50, taskMaxCount)
        let entries = try await store.history(id: id, since: since, count: count)
        let baseURL = serverBaseURL(request)
        let bundleData = buildHistoryBundleJSON(entries: entries, baseURL: baseURL, selfURL: selfURL(request))
        var headers = HTTPFields()
        headers[.contentType] = taskFhirJSON
        return Response(status: .ok, headers: headers,
                        body: ResponseBody(byteBuffer: ByteBuffer(bytes: bundleData)))
    }

    // GET /Task/_history — type history
    group.get("_history") { request, _ in
        let qp = request.uri.queryParameters
        let since: Date? = qp["_since"].flatMap { parseFHIRInstant(String($0)) }
        let count = min(qp["_count"].flatMap { Int($0) } ?? 50, 100)
        let entries = try await store.typeHistory(since: since, count: count)
        let baseURL = serverBaseURL(request)
        let bundleData = buildHistoryBundleJSON(entries: entries, baseURL: baseURL, selfURL: selfURL(request))
        var headers = HTTPFields()
        headers[.contentType] = taskFhirJSON
        return Response(status: .ok, headers: headers,
                        body: ResponseBody(byteBuffer: ByteBuffer(bytes: bundleData)))
    }

    // PUT /Task/:id — update
    group.put(":id") { request, context in
        try taskRequireFHIRContentType(request)
        let preferReturn = parsePreferReturn(request.headers[taskPreferHeader])
        let id = context.parameters.get("id") ?? ""
        let ifMatch = taskParseETag(request.headers[.ifMatch])
        var req = request
        let bodyBuffer = try await req.collectBody(upTo: taskMaxBodyBytes)
        try validateResourceType("Task", from: Data(bodyBuffer.readableBytesView))
        let task = try taskDecodeFHIR(ModelsR4.Task.self, from: bodyBuffer)
        let result = try await store.update(id: id, task: task, ifMatch: ifMatch)
        var headers = HTTPFields()
        headers[.contentType]  = taskFhirJSON
        headers[.eTag]         = "W/\"\(result.versionId)\""
        headers[.lastModified] = httpDate(result.lastUpdated)
        headers[.location] = "\(serverBaseURL(request))/Task/\(result.id)/_history/\(result.versionId)"
        return Response(status: .ok, headers: headers,
                        body: preferBody(preferReturn, resource: result.jsonData))
    }

    // PATCH /Task/:id — JSON Patch (RFC 6902)
    group.patch(":id") { request, context in
        let id = context.parameters.get("id") ?? ""
        let ct = request.headers[.contentType] ?? ""
        guard ct.contains("application/json-patch+json") else {
            throw FHIRRouteError.invalidBody("PATCH requires Content-Type: application/json-patch+json")
        }
        let ifMatch = taskParseETag(request.headers[.ifMatch])
        var req = request
        let bodyBuffer = try await req.collectBody(upTo: taskMaxBodyBytes)
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
        let task: ModelsR4.Task
        do { task = try JSONDecoder().decode(ModelsR4.Task.self, from: patchedJSON) }
        catch { throw FHIRRouteError.unprocessableEntity("Patched resource is not valid FHIR: \(error.localizedDescription)") }
        let result = try await store.update(id: id, task: task, ifMatch: ifMatch)
        var headers = HTTPFields()
        headers[.contentType]  = taskFhirJSON
        headers[.eTag]         = "W/\"\(result.versionId)\""
        headers[.lastModified] = httpDate(result.lastUpdated)
        return Response(status: .ok, headers: headers,
                        body: ResponseBody(byteBuffer: ByteBuffer(bytes: result.jsonData)))
    }

    // DELETE /Task/:id — logical delete
    group.delete(":id") { request, context in
        let id = context.parameters.get("id") ?? ""
        let ifMatch = taskParseETag(request.headers[.ifMatch])
        let result = try await store.delete(id: id, ifMatch: ifMatch)
        var headers = HTTPFields()
        headers[.eTag]         = "W/\"\(result.versionId)\""
        headers[.lastModified] = httpDate(result.lastUpdated)
        return Response(status: .noContent, headers: headers, body: .init())
    }

    // DELETE /Task?<search> — conditional delete
    group.delete { request, _ in
        let qpPairs = request.uri.queryParameters.map { (key: $0.key, value: $0.value) }
        guard !qpPairs.isEmpty else {
            throw FHIRRouteError.invalidBody("DELETE /Task requires search parameters for conditional delete")
        }
        var checkQuery = try parseTaskQuery(from: qpPairs)
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
            throw FHIRServerError.multipleMatches(resourceType: "Task")
        }
    }

    // GET /Task — search
    group.get { request, _ in
        let pairs = request.uri.queryParameters.map { (key: $0.key, value: $0.value) }
        if isStrictHandling(request) {
            let bad = unknownParams(in: pairs, known: knownTaskParams)
            if !bad.isEmpty { throw FHIRRouteError.unknownParams(bad) }
        }
        var query = try parseTaskQuery(from: pairs)
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
            headers[.contentType] = taskFhirJSON
            return Response(status: .ok, headers: headers,
                            body: ResponseBody(byteBuffer: ByteBuffer(bytes: bundleData)))
        }
        let nextURL = result.nextCursor.map { nextTaskPageURL(selfURL: base, cursor: $0, count: query.count) }
        let entries = result.entries.map { e -> (fullUrl: String, json: Data) in
            var json = e.jsonWithMeta
            if let s = summary, s != .false { json = applySummary(json, mode: s, summaryFields: taskSummaryFields) }
            if let elems = elements { json = applyElements(json, elements: elems) }
            return ("\(baseURL)/Task/\(e.id)", json)
        }
        let mainIds = result.entries.map(\.id)
        let resolver = IncludeResolver(client: store.client, logger: logger)
        async let included = resolver.resolve(includes: includes, sourceIds: mainIds)
        async let revIncluded = resolver.resolveRev(revIncludes: revIncludes, mainIds: mainIds)
        let includeEntries = includeEntryTuples(from: try await included + revIncluded, baseURL: baseURL)
        let bundleData = buildBundleJSON(entries: entries, includeEntries: includeEntries,
                                         total: result.total, selfURL: base, nextURL: nextURL)
        var headers = HTTPFields()
        headers[.contentType] = taskFhirJSON
        return Response(status: .ok, headers: headers,
                        body: ResponseBody(byteBuffer: ByteBuffer(bytes: bundleData)))
    }

    // POST /Task/_search — form-encoded search
    group.post("_search") { request, _ in
        let ct = request.headers[.contentType] ?? ""
        guard ct.contains("application/x-www-form-urlencoded") else {
            throw FHIRRouteError.invalidBody("Content-Type must be application/x-www-form-urlencoded for _search")
        }
        var req = request
        let bodyBuffer = try await req.collectBody(upTo: taskMaxBodyBytes)
        let urlPairs = request.uri.queryParameters.map { (key: $0.key, value: $0.value) }
        let pairs = urlPairs + parseFormPairs(from: bodyBuffer)
        if isStrictHandling(request) {
            let bad = unknownParams(in: pairs, known: knownTaskParams)
            if !bad.isEmpty { throw FHIRRouteError.unknownParams(bad) }
        }
        var query = try parseTaskQuery(from: pairs)
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
            headers[.contentType] = taskFhirJSON
            return Response(status: .ok, headers: headers,
                            body: ResponseBody(byteBuffer: ByteBuffer(bytes: bundleData)))
        }
        let nextURL = result.nextCursor.map { nextTaskPageURL(selfURL: base, cursor: $0, count: query.count) }
        let entries = result.entries.map { e -> (fullUrl: String, json: Data) in
            var json = e.jsonWithMeta
            if let s = summary, s != .false { json = applySummary(json, mode: s, summaryFields: taskSummaryFields) }
            if let elems = elements { json = applyElements(json, elements: elems) }
            return ("\(baseURL)/Task/\(e.id)", json)
        }
        let mainIds = result.entries.map(\.id)
        let resolver = IncludeResolver(client: store.client, logger: logger)
        async let included = resolver.resolve(includes: includes, sourceIds: mainIds)
        async let revIncluded = resolver.resolveRev(revIncludes: revIncludes, mainIds: mainIds)
        let includeEntries = includeEntryTuples(from: try await included + revIncluded, baseURL: baseURL)
        let bundleData = buildBundleJSON(entries: entries, includeEntries: includeEntries,
                                         total: result.total, selfURL: base, nextURL: nextURL)
        var headers = HTTPFields()
        headers[.contentType] = taskFhirJSON
        return Response(status: .ok, headers: headers,
                        body: ResponseBody(byteBuffer: ByteBuffer(bytes: bundleData)))
    }
}

// ── Query parser ──────────────────────────────────────────────────────────────

func parseTaskQuery(from pairs: some Collection<(key: Substring, value: Substring)>) throws -> TaskSearchQuery {
    let pairs = normalizeReferenceTypeModifiers(pairs)
    func first(_ key: String) -> Substring? {
        pairs.first(where: { $0.key == key[...] })?.value
    }
    func all(_ key: String) -> [Substring] {
        pairs.filter { $0.key == key[...] }.map { $0.value }
    }
    func tokens(_ key: String) -> [TaskSearchQuery.TokenParam] {
        all(key).flatMap { TaskSearchQuery.TokenParam.parseList(String($0)) }
    }

    let identifier      = first("identifier").map { TaskSearchQuery.IdentifierParam.parseList(String($0)) } ?? []
    let identifierNot   = first("identifier:not").map { TaskSearchQuery.IdentifierParam.parseList(String($0)) } ?? []
    let groupIdentifier = first("group-identifier").map { TaskSearchQuery.IdentifierParam.parseList(String($0)) } ?? []

    let authoredOn = try parseDateParams(all("authored-on"), "authored-on", TaskSearchQuery.DateParam.parse)
    let modified   = try parseDateParams(all("modified"), "modified", TaskSearchQuery.DateParam.parse)
    let period     = try parseDateParams(all("period"), "period", TaskSearchQuery.DateParam.parse)

    let id          = first("_id").map {
        String($0).split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }
    } ?? []
    let lastUpdated = try parseDateParams(all("_lastUpdated"), "_lastUpdated", TaskSearchQuery.DateParam.parse)
    let sortKeys = TaskSearchQuery.parseSortKeys(first("_sort").map(String.init) ?? "-_lastUpdated")
    let count       = min(first("_count").flatMap { Int($0) } ?? 20, taskMaxCount)
    let cursor      = first("_cursor").flatMap { SearchCursor.decode(String($0)) }
    let totalMode   = TaskSearchQuery.TotalMode.parse(first("_total").map(String.init))

    var missing: [String: Bool] = [:]
    for p in ["status", "intent", "priority", "code", "business-status", "performer",
              "identifier", "group-identifier",
              "authored-on", "modified", "period",
              "subject", "patient", "encounter", "focus", "owner", "requester",
              "based-on", "part-of"] {
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

    var query = TaskSearchQuery(
        status: tokens("status"), statusNot: tokens("status:not"),
        intent: tokens("intent"), intentNot: tokens("intent:not"),
        priority: tokens("priority"), priorityNot: tokens("priority:not"),
        code: tokens("code"), codeNot: tokens("code:not"),
        businessStatus: tokens("business-status"), businessStatusNot: tokens("business-status:not"),
        performer: tokens("performer"), performerNot: tokens("performer:not"),
        identifier: identifier, identifierNot: identifierNot,
        groupIdentifier: groupIdentifier,
        authoredOn: authoredOn, modified: modified, period: period,
        subject: first("subject").map(String.init),
        patient: first("patient").map(String.init),
        encounter: first("encounter").map(String.init),
        focus: first("focus").map(String.init),
        owner: first("owner").map(String.init),
        requester: first("requester").map(String.init),
        basedOn: first("based-on").map(String.init),
        partOf: first("part-of").map(String.init),
        id: id, lastUpdated: lastUpdated,
        tokenTexts: tokenTexts,
        missing: missing, chains: chains, has: has,
        totalMode: totalMode, count: count, sortKeys: sortKeys, cursor: cursor)
    query.meta = parseMetaSearchParams(from: pairs)
    return query
}

// ── Helpers ───────────────────────────────────────────────────────────────────

private func taskConditionalResponse(request: Request, versionId: Int64, lastUpdated: Date) -> Response? {
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

private func taskRequireFHIRContentType(_ request: Request) throws {
    let ct = request.headers[.contentType] ?? ""
    guard ct.contains(taskFhirJSON) || ct.contains("application/json") else {
        throw FHIRRouteError.unsupportedMediaType
    }
}

private func taskDecodeFHIR<T: Decodable>(_ type: T.Type, from buffer: ByteBuffer) throws -> T {
    let data = Data(buffer.readableBytesView)
    do { return try JSONDecoder().decode(type, from: data) }
    catch { throw FHIRRouteError.invalidBody(error.localizedDescription) }
}

func nextTaskPageURL(selfURL: String, cursor: SearchCursor, count: Int) -> String {
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

private func taskParseETag(_ raw: String?) -> Int64? {
    guard let raw else { return nil }
    let stripped = raw
        .trimmingCharacters(in: .whitespaces)
        .replacingOccurrences(of: "W/", with: "")
        .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
    return Int64(stripped)
}
