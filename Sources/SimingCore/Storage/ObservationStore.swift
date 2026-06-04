import Foundation
import Logging
import ModelsR4
import PostgresNIO

public struct ObservationStore: Sendable {
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
        public let observation: Observation
    }

    public struct ReadResult: Sendable {
        public let observation: Observation
        public let versionId: Int64
        public let lastUpdated: Date
    }

    public struct SearchResult: Sendable {
        public let observations: [ReadResult]
        public let total: Int
        public let nextCursor: ObservationSearchQuery.SearchCursor?
    }

    // ── Public API ────────────────────────────────────────────────────────────

    public func create(_ obs: Observation) async throws -> WriteResult {
        let id = UUID().uuidString.lowercased()
        return try await write(id: id, observation: obs, ifMatch: nil)
    }

    public func update(id: String, observation: Observation, ifMatch: Int64?) async throws -> WriteResult {
        return try await write(id: id, observation: observation, ifMatch: ifMatch)
    }

    public func read(id: String) async throws -> ReadResult {
        try await client.withConnection { conn in
            let rows = try await conn.query(
                """
                SELECT version_id, last_updated, content, deleted
                FROM resources
                WHERE resource_type = 'Observation' AND id = \(id)
                ORDER BY version_id DESC
                LIMIT 1
                """,
                logger: logger
            )

            var found: ReadResult? = nil
            for try await (versionId, lastUpdated, content, deleted) in
                rows.decode((Int64, Date, String, Bool).self, context: .default)
            {
                if deleted { throw FHIRServerError.gone(resourceType: "Observation", id: id) }
                let data = Data(content.utf8)
                var obs = try JSONDecoder().decode(Observation.self, from: data)
                applyMeta(to: &obs, versionId: versionId, lastUpdated: lastUpdated)
                found = ReadResult(observation: obs, versionId: versionId, lastUpdated: lastUpdated)
            }

            guard let result = found else {
                throw FHIRServerError.notFound(resourceType: "Observation", id: id)
            }
            return result
        }
    }

    public func search(query: ObservationSearchQuery) async throws -> SearchResult {
        try await client.withConnection { conn in
            let (sql, binds) = try buildSearchSQL(query: query)
            let pgQuery = PostgresQuery(unsafeSQL: sql, binds: binds)
            let rows = try await conn.query(pgQuery, logger: logger)

            var results: [ReadResult] = []
            var total = 0
            for try await (id, versionId, lastUpdated, content, rowTotal) in
                rows.decode((String, Int64, Date, String, Int64).self, context: .default)
            {
                total = Int(rowTotal)
                let data = Data(content.utf8)
                var obs = try JSONDecoder().decode(Observation.self, from: data)
                obs.id = FHIRPrimitive(FHIRString(id))
                applyMeta(to: &obs, versionId: versionId, lastUpdated: lastUpdated)
                results.append(ReadResult(observation: obs, versionId: versionId, lastUpdated: lastUpdated))
            }

            let pageSize = min(query.count, results.count)
            let hasNext  = results.count > query.count
            let page     = Array(results.prefix(pageSize))
            let descending = (query.sort == .lastUpdatedDescending)

            let nextCursor: ObservationSearchQuery.SearchCursor? = hasNext ? page.last.flatMap { last in
                guard let id = last.observation.id?.value?.string else { return nil }
                return ObservationSearchQuery.SearchCursor(
                    lastUpdated: last.lastUpdated, id: id, descending: descending)
            } : nil

            return SearchResult(observations: page, total: total, nextCursor: nextCursor)
        }
    }

    // ── Private ───────────────────────────────────────────────────────────────

    private func write(id: String, observation: Observation, ifMatch: Int64?) async throws -> WriteResult {
        // Validation hook — keep this call; it's one of the three open doors.
        try validate(observation)

        var obs = observation
        obs.id   = FHIRPrimitive(FHIRString(id))
        obs.meta = nil

        let jsonData   = try JSONEncoder().encode(obs)
        let jsonString = String(data: jsonData, encoding: .utf8)!
        let searchParams = extractObservationSearchParams(obs)

        return try await client.withConnection { conn in
            _ = try await conn.query("BEGIN", logger: logger)
            do {
                if let expected = ifMatch {
                    let vRows = try await conn.query(
                        """
                        SELECT version_id FROM resources
                        WHERE resource_type = 'Observation' AND id = \(id)
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
                    WHERE resource_type = 'Observation' AND id = \(id)
                    """, logger: logger)
                var nextVersion: Int64 = 1
                for try await (v) in nvRows.decode(Int64.self, context: .default) { nextVersion = v }

                let insRows = try await conn.query(
                    """
                    INSERT INTO resources
                        (resource_type, id, version_id, last_updated, content, deleted)
                    VALUES ('Observation', \(id), \(nextVersion), now(), \(jsonString)::jsonb, false)
                    RETURNING last_updated
                    """, logger: logger)
                var lastUpdated = Date()
                for try await (d) in insRows.decode(Date.self, context: .default) { lastUpdated = d }

                try await replaceIndexRows(conn: conn, id: id, params: searchParams)

                _ = try await conn.query("COMMIT", logger: logger)

                applyMeta(to: &obs, versionId: nextVersion, lastUpdated: lastUpdated)
                return WriteResult(id: id, versionId: nextVersion, lastUpdated: lastUpdated, observation: obs)
            } catch {
                _ = try? await conn.query("ROLLBACK", logger: logger)
                throw error
            }
        }
    }

    private func validate(_ obs: Observation) throws {}

    private func replaceIndexRows(conn: PostgresConnection, id: String, params: SearchParams) async throws {
        _ = try await conn.query("DELETE FROM idx_token     WHERE resource_type = 'Observation' AND resource_id = \(id)", logger: logger)
        _ = try await conn.query("DELETE FROM idx_string    WHERE resource_type = 'Observation' AND resource_id = \(id)", logger: logger)
        _ = try await conn.query("DELETE FROM idx_date      WHERE resource_type = 'Observation' AND resource_id = \(id)", logger: logger)
        _ = try await conn.query("DELETE FROM idx_reference WHERE resource_type = 'Observation' AND resource_id = \(id)", logger: logger)
        _ = try await conn.query("DELETE FROM idx_quantity  WHERE resource_type = 'Observation' AND resource_id = \(id)", logger: logger)

        for row in params.tokens {
            _ = try await conn.query(
                "INSERT INTO idx_token (resource_type, resource_id, param_name, system, code) VALUES ('Observation', \(id), \(row.paramName), \(row.system), \(row.code))",
                logger: logger)
        }
        for row in params.strings {
            _ = try await conn.query(
                "INSERT INTO idx_string (resource_type, resource_id, param_name, value) VALUES ('Observation', \(id), \(row.paramName), \(row.value))",
                logger: logger)
        }
        for row in params.dates {
            _ = try await conn.query(
                "INSERT INTO idx_date (resource_type, resource_id, param_name, date_start, date_end) VALUES ('Observation', \(id), \(row.paramName), \(row.dateStart), \(row.dateEnd))",
                logger: logger)
        }
        for row in params.references {
            _ = try await conn.query(
                "INSERT INTO idx_reference (resource_type, resource_id, param_name, ref_type, ref_id) VALUES ('Observation', \(id), \(row.paramName), \(row.refType), \(row.refId))",
                logger: logger)
        }
        for row in params.quantities {
            _ = try await conn.query(
                "INSERT INTO idx_quantity (resource_type, resource_id, param_name, system, code, value) VALUES ('Observation', \(id), \(row.paramName), \(row.system), \(row.code), \(row.value))",
                logger: logger)
        }
    }

    private func buildSearchSQL(query: ObservationSearchQuery) throws -> (String, PostgresBindings) {
        var binds = PostgresBindings()
        var n = 0

        func bind(_ val: some PostgresDynamicTypeEncodable) -> String {
            n += 1; binds.append(val); return "$\(n)"
        }

        var filterCTEs: [(name: String, sql: String)] = []

        // subject / patient — idx_reference lookup
        if let subject = query.subject {
            let parts = subject.split(separator: "/")
            if parts.count == 2 {
                let refTypeP = bind(String(parts[0]))
                let refIdP   = bind(String(parts[1]))
                filterCTEs.append(("f_subject", """
                    SELECT DISTINCT resource_id FROM idx_reference
                    WHERE resource_type = 'Observation' AND param_name = 'subject'
                      AND ref_type = \(refTypeP) AND ref_id = \(refIdP)
                    """))
            } else {
                let refIdP = bind(subject)
                filterCTEs.append(("f_subject", """
                    SELECT DISTINCT resource_id FROM idx_reference
                    WHERE resource_type = 'Observation' AND param_name = 'subject'
                      AND ref_id = \(refIdP)
                    """))
            }
        }

        // code — idx_token
        if let code = query.code {
            let codeP = bind(code.code)
            var sysCond = ""
            if let sys = code.system { sysCond = " AND system = \(bind(sys))" }
            filterCTEs.append(("f_code", """
                SELECT DISTINCT resource_id FROM idx_token
                WHERE resource_type = 'Observation' AND param_name = 'code'
                  AND code = \(codeP)\(sysCond)
                """))
        }

        // status — idx_token (exact match, no system needed)
        if let status = query.status {
            let statusP = bind(status)
            filterCTEs.append(("f_status", """
                SELECT DISTINCT resource_id FROM idx_token
                WHERE resource_type = 'Observation' AND param_name = 'status'
                  AND code = \(statusP)
                """))
        }

        // category — idx_token
        if let cat = query.category {
            let codeP = bind(cat.code)
            var sysCond = ""
            if let sys = cat.system { sysCond = " AND system = \(bind(sys))" }
            filterCTEs.append(("f_category", """
                SELECT DISTINCT resource_id FROM idx_token
                WHERE resource_type = 'Observation' AND param_name = 'category'
                  AND code = \(codeP)\(sysCond)
                """))
        }

        // date — idx_date range (same prefix logic as Patient birthdate)
        for (i, dp) in query.date.enumerated() {
            let dateP = bind(dp.date)
            let cond: String
            switch dp.prefix {
            case .eq: cond = "date_start <= \(dateP) AND date_end >= \(dateP)"
            case .ne: cond = "NOT (date_start <= \(dateP) AND date_end >= \(dateP))"
            case .lt: cond = "date_start < \(dateP)"
            case .le: cond = "date_start <= \(dateP)"
            case .gt: cond = "date_end > \(dateP)"
            case .ge: cond = "date_end >= \(dateP)"
            }
            filterCTEs.append(("f_date\(i)", """
                SELECT DISTINCT resource_id FROM idx_date
                WHERE resource_type = 'Observation' AND param_name = 'date' AND \(cond)
                """))
        }

        // Build current CTE with filter JOINs
        var fromLines = ["FROM resources r"]
        for cte in filterCTEs {
            fromLines.append("JOIN \(cte.name) ON \(cte.name).resource_id = r.id")
        }
        fromLines.append("WHERE r.resource_type = 'Observation' AND r.deleted = false")
        fromLines.append("ORDER BY r.id, r.version_id DESC")

        let currentInner = (["SELECT DISTINCT ON (r.id) r.id, r.version_id, r.last_updated, r.content"]
            + fromLines).joined(separator: "\n      ")

        // Cursor condition
        var outerWhere: [String] = []
        if let cursor = query.cursor {
            let tsP = bind(cursor.lastUpdated)
            let idP = bind(cursor.id)
            if cursor.descending {
                outerWhere.append("(c.last_updated < \(tsP) OR (c.last_updated = \(tsP) AND c.id > \(idP)))")
            } else {
                outerWhere.append("(c.last_updated > \(tsP) OR (c.last_updated = \(tsP) AND c.id > \(idP)))")
            }
        }

        var cteParts = filterCTEs.map { "\($0.name) AS (\n    \($0.sql)\n  )" }
        cteParts.append("current AS (\n    \(currentInner)\n  )")
        let withClause = "WITH " + cteParts.joined(separator: ",\n  ")

        let whereSQL   = outerWhere.isEmpty ? "" : "WHERE " + outerWhere.joined(separator: "\n  AND ")
        let descending = (query.sort == .lastUpdatedDescending)
        let orderSQL   = "ORDER BY c.last_updated \(descending ? "DESC" : "ASC"), c.id ASC"
        let limitP     = bind(Int64(query.count + 1))

        let sql = """
            \(withClause)
            SELECT c.id, c.version_id, c.last_updated, c.content, COUNT(*) OVER () AS total
            FROM current c
            \(whereSQL)
            \(orderSQL)
            LIMIT \(limitP)
            """
        return (sql, binds)
    }

    private func applyMeta(to obs: inout Observation, versionId: Int64, lastUpdated: Date) {
        var meta = obs.meta ?? Meta()
        meta.versionId = FHIRPrimitive(FHIRString(String(versionId)))
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let instantStr = formatter.string(from: lastUpdated)
        if let instant = try? Instant(instantStr) {
            meta.lastUpdated = FHIRPrimitive(instant)
        }
        obs.meta = meta
    }
}
