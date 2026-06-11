import Foundation
import HTTPTypes
import Hummingbird
import Logging
import ModelsR4
import NIOCore
import SimingCore

private let specMaxCount = 100
private let specFhirJSON = "application/fhir+json"
private let specMaxBodyBytes = 4 * 1024 * 1024
private let specIfNoneExistHeader = HTTPField.Name("If-None-Exist")!
private let specPreferHeader = HTTPField.Name("Prefer")!

let knownSpecimenParams: Set<String> = [
    "status", "type", "accession", "identifier", "bodysite",
    "container", "container-id",
    "collected",
    "subject", "patient", "collector", "parent",
    "status:not", "type:not", "accession:not", "bodysite:not", "container:not", "container-id:not",
    "identifier:not",
    "_id", "_lastUpdated", "_sort", "_count", "_cursor", "_total",
    "_elements", "_format", "_summary", "_include", "_revinclude",
]

public func addSpecimenRoutes(
    to router: Router<BasicRequestContext>,
    store: SpecimenStore,
    logger: Logger
) {
    let group = router.group("Specimen")

    // POST /Specimen — create
    group.post { request, _ in
        try specRequireFHIRContentType(request)
        let preferReturn = parsePreferReturn(request.headers[specPreferHeader])
        var req = request
        let bodyBuffer = try await req.collectBody(upTo: specMaxBodyBytes)
        try validateResourceType("Specimen", from: Data(bodyBuffer.readableBytesView))
        let specimen = try specDecodeFHIR(Specimen.self, from: bodyBuffer)

        if let ifNoneExist = request.headers[specIfNoneExistHeader] {
            let pairs = parseQueryString(ifNoneExist)
            var checkQuery = parseSpecimenQuery(from: pairs)
            checkQuery.count = 2; checkQuery.totalMode = .none; checkQuery.cursor = nil
            let matches = try await store.search(query: checkQuery)
            if matches.entries.count > 1 {
                throw FHIRServerError.multipleMatches(resourceType: "Specimen")
            }
            if let existing = matches.entries.first {
                var headers = HTTPFields()
                headers[.contentType]  = specFhirJSON
                headers[.eTag]         = "W/\"\(existing.versionId)\""
                headers[.lastModified] = httpDate(existing.lastUpdated)
                headers[.location] = "\(serverBaseURL(request))/Specimen/\(existing.id)/_history/\(existing.versionId)"
                return Response(status: .ok, headers: headers,
                                body: preferBody(preferReturn, resource: existing.jsonWithMeta))
            }
        }

        let result = try await store.create(specimen)
        var headers = HTTPFields()
        headers[.contentType]  = specFhirJSON
        headers[.eTag]         = "W/\"\(result.versionId)\""
        headers[.lastModified] = httpDate(result.lastUpdated)
        headers[.location] = "\(serverBaseURL(request))/Specimen/\(result.id)/_history/\(result.versionId)"
        return Response(status: .created, headers: headers,
                        body: preferBody(preferReturn, resource: result.jsonData))
    }

    // PUT /Specimen?<search> — conditional update
    group.put { request, _ in
        try specRequireFHIRContentType(request)
        let preferReturn = parsePreferReturn(request.headers[specPreferHeader])
        let qpPairs = request.uri.queryParameters.map { (key: $0.key, value: $0.value) }
        guard !qpPairs.isEmpty else {
            throw FHIRRouteError.invalidBody("PUT /Specimen requires search parameters for conditional update")
        }
        var req = request
        let bodyBuffer = try await req.collectBody(upTo: specMaxBodyBytes)
        try validateResourceType("Specimen", from: Data(bodyBuffer.readableBytesView))
        let specimen = try specDecodeFHIR(Specimen.self, from: bodyBuffer)
        let ifMatch = specParseETag(request.headers[.ifMatch])

        var checkQuery = parseSpecimenQuery(from: qpPairs)
        checkQuery.count = 2; checkQuery.totalMode = .none; checkQuery.cursor = nil
        let matches = try await store.search(query: checkQuery)

        switch matches.entries.count {
        case 0:
            let result = try await store.create(specimen)
            var headers = HTTPFields()
            headers[.contentType]  = specFhirJSON
            headers[.eTag]         = "W/\"\(result.versionId)\""
            headers[.lastModified] = httpDate(result.lastUpdated)
            headers[.location] = "\(serverBaseURL(request))/Specimen/\(result.id)/_history/\(result.versionId)"
            return Response(status: .created, headers: headers,
                            body: preferBody(preferReturn, resource: result.jsonData))
        case 1:
            let existingId = matches.entries[0].id
            let result = try await store.update(id: existingId, specimen: specimen, ifMatch: ifMatch)
            var headers = HTTPFields()
            headers[.contentType]  = specFhirJSON
            headers[.eTag]         = "W/\"\(result.versionId)\""
            headers[.lastModified] = httpDate(result.lastUpdated)
            headers[.location] = "\(serverBaseURL(request))/Specimen/\(result.id)/_history/\(result.versionId)"
            return Response(status: .ok, headers: headers,
                            body: preferBody(preferReturn, resource: result.jsonData))
        default:
            throw FHIRServerError.multipleMatches(resourceType: "Specimen")
        }
    }

    // GET /Specimen/:id — read
    group.get(":id") { request, context in
        let id = context.parameters.get("id") ?? ""
        let result = try await store.read(id: id)
        if let earlyResponse = specConditionalResponse(request: request, versionId: result.versionId, lastUpdated: result.lastUpdated) {
            return earlyResponse
        }
        let pairs = request.uri.queryParameters.map { (key: $0.key, value: $0.value) }
        let elements = parseElements(from: pairs)
        let summary  = parseSummary(from: pairs)
        var json = result.jsonData
        if let s = summary, s != .false { json = applySummary(json, mode: s, summaryFields: specimenSummaryFields) }
        if let elems = elements { json = applyElements(json, elements: elems) }
        var headers = HTTPFields()
        headers[.contentType]  = specFhirJSON
        headers[.eTag]         = "W/\"\(result.versionId)\""
        headers[.lastModified] = httpDate(result.lastUpdated)
        headers[.contentLocation] = contentLocation(request, versionId: result.versionId)
        return Response(status: .ok, headers: headers,
                        body: ResponseBody(byteBuffer: ByteBuffer(bytes: json)))
    }

    // GET /Specimen/:id/_history/:vid — vread
    group.get(":id/_history/:vid") { request, context in
        let id  = context.parameters.get("id")  ?? ""
        let vid = context.parameters.get("vid").flatMap { Int64($0) } ?? 0
        let result = try await store.vread(id: id, versionId: vid)
        var headers = HTTPFields()
        headers[.contentType]  = specFhirJSON
        headers[.eTag]         = "W/\"\(result.versionId)\""
        headers[.lastModified] = httpDate(result.lastUpdated)
        headers[.contentLocation] = contentLocation(request, versionId: result.versionId)
        return Response(status: .ok, headers: headers,
                        body: ResponseBody(byteBuffer: ByteBuffer(bytes: result.jsonData)))
    }

    // GET /Specimen/:id/_history — instance history
    group.get(":id/_history") { request, context in
        let id = context.parameters.get("id") ?? ""
        let qp = request.uri.queryParameters
        let since: Date? = qp["_since"].flatMap { parseFHIRInstant(String($0)) }
        let count = min(qp["_count"].flatMap { Int($0) } ?? 50, specMaxCount)
        let entries = try await store.history(id: id, since: since, count: count)
        let baseURL = serverBaseURL(request)
        let bundleData = buildHistoryBundleJSON(entries: entries, baseURL: baseURL, selfURL: "\(baseURL)\(request.uri)")
        var headers = HTTPFields()
        headers[.contentType] = specFhirJSON
        return Response(status: .ok, headers: headers,
                        body: ResponseBody(byteBuffer: ByteBuffer(bytes: bundleData)))
    }

    // GET /Specimen/_history — type history
    group.get("_history") { request, _ in
        let qp = request.uri.queryParameters
        let since: Date? = qp["_since"].flatMap { parseFHIRInstant(String($0)) }
        let count = min(qp["_count"].flatMap { Int($0) } ?? 50, 100)
        let entries = try await store.typeHistory(since: since, count: count)
        let baseURL = serverBaseURL(request)
        let bundleData = buildHistoryBundleJSON(entries: entries, baseURL: baseURL, selfURL: "\(baseURL)\(request.uri)")
        var headers = HTTPFields()
        headers[.contentType] = specFhirJSON
        return Response(status: .ok, headers: headers,
                        body: ResponseBody(byteBuffer: ByteBuffer(bytes: bundleData)))
    }

    // PUT /Specimen/:id — update
    group.put(":id") { request, context in
        try specRequireFHIRContentType(request)
        let preferReturn = parsePreferReturn(request.headers[specPreferHeader])
        let id = context.parameters.get("id") ?? ""
        let ifMatch = specParseETag(request.headers[.ifMatch])
        var req = request
        let bodyBuffer = try await req.collectBody(upTo: specMaxBodyBytes)
        try validateResourceType("Specimen", from: Data(bodyBuffer.readableBytesView))
        let specimen = try specDecodeFHIR(Specimen.self, from: bodyBuffer)
        let result = try await store.update(id: id, specimen: specimen, ifMatch: ifMatch)
        var headers = HTTPFields()
        headers[.contentType]  = specFhirJSON
        headers[.eTag]         = "W/\"\(result.versionId)\""
        headers[.lastModified] = httpDate(result.lastUpdated)
        headers[.location] = "\(serverBaseURL(request))/Specimen/\(result.id)/_history/\(result.versionId)"
        return Response(status: .ok, headers: headers,
                        body: preferBody(preferReturn, resource: result.jsonData))
    }

    // PATCH /Specimen/:id — JSON Patch (RFC 6902)
    group.patch(":id") { request, context in
        let id = context.parameters.get("id") ?? ""
        let ct = request.headers[.contentType] ?? ""
        guard ct.contains("application/json-patch+json") else {
            throw FHIRRouteError.invalidBody("PATCH requires Content-Type: application/json-patch+json")
        }
        let ifMatch = specParseETag(request.headers[.ifMatch])
        var req = request
        let bodyBuffer = try await req.collectBody(upTo: specMaxBodyBytes)
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
        let specimen: Specimen
        do { specimen = try JSONDecoder().decode(Specimen.self, from: patchedJSON) }
        catch { throw FHIRRouteError.unprocessableEntity("Patched resource is not valid FHIR: \(error.localizedDescription)") }
        let result = try await store.update(id: id, specimen: specimen, ifMatch: ifMatch)
        var headers = HTTPFields()
        headers[.contentType]  = specFhirJSON
        headers[.eTag]         = "W/\"\(result.versionId)\""
        headers[.lastModified] = httpDate(result.lastUpdated)
        return Response(status: .ok, headers: headers,
                        body: ResponseBody(byteBuffer: ByteBuffer(bytes: result.jsonData)))
    }

    // DELETE /Specimen/:id — logical delete
    group.delete(":id") { request, context in
        let id = context.parameters.get("id") ?? ""
        let ifMatch = specParseETag(request.headers[.ifMatch])
        let result = try await store.delete(id: id, ifMatch: ifMatch)
        var headers = HTTPFields()
        headers[.eTag]         = "W/\"\(result.versionId)\""
        headers[.lastModified] = httpDate(result.lastUpdated)
        return Response(status: .noContent, headers: headers, body: .init())
    }

    // DELETE /Specimen?<search> — conditional delete
    group.delete { request, _ in
        let qpPairs = request.uri.queryParameters.map { (key: $0.key, value: $0.value) }
        guard !qpPairs.isEmpty else {
            throw FHIRRouteError.invalidBody("DELETE /Specimen requires search parameters for conditional delete")
        }
        var checkQuery = parseSpecimenQuery(from: qpPairs)
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
            throw FHIRServerError.multipleMatches(resourceType: "Specimen")
        }
    }

    // GET /Specimen — search
    group.get { request, _ in
        let pairs = request.uri.queryParameters.map { (key: $0.key, value: $0.value) }
        if isStrictHandling(request) {
            let bad = unknownParams(in: pairs, known: knownSpecimenParams)
            if !bad.isEmpty { throw FHIRRouteError.unknownParams(bad) }
        }
        var query = parseSpecimenQuery(from: pairs)
        let elements = parseElements(from: pairs)
        let summary = parseSummary(from: pairs)
        let includes = parseIncludes(from: pairs)
        let revIncludes = parseRevIncludes(from: pairs)
        if summary == .count { query.count = 0; query.totalMode = .accurate }
        let result = try await store.search(query: query)

        let base = specSelfURL(request)
        let baseURL = serverBaseURL(request)
        if summary == .count {
            let bundleData = buildBundleJSON(entries: [], total: result.total, selfURL: base, nextURL: nil)
            var headers = HTTPFields()
            headers[.contentType] = specFhirJSON
            return Response(status: .ok, headers: headers,
                            body: ResponseBody(byteBuffer: ByteBuffer(bytes: bundleData)))
        }
        let nextURL = result.nextCursor.map { nextSpecimenPageURL(selfURL: base, cursor: $0, count: query.count) }
        let entries = result.entries.map { e -> (fullUrl: String, json: Data) in
            var json = e.jsonWithMeta
            if let s = summary, s != .false { json = applySummary(json, mode: s, summaryFields: specimenSummaryFields) }
            if let elems = elements { json = applyElements(json, elements: elems) }
            return ("\(baseURL)/Specimen/\(e.id)", json)
        }
        let mainIds = result.entries.map(\.id)
        let resolver = IncludeResolver(client: store.client, logger: logger)
        async let included = resolver.resolve(includes: includes, sourceIds: mainIds)
        async let revIncluded = resolver.resolveRev(revIncludes: revIncludes, mainIds: mainIds)
        let includeEntries = includeEntryTuples(from: try await included + revIncluded, baseURL: baseURL)
        let bundleData = buildBundleJSON(entries: entries, includeEntries: includeEntries,
                                         total: result.total, selfURL: base, nextURL: nextURL)
        var headers = HTTPFields()
        headers[.contentType] = specFhirJSON
        return Response(status: .ok, headers: headers,
                        body: ResponseBody(byteBuffer: ByteBuffer(bytes: bundleData)))
    }

    // POST /Specimen/_search — form-encoded search
    group.post("_search") { request, _ in
        let ct = request.headers[.contentType] ?? ""
        guard ct.contains("application/x-www-form-urlencoded") else {
            throw FHIRRouteError.invalidBody("Content-Type must be application/x-www-form-urlencoded for _search")
        }
        var req = request
        let bodyBuffer = try await req.collectBody(upTo: specMaxBodyBytes)
        let urlPairs = request.uri.queryParameters.map { (key: $0.key, value: $0.value) }
        let pairs = urlPairs + parseFormPairs(from: bodyBuffer)
        if isStrictHandling(request) {
            let bad = unknownParams(in: pairs, known: knownSpecimenParams)
            if !bad.isEmpty { throw FHIRRouteError.unknownParams(bad) }
        }
        var query = parseSpecimenQuery(from: pairs)
        let elements = parseElements(from: pairs)
        let summary = parseSummary(from: pairs)
        let includes = parseIncludes(from: pairs)
        let revIncludes = parseRevIncludes(from: pairs)
        if summary == .count { query.count = 0; query.totalMode = .accurate }
        let result = try await store.search(query: query)

        let base = specSelfURL(request)
        let baseURL = serverBaseURL(request)
        if summary == .count {
            let bundleData = buildBundleJSON(entries: [], total: result.total, selfURL: base, nextURL: nil)
            var headers = HTTPFields()
            headers[.contentType] = specFhirJSON
            return Response(status: .ok, headers: headers,
                            body: ResponseBody(byteBuffer: ByteBuffer(bytes: bundleData)))
        }
        let nextURL = result.nextCursor.map { nextSpecimenPageURL(selfURL: base, cursor: $0, count: query.count) }
        let entries = result.entries.map { e -> (fullUrl: String, json: Data) in
            var json = e.jsonWithMeta
            if let s = summary, s != .false { json = applySummary(json, mode: s, summaryFields: specimenSummaryFields) }
            if let elems = elements { json = applyElements(json, elements: elems) }
            return ("\(baseURL)/Specimen/\(e.id)", json)
        }
        let mainIds = result.entries.map(\.id)
        let resolver = IncludeResolver(client: store.client, logger: logger)
        async let included = resolver.resolve(includes: includes, sourceIds: mainIds)
        async let revIncluded = resolver.resolveRev(revIncludes: revIncludes, mainIds: mainIds)
        let includeEntries = includeEntryTuples(from: try await included + revIncluded, baseURL: baseURL)
        let bundleData = buildBundleJSON(entries: entries, includeEntries: includeEntries,
                                         total: result.total, selfURL: base, nextURL: nextURL)
        var headers = HTTPFields()
        headers[.contentType] = specFhirJSON
        return Response(status: .ok, headers: headers,
                        body: ResponseBody(byteBuffer: ByteBuffer(bytes: bundleData)))
    }
}

