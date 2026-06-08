import Foundation
import Logging
import ModelsR4
import PostgresNIO

public struct LocationStore: Sendable {
    public let client: PostgresClient
    public let logger: Logger

    public init(client: PostgresClient, logger: Logger) {
        self.client = client
        self.logger = logger
    }

    // ── Result types ──────────────────────────────────────────────────────────

    public struct WriteResult: Sendable {
        public let id: String
        public let versionId: Int64
        public let lastUpdated: Date
        public let jsonData: Data
    }

    public struct ReadResult: Sendable {
        public let jsonData: Data
        public let versionId: Int64
        public let lastUpdated: Date
    }

    public struct SearchResult: Sendable {
        public let entries: [RawEntry]
        public let total: Int?
        public let nextCursor: LocationSearchQuery.SearchCursor?
    }

    public struct DeleteResult: Sendable {
        public let versionId: Int64
        public let lastUpdated: Date
    }

    // ── Public API ────────────────────────────────────────────────────────────

    public func create(_ location: Location) async throws -> WriteResult {
        let id = UUID().uuidString.lowercased()
        return try await write(id: id, location: location, ifMatch: nil)
    }

    public func update(id: String, location: Location, ifMatch: Int64?) async throws -> WriteResult {
        return try await write(id: id, location: location, ifMatch: ifMatch)
    }

    @discardableResult
    public func delete(id: String, ifMatch: Int64?) async throws -> DeleteResult {
        try await client.withConnection { conn in
            let (versionId, lastUpdated, _) = try await deleteResource(
                conn: conn, resourceType: "Location", id: id, ifMatch: ifMatch, logger: logger)
            return DeleteResult(versionId: versionId, lastUpdated: lastUpdated)
        }
    }

    public func vread(id: String, versionId: Int64) async throws -> ReadResult {
        try await client.withConnection { conn in
            let rows = try await conn.query(
                """
                SELECT version_id, last_updated, content, deleted
                FROM resources
                WHERE resource_type = 'Location' AND id = \(id) AND version_id = \(versionId)
                """, logger: logger)
            for try await (vid, lastUpdated, content, deleted) in
                rows.decode((Int64, Date, String, Bool).self, context: .default)
            {
                if deleted { throw FHIRServerError.gone(resourceType: "Location", id: id) }
                let jsonData = injectMeta(into: content, versionId: vid, lastUpdated: lastUpdated)
                return ReadResult(jsonData: jsonData, versionId: vid, lastUpdated: lastUpdated)
            }
            throw FHIRServerError.notFound(resourceType: "Location", id: id)
        }
    }

    public func history(id: String, since: Date? = nil, count: Int = 50) async throws -> [HistoryRawEntry] {
        try await client.withConnection { conn in
            let rows: PostgresRowSequence
            if let since {
                rows = try await conn.query(
                    """
                    SELECT version_id, last_updated, content, deleted
                    FROM resources
                    WHERE resource_type = 'Location' AND id = \(id) AND last_updated >= \(since)
                    ORDER BY version_id DESC
                    LIMIT \(Int64(count))
                    """, logger: logger)
            } else {
                rows = try await conn.query(
                    """
                    SELECT version_id, last_updated, content, deleted
                    FROM resources
                    WHERE resource_type = 'Location' AND id = \(id)
                    ORDER BY version_id DESC
                    LIMIT \(Int64(count))
                    """, logger: logger)
            }
            var entries: [HistoryRawEntry] = []
            for try await (vid, lastUpdated, content, deleted) in
                rows.decode((Int64, Date, String, Bool).self, context: .default)
            {
                let jsonData: Data? = deleted ? nil : injectMeta(into: content, versionId: vid, lastUpdated: lastUpdated)
                entries.append(HistoryRawEntry(resourceType: "Location", id: id, versionId: vid, lastUpdated: lastUpdated, jsonData: jsonData, deleted: deleted))
            }
            if entries.isEmpty {
                if since != nil {
                    let existRows = try await conn.query(
                        """
                        SELECT 1 FROM resources WHERE resource_type = 'Location' AND id = \(id) LIMIT 1
                        """, logger: logger)
                    var exists = false
                    for try await _ in existRows { exists = true }
                    if !exists { throw FHIRServerError.notFound(resourceType: "Location", id: id) }
                } else {
                    throw FHIRServerError.notFound(resourceType: "Location", id: id)
                }
            }
            return entries
        }
    }

