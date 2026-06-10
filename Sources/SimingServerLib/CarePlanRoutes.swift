import Foundation
import HTTPTypes
import Hummingbird
import Logging
import ModelsR4
import NIOCore
import SimingCore

private let carePlanMaxCount = 100
private let carePlanFhirJSON = "application/fhir+json"
private let carePlanMaxBodyBytes = 4 * 1024 * 1024
private let carePlanIfNoneExistHeader = HTTPField.Name("If-None-Exist")!
private let carePlanPreferHeader = HTTPField.Name("Prefer")!

let knownCarePlanParams: Set<String> = [
    "status", "intent", "category", "identifier", "activity-code",
    "date", "activity-date", "activity-date:not",
    "instantiates-canonical", "instantiates-uri",
    "subject", "patient", "encounter", "care-team", "condition", "goal",
    "based-on", "part-of", "replaces", "performer", "activity-reference",
    "status:not", "intent:not", "category:not", "activity-code:not",
    "identifier:not",
    "_id", "_lastUpdated", "_sort", "_count", "_cursor", "_total",
    "_elements", "_format", "_summary", "_include", "_revinclude",
]

public func addCarePlanRoutes(
    to router: Router<BasicRequestContext>,
    store: CarePlanStore,
    logger: Logger
) {
    let group = router.group("CarePlan")

    // POST /CarePlan — create
    group.post { request, _ in
        try cpRequireFHIRContentType(request)
        let returnMinimal = (request.headers[carePlanPreferHeader] ?? "").contains("return=minimal")
        var req = request
        let bodyBuffer = try await req.collectBody(upTo: carePlanMaxBodyBytes)
        let carePlan = try cpDecodeFHIR(CarePlan.self, from: bodyBuffer)

        if let ifNoneExist = request.headers[carePlanIfNoneExistHeader] {
            let pairs = parseQueryString(ifNoneExist)
            var checkQuery = parseCarePlanQuery(from: pairs)
            checkQuery.count = 2; checkQuery.totalMode = .none; checkQuery.cursor = nil
            let matches = try await store.search(query: checkQuery)
            if matches.entries.count > 1 {
                throw FHIRServerError.multipleMatches(resourceType: "CarePlan")
            }
            if let existing = matches.entries.first {
                var headers = HTTPFields()
                headers[.contentType]  = carePlanFhirJSON
                headers[.eTag]         = "W/\"\(existing.versionId)\""
                headers[.lastModified] = httpDate(existing.lastUpdated)
                headers[.location]     = "/CarePlan/\(existing.id)/_history/\(existing.versionId)"
                return Response(status: .ok, headers: headers,
                                body: returnMinimal ? .init() : ResponseBody(byteBuffer: ByteBuffer(bytes: existing.jsonWithMeta)))
            }
        }

        let result = try await store.create(carePlan)
        var headers = HTTPFields()
        headers[.contentType]  = carePlanFhirJSON
        headers[.eTag]         = "W/\"\(result.versionId)\""
        headers[.lastModified] = httpDate(result.lastUpdated)
        headers[.location]     = "/CarePlan/\(result.id)/_history/\(result.versionId)"
        return Response(status: .created, headers: headers,
                        body: returnMinimal ? .init() : ResponseBody(byteBuffer: ByteBuffer(bytes: result.jsonData)))
    }

    // PUT /CarePlan?<search> — conditional update
    group.put { request, _ in
        try cpRequireFHIRContentType(request)
        let returnMinimal = (request.headers[carePlanPreferHeader] ?? "").contains("return=minimal")
        let qpPairs = request.uri.queryParameters.map { (key: $0.key, value: $0.value) }
        guard !qpPairs.isEmpty else {
            throw FHIRRouteError.invalidBody("PUT /CarePlan requires search parameters for conditional update")
        }
        var req = request
        let bodyBuffer = try await req.collectBody(upTo: carePlanMaxBodyBytes)
        let carePlan = try cpDecodeFHIR(CarePlan.self, from: bodyBuffer)
        let ifMatch = cpParseETag(request.headers[.ifMatch])

        var checkQuery = parseCarePlanQuery(from: qpPairs)
        checkQuery.count = 2; checkQuery.totalMode = .none; checkQuery.cursor = nil
        let matches = try await store.search(query: checkQuery)

        switch matches.entries.count {
        case 0:
            let result = try await store.create(carePlan)
            var headers = HTTPFields()
            headers[.contentType]  = carePlanFhirJSON
            headers[.eTag]         = "W/\"\(result.versionId)\""
            headers[.lastModified] = httpDate(result.lastUpdated)
            headers[.location]     = "/CarePlan/\(result.id)/_history/\(result.versionId)"
            return Response(status: .created, headers: headers,
                            body: returnMinimal ? .init() : ResponseBody(byteBuffer: ByteBuffer(bytes: result.jsonData)))
        case 1:
            let existingId = matches.entries[0].id
            let result = try await store.update(id: existingId, carePlan: carePlan, ifMatch: ifMatch)
            var headers = HTTPFields()
            headers[.contentType]  = carePlanFhirJSON
            headers[.eTag]         = "W/\"\(result.versionId)\""
            headers[.lastModified] = httpDate(result.lastUpdated)
            headers[.location]     = "/CarePlan/\(result.id)/_history/\(result.versionId)"
            return Response(status: .ok, headers: headers,
                            body: returnMinimal ? .init() : ResponseBody(byteBuffer: ByteBuffer(bytes: result.jsonData)))
        default:
            throw FHIRServerError.multipleMatches(resourceType: "CarePlan")
        }
    }

    // GET /CarePlan/:id — read
    group.get(":id") { request, context in
        let id = context.parameters.get("id") ?? ""
        let result = try await store.read(id: id)
        if let earlyResponse = cpConditionalResponse(request: request, versionId: result.versionId, lastUpdated: result.lastUpdated) {
            return earlyResponse
        }
        let pairs = request.uri.queryParameters.map { (key: $0.key, value: $0.value) }
        let elements = parseElements(from: pairs)
        let summary  = parseSummary(from: pairs)
        var json = result.jsonData
        if let s = summary, s != .false { json = applySummary(json, mode: s, summaryFields: carePlanSummaryFields) }
        if let elems = elements { json = applyElements(json, elements: elems) }
        var headers = HTTPFields()
        headers[.contentType]  = carePlanFhirJSON
        headers[.eTag]         = "W/\"\(result.versionId)\""
        headers[.lastModified] = httpDate(result.lastUpdated)
        return Response(status: .ok, headers: headers,
                        body: ResponseBody(byteBuffer: ByteBuffer(bytes: json)))
    }

    // GET /CarePlan/:id/_history/:vid — vread
    group.get(":id/_history/:vid") { request, context in
        let id  = context.parameters.get("id")  ?? ""
        let vid = context.parameters.get("vid").flatMap { Int64($0) } ?? 0
        let result = try await store.vread(id: id, versionId: vid)
        var headers = HTTPFields()
        headers[.contentType]  = carePlanFhirJSON
        headers[.eTag]         = "W/\"\(result.versionId)\""
        headers[.lastModified] = httpDate(result.lastUpdated)
        return Response(status: .ok, headers: headers,
                        body: ResponseBody(byteBuffer: ByteBuffer(bytes: result.jsonData)))
    }

    // GET /CarePlan/:id/_history — instance history
    group.get(":id/_history") { request, context in
        let id = context.parameters.get("id") ?? ""
        let qp = request.uri.queryParameters
        let since: Date? = qp["_since"].flatMap { parseFHIRInstant(String($0)) }
        let count = min(qp["_count"].flatMap { Int($0) } ?? 50, carePlanMaxCount)
        let entries = try await store.history(id: id, since: since, count: count)
        let baseURL = serverBaseURL(request)
        let bundleData = buildHistoryBundleJSON(entries: entries, baseURL: baseURL)
        var headers = HTTPFields()
        headers[.contentType] = carePlanFhirJSON
        return Response(status: .ok, headers: headers,
                        body: ResponseBody(byteBuffer: ByteBuffer(bytes: bundleData)))
    }

    // GET /CarePlan/_history — type history
    group.get("_history") { request, _ in
        let qp = request.uri.queryParameters
        let since: Date? = qp["_since"].flatMap { parseFHIRInstant(String($0)) }
        let count = min(qp["_count"].flatMap { Int($0) } ?? 50, 100)
        let entries = try await store.typeHistory(since: since, count: count)
        let baseURL = serverBaseURL(request)
        let bundleData = buildHistoryBundleJSON(entries: entries, baseURL: baseURL)
        var headers = HTTPFields()
        headers[.contentType] = carePlanFhirJSON
        return Response(status: .ok, headers: headers,
                        body: ResponseBody(byteBuffer: ByteBuffer(bytes: bundleData)))
    }

    // PUT /CarePlan/:id — update
    group.put(":id") { request, context in
        try cpRequireFHIRContentType(request)
        let returnMinimal = (request.headers[carePlanPreferHeader] ?? "").contains("return=minimal")
        let id = context.parameters.get("id") ?? ""
        let ifMatch = cpParseETag(request.headers[.ifMatch])
        var req = request
        let bodyBuffer = try await req.collectBody(upTo: carePlanMaxBodyBytes)
        let carePlan = try cpDecodeFHIR(CarePlan.self, from: bodyBuffer)
        let result = try await store.update(id: id, carePlan: carePlan, ifMatch: ifMatch)
        var headers = HTTPFields()
        headers[.contentType]  = carePlanFhirJSON
        headers[.eTag]         = "W/\"\(result.versionId)\""
        headers[.lastModified] = httpDate(result.lastUpdated)
        headers[.location]     = "/CarePlan/\(result.id)/_history/\(result.versionId)"
        return Response(status: .ok, headers: headers,
                        body: returnMinimal ? .init() : ResponseBody(byteBuffer: ByteBuffer(bytes: result.jsonData)))
    }

    // PATCH /CarePlan/:id — JSON Patch (RFC 6902)
    group.patch(":id") { request, context in
        let id = context.parameters.get("id") ?? ""
        let ct = request.headers[.contentType] ?? ""
        guard ct.contains("application/json-patch+json") else {
            throw FHIRRouteError.invalidBody("PATCH requires Content-Type: application/json-patch+json")
        }
        let ifMatch = cpParseETag(request.headers[.ifMatch])
        var req = request
        let bodyBuffer = try await req.collectBody(upTo: carePlanMaxBodyBytes)
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
        let carePlan: CarePlan
        do { carePlan = try JSONDecoder().decode(CarePlan.self, from: patchedJSON) }
        catch { throw FHIRRouteError.unprocessableEntity("Patched resource is not valid FHIR: \(error.localizedDescription)") }
        let result = try await store.update(id: id, carePlan: carePlan, ifMatch: ifMatch)
        var headers = HTTPFields()
        headers[.contentType]  = carePlanFhirJSON
        headers[.eTag]         = "W/\"\(result.versionId)\""
        headers[.lastModified] = httpDate(result.lastUpdated)
        return Response(status: .ok, headers: headers,
                        body: ResponseBody(byteBuffer: ByteBuffer(bytes: result.jsonData)))
    }

    // DELETE /CarePlan/:id — logical delete
    group.delete(":id") { request, context in
        let id = context.parameters.get("id") ?? ""
        let ifMatch = cpParseETag(request.headers[.ifMatch])
        let result = try await store.delete(id: id, ifMatch: ifMatch)
        var headers = HTTPFields()
        headers[.eTag]         = "W/\"\(result.versionId)\""
        headers[.lastModified] = httpDate(result.lastUpdated)
        return Response(status: .noContent, headers: headers, body: .init())
    }

    // DELETE /CarePlan?<search> — conditional delete
    group.delete { request, _ in
        let qpPairs = request.uri.queryParameters.map { (key: $0.key, value: $0.value) }
        guard !qpPairs.isEmpty else {
            throw FHIRRouteError.invalidBody("DELETE /CarePlan requires search parameters for conditional delete")
        }
        var checkQuery = parseCarePlanQuery(from: qpPairs)
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
            throw FHIRServerError.multipleMatches(resourceType: "CarePlan")
        }
    }

    // GET /CarePlan — search
    group.get { request, _ in
        let pairs = request.uri.queryParameters.map { (key: $0.key, value: $0.value) }
        if isStrictHandling(request) {
            let bad = unknownParams(in: pairs, known: knownCarePlanParams)
            if !bad.isEmpty { throw FHIRRouteError.unknownParams(bad) }
        }
        var query = parseCarePlanQuery(from: pairs)
        let elements = parseElements(from: pairs)
        let summary = parseSummary(from: pairs)
        let includes = parseIncludes(from: pairs)
        let revIncludes = parseRevIncludes(from: pairs)
        if summary == .count { query.count = 0; query.totalMode = .accurate }
        let result = try await store.search(query: query)

        let base = cpSelfURL(request)
        let baseURL = serverBaseURL(request)
        if summary == .count {
            let bundleData = buildBundleJSON(entries: [], total: result.total, selfURL: base, nextURL: nil)
            var headers = HTTPFields()
            headers[.contentType] = carePlanFhirJSON
            return Response(status: .ok, headers: headers,
                            body: ResponseBody(byteBuffer: ByteBuffer(bytes: bundleData)))
        }
        let nextURL = result.nextCursor.map { nextCarePlanPageURL(selfURL: base, cursor: $0, count: query.count) }
        let entries = result.entries.map { e -> (fullUrl: String, json: Data) in
            var json = e.jsonWithMeta
            if let s = summary, s != .false { json = applySummary(json, mode: s, summaryFields: carePlanSummaryFields) }
            if let elems = elements { json = applyElements(json, elements: elems) }
            return ("\(baseURL)/CarePlan/\(e.id)", json)
        }
        let mainIds = result.entries.map(\.id)
        let resolver = IncludeResolver(client: store.client, logger: logger)
        async let included = resolver.resolve(includes: includes, sourceIds: mainIds)
        async let revIncluded = resolver.resolveRev(revIncludes: revIncludes, mainIds: mainIds)
        let includeEntries = includeEntryTuples(from: try await included + revIncluded, baseURL: baseURL)
        let bundleData = buildBundleJSON(entries: entries, includeEntries: includeEntries,
                                         total: result.total, selfURL: base, nextURL: nextURL)
        var headers = HTTPFields()
        headers[.contentType] = carePlanFhirJSON
        return Response(status: .ok, headers: headers,
                        body: ResponseBody(byteBuffer: ByteBuffer(bytes: bundleData)))
    }

    // POST /CarePlan/_search — form-encoded search
    group.post("_search") { request, _ in
        let ct = request.headers[.contentType] ?? ""
        guard ct.contains("application/x-www-form-urlencoded") else {
            throw FHIRRouteError.invalidBody("Content-Type must be application/x-www-form-urlencoded for _search")
        }
        var req = request
        let bodyBuffer = try await req.collectBody(upTo: carePlanMaxBodyBytes)
        let urlPairs = request.uri.queryParameters.map { (key: $0.key, value: $0.value) }
        let pairs = urlPairs + parseFormPairs(from: bodyBuffer)
        if isStrictHandling(request) {
            let bad = unknownParams(in: pairs, known: knownCarePlanParams)
            if !bad.isEmpty { throw FHIRRouteError.unknownParams(bad) }
        }
        var query = parseCarePlanQuery(from: pairs)
        let elements = parseElements(from: pairs)
        let summary = parseSummary(from: pairs)
        let includes = parseIncludes(from: pairs)
        let revIncludes = parseRevIncludes(from: pairs)
        if summary == .count { query.count = 0; query.totalMode = .accurate }
        let result = try await store.search(query: query)

        let base = cpSelfURL(request)
        let baseURL = serverBaseURL(request)
        if summary == .count {
            let bundleData = buildBundleJSON(entries: [], total: result.total, selfURL: base, nextURL: nil)
            var headers = HTTPFields()
            headers[.contentType] = carePlanFhirJSON
            return Response(status: .ok, headers: headers,
                            body: ResponseBody(byteBuffer: ByteBuffer(bytes: bundleData)))
        }
        let nextURL = result.nextCursor.map { nextCarePlanPageURL(selfURL: base, cursor: $0, count: query.count) }
        let entries = result.entries.map { e -> (fullUrl: String, json: Data) in
            var json = e.jsonWithMeta
            if let s = summary, s != .false { json = applySummary(json, mode: s, summaryFields: carePlanSummaryFields) }
            if let elems = elements { json = applyElements(json, elements: elems) }
            return ("\(baseURL)/CarePlan/\(e.id)", json)
        }
        let mainIds = result.entries.map(\.id)
        let resolver = IncludeResolver(client: store.client, logger: logger)
        async let included = resolver.resolve(includes: includes, sourceIds: mainIds)
        async let revIncluded = resolver.resolveRev(revIncludes: revIncludes, mainIds: mainIds)
        let includeEntries = includeEntryTuples(from: try await included + revIncluded, baseURL: baseURL)
        let bundleData = buildBundleJSON(entries: entries, includeEntries: includeEntries,
                                         total: result.total, selfURL: base, nextURL: nextURL)
        var headers = HTTPFields()
        headers[.contentType] = carePlanFhirJSON
        return Response(status: .ok, headers: headers,
                        body: ResponseBody(byteBuffer: ByteBuffer(bytes: bundleData)))
    }
}