// ── Query parser ──────────────────────────────────────────────────────────────

func parseSpecimenQuery(from pairs: some Collection<(key: Substring, value: Substring)>) -> SpecimenSearchQuery {
    let pairs = normalizeReferenceTypeModifiers(pairs)
    func first(_ key: String) -> Substring? {
        pairs.first(where: { $0.key == key[...] })?.value
    }
    func all(_ key: String) -> [Substring] {
        pairs.filter { $0.key == key[...] }.map { $0.value }
    }

    let status         = all("status").flatMap { SpecimenSearchQuery.TokenParam.parseList(String($0)) }
    let statusNot      = all("status:not").flatMap { SpecimenSearchQuery.TokenParam.parseList(String($0)) }
    let type           = all("type").flatMap { SpecimenSearchQuery.TokenParam.parseList(String($0)) }
    let typeNot        = all("type:not").flatMap { SpecimenSearchQuery.TokenParam.parseList(String($0)) }
    let accession      = all("accession").flatMap { SpecimenSearchQuery.TokenParam.parseList(String($0)) }
    let accessionNot   = all("accession:not").flatMap { SpecimenSearchQuery.TokenParam.parseList(String($0)) }
    let identifier     = first("identifier").map { SpecimenSearchQuery.IdentifierParam.parseList(String($0)) } ?? []
    let identifierNot  = first("identifier:not").map { SpecimenSearchQuery.IdentifierParam.parseList(String($0)) } ?? []
    let bodysite       = all("bodysite").flatMap { SpecimenSearchQuery.TokenParam.parseList(String($0)) }
    let bodysiteNot    = all("bodysite:not").flatMap { SpecimenSearchQuery.TokenParam.parseList(String($0)) }
    let container      = all("container").flatMap { SpecimenSearchQuery.TokenParam.parseList(String($0)) }
    let containerNot   = all("container:not").flatMap { SpecimenSearchQuery.TokenParam.parseList(String($0)) }
    let containerId    = all("container-id").flatMap { SpecimenSearchQuery.TokenParam.parseList(String($0)) }
    let containerIdNot = all("container-id:not").flatMap { SpecimenSearchQuery.TokenParam.parseList(String($0)) }

    let collected = all("collected").compactMap { SpecimenSearchQuery.DateParam.parse(String($0)) }

    let subject   = first("subject").map(String.init)
    let patient   = first("patient").map(String.init)
    let collector = first("collector").map(String.init)
    let parent    = first("parent").map(String.init)

    let id          = first("_id").map {
        String($0).split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }
    } ?? []
    let lastUpdated = all("_lastUpdated").compactMap { SpecimenSearchQuery.DateParam.parse(String($0)) }
    let sortKeys = SpecimenSearchQuery.parseSortKeys(first("_sort").map(String.init) ?? "-_lastUpdated")
    let count       = min(first("_count").flatMap { Int($0) } ?? 20, specMaxCount)
    let cursor      = first("_cursor").flatMap { SearchCursor.decode(String($0)) }
    let totalMode   = SpecimenSearchQuery.TotalMode.parse(first("_total").map(String.init))

    var missing: [String: Bool] = [:]
    for p in ["status", "type", "accession", "bodysite", "container", "container-id",
              "identifier", "collected", "subject", "patient", "collector", "parent"] {
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

    var query = SpecimenSearchQuery(
        status: status, statusNot: statusNot,
        type: type, typeNot: typeNot,
        accession: accession, accessionNot: accessionNot,
        identifier: identifier, identifierNot: identifierNot,
        bodysite: bodysite, bodysiteNot: bodysiteNot,
        container: container, containerNot: containerNot,
        containerId: containerId, containerIdNot: containerIdNot,
        collected: collected,
        subject: subject, patient: patient,
        collector: collector, parent: parent,
        id: id, lastUpdated: lastUpdated,
        tokenTexts: tokenTexts,
        missing: missing, chains: chains, has: has,
        totalMode: totalMode, count: count, sortKeys: sortKeys, cursor: cursor)
    query.meta = parseMetaSearchParams(from: pairs)
    return query
}

// ── Helpers ───────────────────────────────────────────────────────────────────

private func specConditionalResponse(request: Request, versionId: Int64, lastUpdated: Date) -> Response? {
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

private func specRequireFHIRContentType(_ request: Request) throws {
    let ct = request.headers[.contentType] ?? ""
    guard ct.contains(specFhirJSON) || ct.contains("application/json") else {
        throw FHIRRouteError.unsupportedMediaType
    }
}

private func specDecodeFHIR<T: Decodable>(_ type: T.Type, from buffer: ByteBuffer) throws -> T {
    let data = Data(buffer.readableBytesView)
    do { return try JSONDecoder().decode(type, from: data) }
    catch { throw FHIRRouteError.invalidBody(error.localizedDescription) }
}

private func specSelfURL(_ request: Request) -> String {
    let authority = request.head.authority ?? "localhost"
    return "http://\(authority)\(request.uri)"
}

func nextSpecimenPageURL(selfURL: String, cursor: SearchCursor, count: Int) -> String {
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

private func specParseETag(_ raw: String?) -> Int64? {
    guard let raw else { return nil }
    let stripped = raw
        .trimmingCharacters(in: .whitespaces)
        .replacingOccurrences(of: "W/", with: "")
        .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
    return Int64(stripped)
}
