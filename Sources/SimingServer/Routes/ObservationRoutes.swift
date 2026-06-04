import Foundation
import Hummingbird
import Logging
import ModelsR4
import NIOCore
import SimingCore

func addObservationRoutes(
    to router: Router<BasicRequestContext>,
    store: ObservationStore,
    logger: Logger
) {
    let group = router.group("Observation")

    // POST /Observation
    group.post { request, _ in
        var req = request
        let ct = req.headers[.contentType] ?? ""
        guard ct.contains("application/fhir+json") || ct.contains("application/json") else {
            throw FHIRRouteError.unsupportedMediaType
        }
        let body = try await req.collectBody(upTo: 4 * 1024 * 1024)
        let obs  = try JSONDecoder().decode(Observation.self, from: Data(body.readableBytesView))
        let result = try await store.create(obs)

        let data = try JSONEncoder().encode(result.observation)
        var headers = HTTPFields()
        headers[.contentType] = "application/fhir+json"
        headers[.eTag]        = "W/\"\(result.versionId)\""
        headers[.location]    = "/Observation/\(result.id)/_history/\(result.versionId)"
        return Response(status: .created, headers: headers,
                        body: ResponseBody(byteBuffer: ByteBuffer(bytes: data)))
    }

    // GET /Observation/:id
    group.get(":id") { request, context in
        let id = context.parameters.get("id") ?? ""
        let result: ObservationStore.ReadResult
        do {
            result = try await store.read(id: id)
        } catch let e as FHIRServerError {
            throw e
        }
        let data = try JSONEncoder().encode(result.observation)
        var headers = HTTPFields()
        headers[.contentType] = "application/fhir+json"
        headers[.eTag]        = "W/\"\(result.versionId)\""
        return Response(status: .ok, headers: headers,
                        body: ResponseBody(byteBuffer: ByteBuffer(bytes: data)))
    }

    // GET /Observation (search)
    group.get { request, _ in
        let qp = request.uri.queryParameters

        let subject  = qp["subject"].map(String.init) ?? qp["patient"].map(String.init)
        let code     = qp["code"].map { ObservationSearchQuery.TokenParam.parse(String($0)) }
        let status   = qp["status"].map(String.init)
        let category = qp["category"].map { ObservationSearchQuery.TokenParam.parse(String($0)) }
        let dates    = qp[values: "date"].compactMap {
            ObservationSearchQuery.DateParam.parse(String($0))
        }
        let sort  = ObservationSearchQuery.SortOrder.parse(
            qp["_sort"].map(String.init) ?? "-_lastUpdated")
        let count = min(qp["_count"].flatMap { Int($0) } ?? 20, 100)
        let cursor = qp["_cursor"].flatMap {
            ObservationSearchQuery.SearchCursor.decode(String($0))
        }

        let query = ObservationSearchQuery(
            subject: subject, code: code, date: dates,
            status: status, category: category,
            count: count, sort: sort, cursor: cursor)

        let result = try await store.search(query: query)
        let bundle = buildObservationBundle(result: result, query: query,
                                            selfURL: selfURL(request))
        let data = try JSONEncoder().encode(bundle)
        var headers = HTTPFields()
        headers[.contentType] = "application/fhir+json"
        return Response(status: .ok, headers: headers,
                        body: ResponseBody(byteBuffer: ByteBuffer(bytes: data)))
    }
}

// ── Helpers ───────────────────────────────────────────────────────────────────

private func selfURL(_ request: Request) -> String {
    let authority = request.head.authority ?? "localhost"
    return "http://\(authority)\(request.uri.path)"
}

private func buildObservationBundle(
    result: ObservationStore.SearchResult,
    query: ObservationSearchQuery,
    selfURL: String
) -> ModelsR4.Bundle {
    let entries: [BundleEntry] = result.observations.map { r in
        let id = r.observation.id?.value?.string ?? ""
        return BundleEntry(
            fullUrl: FHIRPrimitive(FHIRURI(stringLiteral: "urn:uuid:\(id)")),
            resource: ResourceProxy.observation(r.observation),
            search: BundleEntrySearch(
                mode: FHIRPrimitive(.match)
            )
        )
    }

    var links: [BundleLink] = [
        BundleLink(
            relation: FHIRPrimitive(FHIRString("self")),
            url: FHIRPrimitive(FHIRURI(stringLiteral: selfURL))
        )
    ]

    if let next = result.nextCursor {
        let token = next.encode()
        let nextURL = "\(selfURL)?_cursor=\(token)"
        links.append(BundleLink(
            relation: FHIRPrimitive(FHIRString("next")),
            url: FHIRPrimitive(FHIRURI(stringLiteral: nextURL))
        ))
    }

    return ModelsR4.Bundle(
        entry: entries.isEmpty ? nil : entries,
        link: links.isEmpty ? nil : links,
        total: FHIRPrimitive(FHIRUnsignedInteger(Int32(result.total))),
        type: FHIRPrimitive(.searchset)
    )
}
