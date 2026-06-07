import Foundation
import HTTPTypes
import Hummingbird
import Logging
import ModelsR4
import NIOCore
import SimingCore

private let docRefMaxCount = 100
private let docRefFhirJSON = "application/fhir+json"
private let docRefMaxBodyBytes = 4 * 1024 * 1024
private let docRefIfNoneExistHeader = HTTPField.Name("If-None-Exist")!
private let docRefPreferHeader = HTTPField.Name("Prefer")!

let knownDocumentReferenceParams: Set<String> = [
    "status", "type", "category", "identifier",
    "security-label", "facility", "event", "description",
    "date", "period",
    "subject", "patient", "author", "encounter",
    "custodian", "authenticator",
    "relatesto", "relation", "relation:not",
    "status:not", "type:not", "category:not", "security-label:not",
    "_id", "_lastUpdated", "_sort", "_count", "_cursor", "_total",
    "_elements", "_format", "_summary", "_include", "_revinclude",
]

public func addDocumentReferenceRoutes(
    to router: Router<BasicRequestContext>,
    store: DocumentReferenceStore,
    logger: Logger
) {
    let group = router.group("DocumentReference")

    // POST /DocumentReference — create
    group.post { request, _ in
        try docRefRequireFHIRContentType(request)
        let returnMinimal = (request.headers[docRefPreferHeader] ?? "").contains("return=minimal")
        var req = request
        let bodyBuffer = try await req.collectBody(upTo: docRefMaxBodyBytes)
        let docRef = try docRefDecodeFHIR(DocumentReference.self, from: bodyBuffer)

        if let ifNoneExist = request.headers[docRefIfNoneExistHeader] {
            let pairs = parseQueryString(ifNoneExist)
            var checkQuery = parseDocumentReferenceQuery(from: pairs)
            checkQuery.count = 2; checkQuery.totalMode = .none; checkQuery.cursor = nil
            let matches = try await store.search(query: checkQuery)
            if matches.entries.count > 1 {
                throw FHIRServerError.multipleMatches(resourceType: "DocumentReference")
            }
            if let existing = matches.entries.first {
                var headers = HTTPFields()
                headers[.contentType]  = docRefFhirJSON
                headers[.eTag]         = "W/\"\(existing.versionId)\""
                headers[.lastModified] = httpDate(existing.lastUpdated)
                headers[.location]     = "/DocumentReference/\(existing.id)/_history/\(existing.versionId)"
                return Response(status: .ok, headers: headers,
                                body: returnMinimal ? .init() : ResponseBody(byteBuffer: ByteBuffer(bytes: existing.jsonWithMeta)))
            }
        }

        let result = try await store.create(docRef)
        var headers = HTTPFields()
        headers[.contentType]  = docRefFhirJSON
        headers[.eTag]         = "W/\"\(result.versionId)\""
        headers[.lastModified] = httpDate(result.lastUpdated)
        headers[.location]     = "/DocumentReference/\(result.id)/_history/\(result.versionId)"
        return Response(status: .created, headers: headers,
                        body: returnMinimal ? .init() : ResponseBody(byteBuffer: ByteBuffer(bytes: result.jsonData)))
    }

    // PUT /DocumentReference?<search> — conditional update
    group.put { request, _ in
        try docRefRequireFHIRContentType(request)
        let returnMinimal = (request.headers[docRefPreferHeader] ?? "").contains("return=minimal")
        let qpPairs = request.uri.queryParameters.map { (key: $0.key, value: $0.value) }
        guard !qpPairs.isEmpty else {
            throw FHIRRouteError.invalidBody("PUT /DocumentReference requires search parameters for conditional update")
        }
        var req = request
        let bodyBuffer = try await req.collectBody(upTo: docRefMaxBodyBytes)
        let docRef = try docRefDecodeFHIR(DocumentReference.self, from: bodyBuffer)
        let ifMatch = docRefParseETag(request.headers[.ifMatch])

        var checkQuery = parseDocumentReferenceQuery(from: qpPairs)
        checkQuery.count = 2; checkQuery.totalMode = .none; checkQuery.cursor = nil
        let matches = try await store.search(query: checkQuery)

        switch matches.entries.count {
        case 0:
            let result = try await store.create(docRef)
            var headers = HTTPFields()
            headers[.contentType]  = docRefFhirJSON
            headers[.eTag]         = "W/\"\(result.versionId)\""
            headers[.lastModified] = httpDate(result.lastUpdated)
            headers[.location]     = "/DocumentReference/\(result.id)/_history/\(result.versionId)"
            return Response(status: .created, headers: headers,
                            body: returnMinimal ? .init() : ResponseBody(byteBuffer: ByteBuffer(bytes: result.jsonData)))
        case 1:
            let existingId = matches.entries[0].id
            let result = try await store.update(id: existingId, docRef: docRef, ifMatch: ifMatch)
            var headers = HTTPFields()
            headers[.contentType]  = docRefFhirJSON
            headers[.eTag]         = "W/\"\(result.versionId)\""
            headers[.lastModified] = httpDate(result.lastUpdated)
            headers[.location]     = "/DocumentReference/\(result.id)/_history/\(result.versionId)"
            return Response(status: .ok, headers: headers,
                            body: returnMinimal ? .init() : ResponseBody(byteBuffer: ByteBuffer(bytes: result.jsonData)))
        default:
            throw FHIRServerError.multipleMatches(resourceType: "DocumentReference")
        }
    }

    // GET /DocumentReference/:id — read
    group.get(":id") { request, context in
        let id = context.parameters.get("id") ?? ""
        let result = try await store.read(id: id)
        if let earlyResponse = docRefConditionalResponse(request: request, versionId: result.versionId, lastUpdated: result.lastUpdated) {
            return earlyResponse
        }
        let pairs = request.uri.queryParameters.map { (key: $0.key, value: $0.value) }
        let elements = parseElements(from: pairs)
        let summary  = parseSummary(from: pairs)
        var json = result.jsonData
        if let s = summary, s != .false { json = applySummary(json, mode: s, summaryFields: documentReferenceSummaryFields) }
        if let elems = elements { json = applyElements(json, elements: elems) }
        var headers = HTTPFields()
        headers[.contentType]  = docRefFhirJSON
        headers[.eTag]         = "W/\"\(result.versionId)\""
        headers[.lastModified] = httpDate(result.lastUpdated)
        return Response(status: .ok, headers: headers,
                        body: ResponseBody(byteBuffer: ByteBuffer(bytes: json)))
    }

    // GET /DocumentReference/:id/_history/:vid — vread
    group.get(":id/_history/:vid") { request, context in
        let id  = context.parameters.get("id")  ?? ""
        let vid = context.parameters.get("vid").flatMap { Int64($0) } ?? 0
        let result = try await store.vread(id: id, versionId: vid)
        var headers = HTTPFields()
        headers[.contentType]  = docRefFhirJSON
        headers[.eTag]         = "W/\"\(result.versionId)\""
        headers[.lastModified] = httpDate(result.lastUpdated)
        return Response(status: .ok, headers: headers,
                        body: ResponseBody(byteBuffer: ByteBuffer(bytes: result.jsonData)))
    }

    // GET /DocumentReference/:id/_history — instance history
    group.get(":id/_history") { request, context in
        let id = context.parameters.get("id") ?? ""
        let qp = request.uri.queryParameters
        let since: Date? = qp["_since"].flatMap { parseFHIRInstant(String($0)) }
        let count = min(qp["_count"].flatMap { Int($0) } ?? 50, docRefMaxCount)
        let entries = try await store.history(id: id, since: since, count: count)
        let baseURL = serverBaseURL(request)
        let bundleData = buildHistoryBundleJSON(entries: entries, baseURL: baseURL)
        var headers = HTTPFields()
        headers[.contentType] = docRefFhirJSON
        return Response(status: .ok, headers: headers,
                        body: ResponseBody(byteBuffer: ByteBuffer(bytes: bundleData)))
    }

    // GET /DocumentReference/_history — type history
    group.get("_history") { request, _ in
        let qp = request.uri.queryParameters
        let since: Date? = qp["_since"].flatMap { parseFHIRInstant(String($0)) }
        let count = min(qp["_count"].flatMap { Int($0) } ?? 50, 100)
        let entries = try await store.typeHistory(since: since, count: count)
        let baseURL = serverBaseURL(request)
        let bundleData = buildHistoryBundleJSON(entries: entries, baseURL: baseURL)
        var headers = HTTPFields()
        headers[.contentType] = docRefFhirJSON
        return Response(status: .ok, headers: headers,
                        body: ResponseBody(byteBuffer: ByteBuffer(bytes: bundleData)))
    }

    // PUT /DocumentReference/:id — update
    group.put(":id") { request, context in
        try docRefRequireFHIRContentType(request)
        let returnMinimal = (request.headers[docRefPreferHeader] ?? "").contains("return=minimal")
        let id = context.parameters.get("id") ?? ""
        let ifMatch = docRefParseETag(request.headers[.ifMatch])
        var req = request
        let bodyBuffer = try await req.collectBody(upTo: docRefMaxBodyBytes)
        let docRef = try docRefDecodeFHIR(DocumentReference.self, from: bodyBuffer)
        let result = try await store.update(id: id, docRef: docRef, ifMatch: ifMatch)
        var headers = HTTPFields()
        headers[.contentType]  = docRefFhirJSON
        headers[.eTag]         = "W/\"\(result.versionId)\""
        headers[.lastModified] = httpDate(result.lastUpdated)
        headers[.location]     = "/DocumentReference/\(result.id)/_history/\(result.versionId)"
        return Response(status: .ok, headers: headers,
                        body: returnMinimal ? .init() : ResponseBody(byteBuffer: ByteBuffer(bytes: result.jsonData)))
    }

    // PATCH /DocumentReference/:id — JSON Patch (RFC 6902)
    group.patch(":id") { request, context in
        let id = context.parameters.get("id") ?? ""
        let ct = request.headers[.contentType] ?? ""
        guard ct.contains("application/json-patch+json") else {
            throw FHIRRouteError.invalidBody("PATCH requires Content-Type: application/json-patch+json")
        }
        let ifMatch = docRefParseETag(request.headers[.ifMatch])
        var req = request
        let bodyBuffer = try await req.collectBody(upTo: docRefMaxBodyBytes)
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
        let docRef: DocumentReference
        do { docRef = try JSONDecoder().decode(DocumentReference.self, from: patchedJSON) }
        catch { throw FHIRRouteError.unprocessableEntity("Patched resource is not valid FHIR: \(error.localizedDescription)") }
        let result = try await store.update(id: id, docRef: docRef, ifMatch: ifMatch)
        var headers = HTTPFields()
        headers[.contentType]  = docRefFhirJSON
        headers[.eTag]         = "W/\"\(result.versionId)\""
        headers[.lastModified] = httpDate(result.lastUpdated)
        return Response(status: .ok, headers: headers,
                        body: ResponseBody(byteBuffer: ByteBuffer(bytes: result.jsonData)))
    }

    // DELETE /DocumentReference/:id — logical delete
    group.delete(":id") { request, context in
        let id = context.parameters.get("id") ?? ""
        let ifMatch = docRefParseETag(request.headers[.ifMatch])
        let result = try await store.delete(id: id, ifMatch: ifMatch)
        var headers = HTTPFields()
        headers[.eTag]         = "W/\"\(result.versionId)\""
        headers[.lastModified] = httpDate(result.lastUpdated)
        return Response(status: .noContent, headers: headers, body: .init())
    }

    // DELETE /DocumentReference?<search> — conditional delete
    group.delete { request, _ in
        let qpPairs = request.uri.queryParameters.map { (key: $0.key, value: $0.value) }
        guard !qpPairs.isEmpty else {
            throw FHIRRouteError.invalidBody("DELETE /DocumentReference requires search parameters for conditional delete")
        }
        var checkQuery = parseDocumentReferenceQuery(from: qpPairs)
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
            throw FHIRServerError.multipleMatches(resourceType: "DocumentReference")
        }
    }

    // GET /DocumentReference — search
    group.get { request, _ in
        let pairs = request.uri.queryParameters.map { (key: $0.key, value: $0.value) }
        if isStrictHandling(request) {
            let bad = unknownParams(in: pairs, known: knownDocumentReferenceParams)
            if !bad.isEmpty { throw FHIRRouteError.unknownParams(bad) }
        }
        var query = parseDocumentReferenceQuery(from: pairs)
        let elements = parseElements(from: pairs)
        let summary = parseSummary(from: pairs)
        let includes = parseIncludes(from: pairs)
        let revIncludes = parseRevIncludes(from: pairs)
        if summary == .count { query.count = 0; query.totalMode = .accurate }
        let result = try await store.search(query: query)

        let base = docRefSelfURL(request)
        let baseURL = serverBaseURL(request)
        if summary == .count {
            let bundleData = buildBundleJSON(entries: [], total: result.total, selfURL: base, nextURL: nil)
            var headers = HTTPFields()
            headers[.contentType] = docRefFhirJSON
            return Response(status: .ok, headers: headers,
                            body: ResponseBody(byteBuffer: ByteBuffer(bytes: bundleData)))
        }
        let nextURL = result.nextCursor.map { nextDocumentReferencePageURL(selfURL: base, cursor: $0, count: query.count) }
        let entries = result.entries.map { e -> (fullUrl: String, json: Data) in
            var json = e.jsonWithMeta
            if let s = summary, s != .false { json = applySummary(json, mode: s, summaryFields: documentReferenceSummaryFields) }
            if let elems = elements { json = applyElements(json, elements: elems) }
            return ("\(baseURL)/DocumentReference/\(e.id)", json)
        }
        let mainIds = result.entries.map(\.id)
        let resolver = IncludeResolver(client: store.client, logger: logger)
        async let included = resolver.resolve(includes: includes, sourceIds: mainIds)
        async let revIncluded = resolver.resolveRev(revIncludes: revIncludes, mainIds: mainIds)
        let includeEntries = includeEntryTuples(from: try await included + revIncluded, baseURL: baseURL)
        let bundleData = buildBundleJSON(entries: entries, includeEntries: includeEntries,
                                         total: result.total, selfURL: base, nextURL: nextURL)
        var headers = HTTPFields()
        headers[.contentType] = docRefFhirJSON
        return Response(status: .ok, headers: headers,
                        body: ResponseBody(byteBuffer: ByteBuffer(bytes: bundleData)))
    }

    // POST /DocumentReference/_search — form-encoded search
    group.post("_search") { request, _ in
        let ct = request.headers[.contentType] ?? ""
        guard ct.contains("application/x-www-form-urlencoded") else {
            throw FHIRRouteError.invalidBody("Content-Type must be application/x-www-form-urlencoded for _search")
        }
        var req = request
        let bodyBuffer = try await req.collectBody(upTo: docRefMaxBodyBytes)
        let urlPairs = request.uri.queryParameters.map { (key: $0.key, value: $0.value) }
        let pairs = urlPairs + parseFormPairs(from: bodyBuffer)
        if isStrictHandling(request) {
            let bad = unknownParams(in: pairs, known: knownDocumentReferenceParams)
            if !bad.isEmpty { throw FHIRRouteError.unknownParams(bad) }
        }
        var query = parseDocumentReferenceQuery(from: pairs)
        let elements = parseElements(from: pairs)
        let summary = parseSummary(from: pairs)
        let includes = parseIncludes(from: pairs)
        let revIncludes = parseRevIncludes(from: pairs)
        if summary == .count { query.count = 0; query.totalMode = .accurate }
        let result = try await store.search(query: query)

        let base = docRefSelfURL(request)
        let baseURL = serverBaseURL(request)
        if summary == .count {
            let bundleData = buildBundleJSON(entries: [], total: result.total, selfURL: base, nextURL: nil)
            var headers = HTTPFields()
            headers[.contentType] = docRefFhirJSON
            return Response(status: .ok, headers: headers,
                            body: ResponseBody(byteBuffer: ByteBuffer(bytes: bundleData)))
        }
        let nextURL = result.nextCursor.map { nextDocumentReferencePageURL(selfURL: base, cursor: $0, count: query.count) }
        let entries = result.entries.map { e -> (fullUrl: String, json: Data) in
            var json = e.jsonWithMeta
            if let s = summary, s != .false { json = applySummary(json, mode: s, summaryFields: documentReferenceSummaryFields) }
            if let elems = elements { json = applyElements(json, elements: elems) }
            return ("\(baseURL)/DocumentReference/\(e.id)", json)
        }
        let mainIds = result.entries.map(\.id)
        let resolver = IncludeResolver(client: store.client, logger: logger)
        async let included = resolver.resolve(includes: includes, sourceIds: mainIds)
        async let revIncluded = resolver.resolveRev(revIncludes: revIncludes, mainIds: mainIds)
        let includeEntries = includeEntryTuples(from: try await included + revIncluded, baseURL: baseURL)
        let bundleData = buildBundleJSON(entries: entries, includeEntries: includeEntries,
                                         total: result.total, selfURL: base, nextURL: nextURL)
        var headers = HTTPFields()
        headers[.contentType] = docRefFhirJSON
        return Response(status: .ok, headers: headers,
                        body: ResponseBody(byteBuffer: ByteBuffer(bytes: bundleData)))
    }
}

