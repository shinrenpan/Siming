import Foundation
import HTTPTypes
import Hummingbird
import Logging
import ModelsR4
import NIOCore
import SimingCore

private let maxCount = 100
private let fhirJSON = "application/fhir+json"
private let maxBodyBytes = 4 * 1024 * 1024
private let ifNoneExistHeader = HTTPField.Name("If-None-Exist")!
private let preferHeader = HTTPField.Name("Prefer")!

let knownPractitionerParams: Set<String> = [
    "name", "family", "given", "phonetic", "identifier", "active", "gender",
    "address", "address-city", "address-state", "address-country", "address-postalcode", "address-use",
    "phone", "email", "communication",
    "identifier:not", "gender:not", "communication:not",
    "_id", "_lastUpdated", "_sort", "_count", "_cursor", "_total", "_elements", "_format", "_summary",
    "_include", "_revinclude",
]

public func addPractitionerRoutes(
    to router: Router<BasicRequestContext>,
    store: PractitionerStore,
    logger: Logger
) {
    let group = router.group("Practitioner")

    // POST /Practitioner — create
    group.post { request, _ in
        try requireFHIRContentType(request)
        let preferReturn = parsePreferReturn(request.headers[preferHeader])
        var req = request
        let bodyBuffer = try await req.collectBody(upTo: maxBodyBytes)
        try validateResourceType("Practitioner", from: Data(bodyBuffer.readableBytesView))
        let prac = try decodeFHIR(Practitioner.self, from: bodyBuffer)

        if let ifNoneExist = request.headers[ifNoneExistHeader] {
            let pairs = parseQueryString(ifNoneExist)
            var checkQuery = parsePractitionerQuery(from: pairs)
            checkQuery.count = 2; checkQuery.totalMode = .none; checkQuery.cursor = nil
            let matches = try await store.search(query: checkQuery)
            if matches.entries.count > 1 {
                throw FHIRServerError.multipleMatches(resourceType: "Practitioner")
            }
            if let existing = matches.entries.first {
                var headers = HTTPFields()
                headers[.contentType]  = fhirJSON
                headers[.eTag]         = "W/\"\(existing.versionId)\""
                headers[.lastModified] = httpDate(existing.lastUpdated)
                headers[.location] = "\(serverBaseURL(request))/Practitioner/\(existing.id)/_history/\(existing.versionId)"
                return Response(status: .ok, headers: headers,
                                body: preferBody(preferReturn, resource: existing.jsonWithMeta))
            }
        }

        let result = try await store.create(prac)
        var headers = HTTPFields()
        headers[.contentType]  = fhirJSON
        headers[.eTag]         = "W/\"\(result.versionId)\""
        headers[.lastModified] = httpDate(result.lastUpdated)
        headers[.location] = "\(serverBaseURL(request))/Practitioner/\(result.id)/_history/\(result.versionId)"
        return Response(status: .created, headers: headers,
                        body: preferBody(preferReturn, resource: result.jsonData))
    }

    // PUT /Practitioner?<search> — conditional update
    group.put { request, _ in
        try requireFHIRContentType(request)
        let preferReturn = parsePreferReturn(request.headers[preferHeader])
        let qpPairs = request.uri.queryParameters.map { (key: $0.key, value: $0.value) }
        guard !qpPairs.isEmpty else {
            throw FHIRRouteError.invalidBody("PUT /Practitioner requires search parameters for conditional update")
        }
        var req = request
        let bodyBuffer = try await req.collectBody(upTo: maxBodyBytes)
        try validateResourceType("Practitioner", from: Data(bodyBuffer.readableBytesView))
        let prac = try decodeFHIR(Practitioner.self, from: bodyBuffer)
        let ifMatch = parseETag(request.headers[.ifMatch])

        var checkQuery = parsePractitionerQuery(from: qpPairs)
        checkQuery.count = 2; checkQuery.totalMode = .none; checkQuery.cursor = nil
        let matches = try await store.search(query: checkQuery)

        switch matches.entries.count {
        case 0:
            let result = try await store.create(prac)
            var headers = HTTPFields()
            headers[.contentType]  = fhirJSON
            headers[.eTag]         = "W/\"\(result.versionId)\""
            headers[.lastModified] = httpDate(result.lastUpdated)
            headers[.location] = "\(serverBaseURL(request))/Practitioner/\(result.id)/_history/\(result.versionId)"
            return Response(status: .created, headers: headers,
                            body: preferBody(preferReturn, resource: result.jsonData))
        case 1:
            let existingId = matches.entries[0].id
            let result = try await store.update(id: existingId, practitioner: prac, ifMatch: ifMatch)
            var headers = HTTPFields()
            headers[.contentType]  = fhirJSON
            headers[.eTag]         = "W/\"\(result.versionId)\""
            headers[.lastModified] = httpDate(result.lastUpdated)
            headers[.location] = "\(serverBaseURL(request))/Practitioner/\(result.id)/_history/\(result.versionId)"
            return Response(status: .ok, headers: headers,
                            body: preferBody(preferReturn, resource: result.jsonData))
        default:
            throw FHIRServerError.multipleMatches(resourceType: "Practitioner")
        }
    }

    // GET /Practitioner/:id/_history/:vid — vread
    group.get(":id/_history/:vid") { request, context in
        let id = context.parameters.get("id") ?? ""
        guard let vid = context.parameters.get("vid").flatMap(Int64.init) else {
            throw FHIRRouteError.invalidBody("_history version id must be an integer")
        }
        let result = try await store.vread(id: id, versionId: vid)
        if let r = conditionalResponse(request: request, versionId: result.versionId, lastUpdated: result.lastUpdated) { return r }
        let qpPairs = request.uri.queryParameters.map { (key: $0.key, value: $0.value) }
        var jsonData = result.jsonData
        if let s = parseSummary(from: qpPairs), s != .false && s != .count {
            jsonData = applySummary(jsonData, mode: s, summaryFields: practitionerSummaryFields)
        } else if let elems = parseElements(from: qpPairs) {
            jsonData = applyElements(jsonData, elements: elems)
        }
        var headers = HTTPFields()
        headers[.contentType]  = fhirJSON
        headers[.eTag]         = "W/\"\(result.versionId)\""
        headers[.lastModified] = httpDate(result.lastUpdated)
        return Response(status: .ok, headers: headers,
                        body: ResponseBody(byteBuffer: ByteBuffer(bytes: jsonData)))
    }

    // GET /Practitioner/_history — type-level history
    group.get("_history") { request, _ in
        let qp = request.uri.queryParameters
        let since: Date? = qp["_since"].flatMap { parseFHIRInstant(String($0)) }
        let count = min(qp["_count"].flatMap { Int($0) } ?? 50, maxCount)
        let entries = try await store.typeHistory(since: since, count: count)
        let authority = request.head.authority ?? "localhost"
        let baseURL = "http://\(authority)"
        let bundleData = buildHistoryBundleJSON(entries: entries, baseURL: baseURL)
        var headers = HTTPFields()
        headers[.contentType] = fhirJSON
        return Response(status: .ok, headers: headers,
                        body: ResponseBody(byteBuffer: ByteBuffer(bytes: bundleData)))
    }

    // GET /Practitioner/:id/_history — instance history
    group.get(":id/_history") { request, context in
        let id = context.parameters.get("id") ?? ""
        let qp = request.uri.queryParameters
        let since: Date? = qp["_since"].flatMap { parseFHIRInstant(String($0)) }
        let count = min(qp["_count"].flatMap { Int($0) } ?? 50, maxCount)
        let entries = try await store.history(id: id, since: since, count: count)
        let authority = request.head.authority ?? "localhost"
        let baseURL = "http://\(authority)"
        let bundleData = buildHistoryBundleJSON(entries: entries, baseURL: baseURL)
        var headers = HTTPFields()
        headers[.contentType] = fhirJSON
        return Response(status: .ok, headers: headers,
                        body: ResponseBody(byteBuffer: ByteBuffer(bytes: bundleData)))
    }

    // GET /Practitioner/:id — read
    group.get(":id") { request, context in
        let id = context.parameters.get("id") ?? ""
        let result = try await store.read(id: id)
        if let r = conditionalResponse(request: request, versionId: result.versionId, lastUpdated: result.lastUpdated) { return r }
        let qpPairs = request.uri.queryParameters.map { (key: $0.key, value: $0.value) }
        var jsonData = result.jsonData
        if let s = parseSummary(from: qpPairs), s != .false && s != .count {
            jsonData = applySummary(jsonData, mode: s, summaryFields: practitionerSummaryFields)
        } else if let elems = parseElements(from: qpPairs) {
            jsonData = applyElements(jsonData, elements: elems)
        }
        var headers = HTTPFields()
        headers[.contentType]  = fhirJSON
        headers[.eTag]         = "W/\"\(result.versionId)\""
        headers[.lastModified] = httpDate(result.lastUpdated)
        return Response(status: .ok, headers: headers,
                        body: ResponseBody(byteBuffer: ByteBuffer(bytes: jsonData)))
    }

    // PUT /Practitioner/:id — update
    group.put(":id") { request, context in
        try requireFHIRContentType(request)
        let preferReturn = parsePreferReturn(request.headers[preferHeader])
        let id = context.parameters.get("id") ?? ""
        let ifMatch = parseETag(request.headers[.ifMatch])
        var req = request
        let bodyBuffer = try await req.collectBody(upTo: maxBodyBytes)
        try validateResourceType("Practitioner", from: Data(bodyBuffer.readableBytesView))
        let prac = try decodeFHIR(Practitioner.self, from: bodyBuffer)
        let result = try await store.update(id: id, practitioner: prac, ifMatch: ifMatch)
        var headers = HTTPFields()
        headers[.contentType]  = fhirJSON
        headers[.eTag]         = "W/\"\(result.versionId)\""
        headers[.lastModified] = httpDate(result.lastUpdated)
        headers[.location] = "\(serverBaseURL(request))/Practitioner/\(result.id)/_history/\(result.versionId)"
        return Response(status: .ok, headers: headers,
                        body: preferBody(preferReturn, resource: result.jsonData))
    }

    // PATCH /Practitioner/:id — JSON Patch (RFC 6902)
    group.patch(":id") { request, context in
        let id = context.parameters.get("id") ?? ""
        let ct = request.headers[.contentType] ?? ""
        guard ct.contains("application/json-patch+json") else {
            throw FHIRRouteError.invalidBody("PATCH requires Content-Type: application/json-patch+json")
        }
        let ifMatch = parseETag(request.headers[.ifMatch])
        var req = request
        let bodyBuffer = try await req.collectBody(upTo: maxBodyBytes)
        let patchData = Data(bodyBuffer.readableBytesView)
        let current = try await store.read(id: id)
        let patchedJSON: Data
        do {
            patchedJSON = try JSONPatch.apply(patchData, to: current.jsonData)
        } catch let e as JSONPatchError {
            switch e {
            case .invalidPatch(let m), .pathNotFound(let m): throw FHIRRouteError.invalidBody(m)
            case .testFailed(let m): throw FHIRRouteError.unprocessableEntity(m)
            }
        }
        let prac: Practitioner
        do { prac = try JSONDecoder().decode(Practitioner.self, from: patchedJSON) }
        catch { throw FHIRRouteError.unprocessableEntity("Patched resource is not valid FHIR: \(error.localizedDescription)") }
        let result = try await store.update(id: id, practitioner: prac, ifMatch: ifMatch)
        var headers = HTTPFields()
        headers[.contentType]  = fhirJSON
        headers[.eTag]         = "W/\"\(result.versionId)\""
        headers[.lastModified] = httpDate(result.lastUpdated)
        headers[.location] = "\(serverBaseURL(request))/Practitioner/\(result.id)/_history/\(result.versionId)"
        return Response(status: .ok, headers: headers,
                        body: ResponseBody(byteBuffer: ByteBuffer(bytes: result.jsonData)))
    }

    // DELETE /Practitioner?<search> — conditional delete
    group.delete { request, _ in
        let qpPairs = request.uri.queryParameters.map { (key: $0.key, value: $0.value) }
        guard !qpPairs.isEmpty else {
            throw FHIRRouteError.invalidBody("DELETE /Practitioner requires search parameters for conditional delete")
        }
        var checkQuery = parsePractitionerQuery(from: qpPairs)
        checkQuery.count = 2; checkQuery.totalMode = .none; checkQuery.cursor = nil
        let matches = try await store.search(query: checkQuery)
        switch matches.entries.count {
        case 0:
            throw FHIRServerError.notFound(resourceType: "Practitioner", id: "(search)")
        case 1:
            let ifMatch = parseETag(request.headers[.ifMatch])
            let result = try await store.delete(id: matches.entries[0].id, ifMatch: ifMatch)
            var headers = HTTPFields()
            headers[.eTag]         = "W/\"\(result.versionId)\""
            headers[.lastModified] = httpDate(result.lastUpdated)
            return Response(status: .noContent, headers: headers, body: .init())
        default:
            throw FHIRServerError.multipleMatches(resourceType: "Practitioner")
        }
    }

    // DELETE /Practitioner/:id — logical delete
    group.delete(":id") { request, context in
        let id = context.parameters.get("id") ?? ""
        let ifMatch = parseETag(request.headers[.ifMatch])
        let result = try await store.delete(id: id, ifMatch: ifMatch)
        var headers = HTTPFields()
        headers[.eTag]         = "W/\"\(result.versionId)\""
        headers[.lastModified] = httpDate(result.lastUpdated)
        return Response(status: .noContent, headers: headers, body: .init())
    }

    // GET /Practitioner — search
    group.get { request, _ in
        let pairs = request.uri.queryParameters.map { (key: $0.key, value: $0.value) }
        if isStrictHandling(request) {
            let bad = unknownParams(in: pairs, known: knownPractitionerParams)
            if !bad.isEmpty { throw FHIRRouteError.unknownParams(bad) }
        }
        var query = parsePractitionerQuery(from: pairs)
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
            headers[.contentType] = fhirJSON
            return Response(status: .ok, headers: headers,
                            body: ResponseBody(byteBuffer: ByteBuffer(bytes: bundleData)))
        }
        let nextURL = result.nextCursor.map { nextPractitionerPageURL(selfURL: base, cursor: $0, count: query.count) }
        let entries = result.entries.map { e -> (fullUrl: String, json: Data) in
            var json = e.jsonWithMeta
            if let s = summary, s != .false { json = applySummary(json, mode: s, summaryFields: practitionerSummaryFields) }
            if let elems = elements { json = applyElements(json, elements: elems) }
            return ("\(baseURL)/Practitioner/\(e.id)", json)
        }
        let mainIds = result.entries.map(\.id)
        let resolver = IncludeResolver(client: store.client, logger: logger)
        async let included = resolver.resolve(includes: includes, sourceIds: mainIds)
        async let revIncluded = resolver.resolveRev(revIncludes: revIncludes, mainIds: mainIds)
        let includeEntries = includeEntryTuples(from: try await included + revIncluded, baseURL: baseURL)
        let bundleData = buildBundleJSON(entries: entries, includeEntries: includeEntries,
                                         total: result.total, selfURL: base, nextURL: nextURL)
        var headers = HTTPFields()
        headers[.contentType] = fhirJSON
        return Response(status: .ok, headers: headers,
                        body: ResponseBody(byteBuffer: ByteBuffer(bytes: bundleData)))
    }

    // POST /Practitioner/_search — form-encoded search
    group.post("_search") { request, _ in
        let ct = request.headers[.contentType] ?? ""
        guard ct.contains("application/x-www-form-urlencoded") else {
            throw FHIRRouteError.invalidBody("Content-Type must be application/x-www-form-urlencoded for _search")
        }
        var req = request
        let bodyBuffer = try await req.collectBody(upTo: maxBodyBytes)
        let urlPairs = request.uri.queryParameters.map { (key: $0.key, value: $0.value) }
        let pairs = urlPairs + parseFormPairs(from: bodyBuffer)
        if isStrictHandling(request) {
            let bad = unknownParams(in: pairs, known: knownPractitionerParams)
            if !bad.isEmpty { throw FHIRRouteError.unknownParams(bad) }
        }
        var query = parsePractitionerQuery(from: pairs)
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
            headers[.contentType] = fhirJSON
            return Response(status: .ok, headers: headers,
                            body: ResponseBody(byteBuffer: ByteBuffer(bytes: bundleData)))
        }
        let nextURL = result.nextCursor.map { nextPractitionerPageURL(selfURL: base, cursor: $0, count: query.count) }
        let entries = result.entries.map { e -> (fullUrl: String, json: Data) in
            var json = e.jsonWithMeta
            if let s = summary, s != .false { json = applySummary(json, mode: s, summaryFields: practitionerSummaryFields) }
            if let elems = elements { json = applyElements(json, elements: elems) }
            return ("\(baseURL)/Practitioner/\(e.id)", json)
        }
        let mainIds = result.entries.map(\.id)
        let resolver = IncludeResolver(client: store.client, logger: logger)
        async let included = resolver.resolve(includes: includes, sourceIds: mainIds)
        async let revIncluded = resolver.resolveRev(revIncludes: revIncludes, mainIds: mainIds)
        let includeEntries = includeEntryTuples(from: try await included + revIncluded, baseURL: baseURL)
        let bundleData = buildBundleJSON(entries: entries, includeEntries: includeEntries,
                                         total: result.total, selfURL: base, nextURL: nextURL)
        var headers = HTTPFields()
        headers[.contentType] = fhirJSON
        return Response(status: .ok, headers: headers,
                        body: ResponseBody(byteBuffer: ByteBuffer(bytes: bundleData)))
    }
}

