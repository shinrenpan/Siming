import Foundation
import Logging
import ModelsR4
import PostgresNIO

public struct PractitionerStore: Sendable {
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
        public let nextCursor: PractitionerSearchQuery.SearchCursor?
    }

    public struct DeleteResult: Sendable {
        public let versionId: Int64
        public let lastUpdated: Date
    }

    // ── Public API ────────────────────────────────────────────────────────────

    public func create(_ prac: Practitioner) async throws -> WriteResult {
        let id = UUID().uuidString.lowercased()
        return try await write(id: id, practitioner: prac, ifMatch: nil)
    }

    public func update(id: String, practitioner: Practitioner, ifMatch: Int64?) async throws -> WriteResult {
        return try await write(id: id, practitioner: practitioner, ifMatch: ifMatch)
    }

    @discardableResult
    public func delete(id: String, ifMatch: Int64?) async throws -> DeleteResult {
        try await client.withConnection { conn in
            _ = try await conn.query("BEGIN", logger: logger)
            do {
                let rows = try await conn.query(
                    """
                    SELECT version_id, deleted FROM resources
                    WHERE resource_type = 'Practitioner' AND id = \(id)
                    ORDER BY version_id DESC LIMIT 1
                    """, logger: logger)
                var currentVersion: Int64? = nil
                var isDeleted = false
                for try await (v, d) in rows.decode((Int64, Bool).self, context: .default) {
                    currentVersion = v; isDeleted = d
                }
                guard let current = currentVersion else {
                    _ = try? await conn.query("ROLLBACK", logger: logger)
                    throw FHIRServerError.notFound(resourceType: "Practitioner", id: id)
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
                    VALUES ('Practitioner', \(id), \(nextVersion), now(), '{}'::jsonb, true)
                    RETURNING last_updated
                    """, logger: logger)
                var lastUpdated = Date()
                for try await (d) in insRows.decode(Date.self, context: .default) { lastUpdated = d }

                _ = try await conn.query("DELETE FROM idx_token     WHERE resource_type = 'Practitioner' AND resource_id = \(id)", logger: logger)
                _ = try await conn.query("DELETE FROM idx_string    WHERE resource_type = 'Practitioner' AND resource_id = \(id)", logger: logger)
                _ = try await conn.query("DELETE FROM idx_date      WHERE resource_type = 'Practitioner' AND resource_id = \(id)", logger: logger)
                _ = try await conn.query("DELETE FROM idx_reference WHERE resource_type = 'Practitioner' AND resource_id = \(id)", logger: logger)
                _ = try await conn.query("DELETE FROM idx_quantity  WHERE resource_type = 'Practitioner' AND resource_id = \(id)", logger: logger)

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
                WHERE resource_type = 'Practitioner' AND id = \(id) AND version_id = \(versionId)
                """, logger: logger)
            for try await (vid, lastUpdated, content, deleted) in
                rows.decode((Int64, Date, String, Bool).self, context: .default)
            {
                if deleted { throw FHIRServerError.gone(resourceType: "Practitioner", id: id) }
                let jsonData = injectMeta(into: content, versionId: vid, lastUpdated: lastUpdated)
                return ReadResult(jsonData: jsonData, versionId: vid, lastUpdated: lastUpdated)
            }
            throw FHIRServerError.notFound(resourceType: "Practitioner", id: id)
        }
    }

    public func history(id: String) async throws -> [HistoryRawEntry] {
        try await client.withConnection { conn in
            let rows = try await conn.query(
                """
                SELECT version_id, last_updated, content, deleted
                FROM resources
                WHERE resource_type = 'Practitioner' AND id = \(id)
                ORDER BY version_id DESC
                """, logger: logger)
            var entries: [HistoryRawEntry] = []
            for try await (vid, lastUpdated, content, deleted) in
                rows.decode((Int64, Date, String, Bool).self, context: .default)
            {
                let jsonData: Data? = deleted ? nil : injectMeta(into: content, versionId: vid, lastUpdated: lastUpdated)
                entries.append(HistoryRawEntry(resourceType: "Practitioner", id: id, versionId: vid, lastUpdated: lastUpdated, jsonData: jsonData, deleted: deleted))
            }
            guard !entries.isEmpty else {
                throw FHIRServerError.notFound(resourceType: "Practitioner", id: id)
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
                    WHERE resource_type = 'Practitioner' AND last_updated >= \(since)
                    ORDER BY last_updated DESC, id, version_id DESC
                    LIMIT \(Int64(count))
                    """, logger: logger)
            } else {
                rows = try await conn.query(
                    """
                    SELECT id, version_id, last_updated, content, deleted
                    FROM resources
                    WHERE resource_type = 'Practitioner'
                    ORDER BY last_updated DESC, id, version_id DESC
                    LIMIT \(Int64(count))
                    """, logger: logger)
            }
            var entries: [HistoryRawEntry] = []
            for try await (rid, vid, lastUpdated, content, deleted) in
                rows.decode((String, Int64, Date, String, Bool).self, context: .default)
            {
                let jsonData: Data? = deleted ? nil : injectMeta(into: content, versionId: vid, lastUpdated: lastUpdated)
                entries.append(HistoryRawEntry(resourceType: "Practitioner", id: rid, versionId: vid, lastUpdated: lastUpdated, jsonData: jsonData, deleted: deleted))
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
                WHERE resource_type = 'Practitioner' AND id = \(id)
                ORDER BY version_id DESC
                LIMIT 1
                """, logger: logger)
            var found: ReadResult? = nil
            for try await (versionId, lastUpdated, content, deleted) in
                rows.decode((Int64, Date, String, Bool).self, context: .default)
            {
                if deleted { throw FHIRServerError.gone(resourceType: "Practitioner", id: id) }
                let jsonData = injectMeta(into: content, versionId: versionId, lastUpdated: lastUpdated)
                found = ReadResult(jsonData: jsonData, versionId: versionId, lastUpdated: lastUpdated)
            }
            guard let result = found else {
                throw FHIRServerError.notFound(resourceType: "Practitioner", id: id)
            }
            return result
        }
    }

    public func search(query: PractitionerSearchQuery) async throws -> SearchResult {
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

            let nextCursor: PractitionerSearchQuery.SearchCursor?
            if hasNext, let lastEntry = page.last, let lastSortVal = pageSortVals.last {
                nextCursor = PractitionerSearchQuery.SearchCursor(
                    sortValue: lastSortVal, id: lastEntry.id, descending: query.sort.isDescending)
            } else {
                nextCursor = nil
            }

            let total: Int? = query.totalMode == .none ? nil : Int(rawTotal)
            return SearchResult(entries: page, total: total, nextCursor: nextCursor)
        }
    }

    // ── Private ───────────────────────────────────────────────────────────────

    private func write(id: String, practitioner: Practitioner, ifMatch: Int64?) async throws -> WriteResult {
        try validate(practitioner)

        var prac = practitioner
        prac.id   = FHIRPrimitive(FHIRString(id))
        prac.meta = nil

        let jsonData   = try JSONEncoder().encode(prac)
        let jsonString = String(data: jsonData, encoding: .utf8)!
        let searchParams = extractPractitionerSearchParams(prac)

        return try await client.withConnection { conn in
            _ = try await conn.query("BEGIN", logger: logger)
            do {
                if let expected = ifMatch {
                    let vRows = try await conn.query(
                        """
                        SELECT version_id FROM resources
                        WHERE resource_type = 'Practitioner' AND id = \(id)
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
                    WHERE resource_type = 'Practitioner' AND id = \(id)
                    """, logger: logger)
                var nextVersion: Int64 = 1
                for try await (v) in nvRows.decode(Int64.self, context: .default) { nextVersion = v }

                let insRows = try await conn.query(
                    """
                    INSERT INTO resources
                        (resource_type, id, version_id, last_updated, content, deleted)
                    VALUES ('Practitioner', \(id), \(nextVersion), now(), \(jsonString)::jsonb, false)
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

    private func validate(_ prac: Practitioner) throws {}

    private func replaceIndexRows(conn: PostgresConnection, id: String, params: SearchParams) async throws {
        _ = try await conn.query("DELETE FROM idx_token     WHERE resource_type = 'Practitioner' AND resource_id = \(id)", logger: logger)
        _ = try await conn.query("DELETE FROM idx_string    WHERE resource_type = 'Practitioner' AND resource_id = \(id)", logger: logger)
        _ = try await conn.query("DELETE FROM idx_date      WHERE resource_type = 'Practitioner' AND resource_id = \(id)", logger: logger)
        _ = try await conn.query("DELETE FROM idx_reference WHERE resource_type = 'Practitioner' AND resource_id = \(id)", logger: logger)
        _ = try await conn.query("DELETE FROM idx_quantity  WHERE resource_type = 'Practitioner' AND resource_id = \(id)", logger: logger)

        for row in params.tokens {
            _ = try await conn.query(
                "INSERT INTO idx_token (resource_type, resource_id, param_name, system, code) VALUES ('Practitioner', \(id), \(row.paramName), \(row.system), \(row.code))",
                logger: logger)
        }
        for row in params.strings {
            _ = try await conn.query(
                "INSERT INTO idx_string (resource_type, resource_id, param_name, value) VALUES ('Practitioner', \(id), \(row.paramName), \(row.value))",
                logger: logger)
        }
        for row in params.dates {
            _ = try await conn.query(
                "INSERT INTO idx_date (resource_type, resource_id, param_name, date_start, date_end) VALUES ('Practitioner', \(id), \(row.paramName), \(row.dateStart), \(row.dateEnd))",
                logger: logger)
        }
        for row in params.references {
            _ = try await conn.query(
                "INSERT INTO idx_reference (resource_type, resource_id, param_name, ref_type, ref_id) VALUES ('Practitioner', \(id), \(row.paramName), \(row.refType), \(row.refId))",
                logger: logger)
        }
        for row in params.quantities {
            _ = try await conn.query(
                "INSERT INTO idx_quantity (resource_type, resource_id, param_name, system, code, value) VALUES ('Practitioner', \(id), \(row.paramName), \(row.system), \(row.code), \(row.value))",
                logger: logger)
        }
    }

    private func stringBindValue(_ param: PractitionerSearchQuery.StringParam) -> String {
        switch param.modifier {
        case .startsWith:      return "\(param.value)%"
        case .contains, .text: return "%\(param.value)%"
        case .exact:           return param.value
        }
    }

    private func stringFilterOp(_ param: PractitionerSearchQuery.StringParam) -> String {
        param.modifier == .exact ? "=" : "ILIKE"
    }

    private func buildSearchSQL(query: PractitionerSearchQuery) throws -> (String, PostgresBindings) {
        var binds = PostgresBindings()
        var n = 0
        func bind(_ val: some PostgresDynamicTypeEncodable) -> String {
            n += 1; binds.append(val); return "$\(n)"
        }

        var filterCTEs: [(name: String, sql: String)] = []

        // String filters
        let stringFilters: [(String, String, PractitionerSearchQuery.StringParam?)] = [
            ("f_name",    "name",             query.name),
            ("f_family",  "family",           query.family),
            ("f_given",   "given",            query.given),
            ("f_addr",    "address",          query.address),
            ("f_city",    "address-city",     query.addressCity),
            ("f_state",   "address-state",    query.addressState),
            ("f_postal",  "address-postalcode", query.addressPostalCode),
            ("f_country", "address-country",  query.addressCountry),
        ]
        for (cteName, paramName, param) in stringFilters {
            guard let param else { continue }
            let bp = bind(stringBindValue(param))
            filterCTEs.append((cteName, "SELECT DISTINCT resource_id FROM idx_string WHERE resource_type = 'Practitioner' AND param_name = '\(paramName)' AND value \(stringFilterOp(param)) \(bp)"))
        }

        // active — boolean token
        if let active = query.active {
            let p = bind(active ? "true" : "false")
            filterCTEs.append(("f_active", "SELECT DISTINCT resource_id FROM idx_token WHERE resource_type = 'Practitioner' AND param_name = 'active' AND code = \(p)"))
        }

        // gender — token OR
        if !query.gender.isEmpty {
            let phs = query.gender.map { bind($0) }.joined(separator: ", ")
            filterCTEs.append(("f_gender", "SELECT DISTINCT resource_id FROM idx_token WHERE resource_type = 'Practitioner' AND param_name = 'gender' AND code IN (\(phs))"))
        }

        // communication — token OR
        func tokenORCTE(name: String, paramName: String, tokens: [PractitionerSearchQuery.TokenParam]) -> (String, String) {
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
            return (name, "SELECT DISTINCT resource_id FROM idx_token WHERE resource_type = 'Practitioner' AND param_name = '\(paramName)' AND (\(orClauses.joined(separator: " OR ")))")
        }

        if !query.communication.isEmpty { filterCTEs.append(tokenORCTE(name: "f_comm", paramName: "communication", tokens: query.communication)) }

        // phone, email — token filters via dedicated param_name entries
        if let phone = query.phone {
            let p = bind(phone)
            filterCTEs.append(("f_phone", "SELECT DISTINCT resource_id FROM idx_token WHERE resource_type = 'Practitioner' AND param_name = 'phone' AND code = \(p)"))
        }
        if let email = query.email {
            let p = bind(email)
            filterCTEs.append(("f_email", "SELECT DISTINCT resource_id FROM idx_token WHERE resource_type = 'Practitioner' AND param_name = 'email' AND code = \(p)"))
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
                filterCTEs.append(("f_ident", "SELECT DISTINCT resource_id FROM idx_token WHERE resource_type = 'Practitioner' AND param_name = 'identifier' AND (\(orClauses.joined(separator: " OR ")))"))
            }
        }

        // ── WHERE conditions ──────────────────────────────────────────────────

        var whereConditions = ["r.resource_type = 'Practitioner'", "r.deleted = false"]

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

        // gender:not
        if !query.genderNot.isEmpty {
            let phs = query.genderNot.map { bind($0) }.joined(separator: ", ")
            whereConditions.append("r.id NOT IN (SELECT resource_id FROM idx_token WHERE resource_type = 'Practitioner' AND param_name = 'gender' AND code IN (\(phs)))")
        }

        // communication:not
        if !query.communicationNot.isEmpty {
            var orClauses: [String] = []
            for tok in query.communicationNot {
                if tok.code.isEmpty, let sys = tok.system {
                    orClauses.append("system = \(bind(sys))")
                } else {
                    let codeP = bind(tok.code); var sysCond = ""
                    if let sys = tok.system { sysCond = " AND system = \(bind(sys))" }
                    orClauses.append("(code = \(codeP)\(sysCond))")
                }
            }
            whereConditions.append("r.id NOT IN (SELECT resource_id FROM idx_token WHERE resource_type = 'Practitioner' AND param_name = 'communication' AND (\(orClauses.joined(separator: " OR "))))")
        }

        for paramName in query.missing.keys.sorted() {
            if let sub = practitionerMissingSubquery(param: paramName) {
                if query.missing[paramName] == true {
                    whereConditions.append("r.id NOT IN (\(sub))")
                } else {
                    whereConditions.append("r.id IN (\(sub))")
                }
            }
        }

        // Chained search params
        let cBindStr: (String) -> String = { bind($0) }
        let cBindDate: (Date) -> String = { bind($0) }
        for (i, chain) in query.chains.enumerated() {
            if let (name, sql) = chainFilterCTE(
                index: filterCTEs.count + i, sourceType: "Practitioner",
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
                index: i, mainType: "Practitioner",
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
                "FROM idx_string WHERE resource_type = 'Practitioner' AND param_name IN ('name', 'family') " +
                "ORDER BY resource_id, value ASC")
            if let cursor = query.cursor {
                let svP = bind(cursor.sortValue); let idP = bind(cursor.id)
                let op = sortIsDescending ? "<" : ">"
                cursorCondSQL = "(sort_val IS NOT NULL AND sort_val \(op) \(svP)) OR " +
                    "(sort_val IS NOT NULL AND sort_val = \(svP) AND id > \(idP))"
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
        cteParts.append("ids AS (\n    \(idsInner)\n  )")
        let skipTotal = query.totalMode == .none
        if !skipTotal { cteParts.append("total_count AS (\n    SELECT COUNT(*) AS n FROM ids\n  )") }
        if let skCTE = sortKeysCTE { cteParts.append("\(skCTE.name) AS (\n    \(skCTE.sql)\n  )") }
        cteParts.append("paged AS (\n    \(pagedInner)\n  )")
        let withClause = "WITH " + cteParts.joined(separator: ",\n  ")

        let totalExpr = skipTotal ? "CAST(0 AS bigint)" : "t.n"
        let fromClause = skipTotal
            ? "FROM paged p JOIN resources r ON r.resource_type = 'Practitioner' AND r.id = p.id AND r.version_id = p.version_id"
            : "FROM paged p CROSS JOIN total_count t JOIN resources r ON r.resource_type = 'Practitioner' AND r.id = p.id AND r.version_id = p.version_id"

        let sql = "\(withClause)\nSELECT p.id, p.version_id, p.last_updated, r.content, \(totalExpr), \(finalSortValSQL) AS sort_val_text\n\(fromClause)"
        return (sql, binds)
    }

    private func buildCountSQL(query: PractitionerSearchQuery) throws -> (String, PostgresBindings) {
        var binds = PostgresBindings()
        var n = 0
        func bind(_ val: some PostgresDynamicTypeEncodable) -> String {
            n += 1; binds.append(val); return "$\(n)"
        }

        var filterCTEs: [(name: String, sql: String)] = []

        let stringFilters: [(String, String, PractitionerSearchQuery.StringParam?)] = [
            ("f_name",    "name",             query.name),
            ("f_family",  "family",           query.family),
            ("f_given",   "given",            query.given),
            ("f_addr",    "address",          query.address),
            ("f_city",    "address-city",     query.addressCity),
            ("f_state",   "address-state",    query.addressState),
            ("f_postal",  "address-postalcode", query.addressPostalCode),
            ("f_country", "address-country",  query.addressCountry),
        ]
        for (cteName, paramName, param) in stringFilters {
            guard let param else { continue }
            let bp = bind(stringBindValue(param))
            filterCTEs.append((cteName, "SELECT DISTINCT resource_id FROM idx_string WHERE resource_type = 'Practitioner' AND param_name = '\(paramName)' AND value \(stringFilterOp(param)) \(bp)"))
        }

        if let active = query.active {
            let p = bind(active ? "true" : "false")
            filterCTEs.append(("f_active", "SELECT DISTINCT resource_id FROM idx_token WHERE resource_type = 'Practitioner' AND param_name = 'active' AND code = \(p)"))
        }

        if !query.gender.isEmpty {
            let phs = query.gender.map { bind($0) }.joined(separator: ", ")
            filterCTEs.append(("f_gender", "SELECT DISTINCT resource_id FROM idx_token WHERE resource_type = 'Practitioner' AND param_name = 'gender' AND code IN (\(phs))"))
        }

        if !query.communication.isEmpty {
            var orClauses: [String] = []
            for tok in query.communication {
                if tok.code.isEmpty, let sys = tok.system {
                    orClauses.append("system = \(bind(sys))")
                } else {
                    let codeP = bind(tok.code); var sysCond = ""
                    if let sys = tok.system { sysCond = " AND system = \(bind(sys))" }
                    orClauses.append("(code = \(codeP)\(sysCond))")
                }
            }
            filterCTEs.append(("f_comm", "SELECT DISTINCT resource_id FROM idx_token WHERE resource_type = 'Practitioner' AND param_name = 'communication' AND (\(orClauses.joined(separator: " OR ")))"))
        }

        if let phone = query.phone {
            let p = bind(phone)
            filterCTEs.append(("f_phone", "SELECT DISTINCT resource_id FROM idx_token WHERE resource_type = 'Practitioner' AND param_name = 'phone' AND code = \(p)"))
        }
        if let email = query.email {
            let p = bind(email)
            filterCTEs.append(("f_email", "SELECT DISTINCT resource_id FROM idx_token WHERE resource_type = 'Practitioner' AND param_name = 'email' AND code = \(p)"))
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
                filterCTEs.append(("f_ident", "SELECT DISTINCT resource_id FROM idx_token WHERE resource_type = 'Practitioner' AND param_name = 'identifier' AND (\(orClauses.joined(separator: " OR ")))"))
            }
        }

        var whereConditions = ["r.resource_type = 'Practitioner'", "r.deleted = false"]
        if !query.id.isEmpty {
            let phs = query.id.map { bind($0) }.joined(separator: ", ")
            whereConditions.append("r.id IN (\(phs))")
        }

        let cBindStr: (String) -> String = { bind($0) }
        let cBindDate: (Date) -> String = { bind($0) }
        for (i, chain) in query.chains.enumerated() {
            if let (name, sql) = chainFilterCTE(
                index: filterCTEs.count + i, sourceType: "Practitioner",
                chain: chain, bindStr: cBindStr, bindDate: cBindDate
            ) {
                filterCTEs.append((name, sql))
            }
        }

        let hBindStr: (String) -> String = { bind($0) }
        let hBindDate: (Date) -> String = { bind($0) }
        for (i, hp) in query.has.enumerated() {
            if let (name, sql) = hasFilterCTE(
                index: i, mainType: "Practitioner",
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

    private func practitionerMissingSubquery(param: String) -> String? {
        switch param {
        case "name":       return "SELECT DISTINCT resource_id FROM idx_string WHERE resource_type = 'Practitioner' AND param_name = 'name'"
        case "family":     return "SELECT DISTINCT resource_id FROM idx_string WHERE resource_type = 'Practitioner' AND param_name = 'family'"
        case "given":      return "SELECT DISTINCT resource_id FROM idx_string WHERE resource_type = 'Practitioner' AND param_name = 'given'"
        case "identifier": return "SELECT DISTINCT resource_id FROM idx_token WHERE resource_type = 'Practitioner' AND param_name = 'identifier'"
        case "active":     return "SELECT DISTINCT resource_id FROM idx_token WHERE resource_type = 'Practitioner' AND param_name = 'active'"
        case "gender":     return "SELECT DISTINCT resource_id FROM idx_token WHERE resource_type = 'Practitioner' AND param_name = 'gender'"
        case "communication": return "SELECT DISTINCT resource_id FROM idx_token WHERE resource_type = 'Practitioner' AND param_name = 'communication'"
        case "address":    return "SELECT DISTINCT resource_id FROM idx_string WHERE resource_type = 'Practitioner' AND param_name = 'address'"
        case "phone":      return "SELECT DISTINCT resource_id FROM idx_token WHERE resource_type = 'Practitioner' AND param_name = 'phone'"
        case "email":      return "SELECT DISTINCT resource_id FROM idx_token WHERE resource_type = 'Practitioner' AND param_name = 'email'"
        default:           return nil
        }
    }
}