// ── Query parser ──────────────────────────────────────────────────────────────

func parseDocumentReferenceQuery(from pairs: some Collection<(key: Substring, value: Substring)>) -> DocumentReferenceSearchQuery {
    func first(_ key: String) -> Substring? {
        pairs.first(where: { $0.key == key[...] })?.value
    }
    func all(_ key: String) -> [Substring] {
        pairs.filter { $0.key == key[...] }.map { $0.value }
    }

    let status           = all("status").flatMap { DocumentReferenceSearchQuery.TokenParam.parseList(String($0)) }
    let statusNot        = all("status:not").flatMap { DocumentReferenceSearchQuery.TokenParam.parseList(String($0)) }
    let type             = all("type").flatMap { DocumentReferenceSearchQuery.TokenParam.parseList(String($0)) }
    let typeNot          = all("type:not").flatMap { DocumentReferenceSearchQuery.TokenParam.parseList(String($0)) }
    let category         = all("category").flatMap { DocumentReferenceSearchQuery.TokenParam.parseList(String($0)) }
    let categoryNot      = all("category:not").flatMap { DocumentReferenceSearchQuery.TokenParam.parseList(String($0)) }
    let identifier       = first("identifier").map { DocumentReferenceSearchQuery.IdentifierParam.parseList(String($0)) } ?? []
    let securityLabel    = all("security-label").flatMap { DocumentReferenceSearchQuery.TokenParam.parseList(String($0)) }
    let securityLabelNot = all("security-label:not").flatMap { DocumentReferenceSearchQuery.TokenParam.parseList(String($0)) }
    let facility         = all("facility").flatMap { DocumentReferenceSearchQuery.TokenParam.parseList(String($0)) }
    let event            = all("event").flatMap { DocumentReferenceSearchQuery.TokenParam.parseList(String($0)) }
    let contentType      = all("contenttype").flatMap { DocumentReferenceSearchQuery.TokenParam.parseList(String($0)) }
    let contentTypeNot   = all("contenttype:not").flatMap { DocumentReferenceSearchQuery.TokenParam.parseList(String($0)) }
    let format           = all("format").flatMap { DocumentReferenceSearchQuery.TokenParam.parseList(String($0)) }
    let formatNot        = all("format:not").flatMap { DocumentReferenceSearchQuery.TokenParam.parseList(String($0)) }
    let language         = all("language").flatMap { DocumentReferenceSearchQuery.TokenParam.parseList(String($0)) }
    let languageNot      = all("language:not").flatMap { DocumentReferenceSearchQuery.TokenParam.parseList(String($0)) }
    let setting          = all("setting").flatMap { DocumentReferenceSearchQuery.TokenParam.parseList(String($0)) }
    let settingNot       = all("setting:not").flatMap { DocumentReferenceSearchQuery.TokenParam.parseList(String($0)) }

    let date   = all("date").compactMap { DocumentReferenceSearchQuery.DateParam.parse(String($0)) }
    let period = all("period").compactMap { DocumentReferenceSearchQuery.DateParam.parse(String($0)) }

    let description = all("description").map(String.init)

    let subject       = first("subject").map(String.init)
    let patient       = first("patient").map(String.init)
    let author        = first("author").map(String.init)
    let encounter     = first("encounter").map(String.init)
    let custodian     = first("custodian").map(String.init)
    let authenticator = first("authenticator").map(String.init)
    let relatesto     = first("relatesto").map(String.init)
    let relation      = all("relation").flatMap { DocumentReferenceSearchQuery.TokenParam.parseList(String($0)) }
    let relationNot   = all("relation:not").flatMap { DocumentReferenceSearchQuery.TokenParam.parseList(String($0)) }

    let id          = first("_id").map {
        String($0).split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }
    } ?? []
    let lastUpdated = all("_lastUpdated").compactMap { DocumentReferenceSearchQuery.DateParam.parse(String($0)) }
    let sort        = DocumentReferenceSearchQuery.SortOrder.parse(first("_sort").map(String.init) ?? "-_lastUpdated")
    let count       = min(first("_count").flatMap { Int($0) } ?? 20, docRefMaxCount)
    let cursor      = first("_cursor").flatMap { DocumentReferenceSearchQuery.SearchCursor.decode(String($0)) }
    let totalMode   = DocumentReferenceSearchQuery.TotalMode.parse(first("_total").map(String.init))

    var missing: [String: Bool] = [:]
    for p in ["status", "type", "category", "identifier", "security-label",
              "facility", "event", "contenttype", "format", "language", "setting",
              "date", "period", "description",
              "subject", "patient", "author", "encounter", "custodian", "authenticator",
              "relatesto", "relation"] {
        if let v = first("\(p):missing").map(String.init) {
            if v == "true" { missing[p] = true } else if v == "false" { missing[p] = false }
        }
    }

    let chains = parseChainParams(from: pairs)
    let has    = parseHasParams(from: pairs)

    return DocumentReferenceSearchQuery(
        status: status, statusNot: statusNot,
        type: type, typeNot: typeNot,
        category: category, categoryNot: categoryNot,
        identifier: identifier,
        securityLabel: securityLabel, securityLabelNot: securityLabelNot,
        facility: facility, event: event,
        contentType: contentType, contentTypeNot: contentTypeNot,
        format: format, formatNot: formatNot,
        language: language, languageNot: languageNot,
        setting: setting, settingNot: settingNot,
        date: date, period: period,
        description: description,
        subject: subject, patient: patient,
        author: author, encounter: encounter,
        custodian: custodian, authenticator: authenticator,
        relatesto: relatesto,
        relation: relation, relationNot: relationNot,
        id: id, lastUpdated: lastUpdated,
        missing: missing, chains: chains, has: has,
        totalMode: totalMode, count: count, sort: sort, cursor: cursor)
}