    public func typeHistory(since: Date?, count: Int) async throws -> [HistoryRawEntry] {
        try await client.withConnection { conn in
            let rows: PostgresRowSequence
            if let since {
                rows = try await conn.query(
                    """
                    SELECT id, version_id, last_updated, content, deleted
                    FROM resources
                    WHERE resource_type = 'Location' AND last_updated >= \(since)
                    ORDER BY last_updated DESC, id, version_id DESC
                    LIMIT \(Int64(count))
                    """, logger: logger)
            } else {
                rows = try await conn.query(
                    """
                    SELECT id, version_id, last_updated, content, deleted
                    FROM resources
                    WHERE resource_type = 'Location'
                    ORDER BY last_updated DESC, id, version_id DESC
                    LIMIT \(Int64(count))
                    """, logger: logger)
            }
            var entries: [HistoryRawEntry] = []
            for try await (rid, vid, lastUpdated, content, deleted) in
                rows.decode((String, Int64, Date, String, Bool).self, context: .default)
            {
                let jsonData: Data? = deleted ? nil : injectMeta(into: content, versionId: vid, lastUpdated: lastUpdated)
                entries.append(HistoryRawEntry(resourceType: "Location", id: rid, versionId: vid, lastUpdated: lastUpdated, jsonData: jsonData, deleted: deleted))
            }
            return entries
        }
    }

    public func read(id: String) async throws -> ReadResult {
        try await client.withConnection { conn in
            let rows = try await conn.query(
                """
                SELECT version_id, last_updated, content, deleted
                FROM resources
                WHERE resource_type = 'Location' AND id = \(id)
                ORDER BY version_id DESC
                LIMIT 1
                """, logger: logger)
            var found: ReadResult? = nil
            for try await (versionId, lastUpdated, content, deleted) in
                rows.decode((Int64, Date, String, Bool).self, context: .default)
            {
                if deleted { throw FHIRServerError.gone(resourceType: "Location", id: id) }
                let jsonData = injectMeta(into: content, versionId: versionId, lastUpdated: lastUpdated)
                found = ReadResult(jsonData: jsonData, versionId: versionId, lastUpdated: lastUpdated)
            }
            guard let result = found else {
                throw FHIRServerError.notFound(resourceType: "Location", id: id)
            }
            return result
        }
    }

    public func search(query: LocationSearchQuery) async throws -> SearchResult {
        if query.count == 0 {
            if query.totalMode == .none {
                return SearchResult(entries: [], total: nil, nextCursor: nil)
            }
            return try await client.withConnection { conn in
                let (countSQL, countBinds) = try buildCountSQL(query: query)
                let rows = try await conn.query(PostgresQuery(unsafeSQL: countSQL, binds: countBinds), logger: logger)
                var total = 0
                for try await (n) in rows.decode(Int64.self, context: .default) { total = Int(n) }
                return SearchResult(entries: [], total: total, nextCursor: nil)
            }
        }
        return try await client.withConnection { conn in
            let (sql, binds) = try buildSearchSQL(query: query)
            let rows = try await conn.query(PostgresQuery(unsafeSQL: sql, binds: binds), logger: logger)

            var results: [RawEntry] = []
            var sortValTexts: [String] = []
            var rawTotal: Int64 = 0
            for try await (id, versionId, lastUpdated, content, rowTotal, sortValText) in
                rows.decode((String, Int64, Date, String, Int64, String).self, context: .default)
            {
                rawTotal = rowTotal
                let jsonData = injectMeta(into: content, versionId: versionId, lastUpdated: lastUpdated)
                results.append(RawEntry(id: id, versionId: versionId, lastUpdated: lastUpdated, jsonWithMeta: jsonData))
                sortValTexts.append(sortValText)
            }

            let pageSize = min(query.count, results.count)
            let hasNext  = results.count > query.count
            let page     = Array(results.prefix(pageSize))
            let pageSortVals = Array(sortValTexts.prefix(pageSize))

            let nextCursor: LocationSearchQuery.SearchCursor?
            if hasNext, let lastEntry = page.last, let lastSortVal = pageSortVals.last {
                nextCursor = LocationSearchQuery.SearchCursor(
                    sortValue: lastSortVal, id: lastEntry.id, descending: query.sort.isDescending)
            } else {
                nextCursor = nil
            }

            let total: Int?
            switch query.totalMode {
            case .accurate: total = Int(rawTotal)
            case .estimate: total = hasNext ? nil : page.count
            case .none:     total = nil
            }
            return SearchResult(entries: page, total: total, nextCursor: nextCursor)
        }
    }

