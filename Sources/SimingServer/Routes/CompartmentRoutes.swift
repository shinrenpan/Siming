import Foundation
import Hummingbird
import Logging
import NIOCore
import SimingCore

private let maxCount = 100
private let fhirJSON = "application/fhir+json"

/// GET /Patient/:patientId/Observation — Patient compartment search.
/// Forces subject=Patient/:patientId; delegates to ObservationStore.search().
func addCompartmentRoutes(
    to router: Router<BasicRequestContext>,
    observationStore: ObservationStore,
    logger: Logger
) {
    let group = router.group("Patient")

    group.get(":patientId/Observation") { request, context in
        let patientId = context.parameters.get("patientId") ?? ""
        let qp = request.uri.queryParameters

        let query = ObservationSearchQuery(
            subject:     "Patient/\(patientId)",
            code:        qp["code"].map     { ObservationSearchQuery.TokenParam.parseList(String($0)) } ?? [],
            date:        qp[values: "date"].compactMap { ObservationSearchQuery.DateParam.parse(String($0)) },
            status:      qp["status"].map   { String($0).split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) } } ?? [],
            category:    qp["category"].map { ObservationSearchQuery.TokenParam.parseList(String($0)) } ?? [],
            id:          qp["_id"].map { String($0).split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) } } ?? [],
            lastUpdated: qp[values: "_lastUpdated"].compactMap { ObservationSearchQuery.DateParam.parse(String($0)) },
            count:       min(qp["_count"].flatMap { Int($0) } ?? 20, maxCount),
            sort:        ObservationSearchQuery.SortOrder.parse(qp["_sort"].map(String.init) ?? "-_lastUpdated"),
            cursor:      qp["_cursor"].flatMap { ObservationSearchQuery.SearchCursor.decode(String($0)) }
        )

        let result = try await observationStore.search(query: query)

        let base = selfURL(request)
        let nextURL = result.nextCursor.map { nextPageURL(selfURL: base, cursor: $0, count: query.count) }
        let entries = result.entries.map { (fullUrl: "/Observation/\($0.id)", json: $0.jsonWithMeta) }
        let bundleData = buildBundleJSON(entries: entries, total: result.total,
                                         selfURL: base, nextURL: nextURL)
        var headers = HTTPFields()
        headers[.contentType] = fhirJSON
        return Response(status: .ok, headers: headers,
                        body: ResponseBody(byteBuffer: ByteBuffer(bytes: bundleData)))
    }
}

// ── Helpers ───────────────────────────────────────────────────────────────────

private func selfURL(_ request: Request) -> String {
    let authority = request.head.authority ?? "localhost"
    return "http://\(authority)\(request.uri)"
}

private func nextPageURL(selfURL: String, cursor: ObservationSearchQuery.SearchCursor, count: Int) -> String {
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
