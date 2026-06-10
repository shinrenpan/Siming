import Foundation
import Logging
import ModelsR4
import PostgresNIO

public struct AppointmentStore: Sendable {
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
        public let nextCursor: SearchCursor?
    }

    public struct DeleteResult: Sendable {
        public let versionId: Int64
        public let lastUpdated: Date
    }

    // ── Public API ────────────────────────────────────────────────────────────

    public func create(_ appt: Appointment) async throws -> WriteResult {
        let id = UUID().uuidString.lowercased()
        return try await write(id: id, appointment: appt, ifMatch: nil)
    }

    public func update(id: String, appointment: Appointment, ifMatch: Int64?) async throws -> WriteResult {
        return try await write(id: id, appointment: appointment, ifMatch: ifMatch)
    }

    @discardableResult
    public func delete(id: String, ifMatch: Int64?) async throws -> DeleteResult {
        try await client.withConnection { conn in
            let (versionId, lastUpdated, _) = try await deleteResource(
                conn: conn, resourceType: "Appointment", id: id, ifMatch: ifMatch, logger: logger)
            return DeleteResult(versionId: versionId, lastUpdated: lastUpdated)
        }
    }

    public func vread(id: String, versionId: Int64) async throws -> ReadResult {
        try await client.withConnection { conn in
            let rows = try await conn.query(
                """
                SELECT version_id, last_updated, content, deleted
                FROM resources
                WHERE resource_type = 'Appointment' AND id = \(id) AND version_id = \(versionId)
                """, logger: logger)
            for try await (vid, lastUpdated, content, deleted) in
                rows.decode((Int64, Date, String, Bool).self, context: .default)
            {
                if deleted { throw FHIRServerError.gone(resourceType: "Appointment", id: id) }
                let jsonData = injectMeta(into: content, versionId: vid, lastUpdated: lastUpdated)
                return ReadResult(jsonData: jsonData, versionId: vid, lastUpdated: lastUpdated)
            }
            throw FHIRServerError.notFound(resourceType: "Appointment", id: id)
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
                    WHERE resource_type = 'Appointment' AND id = \(id) AND last_updated >= \(since)
                    ORDER BY version_id DESC
                    LIMIT \(Int64(count))
                    """, logger: logger)
            } else {
                rows = try await conn.query(
                    """
                    SELECT version_id, last_updated, content, deleted
                    FROM resources
                    WHERE resource_type = 'Appointment' AND id = \(id)
                    ORDER BY version_id DESC
                    LIMIT \(Int64(count))
                    """, logger: logger)
            }
            var entries: [HistoryRawEntry] = []
            for try await (vid, lastUpdated, content, deleted) in
                rows.decode((Int64, Date, String, Bool).self, context: .default)
            {
                let jsonData: Data? = deleted ? nil : injectMeta(into: content, versionId: vid, lastUpdated: lastUpdated)
                entries.append(HistoryRawEntry(resourceType: "Appointment", id: id, versionId: vid, lastUpdated: lastUpdated, jsonData: jsonData, deleted: deleted))
            }
            if entries.isEmpty {
                if since != nil {
                    let existRows = try await conn.query(
                        """
                        SELECT 1 FROM resources WHERE resource_type = 'Appointment' AND id = \(id) LIMIT 1
                        """, logger: logger)
                    var exists = false
                    for try await _ in existRows { exists = true }
                    if !exists { throw FHIRServerError.notFound(resourceType: "Appointment", id: id) }
                } else {
                    throw FHIRServerError.notFound(resourceType: "Appointment", id: id)
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
                    WHERE resource_type = 'Appointment' AND last_updated >= \(since)
                    ORDER BY last_updated DESC, id, version_id DESC
                    LIMIT \(Int64(count))
                    """, logger: logger)
            } else {
                rows = try await conn.query(
                    """
                    SELECT id, version_id, last_updated, content, deleted
                    FROM resources
                    WHERE resource_type = 'Appointment'
                    ORDER BY last_updated DESC, id, version_id DESC
                    LIMIT \(Int64(count))
                    """, logger: logger)
            }
            var entries: [HistoryRawEntry] = []
            for try await (rid, vid, lastUpdated, content, deleted) in
                rows.decode((String, Int64, Date, String, Bool).self, context: .default)
            {
                let jsonData: Data? = deleted ? nil : injectMeta(into: content, versionId: vid, lastUpdated: lastUpdated)
                entries.append(HistoryRawEntry(resourceType: "Appointment", id: rid, versionId: vid, lastUpdated: lastUpdated, jsonData: jsonData, deleted: deleted))
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
                WHERE resource_type = 'Appointment' AND id = \(id)
                ORDER BY version_id DESC
                LIMIT 1
                """, logger: logger)
            var found: ReadResult? = nil
            for try await (versionId, lastUpdated, content, deleted) in
                rows.decode((Int64, Date, String, Bool).self, context: .default)
            {
                if deleted { throw FHIRServerError.gone(resourceType: "Appointment", id: id) }
                let jsonData = injectMeta(into: content, versionId: versionId, lastUpdated: lastUpdated)
                found = ReadResult(jsonData: jsonData, versionId: versionId, lastUpdated: lastUpdated)
            }
            guard let result = found else {
                throw FHIRServerError.notFound(resourceType: "Appointment", id: id)
            }
            return result
        }
    }

    public func search(query: AppointmentSearchQuery) async throws -> SearchResult {
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

    private func write(id: String, appointment: Appointment, ifMatch: Int64?) async throws -> WriteResult {
        try validate(appointment)

        var appt = appointment
        appt.id   = FHIRPrimitive(FHIRString(id))
        let originalMeta = appt.meta
        appt.meta = nil

        let jsonData   = try JSONEncoder().encode(appt)
        let jsonString = String(data: jsonData, encoding: .utf8)!
        var searchParams = extractAppointmentSearchParams(appt)
        appendMetaParams(&searchParams, meta: originalMeta)

        return try await client.withConnection { conn in
            let (versionId, lastUpdated) = try await writeResource(
                conn: conn, resourceType: "Appointment", id: id,
                jsonString: jsonString, ifMatch: ifMatch, params: searchParams, logger: logger)
            let responseData = injectMeta(into: jsonString, versionId: versionId, lastUpdated: lastUpdated)
            return WriteResult(id: id, versionId: versionId, lastUpdated: lastUpdated, jsonData: responseData)
        }
    }

    private func validate(_ appt: Appointment) throws {}

    private func buildSearchSQL(query: AppointmentSearchQuery) throws -> (String, PostgresBindings) {
        var binds = PostgresBindings()
        var n = 0
        func bind(_ val: some PostgresDynamicTypeEncodable) -> String {
            n += 1; binds.append(val); return "$\(n)"
        }

        var filterCTEs: [(name: String, sql: String)] = []

        func tokenORCTE(name: String, paramName: String, tokens: [AppointmentSearchQuery.TokenParam]) -> (String, String) {
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
            return (name, "SELECT DISTINCT resource_id FROM idx_token WHERE resource_type = 'Appointment' AND param_name = '\(paramName)' AND (\(orClauses.joined(separator: " OR ")))")
        }

        func tokenNotCondition(paramName: String, tokens: [AppointmentSearchQuery.TokenParam]) -> String {
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
            return "r.id NOT IN (SELECT resource_id FROM idx_token WHERE resource_type = 'Appointment' AND param_name = '\(paramName)' AND (\(orClauses.joined(separator: " OR "))))"
        }

        func refCTE(name: String, paramName: String, ref: String) -> (String, String) {
            let parts = ref.split(separator: "/")
            if parts.count == 2 {
                let refTypeP = bind(String(parts[0])); let refIdP = bind(String(parts[1]))
                return (name, "SELECT DISTINCT resource_id FROM idx_reference WHERE resource_type = 'Appointment' AND param_name = '\(paramName)' AND ref_type = \(refTypeP) AND ref_id = \(refIdP)")
            } else {
                let refIdP = bind(ref)
                return (name, "SELECT DISTINCT resource_id FROM idx_reference WHERE resource_type = 'Appointment' AND param_name = '\(paramName)' AND ref_id = \(refIdP)")
            }
        }

        func dateCTE(name: String, paramName: String, dp: AppointmentSearchQuery.DateParam) -> (String, String) {
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
            case .ap: cond = "date_start <= \(bind(dp.apExpandedEnd)) AND date_end >= \(bind(dp.apExpandedStart))"
            }
            return (name, "SELECT DISTINCT resource_id FROM idx_date WHERE resource_type = 'Appointment' AND param_name = '\(paramName)' AND \(cond)")
        }

        // token CTEs
        if !query.status.isEmpty         { filterCTEs.append(tokenORCTE(name: "f_status",       paramName: "status",           tokens: query.status)) }
        if !query.serviceType.isEmpty     { filterCTEs.append(tokenORCTE(name: "f_svc_type",     paramName: "service-type",     tokens: query.serviceType)) }
        if !query.appointmentType.isEmpty { filterCTEs.append(tokenORCTE(name: "f_appt_type",    paramName: "appointment-type", tokens: query.appointmentType)) }
        if !query.specialty.isEmpty       { filterCTEs.append(tokenORCTE(name: "f_specialty",    paramName: "specialty",        tokens: query.specialty)) }
        if !query.reasonCode.isEmpty      { filterCTEs.append(tokenORCTE(name: "f_reason",       paramName: "reason-code",      tokens: query.reasonCode)) }
        if !query.serviceCategory.isEmpty { filterCTEs.append(tokenORCTE(name: "f_svc_cat",      paramName: "service-category", tokens: query.serviceCategory)) }
        if !query.partStatus.isEmpty      { filterCTEs.append(tokenORCTE(name: "f_part_status",  paramName: "part-status",      tokens: query.partStatus)) }

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
                filterCTEs.append(("f_ident", "SELECT DISTINCT resource_id FROM idx_token WHERE resource_type = 'Appointment' AND param_name = 'identifier' AND (\(orClauses.joined(separator: " OR ")))"))
            }
        }

        // date CTEs
        for (i, dp) in query.date.enumerated() {
            filterCTEs.append(dateCTE(name: "f_date\(i)", paramName: "date", dp: dp))
        }

        // reference CTEs
        if let ref = query.patient        { filterCTEs.append(refCTE(name: "f_patient",       paramName: "patient",         ref: ref)) }
        if let ref = query.actor          { filterCTEs.append(refCTE(name: "f_actor",         paramName: "actor",           ref: ref)) }
        if let ref = query.practitioner   { filterCTEs.append(refCTE(name: "f_practitioner",  paramName: "practitioner",    ref: ref)) }
        if let ref = query.location       { filterCTEs.append(refCTE(name: "f_location",      paramName: "location",        ref: ref)) }
        if let ref = query.supportingInfo  { filterCTEs.append(refCTE(name: "f_support_info", paramName: "supporting-info",  ref: ref)) }
        if let ref = query.basedOn         { filterCTEs.append(refCTE(name: "f_based_on",     paramName: "based-on",         ref: ref)) }
        if let ref = query.reasonReference { filterCTEs.append(refCTE(name: "f_reason_ref",   paramName: "reason-reference", ref: ref)) }

        // ── WHERE conditions ──────────────────────────────────────────────────

        var whereConditions = ["r.resource_type = 'Appointment'", "r.deleted = false"]

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
            case .ap: cond = "r.last_updated BETWEEN \(bind(lu.apExpandedStart)) AND \(bind(lu.apExpandedEnd))"
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
                whereConditions.append("r.id NOT IN (SELECT resource_id FROM idx_token WHERE resource_type = 'Appointment' AND param_name = 'identifier' AND (\(orClauses.joined(separator: " OR "))))")
            }
        }

        // :not modifiers
        if !query.statusNot.isEmpty         { whereConditions.append(tokenNotCondition(paramName: "status",           tokens: query.statusNot)) }
        if !query.serviceTypeNot.isEmpty     { whereConditions.append(tokenNotCondition(paramName: "service-type",     tokens: query.serviceTypeNot)) }
        if !query.appointmentTypeNot.isEmpty { whereConditions.append(tokenNotCondition(paramName: "appointment-type", tokens: query.appointmentTypeNot)) }
        if !query.specialtyNot.isEmpty       { whereConditions.append(tokenNotCondition(paramName: "specialty",        tokens: query.specialtyNot)) }
        if !query.reasonCodeNot.isEmpty      { whereConditions.append(tokenNotCondition(paramName: "reason-code",      tokens: query.reasonCodeNot)) }
        if !query.serviceCategoryNot.isEmpty { whereConditions.append(tokenNotCondition(paramName: "service-category", tokens: query.serviceCategoryNot)) }
        if !query.partStatusNot.isEmpty      { whereConditions.append(tokenNotCondition(paramName: "part-status",      tokens: query.partStatusNot)) }

        // :missing
        for paramName in query.missing.keys.sorted() {
            if let sub = appointmentMissingSubquery(param: paramName) {
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
                index: filterCTEs.count + i, sourceType: "Appointment",
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
                index: i, mainType: "Appointment",
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
                "SELECT DISTINCT resource_id FROM idx_string WHERE resource_type = 'Appointment' AND param_name = \(pn) AND value ILIKE \(val)"))
        }

        // meta params: _tag, _security, _profile
        let strBind: (String) -> String = { bind($0) }
        let (metaCTEs, metaWhere) = metaFilterCTEs(resourceType: "Appointment", meta: query.meta, bind: strBind)
        filterCTEs += metaCTEs
        whereConditions += metaWhere

        var fromLines = ["FROM resources r"]
        for cte in filterCTEs { fromLines.append("JOIN \(cte.name) ON \(cte.name).resource_id = r.id") }
        fromLines.append("WHERE " + whereConditions.joined(separator: " AND "))
        fromLines.append("ORDER BY r.id, r.version_id DESC")

        let idsInner = (["SELECT DISTINCT ON (r.id) r.id, r.version_id, r.last_updated"]
            + fromLines).joined(separator: "\n      ")

        // ── Multi-sort paged CTE ──────────────────────────────────────────────
        // Cursor binds MUST happen before limitP bind.
        let sortResult = buildMultiSort(
            sortKeys: query.sortKeys,
            resourceType: "Appointment",
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
            ? "FROM paged p JOIN resources r ON r.resource_type = 'Appointment' AND r.id = p.id AND r.version_id = p.version_id"
            : "FROM paged p CROSS JOIN total_count t JOIN resources r ON r.resource_type = 'Appointment' AND r.id = p.id AND r.version_id = p.version_id"

        let sql = "\(withClause)\nSELECT p.id, p.version_id, p.last_updated, r.content, \(totalExpr), p.sort_val_concat\n\(fromClause)\nORDER BY \(sortResult.outerOrderBy)"
        return (sql, binds)
    }

    private func buildCountSQL(query: AppointmentSearchQuery) throws -> (String, PostgresBindings) {
        var binds = PostgresBindings()
        var n = 0
        func bind(_ val: some PostgresDynamicTypeEncodable) -> String {
            n += 1; binds.append(val); return "$\(n)"
        }

        var filterCTEs: [(name: String, sql: String)] = []

        func tokenCTE(name: String, paramName: String, tokens: [AppointmentSearchQuery.TokenParam]) -> (String, String) {
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
            return (name, "SELECT DISTINCT resource_id FROM idx_token WHERE resource_type = 'Appointment' AND param_name = '\(paramName)' AND (\(orClauses.joined(separator: " OR ")))")
        }

        func cRefCTE(name: String, paramName: String, ref: String) -> (String, String) {
            let parts = ref.split(separator: "/")
            if parts.count == 2 {
                let refTypeP = bind(String(parts[0])); let refIdP = bind(String(parts[1]))
                return (name, "SELECT DISTINCT resource_id FROM idx_reference WHERE resource_type = 'Appointment' AND param_name = '\(paramName)' AND ref_type = \(refTypeP) AND ref_id = \(refIdP)")
            } else {
                let refIdP = bind(ref)
                return (name, "SELECT DISTINCT resource_id FROM idx_reference WHERE resource_type = 'Appointment' AND param_name = '\(paramName)' AND ref_id = \(refIdP)")
            }
        }

        func cDateCTE(name: String, paramName: String, dp: AppointmentSearchQuery.DateParam) -> (String, String) {
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
            case .ap: cond = "date_start <= \(bind(dp.apExpandedEnd)) AND date_end >= \(bind(dp.apExpandedStart))"
            }
            return (name, "SELECT DISTINCT resource_id FROM idx_date WHERE resource_type = 'Appointment' AND param_name = '\(paramName)' AND \(cond)")
        }

        if !query.status.isEmpty         { filterCTEs.append(tokenCTE(name: "f_status",      paramName: "status",           tokens: query.status)) }
        if !query.serviceType.isEmpty     { filterCTEs.append(tokenCTE(name: "f_svc_type",    paramName: "service-type",     tokens: query.serviceType)) }
        if !query.appointmentType.isEmpty { filterCTEs.append(tokenCTE(name: "f_appt_type",   paramName: "appointment-type", tokens: query.appointmentType)) }
        if !query.specialty.isEmpty       { filterCTEs.append(tokenCTE(name: "f_specialty",   paramName: "specialty",        tokens: query.specialty)) }
        if !query.reasonCode.isEmpty      { filterCTEs.append(tokenCTE(name: "f_reason",      paramName: "reason-code",      tokens: query.reasonCode)) }
        if !query.serviceCategory.isEmpty { filterCTEs.append(tokenCTE(name: "f_svc_cat",     paramName: "service-category", tokens: query.serviceCategory)) }
        if !query.partStatus.isEmpty      { filterCTEs.append(tokenCTE(name: "f_part_status", paramName: "part-status",      tokens: query.partStatus)) }

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
                filterCTEs.append(("f_ident", "SELECT DISTINCT resource_id FROM idx_token WHERE resource_type = 'Appointment' AND param_name = 'identifier' AND (\(orClauses.joined(separator: " OR ")))"))
            }
        }

        for (i, dp) in query.date.enumerated() { filterCTEs.append(cDateCTE(name: "f_date\(i)", paramName: "date", dp: dp)) }

        if let ref = query.patient        { filterCTEs.append(cRefCTE(name: "f_patient",       paramName: "patient",         ref: ref)) }
        if let ref = query.actor          { filterCTEs.append(cRefCTE(name: "f_actor",         paramName: "actor",           ref: ref)) }
        if let ref = query.practitioner   { filterCTEs.append(cRefCTE(name: "f_practitioner",  paramName: "practitioner",    ref: ref)) }
        if let ref = query.location       { filterCTEs.append(cRefCTE(name: "f_location",      paramName: "location",        ref: ref)) }
        if let ref = query.supportingInfo { filterCTEs.append(cRefCTE(name: "f_support_info",  paramName: "supporting-info", ref: ref)) }
        if let ref = query.basedOn        { filterCTEs.append(cRefCTE(name: "f_based_on",     paramName: "based-on",        ref: ref)) }
        if let ref = query.reasonReference { filterCTEs.append(cRefCTE(name: "f_reason_ref",  paramName: "reason-reference", ref: ref)) }

        var whereConditions = ["r.resource_type = 'Appointment'", "r.deleted = false"]

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
            case .ap: cond = "r.last_updated BETWEEN \(bind(lu.apExpandedStart)) AND \(bind(lu.apExpandedEnd))"
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
                whereConditions.append("r.id NOT IN (SELECT resource_id FROM idx_token WHERE resource_type = 'Appointment' AND param_name = 'identifier' AND (\(orClauses.joined(separator: " OR "))))")
            }
        }

        for (i, chain) in query.chains.enumerated() {
            if let (name, sql) = chainFilterCTE(
                index: filterCTEs.count + i, sourceType: "Appointment",
                chain: chain, bindStr: { bind($0) }, bindDate: { bind($0) }
            ) { filterCTEs.append((name, sql)) }
        }
        for (i, hp) in query.has.enumerated() {
            if let (name, sql) = hasFilterCTE(
                index: i, mainType: "Appointment",
                param: hp, bindStr: { bind($0) }, bindDate: { bind($0) }
            ) { filterCTEs.append((name, sql)) }
        }

        // token:text filters
        for (i, tt) in query.tokenTexts.enumerated() {
            let pn = bind("\(tt.paramName):text")
            let val = bind("%\(tt.value)%")
            filterCTEs.append(("f_ttext\(i)",
                "SELECT DISTINCT resource_id FROM idx_string WHERE resource_type = 'Appointment' AND param_name = \(pn) AND value ILIKE \(val)"))
        }

        // meta params: _tag, _security, _profile
        let strBind: (String) -> String = { bind($0) }
        let (metaCTEs, metaWhere) = metaFilterCTEs(resourceType: "Appointment", meta: query.meta, bind: strBind)
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

    private func appointmentMissingSubquery(param: String) -> String? {
        switch param {
        case "patient":          return "SELECT DISTINCT resource_id FROM idx_reference WHERE resource_type = 'Appointment' AND param_name = 'patient'"
        case "actor":            return "SELECT DISTINCT resource_id FROM idx_reference WHERE resource_type = 'Appointment' AND param_name = 'actor'"
        case "practitioner":     return "SELECT DISTINCT resource_id FROM idx_reference WHERE resource_type = 'Appointment' AND param_name = 'practitioner'"
        case "location":         return "SELECT DISTINCT resource_id FROM idx_reference WHERE resource_type = 'Appointment' AND param_name = 'location'"
        case "supporting-info":  return "SELECT DISTINCT resource_id FROM idx_reference WHERE resource_type = 'Appointment' AND param_name = 'supporting-info'"
        case "status":           return "SELECT DISTINCT resource_id FROM idx_token WHERE resource_type = 'Appointment' AND param_name = 'status'"
        case "service-type":     return "SELECT DISTINCT resource_id FROM idx_token WHERE resource_type = 'Appointment' AND param_name = 'service-type'"
        case "appointment-type": return "SELECT DISTINCT resource_id FROM idx_token WHERE resource_type = 'Appointment' AND param_name = 'appointment-type'"
        case "specialty":        return "SELECT DISTINCT resource_id FROM idx_token WHERE resource_type = 'Appointment' AND param_name = 'specialty'"
        case "reason-code":      return "SELECT DISTINCT resource_id FROM idx_token WHERE resource_type = 'Appointment' AND param_name = 'reason-code'"
        case "service-category": return "SELECT DISTINCT resource_id FROM idx_token WHERE resource_type = 'Appointment' AND param_name = 'service-category'"
        case "part-status":      return "SELECT DISTINCT resource_id FROM idx_token WHERE resource_type = 'Appointment' AND param_name = 'part-status'"
        case "identifier":       return "SELECT DISTINCT resource_id FROM idx_token WHERE resource_type = 'Appointment' AND param_name = 'identifier'"
        case "date":             return "SELECT DISTINCT resource_id FROM idx_date WHERE resource_type = 'Appointment' AND param_name = 'date'"
        default:                 return nil
        }
    }
}