// ── Helpers ───────────────────────────────────────────────────────────────────

private func docRefConditionalResponse(request: Request, versionId: Int64, lastUpdated: Date) -> Response? {
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

private func docRefRequireFHIRContentType(_ request: Request) throws {
    let ct = request.headers[.contentType] ?? ""
    guard ct.contains(docRefFhirJSON) || ct.contains("application/json") else {
        throw FHIRRouteError.unsupportedMediaType
    }
}

private func docRefDecodeFHIR<T: Decodable>(_ type: T.Type, from buffer: ByteBuffer) throws -> T {
    let data = Data(buffer.readableBytesView)
    do { return try JSONDecoder().decode(type, from: data) }
    catch { throw FHIRRouteError.invalidBody(error.localizedDescription) }
}

private func docRefSelfURL(_ request: Request) -> String {
    let authority = request.head.authority ?? "localhost"
    return "http://\(authority)\(request.uri)"
}

func nextDocumentReferencePageURL(selfURL: String, cursor: DocumentReferenceSearchQuery.SearchCursor, count: Int) -> String {
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

private func docRefParseETag(_ raw: String?) -> Int64? {
    guard let raw else { return nil }
    let stripped = raw
        .trimmingCharacters(in: .whitespaces)
        .replacingOccurrences(of: "W/", with: "")
        .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
    return Int64(stripped)
}
