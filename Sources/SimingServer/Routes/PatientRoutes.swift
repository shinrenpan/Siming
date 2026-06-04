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
        var headers = HTTPFields()
        headers[.contentType] = fhirJSON
        headers[.eTag]        = "W/\"\(result.versionId)\""
        headers[.location]    = "/Patient/\(result.id)/_history/\(result.versionId)"
        return Response(status: .created, headers: headers,
                        body: ResponseBody(byteBuffer: ByteBuffer(bytes: result.jsonData)))
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
            name: name, identifier: identifier, birthdate: birthdates,
            sort: sort, count: count, cursor: cursor)
        let result = try await store.search(query: query)

        let base = selfURL(request)
        let nextURL = result.nextCursor.map { nextPageURL(selfURL: base, cursor: $0, count: query.count) }
        let entries = result.entries.map { (fullUrl: "/Patient/\($0.id)", json: $0.jsonWithMeta) }
        let bundleData = buildBundleJSON(entries: entries, total: result.total,
                                         selfURL: base, nextURL: nextURL)
        var headers = HTTPFields()
        headers[.contentType] = fhirJSON
        return Response(status: .ok, headers: headers,
                        body: ResponseBody(byteBuffer: ByteBuffer(bytes: bundleData)))
    }

    // GET /Patient/:id — read
    group.get(":id") { request, context in
        let id = context.parameters.get("id") ?? ""
        let result = try await store.read(id: id)
        var headers = HTTPFields()
        headers[.contentType] = fhirJSON
        headers[.eTag]        = "W/\"\(result.versionId)\""
        return Response(status: .ok, headers: headers,
                        body: ResponseBody(byteBuffer: ByteBuffer(bytes: result.jsonData)))
    }

    // PUT /Patient/:id — update
    group.put(":id") { request, context in
        try requireFHIRContentType(request)
        let id = context.parameters.get("id") ?? ""
        let ifMatch = parseETag(request.headers[.ifMatch])
        var req = request
        let bodyBuffer = try await req.collectBody(upTo: maxBodyBytes)
        let patient = try decodeFHIR(Patient.self, from: bodyBuffer)
        let result = try await store.update(id: id, patient: patient, ifMatch: ifMatch)
        var headers = HTTPFields()
        headers[.contentType] = fhirJSON
        headers[.eTag]        = "W/\"\(result.versionId)\""
        headers[.location]    = "/Patient/\(result.id)/_history/\(result.versionId)"
        return Response(status: .ok, headers: headers,
                        body: ResponseBody(byteBuffer: ByteBuffer(bytes: result.jsonData)))
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

private func selfURL(_ request: Request) -> String {
    let authority = request.head.authority ?? "localhost"
    return "http://\(authority)\(request.uri)"
}

private func nextPageURL(selfURL: String, cursor: PatientSearchQuery.SearchCursor, count: Int) -> String {
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

// ── Route-level errors ────────────────────────────────────────────────────────

enum FHIRRouteError: Error {
    case unsupportedMediaType
    case invalidBody(String)
}

extension FHIRRouteError: HTTPResponseError {
    var status: HTTPResponse.Status {
        switch self {
        case .unsupportedMediaType: .unsupportedMediaType
        case .invalidBody:          .badRequest
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
        return Response(status: status, headers: headers,
                        body: ResponseBody(byteBuffer: ByteBuffer(bytes: data)))
    }
}
