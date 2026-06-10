import Foundation
import Hummingbird
import Logging
import ModelsR4
import NIOCore
import PostgresNIO
import SimingCore

// ── FHIR R4 Transaction Bundle — POST / ──────────────────────────────────────
//
// Accepts Bundle.type = "transaction". Processes entries atomically in a single
// PostgreSQL transaction. Processing order per R4 §9.1.3:
//   1. DELETE entries
//   2. POST entries (creates, with urn:uuid temporary ID resolution)
//   3. PUT entries (updates)
//
// Temporary IDs: if an entry has fullUrl = "urn:uuid:xxx" and method POST, the
// server assigns a real UUID. All occurrences of "urn:uuid:xxx" in every
// entry's resource JSON are replaced with "ResourceType/realId" before writing.
//
// Deferred: GET/HEAD/PATCH entries, conditional create (ifNoneExist),
// absolute URL entries.

// ── File-level types ──────────────────────────────────────────────────────────

private struct TxnEntry {
    enum Method { case post, put, delete }
    let originalIndex: Int
    let method: Method
    let resourceType: String
    let id: String
    let fullUrlUrn: String?
    let ifMatch: Int64?
    var resourceData: Data?
}

private struct TxnResult {
    let originalIndex: Int
    let status: String
    let location: String?
    let etag: String?
    let lastModified: Date?
}

// ── Route registration ────────────────────────────────────────────────────────