// ── Query parser ──────────────────────────────────────────────────────────────

func parseCarePlanQuery(from pairs: some Collection<(key: Substring, value: Substring)>) -> CarePlanSearchQuery {
    let pairs = normalizeReferenceTypeModifiers(pairs)
    func first(_ key: String) -> Substring? {
        pairs.first(where: { $0.key == key[...] })?.value
    }
    func all(_ key: String) -> [Substring] {
        pairs.filter { $0.key == key[...] }.map { $0.value }
    }

    let status       = all("status").flatMap { CarePlanSearchQuery.TokenParam.parseList(String($0)) }
    let statusNot    = all("status:not").flatMap { CarePlanSearchQuery.TokenParam.parseList(String($0)) }
    let intent       = all("intent").flatMap { CarePlanSearchQuery.TokenParam.parseList(String($0)) }
    let intentNot    = all("intent:not").flatMap { CarePlanSearchQuery.TokenParam.parseList(String($0)) }
    let category     = all("category").flatMap { CarePlanSearchQuery.TokenParam.parseList(String($0)) }
    let categoryNot  = all("category:not").flatMap { CarePlanSearchQuery.TokenParam.parseList(String($0)) }
    let identifier      = first("identifier").map { CarePlanSearchQuery.IdentifierParam.parseList(String($0)) } ?? []
    let identifierNot   = first("identifier:not").map { CarePlanSearchQuery.IdentifierParam.parseList(String($0)) } ?? []
    let activityCode    = all("activity-code").flatMap { CarePlanSearchQuery.TokenParam.parseList(String($0)) }
    let activityCodeNot = all("activity-code:not").flatMap { CarePlanSearchQuery.TokenParam.parseList(String($0)) }

    let date              = all("date").compactMap { CarePlanSearchQuery.DateParam.parse(String($0)) }
    let activityDate      = all("activity-date").compactMap { CarePlanSearchQuery.DateParam.parse(String($0)) }
    let activityDateNot   = all("activity-date:not").compactMap { CarePlanSearchQuery.DateParam.parse(String($0)) }
    let instantiatesCanonical = all("instantiates-canonical").map(String.init)
    let instantiatesUri       = all("instantiates-uri").map(String.init)

    let subject           = first("subject").map(String.init)
    let patient           = first("patient").map(String.init)
    let encounter         = first("encounter").map(String.init)
    let careTeam          = first("care-team").map(String.init)
    let condition         = first("condition").map(String.init)
    let goal              = first("goal").map(String.init)
    let basedOn           = first("based-on").map(String.init)
    let partOf            = first("part-of").map(String.init)
    let replaces          = first("replaces").map(String.init)
    let performer         = first("performer").map(String.init)
    let activityReference = first("activity-reference").map(String.init)

    let id          = first("_id").map {
        String($0).split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }
    } ?? []
    let lastUpdated = all("_lastUpdated").compactMap { CarePlanSearchQuery.DateParam.parse(String($0)) }
    let sort        = CarePlanSearchQuery.SortOrder.parse(first("_sort").map(String.init) ?? "-_lastUpdated")
    let count       = min(first("_count").flatMap { Int($0) } ?? 20, carePlanMaxCount)
    let cursor      = first("_cursor").flatMap { CarePlanSearchQuery.SearchCursor.decode(String($0)) }
    let totalMode   = CarePlanSearchQuery.TotalMode.parse(first("_total").map(String.init))

    var missing: [String: Bool] = [:]
    for p in ["status", "intent", "category", "identifier", "activity-code",
              "date", "activity-date", "instantiates-canonical", "instantiates-uri",
              "subject", "patient", "encounter", "care-team",
              "condition", "goal", "based-on", "part-of", "replaces",
              "performer", "activity-reference"] {
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

    var query = CarePlanSearchQuery(
        status: status, statusNot: statusNot,
        intent: intent, intentNot: intentNot,
        category: category, categoryNot: categoryNot,
        identifier: identifier, identifierNot: identifierNot, activityCode: activityCode, activityCodeNot: activityCodeNot,
        date: date,
        activityDate: activityDate, activityDateNot: activityDateNot,
        instantiatesCanonical: instantiatesCanonical, instantiatesUri: instantiatesUri,
        subject: subject, patient: patient,
        encounter: encounter, careTeam: careTeam,
        condition: condition, goal: goal,
        basedOn: basedOn, partOf: partOf,
        replaces: replaces, performer: performer,
        activityReference: activityReference,
        id: id, lastUpdated: lastUpdated,
        tokenTexts: tokenTexts,
        missing: missing, chains: chains, has: has,
        totalMode: totalMode, count: count, sort: sort, cursor: cursor)
    query.meta = parseMetaSearchParams(from: pairs)
    return query
}

