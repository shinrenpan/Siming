import Foundation
import Logging
import ModelsR4
import PostgresNIO

public struct OrganizationStore: Sendable {
    public let client: PostgresClient
    public let logger: Logger
    let terminology: TerminologyIndex

    public init(client: PostgresClient, logger: Logger, terminology: TerminologyIndex = .empty) {
        self.client = client
        self.logger = logger
        self.terminology = terminology
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
        public let nextCursor: SearchCursor?
    }

    public struct DeleteResult: Sendable {
        public let versionId: Int64
        public let lastUpdated: Date
    }

    // ── Public API ────────────────────────────────────────────────────────────

    public func create(_ org: Organization) async throws -> WriteResult {
        let id = UUID().uuidString.lowercased()
        return try await write(id: id, organization: org, ifMatch: nil)
    }

    public func update(id: String, organization: Organization, ifMatch: Int64?) async throws -> WriteResult {
        return try await write(id: id, organization: organization, ifMatch: ifMatch)
    }

    @discardableResult
    public func delete(id: String, ifMatch: Int64?) async throws -> DeleteResult {
        try await client.withConnection { conn in
            let (versionId, lastUpdated, _) = try await deleteResource(
                conn: conn, resourceType: "Organization", id: id, ifMatch: ifMatch, logger: logger)
            return DeleteResult(versionId: versionId, lastUpdated: lastUpdated)
        }
    }