public func addTransactionRoutes(
    to router: Router<BasicRequestContext>,
    stores: StoreContainer,
    logger: Logger
) {
    router.post("/") { request, _ in
        let ct = request.headers[.contentType] ?? ""
        guard ct.contains("application/fhir+json") || ct.contains("application/json") else {
            throw FHIRRouteError.unsupportedMediaType
        }

        var req = request
        let bodyBuffer = try await req.collectBody(upTo: 16 * 1024 * 1024)
        let bodyData = Data(bodyBuffer.readableBytesView)

        let bundle: ModelsR4.Bundle
        do {
            bundle = try JSONDecoder().decode(ModelsR4.Bundle.self, from: bodyData)
        } catch {
            throw FHIRRouteError.invalidBody("Not a valid Bundle: \(error.localizedDescription)")
        }
        guard bundle.type.value == .transaction else {
            throw FHIRRouteError.invalidBody("Bundle.type must be 'transaction'")
        }

        let entries = bundle.entry ?? []

        // ── Parse entries ─────────────────────────────────────────────────────
        var parsed: [TxnEntry] = []
        for (i, entry) in entries.enumerated() {
            guard let entryReq = entry.request,
                  let methodVal = entryReq.method.value,
                  let urlStr = entryReq.url.value?.url.absoluteString
            else {
                throw FHIRRouteError.invalidBody("Entry \(i): missing request.method or request.url")
            }

            let method: TxnEntry.Method
            switch methodVal {
            case .POST:   method = .post
            case .PUT:    method = .put
            case .DELETE: method = .delete
            default:
                throw FHIRRouteError.invalidBody(
                    "Entry \(i): unsupported method '\(methodVal.rawValue)'")
            }

            guard let (resourceType, urlId) = parseTxnUrl(urlStr) else {
                throw FHIRRouteError.invalidBody(
                    "Entry \(i): cannot parse resource type from '\(urlStr)'")
            }

            let entryId: String
            switch method {
            case .post:
                // Use client id from resource.id if present, else assign UUID.
                let clientId = entry.resource.flatMap { extractProxyId($0) }
                entryId = clientId ?? UUID().uuidString.lowercased()
            case .put, .delete:
                guard let uid = urlId else {
                    throw FHIRRouteError.invalidBody(
                        "Entry \(i): PUT/DELETE requires id in URL '\(urlStr)'")
                }
                entryId = uid
            }

            let ifMatch: Int64?
            if let im = entryReq.ifMatch?.value?.string {
                let stripped = im.trimmingCharacters(in: CharacterSet(charactersIn: "W/\""))
                ifMatch = Int64(stripped)
            } else { ifMatch = nil }

            let urn: String? = {
                guard let fu = entry.fullUrl?.value?.url.absoluteString,
                      fu.hasPrefix("urn:uuid:") else { return nil }
                return fu
            }()

            let resourceData: Data?
            if method != .delete, let proxy = entry.resource {
                resourceData = try? JSONEncoder().encode(proxy)
            } else { resourceData = nil }

            if method != .delete && resourceData == nil {
                throw FHIRRouteError.invalidBody(
                    "Entry \(i): \(methodVal.rawValue) requires a resource body")
            }

            parsed.append(TxnEntry(
                originalIndex: i, method: method, resourceType: resourceType, id: entryId,
                fullUrlUrn: urn, ifMatch: ifMatch, resourceData: resourceData))
        }

        // ── Build urn:uuid → ResourceType/realId map ──────────────────────────
        var urnMap: [String: String] = [:]
        for e in parsed where e.method == .post {
            if let urn = e.fullUrlUrn {
                urnMap[urn] = "\(e.resourceType)/\(e.id)"
            }
        }

        // ── Apply urn replacements to all resource JSON ───────────────────────
        if !urnMap.isEmpty {
            for i in parsed.indices {
                guard var jsonStr = parsed[i].resourceData
                    .flatMap({ String(data: $0, encoding: .utf8) }) else { continue }
                for (urn, ref) in urnMap {
                    jsonStr = jsonStr.replacingOccurrences(of: urn, with: ref)
                }
                parsed[i].resourceData = Data(jsonStr.utf8)
            }
        }

        // ── Sort: DELETE → POST → PUT ─────────────────────────────────────────
        let sorted = parsed.sorted {
            func rank(_ m: TxnEntry.Method) -> Int {
                switch m { case .delete: return 0; case .post: return 1; case .put: return 2 }
            }
            return rank($0.method) < rank($1.method)
        }

        // ── Execute in a single DB transaction ────────────────────────────────
        let results: [TxnResult] = try await {
            do {
                return try await stores.client.withConnection { conn in
                    _ = try await conn.query("BEGIN", logger: logger)
                    do {
                        var out: [TxnResult] = []
                        for e in sorted {
                            switch e.method {
                            case .delete:
                                _ = try await deleteResourceInner(
                                    conn: conn, resourceType: e.resourceType, id: e.id,
                                    ifMatch: e.ifMatch, logger: logger)
                                out.append(TxnResult(
                                    originalIndex: e.originalIndex,
                                    status: "204 No Content",
                                    location: nil, etag: nil, lastModified: nil))

                            case .post, .put:
                                guard let data = e.resourceData else {
                                    throw FHIRRouteError.invalidBody(
                                        "Entry \(e.originalIndex): missing resource data")
                                }
                                let (json, params): (String, SearchParams)
                                do {
                                    (json, params) = try prepareEntryForWrite(
                                        resourceType: e.resourceType, id: e.id, data: data)
                                } catch BundleTransactionError.unsupportedResourceType(let rt) {
                                    throw FHIRRouteError.invalidBody(
                                        "Unsupported resource type: \(rt)")
                                }
                                let (versionId, lastUpdated) = try await writeResourceInner(
                                    conn: conn, resourceType: e.resourceType, id: e.id,
                                    jsonString: json, ifMatch: e.ifMatch,
                                    params: params, logger: logger)
                                let isCreate = e.method == .post || versionId == 1
                                out.append(TxnResult(
                                    originalIndex: e.originalIndex,
                                    status: isCreate ? "201 Created" : "200 OK",
                                    location: "\(e.resourceType)/\(e.id)/_history/\(versionId)",
                                    etag: "W/\"\(versionId)\"",
                                    lastModified: lastUpdated))
                            }
                        }
                        _ = try await conn.query("COMMIT", logger: logger)
                        return out
                    } catch {
                        _ = try? await conn.query("ROLLBACK", logger: logger)
                        throw error
                    }
                }
            } catch let e as FHIRServerError {
                throw fhirServerErrorToRouteError(e)
            }
        }()

        // ── Build transaction-response Bundle ─────────────────────────────────
        let responseData = buildTxnResponseJSON(results)
        var headers = HTTPFields()
        headers[.contentType] = "application/fhir+json"
        return Response(
            status: .ok, headers: headers,
            body: ResponseBody(byteBuffer: ByteBuffer(bytes: responseData)))
    }
}