    // ── Private ───────────────────────────────────────────────────────────────

    private func write(id: String, location: Location, ifMatch: Int64?) async throws -> WriteResult {
        try validate(location)

        var loc = location
        loc.id   = FHIRPrimitive(FHIRString(id))
        loc.meta = nil

        let jsonData   = try JSONEncoder().encode(loc)
        let jsonString = String(data: jsonData, encoding: .utf8)!
        let searchParams = extractLocationSearchParams(loc)

        return try await client.withConnection { conn in
            let (versionId, lastUpdated) = try await writeResource(
                conn: conn, resourceType: "Location", id: id,
                jsonString: jsonString, ifMatch: ifMatch, params: searchParams, logger: logger)
            let responseData = injectMeta(into: jsonString, versionId: versionId, lastUpdated: lastUpdated)
            return WriteResult(id: id, versionId: versionId, lastUpdated: lastUpdated, jsonData: responseData)
        }
    }

    private func validate(_ loc: Location) throws {}

    private func stringBindValue(_ param: LocationSearchQuery.StringParam) -> String {
        switch param.modifier {
        case .startsWith:      return "\(param.value)%"
        case .contains, .text: return "%\(param.value)%"
        case .exact:           return param.value
        }
    }

    private func stringFilterCond(_ param: LocationSearchQuery.StringParam, _ bp: String) -> String {
        switch param.modifier {
        case .exact:           return "value = \(bp)"
        case .contains, .text: return "value ILIKE \(bp)"
        case .startsWith:      return "lower(value) LIKE lower(\(bp))"
        }
    }

