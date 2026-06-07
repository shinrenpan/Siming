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
        public let total: Int?   // nil when _total=none
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
            let (versionId, lastUpdated, _) = try await deleteResource(
                conn: conn, resourceType: "Patient", id: id, ifMatch: ifMatch, logger: logger)
            return DeleteResult(versionId: versionId, lastUpdated: lastUpdated)
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
    public func history(id: String, since: Date? = nil, count: Int = 50) async throws -> [HistoryRawEntry] {
        try await client.withConnection { conn in
            let rows: PostgresRowSequence
            if let since {
                rows = try await conn.query(
                    """
                    SELECT version_id, last_updated, content, deleted
                    FROM resources
                    WHERE resource_type = 'Patient' AND id = \(id) AND last_updated >= \(since)
                    ORDER BY version_id DESC
                    LIMIT \(Int64(count))
                    """, logger: logger)
            } else {
                rows = try await conn.query(
                    """
                    SELECT version_id, last_updated, content, deleted
                    FROM resources
                    WHERE resource_type = 'Patient' AND id = \(id)
                    ORDER BY version_id DESC
                    LIMIT \(Int64(count))
                    """, logger: logger)
            }
            var entries: [HistoryRawEntry] = []
            for try await (vid, lastUpdated, content, deleted) in
                rows.decode((Int64, Date, String, Bool).self, context: .default)
            {
                let jsonData: Data? = deleted ? nil : injectMeta(into: content, versionId: vid, lastUpdated: lastUpdated)
                entries.append(HistoryRawEntry(resourceType: "Patient", id: id, versionId: vid, lastUpdated: lastUpdated, jsonData: jsonData, deleted: deleted))
            }
            if entries.isEmpty {
                if since != nil {
                    let existRows = try await conn.query(
                        """
                        SELECT 1 FROM resources WHERE resource_type = 'Patient' AND id = \(id) LIMIT 1
                        """, logger: logger)
                    var exists = false
                    for try await _ in existRows { exists = true }
                    if !exists { throw FHIRServerError.notFound(resourceType: "Patient", id: id) }
                } else {
                    throw FHIRServerError.notFound(resourceType: "Patient", id: id)
                }
            }
            return entries
        }
    }

    /// GET /Patient/_history — all Patient versions across all instances, optional _since filter.
    public func typeHistory(since: Date?, count: Int) async throws -> [HistoryRawEntry] {
        try await client.withConnection { conn in
            let rows: PostgresRowSequence
            if let since {
                rows = try await conn.query(
                    """
                    SELECT id, version_id, last_updated, content, deleted
                    FROM resources
                    WHERE resource_type = 'Patient' AND last_updated >= \(since)
                    ORDER BY last_updated DESC, id, version_id DESC
                    LIMIT \(Int64(count))
                    """, logger: logger)
            } else {
                rows = try await conn.query(
                    """
                    SELECT id, version_id, last_updated, content, deleted
                    FROM resources
                    WHERE resource_type = 'Patient'
                    ORDER BY last_updated DESC, id, version_id DESC
                    LIMIT \(Int64(count))
                    """, logger: logger)
            }
            var entries: [HistoryRawEntry] = []
            for try await (rid, vid, lastUpdated, content, deleted) in
                rows.decode((String, Int64, Date, String, Bool).self, context: .default)
            {
                let jsonData: Data? = deleted ? nil : injectMeta(into: content, versionId: vid, lastUpdated: lastUpdated)
                entries.append(HistoryRawEntry(resourceType: "Patient", id: rid, versionId: vid, lastUpdated: lastUpdated, jsonData: jsonData, deleted: deleted))
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
            let pgQuery = PostgresQuery(unsafeSQL: sql, binds: binds)
            let rows = try await conn.query(pgQuery, logger: logger)

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
            let hasNext = results.count > query.count
            let page = Array(results.prefix(pageSize))
            let pageSortVals = Array(sortValTexts.prefix(pageSize))

            let nextCursor: PatientSearchQuery.SearchCursor?
            if hasNext, let lastEntry = page.last, let lastSortVal = pageSortVals.last {
                nextCursor = PatientSearchQuery.SearchCursor(
                    sortValue: lastSortVal, id: lastEntry.id, descending: query.sort.isDescending)
            } else {
                nextCursor = nil
            }

            let total: Int?
            switch query.totalMode {
            case .accurate: total = Int(rawTotal)
            case .estimate: total = hasNext ? nil : page.count  // exact when last page, nil otherwise
            case .none:     total = nil
            }
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
            let (versionId, lastUpdated) = try await writeResource(
                conn: conn, resourceType: "Patient", id: id,
                jsonString: jsonString, ifMatch: ifMatch, params: searchParams, logger: logger)
            let responseData = injectMeta(into: jsonString, versionId: versionId, lastUpdated: lastUpdated)
            return WriteResult(id: id, versionId: versionId, lastUpdated: lastUpdated, jsonData: responseData)
        }
    }

    /// Validation hook. No-op until profile validation is added.
    private func validate(_ patient: Patient) throws {}

    // ── String filter helpers ────────────────────────────────────────────────

    private func stringBindValue(_ param: PatientSearchQuery.StringParam) -> String {
        switch param.modifier {
        case .startsWith:      return "\(param.value)%"
        case .contains, .text: return "%\(param.value)%"
        case .exact:           return param.value
        }
    }

    private func stringFilterCond(_ param: PatientSearchQuery.StringParam, _ bp: String) -> String {
        switch param.modifier {
        case .exact:           return "value = \(bp)"
        case .contains, .text: return "value ILIKE \(bp)"
        case .startsWith:      return "lower(value) LIKE lower(\(bp))"
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
            let bp = bind(stringBindValue(nameParam))
            filterCTEs.append(("f_name", "SELECT DISTINCT resource_id FROM idx_string WHERE resource_type = 'Patient' AND param_name = 'name' AND \(stringFilterCond(nameParam, bp))"))
        }

        // family, given, address variants — string with modifier
        let stringFilters: [(String, String, PatientSearchQuery.StringParam?)] = [
            ("f_family",  "family",             query.family),
            ("f_given",   "given",              query.given),
            ("f_addr",    "address",            query.address),
            ("f_city",    "address-city",       query.addressCity),
            ("f_state",   "address-state",      query.addressState),
            ("f_postal",  "address-postalcode", query.addressPostalCode),
            ("f_country", "address-country",    query.addressCountry),
        ]
        for (cteName, paramName, param) in stringFilters {
            guard let param else { continue }
            let bp = bind(stringBindValue(param))
            filterCTEs.append((cteName, "SELECT DISTINCT resource_id FROM idx_string WHERE resource_type = 'Patient' AND param_name = '\(paramName)' AND \(stringFilterCond(param, bp))"))
        }

        // gender — token OR
        if !query.gender.isEmpty {
            let phs = query.gender.map { bind($0) }.joined(separator: ", ")
            filterCTEs.append(("f_gender", "SELECT DISTINCT resource_id FROM idx_token WHERE resource_type = 'Patient' AND param_name = 'gender' AND code IN (\(phs))"))
        }

        // active — boolean token
        if let active = query.active {
            let p = bind(active ? "true" : "false")
            filterCTEs.append(("f_active", "SELECT DISTINCT resource_id FROM idx_token WHERE resource_type = 'Patient' AND param_name = 'active' AND code = \(p)"))
        }

        // phone, email — via telecom index (system-filtered)
        if let phone = query.phone {
            let p = bind(phone)
            filterCTEs.append(("f_phone", "SELECT DISTINCT resource_id FROM idx_token WHERE resource_type = 'Patient' AND param_name = 'telecom' AND system = 'phone' AND code = \(p)"))
        }
        if let email = query.email {
            let p = bind(email)
            filterCTEs.append(("f_email", "SELECT DISTINCT resource_id FROM idx_token WHERE resource_type = 'Patient' AND param_name = 'telecom' AND system = 'email' AND code = \(p)"))
        }

        // identifier — token OR; system| = system-only match when code is empty
        if !query.identifier.isEmpty {
            var orClauses: [String] = []
            for ident in query.identifier {
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
                filterCTEs.append(("f_ident", """
                    SELECT DISTINCT resource_id FROM idx_token
                    WHERE resource_type = 'Patient' AND param_name = 'identifier'
                      AND (\(orClauses.joined(separator: " OR ")))
                    """))
            }
        }

        // birthdate — date range; two-bound comparison per FHIR R4 §2.4.0.1
        for (i, bd) in query.birthdate.enumerated() {
            let startP = bind(bd.dateStart)
            let endP   = bind(bd.dateEnd)
            let cond: String
            switch bd.prefix {
            case .eq: cond = "date_start <= \(endP) AND date_end >= \(startP)"
            case .ne: cond = "NOT (date_start <= \(endP) AND date_end >= \(startP))"
            case .lt: cond = "date_end < \(startP)"
            case .le: cond = "date_start <= \(endP)"
            case .gt: cond = "date_start > \(endP)"
            case .ge: cond = "date_end >= \(startP)"
            case .sa: cond = "date_start > \(endP)"
            case .eb: cond = "date_end < \(startP)"
            }
            filterCTEs.append(("f_date\(i)", """
                SELECT DISTINCT resource_id FROM idx_date
                WHERE resource_type = 'Patient' AND param_name = 'birthdate' AND \(cond)
                """))
        }

        // ── `ids` CTE — _id, _lastUpdated, and :not conditions ─────────────────

        var whereConditions = ["r.resource_type = 'Patient'", "r.deleted = false"]

        if !query.id.isEmpty {
            let phs = query.id.map { bind($0) }.joined(separator: ", ")
            whereConditions.append("r.id IN (\(phs))")
        }
        for lu in query.lastUpdated {
            let startP = bind(lu.dateStart)
            let endP   = bind(lu.dateEnd)
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
                whereConditions.append("r.id NOT IN (SELECT resource_id FROM idx_token WHERE resource_type = 'Patient' AND param_name = 'identifier' AND (\(orClauses.joined(separator: " OR "))))")
            }
        }

        // gender:not
        if !query.genderNot.isEmpty {
            let phs = query.genderNot.map { bind($0) }.joined(separator: ", ")
            whereConditions.append("r.id NOT IN (SELECT resource_id FROM idx_token WHERE resource_type = 'Patient' AND param_name = 'gender' AND code IN (\(phs)))")
        }

        // :missing modifier
        for paramName in query.missing.keys.sorted() {
            if let sub = patientMissingSubquery(param: paramName) {
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
                index: filterCTEs.count + i, sourceType: "Patient",
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
                index: i, mainType: "Patient",
                param: hp, bindStr: hBindStr, bindDate: hBindDate
            ) {
                filterCTEs.append((name, sql))
            }
        }

        var fromLines = ["FROM resources r"]
        for cte in filterCTEs {
            fromLines.append("JOIN \(cte.name) ON \(cte.name).resource_id = r.id")
        }
        fromLines.append("WHERE " + whereConditions.joined(separator: " AND "))
        fromLines.append("ORDER BY r.id, r.version_id DESC")

        let idsInner = (["SELECT DISTINCT ON (r.id) r.id, r.version_id, r.last_updated"]
            + fromLines).joined(separator: "\n      ")

        // ── Sort-specific paged CTE ───────────────────────────────────────────

        let sortIsDescending = query.sort.isDescending
        let orderDir = sortIsDescending ? "DESC" : "ASC"

        // Cursor conditions and sort_keys CTE are determined by sort type.
        // Cursor binds MUST happen before limitP bind.
        var sortKeysCTE: (name: String, sql: String)? = nil
        var cursorCondSQL = ""
        var finalSortValSQL = ""
        var sortKind = 0  // 0=lastUpdated, 1=name(string), 2=date, 3=_id

        switch query.sort {
        case .lastUpdatedDescending, .lastUpdatedAscending, .dateAscending, .dateDescending:
            if let cursor = query.cursor, let ts = Double(cursor.sortValue) {
                let tsP = bind(Date(timeIntervalSince1970: ts))
                let idP = bind(cursor.id)
                let op = sortIsDescending ? "<" : ">"
                cursorCondSQL = "(i.last_updated \(op) \(tsP) OR (i.last_updated = \(tsP) AND i.id > \(idP)))"
            }
            finalSortValSQL = "CAST(EXTRACT(EPOCH FROM p.last_updated) AS text)"
            sortKind = 0

        case .nameAscending, .nameDescending:
            sortKeysCTE = ("sort_keys",
                "SELECT DISTINCT ON (resource_id) resource_id, value AS sv " +
                "FROM idx_string WHERE resource_type = 'Patient' AND param_name = 'family' " +
                "ORDER BY resource_id, value ASC")
            if let cursor = query.cursor {
                let svP = bind(cursor.sortValue)
                let idP = bind(cursor.id)
                let op = sortIsDescending ? "<" : ">"
                cursorCondSQL = "(sort_val \(op) \(svP) OR (sort_val = \(svP) AND id > \(idP)))"
            }
            finalSortValSQL = "p.sort_val"
            sortKind = 1

        case .birthdateAscending, .birthdateDescending:
            sortKeysCTE = ("sort_keys",
                "SELECT DISTINCT ON (resource_id) resource_id, date_start AS sv " +
                "FROM idx_date WHERE resource_type = 'Patient' AND param_name = 'birthdate' " +
                "ORDER BY resource_id, date_start ASC")
            if let cursor = query.cursor, let ts = Double(cursor.sortValue) {
                let dateP = bind(Date(timeIntervalSince1970: ts))
                let idP = bind(cursor.id)
                let op = sortIsDescending ? "<" : ">"
                cursorCondSQL = "(sort_val IS NOT NULL AND sort_val \(op) \(dateP)) OR " +
                    "(sort_val IS NOT NULL AND sort_val = \(dateP) AND id > \(idP))"
            }
            finalSortValSQL = "COALESCE(CAST(EXTRACT(EPOCH FROM p.sort_val) AS text), '')"
            sortKind = 2

        case .statusAscending, .statusDescending,
             .clinicalStatusAscending, .clinicalStatusDescending,
             .codeAscending, .codeDescending:
            if let cursor = query.cursor, let ts = Double(cursor.sortValue) {
                let tsP = bind(Date(timeIntervalSince1970: ts))
                let idP = bind(cursor.id)
                let op = sortIsDescending ? "<" : ">"
                cursorCondSQL = "(i.last_updated \(op) \(tsP) OR (i.last_updated = \(tsP) AND i.id > \(idP)))"
            }
            finalSortValSQL = "CAST(EXTRACT(EPOCH FROM p.last_updated) AS text)"
            sortKind = 0

        case ._idAscending, ._idDescending:
            if let cursor = query.cursor {
                let idP = bind(cursor.sortValue)
                let op = sortIsDescending ? "<" : ">"
                cursorCondSQL = "i.id \(op) \(idP)"
            }
            finalSortValSQL = "p.id"
            sortKind = 3
        }

        let limitP = bind(Int64(query.count + 1))

        let pagedInner: String
        switch sortKind {
        case 1:  // name sort — string sort_val via LEFT JOIN idx_string
            let inner = "SELECT i.id, i.version_id, i.last_updated, COALESCE(sk.sv, '') AS sort_val " +
                "FROM ids i LEFT JOIN sort_keys sk ON sk.resource_id = i.id"
            let whereLine = cursorCondSQL.isEmpty ? "" : "\n    WHERE \(cursorCondSQL)"
            pagedInner = "SELECT id, version_id, last_updated, sort_val FROM (\n      \(inner)\n    ) sub" +
                "\(whereLine)\n    ORDER BY sort_val \(orderDir) NULLS LAST, id ASC\n    LIMIT \(limitP)"
        case 2:  // date sort — timestamp sort_val via LEFT JOIN idx_date
            let inner = "SELECT i.id, i.version_id, i.last_updated, sk.sv AS sort_val " +
                "FROM ids i LEFT JOIN sort_keys sk ON sk.resource_id = i.id"
            let whereLine = cursorCondSQL.isEmpty ? "" : "\n    WHERE \(cursorCondSQL)"
            pagedInner = "SELECT id, version_id, last_updated, sort_val FROM (\n      \(inner)\n    ) sub" +
                "\(whereLine)\n    ORDER BY sort_val \(orderDir) NULLS LAST, id ASC\n    LIMIT \(limitP)"
        case 3:  // _id sort
            let whereLine = cursorCondSQL.isEmpty ? "" : "\n    WHERE \(cursorCondSQL)"
            pagedInner = "SELECT i.id, i.version_id, i.last_updated\n    FROM ids i" +
                "\(whereLine)\n    ORDER BY i.id \(orderDir)\n    LIMIT \(limitP)"
        default:  // lastUpdated sort
            let whereLine = cursorCondSQL.isEmpty ? "" : "\n    WHERE \(cursorCondSQL)"
            pagedInner = "SELECT i.id, i.version_id, i.last_updated\n    FROM ids i" +
                "\(whereLine)\n    ORDER BY i.last_updated \(orderDir), i.id ASC\n    LIMIT \(limitP)"
        }

        var cteParts = filterCTEs.map { "\($0.name) AS (\n    \($0.sql)\n  )" }
        cteParts.append("ids AS MATERIALIZED (\n    \(idsInner)\n  )")
        let skipTotal = query.totalMode == .none || query.totalMode == .estimate
        if !skipTotal {
            cteParts.append("total_count AS (\n    SELECT COUNT(*) AS n FROM ids\n  )")
        }
        if let skCTE = sortKeysCTE {
            cteParts.append("\(skCTE.name) AS (\n    \(skCTE.sql)\n  )")
        }
        cteParts.append("paged AS (\n    \(pagedInner)\n  )")
        let withClause = "WITH " + cteParts.joined(separator: ",\n  ")

        let totalExpr = skipTotal
            ? "CAST(0 AS bigint)"
            : "t.n"
        let fromClause = skipTotal
            ? "FROM paged p JOIN resources r ON r.resource_type = 'Patient' AND r.id = p.id AND r.version_id = p.version_id"
            : "FROM paged p CROSS JOIN total_count t JOIN resources r ON r.resource_type = 'Patient' AND r.id = p.id AND r.version_id = p.version_id"

        let sql = "\(withClause)\nSELECT p.id, p.version_id, p.last_updated, r.content, \(totalExpr), \(finalSortValSQL) AS sort_val_text\n\(fromClause)\nORDER BY sort_val_text \(orderDir) NULLS LAST, p.id ASC"
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
            let bp = bind(stringBindValue(nameParam))
            filterCTEs.append(("f_name", "SELECT DISTINCT resource_id FROM idx_string WHERE resource_type = 'Patient' AND param_name = 'name' AND \(stringFilterCond(nameParam, bp))"))
        }

        let stringFilters: [(String, String, PatientSearchQuery.StringParam?)] = [
            ("f_family",  "family",             query.family),
            ("f_given",   "given",              query.given),
            ("f_addr",    "address",            query.address),
            ("f_city",    "address-city",       query.addressCity),
            ("f_state",   "address-state",      query.addressState),
            ("f_postal",  "address-postalcode", query.addressPostalCode),
            ("f_country", "address-country",    query.addressCountry),
        ]
        for (cteName, paramName, param) in stringFilters {
            guard let param else { continue }
            let bp = bind(stringBindValue(param))
            filterCTEs.append((cteName, "SELECT DISTINCT resource_id FROM idx_string WHERE resource_type = 'Patient' AND param_name = '\(paramName)' AND \(stringFilterCond(param, bp))"))
        }

        if !query.gender.isEmpty {
            let phs = query.gender.map { bind($0) }.joined(separator: ", ")
            filterCTEs.append(("f_gender", "SELECT DISTINCT resource_id FROM idx_token WHERE resource_type = 'Patient' AND param_name = 'gender' AND code IN (\(phs))"))
        }
        if let active = query.active {
            let p = bind(active ? "true" : "false")
            filterCTEs.append(("f_active", "SELECT DISTINCT resource_id FROM idx_token WHERE resource_type = 'Patient' AND param_name = 'active' AND code = \(p)"))
        }
        if let phone = query.phone {
            let p = bind(phone)
            filterCTEs.append(("f_phone", "SELECT DISTINCT resource_id FROM idx_token WHERE resource_type = 'Patient' AND param_name = 'telecom' AND system = 'phone' AND code = \(p)"))
        }
        if let email = query.email {
            let p = bind(email)
            filterCTEs.append(("f_email", "SELECT DISTINCT resource_id FROM idx_token WHERE resource_type = 'Patient' AND param_name = 'telecom' AND system = 'email' AND code = \(p)"))
        }

        if !query.identifier.isEmpty {
            var orClauses: [String] = []
            for ident in query.identifier {
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
                filterCTEs.append(("f_ident",
                    "SELECT DISTINCT resource_id FROM idx_token WHERE resource_type = 'Patient' AND param_name = 'identifier' AND (\(orClauses.joined(separator: " OR ")))"))
            }
        }
        for (i, bd) in query.birthdate.enumerated() {
            let startP = bind(bd.dateStart)
            let endP   = bind(bd.dateEnd)
            let cond: String
            switch bd.prefix {
            case .eq: cond = "date_start <= \(endP) AND date_end >= \(startP)"
            case .ne: cond = "NOT (date_start <= \(endP) AND date_end >= \(startP))"
            case .lt: cond = "date_end < \(startP)"
            case .le: cond = "date_start <= \(endP)"
            case .gt: cond = "date_start > \(endP)"
            case .ge: cond = "date_end >= \(startP)"
            case .sa: cond = "date_start > \(endP)"
            case .eb: cond = "date_end < \(startP)"
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
            let startP = bind(lu.dateStart)
            let endP   = bind(lu.dateEnd)
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
                whereConditions.append("r.id NOT IN (SELECT resource_id FROM idx_token WHERE resource_type = 'Patient' AND param_name = 'identifier' AND (\(orClauses.joined(separator: " OR "))))")
            }
        }
        if !query.genderNot.isEmpty {
            let phs = query.genderNot.map { bind($0) }.joined(separator: ", ")
            whereConditions.append("r.id NOT IN (SELECT resource_id FROM idx_token WHERE resource_type = 'Patient' AND param_name = 'gender' AND code IN (\(phs)))")
        }
        for paramName in query.missing.keys.sorted() {
            if let sub = patientMissingSubquery(param: paramName) {
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
                index: filterCTEs.count + i, sourceType: "Patient",
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
                index: i, mainType: "Patient",
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

    /// Returns the subquery text for :missing checks on Patient params.
    /// Returns nil for unknown param names (silently ignored).
    private func patientMissingSubquery(param: String) -> String? {
        switch param {
        case "name":               return "SELECT DISTINCT resource_id FROM idx_string WHERE resource_type = 'Patient' AND param_name = 'name'"
        case "family":             return "SELECT DISTINCT resource_id FROM idx_string WHERE resource_type = 'Patient' AND param_name = 'family'"
        case "given":              return "SELECT DISTINCT resource_id FROM idx_string WHERE resource_type = 'Patient' AND param_name = 'given'"
        case "address":            return "SELECT DISTINCT resource_id FROM idx_string WHERE resource_type = 'Patient' AND param_name = 'address'"
        case "address-city":       return "SELECT DISTINCT resource_id FROM idx_string WHERE resource_type = 'Patient' AND param_name = 'address-city'"
        case "address-state":      return "SELECT DISTINCT resource_id FROM idx_string WHERE resource_type = 'Patient' AND param_name = 'address-state'"
        case "address-postalcode": return "SELECT DISTINCT resource_id FROM idx_string WHERE resource_type = 'Patient' AND param_name = 'address-postalcode'"
        case "address-country":    return "SELECT DISTINCT resource_id FROM idx_string WHERE resource_type = 'Patient' AND param_name = 'address-country'"
        case "gender":             return "SELECT DISTINCT resource_id FROM idx_token WHERE resource_type = 'Patient' AND param_name = 'gender'"
        case "active":             return "SELECT DISTINCT resource_id FROM idx_token WHERE resource_type = 'Patient' AND param_name = 'active'"
        case "identifier":         return "SELECT DISTINCT resource_id FROM idx_token WHERE resource_type = 'Patient' AND param_name = 'identifier'"
        case "phone":              return "SELECT DISTINCT resource_id FROM idx_token WHERE resource_type = 'Patient' AND param_name = 'telecom' AND system = 'phone'"
        case "email":              return "SELECT DISTINCT resource_id FROM idx_token WHERE resource_type = 'Patient' AND param_name = 'telecom' AND system = 'email'"
        case "birthdate":          return "SELECT DISTINCT resource_id FROM idx_date WHERE resource_type = 'Patient' AND param_name = 'birthdate'"
        default:                   return nil
        }
    }

}
