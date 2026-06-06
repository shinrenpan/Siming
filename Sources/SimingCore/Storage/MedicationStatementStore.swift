import Foundation
import Logging
import ModelsR4
import PostgresNIO

public struct MedicationStatementStore: Sendable {
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
        public let nextCursor: MedicationStatementSearchQuery.SearchCursor?
    }

    public struct DeleteResult: Sendable {
        public let versionId: Int64
        public let lastUpdated: Date
    }

    // ── Public API ────────────────────────────────────────────────────────────

    public func create(_ ms: MedicationStatement) async throws -> WriteResult {
        let id = UUID().uuidString.lowercased()
        return try await write(id: id, medicationStatement: ms, ifMatch: nil)
    }

    public func update(id: String, medicationStatement: MedicationStatement, ifMatch: Int64?) async throws -> WriteResult {
        return try await write(id: id, medicationStatement: medicationStatement, ifMatch: ifMatch)
    }

    @discardableResult
    public func delete(id: String, ifMatch: Int64?) async throws -> DeleteResult {
        try await client.withConnection { conn in
            _ = try await conn.query("BEGIN", logger: logger)
            do {
                let rows = try await conn.query(
                    """
                    SELECT version_id, deleted FROM resources
                    WHERE resource_type = 'MedicationStatement' AND id = \(id)
                    ORDER BY version_id DESC LIMIT 1
                    """, logger: logger)
                var currentVersion: Int64? = nil
                var isDeleted = false
                for try await (v, d) in rows.decode((Int64, Bool).self, context: .default) {
                    currentVersion = v; isDeleted = d
                }
                guard let current = currentVersion else {
                    _ = try? await conn.query("ROLLBACK", logger: logger)
                    throw FHIRServerError.notFound(resourceType: "MedicationStatement", id: id)
                }
                if isDeleted {
                    _ = try? await conn.query("ROLLBACK", logger: logger)
                    return DeleteResult(versionId: current, lastUpdated: Date())
                }
                if let expected = ifMatch, current != expected {
                    _ = try? await conn.query("ROLLBACK", logger: logger)
                    throw FHIRServerError.versionConflict(id: id, expected: expected, actual: current)
                }

                let nextVersion = current + 1
                let insRows = try await conn.query(
                    """
                    INSERT INTO resources (resource_type, id, version_id, last_updated, content, deleted)
                    VALUES ('MedicationStatement', \(id), \(nextVersion), now(), '{}'::jsonb, true)
                    RETURNING last_updated
                    """, logger: logger)
                var lastUpdated = Date()
                for try await (d) in insRows.decode(Date.self, context: .default) { lastUpdated = d }

                _ = try await conn.query("DELETE FROM idx_token     WHERE resource_type = 'MedicationStatement' AND resource_id = \(id)", logger: logger)
                _ = try await conn.query("DELETE FROM idx_string    WHERE resource_type = 'MedicationStatement' AND resource_id = \(id)", logger: logger)
                _ = try await conn.query("DELETE FROM idx_date      WHERE resource_type = 'MedicationStatement' AND resource_id = \(id)", logger: logger)
                _ = try await conn.query("DELETE FROM idx_reference WHERE resource_type = 'MedicationStatement' AND resource_id = \(id)", logger: logger)
                _ = try await conn.query("DELETE FROM idx_quantity  WHERE resource_type = 'MedicationStatement' AND resource_id = \(id)", logger: logger)

                _ = try await conn.query("COMMIT", logger: logger)
                return DeleteResult(versionId: nextVersion, lastUpdated: lastUpdated)
            } catch {
                _ = try? await conn.query("ROLLBACK", logger: logger)
                throw error
            }
        }
    }

    public func vread(id: String, versionId: Int64) async throws -> ReadResult {
        try await client.withConnection { conn in
            let rows = try await conn.query(
                """
                SELECT version_id, last_updated, content, deleted
                FROM resources
                WHERE resource_type = 'MedicationStatement' AND id = \(id) AND version_id = \(versionId)
                """, logger: logger)
            for try await (vid, lastUpdated, content, deleted) in
                rows.decode((Int64, Date, String, Bool).self, context: .default)
            {
                if deleted { throw FHIRServerError.gone(resourceType: "MedicationStatement", id: id) }
                let jsonData = injectMeta(into: content, versionId: vid, lastUpdated: lastUpdated)
                return ReadResult(jsonData: jsonData, versionId: vid, lastUpdated: lastUpdated)
            }
            throw FHIRServerError.notFound(resourceType: "MedicationStatement", id: id)
        }
    }

    public func history(id: String) async throws -> [HistoryRawEntry] {
        try await client.withConnection { conn in
            let rows = try await conn.query(
                """
                SELECT version_id, last_updated, content, deleted
                FROM resources
                WHERE resource_type = 'MedicationStatement' AND id = \(id)
                ORDER BY version_id DESC
                """, logger: logger)
            var entries: [HistoryRawEntry] = []
            for try await (vid, lastUpdated, content, deleted) in
                rows.decode((Int64, Date, String, Bool).self, context: .default)
            {
                let jsonData: Data? = deleted ? nil : injectMeta(into: content, versionId: vid, lastUpdated: lastUpdated)
                entries.append(HistoryRawEntry(resourceType: "MedicationStatement", id: id, versionId: vid, lastUpdated: lastUpdated, jsonData: jsonData, deleted: deleted))
            }
            guard !entries.isEmpty else {
                throw FHIRServerError.notFound(resourceType: "MedicationStatement", id: id)
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
                    WHERE resource_type = 'MedicationStatement' AND last_updated >= \(since)
                    ORDER BY last_updated DESC, id, version_id DESC
                    LIMIT \(Int64(count))
                    """, logger: logger)
            } else {
                rows = try await conn.query(
                    """
                    SELECT id, version_id, last_updated, content, deleted
                    FROM resources
                    WHERE resource_type = 'MedicationStatement'
                    ORDER BY last_updated DESC, id, version_id DESC
                    LIMIT \(Int64(count))
                    """, logger: logger)
            }
            var entries: [HistoryRawEntry] = []
            for try await (rid, vid, lastUpdated, content, deleted) in
                rows.decode((String, Int64, Date, String, Bool).self, context: .default)
            {
                let jsonData: Data? = deleted ? nil : injectMeta(into: content, versionId: vid, lastUpdated: lastUpdated)
                entries.append(HistoryRawEntry(resourceType: "MedicationStatement", id: rid, versionId: vid, lastUpdated: lastUpdated, jsonData: jsonData, deleted: deleted))
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
                WHERE resource_type = 'MedicationStatement' AND id = \(id)
                ORDER BY version_id DESC
                LIMIT 1
                """, logger: logger)
            var found: ReadResult? = nil
            for try await (versionId, lastUpdated, content, deleted) in
                rows.decode((Int64, Date, String, Bool).self, context: .default)
            {
                if deleted { throw FHIRServerError.gone(resourceType: "MedicationStatement", id: id) }
                let jsonData = injectMeta(into: content, versionId: versionId, lastUpdated: lastUpdated)
                found = ReadResult(jsonData: jsonData, versionId: versionId, lastUpdated: lastUpdated)
            }
            guard let result = found else {
                throw FHIRServerError.notFound(resourceType: "MedicationStatement", id: id)
            }
            return result
        }
    }

    public func search(query: MedicationStatementSearchQuery) async throws -> SearchResult {
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

            let nextCursor: MedicationStatementSearchQuery.SearchCursor?
            if hasNext, let lastEntry = page.last, let lastSortVal = pageSortVals.last {
                nextCursor = MedicationStatementSearchQuery.SearchCursor(
                    sortValue: lastSortVal, id: lastEntry.id, descending: query.sort.isDescending)
            } else {
                nextCursor = nil
            }

            let total: Int? = query.totalMode == .none ? nil : Int(rawTotal)
            return SearchResult(entries: page, total: total, nextCursor: nextCursor)
        }
    }

    // ── Private ───────────────────────────────────────────────────────────────

    private func write(id: String, medicationStatement: MedicationStatement, ifMatch: Int64?) async throws -> WriteResult {
        try validate(medicationStatement)

        var ms = medicationStatement
        ms.id   = FHIRPrimitive(FHIRString(id))
        ms.meta = nil

        let jsonData   = try JSONEncoder().encode(ms)
        let jsonString = String(data: jsonData, encoding: .utf8)!
        let searchParams = extractMedicationStatementSearchParams(ms)

        return try await client.withConnection { conn in
            _ = try await conn.query("BEGIN", logger: logger)
            do {
                if let expected = ifMatch {
                    let vRows = try await conn.query(
                        """
                        SELECT version_id FROM resources
                        WHERE resource_type = 'MedicationStatement' AND id = \(id)
                        ORDER BY version_id DESC LIMIT 1
                        """, logger: logger)
                    var current: Int64? = nil
                    for try await (v) in vRows.decode(Int64.self, context: .default) { current = v }
                    guard current == expected else {
                        throw FHIRServerError.versionConflict(id: id, expected: expected, actual: current)
                    }
                }

                let nvRows = try await conn.query(
                    """
                    SELECT COALESCE(MAX(version_id), 0) + 1
                    FROM resources
                    WHERE resource_type = 'MedicationStatement' AND id = \(id)
                    """, logger: logger)
                var nextVersion: Int64 = 1
                for try await (v) in nvRows.decode(Int64.self, context: .default) { nextVersion = v }

                let insRows = try await conn.query(
                    """
                    INSERT INTO resources
                        (resource_type, id, version_id, last_updated, content, deleted)
                    VALUES ('MedicationStatement', \(id), \(nextVersion), now(), \(jsonString)::jsonb, false)
                    RETURNING last_updated
                    """, logger: logger)
                var lastUpdated = Date()
                for try await (d) in insRows.decode(Date.self, context: .default) { lastUpdated = d }

                try await replaceIndexRows(conn: conn, id: id, params: searchParams)

                _ = try await conn.query("COMMIT", logger: logger)

                let responseData = injectMeta(into: jsonString, versionId: nextVersion, lastUpdated: lastUpdated)
                return WriteResult(id: id, versionId: nextVersion, lastUpdated: lastUpdated, jsonData: responseData)
            } catch {
                _ = try? await conn.query("ROLLBACK", logger: logger)
                throw error
            }
        }
    }

    private func validate(_ ms: MedicationStatement) throws {}

    private func replaceIndexRows(conn: PostgresConnection, id: String, params: SearchParams) async throws {
        _ = try await conn.query("DELETE FROM idx_token     WHERE resource_type = 'MedicationStatement' AND resource_id = \(id)", logger: logger)
        _ = try await conn.query("DELETE FROM idx_string    WHERE resource_type = 'MedicationStatement' AND resource_id = \(id)", logger: logger)
        _ = try await conn.query("DELETE FROM idx_date      WHERE resource_type = 'MedicationStatement' AND resource_id = \(id)", logger: logger)
        _ = try await conn.query("DELETE FROM idx_reference WHERE resource_type = 'MedicationStatement' AND resource_id = \(id)", logger: logger)
        _ = try await conn.query("DELETE FROM idx_quantity  WHERE resource_type = 'MedicationStatement' AND resource_id = \(id)", logger: logger)

        for row in params.tokens {
            _ = try await conn.query(
                "INSERT INTO idx_token (resource_type, resource_id, param_name, system, code) VALUES ('MedicationStatement', \(id), \(row.paramName), \(row.system), \(row.code))",
                logger: logger)
        }
        for row in params.strings {
            _ = try await conn.query(
                "INSERT INTO idx_string (resource_type, resource_id, param_name, value) VALUES ('MedicationStatement', \(id), \(row.paramName), \(row.value))",
                logger: logger)
        }
        for row in params.dates {
            _ = try await conn.query(
                "INSERT INTO idx_date (resource_type, resource_id, param_name, date_start, date_end) VALUES ('MedicationStatement', \(id), \(row.paramName), \(row.dateStart), \(row.dateEnd))",
                logger: logger)
        }
        for row in params.references {
            _ = try await conn.query(
                "INSERT INTO idx_reference (resource_type, resource_id, param_name, ref_type, ref_id) VALUES ('MedicationStatement', \(id), \(row.paramName), \(row.refType), \(row.refId))",
                logger: logger)
        }
        for row in params.quantities {
            _ = try await conn.query(
                "INSERT INTO idx_quantity (resource_type, resource_id, param_name, system, code, value) VALUES ('MedicationStatement', \(id), \(row.paramName), \(row.system), \(row.code), \(row.value))",
                logger: logger)
        }
    }

    private func buildSearchSQL(query: MedicationStatementSearchQuery) throws -> (String, PostgresBindings) {
        var binds = PostgresBindings()
        var n = 0
        func bind(_ val: some PostgresDynamicTypeEncodable) -> String {
            n += 1; binds.append(val); return "$\(n)"
        }

        var filterCTEs: [(name: String, sql: String)] = []

        func tokenORCTE(name: String, paramName: String, tokens: [MedicationStatementSearchQuery.TokenParam]) -> (String, String) {
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
            return (name, "SELECT DISTINCT resource_id FROM idx_token WHERE resource_type = 'MedicationStatement' AND param_name = '\(paramName)' AND (\(orClauses.joined(separator: " OR ")))")
        }

        func tokenNotCondition(paramName: String, tokens: [MedicationStatementSearchQuery.TokenParam]) -> String {
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
            return "r.id NOT IN (SELECT resource_id FROM idx_token WHERE resource_type = 'MedicationStatement' AND param_name = '\(paramName)' AND (\(orClauses.joined(separator: " OR "))))"
        }

        func refCTE(name: String, paramName: String, ref: String) -> (String, String) {
            let parts = ref.split(separator: "/")
            if parts.count == 2 {
                let refTypeP = bind(String(parts[0])); let refIdP = bind(String(parts[1]))
                return (name, "SELECT DISTINCT resource_id FROM idx_reference WHERE resource_type = 'MedicationStatement' AND param_name = '\(paramName)' AND ref_type = \(refTypeP) AND ref_id = \(refIdP)")
            } else {
                let refIdP = bind(ref)
                return (name, "SELECT DISTINCT resource_id FROM idx_reference WHERE resource_type = 'MedicationStatement' AND param_name = '\(paramName)' AND ref_id = \(refIdP)")
            }
        }

        func dateCTE(name: String, paramName: String, dp: MedicationStatementSearchQuery.DateParam) -> (String, String) {
            let startP = bind(dp.dateStart); let endP = bind(dp.dateEnd)
            let cond: String
            switch dp.prefix {
            case .eq: cond = "date_start <= \(endP) AND date_end >= \(startP)"
            case .ne: cond = "NOT (date_start <= \(endP) AND date_end >= \(startP))"
            case .lt: cond = "date_end < \(startP)"
            case .le: cond = "date_start <= \(endP)"
            case .gt: cond = "date_start > \(endP)"
            case .ge: cond = "date_end >= \(startP)"
            case .sa: cond = "date_start > \(endP)"
            case .eb: cond = "date_end < \(startP)"
            }
            return (name, "SELECT DISTINCT resource_id FROM idx_date WHERE resource_type = 'MedicationStatement' AND param_name = '\(paramName)' AND \(cond)")
        }

        // token CTEs
        if !query.status.isEmpty   { filterCTEs.append(tokenORCTE(name: "f_status",   paramName: "status",   tokens: query.status)) }
        if !query.category.isEmpty { filterCTEs.append(tokenORCTE(name: "f_category", paramName: "category", tokens: query.category)) }
        if !query.code.isEmpty     { filterCTEs.append(tokenORCTE(name: "f_code",     paramName: "code",     tokens: query.code)) }

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
                filterCTEs.append(("f_ident", "SELECT DISTINCT resource_id FROM idx_token WHERE resource_type = 'MedicationStatement' AND param_name = 'identifier' AND (\(orClauses.joined(separator: " OR ")))"))
            }
        }

        // date CTEs
        for (i, dp) in query.effective.enumerated() {
            filterCTEs.append(dateCTE(name: "f_effective\(i)", paramName: "effective", dp: dp))
        }

        // reference CTEs
        if let ref = query.subject  { filterCTEs.append(refCTE(name: "f_subject",    paramName: "subject",    ref: ref)) }
        if let ref = query.patient  { filterCTEs.append(refCTE(name: "f_patient",    paramName: "patient",    ref: ref)) }
        if let ref = query.context  { filterCTEs.append(refCTE(name: "f_context",    paramName: "context",    ref: ref)) }
        if let ref = query.source   { filterCTEs.append(refCTE(name: "f_source",     paramName: "source",     ref: ref)) }
        if let ref = query.medication { filterCTEs.append(refCTE(name: "f_medication", paramName: "medication", ref: ref)) }
        if let ref = query.partOf   { filterCTEs.append(refCTE(name: "f_partof",     paramName: "part-of",    ref: ref)) }

        // ── WHERE conditions ──────────────────────────────────────────────────

        var whereConditions = ["r.resource_type = 'MedicationStatement'", "r.deleted = false"]

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
        if !query.statusNot.isEmpty   { whereConditions.append(tokenNotCondition(paramName: "status",   tokens: query.statusNot)) }
        if !query.categoryNot.isEmpty { whereConditions.append(tokenNotCondition(paramName: "category", tokens: query.categoryNot)) }
        if !query.codeNot.isEmpty     { whereConditions.append(tokenNotCondition(paramName: "code",     tokens: query.codeNot)) }

        // :missing
        for paramName in query.missing.keys.sorted() {
            if let sub = medicationStatementMissingSubquery(param: paramName) {
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
                index: filterCTEs.count + i, sourceType: "MedicationStatement",
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
                index: i, mainType: "MedicationStatement",
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

        var cursorCondSQL = ""
        var finalSortValSQL = ""
        var sortKind = 0

        var sortKeysCTE: (name: String, sql: String)? = nil

        switch query.sort {
        case .dateAscending, .dateDescending:
            sortKeysCTE = ("sort_keys",
                "SELECT DISTINCT ON (resource_id) resource_id, date_start AS sv " +
                "FROM idx_date WHERE resource_type = 'MedicationStatement' AND param_name = 'effective' " +
                "ORDER BY resource_id, date_start ASC")
            if let cursor = query.cursor, let ts = Double(cursor.sortValue) {
                let dateP = bind(Date(timeIntervalSince1970: ts))
                let idP = bind(cursor.id)
                let op = sortIsDescending ? "<" : ">"
                cursorCondSQL = "(sort_val IS NOT NULL AND sort_val \(op) \(dateP)) OR " +
                    "(sort_val IS NOT NULL AND sort_val = \(dateP) AND id > \(idP))"
            }
            finalSortValSQL = "COALESCE(CAST(EXTRACT(EPOCH FROM p.sort_val) AS text), '')"
            sortKind = 1

        case .codeAscending, .codeDescending:
            sortKeysCTE = ("sort_keys",
                "SELECT DISTINCT ON (resource_id) resource_id, code AS sv " +
                "FROM idx_token WHERE resource_type = 'MedicationStatement' AND param_name = 'code' " +
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

        case .statusAscending, .statusDescending:
            sortKeysCTE = ("sort_keys",
                "SELECT DISTINCT ON (resource_id) resource_id, code AS sv " +
                "FROM idx_token WHERE resource_type = 'MedicationStatement' AND param_name = 'status' " +
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
                let idP = bind(cursor.sortValue)
                let op = sortIsDescending ? "<" : ">"
                cursorCondSQL = "i.id \(op) \(idP)"
            }
            finalSortValSQL = "p.id"
            sortKind = 2

        default:
            if let cursor = query.cursor, let ts = Double(cursor.sortValue) {
                let tsP = bind(Date(timeIntervalSince1970: ts))
                let idP = bind(cursor.id)
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
        cteParts.append("ids AS (\n    \(idsInner)\n  )")
        let skipTotal = query.totalMode == .none
        if !skipTotal { cteParts.append("total_count AS (\n    SELECT COUNT(*) AS n FROM ids\n  )") }
        if let skCTE = sortKeysCTE { cteParts.append("\(skCTE.name) AS (\n    \(skCTE.sql)\n  )") }
        cteParts.append("paged AS (\n    \(pagedInner)\n  )")
        let withClause = "WITH " + cteParts.joined(separator: ",\n  ")

        let totalExpr = skipTotal ? "CAST(0 AS bigint)" : "t.n"
        let fromClause = skipTotal
            ? "FROM paged p JOIN resources r ON r.resource_type = 'MedicationStatement' AND r.id = p.id AND r.version_id = p.version_id"
            : "FROM paged p CROSS JOIN total_count t JOIN resources r ON r.resource_type = 'MedicationStatement' AND r.id = p.id AND r.version_id = p.version_id"

        let sql = "\(withClause)\nSELECT p.id, p.version_id, p.last_updated, r.content, \(totalExpr), \(finalSortValSQL) AS sort_val_text\n\(fromClause)"
        return (sql, binds)
    }

    private func buildCountSQL(query: MedicationStatementSearchQuery) throws -> (String, PostgresBindings) {
        var binds = PostgresBindings()
        var n = 0
        func bind(_ val: some PostgresDynamicTypeEncodable) -> String {
            n += 1; binds.append(val); return "$\(n)"
        }

        var filterCTEs: [(name: String, sql: String)] = []

        func tokenCTE(name: String, paramName: String, tokens: [MedicationStatementSearchQuery.TokenParam]) -> (String, String) {
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
            return (name, "SELECT DISTINCT resource_id FROM idx_token WHERE resource_type = 'MedicationStatement' AND param_name = '\(paramName)' AND (\(orClauses.joined(separator: " OR ")))")
        }

        func cRefCTE(name: String, paramName: String, ref: String) -> (String, String) {
            let parts = ref.split(separator: "/")
            if parts.count == 2 {
                let refTypeP = bind(String(parts[0])); let refIdP = bind(String(parts[1]))
                return (name, "SELECT DISTINCT resource_id FROM idx_reference WHERE resource_type = 'MedicationStatement' AND param_name = '\(paramName)' AND ref_type = \(refTypeP) AND ref_id = \(refIdP)")
            } else {
                let refIdP = bind(ref)
                return (name, "SELECT DISTINCT resource_id FROM idx_reference WHERE resource_type = 'MedicationStatement' AND param_name = '\(paramName)' AND ref_id = \(refIdP)")
            }
        }

        func cDateCTE(name: String, paramName: String, dp: MedicationStatementSearchQuery.DateParam) -> (String, String) {
            let startP = bind(dp.dateStart); let endP = bind(dp.dateEnd)
            let cond: String
            switch dp.prefix {
            case .eq: cond = "date_start <= \(endP) AND date_end >= \(startP)"
            case .ne: cond = "NOT (date_start <= \(endP) AND date_end >= \(startP))"
            case .lt: cond = "date_end < \(startP)"
            case .le: cond = "date_start <= \(endP)"
            case .gt: cond = "date_start > \(endP)"
            case .ge: cond = "date_end >= \(startP)"
            case .sa: cond = "date_start > \(endP)"
            case .eb: cond = "date_end < \(startP)"
            }
            return (name, "SELECT DISTINCT resource_id FROM idx_date WHERE resource_type = 'MedicationStatement' AND param_name = '\(paramName)' AND \(cond)")
        }

        if !query.status.isEmpty   { filterCTEs.append(tokenCTE(name: "f_status",   paramName: "status",   tokens: query.status)) }
        if !query.category.isEmpty { filterCTEs.append(tokenCTE(name: "f_category", paramName: "category", tokens: query.category)) }
        if !query.code.isEmpty     { filterCTEs.append(tokenCTE(name: "f_code",     paramName: "code",     tokens: query.code)) }

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
                filterCTEs.append(("f_ident", "SELECT DISTINCT resource_id FROM idx_token WHERE resource_type = 'MedicationStatement' AND param_name = 'identifier' AND (\(orClauses.joined(separator: " OR ")))"))
            }
        }

        for (i, dp) in query.effective.enumerated() {
            filterCTEs.append(cDateCTE(name: "f_effective\(i)", paramName: "effective", dp: dp))
        }

        if let ref = query.subject    { filterCTEs.append(cRefCTE(name: "f_subject",    paramName: "subject",    ref: ref)) }
        if let ref = query.patient    { filterCTEs.append(cRefCTE(name: "f_patient",    paramName: "patient",    ref: ref)) }
        if let ref = query.context    { filterCTEs.append(cRefCTE(name: "f_context",    paramName: "context",    ref: ref)) }
        if let ref = query.source     { filterCTEs.append(cRefCTE(name: "f_source",     paramName: "source",     ref: ref)) }
        if let ref = query.medication { filterCTEs.append(cRefCTE(name: "f_medication", paramName: "medication", ref: ref)) }
        if let ref = query.partOf     { filterCTEs.append(cRefCTE(name: "f_partof",     paramName: "part-of",    ref: ref)) }

        var whereConditions = ["r.resource_type = 'MedicationStatement'", "r.deleted = false"]
        if !query.id.isEmpty {
            let phs = query.id.map { bind($0) }.joined(separator: ", ")
            whereConditions.append("r.id IN (\(phs))")
        }

        let cBindStr: (String) -> String = { bind($0) }
        let cBindDate: (Date) -> String = { bind($0) }
        for (i, chain) in query.chains.enumerated() {
            if let (name, sql) = chainFilterCTE(
                index: filterCTEs.count + i, sourceType: "MedicationStatement",
                chain: chain, bindStr: cBindStr, bindDate: cBindDate
            ) {
                filterCTEs.append((name, sql))
            }
        }

        let hBindStr: (String) -> String = { bind($0) }
        let hBindDate: (Date) -> String = { bind($0) }
        for (i, hp) in query.has.enumerated() {
            if let (name, sql) = hasFilterCTE(
                index: i, mainType: "MedicationStatement",
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
        cteParts.append("ids AS (\n    \(idsInner)\n  )")
        let withClause = "WITH " + cteParts.joined(separator: ",\n  ")
        return ("\(withClause)\nSELECT COUNT(*) FROM ids", binds)
    }

    private func medicationStatementMissingSubquery(param: String) -> String? {
        switch param {
        case "subject", "patient": return "SELECT DISTINCT resource_id FROM idx_reference WHERE resource_type = 'MedicationStatement' AND param_name IN ('subject', 'patient')"
        case "status":             return "SELECT DISTINCT resource_id FROM idx_token WHERE resource_type = 'MedicationStatement' AND param_name = 'status'"
        case "category":           return "SELECT DISTINCT resource_id FROM idx_token WHERE resource_type = 'MedicationStatement' AND param_name = 'category'"
        case "code":               return "SELECT DISTINCT resource_id FROM idx_token WHERE resource_type = 'MedicationStatement' AND param_name = 'code'"
        case "identifier":         return "SELECT DISTINCT resource_id FROM idx_token WHERE resource_type = 'MedicationStatement' AND param_name = 'identifier'"
        case "effective":          return "SELECT DISTINCT resource_id FROM idx_date WHERE resource_type = 'MedicationStatement' AND param_name = 'effective'"
        case "context":            return "SELECT DISTINCT resource_id FROM idx_reference WHERE resource_type = 'MedicationStatement' AND param_name = 'context'"
        case "source":             return "SELECT DISTINCT resource_id FROM idx_reference WHERE resource_type = 'MedicationStatement' AND param_name = 'source'"
        case "medication":         return "SELECT DISTINCT resource_id FROM idx_reference WHERE resource_type = 'MedicationStatement' AND param_name = 'medication'"
        default:                   return nil
        }
    }
}
