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
        public let patient: Patient  // with id + meta set by server
    }

    public struct ReadResult: Sendable {
        public let patient: Patient  // with id + meta set from resources row
        public let versionId: Int64
        public let lastUpdated: Date
    }

    public struct SearchResult: Sendable {
        public let patients: [ReadResult]
        public let total: Int          // total matching across all pages
        public let nextCursor: PatientSearchQuery.SearchCursor?
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
                let data = Data(content.utf8)
                var p = try JSONDecoder().decode(Patient.self, from: data)
                applyMeta(to: &p, versionId: versionId, lastUpdated: lastUpdated)
                found = ReadResult(patient: p, versionId: versionId, lastUpdated: lastUpdated)
            }

            guard let result = found else {
                throw FHIRServerError.notFound(resourceType: "Patient", id: id)
            }
            return result
        }
    }

    /// GET /Patient — search with optional name/identifier/birthdate filters + cursor pagination.
    public func search(query: PatientSearchQuery) async throws -> SearchResult {
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
                var p = try JSONDecoder().decode(Patient.self, from: data)
                p.id = FHIRPrimitive(FHIRString(id))
                applyMeta(to: &p, versionId: versionId, lastUpdated: lastUpdated)
                results.append(ReadResult(patient: p, versionId: versionId, lastUpdated: lastUpdated))
            }

            // Fetched count+1; the extra row means there's a next page.
            let pageSize = min(query.count, results.count)
            let hasNext = results.count > query.count
            let page = Array(results.prefix(pageSize))
            let descending = (query.sort == .lastUpdatedDescending)

            let nextCursor: PatientSearchQuery.SearchCursor? = hasNext ? page.last.flatMap { last in
                guard let id = last.patient.id?.value?.string else { return nil }
                return PatientSearchQuery.SearchCursor(lastUpdated: last.lastUpdated, id: id, descending: descending)
            } : nil

            return SearchResult(patients: page, total: total, nextCursor: nextCursor)
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

                // Build the response patient with server-assigned meta.
                applyMeta(to: &p, versionId: nextVersion, lastUpdated: lastUpdated)
                return WriteResult(id: id, versionId: nextVersion, lastUpdated: lastUpdated, patient: p)

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

    /// Builds the parameterised search SQL for GET /Patient.
    /// Returns (unsafeSQL, binds) ready for PostgresQuery(unsafeSQL:binds:).
    ///
    /// Strategy: each active filter becomes a pre-filter CTE that selects matching
    /// resource_ids from the appropriate index table. These CTEs are then JOIN-ed into
    /// the `current` CTE so PostgreSQL only materialises the matching rows — instead of
    /// scanning all resources and running a correlated EXISTS per row.
    private func buildSearchSQL(query: PatientSearchQuery) throws -> (String, PostgresBindings) {
        var binds = PostgresBindings()
        var n = 0

        func bind(_ val: some PostgresDynamicTypeEncodable) -> String {
            n += 1; binds.append(val); return "$\(n)"
        }

        // ── Build one pre-filter CTE per active search param ──────────────────

        // Each entry: (cte_name, inner_sql)
        var filterCTEs: [(name: String, sql: String)] = []

        if let name = query.name {
            let p = bind("%\(name)%")
            filterCTEs.append(("f_name", """
                SELECT DISTINCT resource_id FROM idx_string
                WHERE resource_type = 'Patient' AND param_name = 'name' AND value ILIKE \(p)
                """))
        }

        if let ident = query.identifier {
            let codeP = bind(ident.code)
            var sysCond = ""
            switch ident.systemFilter {
            case .any: break
            case .specific(nil): sysCond = " AND system IS NULL"
            case .specific(let sys?): sysCond = " AND system = \(bind(sys))"
            }
            filterCTEs.append(("f_ident", """
                SELECT DISTINCT resource_id FROM idx_token
                WHERE resource_type = 'Patient' AND param_name = 'identifier'
                  AND code = \(codeP)\(sysCond)
                """))
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
            }
            filterCTEs.append(("f_date\(i)", """
                SELECT DISTINCT resource_id FROM idx_date
                WHERE resource_type = 'Patient' AND param_name = 'birthdate' AND \(cond)
                """))
        }

        // ── Build `current` CTE — JOIN to filter CTEs to narrow the scan ─────

        var fromLines = ["FROM resources r"]
        for cte in filterCTEs {
            fromLines.append("JOIN \(cte.name) ON \(cte.name).resource_id = r.id")
        }
        fromLines.append("WHERE r.resource_type = 'Patient' AND r.deleted = false")
        fromLines.append("ORDER BY r.id, r.version_id DESC")

        let currentInner = (["SELECT DISTINCT ON (r.id) r.id, r.version_id, r.last_updated, r.content"]
            + fromLines).joined(separator: "\n      ")

        // ── Outer WHERE — cursor only (index filters are already applied above) ─

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

        // ── Assemble final SQL ────────────────────────────────────────────────

        var cteParts = filterCTEs.map { "\($0.name) AS (\n    \($0.sql)\n  )" }
        cteParts.append("current AS (\n    \(currentInner)\n  )")
        let withClause = "WITH " + cteParts.joined(separator: ",\n  ")

        let whereSQL = outerWhere.isEmpty ? "" : "WHERE " + outerWhere.joined(separator: "\n  AND ")
        let descending = (query.sort == .lastUpdatedDescending)
        let orderSQL = "ORDER BY c.last_updated \(descending ? "DESC" : "ASC"), c.id ASC"
        let limitP = bind(Int64(query.count + 1))  // +1 to detect next page

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

    /// Set server-managed meta fields on the patient before returning it.
    private func applyMeta(to patient: inout Patient, versionId: Int64, lastUpdated: Date) {
        var meta = patient.meta ?? Meta()
        meta.versionId = FHIRPrimitive(FHIRString(String(versionId)))
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let instantStr = formatter.string(from: lastUpdated)
        if let instant = try? Instant(instantStr) {
            meta.lastUpdated = FHIRPrimitive(instant)
        }
        patient.meta = meta
    }
}
