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
private let preferHeader = HTTPField.Name("Prefer")!

public func addPatientRoutes(to router: Router<BasicRequestContext>, store: PatientStore, logger: Logger) {
    let group = router.group("Patient")

    // POST /Patient — create (with optional If-None-Exist conditional create)
    group.post { request, _ in
        try requireFHIRContentType(request)
        let preferReturn = parsePreferReturn(request.headers[preferHeader])
        var req = request
        let bodyBuffer = try await req.collectBody(upTo: maxBodyBytes)
        try validateResourceType("Patient", from: Data(bodyBuffer.readableBytesView))
        let patient = try decodeFHIR(Patient.self, from: bodyBuffer)

        if let ifNoneExist = request.headers[ifNoneExistHeader] {
            let pairs = parseQueryString(ifNoneExist)
            var checkQuery = parsePatientQuery(from: pairs)
            checkQuery.count = 2
            checkQuery.totalMode = .none
            checkQuery.cursor = nil
            let matches = try await store.search(query: checkQuery)
            if matches.entries.count > 1 {
                throw FHIRServerError.multipleMatches(resourceType: "Patient")
            }
            if let existing = matches.entries.first {
                var headers = HTTPFields()
                headers[.contentType]  = fhirJSON
                headers[.eTag]         = "W/\"\(existing.versionId)\""
                headers[.lastModified] = httpDate(existing.lastUpdated)
                headers[.location] = "\(serverBaseURL(request))/Patient/\(existing.id)/_history/\(existing.versionId)"
                return Response(status: .ok, headers: headers,
                                body: preferBody(preferReturn, resource: existing.jsonWithMeta))
            }
            // 0 matches — fall through to normal create
        }

        let result = try await store.create(patient)
        var headers = HTTPFields()
        headers[.contentType]  = fhirJSON
        headers[.eTag]         = "W/\"\(result.versionId)\""
        headers[.lastModified] = httpDate(result.lastUpdated)
        headers[.location] = "\(serverBaseURL(request))/Patient/\(result.id)/_history/\(result.versionId)"
        return Response(status: .created, headers: headers,
                        body: preferBody(preferReturn, resource: result.jsonData))
    }

    // PUT /Patient?<search> — conditional update (no id in URL)
    group.put { request, _ in
        try requireFHIRContentType(request)
        let preferReturn = parsePreferReturn(request.headers[preferHeader])
        let qpPairs = request.uri.queryParameters.map { (key: $0.key, value: $0.value) }
        guard !qpPairs.isEmpty else {
            throw FHIRRouteError.invalidBody("PUT /Patient requires search parameters for conditional update")
        }
        var req = request
        let bodyBuffer = try await req.collectBody(upTo: maxBodyBytes)
        try validateResourceType("Patient", from: Data(bodyBuffer.readableBytesView))
        let patient = try decodeFHIR(Patient.self, from: bodyBuffer)
        let ifMatch = parseETag(request.headers[.ifMatch])

        var checkQuery = parsePatientQuery(from: qpPairs)
        checkQuery.count = 2
        checkQuery.totalMode = .none
        checkQuery.cursor = nil
        let matches = try await store.search(query: checkQuery)

        switch matches.entries.count {
        case 0:
            let result = try await store.create(patient)
            var headers = HTTPFields()
            headers[.contentType]  = fhirJSON
            headers[.eTag]         = "W/\"\(result.versionId)\""
            headers[.lastModified] = httpDate(result.lastUpdated)
            headers[.location] = "\(serverBaseURL(request))/Patient/\(result.id)/_history/\(result.versionId)"
            return Response(status: .created, headers: headers,
                            body: preferBody(preferReturn, resource: result.jsonData))
        case 1:
            let existingId = matches.entries[0].id
            let result = try await store.update(id: existingId, patient: patient, ifMatch: ifMatch)
            var headers = HTTPFields()
            headers[.contentType]  = fhirJSON
            headers[.eTag]         = "W/\"\(result.versionId)\""
            headers[.lastModified] = httpDate(result.lastUpdated)
            headers[.location] = "\(serverBaseURL(request))/Patient/\(result.id)/_history/\(result.versionId)"
            return Response(status: .ok, headers: headers,
                            body: preferBody(preferReturn, resource: result.jsonData))
        default:
            throw FHIRServerError.multipleMatches(resourceType: "Patient")
        }
    }

    // GET /Patient — search
    group.get { request, _ in
        let qpPairs = request.uri.queryParameters.map { (key: $0.key, value: $0.value) }
        if isStrictHandling(request) {
            let bad = unknownParams(in: qpPairs, known: knownPatientParams)
            if !bad.isEmpty { throw FHIRRouteError.unknownParams(bad) }
        }
        var query = parsePatientQuery(from: qpPairs)
        let elements = parseElements(from: qpPairs)
        let summary = parseSummary(from: qpPairs)
        let includes = parseIncludes(from: qpPairs)
        let revIncludes = parseRevIncludes(from: qpPairs)
        if summary == .count { query.count = 0; query.totalMode = .accurate }
        let result = try await store.search(query: query)

        let base = selfURL(request)
        let baseURL = serverBaseURL(request)
        if summary == .count {
            let bundleData = buildBundleJSON(entries: [], total: result.total,
                                             selfURL: base, nextURL: nil)
            var headers = HTTPFields()
            headers[.contentType] = fhirJSON
            return Response(status: .ok, headers: headers,
                            body: ResponseBody(byteBuffer: ByteBuffer(bytes: bundleData)))
        }
        let nextURL = result.nextCursor.map { nextPageURL(selfURL: base, cursor: $0, count: query.count) }
        let entries = result.entries.map { e -> (fullUrl: String, json: Data) in
            var json = e.jsonWithMeta
            if let s = summary, s != .false {
                json = applySummary(json, mode: s, summaryFields: patientSummaryFields)
            }
            if let elems = elements { json = applyElements(json, elements: elems) }
            return ("\(baseURL)/Patient/\(e.id)", json)
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

    // POST /Patient/_search — form-encoded search (FHIR R4 §3.1.1.7)
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
            let bad = unknownParams(in: pairs, known: knownPatientParams)
            if !bad.isEmpty { throw FHIRRouteError.unknownParams(bad) }
        }
        var query = parsePatientQuery(from: pairs)
        let elements = parseElements(from: pairs)
        let summary = parseSummary(from: pairs)
        let includes = parseIncludes(from: pairs)
        let revIncludes = parseRevIncludes(from: pairs)
        if summary == .count { query.count = 0; query.totalMode = .accurate }
        let result = try await store.search(query: query)

        let base = selfURL(request)
        let baseURL = serverBaseURL(request)
        if summary == .count {
            let bundleData = buildBundleJSON(entries: [], total: result.total,
                                             selfURL: base, nextURL: nil)
            var headers = HTTPFields()
            headers[.contentType] = fhirJSON
            return Response(status: .ok, headers: headers,
                            body: ResponseBody(byteBuffer: ByteBuffer(bytes: bundleData)))
        }
        let nextURL = result.nextCursor.map { nextPageURL(selfURL: base, cursor: $0, count: query.count) }
        let entries = result.entries.map { e -> (fullUrl: String, json: Data) in
            var json = e.jsonWithMeta
            if let s = summary, s != .false {
                json = applySummary(json, mode: s, summaryFields: patientSummaryFields)
            }
            if let elems = elements { json = applyElements(json, elements: elems) }
            return ("\(baseURL)/Patient/\(e.id)", json)
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

    // GET /Patient/:id/_history/:vid — vread
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
            jsonData = applySummary(jsonData, mode: s, summaryFields: patientSummaryFields)
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

    // GET /Patient/_history — type-level history; optional _since and _count
    group.get("_history") { request, _ in
        let qp = request.uri.queryParameters
        let since: Date? = qp["_since"].flatMap { parseFHIRInstant(String($0)) }
        let count = min(qp["_count"].flatMap { Int($0) } ?? 50, maxCount)
        let entries = try await store.typeHistory(since: since, count: count)
        let authority = request.head.authority ?? "localhost"
        let baseURL = "http://\(authority)"
        let bundleData = buildHistoryBundleJSON(entries: entries, baseURL: baseURL, selfURL: "\(baseURL)\(request.uri)")
        var headers = HTTPFields()
        headers[.contentType] = fhirJSON
        return Response(status: .ok, headers: headers,
                        body: ResponseBody(byteBuffer: ByteBuffer(bytes: bundleData)))
    }

    // GET /Patient/:id/_history — instance history
    group.get(":id/_history") { request, context in
        let id = context.parameters.get("id") ?? ""
        let qp = request.uri.queryParameters
        let since: Date? = qp["_since"].flatMap { parseFHIRInstant(String($0)) }
        let count = min(qp["_count"].flatMap { Int($0) } ?? 50, maxCount)
        let entries = try await store.history(id: id, since: since, count: count)
        let authority = request.head.authority ?? "localhost"
        let baseURL = "http://\(authority)"
        let bundleData = buildHistoryBundleJSON(entries: entries, baseURL: baseURL, selfURL: "\(baseURL)\(request.uri)")
        var headers = HTTPFields()
        headers[.contentType] = fhirJSON
        return Response(status: .ok, headers: headers,
                        body: ResponseBody(byteBuffer: ByteBuffer(bytes: bundleData)))
    }

    // GET /Patient/:id — read
    group.get(":id") { request, context in
        let id = context.parameters.get("id") ?? ""
        let result = try await store.read(id: id)
        if let r = conditionalResponse(request: request, versionId: result.versionId, lastUpdated: result.lastUpdated) { return r }
        let qpPairs = request.uri.queryParameters.map { (key: $0.key, value: $0.value) }
        var jsonData = result.jsonData
        if let s = parseSummary(from: qpPairs), s != .false && s != .count {
            jsonData = applySummary(jsonData, mode: s, summaryFields: patientSummaryFields)
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

    // PUT /Patient/:id — update
    group.put(":id") { request, context in
        try requireFHIRContentType(request)
        let preferReturn = parsePreferReturn(request.headers[preferHeader])
        let id = context.parameters.get("id") ?? ""
        let ifMatch = parseETag(request.headers[.ifMatch])
        var req = request
        let bodyBuffer = try await req.collectBody(upTo: maxBodyBytes)
        try validateResourceType("Patient", from: Data(bodyBuffer.readableBytesView))
        let patient = try decodeFHIR(Patient.self, from: bodyBuffer)
        let result = try await store.update(id: id, patient: patient, ifMatch: ifMatch)
        var headers = HTTPFields()
        headers[.contentType]  = fhirJSON
        headers[.eTag]         = "W/\"\(result.versionId)\""
        headers[.lastModified] = httpDate(result.lastUpdated)
        headers[.location] = "\(serverBaseURL(request))/Patient/\(result.id)/_history/\(result.versionId)"
        return Response(status: .ok, headers: headers,
                        body: preferBody(preferReturn, resource: result.jsonData))
    }

    // PATCH /Patient/:id — JSON Patch (RFC 6902)
    group.patch(":id") { request, context in
        let id = context.parameters.get("id") ?? ""
        let ct = request.headers[.contentType] ?? ""
        guard ct.contains("application/json-patch+json") else {
            throw FHIRRouteError.invalidBody(
                "PATCH requires Content-Type: application/json-patch+json"
            )
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
            case .invalidPatch(let m), .pathNotFound(let m):
                throw FHIRRouteError.invalidBody(m)
            case .testFailed(let m):
                throw FHIRRouteError.unprocessableEntity(m)
            }
        }
        let patient: Patient
        do {
            patient = try JSONDecoder().decode(Patient.self, from: patchedJSON)
        } catch {
            throw FHIRRouteError.unprocessableEntity(
                "Patched resource is not valid FHIR: \(error.localizedDescription)"
            )
        }
        let result = try await store.update(id: id, patient: patient, ifMatch: ifMatch)
        var headers = HTTPFields()
        headers[.contentType]  = fhirJSON
        headers[.eTag]         = "W/\"\(result.versionId)\""
        headers[.lastModified] = httpDate(result.lastUpdated)
        headers[.location] = "\(serverBaseURL(request))/Patient/\(result.id)/_history/\(result.versionId)"
        return Response(status: .ok, headers: headers,
                        body: ResponseBody(byteBuffer: ByteBuffer(bytes: result.jsonData)))
    }

    // DELETE /Patient?<search> — conditional delete (no id in URL)
    group.delete { request, _ in
        let qpPairs = request.uri.queryParameters.map { (key: $0.key, value: $0.value) }
        guard !qpPairs.isEmpty else {
            throw FHIRRouteError.invalidBody("DELETE /Patient requires search parameters for conditional delete")
        }
        var checkQuery = parsePatientQuery(from: qpPairs)
        checkQuery.count = 2
        checkQuery.totalMode = .none
        checkQuery.cursor = nil
        let matches = try await store.search(query: checkQuery)
        switch matches.entries.count {
        case 0:
            throw FHIRServerError.notFound(resourceType: "Patient", id: "(search)")
        case 1:
            let ifMatch = parseETag(request.headers[.ifMatch])
            let result = try await store.delete(id: matches.entries[0].id, ifMatch: ifMatch)
            var headers = HTTPFields()
            headers[.eTag]         = "W/\"\(result.versionId)\""
            headers[.lastModified] = httpDate(result.lastUpdated)
            return Response(status: .noContent, headers: headers, body: .init())
        default:
            throw FHIRServerError.multipleMatches(resourceType: "Patient")
        }
    }

    // DELETE /Patient/:id — logical delete
    group.delete(":id") { request, context in
        let id = context.parameters.get("id") ?? ""
        let ifMatch = parseETag(request.headers[.ifMatch])
        let result = try await store.delete(id: id, ifMatch: ifMatch)
        var headers = HTTPFields()
        headers[.eTag]         = "W/\"\(result.versionId)\""
        headers[.lastModified] = httpDate(result.lastUpdated)
        return Response(status: .noContent, headers: headers, body: .init())
    }
}

// ── Query parser ──────────────────────────────────────────────────────────────

private func parsePatientQuery(from pairs: some Collection<(key: Substring, value: Substring)>) -> PatientSearchQuery {
    let pairs = normalizeReferenceTypeModifiers(pairs)
    func first(_ key: String) -> Substring? {
        pairs.first(where: { $0.key == key[...] })?.value
    }
    func all(_ key: String) -> [Substring] {
        pairs.filter { $0.key == key[...] }.map { $0.value }
    }

    let name             = PatientSearchQuery.StringParam.parse(key: "name", from: pairs)
    let family           = PatientSearchQuery.StringParam.parse(key: "family", from: pairs)
    let given            = PatientSearchQuery.StringParam.parse(key: "given", from: pairs)
    let address          = PatientSearchQuery.StringParam.parse(key: "address", from: pairs)
    let addressCity      = PatientSearchQuery.StringParam.parse(key: "address-city", from: pairs)
    let addressState     = PatientSearchQuery.StringParam.parse(key: "address-state", from: pairs)
    let addressPostalCode = PatientSearchQuery.StringParam.parse(key: "address-postalcode", from: pairs)
    let addressCountry   = PatientSearchQuery.StringParam.parse(key: "address-country", from: pairs)
    let gender = all("gender").flatMap { v in
        String(v).split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }
    }
    let active = first("active").flatMap { v -> Bool? in
        switch String(v).lowercased() {
        case "true":  return true
        case "false": return false
        default:      return nil
        }
    }
    let phone         = first("phone").map(String.init)
    let email         = first("email").map(String.init)
    let organization        = first("organization").map(String.init)
    let generalPractitioner = first("general-practitioner").map(String.init)
    let link                = first("link").map(String.init)
    let language    = all("language").flatMap { PatientSearchQuery.TokenParam.parseList(String($0)) }
    let languageNot = all("language:not").flatMap { PatientSearchQuery.TokenParam.parseList(String($0)) }
    let deceased: Bool? = first("deceased").flatMap { v -> Bool? in
        switch String(v).lowercased() { case "true": return true; case "false": return false; default: return nil }
    }
    let deathDates = all("death-date").compactMap { PatientSearchQuery.BirthdateParam.parse(String($0)) }
    let identifierNot = first("identifier:not").map { PatientSearchQuery.IdentifierParam.parseList(String($0)) } ?? []
    let genderNot = all("gender:not").flatMap { v in
        String(v).split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }
    }
    let identifier = first("identifier").map { PatientSearchQuery.IdentifierParam.parseList(String($0)) } ?? []
    let id         = first("_id").map {
        String($0).split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }
    } ?? []
    let birthdates  = all("birthdate").compactMap { PatientSearchQuery.BirthdateParam.parse(String($0)) }
    let lastUpdated = all("_lastUpdated").compactMap { PatientSearchQuery.BirthdateParam.parse(String($0)) }
    let sortKeys    = PatientSearchQuery.parseSortKeys(first("_sort").map(String.init) ?? "-_lastUpdated")
    let count       = min(first("_count").flatMap { Int($0) } ?? 20, maxCount)
    let cursor      = first("_cursor").flatMap { SearchCursor.decode(String($0)) }
    let totalMode   = PatientSearchQuery.TotalMode.parse(first("_total").map(String.init))
    var missing: [String: Bool] = [:]
    for p in ["name","family","given","gender","active","address","address-city","address-state",
              "address-postalcode","address-country","phone","email","identifier","birthdate",
              "deceased","death-date","organization","general-practitioner","link","language"] {
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
    let has = parseHasParams(from: pairs)
    var query = PatientSearchQuery(
        name: name, family: family, given: given,
        gender: gender, active: active,
        address: address, addressCity: addressCity,
        addressState: addressState, addressPostalCode: addressPostalCode,
        addressCountry: addressCountry, phone: phone, email: email,
        organization: organization, generalPractitioner: generalPractitioner,
        link: link, language: language, languageNot: languageNot,
        identifierNot: identifierNot, genderNot: genderNot,
        identifier: identifier, id: id,
        birthdate: birthdates, deceased: deceased, deathDate: deathDates,
        lastUpdated: lastUpdated,
        tokenTexts: tokenTexts,
        missing: missing, chains: chains, has: has, totalMode: totalMode, sortKeys: sortKeys, count: count, cursor: cursor)
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

private func nextPageURL(selfURL: String, cursor: SearchCursor, count: Int) -> String {
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

// ── Known search parameters ───────────────────────────────────────────────────

private let knownPatientParams: Set<String> = [
    "name", "family", "given", "gender", "active",
    "address", "address-city", "address-state", "address-postalcode", "address-country",
    "phone", "email", "identifier", "birthdate", "deceased", "death-date",
    "organization", "general-practitioner", "link",
    "language", "language:not",
    "gender:not", "identifier:not",
    "_id", "_lastUpdated", "_sort", "_count", "_cursor", "_total", "_elements", "_format", "_summary",
    "_include", "_revinclude",
]

// ── Route-level errors ────────────────────────────────────────────────────────

enum FHIRRouteError: Error {
    case unsupportedMediaType
    case invalidBody(String)
    case unknownParams([String])
    case unprocessableEntity(String)
}

extension FHIRRouteError: HTTPResponseError {
    var status: HTTPResponse.Status {
        switch self {
        case .unsupportedMediaType:  .unsupportedMediaType
        case .invalidBody:           .badRequest
        case .unknownParams:         .badRequest
        case .unprocessableEntity:   .unprocessableContent
        }
    }

    func response(from request: Request, context: some RequestContext) throws -> Response {
        let (severity, code, message): (IssueSeverity, IssueType, String) = switch self {
        case .unsupportedMediaType:
            (.error, .notSupported, "Content-Type must be application/fhir+json")
        case .invalidBody(let msg):
            (.error, .invalid, "Request body is not valid FHIR JSON: \(msg)")
        case .unknownParams(let names):
            (.error, .notSupported, "Unknown search parameter(s): \(names.joined(separator: ", "))")
        case .unprocessableEntity(let msg):
            (.error, .invalid, msg)
        }
        let outcome = buildOutcome(severity: severity, code: code, diagnostics: message)
        let data = (try? JSONEncoder().encode(outcome)) ?? Data()
        var headers = HTTPFields()
        headers[.contentType] = fhirJSON
        return Response(status: status, headers: headers,
                        body: ResponseBody(byteBuffer: ByteBuffer(bytes: data)))
    }
}

extension FHIRServerError: HTTPResponseError {
    public var status: HTTPResponse.Status {
        switch self {
        case .unsupportedMediaType:         .unsupportedMediaType
        case .invalidBody:                  .badRequest
        case .notFound:                     .notFound
        case .gone:                         .gone
        case .versionConflict:              .preconditionFailed
        case .multipleMatches:              .preconditionFailed
        }
    }

    public func response(from request: Request, context: some RequestContext) throws -> Response {
        let (severity, code, message): (IssueSeverity, IssueType, String) = switch self {
        case .unsupportedMediaType:
            (.error, .notSupported, "Content-Type must be application/fhir+json")
        case .invalidBody(let msg):
            (.error, .invalid, msg)
        case .notFound(let rt, let id):
            (.error, .notFound, "\(rt)/\(id) not found")
        case .gone(let rt, let id):
            (.error, .deleted, "\(rt)/\(id) has been deleted")
        case .versionConflict(let id, let expected, let actual):
            (.error, .conflict,
             "Version conflict for Patient/\(id): expected W/\"\(expected)\", current is W/\"\(actual.map(String.init) ?? "none")\"")
        case .multipleMatches(let rt):
            (.error, .multipleMatches,
             "Multiple \(rt) resources match the search criteria; criteria are not selective enough")
        }
        let outcome = buildOutcome(severity: severity, code: code, diagnostics: message)
        let data = (try? JSONEncoder().encode(outcome)) ?? Data()
        var headers = HTTPFields()
        headers[.contentType] = fhirJSON
        return Response(status: status, headers: headers,
                        body: ResponseBody(byteBuffer: ByteBuffer(bytes: data)))
    }
}