// ── Helpers ───────────────────────────────────────────────────────────────────

private func cpConditionalResponse(request: Request, versionId: Int64, lastUpdated: Date) -> Response? {
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

private func cpRequireFHIRContentType(_ request: Request) throws {
    let ct = request.headers[.contentType] ?? ""
    guard ct.contains(carePlanFhirJSON) || ct.contains("application/json") else {
        throw FHIRRouteError.unsupportedMediaType
    }
}

private func cpDecodeFHIR<T: Decodable>(_ type: T.Type, from buffer: ByteBuffer) throws -> T {
    let data = Data(buffer.readableBytesView)
    do { return try JSONDecoder().decode(type, from: data) }
    catch { throw FHIRRouteError.invalidBody(error.localizedDescription) }
}

private func cpSelfURL(_ request: Request) -> String {
    let authority = request.head.authority ?? "localhost"
    return "http://\(authority)\(request.uri)"
}

func nextCarePlanPageURL(selfURL: String, cursor: CarePlanSearchQuery.SearchCursor, count: Int) -> String {
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

private func cpParseETag(_ raw: String?) -> Int64? {
    guard let raw else { return nil }
    let stripped = raw
        .trimmingCharacters(in: .whitespaces)
        .replacingOccurrences(of: "W/", with: "")
        .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
    return Int64(stripped)
}
