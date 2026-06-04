import Foundation
import Hummingbird
import Logging
import ModelsR4
import NIOCore
import SimingCore

private let maxCount = 100

private let fhirJSON = "application/fhir+json"
private let maxBodyBytes = 4 * 1024 * 1024  // 4 MB

func addPatientRoutes(to router: Router<BasicRequestContext>, store: PatientStore, logger: Logger) {
    let group = router.group("Patient")

    // POST /Patient — create
    group.post { request, _ in
        try requireFHIRContentType(request)
        var req = request
        let bodyBuffer = try await req.collectBody(upTo: maxBodyBytes)
        let patient = try decodeFHIR(Patient.self, from: bodyBuffer)

        let result = try await store.create(patient)
        return try fhirResponse(result.patient, status: .created, versionId: result.versionId, id: result.id)
    }

    // GET /Patient — search
    group.get { request, _ in
        let qp = request.uri.queryParameters
        let name = qp["name"].map(String.init)
        let identifier = qp["identifier"].map { PatientSearchQuery.IdentifierParam.parse(String($0)) }
        let birthdates = qp[values: "birthdate"].compactMap { PatientSearchQuery.BirthdateParam.parse(String($0)) }
        let sort = PatientSearchQuery.SortOrder.parse(qp["_sort"].map(String.init) ?? "-_lastUpdated")
        let count = min(qp["_count"].flatMap { Int($0) } ?? 20, maxCount)
        let cursor = qp["_cursor"].flatMap { PatientSearchQuery.SearchCursor.decode(String($0)) }

        let query = PatientSearchQuery(
            name: name,
            identifier: identifier,
            birthdate: birthdates,
            sort: sort,
            count: count,
            cursor: cursor
        )
        let result = try await store.search(query: query)
        let bundle = buildSearchBundle(result: result, query: query, selfURL: selfURL(request))
        let data = try JSONEncoder().encode(bundle)
        let buffer = ByteBuffer(bytes: data)
        var headers = HTTPFields()
        headers[.contentType] = fhirJSON
        return Response(status: .ok, headers: headers, body: ResponseBody(byteBuffer: buffer))
    }

    // GET /Patient/:id — read
    group.get(":id") { request, context in
        let id = context.parameters.get("id") ?? ""
        let result = try await store.read(id: id)
        return try fhirResponse(result.patient, status: .ok, versionId: result.versionId, id: id)
    }

    // PUT /Patient/:id — update (or conditional create)
    group.put(":id") { request, context in
        try requireFHIRContentType(request)
        let id = context.parameters.get("id") ?? ""
        let ifMatch = parseETag(request.headers[.ifMatch])

        var req = request
        let bodyBuffer = try await req.collectBody(upTo: maxBodyBytes)
        let patient = try decodeFHIR(Patient.self, from: bodyBuffer)

        let result = try await store.update(id: id, patient: patient, ifMatch: ifMatch)
        let status: HTTPResponse.Status = ifMatch == nil ? .ok : .ok
        return try fhirResponse(result.patient, status: status, versionId: result.versionId, id: id)
    }
}

// ── Helpers ───────────────────────────────────────────────────────────────────

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

/// Build a standard FHIR JSON response with ETag and Location headers.
private func fhirResponse<T: Encodable>(
    _ resource: T,
    status: HTTPResponse.Status,
    versionId: Int64,
    id: String
) throws -> Response {
    let data = try JSONEncoder().encode(resource)
    let buffer = ByteBuffer(bytes: data)
    var headers = HTTPFields()
    headers[.contentType] = fhirJSON
    headers[.eTag] = "W/\"\(versionId)\""
    headers[.location] = "/Patient/\(id)/_history/\(versionId)"
    return Response(status: status, headers: headers, body: ResponseBody(byteBuffer: buffer))
}

/// Reconstructs the full request URL string for Bundle.link.self.
private func selfURL(_ request: Request) -> String {
    let authority = request.head.authority ?? "localhost"
    return "http://\(authority)\(request.uri)"
}