    public func vread(id: String, versionId: Int64) async throws -> ReadResult {
        try await client.withConnection { conn in
            let rows = try await conn.query(
                """
                SELECT version_id, last_updated, content, deleted
                FROM resources
                WHERE resource_type = 'Organization' AND id = \(id) AND version_id = \(versionId)
                """, logger: logger)
            for try await (vid, lastUpdated, content, deleted) in
                rows.decode((Int64, Date, String, Bool).self, context: .default)
            {
                if deleted { throw FHIRServerError.gone(resourceType: "Organization", id: id) }
                let jsonData = injectMeta(into: content, versionId: vid, lastUpdated: lastUpdated)
                return ReadResult(jsonData: jsonData, versionId: vid, lastUpdated: lastUpdated)
            }
            throw FHIRServerError.notFound(resourceType: "Organization", id: id)
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
                    WHERE resource_type = 'Organization' AND id = \(id) AND last_updated >= \(since)
                    ORDER BY version_id DESC
                    LIMIT \(Int64(count))
                    """, logger: logger)
            } else {
                rows = try await conn.query(
                    """
                    SELECT version_id, last_updated, content, deleted
                    FROM resources
                    WHERE resource_type = 'Organization' AND id = \(id)
                    ORDER BY version_id DESC
                    LIMIT \(Int64(count))
                    """, logger: logger)
            }
            var entries: [HistoryRawEntry] = []
            for try await (vid, lastUpdated, content, deleted) in
                rows.decode((Int64, Date, String, Bool).self, context: .default)
            {
                let jsonData: Data? = deleted ? nil : injectMeta(into: content, versionId: vid, lastUpdated: lastUpdated)
                entries.append(HistoryRawEntry(resourceType: "Organization", id: id, versionId: vid, lastUpdated: lastUpdated, jsonData: jsonData, deleted: deleted))
            }
            if entries.isEmpty {
                if since != nil {
                    let existRows = try await conn.query(
                        """
                        SELECT 1 FROM resources WHERE resource_type = 'Organization' AND id = \(id) LIMIT 1
                        """, logger: logger)
                    var exists = false
                    for try await _ in existRows { exists = true }
                    if !exists { throw FHIRServerError.notFound(resourceType: "Organization", id: id) }
                } else {
                    throw FHIRServerError.notFound(resourceType: "Organization", id: id)
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
                    WHERE resource_type = 'Organization' AND last_updated >= \(since)
                    ORDER BY last_updated DESC, id, version_id DESC
                    LIMIT \(Int64(count))
                    """, logger: logger)
            } else {
                rows = try await conn.query(
                    """
                    SELECT id, version_id, last_updated, content, deleted
                    FROM resources
                    WHERE resource_type = 'Organization'
                    ORDER BY last_updated DESC, id, version_id DESC
                    LIMIT \(Int64(count))
                    """, logger: logger)
            }
            var entries: [HistoryRawEntry] = []
            for try await (rid, vid, lastUpdated, content, deleted) in
                rows.decode((String, Int64, Date, String, Bool).self, context: .default)
            {
                let jsonData: Data? = deleted ? nil : injectMeta(into: content, versionId: vid, lastUpdated: lastUpdated)
                entries.append(HistoryRawEntry(resourceType: "Organization", id: rid, versionId: vid, lastUpdated: lastUpdated, jsonData: jsonData, deleted: deleted))
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
                WHERE resource_type = 'Organization' AND id = \(id)
                ORDER BY version_id DESC
                LIMIT 1
                """, logger: logger)
            var found: ReadResult? = nil
            for try await (versionId, lastUpdated, content, deleted) in
                rows.decode((Int64, Date, String, Bool).self, context: .default)
            {
                if deleted { throw FHIRServerError.gone(resourceType: "Organization", id: id) }
                let jsonData = injectMeta(into: content, versionId: versionId, lastUpdated: lastUpdated)
                found = ReadResult(jsonData: jsonData, versionId: versionId, lastUpdated: lastUpdated)
            }
            guard let result = found else {
                throw FHIRServerError.notFound(resourceType: "Organization", id: id)
            }
            return result
        }
    }

    public func search(query: OrganizationSearchQuery) async throws -> SearchResult {
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

            let nextCursor: SearchCursor?
            if hasNext, let lastEntry = page.last, let lastConcat = pageSortVals.last {
                let parts = lastConcat.split(separator: "\u{1f}", omittingEmptySubsequences: false).map(String.init)
                let cursorValues = parts.count > 1 ? Array(parts.dropLast()) : parts
                nextCursor = SearchCursor(values: cursorValues, id: lastEntry.id)
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

    private func write(id: String, organization: Organization, ifMatch: Int64?) async throws -> WriteResult {
        try validate(organization)

        var org = organization
        org.id   = FHIRPrimitive(FHIRString(id))
        org.meta = nil

        let jsonData   = try JSONEncoder().encode(org)
        if let _jsonObj = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] {
            try validateCodes(resourceType: "Organization", json: _jsonObj, terminology: terminology)
        }
        let jsonString = String(data: jsonData, encoding: .utf8)!
        var searchParams = extractOrganizationSearchParams(org)
        appendMetaParams(&searchParams, meta: organization.meta)

        return try await client.withConnection { conn in
            let (versionId, lastUpdated) = try await writeResource(
                conn: conn, resourceType: "Organization", id: id,
                jsonString: jsonString, ifMatch: ifMatch, params: searchParams, logger: logger)
            let responseData = injectMeta(into: jsonString, versionId: versionId, lastUpdated: lastUpdated)
            return WriteResult(id: id, versionId: versionId, lastUpdated: lastUpdated, jsonData: responseData)
        }
    }

    private func validate(_ org: Organization) throws {}

    private func stringBindValue(_ param: OrganizationSearchQuery.StringParam) -> String {
        switch param.modifier {
        case .startsWith:      return "\(param.value)%"
        case .contains, .text: return "%\(param.value)%"
        case .exact:           return param.value
        }
    }

    private func stringFilterCond(_ param: OrganizationSearchQuery.StringParam, _ bp: String) -> String {
        switch param.modifier {
        case .exact:           return "value = \(bp)"
        case .contains, .text: return "value ILIKE \(bp)"
        case .startsWith:      return "lower(value) LIKE lower(\(bp))"
        }
    }

    private func buildSearchSQL(query: OrganizationSearchQuery) throws -> (String, PostgresBindings) {
        var binds = PostgresBindings()
        var n = 0
        func bind(_ val: some PostgresDynamicTypeEncodable) -> String {
            n += 1; binds.append(val); return "$\(n)"
        }

        var filterCTEs: [(name: String, sql: String)] = []

        // String filters
        let stringFilters: [(String, String, OrganizationSearchQuery.StringParam?)] = [
            ("f_name",     "name",               query.name),
            ("f_phonetic", "phonetic",           query.phonetic),
            ("f_addr",     "address",            query.address),
            ("f_city",     "address-city",       query.addressCity),
            ("f_state",    "address-state",      query.addressState),
            ("f_postal",   "address-postalcode", query.addressPostalCode),
            ("f_country",  "address-country",    query.addressCountry),
        ]
        for (cteName, paramName, param) in stringFilters {
            guard let param else { continue }
            let bp = bind(stringBindValue(param))
            filterCTEs.append((cteName, "SELECT DISTINCT resource_id FROM idx_string WHERE resource_type = 'Organization' AND param_name = '\(paramName)' AND \(stringFilterCond(param, bp))"))
        }

        // active — boolean token
        if let active = query.active {
            let p = bind(active ? "true" : "false")
            filterCTEs.append(("f_active", "SELECT DISTINCT resource_id FROM idx_token WHERE resource_type = 'Organization' AND param_name = 'active' AND code = \(p)"))
        }

        // type — token OR
        func tokenORCTE(name: String, paramName: String, tokens: [OrganizationSearchQuery.TokenParam]) -> (String, String) {
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
            return (name, "SELECT DISTINCT resource_id FROM idx_token WHERE resource_type = 'Organization' AND param_name = '\(paramName)' AND (\(orClauses.joined(separator: " OR ")))")
        }

        if !query.type.isEmpty { filterCTEs.append(tokenORCTE(name: "f_type", paramName: "type", tokens: query.type)) }

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
                filterCTEs.append(("f_ident", "SELECT DISTINCT resource_id FROM idx_token WHERE resource_type = 'Organization' AND param_name = 'identifier' AND (\(orClauses.joined(separator: " OR ")))"))
            }
        }

        // partof — reference filter
        if let partof = query.partof {
            let parts = partof.split(separator: "/")
            if parts.count == 2 {
                let refTypeP = bind(String(parts[0])); let refIdP = bind(String(parts[1]))
                filterCTEs.append(("f_partof",
                    "SELECT DISTINCT resource_id FROM idx_reference WHERE resource_type = 'Organization' AND param_name = 'partof' AND ref_type = \(refTypeP) AND ref_id = \(refIdP)"))
            } else {
                let refIdP = bind(partof)
                filterCTEs.append(("f_partof",
                    "SELECT DISTINCT resource_id FROM idx_reference WHERE resource_type = 'Organization' AND param_name = 'partof' AND ref_id = \(refIdP)"))
            }
        }

        // endpoint — reference filter
        if let endpoint = query.endpoint {
            let parts = endpoint.split(separator: "/")
            if parts.count == 2 {
                let refTypeP = bind(String(parts[0])); let refIdP = bind(String(parts[1]))
                filterCTEs.append(("f_endpoint",
                    "SELECT DISTINCT resource_id FROM idx_reference WHERE resource_type = 'Organization' AND param_name = 'endpoint' AND ref_type = \(refTypeP) AND ref_id = \(refIdP)"))
            } else {
                let refIdP = bind(endpoint)
                filterCTEs.append(("f_endpoint",
                    "SELECT DISTINCT resource_id FROM idx_reference WHERE resource_type = 'Organization' AND param_name = 'endpoint' AND ref_id = \(refIdP)"))
            }
        }

        // ── WHERE conditions ──────────────────────────────────────────────────

        var extraConditions: [String] = []

        if !query.id.isEmpty {
            let phs = query.id.map { bind($0) }.joined(separator: ", ")
            extraConditions.append("r.id IN (\(phs))")
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
            case .ap: cond = "r.last_updated BETWEEN \(bind(lu.apExpandedStart)) AND \(bind(lu.apExpandedEnd))"
            }
            extraConditions.append(cond)
        }

        // type:not
        if !query.typeNot.isEmpty {
            var orClauses: [String] = []
            for tok in query.typeNot {
                if tok.code.isEmpty, let sys = tok.system {
                    orClauses.append("system = \(bind(sys))")
                } else {
                    let codeP = bind(tok.code); var sysCond = ""
                    if let sys = tok.system { sysCond = " AND system = \(bind(sys))" }
                    orClauses.append("(code = \(codeP)\(sysCond))")
                }
            }
            extraConditions.append("r.id NOT IN (SELECT resource_id FROM idx_token WHERE resource_type = 'Organization' AND param_name = 'type' AND (\(orClauses.joined(separator: " OR "))))")
        }

        // identifier:not
        if !query.identifierNot.isEmpty {
            var orClauses: [String] = []
            for ident in query.identifierNot {
                if ident.code.isEmpty {
                    if case .specific(let sys?) = ident.systemFilter {
                        orClauses.append("system = \(bind(sys))")
                    }
                } else {
                    let codeP = bind(ident.code)
                    var sysCond = ""
                    switch ident.systemFilter {
                    case .any: break
                    case .specific(nil): sysCond = " AND system IS NULL"
                    case .specific(let sys?): sysCond = " AND system = \(bind(sys))"
                    }
                    orClauses.append("(code = \(codeP)\(sysCond))")
                }
            }
            if !orClauses.isEmpty {
                extraConditions.append("r.id NOT IN (SELECT resource_id FROM idx_token WHERE resource_type = 'Organization' AND param_name = 'identifier' AND (\(orClauses.joined(separator: " OR "))))")
            }
        }

        for paramName in query.missing.keys.sorted() {
            if let sub = organizationMissingSubquery(param: paramName) {
                if query.missing[paramName] == true {
                    extraConditions.append("r.id NOT IN (\(sub))")
                } else {
                    extraConditions.append("r.id IN (\(sub))")
                }
            }
        }

        // Chained search params
        let cBindStr: (String) -> String = { bind($0) }
        let cBindDate: (Date) -> String = { bind($0) }
        for (i, chain) in query.chains.enumerated() {
            if let (name, sql) = chainFilterCTE(
                index: filterCTEs.count + i, sourceType: "Organization",
                chain: chain, bindStr: cBindStr, bindDate: cBindDate
            ) {
                filterCTEs.append((name, sql))
            }
        }

        // _has modifier (reverse chaining)
        let hBindStr: (String) -> String = { bind($0) }
        let hBindDate: (Date) -> String = { bind($0) }
        for (i, hp) in query.has.enumerated() {
            if let (name, sql) = hasFilterCTE(
                index: i, mainType: "Organization",
                param: hp, bindStr: hBindStr, bindDate: hBindDate
            ) {
                filterCTEs.append((name, sql))
            }
        }

        // token:text filters
        for (i, tt) in query.tokenTexts.enumerated() {
            let pn = bind("\(tt.paramName):text")
            let val = bind("%\(tt.value)%")
            filterCTEs.append(("f_ttext\(i)",
                "SELECT DISTINCT resource_id FROM idx_string WHERE resource_type = 'Organization' AND param_name = \(pn) AND value ILIKE \(val)"))
        }

        let strBind: (String) -> String = { bind($0) }
        let (metaCTEs, metaWhere) = metaFilterCTEs(resourceType: "Organization", meta: query.meta, bind: strBind)
        filterCTEs += metaCTEs
        extraConditions += metaWhere

        let idsInner = buildIdsInner(
            resourceType: "Organization",
            filterCTEs: filterCTEs,
            extraConditions: extraConditions
        )

        // ── Multi-sort paged CTE ──────────────────────────────────────────────
        // Cursor binds MUST happen before limitP bind.
        let sortResult = buildMultiSort(
            sortKeys: query.sortKeys,
            resourceType: "Organization",
            idsAlias: "ids",
            cursor: query.cursor,
            limitBind: bind(Int64(query.count + 1)),
            bindString: { bind($0) },
            bindDate: { bind($0) }
        )

        var cteParts = filterCTEs.map { "\($0.name) AS (\n    \($0.sql)\n  )" }
        cteParts.append("ids AS MATERIALIZED (\n    \(idsInner)\n  )")
        let skipTotal = query.totalMode == .none || query.totalMode == .estimate
        if !skipTotal {
            cteParts.append("total_count AS (\n    SELECT COUNT(*) AS n FROM ids\n  )")
        }
        for (name, sql) in sortResult.sortCTEs {
            cteParts.append("\(name) AS (\n    \(sql)\n  )")
        }
        cteParts.append("paged AS (\n    \(sortResult.pagedBody)\n  )")
        let withClause = "WITH " + cteParts.joined(separator: ",\n  ")

        let totalExpr = skipTotal ? "CAST(0 AS bigint)" : "t.n"
        let fromClause = skipTotal
            ? "FROM paged p JOIN resources r ON r.resource_type = 'Organization' AND r.id = p.id AND r.version_id = p.version_id"
            : "FROM paged p CROSS JOIN total_count t JOIN resources r ON r.resource_type = 'Organization' AND r.id = p.id AND r.version_id = p.version_id"

        let sql = "\(withClause)\nSELECT p.id, p.version_id, p.last_updated, r.content, \(totalExpr), p.sort_val_concat\n\(fromClause)\nORDER BY \(sortResult.outerOrderBy)"
        return (sql, binds)
    }

    private func buildCountSQL(query: OrganizationSearchQuery) throws -> (String, PostgresBindings) {
        var binds = PostgresBindings()
        var n = 0
        func bind(_ val: some PostgresDynamicTypeEncodable) -> String {
            n += 1; binds.append(val); return "$\(n)"
        }

        var filterCTEs: [(name: String, sql: String)] = []

        let stringFilters: [(String, String, OrganizationSearchQuery.StringParam?)] = [
            ("f_name",     "name",               query.name),
            ("f_phonetic", "phonetic",           query.phonetic),
            ("f_addr",     "address",            query.address),
            ("f_city",     "address-city",       query.addressCity),
            ("f_state",    "address-state",      query.addressState),
            ("f_postal",   "address-postalcode", query.addressPostalCode),
            ("f_country",  "address-country",    query.addressCountry),
        ]
        for (cteName, paramName, param) in stringFilters {
            guard let param else { continue }
            let bp = bind(stringBindValue(param))
            filterCTEs.append((cteName, "SELECT DISTINCT resource_id FROM idx_string WHERE resource_type = 'Organization' AND param_name = '\(paramName)' AND \(stringFilterCond(param, bp))"))
        }

        if let active = query.active {
            let p = bind(active ? "true" : "false")
            filterCTEs.append(("f_active", "SELECT DISTINCT resource_id FROM idx_token WHERE resource_type = 'Organization' AND param_name = 'active' AND code = \(p)"))
        }

        if !query.type.isEmpty {
            var orClauses: [String] = []
            for tok in query.type {
                if tok.code.isEmpty, let sys = tok.system {
                    orClauses.append("system = \(bind(sys))")
                } else {
                    let codeP = bind(tok.code); var sysCond = ""
                    if let sys = tok.system { sysCond = " AND system = \(bind(sys))" }
                    orClauses.append("(code = \(codeP)\(sysCond))")
                }
            }
            filterCTEs.append(("f_type", "SELECT DISTINCT resource_id FROM idx_token WHERE resource_type = 'Organization' AND param_name = 'type' AND (\(orClauses.joined(separator: " OR ")))"))
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
                filterCTEs.append(("f_ident", "SELECT DISTINCT resource_id FROM idx_token WHERE resource_type = 'Organization' AND param_name = 'identifier' AND (\(orClauses.joined(separator: " OR ")))"))
            }
        }

        if let partof = query.partof {
            let parts = partof.split(separator: "/")
            if parts.count == 2 {
                let refTypeP = bind(String(parts[0])); let refIdP = bind(String(parts[1]))
                filterCTEs.append(("f_partof",
                    "SELECT DISTINCT resource_id FROM idx_reference WHERE resource_type = 'Organization' AND param_name = 'partof' AND ref_type = \(refTypeP) AND ref_id = \(refIdP)"))
            } else {
                let refIdP = bind(partof)
                filterCTEs.append(("f_partof",
                    "SELECT DISTINCT resource_id FROM idx_reference WHERE resource_type = 'Organization' AND param_name = 'partof' AND ref_id = \(refIdP)"))
            }
        }

        if let endpoint = query.endpoint {
            let parts = endpoint.split(separator: "/")
            if parts.count == 2 {
                let refTypeP = bind(String(parts[0])); let refIdP = bind(String(parts[1]))
                filterCTEs.append(("f_endpoint",
                    "SELECT DISTINCT resource_id FROM idx_reference WHERE resource_type = 'Organization' AND param_name = 'endpoint' AND ref_type = \(refTypeP) AND ref_id = \(refIdP)"))
            } else {
                let refIdP = bind(endpoint)
                filterCTEs.append(("f_endpoint",
                    "SELECT DISTINCT resource_id FROM idx_reference WHERE resource_type = 'Organization' AND param_name = 'endpoint' AND ref_id = \(refIdP)"))
            }
        }

        var whereConditions = ["r.resource_type = 'Organization'", "r.deleted = false"]
        if !query.id.isEmpty {
            let phs = query.id.map { bind($0) }.joined(separator: ", ")
            whereConditions.append("r.id IN (\(phs))")
        }

        // identifier:not
        if !query.identifierNot.isEmpty {
            var orClauses: [String] = []
            for ident in query.identifierNot {
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
                whereConditions.append("r.id NOT IN (SELECT resource_id FROM idx_token WHERE resource_type = 'Organization' AND param_name = 'identifier' AND (\(orClauses.joined(separator: " OR "))))")
            }
        }

        let cBindStr: (String) -> String = { bind($0) }
        let cBindDate: (Date) -> String = { bind($0) }
        for (i, chain) in query.chains.enumerated() {
            if let (name, sql) = chainFilterCTE(
                index: filterCTEs.count + i, sourceType: "Organization",
                chain: chain, bindStr: cBindStr, bindDate: cBindDate
            ) {
                filterCTEs.append((name, sql))
            }
        }

        let hBindStr: (String) -> String = { bind($0) }
        let hBindDate: (Date) -> String = { bind($0) }
        for (i, hp) in query.has.enumerated() {
            if let (name, sql) = hasFilterCTE(
                index: i, mainType: "Organization",
                param: hp, bindStr: hBindStr, bindDate: hBindDate
            ) {
                filterCTEs.append((name, sql))
            }
        }

        // token:text filters
        for (i, tt) in query.tokenTexts.enumerated() {
            let pn = bind("\(tt.paramName):text")
            let val = bind("%\(tt.value)%")
            filterCTEs.append(("f_ttext\(i)",
                "SELECT DISTINCT resource_id FROM idx_string WHERE resource_type = 'Organization' AND param_name = \(pn) AND value ILIKE \(val)"))
        }

        let strBind: (String) -> String = { bind($0) }
        let (metaCTEs, metaWhere) = metaFilterCTEs(resourceType: "Organization", meta: query.meta, bind: strBind)
        filterCTEs += metaCTEs
        whereConditions += metaWhere

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

    private func organizationMissingSubquery(param: String) -> String? {
        switch param {
        case "name":       return "SELECT DISTINCT resource_id FROM idx_string WHERE resource_type = 'Organization' AND param_name = 'name'"
        case "identifier": return "SELECT DISTINCT resource_id FROM idx_token WHERE resource_type = 'Organization' AND param_name = 'identifier'"
        case "active":     return "SELECT DISTINCT resource_id FROM idx_token WHERE resource_type = 'Organization' AND param_name = 'active'"
        case "type":       return "SELECT DISTINCT resource_id FROM idx_token WHERE resource_type = 'Organization' AND param_name = 'type'"
        case "address":    return "SELECT DISTINCT resource_id FROM idx_string WHERE resource_type = 'Organization' AND param_name = 'address'"
        case "phonetic":   return "SELECT DISTINCT resource_id FROM idx_string WHERE resource_type = 'Organization' AND param_name = 'phonetic'"
        case "partof":     return "SELECT DISTINCT resource_id FROM idx_reference WHERE resource_type = 'Organization' AND param_name = 'partof'"
        case "endpoint":   return "SELECT DISTINCT resource_id FROM idx_reference WHERE resource_type = 'Organization' AND param_name = 'endpoint'"
        default:           return nil
        }
    }
}