// ── Helpers ───────────────────────────────────────────────────────────────────

/// Parses "Patient" → ("Patient", nil) or "Patient/123" → ("Patient", "123").
/// Returns nil for absolute URLs or unparseable formats.
private func parseTxnUrl(_ url: String) -> (String, String?)? {
    guard !url.hasPrefix("http://"), !url.hasPrefix("https://") else { return nil }
    let path = url.components(separatedBy: "?").first ?? url
    let parts = path.components(separatedBy: "/").filter { !$0.isEmpty }
    guard let rt = parts.first, !rt.isEmpty else { return nil }
    return (rt, parts.count >= 2 ? parts[1] : nil)
}

/// Extracts `id` from a ResourceProxy without a type-specific decode.
private func extractProxyId(_ proxy: ResourceProxy) -> String? {
    guard let data = try? JSONEncoder().encode(proxy),
          let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let id = obj["id"] as? String else { return nil }
    return id
}

/// Maps FHIRServerError to FHIRRouteError for the transaction error response (422).
private func fhirServerErrorToRouteError(_ e: FHIRServerError) -> FHIRRouteError {
    switch e {
    case .notFound(let rt, let id):
        return .unprocessableEntity("Resource not found: \(rt)/\(id)")
    case .gone(let rt, let id):
        return .unprocessableEntity("Resource is deleted: \(rt)/\(id)")
    case .versionConflict(let id, let expected, let actual):
        let act = actual.map { "\($0)" } ?? "none"
        return .unprocessableEntity("Version conflict on \(id): expected \(expected), actual \(act)")
    case .multipleMatches(let rt):
        return .unprocessableEntity("Multiple matches for \(rt) — conditional operations not supported in transactions")
    case .unsupportedMediaType, .invalidBody:
        return .unprocessableEntity("Transaction entry failed: \(e)")
    }
}

// ── transaction-response Bundle JSON builder ──────────────────────────────────

nonisolated(unsafe) private let txnInstantFormatter: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return f
}()

private func jsonEsc(_ s: String) -> String {
    s.replacingOccurrences(of: "\\", with: "\\\\")
     .replacingOccurrences(of: "\"", with: "\\\"")
     .replacingOccurrences(of: "\n", with: "\\n")
     .replacingOccurrences(of: "\r", with: "\\r")
     .replacingOccurrences(of: "\t", with: "\\t")
}

private func buildTxnResponseJSON(_ results: [TxnResult]) -> Data {
    var entries: [String] = Array(repeating: "", count: results.count)
    for r in results {
        var resp = "{\"status\":\"\(jsonEsc(r.status))\""
        if let loc = r.location { resp += ",\"location\":\"\(jsonEsc(loc))\"" }
        if let etag = r.etag    { resp += ",\"etag\":\"\(jsonEsc(etag))\"" }
        if let lm = r.lastModified {
            resp += ",\"lastModified\":\"\(txnInstantFormatter.string(from: lm))\""
        }
        resp += "}"
        entries[r.originalIndex] = "{\"response\":\(resp)}"
    }
    let id = UUID().uuidString.lowercased()
    return Data(
        "{\"resourceType\":\"Bundle\",\"id\":\"\(id)\",\"type\":\"transaction-response\",\"entry\":[\(entries.joined(separator: ","))]}"
        .utf8)
}