/// Builds a FHIR searchset Bundle from a PatientStore.SearchResult.
private func buildSearchBundle(
    result: PatientStore.SearchResult,
    query: PatientSearchQuery,
    selfURL: String
) -> ModelsR4.Bundle {
    let entries: [BundleEntry] = result.patients.map { r in
        let id = r.patient.id?.value?.string ?? ""
        return BundleEntry(
            fullUrl: FHIRPrimitive(FHIRURI(stringLiteral: "/Patient/\(id)")),
            resource: .patient(r.patient),
            search: BundleEntrySearch(mode: FHIRPrimitive(.match))
        )
    }

    var links = [BundleLink(
        relation: FHIRPrimitive(FHIRString("self")),
        url: FHIRPrimitive(FHIRURI(stringLiteral: selfURL))
    )]

    if let cursor = result.nextCursor {
        let nextURL = nextPageURL(selfURL: selfURL, cursor: cursor, count: query.count)
        links.append(BundleLink(
            relation: FHIRPrimitive(FHIRString("next")),
            url: FHIRPrimitive(FHIRURI(stringLiteral: nextURL))
        ))
    }

    return ModelsR4.Bundle(
        entry: entries.isEmpty ? nil : entries,
        link: links,
        total: FHIRPrimitive(FHIRUnsignedInteger(Int32(result.total))),
        type: FHIRPrimitive(.searchset)
    )
}

/// Builds the "next" page URL by replacing/adding _cursor and preserving other params.
private func nextPageURL(selfURL: String, cursor: PatientSearchQuery.SearchCursor, count: Int) -> String {
    guard let urlComponents = URLComponents(string: selfURL) else { return selfURL }
    var components = urlComponents
    var items = (components.queryItems ?? []).filter { $0.name != "_cursor" }
    items.append(URLQueryItem(name: "_cursor", value: cursor.encode()))
    // Preserve _count from the current request
    if !items.contains(where: { $0.name == "_count" }) {
        items.append(URLQueryItem(name: "_count", value: String(count)))
    }
    components.queryItems = items
    return components.string ?? selfURL
}

/// Parse `W/"<versionId>"` or `"<versionId>"` → Int64.
private func parseETag(_ raw: String?) -> Int64? {
    guard let raw else { return nil }
    let stripped = raw
        .trimmingCharacters(in: .whitespaces)
        .replacingOccurrences(of: "W/", with: "")
        .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
    return Int64(stripped)
}

// ── Route-level errors (converted to OperationOutcome by the error handler) ──

enum FHIRRouteError: Error {
    case unsupportedMediaType
    case invalidBody(String)
}

extension FHIRRouteError: HTTPResponseError {
    var status: HTTPResponse.Status {
        switch self {
        case .unsupportedMediaType: .unsupportedMediaType
        case .invalidBody: .badRequest
        }
    }

    func response(from request: Request, context: some RequestContext) throws -> Response {
        let (severity, code, message): (IssueSeverity, IssueType, String) = switch self {
        case .unsupportedMediaType:
            (.error, .notSupported, "Content-Type must be application/fhir+json")
        case .invalidBody(let msg):
            (.error, .invalid, "Request body is not valid FHIR JSON: \(msg)")
        }
        let outcome = buildOutcome(severity: severity, code: code, diagnostics: message)
        let data = (try? JSONEncoder().encode(outcome)) ?? Data()
        var headers = HTTPFields()
        headers[.contentType] = fhirJSON
        return Response(status: status, headers: headers, body: ResponseBody(byteBuffer: ByteBuffer(bytes: data)))
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
        }
        let outcome = buildOutcome(severity: severity, code: code, diagnostics: message)
        let data = (try? JSONEncoder().encode(outcome)) ?? Data()
        var headers = HTTPFields()
        headers[.contentType] = fhirJSON
        return Response(status: status, headers: headers, body: ResponseBody(byteBuffer: ByteBuffer(bytes: data)))
    }
}
