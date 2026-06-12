import Foundation
import Logging
import ModelsR4
import PostgresNIO

public struct RelatedPersonStore: Sendable {
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

    public func create(_ rp: RelatedPerson) async throws -> WriteResult {
        let id = UUID().uuidString.lowercased()
        return try await write(id: id, rp: rp, ifMatch: nil)
    }

    public func update(id: String, rp: RelatedPerson, ifMatch: Int64?) async throws -> WriteResult {
        return try await write(id: id, rp: rp, ifMatch: ifMatch)
    }

    @discardableResult
    public func delete(id: String, ifMatch: Int64?) async throws -> DeleteResult {
        try await client.withConnection { conn in
            let (versionId, lastUpdated, _) = try await deleteResource(
                conn: conn, resourceType: "RelatedPerson", id: id, ifMatch: ifMatch, logger: logger)
            return DeleteResult(versionId: versionId, lastUpdated: lastUpdated)
        }
    }

    public func vread(id: String, versionId: Int64) async throws -> ReadResult {
        try await client.withConnection { conn in
            let rows = try await conn.query(
                """
                SELECT version_id, last_updated, content, deleted
                FROM resources
                WHERE resource_type = 'RelatedPerson' AND id = \(id) AND version_id = \(versionId)
                """, logger: logger)
            for try await (vid, lastUpdated, content, deleted) in
                rows.decode((Int64, Date, String, Bool).self, context: .default)
            {
                if deleted { throw FHIRServerError.gone(resourceType: "RelatedPerson", id: id) }
                let jsonData = injectMeta(into: content, versionId: vid, lastUpdated: lastUpdated)
                return ReadResult(jsonData: jsonData, versionId: vid, lastUpdated: lastUpdated)
            }
            throw FHIRServerError.notFound(resourceType: "RelatedPerson", id: id)
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
                    WHERE resource_type = 'RelatedPerson' AND id = \(id) AND last_updated >= \(since)
                    ORDER BY version_id DESC
                    LIMIT \(Int64(count))
                    """, logger: logger)
            } else {
                rows = try await conn.query(
                    """
                    SELECT version_id, last_updated, content, deleted
                    FROM resources
                    WHERE resource_type = 'RelatedPerson' AND id = \(id)
                    ORDER BY version_id DESC
                    LIMIT \(Int64(count))
                    """, logger: logger)
            }
            var entries: [HistoryRawEntry] = []
            for try await (vid, lastUpdated, content, deleted) in
                rows.decode((Int64, Date, String, Bool).self, context: .default)
            {
                let jsonData: Data? = deleted ? nil : injectMeta(into: content, versionId: vid, lastUpdated: lastUpdated)
                entries.append(HistoryRawEntry(resourceType: "RelatedPerson", id: id, versionId: vid, lastUpdated: lastUpdated, jsonData: jsonData, deleted: deleted))
            }
            if entries.isEmpty {
                if since != nil {
                    let existRows = try await conn.query(
                        """
                        SELECT 1 FROM resources WHERE resource_type = 'RelatedPerson' AND id = \(id) LIMIT 1
                        """, logger: logger)
                    var exists = false
                    for try await _ in existRows { exists = true }
                    if !exists { throw FHIRServerError.notFound(resourceType: "RelatedPerson", id: id) }
                } else {
                    throw FHIRServerError.notFound(resourceType: "RelatedPerson", id: id)
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
                    WHERE resource_type = 'RelatedPerson' AND last_updated >= \(since)
                    ORDER BY last_updated DESC, id, version_id DESC
                    LIMIT \(Int64(count))
                    """, logger: logger)
            } else {
                rows = try await conn.query(
                    """
                    SELECT id, version_id, last_updated, content, deleted
                    FROM resources
                    WHERE resource_type = 'RelatedPerson'
                    ORDER BY last_updated DESC, id, version_id DESC
                    LIMIT \(Int64(count))
                    """, logger: logger)
            }
            var entries: [HistoryRawEntry] = []
            for try await (rid, vid, lastUpdated, content, deleted) in
                rows.decode((String, Int64, Date, String, Bool).self, context: .default)
            {
                let jsonData: Data? = deleted ? nil : injectMeta(into: content, versionId: vid, lastUpdated: lastUpdated)
                entries.append(HistoryRawEntry(resourceType: "RelatedPerson", id: rid, versionId: vid, lastUpdated: lastUpdated, jsonData: jsonData, deleted: deleted))
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
                WHERE resource_type = 'RelatedPerson' AND id = \(id)
                ORDER BY version_id DESC
                LIMIT 1
                """, logger: logger)
            var found: ReadResult? = nil
            for try await (versionId, lastUpdated, content, deleted) in
                rows.decode((Int64, Date, String, Bool).self, context: .default)
            {
                if deleted { throw FHIRServerError.gone(resourceType: "RelatedPerson", id: id) }
                let jsonData = injectMeta(into: content, versionId: versionId, lastUpdated: lastUpdated)
                found = ReadResult(jsonData: jsonData, versionId: versionId, lastUpdated: lastUpdated)
            }
            guard let result = found else {
                throw FHIRServerError.notFound(resourceType: "RelatedPerson", id: id)
            }
            return result
        }
    }

    public func search(query: RelatedPersonSearchQuery) async throws -> SearchResult {
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

    private func write(id: String, rp: RelatedPerson, ifMatch: Int64?) async throws -> WriteResult {
        try validate(rp)

        var person = rp
        person.id   = FHIRPrimitive(FHIRString(id))
        person.meta = nil

        let jsonData   = try JSONEncoder().encode(person)
        if let _jsonObj = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] {
            try validateCodes(resourceType: "RelatedPerson", json: _jsonObj, terminology: terminology)
        }
        let jsonString = String(data: jsonData, encoding: .utf8)!
        var searchParams = extractRelatedPersonSearchParams(person)
        appendMetaParams(&searchParams, meta: rp.meta)

        return try await client.withConnection { conn in
            let (versionId, lastUpdated) = try await writeResource(
                conn: conn, resourceType: "RelatedPerson", id: id,
                jsonString: jsonString, ifMatch: ifMatch, params: searchParams, logger: logger)
            let responseData = injectMeta(into: jsonString, versionId: versionId, lastUpdated: lastUpdated)
            return WriteResult(id: id, versionId: versionId, lastUpdated: lastUpdated, jsonData: responseData)
        }
    }

    private func validate(_ rp: RelatedPerson) throws {}

    private func stringBindValue(_ param: RelatedPersonSearchQuery.StringParam) -> String {
        switch param.modifier {
        case .startsWith:      return "\(param.value)%"
        case .contains, .text: return "%\(param.value)%"
        case .exact:           return param.value
        }
    }

    private func stringFilterCond(_ param: RelatedPersonSearchQuery.StringParam, _ bp: String) -> String {
        switch param.modifier {
        case .exact:           return "value = \(bp)"
        case .contains, .text: return "value ILIKE \(bp)"
        case .startsWith:      return "lower(value) LIKE lower(\(bp))"
        }
    }

    private func buildSearchSQL(query: RelatedPersonSearchQuery) throws -> (String, PostgresBindings) {
        var binds = PostgresBindings()
        var n = 0
        func bind(_ val: some PostgresDynamicTypeEncodable) -> String {
            n += 1; binds.append(val); return "$\(n)"
        }

        var filterCTEs: [(name: String, sql: String)] = []

        func tokenORCTE(name: String, paramName: String, tokens: [RelatedPersonSearchQuery.TokenParam]) -> (String, String) {
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
            return (name, "SELECT DISTINCT resource_id FROM idx_token WHERE resource_type = 'RelatedPerson' AND param_name = '\(paramName)' AND (\(orClauses.joined(separator: " OR ")))")
        }

        func tokenNotCondition(paramName: String, tokens: [RelatedPersonSearchQuery.TokenParam]) -> String {
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
            return "r.id NOT IN (SELECT resource_id FROM idx_token WHERE resource_type = 'RelatedPerson' AND param_name = '\(paramName)' AND (\(orClauses.joined(separator: " OR "))))"
        }

        // token CTEs
        if !query.active.isEmpty       { filterCTEs.append(tokenORCTE(name: "f_active", paramName: "active", tokens: query.active)) }
        if !query.gender.isEmpty       { filterCTEs.append(tokenORCTE(name: "f_gender", paramName: "gender", tokens: query.gender)) }
        if !query.relationship.isEmpty { filterCTEs.append(tokenORCTE(name: "f_rel", paramName: "relationship", tokens: query.relationship)) }
        if !query.phone.isEmpty        { filterCTEs.append(tokenORCTE(name: "f_phone", paramName: "phone", tokens: query.phone)) }
        if !query.email.isEmpty        { filterCTEs.append(tokenORCTE(name: "f_email", paramName: "email", tokens: query.email)) }
        if !query.telecom.isEmpty      { filterCTEs.append(tokenORCTE(name: "f_telecom", paramName: "telecom", tokens: query.telecom)) }
        if !query.addressUse.isEmpty   { filterCTEs.append(tokenORCTE(name: "f_addruse", paramName: "address-use", tokens: query.addressUse)) }

        // identifier
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
                filterCTEs.append(("f_ident", "SELECT DISTINCT resource_id FROM idx_token WHERE resource_type = 'RelatedPerson' AND param_name = 'identifier' AND (\(orClauses.joined(separator: " OR ")))"))
            }
        }

        // string CTEs
        let stringFilters: [(String, String, RelatedPersonSearchQuery.StringParam?)] = [
            ("f_name",    "name",               query.name),
            ("f_addr",    "address",             query.address),
            ("f_city",    "address-city",        query.addressCity),
            ("f_country", "address-country",     query.addressCountry),
            ("f_postal",  "address-postalcode",  query.addressPostalcode),
            ("f_state",   "address-state",       query.addressState),
        ]
        for (cteName, paramName, param) in stringFilters {
            guard let param else { continue }
            let bp = bind(stringBindValue(param))
            filterCTEs.append((cteName, "SELECT DISTINCT resource_id FROM idx_string WHERE resource_type = 'RelatedPerson' AND param_name = '\(paramName)' AND \(stringFilterCond(param, bp))"))
        }

        // birthdate
        for (i, dp) in query.birthdate.enumerated() {
            let cteName = "f_bd\(i)"
            let startP = bind(dp.dateStart); let endP = bind(dp.dateEnd)
            let cond: String
            switch dp.prefix {
            case .eq: cond = "date_start >= \(startP) AND date_end <= \(endP)"
            case .ne: cond = "NOT (date_start >= \(startP) AND date_end <= \(endP))"
            case .lt: cond = "date_start < \(startP)"
            case .le: cond = "date_end <= \(endP)"
            case .gt: cond = "date_end > \(endP)"
            case .ge: cond = "date_start >= \(startP)"
            case .sa: cond = "date_start > \(endP)"
            case .eb: cond = "date_end < \(startP)"
            case .ap: cond = "date_start <= \(bind(dp.apExpandedEnd)) AND date_end >= \(bind(dp.apExpandedStart))"
            }
            filterCTEs.append((cteName, "SELECT DISTINCT resource_id FROM idx_date WHERE resource_type = 'RelatedPerson' AND param_name = 'birthdate' AND \(cond)"))
        }

        // patient (reference)
        if let pat = query.patient {
            let parts = pat.split(separator: "/")
            if parts.count == 2 {
                let refTypeP = bind(String(parts[0])); let refIdP = bind(String(parts[1]))
                filterCTEs.append(("f_patient",
                    "SELECT DISTINCT resource_id FROM idx_reference WHERE resource_type = 'RelatedPerson' AND param_name = 'patient' AND ref_type = \(refTypeP) AND ref_id = \(refIdP)"))
            } else {
                let refIdP = bind(pat)
                filterCTEs.append(("f_patient",
                    "SELECT DISTINCT resource_id FROM idx_reference WHERE resource_type = 'RelatedPerson' AND param_name = 'patient' AND ref_id = \(refIdP)"))
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

        // :not modifiers
        if !query.activeNot.isEmpty       { extraConditions.append(tokenNotCondition(paramName: "active",       tokens: query.activeNot)) }
        if !query.genderNot.isEmpty       { extraConditions.append(tokenNotCondition(paramName: "gender",       tokens: query.genderNot)) }
        if !query.relationshipNot.isEmpty { extraConditions.append(tokenNotCondition(paramName: "relationship", tokens: query.relationshipNot)) }
        if !query.phoneNot.isEmpty        { extraConditions.append(tokenNotCondition(paramName: "phone",        tokens: query.phoneNot)) }
        if !query.emailNot.isEmpty        { extraConditions.append(tokenNotCondition(paramName: "email",        tokens: query.emailNot)) }
        if !query.telecomNot.isEmpty      { extraConditions.append(tokenNotCondition(paramName: "telecom",      tokens: query.telecomNot)) }
        if !query.addressUseNot.isEmpty   { extraConditions.append(tokenNotCondition(paramName: "address-use",  tokens: query.addressUseNot)) }

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
                extraConditions.append("r.id NOT IN (SELECT resource_id FROM idx_token WHERE resource_type = 'RelatedPerson' AND param_name = 'identifier' AND (\(orClauses.joined(separator: " OR "))))")
            }
        }

        // :missing
        for paramName in query.missing.keys.sorted() {
            if let sub = relatedPersonMissingSubquery(param: paramName) {
                if query.missing[paramName] == true {
                    extraConditions.append("r.id NOT IN (\(sub))")
                } else {
                    extraConditions.append("r.id IN (\(sub))")
                }
            }
        }

        // Chained search
        let cBindStr: (String) -> String = { bind($0) }
        let cBindDate: (Date) -> String = { bind($0) }
        for (i, chain) in query.chains.enumerated() {
            if let (name, sql) = chainFilterCTE(
                index: filterCTEs.count + i, sourceType: "RelatedPerson",
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
                index: i, mainType: "RelatedPerson",
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
                "SELECT DISTINCT resource_id FROM idx_string WHERE resource_type = 'RelatedPerson' AND param_name = \(pn) AND value ILIKE \(val)"))
        }

        let strBind: (String) -> String = { bind($0) }
        let (metaCTEs, metaWhere) = metaFilterCTEs(resourceType: "RelatedPerson", meta: query.meta, bind: strBind)
        filterCTEs += metaCTEs
        extraConditions += metaWhere

        let idsInner = buildIdsInner(
            resourceType: "RelatedPerson",
            filterCTEs: filterCTEs,
            extraConditions: extraConditions
        )

        // ── Multi-sort paged CTE ──────────────────────────────────────────────
        // Cursor binds MUST happen before limitP bind.
        let sortResult = buildMultiSort(
            sortKeys: query.sortKeys,
            resourceType: "RelatedPerson",
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
            ? "FROM paged p JOIN resources r ON r.resource_type = 'RelatedPerson' AND r.id = p.id AND r.version_id = p.version_id"
            : "FROM paged p CROSS JOIN total_count t JOIN resources r ON r.resource_type = 'RelatedPerson' AND r.id = p.id AND r.version_id = p.version_id"

        let sql = "\(withClause)\nSELECT p.id, p.version_id, p.last_updated, r.content, \(totalExpr), p.sort_val_concat\n\(fromClause)\nORDER BY \(sortResult.outerOrderBy)"
        return (sql, binds)
    }

    private func buildCountSQL(query: RelatedPersonSearchQuery) throws -> (String, PostgresBindings) {
        var binds = PostgresBindings()
        var n = 0
        func bind(_ val: some PostgresDynamicTypeEncodable) -> String {
            n += 1; binds.append(val); return "$\(n)"
        }

        var filterCTEs: [(name: String, sql: String)] = []

        func countTokenORCTE(name: String, paramName: String, tokens: [RelatedPersonSearchQuery.TokenParam]) -> (String, String) {
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
            return (name, "SELECT DISTINCT resource_id FROM idx_token WHERE resource_type = 'RelatedPerson' AND param_name = '\(paramName)' AND (\(orClauses.joined(separator: " OR ")))")
        }

        if !query.active.isEmpty       { filterCTEs.append(countTokenORCTE(name: "f_active", paramName: "active", tokens: query.active)) }
        if !query.gender.isEmpty       { filterCTEs.append(countTokenORCTE(name: "f_gender", paramName: "gender", tokens: query.gender)) }
        if !query.relationship.isEmpty { filterCTEs.append(countTokenORCTE(name: "f_rel", paramName: "relationship", tokens: query.relationship)) }
        if !query.phone.isEmpty        { filterCTEs.append(countTokenORCTE(name: "f_phone", paramName: "phone", tokens: query.phone)) }
        if !query.email.isEmpty        { filterCTEs.append(countTokenORCTE(name: "f_email", paramName: "email", tokens: query.email)) }
        if !query.telecom.isEmpty      { filterCTEs.append(countTokenORCTE(name: "f_telecom", paramName: "telecom", tokens: query.telecom)) }
        if !query.addressUse.isEmpty   { filterCTEs.append(countTokenORCTE(name: "f_addruse", paramName: "address-use", tokens: query.addressUse)) }

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
                filterCTEs.append(("f_ident", "SELECT DISTINCT resource_id FROM idx_token WHERE resource_type = 'RelatedPerson' AND param_name = 'identifier' AND (\(orClauses.joined(separator: " OR ")))"))
            }
        }

        let countStringFilters: [(String, String, RelatedPersonSearchQuery.StringParam?)] = [
            ("f_name",    "name",               query.name),
            ("f_addr",    "address",             query.address),
            ("f_city",    "address-city",        query.addressCity),
            ("f_country", "address-country",     query.addressCountry),
            ("f_postal",  "address-postalcode",  query.addressPostalcode),
            ("f_state",   "address-state",       query.addressState),
        ]
        for (cteName, paramName, param) in countStringFilters {
            guard let param else { continue }
            let bp = bind(stringBindValue(param))
            filterCTEs.append((cteName, "SELECT DISTINCT resource_id FROM idx_string WHERE resource_type = 'RelatedPerson' AND param_name = '\(paramName)' AND \(stringFilterCond(param, bp))"))
        }

        for (i, dp) in query.birthdate.enumerated() {
            let cteName = "f_bd\(i)"
            let startP = bind(dp.dateStart); let endP = bind(dp.dateEnd)
            let cond: String
            switch dp.prefix {
            case .eq: cond = "date_start >= \(startP) AND date_end <= \(endP)"
            case .ne: cond = "NOT (date_start >= \(startP) AND date_end <= \(endP))"
            case .lt: cond = "date_start < \(startP)"
            case .le: cond = "date_end <= \(endP)"
            case .gt: cond = "date_end > \(endP)"
            case .ge: cond = "date_start >= \(startP)"
            case .sa: cond = "date_start > \(endP)"
            case .eb: cond = "date_end < \(startP)"
            case .ap: cond = "date_start <= \(bind(dp.apExpandedEnd)) AND date_end >= \(bind(dp.apExpandedStart))"
            }
            filterCTEs.append((cteName, "SELECT DISTINCT resource_id FROM idx_date WHERE resource_type = 'RelatedPerson' AND param_name = 'birthdate' AND \(cond)"))
        }

        if let pat = query.patient {
            let parts = pat.split(separator: "/")
            if parts.count == 2 {
                let refTypeP = bind(String(parts[0])); let refIdP = bind(String(parts[1]))
                filterCTEs.append(("f_patient",
                    "SELECT DISTINCT resource_id FROM idx_reference WHERE resource_type = 'RelatedPerson' AND param_name = 'patient' AND ref_type = \(refTypeP) AND ref_id = \(refIdP)"))
            } else {
                let refIdP = bind(pat)
                filterCTEs.append(("f_patient",
                    "SELECT DISTINCT resource_id FROM idx_reference WHERE resource_type = 'RelatedPerson' AND param_name = 'patient' AND ref_id = \(refIdP)"))
            }
        }

        func countTokenNotCond(paramName: String, tokens: [RelatedPersonSearchQuery.TokenParam]) -> String {
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
            return "r.id NOT IN (SELECT resource_id FROM idx_token WHERE resource_type = 'RelatedPerson' AND param_name = '\(paramName)' AND (\(orClauses.joined(separator: " OR "))))"
        }

        var whereConditions = ["r.resource_type = 'RelatedPerson'", "r.deleted = false"]
        if !query.id.isEmpty {
            let phs = query.id.map { bind($0) }.joined(separator: ", ")
            whereConditions.append("r.id IN (\(phs))")
        }

        if !query.phoneNot.isEmpty        { whereConditions.append(countTokenNotCond(paramName: "phone",        tokens: query.phoneNot)) }
        if !query.emailNot.isEmpty        { whereConditions.append(countTokenNotCond(paramName: "email",        tokens: query.emailNot)) }
        if !query.telecomNot.isEmpty      { whereConditions.append(countTokenNotCond(paramName: "telecom",      tokens: query.telecomNot)) }
        if !query.addressUseNot.isEmpty   { whereConditions.append(countTokenNotCond(paramName: "address-use",  tokens: query.addressUseNot)) }

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
                whereConditions.append("r.id NOT IN (SELECT resource_id FROM idx_token WHERE resource_type = 'RelatedPerson' AND param_name = 'identifier' AND (\(orClauses.joined(separator: " OR "))))")
            }
        }

        let cBindStr: (String) -> String = { bind($0) }
        let cBindDate: (Date) -> String = { bind($0) }
        for (i, chain) in query.chains.enumerated() {
            if let (name, sql) = chainFilterCTE(
                index: filterCTEs.count + i, sourceType: "RelatedPerson",
                chain: chain, bindStr: cBindStr, bindDate: cBindDate
            ) {
                filterCTEs.append((name, sql))
            }
        }

        let hBindStr: (String) -> String = { bind($0) }
        let hBindDate: (Date) -> String = { bind($0) }
        for (i, hp) in query.has.enumerated() {
            if let (name, sql) = hasFilterCTE(
                index: i, mainType: "RelatedPerson",
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
                "SELECT DISTINCT resource_id FROM idx_string WHERE resource_type = 'RelatedPerson' AND param_name = \(pn) AND value ILIKE \(val)"))
        }

        let strBind: (String) -> String = { bind($0) }
        let (metaCTEs, metaWhere) = metaFilterCTEs(resourceType: "RelatedPerson", meta: query.meta, bind: strBind)
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

    private func relatedPersonMissingSubquery(param: String) -> String? {
        switch param {
        case "active":           return "SELECT DISTINCT resource_id FROM idx_token WHERE resource_type = 'RelatedPerson' AND param_name = 'active'"
        case "gender":           return "SELECT DISTINCT resource_id FROM idx_token WHERE resource_type = 'RelatedPerson' AND param_name = 'gender'"
        case "identifier":       return "SELECT DISTINCT resource_id FROM idx_token WHERE resource_type = 'RelatedPerson' AND param_name = 'identifier'"
        case "relationship":     return "SELECT DISTINCT resource_id FROM idx_token WHERE resource_type = 'RelatedPerson' AND param_name = 'relationship'"
        case "phone":            return "SELECT DISTINCT resource_id FROM idx_token WHERE resource_type = 'RelatedPerson' AND param_name = 'phone'"
        case "email":            return "SELECT DISTINCT resource_id FROM idx_token WHERE resource_type = 'RelatedPerson' AND param_name = 'email'"
        case "name":             return "SELECT DISTINCT resource_id FROM idx_string WHERE resource_type = 'RelatedPerson' AND param_name = 'name'"
        case "address":          return "SELECT DISTINCT resource_id FROM idx_string WHERE resource_type = 'RelatedPerson' AND param_name = 'address'"
        case "birthdate":        return "SELECT DISTINCT resource_id FROM idx_date WHERE resource_type = 'RelatedPerson' AND param_name = 'birthdate'"
        case "patient":          return "SELECT DISTINCT resource_id FROM idx_reference WHERE resource_type = 'RelatedPerson' AND param_name = 'patient'"
        default:                 return nil
        }
    }
}
