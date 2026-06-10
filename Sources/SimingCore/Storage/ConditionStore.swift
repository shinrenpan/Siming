import Foundation
import Logging
import ModelsR4
import PostgresNIO

public struct ConditionStore: Sendable {
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

    public func create(_ cond: Condition) async throws -> WriteResult {
        let id = UUID().uuidString.lowercased()
        return try await write(id: id, condition: cond, ifMatch: nil)
    }

    public func update(id: String, condition: Condition, ifMatch: Int64?) async throws -> WriteResult {
        return try await write(id: id, condition: condition, ifMatch: ifMatch)
    }

    @discardableResult
    public func delete(id: String, ifMatch: Int64?) async throws -> DeleteResult {
        try await client.withConnection { conn in
            let (versionId, lastUpdated, _) = try await deleteResource(
                conn: conn, resourceType: "Condition", id: id, ifMatch: ifMatch, logger: logger)
            return DeleteResult(versionId: versionId, lastUpdated: lastUpdated)
        }
    }

    public func vread(id: String, versionId: Int64) async throws -> ReadResult {
        try await client.withConnection { conn in
            let rows = try await conn.query(
                """
                SELECT version_id, last_updated, content, deleted
                FROM resources
                WHERE resource_type = 'Condition' AND id = \(id) AND version_id = \(versionId)
                """, logger: logger)
            for try await (vid, lastUpdated, content, deleted) in
                rows.decode((Int64, Date, String, Bool).self, context: .default)
            {
                if deleted { throw FHIRServerError.gone(resourceType: "Condition", id: id) }
                let jsonData = injectMeta(into: content, versionId: vid, lastUpdated: lastUpdated)
                return ReadResult(jsonData: jsonData, versionId: vid, lastUpdated: lastUpdated)
            }
            throw FHIRServerError.notFound(resourceType: "Condition", id: id)
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
                    WHERE resource_type = 'Condition' AND id = \(id) AND last_updated >= \(since)
                    ORDER BY version_id DESC
                    LIMIT \(Int64(count))
                    """, logger: logger)
            } else {
                rows = try await conn.query(
                    """
                    SELECT version_id, last_updated, content, deleted
                    FROM resources
                    WHERE resource_type = 'Condition' AND id = \(id)
                    ORDER BY version_id DESC
                    LIMIT \(Int64(count))
                    """, logger: logger)
            }
            var entries: [HistoryRawEntry] = []
            for try await (vid, lastUpdated, content, deleted) in
                rows.decode((Int64, Date, String, Bool).self, context: .default)
            {
                let jsonData: Data? = deleted ? nil : injectMeta(into: content, versionId: vid, lastUpdated: lastUpdated)
                entries.append(HistoryRawEntry(resourceType: "Condition", id: id, versionId: vid, lastUpdated: lastUpdated, jsonData: jsonData, deleted: deleted))
            }
            if entries.isEmpty {
                if since != nil {
                    let existRows = try await conn.query(
                        """
                        SELECT 1 FROM resources WHERE resource_type = 'Condition' AND id = \(id) LIMIT 1
                        """, logger: logger)
                    var exists = false
                    for try await _ in existRows { exists = true }
                    if !exists { throw FHIRServerError.notFound(resourceType: "Condition", id: id) }
                } else {
                    throw FHIRServerError.notFound(resourceType: "Condition", id: id)
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
                    WHERE resource_type = 'Condition' AND last_updated >= \(since)
                    ORDER BY last_updated DESC, id, version_id DESC
                    LIMIT \(Int64(count))
                    """, logger: logger)
            } else {
                rows = try await conn.query(
                    """
                    SELECT id, version_id, last_updated, content, deleted
                    FROM resources
                    WHERE resource_type = 'Condition'
                    ORDER BY last_updated DESC, id, version_id DESC
                    LIMIT \(Int64(count))
                    """, logger: logger)
            }
            var entries: [HistoryRawEntry] = []
            for try await (rid, vid, lastUpdated, content, deleted) in
                rows.decode((String, Int64, Date, String, Bool).self, context: .default)
            {
                let jsonData: Data? = deleted ? nil : injectMeta(into: content, versionId: vid, lastUpdated: lastUpdated)
                entries.append(HistoryRawEntry(resourceType: "Condition", id: rid, versionId: vid, lastUpdated: lastUpdated, jsonData: jsonData, deleted: deleted))
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
                WHERE resource_type = 'Condition' AND id = \(id)
                ORDER BY version_id DESC
                LIMIT 1
                """, logger: logger)
            var found: ReadResult? = nil
            for try await (versionId, lastUpdated, content, deleted) in
                rows.decode((Int64, Date, String, Bool).self, context: .default)
            {
                if deleted { throw FHIRServerError.gone(resourceType: "Condition", id: id) }
                let jsonData = injectMeta(into: content, versionId: versionId, lastUpdated: lastUpdated)
                found = ReadResult(jsonData: jsonData, versionId: versionId, lastUpdated: lastUpdated)
            }
            guard let result = found else {
                throw FHIRServerError.notFound(resourceType: "Condition", id: id)
            }
            return result
        }
    }

    public func search(query: ConditionSearchQuery) async throws -> SearchResult {
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

    private func write(id: String, condition: Condition, ifMatch: Int64?) async throws -> WriteResult {
        // Validation hook — keep this call; it's one of the three open doors.
        try validate(condition)

        var cond = condition
        cond.id   = FHIRPrimitive(FHIRString(id))
        let originalMeta = cond.meta
        cond.meta = nil

        let jsonData   = try JSONEncoder().encode(cond)
        let jsonString = String(data: jsonData, encoding: .utf8)!
        var searchParams = extractConditionSearchParams(cond)
        appendMetaParams(&searchParams, meta: originalMeta)

        return try await client.withConnection { conn in
            let (versionId, lastUpdated) = try await writeResource(
                conn: conn, resourceType: "Condition", id: id,
                jsonString: jsonString, ifMatch: ifMatch, params: searchParams, logger: logger)
            let responseData = injectMeta(into: jsonString, versionId: versionId, lastUpdated: lastUpdated)
            return WriteResult(id: id, versionId: versionId, lastUpdated: lastUpdated, jsonData: responseData)
        }
    }

    private func validate(_ cond: Condition) throws {}

    private func buildSearchSQL(query: ConditionSearchQuery) throws -> (String, PostgresBindings) {
        var binds = PostgresBindings()
        var n = 0
        func bind(_ val: some PostgresDynamicTypeEncodable) -> String {
            n += 1; binds.append(val); return "$\(n)"
        }

        var filterCTEs: [(name: String, sql: String)] = []

        // subject — idx_reference (both 'subject' and 'patient' param_names)
        if let subject = query.subject {
            let parts = subject.split(separator: "/")
            if parts.count == 2 {
                let refTypeP = bind(String(parts[0]))
                let refIdP   = bind(String(parts[1]))
                filterCTEs.append(("f_subject", """
                    SELECT DISTINCT resource_id FROM idx_reference
                    WHERE resource_type = 'Condition' AND param_name IN ('subject', 'patient')
                      AND ref_type = \(refTypeP) AND ref_id = \(refIdP)
                    """))
            } else {
                let refIdP = bind(subject)
                filterCTEs.append(("f_subject", """
                    SELECT DISTINCT resource_id FROM idx_reference
                    WHERE resource_type = 'Condition' AND param_name IN ('subject', 'patient')
                      AND ref_id = \(refIdP)
                    """))
            }
        }

        // encounter — idx_reference
        if let enc = query.encounter {
            let parts = enc.split(separator: "/")
            if parts.count == 2 {
                let refTypeP = bind(String(parts[0]))
                let refIdP   = bind(String(parts[1]))
                filterCTEs.append(("f_encounter", """
                    SELECT DISTINCT resource_id FROM idx_reference
                    WHERE resource_type = 'Condition' AND param_name = 'encounter'
                      AND ref_type = \(refTypeP) AND ref_id = \(refIdP)
                    """))
            } else {
                let refIdP = bind(enc)
                filterCTEs.append(("f_encounter", """
                    SELECT DISTINCT resource_id FROM idx_reference
                    WHERE resource_type = 'Condition' AND param_name = 'encounter'
                      AND ref_id = \(refIdP)
                    """))
            }
        }

        // clinical-status — token OR
        if !query.clinicalStatus.isEmpty {
            var orClauses: [String] = []
            for tok in query.clinicalStatus {
                if tok.code.isEmpty, let sys = tok.system {
                    orClauses.append("system = \(bind(sys))")
                } else {
                    let codeP = bind(tok.code)
                    var sysCond = ""
                    if let sys = tok.system { sysCond = " AND system = \(bind(sys))" }
                    orClauses.append("(code = \(codeP)\(sysCond))")
                }
            }
            filterCTEs.append(("f_clinical_status", """
                SELECT DISTINCT resource_id FROM idx_token
                WHERE resource_type = 'Condition' AND param_name = 'clinical-status'
                  AND (\(orClauses.joined(separator: " OR ")))
                """))
        }

        // verification-status — token OR
        if !query.verificationStatus.isEmpty {
            var orClauses: [String] = []
            for tok in query.verificationStatus {
                if tok.code.isEmpty, let sys = tok.system {
                    orClauses.append("system = \(bind(sys))")
                } else {
                    let codeP = bind(tok.code)
                    var sysCond = ""
                    if let sys = tok.system { sysCond = " AND system = \(bind(sys))" }
                    orClauses.append("(code = \(codeP)\(sysCond))")
                }
            }
            filterCTEs.append(("f_ver_status", """
                SELECT DISTINCT resource_id FROM idx_token
                WHERE resource_type = 'Condition' AND param_name = 'verification-status'
                  AND (\(orClauses.joined(separator: " OR ")))
                """))
        }

        // category — token OR
        if !query.category.isEmpty {
            var orClauses: [String] = []
            for tok in query.category {
                if tok.code.isEmpty, let sys = tok.system {
                    orClauses.append("system = \(bind(sys))")
                } else {
                    let codeP = bind(tok.code)
                    var sysCond = ""
                    if let sys = tok.system { sysCond = " AND system = \(bind(sys))" }
                    orClauses.append("(code = \(codeP)\(sysCond))")
                }
            }
            filterCTEs.append(("f_category", """
                SELECT DISTINCT resource_id FROM idx_token
                WHERE resource_type = 'Condition' AND param_name = 'category'
                  AND (\(orClauses.joined(separator: " OR ")))
                """))
        }

        // code — token OR
        if !query.code.isEmpty {
            var orClauses: [String] = []
            for tok in query.code {
                if tok.code.isEmpty, let sys = tok.system {
                    orClauses.append("system = \(bind(sys))")
                } else {
                    let codeP = bind(tok.code)
                    var sysCond = ""
                    if let sys = tok.system { sysCond = " AND system = \(bind(sys))" }
                    orClauses.append("(code = \(codeP)\(sysCond))")
                }
            }
            filterCTEs.append(("f_code", """
                SELECT DISTINCT resource_id FROM idx_token
                WHERE resource_type = 'Condition' AND param_name = 'code'
                  AND (\(orClauses.joined(separator: " OR ")))
                """))
        }

        // identifier — token OR
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
                    WHERE resource_type = 'Condition' AND param_name = 'identifier'
                      AND (\(orClauses.joined(separator: " OR ")))
                    """))
            }
        }

        // onset-date — idx_date range
        for (i, dp) in query.onsetDate.enumerated() {
            let startP = bind(dp.dateStart)
            let endP   = bind(dp.dateEnd)
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
            filterCTEs.append(("f_onset\(i)", """
                SELECT DISTINCT resource_id FROM idx_date
                WHERE resource_type = 'Condition' AND param_name = 'onset-date' AND \(cond)
                """))
        }

        // abatement-date — idx_date range
        for (i, dp) in query.abatementDate.enumerated() {
            let startP = bind(dp.dateStart)
            let endP   = bind(dp.dateEnd)
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
            filterCTEs.append(("f_abatement\(i)", """
                SELECT DISTINCT resource_id FROM idx_date
                WHERE resource_type = 'Condition' AND param_name = 'abatement-date' AND \(cond)
                """))
        }

        // asserter — idx_reference
        if let asserter = query.asserter {
            let parts = asserter.split(separator: "/")
            if parts.count == 2 {
                let refTypeP = bind(String(parts[0])); let refIdP = bind(String(parts[1]))
                filterCTEs.append(("f_asserter", """
                    SELECT DISTINCT resource_id FROM idx_reference
                    WHERE resource_type = 'Condition' AND param_name = 'asserter'
                      AND ref_type = \(refTypeP) AND ref_id = \(refIdP)
                    """))
            } else {
                let refIdP = bind(asserter)
                filterCTEs.append(("f_asserter", """
                    SELECT DISTINCT resource_id FROM idx_reference
                    WHERE resource_type = 'Condition' AND param_name = 'asserter'
                      AND ref_id = \(refIdP)
                    """))
            }
        }

        // evidence-detail — idx_reference
        if let evDetail = query.evidenceDetail {
            let parts = evDetail.split(separator: "/")
            if parts.count == 2 {
                let refTypeP = bind(String(parts[0])); let refIdP = bind(String(parts[1]))
                filterCTEs.append(("f_evidence_detail", """
                    SELECT DISTINCT resource_id FROM idx_reference
                    WHERE resource_type = 'Condition' AND param_name = 'evidence-detail'
                      AND ref_type = \(refTypeP) AND ref_id = \(refIdP)
                    """))
            } else {
                let refIdP = bind(evDetail)
                filterCTEs.append(("f_evidence_detail", """
                    SELECT DISTINCT resource_id FROM idx_reference
                    WHERE resource_type = 'Condition' AND param_name = 'evidence-detail'
                      AND ref_id = \(refIdP)
                    """))
            }
        }

        // body-site — token OR
        if !query.bodySite.isEmpty {
            var orClauses: [String] = []
            for tok in query.bodySite {
                if tok.code.isEmpty, let sys = tok.system {
                    orClauses.append("system = \(bind(sys))")
                } else {
                    let codeP = bind(tok.code)
                    var sysCond = ""
                    if let sys = tok.system { sysCond = " AND system = \(bind(sys))" }
                    orClauses.append("(code = \(codeP)\(sysCond))")
                }
            }
            filterCTEs.append(("f_body_site", """
                SELECT DISTINCT resource_id FROM idx_token
                WHERE resource_type = 'Condition' AND param_name = 'body-site'
                  AND (\(orClauses.joined(separator: " OR ")))
                """))
        }

        // evidence — token OR
        if !query.evidence.isEmpty {
            var orClauses: [String] = []
            for tok in query.evidence {
                if tok.code.isEmpty, let sys = tok.system {
                    orClauses.append("system = \(bind(sys))")
                } else {
                    let codeP = bind(tok.code)
                    var sysCond = ""
                    if let sys = tok.system { sysCond = " AND system = \(bind(sys))" }
                    orClauses.append("(code = \(codeP)\(sysCond))")
                }
            }
            filterCTEs.append(("f_evidence", """
                SELECT DISTINCT resource_id FROM idx_token
                WHERE resource_type = 'Condition' AND param_name = 'evidence'
                  AND (\(orClauses.joined(separator: " OR ")))
                """))
        }

        // severity — token OR
        if !query.severity.isEmpty {
            var orClauses: [String] = []
            for tok in query.severity {
                if tok.code.isEmpty, let sys = tok.system {
                    orClauses.append("system = \(bind(sys))")
                } else {
                    let codeP = bind(tok.code)
                    var sysCond = ""
                    if let sys = tok.system { sysCond = " AND system = \(bind(sys))" }
                    orClauses.append("(code = \(codeP)\(sysCond))")
                }
            }
            filterCTEs.append(("f_severity", """
                SELECT DISTINCT resource_id FROM idx_token
                WHERE resource_type = 'Condition' AND param_name = 'severity'
                  AND (\(orClauses.joined(separator: " OR ")))
                """))
        }

        // stage — token OR
        if !query.stage.isEmpty {
            var orClauses: [String] = []
            for tok in query.stage {
                if tok.code.isEmpty, let sys = tok.system {
                    orClauses.append("system = \(bind(sys))")
                } else {
                    let codeP = bind(tok.code)
                    var sysCond = ""
                    if let sys = tok.system { sysCond = " AND system = \(bind(sys))" }
                    orClauses.append("(code = \(codeP)\(sysCond))")
                }
            }
            filterCTEs.append(("f_stage", """
                SELECT DISTINCT resource_id FROM idx_token
                WHERE resource_type = 'Condition' AND param_name = 'stage'
                  AND (\(orClauses.joined(separator: " OR ")))
                """))
        }

        // onset-age / abatement-age — idx_quantity numeric filter
        func quantityCTE(name: String, paramName: String, quantities: [ConditionSearchQuery.QuantityParam]) -> (String, String) {
            var orClauses: [String] = []
            for qp in quantities {
                var cond: String
                switch qp.prefix {
                case .eq:
                    let lo = bind(qp.value - 0.5 * pow(10.0, Double(-qp.decimalPlaces)))
                    let hi = bind(qp.value + 0.5 * pow(10.0, Double(-qp.decimalPlaces)))
                    cond = "value >= \(lo) AND value <= \(hi)"
                case .ne: cond = "value != \(bind(qp.value))"
                case .lt: cond = "value < \(bind(qp.value))"
                case .le: cond = "value <= \(bind(qp.value))"
                case .gt: cond = "value > \(bind(qp.value))"
                case .ge: cond = "value >= \(bind(qp.value))"
                case .sa: cond = "value > \(bind(qp.value))"
                case .eb: cond = "value < \(bind(qp.value))"
                case .ap: let lo = bind(qp.value * 0.9); let hi = bind(qp.value * 1.1); cond = "value BETWEEN \(lo) AND \(hi)"
                }
                if let sys = qp.system { cond += " AND system = \(bind(sys))" }
                if let code = qp.code  { cond += " AND code = \(bind(code))" }
                orClauses.append("(\(cond))")
            }
            return (name, "SELECT DISTINCT resource_id FROM idx_quantity WHERE resource_type = 'Condition' AND param_name = '\(paramName)' AND (\(orClauses.joined(separator: " OR ")))")
        }
        if !query.onsetAge.isEmpty      { filterCTEs.append(quantityCTE(name: "f_onset_age",     paramName: "onset-age",      quantities: query.onsetAge)) }
        if !query.abatementAge.isEmpty  { filterCTEs.append(quantityCTE(name: "f_abatement_age", paramName: "abatement-age",  quantities: query.abatementAge)) }

        // onset-info — idx_string, modifier-aware
        if let onsetInfo = query.onsetInfo {
            let cond: String
            switch onsetInfo.modifier {
            case .startsWith: cond = "lower(value) LIKE lower(\(bind(onsetInfo.value + "%")))"
            case .contains, .text: cond = "value ILIKE \(bind("%" + onsetInfo.value + "%"))"
            case .exact: cond = "value = \(bind(onsetInfo.value))"
            }
            filterCTEs.append(("f_onset_info",
                "SELECT DISTINCT resource_id FROM idx_string WHERE resource_type = 'Condition' AND param_name = 'onset-info' AND \(cond)"))
        }

        // abatement-string — idx_string, modifier-aware
        if let abatStr = query.abatementString {
            let cond: String
            switch abatStr.modifier {
            case .startsWith: cond = "lower(value) LIKE lower(\(bind(abatStr.value + "%")))"
            case .contains, .text: cond = "value ILIKE \(bind("%" + abatStr.value + "%"))"
            case .exact: cond = "value = \(bind(abatStr.value))"
            }
            filterCTEs.append(("f_abatement_string",
                "SELECT DISTINCT resource_id FROM idx_string WHERE resource_type = 'Condition' AND param_name = 'abatement-string' AND \(cond)"))
        }

        // recorded-date — idx_date range
        for (i, dp) in query.recordedDate.enumerated() {
            let startP = bind(dp.dateStart)
            let endP   = bind(dp.dateEnd)
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
            filterCTEs.append(("f_recorded\(i)", """
                SELECT DISTINCT resource_id FROM idx_date
                WHERE resource_type = 'Condition' AND param_name = 'recorded-date' AND \(cond)
                """))
        }

        // ── WHERE conditions ──────────────────────────────────────────────────

        var extraConditions: [String] = []

        if !query.id.isEmpty {
            let phs = query.id.map { bind($0) }.joined(separator: ", ")
            extraConditions.append("r.id IN (\(phs))")
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
            case .ap: cond = "r.last_updated BETWEEN \(bind(lu.apExpandedStart)) AND \(bind(lu.apExpandedEnd))"
            }
            extraConditions.append(cond)
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
                extraConditions.append("r.id NOT IN (SELECT resource_id FROM idx_token WHERE resource_type = 'Condition' AND param_name = 'identifier' AND (\(orClauses.joined(separator: " OR "))))")
            }
        }

        if !query.clinicalStatusNot.isEmpty {
            var orClauses: [String] = []
            for tok in query.clinicalStatusNot {
                if tok.code.isEmpty, let sys = tok.system {
                    orClauses.append("system = \(bind(sys))")
                } else {
                    let codeP = bind(tok.code)
                    var sysCond = ""
                    if let sys = tok.system { sysCond = " AND system = \(bind(sys))" }
                    orClauses.append("(code = \(codeP)\(sysCond))")
                }
            }
            extraConditions.append("r.id NOT IN (SELECT resource_id FROM idx_token WHERE resource_type = 'Condition' AND param_name = 'clinical-status' AND (\(orClauses.joined(separator: " OR "))))")
        }

        if !query.verificationStatusNot.isEmpty {
            var orClauses: [String] = []
            for tok in query.verificationStatusNot {
                if tok.code.isEmpty, let sys = tok.system {
                    orClauses.append("system = \(bind(sys))")
                } else {
                    let codeP = bind(tok.code)
                    var sysCond = ""
                    if let sys = tok.system { sysCond = " AND system = \(bind(sys))" }
                    orClauses.append("(code = \(codeP)\(sysCond))")
                }
            }
            extraConditions.append("r.id NOT IN (SELECT resource_id FROM idx_token WHERE resource_type = 'Condition' AND param_name = 'verification-status' AND (\(orClauses.joined(separator: " OR "))))")
        }

        if !query.categoryNot.isEmpty {
            var orClauses: [String] = []
            for tok in query.categoryNot {
                if tok.code.isEmpty, let sys = tok.system {
                    orClauses.append("system = \(bind(sys))")
                } else {
                    let codeP = bind(tok.code)
                    var sysCond = ""
                    if let sys = tok.system { sysCond = " AND system = \(bind(sys))" }
                    orClauses.append("(code = \(codeP)\(sysCond))")
                }
            }
            extraConditions.append("r.id NOT IN (SELECT resource_id FROM idx_token WHERE resource_type = 'Condition' AND param_name = 'category' AND (\(orClauses.joined(separator: " OR "))))")
        }

        if !query.codeNot.isEmpty {
            var orClauses: [String] = []
            for tok in query.codeNot {
                if tok.code.isEmpty, let sys = tok.system {
                    orClauses.append("system = \(bind(sys))")
                } else {
                    let codeP = bind(tok.code)
                    var sysCond = ""
                    if let sys = tok.system { sysCond = " AND system = \(bind(sys))" }
                    orClauses.append("(code = \(codeP)\(sysCond))")
                }
            }
            extraConditions.append("r.id NOT IN (SELECT resource_id FROM idx_token WHERE resource_type = 'Condition' AND param_name = 'code' AND (\(orClauses.joined(separator: " OR "))))")
        }

        func notTokenCond(paramName: String, tokens: [ConditionSearchQuery.TokenParam]) -> String {
            var orClauses: [String] = []
            for tok in tokens {
                if tok.code.isEmpty, let sys = tok.system { orClauses.append("system = \(bind(sys))") }
                else { let cp = bind(tok.code); var sc = ""; if let s = tok.system { sc = " AND system = \(bind(s))" }; orClauses.append("(code = \(cp)\(sc))") }
            }
            return "r.id NOT IN (SELECT resource_id FROM idx_token WHERE resource_type = 'Condition' AND param_name = '\(paramName)' AND (\(orClauses.joined(separator: " OR "))))"
        }

        if !query.bodySiteNot.isEmpty { extraConditions.append(notTokenCond(paramName: "body-site", tokens: query.bodySiteNot)) }
        if !query.evidenceNot.isEmpty { extraConditions.append(notTokenCond(paramName: "evidence",  tokens: query.evidenceNot)) }
        if !query.severityNot.isEmpty { extraConditions.append(notTokenCond(paramName: "severity",  tokens: query.severityNot)) }
        if !query.stageNot.isEmpty    { extraConditions.append(notTokenCond(paramName: "stage",     tokens: query.stageNot)) }

        for paramName in query.missing.keys.sorted() {
            if let sub = conditionMissingSubquery(param: paramName) {
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
                index: filterCTEs.count + i, sourceType: "Condition",
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
                index: i, mainType: "Condition",
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
                "SELECT DISTINCT resource_id FROM idx_string WHERE resource_type = 'Condition' AND param_name = \(pn) AND value ILIKE \(val)"))
        }

        // meta params: _tag, _security, _profile
        let strBind: (String) -> String = { bind($0) }
        let (metaCTEs, metaWhere) = metaFilterCTEs(resourceType: "Condition", meta: query.meta, bind: strBind)
        filterCTEs += metaCTEs
        extraConditions += metaWhere

        let idsInner = buildIdsInner(
            resourceType: "Condition",
            filterCTEs: filterCTEs,
            extraConditions: extraConditions
        )

        // ── Sort — `dateAscending`/`dateDescending` maps to onset-date ─────────

        // ── Multi-sort paged CTE ──────────────────────────────────────────────
        // Cursor binds MUST happen before limitP bind.
        let sortResult = buildMultiSort(
            sortKeys: query.sortKeys,
            resourceType: "Condition",
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
            ? "FROM paged p JOIN resources r ON r.resource_type = 'Condition' AND r.id = p.id AND r.version_id = p.version_id"
            : "FROM paged p CROSS JOIN total_count t JOIN resources r ON r.resource_type = 'Condition' AND r.id = p.id AND r.version_id = p.version_id"

        let sql = "\(withClause)\nSELECT p.id, p.version_id, p.last_updated, r.content, \(totalExpr), p.sort_val_concat\n\(fromClause)\nORDER BY \(sortResult.outerOrderBy)"
        return (sql, binds)
    }

    private func buildCountSQL(query: ConditionSearchQuery) throws -> (String, PostgresBindings) {
        var binds = PostgresBindings()
        var n = 0
        func bind(_ val: some PostgresDynamicTypeEncodable) -> String {
            n += 1; binds.append(val); return "$\(n)"
        }

        var filterCTEs: [(name: String, sql: String)] = []

        if let subject = query.subject {
            let parts = subject.split(separator: "/")
            if parts.count == 2 {
                let refTypeP = bind(String(parts[0])); let refIdP = bind(String(parts[1]))
                filterCTEs.append(("f_subject",
                    "SELECT DISTINCT resource_id FROM idx_reference WHERE resource_type = 'Condition' AND param_name IN ('subject', 'patient') AND ref_type = \(refTypeP) AND ref_id = \(refIdP)"))
            } else {
                let refIdP = bind(subject)
                filterCTEs.append(("f_subject",
                    "SELECT DISTINCT resource_id FROM idx_reference WHERE resource_type = 'Condition' AND param_name IN ('subject', 'patient') AND ref_id = \(refIdP)"))
            }
        }

        if let enc = query.encounter {
            let parts = enc.split(separator: "/")
            if parts.count == 2 {
                let refTypeP = bind(String(parts[0])); let refIdP = bind(String(parts[1]))
                filterCTEs.append(("f_encounter",
                    "SELECT DISTINCT resource_id FROM idx_reference WHERE resource_type = 'Condition' AND param_name = 'encounter' AND ref_type = \(refTypeP) AND ref_id = \(refIdP)"))
            } else {
                let refIdP = bind(enc)
                filterCTEs.append(("f_encounter",
                    "SELECT DISTINCT resource_id FROM idx_reference WHERE resource_type = 'Condition' AND param_name = 'encounter' AND ref_id = \(refIdP)"))
            }
        }

        func tokenCTE(name: String, paramName: String, tokens: [ConditionSearchQuery.TokenParam]) -> (String, String) {
            var orClauses: [String] = []
            for tok in tokens {
                if tok.code.isEmpty, let sys = tok.system {
                    orClauses.append("system = \(bind(sys))")
                } else {
                    let codeP = bind(tok.code)
                    var sysCond = ""
                    if let sys = tok.system { sysCond = " AND system = \(bind(sys))" }
                    orClauses.append("(code = \(codeP)\(sysCond))")
                }
            }
            return (name,
                "SELECT DISTINCT resource_id FROM idx_token WHERE resource_type = 'Condition' AND param_name = '\(paramName)' AND (\(orClauses.joined(separator: " OR ")))")
        }

        if !query.clinicalStatus.isEmpty { filterCTEs.append(tokenCTE(name: "f_clinical_status", paramName: "clinical-status", tokens: query.clinicalStatus)) }
        if !query.verificationStatus.isEmpty { filterCTEs.append(tokenCTE(name: "f_ver_status", paramName: "verification-status", tokens: query.verificationStatus)) }
        if !query.category.isEmpty { filterCTEs.append(tokenCTE(name: "f_category", paramName: "category", tokens: query.category)) }
        if !query.code.isEmpty { filterCTEs.append(tokenCTE(name: "f_code", paramName: "code", tokens: query.code)) }

        if !query.identifier.isEmpty {
            var orClauses: [String] = []
            for ident in query.identifier {
                if ident.code.isEmpty {
                    if case .specific(let sys?) = ident.systemFilter { orClauses.append("system = \(bind(sys))") }
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
                    "SELECT DISTINCT resource_id FROM idx_token WHERE resource_type = 'Condition' AND param_name = 'identifier' AND (\(orClauses.joined(separator: " OR ")))"))
            }
        }

        func dateCTEs(prefix: String, paramName: String, dates: [ConditionSearchQuery.DateParam]) {
            for (i, dp) in dates.enumerated() {
                let startP = bind(dp.dateStart)
                let endP   = bind(dp.dateEnd)
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
                filterCTEs.append(("\(prefix)\(i)",
                    "SELECT DISTINCT resource_id FROM idx_date WHERE resource_type = 'Condition' AND param_name = '\(paramName)' AND \(cond)"))
            }
        }
        dateCTEs(prefix: "f_onset", paramName: "onset-date", dates: query.onsetDate)
        dateCTEs(prefix: "f_abatement", paramName: "abatement-date", dates: query.abatementDate)
        dateCTEs(prefix: "f_recorded", paramName: "recorded-date", dates: query.recordedDate)

        func refCTECount(name: String, paramName: String, ref: String) -> (String, String) {
            let parts = ref.split(separator: "/")
            if parts.count == 2 {
                let tP = bind(String(parts[0])); let iP = bind(String(parts[1]))
                return (name, "SELECT DISTINCT resource_id FROM idx_reference WHERE resource_type = 'Condition' AND param_name = '\(paramName)' AND ref_type = \(tP) AND ref_id = \(iP)")
            } else {
                let iP = bind(ref)
                return (name, "SELECT DISTINCT resource_id FROM idx_reference WHERE resource_type = 'Condition' AND param_name = '\(paramName)' AND ref_id = \(iP)")
            }
        }
        if let v = query.asserter      { filterCTEs.append(refCTECount(name: "f_asserter",        paramName: "asserter",        ref: v)) }
        if let v = query.evidenceDetail { filterCTEs.append(refCTECount(name: "f_evidence_detail", paramName: "evidence-detail", ref: v)) }

        func tokenCTECount(name: String, paramName: String, tokens: [ConditionSearchQuery.TokenParam]) -> (String, String) {
            var orClauses: [String] = []
            for tok in tokens {
                if tok.code.isEmpty, let sys = tok.system { orClauses.append("system = \(bind(sys))") }
                else { let cp = bind(tok.code); var sc = ""; if let s = tok.system { sc = " AND system = \(bind(s))" }; orClauses.append("(code = \(cp)\(sc))") }
            }
            return (name, "SELECT DISTINCT resource_id FROM idx_token WHERE resource_type = 'Condition' AND param_name = '\(paramName)' AND (\(orClauses.joined(separator: " OR ")))")
        }
        if !query.bodySite.isEmpty { filterCTEs.append(tokenCTECount(name: "f_body_site", paramName: "body-site", tokens: query.bodySite)) }
        if !query.evidence.isEmpty { filterCTEs.append(tokenCTECount(name: "f_evidence",  paramName: "evidence",  tokens: query.evidence)) }
        if !query.severity.isEmpty { filterCTEs.append(tokenCTECount(name: "f_severity",  paramName: "severity",  tokens: query.severity)) }
        if !query.stage.isEmpty    { filterCTEs.append(tokenCTECount(name: "f_stage",     paramName: "stage",     tokens: query.stage)) }

        func quantityCTECount(name: String, paramName: String, quantities: [ConditionSearchQuery.QuantityParam]) -> (String, String) {
            var orClauses: [String] = []
            for qp in quantities {
                var cond: String
                switch qp.prefix {
                case .eq:
                    let lo = bind(qp.value - 0.5 * pow(10.0, Double(-qp.decimalPlaces)))
                    let hi = bind(qp.value + 0.5 * pow(10.0, Double(-qp.decimalPlaces)))
                    cond = "value >= \(lo) AND value <= \(hi)"
                case .ne: cond = "value != \(bind(qp.value))"
                case .lt: cond = "value < \(bind(qp.value))"
                case .le: cond = "value <= \(bind(qp.value))"
                case .gt: cond = "value > \(bind(qp.value))"
                case .ge: cond = "value >= \(bind(qp.value))"
                case .sa: cond = "value > \(bind(qp.value))"
                case .eb: cond = "value < \(bind(qp.value))"
                case .ap: let lo = bind(qp.value * 0.9); let hi = bind(qp.value * 1.1); cond = "value BETWEEN \(lo) AND \(hi)"
                }
                if let sys = qp.system { cond += " AND system = \(bind(sys))" }
                if let code = qp.code  { cond += " AND code = \(bind(code))" }
                orClauses.append("(\(cond))")
            }
            return (name, "SELECT DISTINCT resource_id FROM idx_quantity WHERE resource_type = 'Condition' AND param_name = '\(paramName)' AND (\(orClauses.joined(separator: " OR ")))")
        }
        if !query.onsetAge.isEmpty      { filterCTEs.append(quantityCTECount(name: "f_onset_age",     paramName: "onset-age",      quantities: query.onsetAge)) }
        if !query.abatementAge.isEmpty  { filterCTEs.append(quantityCTECount(name: "f_abatement_age", paramName: "abatement-age",  quantities: query.abatementAge)) }

        if let onsetInfo = query.onsetInfo {
            let cond: String
            switch onsetInfo.modifier {
            case .startsWith: cond = "lower(value) LIKE lower(\(bind(onsetInfo.value + "%")))"
            case .contains, .text: cond = "value ILIKE \(bind("%" + onsetInfo.value + "%"))"
            case .exact: cond = "value = \(bind(onsetInfo.value))"
            }
            filterCTEs.append(("f_onset_info",
                "SELECT DISTINCT resource_id FROM idx_string WHERE resource_type = 'Condition' AND param_name = 'onset-info' AND \(cond)"))
        }
        if let abatStr = query.abatementString {
            let cond: String
            switch abatStr.modifier {
            case .startsWith: cond = "lower(value) LIKE lower(\(bind(abatStr.value + "%")))"
            case .contains, .text: cond = "value ILIKE \(bind("%" + abatStr.value + "%"))"
            case .exact: cond = "value = \(bind(abatStr.value))"
            }
            filterCTEs.append(("f_abatement_string",
                "SELECT DISTINCT resource_id FROM idx_string WHERE resource_type = 'Condition' AND param_name = 'abatement-string' AND \(cond)"))
        }

        var whereConditions = ["r.resource_type = 'Condition'", "r.deleted = false"]
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
            case .ap: cond = "r.last_updated BETWEEN \(bind(lu.apExpandedStart)) AND \(bind(lu.apExpandedEnd))"
            }
            whereConditions.append(cond)
        }

        func notTokenCondition(paramName: String, tokens: [ConditionSearchQuery.TokenParam]) -> String {
            var orClauses: [String] = []
            for tok in tokens {
                if tok.code.isEmpty, let sys = tok.system {
                    orClauses.append("system = \(bind(sys))")
                } else {
                    let codeP = bind(tok.code)
                    var sysCond = ""
                    if let sys = tok.system { sysCond = " AND system = \(bind(sys))" }
                    orClauses.append("(code = \(codeP)\(sysCond))")
                }
            }
            return "r.id NOT IN (SELECT resource_id FROM idx_token WHERE resource_type = 'Condition' AND param_name = '\(paramName)' AND (\(orClauses.joined(separator: " OR "))))"
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
                whereConditions.append("r.id NOT IN (SELECT resource_id FROM idx_token WHERE resource_type = 'Condition' AND param_name = 'identifier' AND (\(orClauses.joined(separator: " OR "))))")
            }
        }
        if !query.clinicalStatusNot.isEmpty { whereConditions.append(notTokenCondition(paramName: "clinical-status", tokens: query.clinicalStatusNot)) }
        if !query.verificationStatusNot.isEmpty { whereConditions.append(notTokenCondition(paramName: "verification-status", tokens: query.verificationStatusNot)) }
        if !query.categoryNot.isEmpty { whereConditions.append(notTokenCondition(paramName: "category", tokens: query.categoryNot)) }
        if !query.codeNot.isEmpty { whereConditions.append(notTokenCondition(paramName: "code", tokens: query.codeNot)) }
        if !query.bodySiteNot.isEmpty { whereConditions.append(notTokenCondition(paramName: "body-site", tokens: query.bodySiteNot)) }
        if !query.evidenceNot.isEmpty { whereConditions.append(notTokenCondition(paramName: "evidence",  tokens: query.evidenceNot)) }
        if !query.severityNot.isEmpty { whereConditions.append(notTokenCondition(paramName: "severity",  tokens: query.severityNot)) }
        if !query.stageNot.isEmpty    { whereConditions.append(notTokenCondition(paramName: "stage",     tokens: query.stageNot)) }

        for paramName in query.missing.keys.sorted() {
            if let sub = conditionMissingSubquery(param: paramName) {
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
                index: filterCTEs.count + i, sourceType: "Condition",
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
                index: i, mainType: "Condition",
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
                "SELECT DISTINCT resource_id FROM idx_string WHERE resource_type = 'Condition' AND param_name = \(pn) AND value ILIKE \(val)"))
        }

        // meta params: _tag, _security, _profile
        let strBind: (String) -> String = { bind($0) }
        let (metaCTEs, metaWhere) = metaFilterCTEs(resourceType: "Condition", meta: query.meta, bind: strBind)
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

    private func conditionMissingSubquery(param: String) -> String? {
        switch param {
        case "subject", "patient":    return "SELECT DISTINCT resource_id FROM idx_reference WHERE resource_type = 'Condition' AND param_name IN ('subject', 'patient')"
        case "clinical-status":       return "SELECT DISTINCT resource_id FROM idx_token WHERE resource_type = 'Condition' AND param_name = 'clinical-status'"
        case "verification-status":   return "SELECT DISTINCT resource_id FROM idx_token WHERE resource_type = 'Condition' AND param_name = 'verification-status'"
        case "category":              return "SELECT DISTINCT resource_id FROM idx_token WHERE resource_type = 'Condition' AND param_name = 'category'"
        case "code":                  return "SELECT DISTINCT resource_id FROM idx_token WHERE resource_type = 'Condition' AND param_name = 'code'"
        case "identifier":            return "SELECT DISTINCT resource_id FROM idx_token WHERE resource_type = 'Condition' AND param_name = 'identifier'"
        case "onset-date":            return "SELECT DISTINCT resource_id FROM idx_date WHERE resource_type = 'Condition' AND param_name = 'onset-date'"
        case "abatement-date":        return "SELECT DISTINCT resource_id FROM idx_date WHERE resource_type = 'Condition' AND param_name = 'abatement-date'"
        case "recorded-date":         return "SELECT DISTINCT resource_id FROM idx_date WHERE resource_type = 'Condition' AND param_name = 'recorded-date'"
        case "asserter":              return "SELECT DISTINCT resource_id FROM idx_reference WHERE resource_type = 'Condition' AND param_name = 'asserter'"
        case "evidence-detail":       return "SELECT DISTINCT resource_id FROM idx_reference WHERE resource_type = 'Condition' AND param_name = 'evidence-detail'"
        case "body-site":             return "SELECT DISTINCT resource_id FROM idx_token WHERE resource_type = 'Condition' AND param_name = 'body-site'"
        case "evidence":              return "SELECT DISTINCT resource_id FROM idx_token WHERE resource_type = 'Condition' AND param_name = 'evidence'"
        case "severity":              return "SELECT DISTINCT resource_id FROM idx_token WHERE resource_type = 'Condition' AND param_name = 'severity'"
        case "stage":                 return "SELECT DISTINCT resource_id FROM idx_token WHERE resource_type = 'Condition' AND param_name = 'stage'"
        case "onset-info":            return "SELECT DISTINCT resource_id FROM idx_string WHERE resource_type = 'Condition' AND param_name = 'onset-info'"
        case "abatement-string":      return "SELECT DISTINCT resource_id FROM idx_string WHERE resource_type = 'Condition' AND param_name = 'abatement-string'"
        case "onset-age":             return "SELECT DISTINCT resource_id FROM idx_quantity WHERE resource_type = 'Condition' AND param_name = 'onset-age'"
        case "abatement-age":         return "SELECT DISTINCT resource_id FROM idx_quantity WHERE resource_type = 'Condition' AND param_name = 'abatement-age'"
        default:                      return nil
        }
    }
}