// ── Query parser ──────────────────────────────────────────────────────────────

func parsePractitionerQuery(from pairs: some Collection<(key: Substring, value: Substring)>) -> PractitionerSearchQuery {
    let pairs = normalizeReferenceTypeModifiers(pairs)
    func first(_ key: String) -> Substring? {
        pairs.first(where: { $0.key == key[...] })?.value
    }
    func all(_ key: String) -> [Substring] {
        pairs.filter { $0.key == key[...] }.map { $0.value }
    }

    let name           = PractitionerSearchQuery.StringParam.parse(key: "name",     from: pairs)
    let family         = PractitionerSearchQuery.StringParam.parse(key: "family",   from: pairs)
    let given          = PractitionerSearchQuery.StringParam.parse(key: "given",    from: pairs)
    let phonetic       = PractitionerSearchQuery.StringParam.parse(key: "phonetic", from: pairs)
    let address        = PractitionerSearchQuery.StringParam.parse(key: "address",             from: pairs)
    let addressCity    = PractitionerSearchQuery.StringParam.parse(key: "address-city",        from: pairs)
    let addressState   = PractitionerSearchQuery.StringParam.parse(key: "address-state",       from: pairs)
    let addressPostalCode = PractitionerSearchQuery.StringParam.parse(key: "address-postalcode", from: pairs)
    let addressCountry = PractitionerSearchQuery.StringParam.parse(key: "address-country",     from: pairs)

    let active: Bool?
    if let v = first("active") {
        active = String(v) == "true" ? true : (String(v) == "false" ? false : nil)
    } else { active = nil }

    let gender    = all("gender").flatMap { String($0).split(separator: ",").map(String.init) }
    let genderNot = all("gender:not").flatMap { String($0).split(separator: ",").map(String.init) }

    let communication    = all("communication").flatMap { PractitionerSearchQuery.TokenParam.parseList(String($0)) }
    let communicationNot = all("communication:not").flatMap { PractitionerSearchQuery.TokenParam.parseList(String($0)) }

    let identifier    = first("identifier").map { PractitionerSearchQuery.IdentifierParam.parseList(String($0)) } ?? []
    let identifierNot = first("identifier:not").map { PractitionerSearchQuery.IdentifierParam.parseList(String($0)) } ?? []

    let phone = first("phone").map(String.init)
    let email = first("email").map(String.init)

    let id          = first("_id").map {
        String($0).split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }
    } ?? []
    let lastUpdated = all("_lastUpdated").compactMap { PractitionerSearchQuery.DateParam.parse(String($0)) }
    let sortKeys = PractitionerSearchQuery.parseSortKeys(first("_sort").map(String.init) ?? "-_lastUpdated")
    let count       = min(first("_count").flatMap { Int($0) } ?? 20, maxCount)
    let cursor      = first("_cursor").flatMap { SearchCursor.decode(String($0)) }
    let totalMode   = PractitionerSearchQuery.TotalMode.parse(first("_total").map(String.init))

    var missing: [String: Bool] = [:]
    for p in ["name", "family", "given", "phonetic", "identifier", "active", "gender",
              "communication", "address", "phone", "email"] {
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

    var query = PractitionerSearchQuery(
        name: name, family: family, given: given, phonetic: phonetic,
        identifier: identifier, identifierNot: identifierNot, active: active,
        gender: gender, genderNot: genderNot,
        address: address, addressCity: addressCity, addressState: addressState,
        addressPostalCode: addressPostalCode, addressCountry: addressCountry,
        phone: phone, email: email,
        communication: communication, communicationNot: communicationNot,
        id: id, lastUpdated: lastUpdated, tokenTexts: tokenTexts,
        missing: missing, chains: chains, has: has,
        totalMode: totalMode, count: count, sortKeys: sortKeys, cursor: cursor)
    query.meta = parseMetaSearchParams(from: pairs)
    return query
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

private func requireFHIRContentType(_ request: Request) throws {
    let ct = request.headers[.contentType] ?? ""
    guard ct.contains(fhirJSON) || ct.contains("application/json") else {
        throw FHIRRouteError.unsupportedMediaType
    }
}

private func decodeFHIR<T: Decodable>(_ type: T.Type, from buffer: ByteBuffer) throws -> T {
    let data = Data(buffer.readableBytesView)
    do { return try JSONDecoder().decode(type, from: data) }
    catch { throw FHIRRouteError.invalidBody(error.localizedDescription) }
}

private func selfURL(_ request: Request) -> String {
    let authority = request.head.authority ?? "localhost"
    return "http://\(authority)\(request.uri)"
}

private func nextPractitionerPageURL(selfURL: String, cursor: SearchCursor, count: Int) -> String {
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
