import Foundation
import HTTPTypes
import Hummingbird
import Logging
import ModelsR4
import NIOCore
import SimingCore

private let apptMaxCount = 100
private let apptFhirJSON = "application/fhir+json"
private let apptMaxBodyBytes = 4 * 1024 * 1024
private let apptIfNoneExistHeader = HTTPField.Name("If-None-Exist")!
private let apptPreferHeader = HTTPField.Name("Prefer")!

let knownAppointmentParams: Set<String> = [
    "patient", "actor", "practitioner", "location", "supporting-info",
    "status", "service-type", "appointment-type", "specialty",
    "reason-code", "service-category", "part-status", "identifier", "date",
    "status:not", "service-type:not", "appointment-type:not", "specialty:not",
    "reason-code:not", "service-category:not", "part-status:not",
    "_id", "_lastUpdated", "_sort", "_count", "_cursor", "_total",
    "_elements", "_format", "_summary", "_include", "_revinclude",
]

public func addAppointmentRoutes(
    to router: Router<BasicRequestContext>,
    store: AppointmentStore,
    logger: Logger
) {
    let group = router.group("Appointment")

    // POST /Appointment — create
    group.post { request, _ in
        try apptRequireFHIRContentType(request)
        let returnMinimal = (request.headers[apptPreferHeader] ?? "").contains("return=minimal")
        var req = request
        let bodyBuffer = try await req.collectBody(upTo: apptMaxBodyBytes)
        let appt = try apptDecodeFHIR(Appointment.self, from: bodyBuffer)

        if let ifNoneExist = request.headers[apptIfNoneExistHeader] {
            let pairs = parseQueryString(ifNoneExist)
            var checkQuery = parseAppointmentQuery(from: pairs)
            checkQuery.count = 2; checkQuery.totalMode = .none; checkQuery.cursor = nil
            let matches = try await store.search(query: checkQuery)
            if matches.entries.count > 1 {
                throw FHIRServerError.multipleMatches(resourceType: "Appointment")
            }
            if let existing = matches.entries.first {
                var headers = HTTPFields()
                headers[.contentType]  = apptFhirJSON
                headers[.eTag]         = "W/\"\(existing.versionId)\""
                headers[.lastModified] = httpDate(existing.lastUpdated)
                headers[.location]     = "/Appointment/\(existing.id)/_history/\(existing.versionId)"
                return Response(status: .ok, headers: headers,
                                body: returnMinimal ? .init() : ResponseBody(byteBuffer: ByteBuffer(bytes: existing.jsonWithMeta)))
            }
        }

        let result = try await store.create(appt)
        var headers = HTTPFields()
        headers[.contentType]  = apptFhirJSON
        headers[.eTag]         = "W/\"\(result.versionId)\""
        headers[.lastModified] = httpDate(result.lastUpdated)
        headers[.location]     = "/Appointment/\(result.id)/_history/\(result.versionId)"
        return Response(status: .created, headers: headers,
                        body: returnMinimal ? .init() : ResponseBody(byteBuffer: ByteBuffer(bytes: result.jsonData)))
    }

    // PUT /Appointment?<search> — conditional update
    group.put { request, _ in
        try apptRequireFHIRContentType(request)
        let returnMinimal = (request.headers[apptPreferHeader] ?? "").contains("return=minimal")
        let qpPairs = request.uri.queryParameters.map { (key: $0.key, value: $0.value) }
        guard !qpPairs.isEmpty else {
            throw FHIRRouteError.invalidBody("PUT /Appointment requires search parameters for conditional update")
        }
        var req = request
        let bodyBuffer = try await req.collectBody(upTo: apptMaxBodyBytes)
        let appt = try apptDecodeFHIR(Appointment.self, from: bodyBuffer)
        let ifMatch = apptParseETag(request.headers[.ifMatch])

        var checkQuery = parseAppointmentQuery(from: qpPairs)
        checkQuery.count = 2; checkQuery.totalMode = .none; checkQuery.cursor = nil
        let matches = try await store.search(query: checkQuery)

        switch matches.entries.count {
        case 0:
            let result = try await store.create(appt)
            var headers = HTTPFields()
            headers[.contentType]  = apptFhirJSON
            headers[.eTag]         = "W/\"\(result.versionId)\""
            headers[.lastModified] = httpDate(result.lastUpdated)
            headers[.location]     = "/Appointment/\(result.id)/_history/\(result.versionId)"
            return Response(status: .created, headers: headers,
                            body: returnMinimal ? .init() : ResponseBody(byteBuffer: ByteBuffer(bytes: result.jsonData)))
        case 1:
            let existingId = matches.entries[0].id
            let result = try await store.update(id: existingId, appointment: appt, ifMatch: ifMatch)
            var headers = HTTPFields()
            headers[.contentType]  = apptFhirJSON
            headers[.eTag]         = "W/\"\(result.versionId)\""
            headers[.lastModified] = httpDate(result.lastUpdated)
            headers[.location]     = "/Appointment/\(result.id)/_history/\(result.versionId)"
            return Response(status: .ok, headers: headers,
                            body: returnMinimal ? .init() : ResponseBody(byteBuffer: ByteBuffer(bytes: result.jsonData)))
        default:
            throw FHIRServerError.multipleMatches(resourceType: "Appointment")
        }
    }

    // GET /Appointment/:id — read
    group.get(":id") { request, context in
        let id = context.parameters.get("id") ?? ""
        let result = try await store.read(id: id)
        if let earlyResponse = apptConditionalResponse(request: request, versionId: result.versionId, lastUpdated: result.lastUpdated) {
            return earlyResponse
        }
        let pairs = request.uri.queryParameters.map { (key: $0.key, value: $0.value) }
        let elements = parseElements(from: pairs)
        let summary  = parseSummary(from: pairs)
        var json = result.jsonData
        if let s = summary, s != .false { json = applySummary(json, mode: s, summaryFields: appointmentSummaryFields) }
        if let elems = elements { json = applyElements(json, elements: elems) }
        var headers = HTTPFields()
        headers[.contentType]  = apptFhirJSON
        headers[.eTag]         = "W/\"\(result.versionId)\""
        headers[.lastModified] = httpDate(result.lastUpdated)
        return Response(status: .ok, headers: headers,
                        body: ResponseBody(byteBuffer: ByteBuffer(bytes: json)))
    }

    // GET /Appointment/:id/_history/:vid — vread
    group.get(":id/_history/:vid") { request, context in
        let id  = context.parameters.get("id")  ?? ""
        let vid = context.parameters.get("vid").flatMap { Int64($0) } ?? 0
        let result = try await store.vread(id: id, versionId: vid)
        var headers = HTTPFields()
        headers[.contentType]  = apptFhirJSON
        headers[.eTag]         = "W/\"\(result.versionId)\""
        headers[.lastModified] = httpDate(result.lastUpdated)
        return Response(status: .ok, headers: headers,
                        body: ResponseBody(byteBuffer: ByteBuffer(bytes: result.jsonData)))
    }

    // GET /Appointment/:id/_history — instance history
    group.get(":id/_history") { request, context in
        let id = context.parameters.get("id") ?? ""
        let qp = request.uri.queryParameters
        let since: Date? = qp["_since"].flatMap { parseFHIRInstant(String($0)) }
        let count = min(qp["_count"].flatMap { Int($0) } ?? 50, apptMaxCount)
        let entries = try await store.history(id: id, since: since, count: count)
        let baseURL = serverBaseURL(request)
        let bundleData = buildHistoryBundleJSON(entries: entries, baseURL: baseURL)
        var headers = HTTPFields()
        headers[.contentType] = apptFhirJSON
        return Response(status: .ok, headers: headers,
                        body: ResponseBody(byteBuffer: ByteBuffer(bytes: bundleData)))
    }

    // GET /Appointment/_history — type history
    group.get("_history") { request, _ in
        let qp = request.uri.queryParameters
        let since: Date? = qp["_since"].flatMap { parseFHIRInstant(String($0)) }
        let count = min(qp["_count"].flatMap { Int($0) } ?? 50, 100)
        let entries = try await store.typeHistory(since: since, count: count)
        let baseURL = serverBaseURL(request)
        let bundleData = buildHistoryBundleJSON(entries: entries, baseURL: baseURL)
        var headers = HTTPFields()
        headers[.contentType] = apptFhirJSON
        return Response(status: .ok, headers: headers,
                        body: ResponseBody(byteBuffer: ByteBuffer(bytes: bundleData)))
    }

    // PUT /Appointment/:id — update
    group.put(":id") { request, context in
        try apptRequireFHIRContentType(request)
        let returnMinimal = (request.headers[apptPreferHeader] ?? "").contains("return=minimal")
        let id = context.parameters.get("id") ?? ""
        let ifMatch = apptParseETag(request.headers[.ifMatch])
        var req = request
        let bodyBuffer = try await req.collectBody(upTo: apptMaxBodyBytes)
        let appt = try apptDecodeFHIR(Appointment.self, from: bodyBuffer)
        let result = try await store.update(id: id, appointment: appt, ifMatch: ifMatch)
        var headers = HTTPFields()
        headers[.contentType]  = apptFhirJSON
        headers[.eTag]         = "W/\"\(result.versionId)\""
        headers[.lastModified] = httpDate(result.lastUpdated)
        headers[.location]     = "/Appointment/\(result.id)/_history/\(result.versionId)"
        return Response(status: .ok, headers: headers,
                        body: returnMinimal ? .init() : ResponseBody(byteBuffer: ByteBuffer(bytes: result.jsonData)))
    }

    // PATCH /Appointment/:id — JSON Patch (RFC 6902)
    group.patch(":id") { request, context in
        let id = context.parameters.get("id") ?? ""
        let ct = request.headers[.contentType] ?? ""
        guard ct.contains("application/json-patch+json") else {
            throw FHIRRouteError.invalidBody("PATCH requires Content-Type: application/json-patch+json")
        }
        let ifMatch = apptParseETag(request.headers[.ifMatch])
        var req = request
        let bodyBuffer = try await req.collectBody(upTo: apptMaxBodyBytes)
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
        let appointment: Appointment
        do { appointment = try JSONDecoder().decode(Appointment.self, from: patchedJSON) }
        catch { throw FHIRRouteError.unprocessableEntity("Patched resource is not valid FHIR: \(error.localizedDescription)") }
        let result = try await store.update(id: id, appointment: appointment, ifMatch: ifMatch)
        var headers = HTTPFields()
        headers[.contentType]  = apptFhirJSON
        headers[.eTag]         = "W/\"\(result.versionId)\""
        headers[.lastModified] = httpDate(result.lastUpdated)
        return Response(status: .ok, headers: headers,
                        body: ResponseBody(byteBuffer: ByteBuffer(bytes: result.jsonData)))
    }

    // DELETE /Appointment/:id — logical delete
    group.delete(":id") { request, context in
        let id = context.parameters.get("id") ?? ""
        let ifMatch = apptParseETag(request.headers[.ifMatch])
        let result = try await store.delete(id: id, ifMatch: ifMatch)
        var headers = HTTPFields()
        headers[.eTag]         = "W/\"\(result.versionId)\""
        headers[.lastModified] = httpDate(result.lastUpdated)
        return Response(status: .noContent, headers: headers, body: .init())
    }

    // DELETE /Appointment?<search> — conditional delete
    group.delete { request, _ in
        let qpPairs = request.uri.queryParameters.map { (key: $0.key, value: $0.value) }
        guard !qpPairs.isEmpty else {
            throw FHIRRouteError.invalidBody("DELETE /Appointment requires search parameters for conditional delete")
        }
        var checkQuery = parseAppointmentQuery(from: qpPairs)
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
            throw FHIRServerError.multipleMatches(resourceType: "Appointment")
        }
    }

    // GET /Appointment — search
    group.get { request, _ in
        let pairs = request.uri.queryParameters.map { (key: $0.key, value: $0.value) }
        if isStrictHandling(request) {
            let bad = unknownParams(in: pairs, known: knownAppointmentParams)
            if !bad.isEmpty { throw FHIRRouteError.unknownParams(bad) }
        }
        var query = parseAppointmentQuery(from: pairs)
        let elements = parseElements(from: pairs)
        let summary = parseSummary(from: pairs)
        let includes = parseIncludes(from: pairs)
        let revIncludes = parseRevIncludes(from: pairs)
        if summary == .count { query.count = 0; query.totalMode = .accurate }
        let result = try await store.search(query: query)

        let base = apptSelfURL(request)
        let baseURL = serverBaseURL(request)
        if summary == .count {
            let bundleData = buildBundleJSON(entries: [], total: result.total, selfURL: base, nextURL: nil)
            var headers = HTTPFields()
            headers[.contentType] = apptFhirJSON
            return Response(status: .ok, headers: headers,
                            body: ResponseBody(byteBuffer: ByteBuffer(bytes: bundleData)))
        }
        let nextURL = result.nextCursor.map { nextAppointmentPageURL(selfURL: base, cursor: $0, count: query.count) }
        let entries = result.entries.map { e -> (fullUrl: String, json: Data) in
            var json = e.jsonWithMeta
            if let s = summary, s != .false { json = applySummary(json, mode: s, summaryFields: appointmentSummaryFields) }
            if let elems = elements { json = applyElements(json, elements: elems) }
            return ("\(baseURL)/Appointment/\(e.id)", json)
        }
        let mainIds = result.entries.map(\.id)
        let resolver = IncludeResolver(client: store.client, logger: logger)
        async let included = resolver.resolve(includes: includes, sourceIds: mainIds)
        async let revIncluded = resolver.resolveRev(revIncludes: revIncludes, mainIds: mainIds)
        let includeEntries = includeEntryTuples(from: try await included + revIncluded, baseURL: baseURL)
        let bundleData = buildBundleJSON(entries: entries, includeEntries: includeEntries,
                                         total: result.total, selfURL: base, nextURL: nextURL)
        var headers = HTTPFields()
        headers[.contentType] = apptFhirJSON
        return Response(status: .ok, headers: headers,
                        body: ResponseBody(byteBuffer: ByteBuffer(bytes: bundleData)))
    }

    // POST /Appointment/_search — form-encoded search
    group.post("_search") { request, _ in
        let ct = request.headers[.contentType] ?? ""
        guard ct.contains("application/x-www-form-urlencoded") else {
            throw FHIRRouteError.invalidBody("Content-Type must be application/x-www-form-urlencoded for _search")
        }
        var req = request
        let bodyBuffer = try await req.collectBody(upTo: apptMaxBodyBytes)
        let urlPairs = request.uri.queryParameters.map { (key: $0.key, value: $0.value) }
        let pairs = urlPairs + parseFormPairs(from: bodyBuffer)
        if isStrictHandling(request) {
            let bad = unknownParams(in: pairs, known: knownAppointmentParams)
            if !bad.isEmpty { throw FHIRRouteError.unknownParams(bad) }
        }
        var query = parseAppointmentQuery(from: pairs)
        let elements = parseElements(from: pairs)
        let summary = parseSummary(from: pairs)
        let includes = parseIncludes(from: pairs)
        let revIncludes = parseRevIncludes(from: pairs)
        if summary == .count { query.count = 0; query.totalMode = .accurate }
        let result = try await store.search(query: query)

        let base = apptSelfURL(request)
        let baseURL = serverBaseURL(request)
        if summary == .count {
            let bundleData = buildBundleJSON(entries: [], total: result.total, selfURL: base, nextURL: nil)
            var headers = HTTPFields()
            headers[.contentType] = apptFhirJSON
            return Response(status: .ok, headers: headers,
                            body: ResponseBody(byteBuffer: ByteBuffer(bytes: bundleData)))
        }
        let nextURL = result.nextCursor.map { nextAppointmentPageURL(selfURL: base, cursor: $0, count: query.count) }
        let entries = result.entries.map { e -> (fullUrl: String, json: Data) in
            var json = e.jsonWithMeta
            if let s = summary, s != .false { json = applySummary(json, mode: s, summaryFields: appointmentSummaryFields) }
            if let elems = elements { json = applyElements(json, elements: elems) }
            return ("\(baseURL)/Appointment/\(e.id)", json)
        }
        let mainIds = result.entries.map(\.id)
        let resolver = IncludeResolver(client: store.client, logger: logger)
        async let included = resolver.resolve(includes: includes, sourceIds: mainIds)
        async let revIncluded = resolver.resolveRev(revIncludes: revIncludes, mainIds: mainIds)
        let includeEntries = includeEntryTuples(from: try await included + revIncluded, baseURL: baseURL)
        let bundleData = buildBundleJSON(entries: entries, includeEntries: includeEntries,
                                         total: result.total, selfURL: base, nextURL: nextURL)
        var headers = HTTPFields()
        headers[.contentType] = apptFhirJSON
        return Response(status: .ok, headers: headers,
                        body: ResponseBody(byteBuffer: ByteBuffer(bytes: bundleData)))
    }
}