    private func buildSearchSQL(query: LocationSearchQuery) throws -> (String, PostgresBindings) {
        var binds = PostgresBindings()
        var n = 0
        func bind(_ val: some PostgresDynamicTypeEncodable) -> String {
            n += 1; binds.append(val); return "$\(n)"
        }

        var filterCTEs: [(name: String, sql: String)] = []

        // String filters
        let stringFilters: [(String, String, LocationSearchQuery.StringParam?)] = [
            ("f_name",    "name",               query.name),
            ("f_addr",    "address",             query.address),
            ("f_city",    "address-city",        query.addressCity),
            ("f_state",   "address-state",       query.addressState),
            ("f_postal",  "address-postalcode",  query.addressPostalCode),
            ("f_country", "address-country",     query.addressCountry),
        ]
        for (cteName, paramName, param) in stringFilters {
            guard let param else { continue }
            let bp = bind(stringBindValue(param))
            filterCTEs.append((cteName, "SELECT DISTINCT resource_id FROM idx_string WHERE resource_type = 'Location' AND param_name = '\(paramName)' AND \(stringFilterCond(param, bp))"))
        }

        // token OR CTE builder (inline closure to work around 'some' parameter restriction)
        func tokenORCTE(name: String, paramName: String, tokens: [LocationSearchQuery.TokenParam]) -> (String, String) {
            var orClauses: [String] = []
            for tok in tokens {
                if tok.code.isEmpty, let sys = tok.system {
                    orClauses.append("system = \(bind(sys))")
                } else {
                    let codeP = bind(tok.code); var sysCond = ""
                    if let sys = tok.system { sysCond = " AND system = \(bind(sys))" }
                    orClauses.append("(code = \(codeP)\(sysCond))")
                }
            }
            return (name, "SELECT DISTINCT resource_id FROM idx_token WHERE resource_type = 'Location' AND param_name = '\(paramName)' AND (\(orClauses.joined(separator: " OR ")))")
        }

        func tokenNotCondition(paramName: String, tokens: [LocationSearchQuery.TokenParam]) -> String {
            var orClauses: [String] = []
            for tok in tokens {
                if tok.code.isEmpty, let sys = tok.system {
                    orClauses.append("system = \(bind(sys))")
                } else {
                    let codeP = bind(tok.code); var sysCond = ""
                    if let sys = tok.system { sysCond = " AND system = \(bind(sys))" }
                    orClauses.append("(code = \(codeP)\(sysCond))")
                }
            }
            return "r.id NOT IN (SELECT resource_id FROM idx_token WHERE resource_type = 'Location' AND param_name = '\(paramName)' AND (\(orClauses.joined(separator: " OR "))))"
        }

        // status — token OR
        if !query.status.isEmpty {
            filterCTEs.append(tokenORCTE(name: "f_status", paramName: "status", tokens: query.status))
        }

        // type — token OR
        if !query.type.isEmpty {
            filterCTEs.append(tokenORCTE(name: "f_type", paramName: "type", tokens: query.type))
        }

        // operational-status — token OR
        if !query.operationalStatus.isEmpty {
            filterCTEs.append(tokenORCTE(name: "f_opstatus", paramName: "operational-status", tokens: query.operationalStatus))
        }

        // identifier — token OR
        if !query.identifier.isEmpty {
            var orClauses: [String] = []
            for ident in query.identifier {
                if ident.code.isEmpty {
                    if case .specific(let sys?) = ident.systemFilter { orClauses.append("system = \(bind(sys))") }
                } else {
                    let codeP = bind(ident.code); var sysCond = ""
                    switch ident.systemFilter {
                    case .any: break
                    case .specific(nil): sysCond = " AND system IS NULL"
                    case .specific(let sys?): sysCond = " AND system = \(bind(sys))"
                    }
                    orClauses.append("(code = \(codeP)\(sysCond))")
                }
            }
            if !orClauses.isEmpty {
                filterCTEs.append(("f_ident", "SELECT DISTINCT resource_id FROM idx_token WHERE resource_type = 'Location' AND param_name = 'identifier' AND (\(orClauses.joined(separator: " OR ")))"))
            }
        }

        // organization — reference
        if let org = query.organization {
            let parts = org.split(separator: "/")
            if parts.count == 2 {
                let refTypeP = bind(String(parts[0])); let refIdP = bind(String(parts[1]))
                filterCTEs.append(("f_org",
                    "SELECT DISTINCT resource_id FROM idx_reference WHERE resource_type = 'Location' AND param_name = 'organization' AND ref_type = \(refTypeP) AND ref_id = \(refIdP)"))
            } else {
                let refIdP = bind(org)
                filterCTEs.append(("f_org",
                    "SELECT DISTINCT resource_id FROM idx_reference WHERE resource_type = 'Location' AND param_name = 'organization' AND ref_id = \(refIdP)"))
            }
        }

        // partof — reference
        if let partof = query.partof {
            let parts = partof.split(separator: "/")
            if parts.count == 2 {
                let refTypeP = bind(String(parts[0])); let refIdP = bind(String(parts[1]))
                filterCTEs.append(("f_partof",
                    "SELECT DISTINCT resource_id FROM idx_reference WHERE resource_type = 'Location' AND param_name = 'partof' AND ref_type = \(refTypeP) AND ref_id = \(refIdP)"))
            } else {
                let refIdP = bind(partof)
                filterCTEs.append(("f_partof",
                    "SELECT DISTINCT resource_id FROM idx_reference WHERE resource_type = 'Location' AND param_name = 'partof' AND ref_id = \(refIdP)"))
            }
        }

        // endpoint — reference
        if let endpoint = query.endpoint {
            let parts = endpoint.split(separator: "/")
            if parts.count == 2 {
                let refTypeP = bind(String(parts[0])); let refIdP = bind(String(parts[1]))
                filterCTEs.append(("f_endpoint",
                    "SELECT DISTINCT resource_id FROM idx_reference WHERE resource_type = 'Location' AND param_name = 'endpoint' AND ref_type = \(refTypeP) AND ref_id = \(refIdP)"))
            } else {
                let refIdP = bind(endpoint)
                filterCTEs.append(("f_endpoint",
                    "SELECT DISTINCT resource_id FROM idx_reference WHERE resource_type = 'Location' AND param_name = 'endpoint' AND ref_id = \(refIdP)"))
            }
        }

        // ── WHERE conditions ──────────────────────────────────────────────────

        var whereConditions = ["r.resource_type = 'Location'", "r.deleted = false"]

        if !query.id.isEmpty {
            let phs = query.id.map { bind($0) }.joined(separator: ", ")
            whereConditions.append("r.id IN (\(phs))")
        }
        for lu in query.lastUpdated {
            let startP = bind(lu.dateStart); let endP = bind(lu.dateEnd)
            let cond: String
            switch lu.prefix {
            case .eq: cond = "r.last_updated >= \(startP) AND r.last_updated <= \(endP)"
            case .ne: cond = "r.last_updated < \(startP) OR r.last_updated > \(endP)"
            case .lt: cond = "r.last_updated < \(startP)"
            case .le: cond = "r.last_updated <= \(endP)"
            case .gt: cond = "r.last_updated > \(endP)"
            case .ge: cond = "r.last_updated >= \(startP)"
            case .sa: cond = "r.last_updated > \(endP)"
            case .eb: cond = "r.last_updated < \(startP)"
            }
            whereConditions.append(cond)
        }

        // :not modifiers
        if !query.statusNot.isEmpty {
            whereConditions.append(tokenNotCondition(paramName: "status", tokens: query.statusNot))
        }
        if !query.typeNot.isEmpty {
            whereConditions.append(tokenNotCondition(paramName: "type", tokens: query.typeNot))
        }

        // :missing
        for paramName in query.missing.keys.sorted() {
            if let sub = locationMissingSubquery(param: paramName) {
                if query.missing[paramName] == true {
                    whereConditions.append("r.id NOT IN (\(sub))")
                } else {
                    whereConditions.append("r.id IN (\(sub))")
                }
            }
        }

        // Chained search
        let cBindStr: (String) -> String = { bind($0) }
        let cBindDate: (Date) -> String = { bind($0) }
        for (i, chain) in query.chains.enumerated() {
            if let (name, sql) = chainFilterCTE(
                index: filterCTEs.count + i, sourceType: "Location",
                chain: chain, bindStr: cBindStr, bindDate: cBindDate
            ) {
                filterCTEs.append((name, sql))
            }
        }

        // _has
        let hBindStr: (String) -> String = { bind($0) }
        let hBindDate: (Date) -> String = { bind($0) }
        for (i, hp) in query.has.enumerated() {
            if let (name, sql) = hasFilterCTE(
                index: i, mainType: "Location",
                param: hp, bindStr: hBindStr, bindDate: hBindDate
            ) {
                filterCTEs.append((name, sql))
            }
        }

        var fromLines = ["FROM resources r"]
        for cte in filterCTEs { fromLines.append("JOIN \(cte.name) ON \(cte.name).resource_id = r.id") }
        fromLines.append("WHERE " + whereConditions.joined(separator: " AND "))
        fromLines.append("ORDER BY r.id, r.version_id DESC")

        let idsInner = (["SELECT DISTINCT ON (r.id) r.id, r.version_id, r.last_updated"]
            + fromLines).joined(separator: "\n      ")

        let sortIsDescending = query.sort.isDescending
        let orderDir = sortIsDescending ? "DESC" : "ASC"

        var sortKeysCTE: (name: String, sql: String)? = nil
        var cursorCondSQL = ""
        var finalSortValSQL = ""
        var sortKind = 0

        switch query.sort {
        case .nameAscending, .nameDescending:
            sortKeysCTE = ("sort_keys",
                "SELECT DISTINCT ON (resource_id) resource_id, value AS sv " +
                "FROM idx_string WHERE resource_type = 'Location' AND param_name = 'name' " +
                "ORDER BY resource_id, value ASC")
            if let cursor = query.cursor {
                let svP = bind(cursor.sortValue); let idP = bind(cursor.id)
                let op = sortIsDescending ? "<" : ">"
                cursorCondSQL = "(sort_val IS NOT NULL AND sort_val \(op) \(svP)) OR " +
                    "(sort_val IS NOT NULL AND sort_val = \(svP) AND id > \(idP))"
            }
            finalSortValSQL = "COALESCE(p.sort_val, '')"
            sortKind = 1

        case .statusAscending, .statusDescending:
            sortKeysCTE = ("sort_keys",
                "SELECT DISTINCT ON (resource_id) resource_id, code AS sv " +
                "FROM idx_token WHERE resource_type = 'Location' AND param_name = 'status' " +
                "ORDER BY resource_id, code ASC")
            if let cursor = query.cursor {
                let codeP = bind(cursor.sortValue)
                let idP = bind(cursor.id)
                let op = sortIsDescending ? "<" : ">"
                cursorCondSQL = "(sort_val IS NOT NULL AND sort_val \(op) \(codeP)) OR " +
                    "(sort_val IS NOT NULL AND sort_val = \(codeP) AND id > \(idP))"
            }
            finalSortValSQL = "COALESCE(p.sort_val, '')"
            sortKind = 1

                case ._idAscending, ._idDescending:
            if let cursor = query.cursor {
                let idP = bind(cursor.sortValue); let op = sortIsDescending ? "<" : ">"
                cursorCondSQL = "i.id \(op) \(idP)"
            }
            finalSortValSQL = "p.id"
            sortKind = 2

        default:
            if let cursor = query.cursor, let ts = Double(cursor.sortValue) {
                let tsP = bind(Date(timeIntervalSince1970: ts)); let idP = bind(cursor.id)
                let op = sortIsDescending ? "<" : ">"
                cursorCondSQL = "(i.last_updated \(op) \(tsP) OR (i.last_updated = \(tsP) AND i.id > \(idP)))"
            }
            finalSortValSQL = "CAST(EXTRACT(EPOCH FROM p.last_updated) AS text)"
        }

        let limitP = bind(Int64(query.count + 1))

        let pagedInner: String
        switch sortKind {
        case 1:
            let inner = "SELECT i.id, i.version_id, i.last_updated, sk.sv AS sort_val " +
                "FROM ids i LEFT JOIN sort_keys sk ON sk.resource_id = i.id"
            let whereLine = cursorCondSQL.isEmpty ? "" : "\n    WHERE \(cursorCondSQL)"
            pagedInner = "SELECT id, version_id, last_updated, sort_val FROM (\n      \(inner)\n    ) sub" +
                "\(whereLine)\n    ORDER BY sort_val \(orderDir) NULLS LAST, id ASC\n    LIMIT \(limitP)"
        case 2:
            let whereLine = cursorCondSQL.isEmpty ? "" : "\n    WHERE \(cursorCondSQL)"
            pagedInner = "SELECT i.id, i.version_id, i.last_updated\n    FROM ids i" +
                "\(whereLine)\n    ORDER BY i.id \(orderDir)\n    LIMIT \(limitP)"
        default:
            let whereLine = cursorCondSQL.isEmpty ? "" : "\n    WHERE \(cursorCondSQL)"
            pagedInner = "SELECT i.id, i.version_id, i.last_updated\n    FROM ids i" +
                "\(whereLine)\n    ORDER BY i.last_updated \(orderDir), i.id ASC\n    LIMIT \(limitP)"
        }

        var cteParts = filterCTEs.map { "\($0.name) AS (\n    \($0.sql)\n  )" }
        cteParts.append("ids AS MATERIALIZED (\n    \(idsInner)\n  )")
        let skipTotal = query.totalMode == .none || query.totalMode == .estimate
        if !skipTotal { cteParts.append("total_count AS (\n    SELECT COUNT(*) AS n FROM ids\n  )") }
        if let skCTE = sortKeysCTE { cteParts.append("\(skCTE.name) AS (\n    \(skCTE.sql)\n  )") }
        cteParts.append("paged AS (\n    \(pagedInner)\n  )")
        let withClause = "WITH " + cteParts.joined(separator: ",\n  ")

        let totalExpr = skipTotal ? "CAST(0 AS bigint)" : "t.n"
        let fromClause = skipTotal
            ? "FROM paged p JOIN resources r ON r.resource_type = 'Location' AND r.id = p.id AND r.version_id = p.version_id"
            : "FROM paged p CROSS JOIN total_count t JOIN resources r ON r.resource_type = 'Location' AND r.id = p.id AND r.version_id = p.version_id"

        let sql = "\(withClause)\nSELECT p.id, p.version_id, p.last_updated, r.content, \(totalExpr), \(finalSortValSQL) AS sort_val_text\n\(fromClause)\nORDER BY sort_val_text \(orderDir) NULLS LAST, p.id ASC"
        return (sql, binds)
    }

