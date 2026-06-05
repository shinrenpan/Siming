import Foundation
import Logging
import ModelsR4
import PostgresNIO

public struct PatientStore: Sendable {
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
        public let jsonData: Data   // complete resource JSON with meta, ready to send
    }

    public struct ReadResult: Sendable {
        public let jsonData: Data   // complete resource JSON with meta, ready to send
        public let versionId: Int64
        public let lastUpdated: Date
    }

    public struct SearchResult: Sendable {
        public let entries: [RawEntry]
        public let total: Int
        public let nextCursor: PatientSearchQuery.SearchCursor?
    }

    public struct DeleteResult: Sendable {
        public let versionId: Int64
        public let lastUpdated: Date
    }

    // ── Public API ────────────────────────────────────────────────────────────

    /// POST /Patient — server assigns a new UUID as the resource id.
    public func create(_ patient: Patient) async throws -> WriteResult {
        let id = UUID().uuidString.lowercased()
        return try await write(id: id, patient: patient, ifMatch: nil)
    }

    /// PUT /Patient/:id — client provides the id; uses If-Match for optimistic locking.
    public func update(id: String, patient: Patient, ifMatch: Int64?) async throws -> WriteResult {
        return try await write(id: id, patient: patient, ifMatch: ifMatch)
    }

    /// DELETE /Patient/:id — logical delete; inserts a deleted=true version row.
    /// Returns the new version info for ETag / Last-Modified.
    /// If the resource is already deleted, returns the latest version (idempotent).
    @discardableResult
    public func delete(id: String, ifMatch: Int64?) async throws -> DeleteResult {
        try await client.withConnection { conn in
            _ = try await conn.query("BEGIN", logger: logger)
            do {
                let rows = try await conn.query(
                    """
                    SELECT version_id, deleted FROM resources
                    WHERE resource_type = 'Patient' AND id = \(id)
                    ORDER BY version_id DESC LIMIT 1
                    """, logger: logger)
                var currentVersion: Int64? = nil
                var isDeleted = false
                for try await (v, d) in rows.decode((Int64, Bool).self, context: .default) {
                    currentVersion = v
                    isDeleted = d
                }
                guard let current = currentVersion else {
                    _ = try? await conn.query("ROLLBACK", logger: logger)
                    throw FHIRServerError.notFound(resourceType: "Patient", id: id)
                }
                if isDeleted {
                    _ = try? await conn.query("ROLLBACK", logger: logger)
                    // Already deleted — idempotent, return existing version
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
                    VALUES ('Patient', \(id), \(nextVersion), now(), '{}'::jsonb, true)
                    RETURNING last_updated
                    """, logger: logger)
                var lastUpdated = Date()
                for try await (d) in insRows.decode(Date.self, context: .default) { lastUpdated = d }

                _ = try await conn.query("DELETE FROM idx_token     WHERE resource_type = 'Patient' AND resource_id = \(id)", logger: logger)
                _ = try await conn.query("DELETE FROM idx_string    WHERE resource_type = 'Patient' AND resource_id = \(id)", logger: logger)
                _ = try await conn.query("DELETE FROM idx_date      WHERE resource_type = 'Patient' AND resource_id = \(id)", logger: logger)
                _ = try await conn.query("DELETE FROM idx_reference WHERE resource_type = 'Patient' AND resource_id = \(id)", logger: logger)
                _ = try await conn.query("DELETE FROM idx_quantity  WHERE resource_type = 'Patient' AND resource_id = \(id)", logger: logger)

                _ = try await conn.query("COMMIT", logger: logger)
                return DeleteResult(versionId: nextVersion, lastUpdated: lastUpdated)
            } catch {
                _ = try? await conn.query("ROLLBACK", logger: logger)
                throw error
            }
        }
    }

    /// GET /Patient/:id/_history/:vid — returns exact stored version; 410 if that version is a delete marker.
    public func vread(id: String, versionId: Int64) async throws -> ReadResult {
        try await client.withConnection { conn in
            let rows = try await conn.query(
                """
                SELECT version_id, last_updated, content, deleted
                FROM resources
                WHERE resource_type = 'Patient' AND id = \(id) AND version_id = \(versionId)
                """, logger: logger)
            for try await (vid, lastUpdated, content, deleted) in
                rows.decode((Int64, Date, String, Bool).self, context: .default)
            {
                if deleted { throw FHIRServerError.gone(resourceType: "Patient", id: id) }
                let jsonData = injectMeta(into: content, versionId: vid, lastUpdated: lastUpdated)
                return ReadResult(jsonData: jsonData, versionId: vid, lastUpdated: lastUpdated)
            }
            throw FHIRServerError.notFound(resourceType: "Patient", id: id)
        }
    }

    /// GET /Patient/:id/_history — all versions newest-first; 404 if id never existed.
    public func history(id: String) async throws -> [HistoryRawEntry] {
        try await client.withConnection { conn in
            let rows = try await conn.query(
                """
                SELECT version_id, last_updated, content, deleted
                FROM resources
                WHERE resource_type = 'Patient' AND id = \(id)
                ORDER BY version_id DESC
                """, logger: logger)
            var entries: [HistoryRawEntry] = []
            for try await (vid, lastUpdated, content, deleted) in
                rows.decode((Int64, Date, String, Bool).self, context: .default)
            {
                let jsonData: Data? = deleted ? nil : injectMeta(into: content, versionId: vid, lastUpdated: lastUpdated)
                entries.append(HistoryRawEntry(versionId: vid, lastUpdated: lastUpdated, jsonData: jsonData, deleted: deleted))
            }
            guard !entries.isEmpty else {
                throw FHIRServerError.notFound(resourceType: "Patient", id: id)
            }
            return entries
        }
    }

    /// GET /Patient/:id — returns the current (highest version_id) non-deleted row.
    public func read(id: String) async throws -> ReadResult {
        try await client.withConnection { conn in
            let rows = try await conn.query(
                """
                SELECT version_id, last_updated, content, deleted
                FROM resources
                WHERE resource_type = 'Patient' AND id = \(id)
                ORDER BY version_id DESC
                LIMIT 1
                """,
                logger: logger
            )

            var found: ReadResult? = nil
            for try await (versionId, lastUpdated, content, deleted) in
                rows.decode((Int64, Date, String, Bool).self, context: .default)
            {
                if deleted {
                    throw FHIRServerError.gone(resourceType: "Patient", id: id)
                }
                let jsonData = injectMeta(into: content, versionId: versionId, lastUpdated: lastUpdated)
                found = ReadResult(jsonData: jsonData, versionId: versionId, lastUpdated: lastUpdated)
            }

            guard let result = found else {
                throw FHIRServerError.notFound(resourceType: "Patient", id: id)
            }
            return result
        }
    }

    /// GET /Patient — search with optional name/identifier/birthdate filters + cursor pagination.
    public func search(query: PatientSearchQuery) async throws -> SearchResult {
        if query.count == 0 {
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
            let pgQuery = PostgresQuery(unsafeSQL: sql, binds: binds)
            let rows = try await conn.query(pgQuery, logger: logger)

            var results: [RawEntry] = []
            var total = 0
            for try await (id, versionId, lastUpdated, content, rowTotal) in
                rows.decode((String, Int64, Date, String, Int64).self, context: .default)
            {
                total = Int(rowTotal)
                let jsonData = injectMeta(into: content, versionId: versionId, lastUpdated: lastUpdated)
                results.append(RawEntry(id: id, versionId: versionId, lastUpdated: lastUpdated, jsonWithMeta: jsonData))
            }

            let pageSize = min(query.count, results.count)
            let hasNext = results.count > query.count
            let page = Array(results.prefix(pageSize))
            let descending = (query.sort == .lastUpdatedDescending)

            let nextCursor: PatientSearchQuery.SearchCursor? = hasNext ? page.last.map { last in
                PatientSearchQuery.SearchCursor(lastUpdated: last.lastUpdated, id: last.id, descending: descending)
            } : nil

            return SearchResult(entries: page, total: total, nextCursor: nextCursor)
        }
    }

    // ── Private ───────────────────────────────────────────────────────────────

    private func write(id: String, patient: Patient, ifMatch: Int64?) async throws -> WriteResult {
        // Validation hook — empty now; add profile validation here in the future.
        // This call is one of the three open doors and MUST remain in the write path.
        try validate(patient)

        // Prepare the patient for storage: server owns id and meta.
        var p = patient
        p.id = FHIRPrimitive(FHIRString(id))
        p.meta = nil  // meta is reconstructed from the resources row on every read

        let jsonData = try JSONEncoder().encode(p)
        let jsonString = String(data: jsonData, encoding: .utf8)!
        let searchParams = extractPatientSearchParams(p)

        return try await client.withConnection { conn in
            _ = try await conn.query("BEGIN", logger: logger)

            do {
                // If-Match: verify current version equals expected before writing.
                if let expected = ifMatch {
                    let vRows = try await conn.query(
                        """
                        SELECT version_id FROM resources
                        WHERE resource_type = 'Patient' AND id = \(id)
                        ORDER BY version_id DESC LIMIT 1
                        """,
                        logger: logger
                    )
                    var current: Int64? = nil
                    for try await (v) in vRows.decode(Int64.self, context: .default) {
                        current = v
                    }
                    guard current == expected else {
                        throw FHIRServerError.versionConflict(id: id, expected: expected, actual: current)
                    }
                }

                // Compute next version_id (MAX + 1, 1 if no existing rows).
                let nvRows = try await conn.query(
                    """
                    SELECT COALESCE(MAX(version_id), 0) + 1
                    FROM resources
                    WHERE resource_type = 'Patient' AND id = \(id)
                    """,
                    logger: logger
                )
                var nextVersion: Int64 = 1
                for try await (v) in nvRows.decode(Int64.self, context: .default) {
                    nextVersion = v
                }

                // Insert the new version row.
                let insRows = try await conn.query(
                    """
                    INSERT INTO resources
                        (resource_type, id, version_id, last_updated, content, deleted)
                    VALUES ('Patient', \(id), \(nextVersion), now(), \(jsonString)::jsonb, false)
                    RETURNING last_updated
                    """,
                    logger: logger
                )
                var lastUpdated = Date()
                for try await (d) in insRows.decode(Date.self, context: .default) {
                    lastUpdated = d
                }

                // Replace all index rows for this resource.
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

    /// Validation hook. No-op until profile validation is added.
    private func validate(_ patient: Patient) throws {}

    /// Delete all existing index rows for this resource, then bulk-insert the new ones.
    private func replaceIndexRows(conn: PostgresConnection, id: String, params: SearchParams) async throws {
        _ = try await conn.query("DELETE FROM idx_token     WHERE resource_type = 'Patient' AND resource_id = \(id)", logger: logger)
        _ = try await conn.query("DELETE FROM idx_string    WHERE resource_type = 'Patient' AND resource_id = \(id)", logger: logger)
        _ = try await conn.query("DELETE FROM idx_date      WHERE resource_type = 'Patient' AND resource_id = \(id)", logger: logger)
        _ = try await conn.query("DELETE FROM idx_reference WHERE resource_type = 'Patient' AND resource_id = \(id)", logger: logger)
        _ = try await conn.query("DELETE FROM idx_quantity  WHERE resource_type = 'Patient' AND resource_id = \(id)", logger: logger)

        for row in params.tokens {
            _ = try await conn.query(
                "INSERT INTO idx_token (resource_type, resource_id, param_name, system, code) VALUES ('Patient', \(id), \(row.paramName), \(row.system), \(row.code))",
                logger: logger
            )
        }
        for row in params.strings {
            _ = try await conn.query(
                "INSERT INTO idx_string (resource_type, resource_id, param_name, value) VALUES ('Patient', \(id), \(row.paramName), \(row.value))",
                logger: logger
            )
        }
        for row in params.dates {
            _ = try await conn.query(
                "INSERT INTO idx_date (resource_type, resource_id, param_name, date_start, date_end) VALUES ('Patient', \(id), \(row.paramName), \(row.dateStart), \(row.dateEnd))",
                logger: logger
            )
        }
        for row in params.references {
            _ = try await conn.query(
                "INSERT INTO idx_reference (resource_type, resource_id, param_name, ref_type, ref_id) VALUES ('Patient', \(id), \(row.paramName), \(row.refType), \(row.refId))",
                logger: logger
            )
        }
    }

    private func buildSearchSQL(query: PatientSearchQuery) throws -> (String, PostgresBindings) {
        var binds = PostgresBindings()
        var n = 0
        func bind(_ val: some PostgresDynamicTypeEncodable) -> String {
            n += 1; binds.append(val); return "$\(n)"
        }

        var filterCTEs: [(name: String, sql: String)] = []

        // name — starts-with (default), :contains, or :exact
        if let nameParam = query.name {
            let (bindVal, op): (String, String)
            switch nameParam.modifier {
            case .startsWith: bindVal = "\(nameParam.value)%"; op = "ILIKE"
            case .contains:   bindVal = "%\(nameParam.value)%"; op = "ILIKE"
            case .exact:      bindVal = nameParam.value; op = "="
            }
            let p = bind(bindVal)
            filterCTEs.append(("f_name", """
                SELECT DISTINCT resource_id FROM idx_string
                WHERE resource_type = 'Patient' AND param_name = 'name' AND value \(op) \(p)
                """))
        }

        // identifier — token OR (comma-separated values become OR clauses)
        if !query.identifier.isEmpty {
            var orClauses: [String] = []
            for ident in query.identifier {
                let codeP = bind(ident.code)
                var sysCond = ""
                switch ident.systemFilter {
                case .any: break
                case .specific(nil): sysCond = " AND system IS NULL"
                case .specific(let sys?): sysCond = " AND system = \(bind(sys))"
                }
                orClauses.append("(code = \(codeP)\(sysCond))")
            }
            filterCTEs.append(("f_ident", """
                SELECT DISTINCT resource_id FROM idx_token
                WHERE resource_type = 'Patient' AND param_name = 'identifier'
                  AND (\(orClauses.joined(separator: " OR ")))
                """))
        }

        // birthdate — date range; sa/eb for period semantics
        for (i, bd) in query.birthdate.enumerated() {
            let dateP = bind(bd.date)
            let cond: String
            switch bd.prefix {
            case .eq: cond = "date_start <= \(dateP) AND date_end >= \(dateP)"
            case .ne: cond = "NOT (date_start <= \(dateP) AND date_end >= \(dateP))"
            case .lt: cond = "date_start < \(dateP)"
            case .le: cond = "date_start <= \(dateP)"
            case .gt: cond = "date_end > \(dateP)"
            case .ge: cond = "date_end >= \(dateP)"
            case .sa: cond = "date_start > \(dateP)"   // period starts after
            case .eb: cond = "date_end < \(dateP)"     // period ends before
            }
            filterCTEs.append(("f_date\(i)", """
                SELECT DISTINCT resource_id FROM idx_date
                WHERE resource_type = 'Patient' AND param_name = 'birthdate' AND \(cond)
                """))
        }

        // ── `ids` CTE — _id and _lastUpdated go directly into WHERE ──────────

        var whereConditions = ["r.resource_type = 'Patient'", "r.deleted = false"]

        if !query.id.isEmpty {
            let phs = query.id.map { bind($0) }.joined(separator: ", ")
            whereConditions.append("r.id IN (\(phs))")
        }
        for lu in query.lastUpdated {
            let tsP = bind(lu.date)
            let cond: String
            switch lu.prefix {
            case .eq: cond = "r.last_updated = \(tsP)"
            case .ne: cond = "r.last_updated != \(tsP)"
            case .lt: cond = "r.last_updated < \(tsP)"
            case .le: cond = "r.last_updated <= \(tsP)"
            case .gt: cond = "r.last_updated > \(tsP)"
            case .ge: cond = "r.last_updated >= \(tsP)"
            case .sa: cond = "r.last_updated > \(tsP)"
            case .eb: cond = "r.last_updated < \(tsP)"
            }
            whereConditions.append(cond)
        }

        var fromLines = ["FROM resources r"]
        for cte in filterCTEs {
            fromLines.append("JOIN \(cte.name) ON \(cte.name).resource_id = r.id")
        }
        fromLines.append("WHERE " + whereConditions.joined(separator: " AND "))
        fromLines.append("ORDER BY r.id, r.version_id DESC")

        let idsInner = (["SELECT DISTINCT ON (r.id) r.id, r.version_id, r.last_updated"]
            + fromLines).joined(separator: "\n      ")

        // ── `paged` CTE ───────────────────────────────────────────────────────

        var cursorCond = ""
        if let cursor = query.cursor {
            let tsP = bind(cursor.lastUpdated)
            let idP = bind(cursor.id)
            if cursor.descending {
                cursorCond = "WHERE (i.last_updated < \(tsP) OR (i.last_updated = \(tsP) AND i.id > \(idP)))\n  "
            } else {
                cursorCond = "WHERE (i.last_updated > \(tsP) OR (i.last_updated = \(tsP) AND i.id > \(idP)))\n  "
            }
        }

        let descending = (query.sort == .lastUpdatedDescending)
        let orderSQL = "ORDER BY i.last_updated \(descending ? "DESC" : "ASC"), i.id ASC"
        let limitP = bind(Int64(query.count + 1))

        let pagedInner = """
            SELECT i.id, i.version_id, i.last_updated
            FROM ids i
            \(cursorCond)\(orderSQL)
            LIMIT \(limitP)
            """

        var cteParts = filterCTEs.map { "\($0.name) AS (\n    \($0.sql)\n  )" }
        cteParts.append("ids AS (\n    \(idsInner)\n  )")
        cteParts.append("total_count AS (\n    SELECT COUNT(*) AS n FROM ids\n  )")
        cteParts.append("paged AS (\n    \(pagedInner)\n  )")
        let withClause = "WITH " + cteParts.joined(separator: ",\n  ")

        let sql = """
            \(withClause)
            SELECT p.id, p.version_id, p.last_updated, r.content, t.n
            FROM paged p
            CROSS JOIN total_count t
            JOIN resources r ON r.resource_type = 'Patient'
              AND r.id = p.id AND r.version_id = p.version_id
            """
        return (sql, binds)
    }

    private func buildCountSQL(query: PatientSearchQuery) throws -> (String, PostgresBindings) {
        var binds = PostgresBindings()
        var n = 0
        func bind(_ val: some PostgresDynamicTypeEncodable) -> String {
            n += 1; binds.append(val); return "$\(n)"
        }

        var filterCTEs: [(name: String, sql: String)] = []

        if let nameParam = query.name {
            let (bindVal, op): (String, String)
            switch nameParam.modifier {
            case .startsWith: bindVal = "\(nameParam.value)%"; op = "ILIKE"
            case .contains:   bindVal = "%\(nameParam.value)%"; op = "ILIKE"
            case .exact:      bindVal = nameParam.value; op = "="
            }
            let p = bind(bindVal)
            filterCTEs.append(("f_name",
                "SELECT DISTINCT resource_id FROM idx_string WHERE resource_type = 'Patient' AND param_name = 'name' AND value \(op) \(p)"))
        }
        if !query.identifier.isEmpty {
            var orClauses: [String] = []
            for ident in query.identifier {
                let codeP = bind(ident.code)
                var sysCond = ""
                switch ident.systemFilter {
                case .any: break
                case .specific(nil): sysCond = " AND system IS NULL"
                case .specific(let sys?): sysCond = " AND system = \(bind(sys))"
                }
                orClauses.append("(code = \(codeP)\(sysCond))")
            }
            filterCTEs.append(("f_ident",
                "SELECT DISTINCT resource_id FROM idx_token WHERE resource_type = 'Patient' AND param_name = 'identifier' AND (\(orClauses.joined(separator: " OR ")))"))
        }
        for (i, bd) in query.birthdate.enumerated() {
            let dateP = bind(bd.date)
            let cond: String
            switch bd.prefix {
            case .eq: cond = "date_start <= \(dateP) AND date_end >= \(dateP)"
            case .ne: cond = "NOT (date_start <= \(dateP) AND date_end >= \(dateP))"
            case .lt: cond = "date_start < \(dateP)"
            case .le: cond = "date_start <= \(dateP)"
            case .gt: cond = "date_end > \(dateP)"
            case .ge: cond = "date_end >= \(dateP)"
            case .sa: cond = "date_start > \(dateP)"
            case .eb: cond = "date_end < \(dateP)"
            }
            filterCTEs.append(("f_date\(i)",
                "SELECT DISTINCT resource_id FROM idx_date WHERE resource_type = 'Patient' AND param_name = 'birthdate' AND \(cond)"))
        }

        var whereConditions = ["r.resource_type = 'Patient'", "r.deleted = false"]
        if !query.id.isEmpty {
            let phs = query.id.map { bind($0) }.joined(separator: ", ")
            whereConditions.append("r.id IN (\(phs))")
        }
        for lu in query.lastUpdated {
            let tsP = bind(lu.date)
            let cond: String
            switch lu.prefix {
            case .eq: cond = "r.last_updated = \(tsP)"
            case .ne: cond = "r.last_updated != \(tsP)"
            case .lt: cond = "r.last_updated < \(tsP)"
            case .le: cond = "r.last_updated <= \(tsP)"
            case .gt: cond = "r.last_updated > \(tsP)"
            case .ge: cond = "r.last_updated >= \(tsP)"
            case .sa: cond = "r.last_updated > \(tsP)"
            case .eb: cond = "r.last_updated < \(tsP)"
            }
            whereConditions.append(cond)
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

}