// ── Query parser ──────────────────────────────────────────────────────────────

func parseAppointmentQuery(from pairs: some Collection<(key: Substring, value: Substring)>) -> AppointmentSearchQuery {
    func first(_ key: String) -> Substring? {
        pairs.first(where: { $0.key == key[...] })?.value
    }
    func all(_ key: String) -> [Substring] {
        pairs.filter { $0.key == key[...] }.map { $0.value }
    }

    let status           = all("status").flatMap { AppointmentSearchQuery.TokenParam.parseList(String($0)) }
    let statusNot        = all("status:not").flatMap { AppointmentSearchQuery.TokenParam.parseList(String($0)) }
    let serviceType      = all("service-type").flatMap { AppointmentSearchQuery.TokenParam.parseList(String($0)) }
    let serviceTypeNot   = all("service-type:not").flatMap { AppointmentSearchQuery.TokenParam.parseList(String($0)) }
    let appointmentType  = all("appointment-type").flatMap { AppointmentSearchQuery.TokenParam.parseList(String($0)) }
    let appointmentTypeNot = all("appointment-type:not").flatMap { AppointmentSearchQuery.TokenParam.parseList(String($0)) }
    let specialty        = all("specialty").flatMap { AppointmentSearchQuery.TokenParam.parseList(String($0)) }
    let specialtyNot     = all("specialty:not").flatMap { AppointmentSearchQuery.TokenParam.parseList(String($0)) }
    let reasonCode       = all("reason-code").flatMap { AppointmentSearchQuery.TokenParam.parseList(String($0)) }
    let reasonCodeNot    = all("reason-code:not").flatMap { AppointmentSearchQuery.TokenParam.parseList(String($0)) }
    let serviceCategory  = all("service-category").flatMap { AppointmentSearchQuery.TokenParam.parseList(String($0)) }
    let serviceCategoryNot = all("service-category:not").flatMap { AppointmentSearchQuery.TokenParam.parseList(String($0)) }
    let partStatus       = all("part-status").flatMap { AppointmentSearchQuery.TokenParam.parseList(String($0)) }
    let partStatusNot    = all("part-status:not").flatMap { AppointmentSearchQuery.TokenParam.parseList(String($0)) }

    let identifier = first("identifier").map { AppointmentSearchQuery.IdentifierParam.parseList(String($0)) } ?? []
    let date       = all("date").compactMap { AppointmentSearchQuery.DateParam.parse(String($0)) }

    let patient        = first("patient").map(String.init)
    let actor          = first("actor").map(String.init)
    let practitioner   = first("practitioner").map(String.init)
    let location       = first("location").map(String.init)
    let supportingInfo = first("supporting-info").map(String.init)

    let id          = first("_id").map {
        String($0).split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }
    } ?? []
    let lastUpdated = all("_lastUpdated").compactMap { AppointmentSearchQuery.DateParam.parse(String($0)) }
    let sort        = AppointmentSearchQuery.SortOrder.parse(first("_sort").map(String.init) ?? "-_lastUpdated")
    let count       = min(first("_count").flatMap { Int($0) } ?? 20, apptMaxCount)
    let cursor      = first("_cursor").flatMap { AppointmentSearchQuery.SearchCursor.decode(String($0)) }
    let totalMode   = AppointmentSearchQuery.TotalMode.parse(first("_total").map(String.init))

    var missing: [String: Bool] = [:]
    for p in ["status", "service-type", "appointment-type", "specialty", "reason-code",
              "service-category", "part-status", "identifier", "date", "patient",
              "actor", "practitioner", "location", "supporting-info"] {
        if let v = first("\(p):missing").map(String.init) {
            if v == "true" { missing[p] = true } else if v == "false" { missing[p] = false }
        }
    }

    let chains = parseChainParams(from: pairs)
    let has    = parseHasParams(from: pairs)

    return AppointmentSearchQuery(
        patient: patient, actor: actor, practitioner: practitioner, location: location,
        status: status, statusNot: statusNot,
        identifier: identifier, date: date,
        serviceType: serviceType, serviceTypeNot: serviceTypeNot,
        appointmentType: appointmentType, appointmentTypeNot: appointmentTypeNot,
        specialty: specialty, specialtyNot: specialtyNot,
        reasonCode: reasonCode, reasonCodeNot: reasonCodeNot,
        serviceCategory: serviceCategory, serviceCategoryNot: serviceCategoryNot,
        partStatus: partStatus, partStatusNot: partStatusNot,
        supportingInfo: supportingInfo,
        id: id, lastUpdated: lastUpdated,
        missing: missing, chains: chains, has: has,
        totalMode: totalMode, count: count, sort: sort, cursor: cursor)
}