    private func buildCountSQL(query: LocationSearchQuery) throws -> (String, PostgresBindings) {
        var binds = PostgresBindings()
        var n = 0
        func bind(_ val: some PostgresDynamicTypeEncodable) -> String {
            n += 1; binds.append(val); return "$\(n)"
        }

        var filterCTEs: [(name: String, sql: String)] = []

        let stringFilters: [(String, String, LocationSearchQuery.StringParam?)] = [
            ("f_name",    "name",               query.name),
            ("f_addr",    "address",             query.address),
            ("f_city",    "address-city",        query.addressCity),
            ("f_state",   "address-state",       query.addressState),
            ("f_postal",  "address-postalcode",  query.addressPostalCode),
            ("f_country", "address-country",     query.addressCountry),
        ]
        for (cteName, paramName, param) in stringFilters {
            guard let param else { continue }
            let bp = bind(stringBindValue(param))
            filterCTEs.append((cteName, "SELECT DISTINCT resource_id FROM idx_string WHERE resource_type = 'Location' AND param_name = '\(paramName)' AND \(stringFilterCond(param, bp))"))
        }

        func countTokenORCTE(name: String, paramName: String, tokens: [LocationSearchQuery.TokenParam]) -> (String, String) {
            var orClauses: [String] = []
            for tok in tokens {
                if tok.code.isEmpty, let sys = tok.system {
                    orClauses.append("system = \(bind(sys))")
                } else {
                    let codeP = bind(tok.code); var sysCond = ""
                    if let sys = tok.system { sysCond = " AND system = \(bind(sys))" }
                    orClauses.append("(code = \(codeP)\(sysCond))")
                }
            }
            return (name, "SELECT DISTINCT resource_id FROM idx_token WHERE resource_type = 'Location' AND param_name = '\(paramName)' AND (\(orClauses.joined(separator: " OR ")))")
        }

        if !query.status.isEmpty {
            filterCTEs.append(countTokenORCTE(name: "f_status", paramName: "status", tokens: query.status))
        }
        if !query.type.isEmpty {
            filterCTEs.append(countTokenORCTE(name: "f_type", paramName: "type", tokens: query.type))
        }
        if !query.operationalStatus.isEmpty {
            filterCTEs.append(countTokenORCTE(name: "f_opstatus", paramName: "operational-status", tokens: query.operationalStatus))
        }

        if !query.identifier.isEmpty {
            var orClauses: [String] = []
            for ident in query.identifier {
                if ident.code.isEmpty {
                    if case .specific(let sys?) = ident.systemFilter { orClauses.append("system = \(bind(sys))") }
                } else {
                    let codeP = bind(ident.code); var sysCond = ""
                    switch ident.systemFilter {
                    case .any: break
                    case .specific(nil): sysCond = " AND system IS NULL"
                    case .specific(let sys?): sysCond = " AND system = \(bind(sys))"
                    }
                    orClauses.append("(code = \(codeP)\(sysCond))")
                }
            }
            if !orClauses.isEmpty {
                filterCTEs.append(("f_ident", "SELECT DISTINCT resource_id FROM idx_token WHERE resource_type = 'Location' AND param_name = 'identifier' AND (\(orClauses.joined(separator: " OR ")))"))
            }
        }

        if let org = query.organization {
            let parts = org.split(separator: "/")
            if parts.count == 2 {
                let refTypeP = bind(String(parts[0])); let refIdP = bind(String(parts[1]))
                filterCTEs.append(("f_org", "SELECT DISTINCT resource_id FROM idx_reference WHERE resource_type = 'Location' AND param_name = 'organization' AND ref_type = \(refTypeP) AND ref_id = \(refIdP)"))
            } else {
                let refIdP = bind(org)
                filterCTEs.append(("f_org", "SELECT DISTINCT resource_id FROM idx_reference WHERE resource_type = 'Location' AND param_name = 'organization' AND ref_id = \(refIdP)"))
            }
        }

        if let partof = query.partof {
            let parts = partof.split(separator: "/")
            if parts.count == 2 {
                let refTypeP = bind(String(parts[0])); let refIdP = bind(String(parts[1]))
                filterCTEs.append(("f_partof", "SELECT DISTINCT resource_id FROM idx_reference WHERE resource_type = 'Location' AND param_name = 'partof' AND ref_type = \(refTypeP) AND ref_id = \(refIdP)"))
            } else {
                let refIdP = bind(partof)
                filterCTEs.append(("f_partof", "SELECT DISTINCT resource_id FROM idx_reference WHERE resource_type = 'Location' AND param_name = 'partof' AND ref_id = \(refIdP)"))
            }
        }

        if let endpoint = query.endpoint {
            let parts = endpoint.split(separator: "/")
            if parts.count == 2 {
                let refTypeP = bind(String(parts[0])); let refIdP = bind(String(parts[1]))
                filterCTEs.append(("f_endpoint", "SELECT DISTINCT resource_id FROM idx_reference WHERE resource_type = 'Location' AND param_name = 'endpoint' AND ref_type = \(refTypeP) AND ref_id = \(refIdP)"))
            } else {
                let refIdP = bind(endpoint)
                filterCTEs.append(("f_endpoint", "SELECT DISTINCT resource_id FROM idx_reference WHERE resource_type = 'Location' AND param_name = 'endpoint' AND ref_id = \(refIdP)"))
            }
        }

        var whereConditions = ["r.resource_type = 'Location'", "r.deleted = false"]
        if !query.id.isEmpty {
            let phs = query.id.map { bind($0) }.joined(separator: ", ")
            whereConditions.append("r.id IN (\(phs))")
        }

        let cBindStr: (String) -> String = { bind($0) }
        let cBindDate: (Date) -> String = { bind($0) }
        for (i, chain) in query.chains.enumerated() {
            if let (name, sql) = chainFilterCTE(
                index: filterCTEs.count + i, sourceType: "Location",
                chain: chain, bindStr: cBindStr, bindDate: cBindDate
            ) {
                filterCTEs.append((name, sql))
            }
        }

        let hBindStr: (String) -> String = { bind($0) }
        let hBindDate: (Date) -> String = { bind($0) }
        for (i, hp) in query.has.enumerated() {
            if let (name, sql) = hasFilterCTE(
                index: i, mainType: "Location",
                param: hp, bindStr: hBindStr, bindDate: hBindDate
            ) {
                filterCTEs.append((name, sql))
            }
        }

        var fromLines = ["FROM resources r"]
        for cte in filterCTEs { fromLines.append("JOIN \(cte.name) ON \(cte.name).resource_id = r.id") }
        fromLines.append("WHERE " + whereConditions.joined(separator: " AND "))
        fromLines.append("ORDER BY r.id, r.version_id DESC")
        let idsInner = (["SELECT DISTINCT ON (r.id) r.id"]
            + fromLines).joined(separator: "\n      ")

        var cteParts = filterCTEs.map { "\($0.name) AS (\($0.sql))" }
        cteParts.append("ids AS MATERIALIZED (\n    \(idsInner)\n  )")
        let withClause = "WITH " + cteParts.joined(separator: ",\n  ")
        return ("\(withClause)\nSELECT COUNT(*) FROM ids", binds)
    }

    private func locationMissingSubquery(param: String) -> String? {
        switch param {
        case "name":               return "SELECT DISTINCT resource_id FROM idx_string WHERE resource_type = 'Location' AND param_name = 'name'"
        case "identifier":         return "SELECT DISTINCT resource_id FROM idx_token WHERE resource_type = 'Location' AND param_name = 'identifier'"
        case "status":             return "SELECT DISTINCT resource_id FROM idx_token WHERE resource_type = 'Location' AND param_name = 'status'"
        case "type":               return "SELECT DISTINCT resource_id FROM idx_token WHERE resource_type = 'Location' AND param_name = 'type'"
        case "operational-status": return "SELECT DISTINCT resource_id FROM idx_token WHERE resource_type = 'Location' AND param_name = 'operational-status'"
        case "address":            return "SELECT DISTINCT resource_id FROM idx_string WHERE resource_type = 'Location' AND param_name = 'address'"
        case "organization":       return "SELECT DISTINCT resource_id FROM idx_reference WHERE resource_type = 'Location' AND param_name = 'organization'"
        case "partof":             return "SELECT DISTINCT resource_id FROM idx_reference WHERE resource_type = 'Location' AND param_name = 'partof'"
        case "endpoint":           return "SELECT DISTINCT resource_id FROM idx_reference WHERE resource_type = 'Location' AND param_name = 'endpoint'"
        default:                   return nil
        }
    }
}