// ── Helpers ───────────────────────────────────────────────────────────────────

private func apptConditionalResponse(request: Request, versionId: Int64, lastUpdated: Date) -> Response? {
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

private func apptRequireFHIRContentType(_ request: Request) throws {
    let ct = request.headers[.contentType] ?? ""
    guard ct.contains(apptFhirJSON) || ct.contains("application/json") else {
        throw FHIRRouteError.unsupportedMediaType
    }
}

private func apptDecodeFHIR<T: Decodable>(_ type: T.Type, from buffer: ByteBuffer) throws -> T {
    let data = Data(buffer.readableBytesView)
    do { return try JSONDecoder().decode(type, from: data) }
    catch { throw FHIRRouteError.invalidBody(error.localizedDescription) }
}

private func apptSelfURL(_ request: Request) -> String {
    let authority = request.head.authority ?? "localhost"
    return "http://\(authority)\(request.uri)"
}

func nextAppointmentPageURL(selfURL: String, cursor: AppointmentSearchQuery.SearchCursor, count: Int) -> String {
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

private func apptParseETag(_ raw: String?) -> Int64? {
    guard let raw else { return nil }
    let stripped = raw
        .trimmingCharacters(in: .whitespaces)
        .replacingOccurrences(of: "W/", with: "")
        .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
    return Int64(stripped)
}
