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
        public let jsonData: Data
    }

    public struct ReadResult: Sendable {
        public let jsonData: Data
        public let versionId: Int64
        public let lastUpdated: Date
    }

    public struct SearchResult: Sendable {
        public let entries: [RawEntry]
        public let total: Int?   // nil when _total=none
        public let nextCursor: ObservationSearchQuery.SearchCursor?
    }

    public struct DeleteResult: Sendable {
        public let versionId: Int64
        public let lastUpdated: Date
    }

    // ── Public API ────────────────────────────────────────────────────────────

    public func create(_ obs: Observation) async throws -> WriteResult {
        let id = UUID().uuidString.lowercased()
        return try await write(id: id, observation: obs, ifMatch: nil)
    }

    public func update(id: String, observation: Observation, ifMatch: Int64?) async throws -> WriteResult {
        return try await write(id: id, observation: observation, ifMatch: ifMatch)
    }

    /// DELETE /Observation/:id — logical delete; inserts a deleted=true version row.
    @discardableResult
    public func delete(id: String, ifMatch: Int64?) async throws -> DeleteResult {
        try await client.withConnection { conn in
            let (versionId, lastUpdated, _) = try await deleteResource(
                conn: conn, resourceType: "Observation", id: id, ifMatch: ifMatch, logger: logger)
            return DeleteResult(versionId: versionId, lastUpdated: lastUpdated)
        }
    }

    /// GET /Observation/:id/_history/:vid — returns exact stored version; 410 if that version is a delete marker.
    public func vread(id: String, versionId: Int64) async throws -> ReadResult {
        try await client.withConnection { conn in
            let rows = try await conn.query(
                """
                SELECT version_id, last_updated, content, deleted
                FROM resources
                WHERE resource_type = 'Observation' AND id = \(id) AND version_id = \(versionId)
                """, logger: logger)
            for try await (vid, lastUpdated, content, deleted) in
                rows.decode((Int64, Date, String, Bool).self, context: .default)
            {
                if deleted { throw FHIRServerError.gone(resourceType: "Observation", id: id) }
                let jsonData = injectMeta(into: content, versionId: vid, lastUpdated: lastUpdated)
                return ReadResult(jsonData: jsonData, versionId: vid, lastUpdated: lastUpdated)
            }
            throw FHIRServerError.notFound(resourceType: "Observation", id: id)
        }
    }

    /// GET /Observation/:id/_history — all versions newest-first; 404 if id never existed.
    public func history(id: String, since: Date? = nil, count: Int = 50) async throws -> [HistoryRawEntry] {
        try await client.withConnection { conn in
            let rows: PostgresRowSequence
            if let since {
                rows = try await conn.query(
                    """
                    SELECT version_id, last_updated, content, deleted
                    FROM resources
                    WHERE resource_type = 'Observation' AND id = \(id) AND last_updated >= \(since)
                    ORDER BY version_id DESC
                    LIMIT \(Int64(count))
                    """, logger: logger)
            } else {
                rows = try await conn.query(
                    """
                    SELECT version_id, last_updated, content, deleted
                    FROM resources
                    WHERE resource_type = 'Observation' AND id = \(id)
                    ORDER BY version_id DESC
                    LIMIT \(Int64(count))
                    """, logger: logger)
            }
            var entries: [HistoryRawEntry] = []
            for try await (vid, lastUpdated, content, deleted) in
                rows.decode((Int64, Date, String, Bool).self, context: .default)
            {
                let jsonData: Data? = deleted ? nil : injectMeta(into: content, versionId: vid, lastUpdated: lastUpdated)
                entries.append(HistoryRawEntry(resourceType: "Observation", id: id, versionId: vid, lastUpdated: lastUpdated, jsonData: jsonData, deleted: deleted))
            }
            if entries.isEmpty {
                if since != nil {
                    let existRows = try await conn.query(
                        """
                        SELECT 1 FROM resources WHERE resource_type = 'Observation' AND id = \(id) LIMIT 1
                        """, logger: logger)
                    var exists = false
                    for try await _ in existRows { exists = true }
                    if !exists { throw FHIRServerError.notFound(resourceType: "Observation", id: id) }
                } else {
                    throw FHIRServerError.notFound(resourceType: "Observation", id: id)
                }
            }
            return entries
        }
    }

    /// GET /Observation/_history — all Observation versions across all instances, optional _since filter.
    public func typeHistory(since: Date?, count: Int) async throws -> [HistoryRawEntry] {
        try await client.withConnection { conn in
            let rows: PostgresRowSequence
            if let since {
                rows = try await conn.query(
                    """
                    SELECT id, version_id, last_updated, content, deleted
                    FROM resources
                    WHERE resource_type = 'Observation' AND last_updated >= \(since)
                    ORDER BY last_updated DESC, id, version_id DESC
                    LIMIT \(Int64(count))
                    """, logger: logger)
            } else {
                rows = try await conn.query(
                    """
                    SELECT id, version_id, last_updated, content, deleted
                    FROM resources
                    WHERE resource_type = 'Observation'
                    ORDER BY last_updated DESC, id, version_id DESC
                    LIMIT \(Int64(count))
                    """, logger: logger)
            }
            var entries: [HistoryRawEntry] = []
            for try await (rid, vid, lastUpdated, content, deleted) in
                rows.decode((String, Int64, Date, String, Bool).self, context: .default)
            {
                let jsonData: Data? = deleted ? nil : injectMeta(into: content, versionId: vid, lastUpdated: lastUpdated)
                entries.append(HistoryRawEntry(resourceType: "Observation", id: rid, versionId: vid, lastUpdated: lastUpdated, jsonData: jsonData, deleted: deleted))
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
                let jsonData = injectMeta(into: content, versionId: versionId, lastUpdated: lastUpdated)
                found = ReadResult(jsonData: jsonData, versionId: versionId, lastUpdated: lastUpdated)
            }

            guard let result = found else {
                throw FHIRServerError.notFound(resourceType: "Observation", id: id)
            }
            return result
        }
    }

    public func search(query: ObservationSearchQuery) async throws -> SearchResult {
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
            let hasNext  = results.count > query.count
            let page     = Array(results.prefix(pageSize))
            let pageSortVals = Array(sortValTexts.prefix(pageSize))

            let nextCursor: ObservationSearchQuery.SearchCursor?
            if hasNext, let lastEntry = page.last, let lastSortVal = pageSortVals.last {
                nextCursor = ObservationSearchQuery.SearchCursor(
                    sortValue: lastSortVal, id: lastEntry.id, descending: query.sort.isDescending)
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

    private func write(id: String, observation: Observation, ifMatch: Int64?) async throws -> WriteResult {
        // Validation hook — keep this call; it's one of the three open doors.
        try validate(observation)

        var obs = observation
        obs.id   = FHIRPrimitive(FHIRString(id))
        let originalMeta = obs.meta
        obs.meta = nil

        let jsonData   = try JSONEncoder().encode(obs)
        let jsonString = String(data: jsonData, encoding: .utf8)!
        var searchParams = extractObservationSearchParams(obs)
        appendMetaParams(&searchParams, meta: originalMeta)

        return try await client.withConnection { conn in
            let (versionId, lastUpdated) = try await writeResource(
                conn: conn, resourceType: "Observation", id: id,
                jsonString: jsonString, ifMatch: ifMatch, params: searchParams, logger: logger)
            let responseData = injectMeta(into: jsonString, versionId: versionId, lastUpdated: lastUpdated)
            return WriteResult(id: id, versionId: versionId, lastUpdated: lastUpdated, jsonData: responseData)
        }
    }

    private func validate(_ obs: Observation) throws {}

    private func buildSearchSQL(query: ObservationSearchQuery) throws -> (String, PostgresBindings) {
        var binds = PostgresBindings()
        var n = 0
        func bind(_ val: some PostgresDynamicTypeEncodable) -> String {
            n += 1; binds.append(val); return "$\(n)"
        }

        var filterCTEs: [(name: String, sql: String)] = []

        // subject — idx_reference
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

        // code — token OR (system| = system-only match when code is empty)
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
                WHERE resource_type = 'Observation' AND param_name = 'code'
                  AND (\(orClauses.joined(separator: " OR ")))
                """))
        }

        // status — token OR (no system for status)
        if !query.status.isEmpty {
            let phs = query.status.map { bind($0) }.joined(separator: ", ")
            filterCTEs.append(("f_status", """
                SELECT DISTINCT resource_id FROM idx_token
                WHERE resource_type = 'Observation' AND param_name = 'status'
                  AND code IN (\(phs))
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
                WHERE resource_type = 'Observation' AND param_name = 'category'
                  AND (\(orClauses.joined(separator: " OR ")))
                """))
        }

        // identifier — token OR with system|code (same semantics as Patient identifier)
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
                    WHERE resource_type = 'Observation' AND param_name = 'identifier'
                      AND (\(orClauses.joined(separator: " OR ")))
                    """))
            }
        }

        // encounter — idx_reference
        if let encounter = query.encounter {
            let parts = encounter.split(separator: "/")
            if parts.count == 2 {
                let refTypeP = bind(String(parts[0]))
                let refIdP   = bind(String(parts[1]))
                filterCTEs.append(("f_encounter", """
                    SELECT DISTINCT resource_id FROM idx_reference
                    WHERE resource_type = 'Observation' AND param_name = 'encounter'
                      AND ref_type = \(refTypeP) AND ref_id = \(refIdP)
                    """))
            } else {
                let refIdP = bind(encounter)
                filterCTEs.append(("f_encounter", """
                    SELECT DISTINCT resource_id FROM idx_reference
                    WHERE resource_type = 'Observation' AND param_name = 'encounter'
                      AND ref_id = \(refIdP)
                    """))
            }
        }

        // performer — idx_reference
        if let performer = query.performer {
            let parts = performer.split(separator: "/")
            if parts.count == 2 {
                let refTypeP = bind(String(parts[0]))
                let refIdP   = bind(String(parts[1]))
                filterCTEs.append(("f_performer", """
                    SELECT DISTINCT resource_id FROM idx_reference
                    WHERE resource_type = 'Observation' AND param_name = 'performer'
                      AND ref_type = \(refTypeP) AND ref_id = \(refIdP)
                    """))
            } else {
                let refIdP = bind(performer)
                filterCTEs.append(("f_performer", """
                    SELECT DISTINCT resource_id FROM idx_reference
                    WHERE resource_type = 'Observation' AND param_name = 'performer'
                      AND ref_id = \(refIdP)
                    """))
            }
        }

        // new reference CTEs: based-on, derived-from, device, focus, has-member, part-of, specimen
        func obsRefCTE(name: String, paramName: String, ref: String) -> (String, String) {
            let parts = ref.split(separator: "/")
            if parts.count == 2 {
                let rtP = bind(String(parts[0])); let riP = bind(String(parts[1]))
                return (name, "SELECT DISTINCT resource_id FROM idx_reference WHERE resource_type = 'Observation' AND param_name = '\(paramName)' AND ref_type = \(rtP) AND ref_id = \(riP)")
            } else {
                let riP = bind(ref)
                return (name, "SELECT DISTINCT resource_id FROM idx_reference WHERE resource_type = 'Observation' AND param_name = '\(paramName)' AND ref_id = \(riP)")
            }
        }
        if let r = query.basedOn    { filterCTEs.append(obsRefCTE(name: "f_based_on",    paramName: "based-on",    ref: r)) }
        if let r = query.derivedFrom { filterCTEs.append(obsRefCTE(name: "f_derived_from", paramName: "derived-from", ref: r)) }
        if let r = query.device     { filterCTEs.append(obsRefCTE(name: "f_device",      paramName: "device",      ref: r)) }
        if let r = query.focus      { filterCTEs.append(obsRefCTE(name: "f_focus",       paramName: "focus",       ref: r)) }
        if let r = query.hasMember  { filterCTEs.append(obsRefCTE(name: "f_has_member",  paramName: "has-member",  ref: r)) }
        if let r = query.partOf     { filterCTEs.append(obsRefCTE(name: "f_part_of",     paramName: "part-of",     ref: r)) }
        if let r = query.specimen   { filterCTEs.append(obsRefCTE(name: "f_specimen",    paramName: "specimen",    ref: r)) }

        // token OR helper
        func obsTokenORCTE(name: String, paramName: String, tokens: [ObservationSearchQuery.TokenParam]) -> (String, String) {
            var or: [String] = []
            for tok in tokens {
                if tok.code.isEmpty, let sys = tok.system { or.append("system = \(bind(sys))") }
                else {
                    let cP = bind(tok.code); var sc = ""
                    if let sys = tok.system { sc = " AND system = \(bind(sys))" }
                    or.append("(code = \(cP)\(sc))")
                }
            }
            return (name, "SELECT DISTINCT resource_id FROM idx_token WHERE resource_type = 'Observation' AND param_name = '\(paramName)' AND (\(or.joined(separator: " OR ")))")
        }
        if !query.comboCode.isEmpty               { filterCTEs.append(obsTokenORCTE(name: "f_combo_code",                paramName: "combo-code",                tokens: query.comboCode)) }
        if !query.method.isEmpty                  { filterCTEs.append(obsTokenORCTE(name: "f_method",                     paramName: "method",                     tokens: query.method)) }
        if !query.valueConcept.isEmpty            { filterCTEs.append(obsTokenORCTE(name: "f_value_concept",              paramName: "value-concept",              tokens: query.valueConcept)) }
        if !query.comboValueConcept.isEmpty       { filterCTEs.append(obsTokenORCTE(name: "f_combo_value_concept",        paramName: "combo-value-concept",        tokens: query.comboValueConcept)) }
        if !query.dataAbsentReason.isEmpty        { filterCTEs.append(obsTokenORCTE(name: "f_data_absent",                paramName: "data-absent-reason",         tokens: query.dataAbsentReason)) }
        if !query.comboDataAbsentReason.isEmpty   { filterCTEs.append(obsTokenORCTE(name: "f_combo_data_absent",          paramName: "combo-data-absent-reason",   tokens: query.comboDataAbsentReason)) }
        if !query.componentDataAbsentReason.isEmpty { filterCTEs.append(obsTokenORCTE(name: "f_comp_data_absent",         paramName: "component-data-absent-reason", tokens: query.componentDataAbsentReason)) }
        if !query.componentValueConcept.isEmpty   { filterCTEs.append(obsTokenORCTE(name: "f_comp_value_concept",         paramName: "component-value-concept",    tokens: query.componentValueConcept)) }

        // value-date — idx_date
        for (i, dp) in query.valueDate.enumerated() {
            let sP = bind(dp.dateStart); let eP = bind(dp.dateEnd)
            let cond: String
            switch dp.prefix {
            case .eq: cond = "date_start <= \(eP) AND date_end >= \(sP)"
            case .ne: cond = "NOT (date_start <= \(eP) AND date_end >= \(sP))"
            case .lt: cond = "date_end < \(sP)"
            case .le: cond = "date_start <= \(eP)"
            case .gt: cond = "date_start > \(eP)"
            case .ge: cond = "date_end >= \(sP)"
            case .sa: cond = "date_start > \(eP)"
            case .eb: cond = "date_end < \(sP)"
            case .ap: cond = "date_start <= \(bind(dp.apExpandedEnd)) AND date_end >= \(bind(dp.apExpandedStart))"
            }
            filterCTEs.append(("f_vdate\(i)", "SELECT DISTINCT resource_id FROM idx_date WHERE resource_type = 'Observation' AND param_name = 'value-date' AND \(cond)"))
        }

        // value-string — idx_string, modifier-aware
        for (i, vs) in query.valueString.enumerated() {
            let cond: String
            switch vs.modifier {
            case .startsWith: cond = "lower(value) LIKE lower(\(bind(vs.value + "%")))"
            case .contains, .text: cond = "value ILIKE \(bind("%" + vs.value + "%"))"
            case .exact: cond = "value = \(bind(vs.value))"
            }
            filterCTEs.append(("f_vstr\(i)", "SELECT DISTINCT resource_id FROM idx_string WHERE resource_type = 'Observation' AND param_name = 'value-string' AND \(cond)"))
        }

        // component-code — token OR
        if !query.componentCode.isEmpty {
            var orClauses: [String] = []
            for tok in query.componentCode {
                if tok.code.isEmpty, let sys = tok.system {
                    orClauses.append("system = \(bind(sys))")
                } else {
                    let codeP = bind(tok.code)
                    var sysCond = ""
                    if let sys = tok.system { sysCond = " AND system = \(bind(sys))" }
                    orClauses.append("(code = \(codeP)\(sysCond))")
                }
            }
            filterCTEs.append(("f_component_code", """
                SELECT DISTINCT resource_id FROM idx_token
                WHERE resource_type = 'Observation' AND param_name = 'component-code'
                  AND (\(orClauses.joined(separator: " OR ")))
                """))
        }

        // value-quantity — idx_quantity with numeric comparison and optional system/code
        if !query.valueQuantity.isEmpty {
            var orClauses: [String] = []
            for qp in query.valueQuantity {
                var cond: String
                switch qp.prefix {
                case .eq: cond = "value = \(bind(qp.value))"
                case .ne: cond = "value != \(bind(qp.value))"
                case .lt: cond = "value < \(bind(qp.value))"
                case .le: cond = "value <= \(bind(qp.value))"
                case .gt: cond = "value > \(bind(qp.value))"
                case .ge: cond = "value >= \(bind(qp.value))"
                case .sa: cond = "value > \(bind(qp.value))"
                case .eb: cond = "value < \(bind(qp.value))"
                case .ap:
                    let low = bind(qp.value * 0.9); let high = bind(qp.value * 1.1)
                    cond = "value BETWEEN \(low) AND \(high)"
                }
                if let sys = qp.system { cond += " AND system = \(bind(sys))" }
                if let code = qp.code  { cond += " AND code = \(bind(code))" }
                orClauses.append("(\(cond))")
            }
            filterCTEs.append(("f_vquantity", """
                SELECT DISTINCT resource_id FROM idx_quantity
                WHERE resource_type = 'Observation' AND param_name = 'value-quantity'
                  AND (\(orClauses.joined(separator: " OR ")))
                """))
        }

        // combo-value-quantity — idx_quantity (obs.value as Quantity; component part not yet indexed)
        if !query.comboValueQuantity.isEmpty {
            var orClauses: [String] = []
            for qp in query.comboValueQuantity {
                var cond: String
                switch qp.prefix {
                case .eq: cond = "value = \(bind(qp.value))"
                case .ne: cond = "value != \(bind(qp.value))"
                case .lt: cond = "value < \(bind(qp.value))"
                case .le: cond = "value <= \(bind(qp.value))"
                case .gt: cond = "value > \(bind(qp.value))"
                case .ge: cond = "value >= \(bind(qp.value))"
                case .sa: cond = "value > \(bind(qp.value))"
                case .eb: cond = "value < \(bind(qp.value))"
                case .ap:
                    let low = bind(qp.value * 0.9); let high = bind(qp.value * 1.1)
                    cond = "value BETWEEN \(low) AND \(high)"
                }
                if let sys = qp.system { cond += " AND system = \(bind(sys))" }
                if let code = qp.code  { cond += " AND code = \(bind(code))" }
                orClauses.append("(\(cond))")
            }
            filterCTEs.append(("f_combo_vquantity", """
                SELECT DISTINCT resource_id FROM idx_quantity
                WHERE resource_type = 'Observation' AND param_name = 'combo-value-quantity'
                  AND (\(orClauses.joined(separator: " OR ")))
                """))
        }

        // component-value-quantity — idx_quantity with numeric comparison and optional system/code
        if !query.componentValueQuantity.isEmpty {
            var orClauses: [String] = []
            for qp in query.componentValueQuantity {
                var cond: String
                switch qp.prefix {
                case .eq: cond = "value = \(bind(qp.value))"
                case .ne: cond = "value != \(bind(qp.value))"
                case .lt: cond = "value < \(bind(qp.value))"
                case .le: cond = "value <= \(bind(qp.value))"
                case .gt: cond = "value > \(bind(qp.value))"
                case .ge: cond = "value >= \(bind(qp.value))"
                case .sa: cond = "value > \(bind(qp.value))"
                case .eb: cond = "value < \(bind(qp.value))"
                case .ap:
                    let low = bind(qp.value * 0.9); let high = bind(qp.value * 1.1)
                    cond = "value BETWEEN \(low) AND \(high)"
                }
                if let sys = qp.system { cond += " AND system = \(bind(sys))" }
                if let code = qp.code  { cond += " AND code = \(bind(code))" }
                orClauses.append("(\(cond))")
            }
            filterCTEs.append(("f_comp_vquantity", """
                SELECT DISTINCT resource_id FROM idx_quantity
                WHERE resource_type = 'Observation' AND param_name = 'component-value-quantity'
                  AND (\(orClauses.joined(separator: " OR ")))
                """))
        }

        // ── Root-level composite params (INTERSECT-per-pair, UNION across OR values) ─

        // Helper: quantity comparison string
        func qCond(_ qp: ObservationSearchQuery.QuantityParam) -> String {
            var c: String
            switch qp.prefix {
            case .eq: c = "value = \(bind(qp.value))"
            case .ne: c = "value != \(bind(qp.value))"
            case .lt: c = "value < \(bind(qp.value))"
            case .le: c = "value <= \(bind(qp.value))"
            case .gt: c = "value > \(bind(qp.value))"
            case .ge: c = "value >= \(bind(qp.value))"
            case .sa: c = "value > \(bind(qp.value))"
            case .eb: c = "value < \(bind(qp.value))"
            case .ap:
                let lo = bind(qp.value * 0.9); let hi = bind(qp.value * 1.1)
                c = "value BETWEEN \(lo) AND \(hi)"
            }
            if let sys = qp.system { c += " AND system = \(bind(sys))" }
            if let code = qp.code  { c += " AND code = \(bind(code))" }
            return c
        }

        func tokenCodeCond(_ tok: ObservationSearchQuery.TokenParam) -> String {
            if tok.code.isEmpty, let sys = tok.system { return "system = \(bind(sys))" }
            let cP = bind(tok.code)
            if let sys = tok.system { return "code = \(cP) AND system = \(bind(sys))" }
            return "code = \(cP)"
        }

        if !query.codeValueQuantity.isEmpty {
            let parts = query.codeValueQuantity.map { pair -> String in
                let codeSQ = "SELECT DISTINCT resource_id FROM idx_token WHERE resource_type = 'Observation' AND param_name = 'code' AND \(tokenCodeCond(pair.codeToken))"
                let valSQ  = "SELECT DISTINCT resource_id FROM idx_quantity WHERE resource_type = 'Observation' AND param_name = 'value-quantity' AND \(qCond(pair.valueQuantity))"
                return "(\(codeSQ) INTERSECT \(valSQ))"
            }
            filterCTEs.append(("f_cvq", parts.joined(separator: "\nUNION\n")))
        }

        if !query.codeValueString.isEmpty {
            let parts = query.codeValueString.map { pair -> String in
                let codeSQ = "SELECT DISTINCT resource_id FROM idx_token WHERE resource_type = 'Observation' AND param_name = 'code' AND \(tokenCodeCond(pair.codeToken))"
                let pLike  = bind("\(pair.valueString)%")
                let valSQ  = "SELECT DISTINCT resource_id FROM idx_string WHERE resource_type = 'Observation' AND param_name = 'value-string' AND lower(value) LIKE lower(\(pLike))"
                return "(\(codeSQ) INTERSECT \(valSQ))"
            }
            filterCTEs.append(("f_cvs", parts.joined(separator: "\nUNION\n")))
        }

        if !query.codeValueConcept.isEmpty {
            let parts = query.codeValueConcept.map { pair -> String in
                let codeSQ    = "SELECT DISTINCT resource_id FROM idx_token WHERE resource_type = 'Observation' AND param_name = 'code' AND \(tokenCodeCond(pair.codeToken))"
                let conceptSQ = "SELECT DISTINCT resource_id FROM idx_token WHERE resource_type = 'Observation' AND param_name = 'value-concept' AND \(tokenCodeCond(pair.valueConcept))"
                return "(\(codeSQ) INTERSECT \(conceptSQ))"
            }
            filterCTEs.append(("f_cvc", parts.joined(separator: "\nUNION\n")))
        }

        if !query.codeValueDate.isEmpty {
            let parts = query.codeValueDate.enumerated().map { (_, pair) -> String in
                let codeSQ = "SELECT DISTINCT resource_id FROM idx_token WHERE resource_type = 'Observation' AND param_name = 'code' AND \(tokenCodeCond(pair.codeToken))"
                let dp = pair.valueDate
                let sP = bind(dp.dateStart); let eP = bind(dp.dateEnd)
                let dateCond: String
                switch dp.prefix {
                case .eq: dateCond = "date_start <= \(eP) AND date_end >= \(sP)"
                case .ne: dateCond = "NOT (date_start <= \(eP) AND date_end >= \(sP))"
                case .lt: dateCond = "date_end < \(sP)"
                case .le: dateCond = "date_start <= \(eP)"
                case .gt: dateCond = "date_start > \(eP)"
                case .ge: dateCond = "date_end >= \(sP)"
                case .sa: dateCond = "date_start > \(eP)"
                case .eb: dateCond = "date_end < \(sP)"
                case .ap: dateCond = "date_start <= \(bind(dp.apExpandedEnd)) AND date_end >= \(bind(dp.apExpandedStart))"
                }
                let valSQ = "SELECT DISTINCT resource_id FROM idx_date WHERE resource_type = 'Observation' AND param_name = 'value-date' AND \(dateCond)"
                return "(\(codeSQ) INTERSECT \(valSQ))"
            }
            filterCTEs.append(("f_cvd", parts.joined(separator: "\nUNION\n")))
        }

        // ── idx_composite-backed params (tuple match per component/combo) ────────

        func compositeQCond(_ pair: ObservationSearchQuery.CompositeCodeQuantity) -> String {
            var parts: [String] = []
            parts.append("code1_code = \(bind(pair.codeToken.code))")
            if let sys = pair.codeToken.system { parts.append("code1_system = \(bind(sys))") }
            let qp = pair.valueQuantity
            let valCond: String
            switch qp.prefix {
            case .eq: valCond = "value2 = \(bind(qp.value))"
            case .ne: valCond = "value2 != \(bind(qp.value))"
            case .lt: valCond = "value2 < \(bind(qp.value))"
            case .le: valCond = "value2 <= \(bind(qp.value))"
            case .gt: valCond = "value2 > \(bind(qp.value))"
            case .ge: valCond = "value2 >= \(bind(qp.value))"
            case .sa: valCond = "value2 > \(bind(qp.value))"
            case .eb: valCond = "value2 < \(bind(qp.value))"
            case .ap:
                let lo = bind(qp.value * 0.9); let hi = bind(qp.value * 1.1)
                valCond = "value2 BETWEEN \(lo) AND \(hi)"
            }
            parts.append(valCond)
            if let sys = qp.system  { parts.append("code2_system = \(bind(sys))") }
            if let code = qp.code   { parts.append("code2_code = \(bind(code))") }
            return "(" + parts.joined(separator: " AND ") + ")"
        }

        func compositeConceptCond(_ pair: ObservationSearchQuery.CompositeCodeConcept) -> String {
            var parts: [String] = []
            parts.append("code1_code = \(bind(pair.codeToken.code))")
            if let sys = pair.codeToken.system { parts.append("code1_system = \(bind(sys))") }
            parts.append("code2_code = \(bind(pair.valueConcept.code))")
            if let sys = pair.valueConcept.system { parts.append("code2_system = \(bind(sys))") }
            return "(" + parts.joined(separator: " AND ") + ")"
        }

        if !query.componentCodeValueQuantity.isEmpty {
            let orConds = query.componentCodeValueQuantity.map { compositeQCond($0) }.joined(separator: " OR ")
            filterCTEs.append(("f_comp_cvq", """
                SELECT DISTINCT resource_id FROM idx_composite
                WHERE resource_type = 'Observation' AND param_name = 'component-code-value-quantity'
                  AND (\(orConds))
                """))
        }

        if !query.componentCodeValueConcept.isEmpty {
            let orConds = query.componentCodeValueConcept.map { compositeConceptCond($0) }.joined(separator: " OR ")
            filterCTEs.append(("f_comp_cvc", """
                SELECT DISTINCT resource_id FROM idx_composite
                WHERE resource_type = 'Observation' AND param_name = 'component-code-value-concept'
                  AND (\(orConds))
                """))
        }

        if !query.comboCodeValueQuantity.isEmpty {
            let orConds = query.comboCodeValueQuantity.map { compositeQCond($0) }.joined(separator: " OR ")
            filterCTEs.append(("f_combo_cvq", """
                SELECT DISTINCT resource_id FROM idx_composite
                WHERE resource_type = 'Observation' AND param_name = 'combo-code-value-quantity'
                  AND (\(orConds))
                """))
        }

        if !query.comboCodeValueConcept.isEmpty {
            let orConds = query.comboCodeValueConcept.map { compositeConceptCond($0) }.joined(separator: " OR ")
            filterCTEs.append(("f_combo_cvc", """
                SELECT DISTINCT resource_id FROM idx_composite
                WHERE resource_type = 'Observation' AND param_name = 'combo-code-value-concept'
                  AND (\(orConds))
                """))
        }

        // date — idx_date range with two-bound comparison per FHIR R4 §2.4.0.1
        for (i, dp) in query.date.enumerated() {
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
            filterCTEs.append(("f_date\(i)", """
                SELECT DISTINCT resource_id FROM idx_date
                WHERE resource_type = 'Observation' AND param_name = 'date' AND \(cond)
                """))
        }

        // ── `ids` CTE — _id, _lastUpdated, and :not conditions ─────────────────

        var whereConditions = ["r.resource_type = 'Observation'", "r.deleted = false"]

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
                whereConditions.append("r.id NOT IN (SELECT resource_id FROM idx_token WHERE resource_type = 'Observation' AND param_name = 'identifier' AND (\(orClauses.joined(separator: " OR "))))")
            }
        }

        // status:not — exclude resources where status matches any value
        if !query.statusNot.isEmpty {
            let phs = query.statusNot.map { bind($0) }.joined(separator: ", ")
            whereConditions.append("r.id NOT IN (SELECT resource_id FROM idx_token WHERE resource_type = 'Observation' AND param_name = 'status' AND code IN (\(phs)))")
        }

        // code:not
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
            whereConditions.append("r.id NOT IN (SELECT resource_id FROM idx_token WHERE resource_type = 'Observation' AND param_name = 'code' AND (\(orClauses.joined(separator: " OR "))))")
        }

        // category:not
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
            whereConditions.append("r.id NOT IN (SELECT resource_id FROM idx_token WHERE resource_type = 'Observation' AND param_name = 'category' AND (\(orClauses.joined(separator: " OR "))))")
        }

        // combo-code:not / method:not / value-concept:not
        func obsTokenNotCond(paramName: String, tokens: [ObservationSearchQuery.TokenParam]) -> String {
            var or: [String] = []
            for tok in tokens {
                if tok.code.isEmpty, let sys = tok.system { or.append("system = \(bind(sys))") }
                else {
                    let cP = bind(tok.code); var sc = ""
                    if let sys = tok.system { sc = " AND system = \(bind(sys))" }
                    or.append("(code = \(cP)\(sc))")
                }
            }
            return "r.id NOT IN (SELECT resource_id FROM idx_token WHERE resource_type = 'Observation' AND param_name = '\(paramName)' AND (\(or.joined(separator: " OR "))))"
        }
        if !query.comboCodeNot.isEmpty         { whereConditions.append(obsTokenNotCond(paramName: "combo-code",         tokens: query.comboCodeNot)) }
        if !query.methodNot.isEmpty            { whereConditions.append(obsTokenNotCond(paramName: "method",             tokens: query.methodNot)) }
        if !query.valueConceptNot.isEmpty      { whereConditions.append(obsTokenNotCond(paramName: "value-concept",      tokens: query.valueConceptNot)) }
        if !query.comboValueConceptNot.isEmpty { whereConditions.append(obsTokenNotCond(paramName: "combo-value-concept", tokens: query.comboValueConceptNot)) }

        // :missing modifier
        for paramName in query.missing.keys.sorted() {
            if let sub = observationMissingSubquery(param: paramName) {
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
                index: filterCTEs.count + i, sourceType: "Observation",
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
                index: i, mainType: "Observation",
                param: hp, bindStr: hBindStr, bindDate: hBindDate
            ) {
                filterCTEs.append((name, sql))
            }
        }

        // meta params: _tag, _security, _profile
        let strBind: (String) -> String = { bind($0) }
        let (metaCTEs, metaWhere) = metaFilterCTEs(resourceType: "Observation", meta: query.meta, bind: strBind)
        filterCTEs += metaCTEs
        whereConditions += metaWhere

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

        var sortKeysCTE: (name: String, sql: String)? = nil
        var cursorCondSQL = ""
        var finalSortValSQL = ""
        var sortKind = 0  // 0=lastUpdated, 1=date, 2=_id

        switch query.sort {
        case .dateAscending, .dateDescending:
            sortKeysCTE = ("sort_keys",
                "SELECT DISTINCT ON (resource_id) resource_id, date_start AS sv " +
                "FROM idx_date WHERE resource_type = 'Observation' AND param_name = 'date' " +
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
                "FROM idx_token WHERE resource_type = 'Observation' AND param_name = 'code' " +
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
                "FROM idx_token WHERE resource_type = 'Observation' AND param_name = 'status' " +
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

        default:  // lastUpdated (and any unsupported sort → fallback)
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
        case 1:  // date sort — sort_val via LEFT JOIN idx_date
            let inner = "SELECT i.id, i.version_id, i.last_updated, sk.sv AS sort_val " +
                "FROM ids i LEFT JOIN sort_keys sk ON sk.resource_id = i.id"
            let whereLine = cursorCondSQL.isEmpty ? "" : "\n    WHERE \(cursorCondSQL)"
            pagedInner = "SELECT id, version_id, last_updated, sort_val FROM (\n      \(inner)\n    ) sub" +
                "\(whereLine)\n    ORDER BY sort_val \(orderDir) NULLS LAST, id ASC\n    LIMIT \(limitP)"
        case 2:  // _id sort
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

        let totalExpr = skipTotal ? "CAST(0 AS bigint)" : "t.n"
        let fromClause = skipTotal
            ? "FROM paged p JOIN resources r ON r.resource_type = 'Observation' AND r.id = p.id AND r.version_id = p.version_id"
            : "FROM paged p CROSS JOIN total_count t JOIN resources r ON r.resource_type = 'Observation' AND r.id = p.id AND r.version_id = p.version_id"

        let sql = "\(withClause)\nSELECT p.id, p.version_id, p.last_updated, r.content, \(totalExpr), \(finalSortValSQL) AS sort_val_text\n\(fromClause)\nORDER BY sort_val_text \(orderDir) NULLS LAST, p.id ASC"
        return (sql, binds)
    }

    private func buildCountSQL(query: ObservationSearchQuery) throws -> (String, PostgresBindings) {
        var binds = PostgresBindings()
        var n = 0
        func bind(_ val: some PostgresDynamicTypeEncodable) -> String {
            n += 1; binds.append(val); return "$\(n)"
        }

        var filterCTEs: [(name: String, sql: String)] = []

        if let subject = query.subject {
            let parts = subject.split(separator: "/")
            if parts.count == 2 {
                let refTypeP = bind(String(parts[0]))
                let refIdP   = bind(String(parts[1]))
                filterCTEs.append(("f_subject",
                    "SELECT DISTINCT resource_id FROM idx_reference WHERE resource_type = 'Observation' AND param_name = 'subject' AND ref_type = \(refTypeP) AND ref_id = \(refIdP)"))
            } else {
                let refIdP = bind(subject)
                filterCTEs.append(("f_subject",
                    "SELECT DISTINCT resource_id FROM idx_reference WHERE resource_type = 'Observation' AND param_name = 'subject' AND ref_id = \(refIdP)"))
            }
        }
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
            filterCTEs.append(("f_code",
                "SELECT DISTINCT resource_id FROM idx_token WHERE resource_type = 'Observation' AND param_name = 'code' AND (\(orClauses.joined(separator: " OR ")))"))
        }
        if !query.status.isEmpty {
            let phs = query.status.map { bind($0) }.joined(separator: ", ")
            filterCTEs.append(("f_status",
                "SELECT DISTINCT resource_id FROM idx_token WHERE resource_type = 'Observation' AND param_name = 'status' AND code IN (\(phs))"))
        }
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
            filterCTEs.append(("f_category",
                "SELECT DISTINCT resource_id FROM idx_token WHERE resource_type = 'Observation' AND param_name = 'category' AND (\(orClauses.joined(separator: " OR ")))"))
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
                    "SELECT DISTINCT resource_id FROM idx_token WHERE resource_type = 'Observation' AND param_name = 'identifier' AND (\(orClauses.joined(separator: " OR ")))"))
            }
        }
        if let encounter = query.encounter {
            let parts = encounter.split(separator: "/")
            if parts.count == 2 {
                let refTypeP = bind(String(parts[0])); let refIdP = bind(String(parts[1]))
                filterCTEs.append(("f_encounter",
                    "SELECT DISTINCT resource_id FROM idx_reference WHERE resource_type = 'Observation' AND param_name = 'encounter' AND ref_type = \(refTypeP) AND ref_id = \(refIdP)"))
            } else {
                let refIdP = bind(encounter)
                filterCTEs.append(("f_encounter",
                    "SELECT DISTINCT resource_id FROM idx_reference WHERE resource_type = 'Observation' AND param_name = 'encounter' AND ref_id = \(refIdP)"))
            }
        }
        if let performer = query.performer {
            let parts = performer.split(separator: "/")
            if parts.count == 2 {
                let refTypeP = bind(String(parts[0])); let refIdP = bind(String(parts[1]))
                filterCTEs.append(("f_performer",
                    "SELECT DISTINCT resource_id FROM idx_reference WHERE resource_type = 'Observation' AND param_name = 'performer' AND ref_type = \(refTypeP) AND ref_id = \(refIdP)"))
            } else {
                let refIdP = bind(performer)
                filterCTEs.append(("f_performer",
                    "SELECT DISTINCT resource_id FROM idx_reference WHERE resource_type = 'Observation' AND param_name = 'performer' AND ref_id = \(refIdP)"))
            }
        }
        func countObsRefCTE(name: String, paramName: String, ref: String) -> (String, String) {
            let parts = ref.split(separator: "/")
            if parts.count == 2 {
                let rtP = bind(String(parts[0])); let riP = bind(String(parts[1]))
                return (name, "SELECT DISTINCT resource_id FROM idx_reference WHERE resource_type = 'Observation' AND param_name = '\(paramName)' AND ref_type = \(rtP) AND ref_id = \(riP)")
            } else {
                let riP = bind(ref)
                return (name, "SELECT DISTINCT resource_id FROM idx_reference WHERE resource_type = 'Observation' AND param_name = '\(paramName)' AND ref_id = \(riP)")
            }
        }
        if let r = query.basedOn    { filterCTEs.append(countObsRefCTE(name: "f_based_on",    paramName: "based-on",    ref: r)) }
        if let r = query.derivedFrom { filterCTEs.append(countObsRefCTE(name: "f_derived_from", paramName: "derived-from", ref: r)) }
        if let r = query.device     { filterCTEs.append(countObsRefCTE(name: "f_device",      paramName: "device",      ref: r)) }
        if let r = query.focus      { filterCTEs.append(countObsRefCTE(name: "f_focus",       paramName: "focus",       ref: r)) }
        if let r = query.hasMember  { filterCTEs.append(countObsRefCTE(name: "f_has_member",  paramName: "has-member",  ref: r)) }
        if let r = query.partOf     { filterCTEs.append(countObsRefCTE(name: "f_part_of",     paramName: "part-of",     ref: r)) }
        if let r = query.specimen   { filterCTEs.append(countObsRefCTE(name: "f_specimen",    paramName: "specimen",    ref: r)) }
        func countObsTokenORCTE(name: String, paramName: String, tokens: [ObservationSearchQuery.TokenParam]) -> (String, String) {
            var or: [String] = []
            for tok in tokens {
                if tok.code.isEmpty, let sys = tok.system { or.append("system = \(bind(sys))") }
                else { let cP = bind(tok.code); var sc = ""; if let sys = tok.system { sc = " AND system = \(bind(sys))" }; or.append("(code = \(cP)\(sc))") }
            }
            return (name, "SELECT DISTINCT resource_id FROM idx_token WHERE resource_type = 'Observation' AND param_name = '\(paramName)' AND (\(or.joined(separator: " OR ")))")
        }
        if !query.comboCode.isEmpty               { filterCTEs.append(countObsTokenORCTE(name: "f_combo_code",          paramName: "combo-code",                tokens: query.comboCode)) }
        if !query.method.isEmpty                  { filterCTEs.append(countObsTokenORCTE(name: "f_method",               paramName: "method",                     tokens: query.method)) }
        if !query.valueConcept.isEmpty            { filterCTEs.append(countObsTokenORCTE(name: "f_value_concept",         paramName: "value-concept",              tokens: query.valueConcept)) }
        if !query.comboValueConcept.isEmpty       { filterCTEs.append(countObsTokenORCTE(name: "f_combo_value_concept",   paramName: "combo-value-concept",        tokens: query.comboValueConcept)) }
        if !query.dataAbsentReason.isEmpty        { filterCTEs.append(countObsTokenORCTE(name: "f_data_absent",           paramName: "data-absent-reason",         tokens: query.dataAbsentReason)) }
        if !query.comboDataAbsentReason.isEmpty   { filterCTEs.append(countObsTokenORCTE(name: "f_combo_data_absent",     paramName: "combo-data-absent-reason",   tokens: query.comboDataAbsentReason)) }
        if !query.componentDataAbsentReason.isEmpty { filterCTEs.append(countObsTokenORCTE(name: "f_comp_data_absent",   paramName: "component-data-absent-reason", tokens: query.componentDataAbsentReason)) }
        if !query.componentValueConcept.isEmpty   { filterCTEs.append(countObsTokenORCTE(name: "f_comp_val_concept",     paramName: "component-value-concept",    tokens: query.componentValueConcept)) }
        for (i, dp) in query.valueDate.enumerated() {
            let sP = bind(dp.dateStart); let eP = bind(dp.dateEnd)
            let cond: String
            switch dp.prefix {
            case .eq: cond = "date_start <= \(eP) AND date_end >= \(sP)"
            case .ne: cond = "NOT (date_start <= \(eP) AND date_end >= \(sP))"
            case .lt: cond = "date_end < \(sP)"
            case .le: cond = "date_start <= \(eP)"
            case .gt: cond = "date_start > \(eP)"
            case .ge: cond = "date_end >= \(sP)"
            case .sa: cond = "date_start > \(eP)"
            case .eb: cond = "date_end < \(sP)"
            case .ap: cond = "date_start <= \(bind(dp.apExpandedEnd)) AND date_end >= \(bind(dp.apExpandedStart))"
            }
            filterCTEs.append(("f_vdate\(i)", "SELECT DISTINCT resource_id FROM idx_date WHERE resource_type = 'Observation' AND param_name = 'value-date' AND \(cond)"))
        }
        for (i, vs) in query.valueString.enumerated() {
            let cond: String
            switch vs.modifier {
            case .startsWith: cond = "lower(value) LIKE lower(\(bind(vs.value + "%")))"
            case .contains, .text: cond = "value ILIKE \(bind("%" + vs.value + "%"))"
            case .exact: cond = "value = \(bind(vs.value))"
            }
            filterCTEs.append(("f_vstr\(i)", "SELECT DISTINCT resource_id FROM idx_string WHERE resource_type = 'Observation' AND param_name = 'value-string' AND \(cond)"))
        }
        if !query.componentCode.isEmpty {
            var orClauses: [String] = []
            for tok in query.componentCode {
                if tok.code.isEmpty, let sys = tok.system {
                    orClauses.append("system = \(bind(sys))")
                } else {
                    let codeP = bind(tok.code)
                    var sysCond = ""
                    if let sys = tok.system { sysCond = " AND system = \(bind(sys))" }
                    orClauses.append("(code = \(codeP)\(sysCond))")
                }
            }
            filterCTEs.append(("f_component_code",
                "SELECT DISTINCT resource_id FROM idx_token WHERE resource_type = 'Observation' AND param_name = 'component-code' AND (\(orClauses.joined(separator: " OR ")))"))
        }
        if !query.valueQuantity.isEmpty {
            var orClauses: [String] = []
            for qp in query.valueQuantity {
                var cond: String
                switch qp.prefix {
                case .eq: cond = "value = \(bind(qp.value))"
                case .ne: cond = "value != \(bind(qp.value))"
                case .lt: cond = "value < \(bind(qp.value))"
                case .le: cond = "value <= \(bind(qp.value))"
                case .gt: cond = "value > \(bind(qp.value))"
                case .ge: cond = "value >= \(bind(qp.value))"
                case .sa: cond = "value > \(bind(qp.value))"
                case .eb: cond = "value < \(bind(qp.value))"
                case .ap:
                    let low = bind(qp.value * 0.9); let high = bind(qp.value * 1.1)
                    cond = "value BETWEEN \(low) AND \(high)"
                }
                if let sys = qp.system { cond += " AND system = \(bind(sys))" }
                if let code = qp.code  { cond += " AND code = \(bind(code))" }
                orClauses.append("(\(cond))")
            }
            filterCTEs.append(("f_vquantity",
                "SELECT DISTINCT resource_id FROM idx_quantity WHERE resource_type = 'Observation' AND param_name = 'value-quantity' AND (\(orClauses.joined(separator: " OR ")))"))
        }
        if !query.comboValueQuantity.isEmpty {
            var orClauses: [String] = []
            for qp in query.comboValueQuantity {
                var cond: String
                switch qp.prefix {
                case .eq: cond = "value = \(bind(qp.value))"
                case .ne: cond = "value != \(bind(qp.value))"
                case .lt: cond = "value < \(bind(qp.value))"
                case .le: cond = "value <= \(bind(qp.value))"
                case .gt: cond = "value > \(bind(qp.value))"
                case .ge: cond = "value >= \(bind(qp.value))"
                case .sa: cond = "value > \(bind(qp.value))"
                case .eb: cond = "value < \(bind(qp.value))"
                case .ap:
                    let low = bind(qp.value * 0.9); let high = bind(qp.value * 1.1)
                    cond = "value BETWEEN \(low) AND \(high)"
                }
                if let sys = qp.system { cond += " AND system = \(bind(sys))" }
                if let code = qp.code  { cond += " AND code = \(bind(code))" }
                orClauses.append("(\(cond))")
            }
            filterCTEs.append(("f_combo_vquantity",
                "SELECT DISTINCT resource_id FROM idx_quantity WHERE resource_type = 'Observation' AND param_name = 'combo-value-quantity' AND (\(orClauses.joined(separator: " OR ")))"))
        }
        if !query.componentValueQuantity.isEmpty {
            var orClauses: [String] = []
            for qp in query.componentValueQuantity {
                var cond: String
                switch qp.prefix {
                case .eq: cond = "value = \(bind(qp.value))"
                case .ne: cond = "value != \(bind(qp.value))"
                case .lt: cond = "value < \(bind(qp.value))"
                case .le: cond = "value <= \(bind(qp.value))"
                case .gt: cond = "value > \(bind(qp.value))"
                case .ge: cond = "value >= \(bind(qp.value))"
                case .sa: cond = "value > \(bind(qp.value))"
                case .eb: cond = "value < \(bind(qp.value))"
                case .ap:
                    let low = bind(qp.value * 0.9); let high = bind(qp.value * 1.1)
                    cond = "value BETWEEN \(low) AND \(high)"
                }
                if let sys = qp.system { cond += " AND system = \(bind(sys))" }
                if let code = qp.code  { cond += " AND code = \(bind(code))" }
                orClauses.append("(\(cond))")
            }
            filterCTEs.append(("f_comp_vquantity",
                "SELECT DISTINCT resource_id FROM idx_quantity WHERE resource_type = 'Observation' AND param_name = 'component-value-quantity' AND (\(orClauses.joined(separator: " OR ")))"))
        }
        // root-level composite params in buildCountSQL
        func countTokenCodeCond(_ tok: ObservationSearchQuery.TokenParam) -> String {
            if tok.code.isEmpty, let sys = tok.system { return "system = \(bind(sys))" }
            let cP = bind(tok.code)
            if let sys = tok.system { return "code = \(cP) AND system = \(bind(sys))" }
            return "code = \(cP)"
        }
        func countQCond(_ qp: ObservationSearchQuery.QuantityParam) -> String {
            var c: String
            switch qp.prefix {
            case .eq: c = "value = \(bind(qp.value))"
            case .ne: c = "value != \(bind(qp.value))"
            case .lt: c = "value < \(bind(qp.value))"
            case .le: c = "value <= \(bind(qp.value))"
            case .gt: c = "value > \(bind(qp.value))"
            case .ge: c = "value >= \(bind(qp.value))"
            case .sa: c = "value > \(bind(qp.value))"
            case .eb: c = "value < \(bind(qp.value))"
            case .ap:
                let lo = bind(qp.value * 0.9); let hi = bind(qp.value * 1.1)
                c = "value BETWEEN \(lo) AND \(hi)"
            }
            if let sys = qp.system { c += " AND system = \(bind(sys))" }
            if let code = qp.code  { c += " AND code = \(bind(code))" }
            return c
        }
        if !query.codeValueQuantity.isEmpty {
            let parts = query.codeValueQuantity.map { pair -> String in
                let codeSQ = "SELECT DISTINCT resource_id FROM idx_token WHERE resource_type = 'Observation' AND param_name = 'code' AND \(countTokenCodeCond(pair.codeToken))"
                let valSQ  = "SELECT DISTINCT resource_id FROM idx_quantity WHERE resource_type = 'Observation' AND param_name = 'value-quantity' AND \(countQCond(pair.valueQuantity))"
                return "(\(codeSQ) INTERSECT \(valSQ))"
            }
            filterCTEs.append(("f_cvq", parts.joined(separator: "\nUNION\n")))
        }
        if !query.codeValueString.isEmpty {
            let parts = query.codeValueString.map { pair -> String in
                let codeSQ = "SELECT DISTINCT resource_id FROM idx_token WHERE resource_type = 'Observation' AND param_name = 'code' AND \(countTokenCodeCond(pair.codeToken))"
                let pLike  = bind("\(pair.valueString)%")
                let valSQ  = "SELECT DISTINCT resource_id FROM idx_string WHERE resource_type = 'Observation' AND param_name = 'value-string' AND lower(value) LIKE lower(\(pLike))"
                return "(\(codeSQ) INTERSECT \(valSQ))"
            }
            filterCTEs.append(("f_cvs", parts.joined(separator: "\nUNION\n")))
        }
        if !query.codeValueConcept.isEmpty {
            let parts = query.codeValueConcept.map { pair -> String in
                let codeSQ    = "SELECT DISTINCT resource_id FROM idx_token WHERE resource_type = 'Observation' AND param_name = 'code' AND \(countTokenCodeCond(pair.codeToken))"
                let conceptSQ = "SELECT DISTINCT resource_id FROM idx_token WHERE resource_type = 'Observation' AND param_name = 'value-concept' AND \(countTokenCodeCond(pair.valueConcept))"
                return "(\(codeSQ) INTERSECT \(conceptSQ))"
            }
            filterCTEs.append(("f_cvc", parts.joined(separator: "\nUNION\n")))
        }
        if !query.codeValueDate.isEmpty {
            let parts = query.codeValueDate.map { pair -> String in
                let codeSQ = "SELECT DISTINCT resource_id FROM idx_token WHERE resource_type = 'Observation' AND param_name = 'code' AND \(countTokenCodeCond(pair.codeToken))"
                let dp = pair.valueDate
                let sP = bind(dp.dateStart); let eP = bind(dp.dateEnd)
                let dateCond: String
                switch dp.prefix {
                case .eq: dateCond = "date_start <= \(eP) AND date_end >= \(sP)"
                case .ne: dateCond = "NOT (date_start <= \(eP) AND date_end >= \(sP))"
                case .lt: dateCond = "date_end < \(sP)"
                case .le: dateCond = "date_start <= \(eP)"
                case .gt: dateCond = "date_start > \(eP)"
                case .ge: dateCond = "date_end >= \(sP)"
                case .sa: dateCond = "date_start > \(eP)"
                case .eb: dateCond = "date_end < \(sP)"
                case .ap: dateCond = "date_start <= \(bind(dp.apExpandedEnd)) AND date_end >= \(bind(dp.apExpandedStart))"
                }
                let valSQ = "SELECT DISTINCT resource_id FROM idx_date WHERE resource_type = 'Observation' AND param_name = 'value-date' AND \(dateCond)"
                return "(\(codeSQ) INTERSECT \(valSQ))"
            }
            filterCTEs.append(("f_cvd", parts.joined(separator: "\nUNION\n")))
        }

        // idx_composite-backed params (count path)
        func countCompositeQCond(_ pair: ObservationSearchQuery.CompositeCodeQuantity) -> String {
            var parts: [String] = []
            parts.append("code1_code = \(bind(pair.codeToken.code))")
            if let sys = pair.codeToken.system { parts.append("code1_system = \(bind(sys))") }
            let qp = pair.valueQuantity
            let valCond: String
            switch qp.prefix {
            case .eq: valCond = "value2 = \(bind(qp.value))"
            case .ne: valCond = "value2 != \(bind(qp.value))"
            case .lt: valCond = "value2 < \(bind(qp.value))"
            case .le: valCond = "value2 <= \(bind(qp.value))"
            case .gt: valCond = "value2 > \(bind(qp.value))"
            case .ge: valCond = "value2 >= \(bind(qp.value))"
            case .sa: valCond = "value2 > \(bind(qp.value))"
            case .eb: valCond = "value2 < \(bind(qp.value))"
            case .ap:
                let lo = bind(qp.value * 0.9); let hi = bind(qp.value * 1.1)
                valCond = "value2 BETWEEN \(lo) AND \(hi)"
            }
            parts.append(valCond)
            if let sys = qp.system  { parts.append("code2_system = \(bind(sys))") }
            if let code = qp.code   { parts.append("code2_code = \(bind(code))") }
            return "(" + parts.joined(separator: " AND ") + ")"
        }
        func countCompositeConceptCond(_ pair: ObservationSearchQuery.CompositeCodeConcept) -> String {
            var parts: [String] = []
            parts.append("code1_code = \(bind(pair.codeToken.code))")
            if let sys = pair.codeToken.system { parts.append("code1_system = \(bind(sys))") }
            parts.append("code2_code = \(bind(pair.valueConcept.code))")
            if let sys = pair.valueConcept.system { parts.append("code2_system = \(bind(sys))") }
            return "(" + parts.joined(separator: " AND ") + ")"
        }
        if !query.componentCodeValueQuantity.isEmpty {
            let orConds = query.componentCodeValueQuantity.map { countCompositeQCond($0) }.joined(separator: " OR ")
            filterCTEs.append(("f_comp_cvq", "SELECT DISTINCT resource_id FROM idx_composite WHERE resource_type = 'Observation' AND param_name = 'component-code-value-quantity' AND (\(orConds))"))
        }
        if !query.componentCodeValueConcept.isEmpty {
            let orConds = query.componentCodeValueConcept.map { countCompositeConceptCond($0) }.joined(separator: " OR ")
            filterCTEs.append(("f_comp_cvc", "SELECT DISTINCT resource_id FROM idx_composite WHERE resource_type = 'Observation' AND param_name = 'component-code-value-concept' AND (\(orConds))"))
        }
        if !query.comboCodeValueQuantity.isEmpty {
            let orConds = query.comboCodeValueQuantity.map { countCompositeQCond($0) }.joined(separator: " OR ")
            filterCTEs.append(("f_combo_cvq", "SELECT DISTINCT resource_id FROM idx_composite WHERE resource_type = 'Observation' AND param_name = 'combo-code-value-quantity' AND (\(orConds))"))
        }
        if !query.comboCodeValueConcept.isEmpty {
            let orConds = query.comboCodeValueConcept.map { countCompositeConceptCond($0) }.joined(separator: " OR ")
            filterCTEs.append(("f_combo_cvc", "SELECT DISTINCT resource_id FROM idx_composite WHERE resource_type = 'Observation' AND param_name = 'combo-code-value-concept' AND (\(orConds))"))
        }

        for (i, dp) in query.date.enumerated() {
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
            filterCTEs.append(("f_date\(i)",
                "SELECT DISTINCT resource_id FROM idx_date WHERE resource_type = 'Observation' AND param_name = 'date' AND \(cond)"))
        }

        var whereConditions = ["r.resource_type = 'Observation'", "r.deleted = false"]
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
                whereConditions.append("r.id NOT IN (SELECT resource_id FROM idx_token WHERE resource_type = 'Observation' AND param_name = 'identifier' AND (\(orClauses.joined(separator: " OR "))))")
            }
        }
        if !query.statusNot.isEmpty {
            let phs = query.statusNot.map { bind($0) }.joined(separator: ", ")
            whereConditions.append("r.id NOT IN (SELECT resource_id FROM idx_token WHERE resource_type = 'Observation' AND param_name = 'status' AND code IN (\(phs)))")
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
            whereConditions.append("r.id NOT IN (SELECT resource_id FROM idx_token WHERE resource_type = 'Observation' AND param_name = 'code' AND (\(orClauses.joined(separator: " OR "))))")
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
            whereConditions.append("r.id NOT IN (SELECT resource_id FROM idx_token WHERE resource_type = 'Observation' AND param_name = 'category' AND (\(orClauses.joined(separator: " OR "))))")
        }
        for paramName in query.missing.keys.sorted() {
            if let sub = observationMissingSubquery(param: paramName) {
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
                index: filterCTEs.count + i, sourceType: "Observation",
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
                index: i, mainType: "Observation",
                param: hp, bindStr: hBindStr, bindDate: hBindDate
            ) {
                filterCTEs.append((name, sql))
            }
        }

        // meta params: _tag, _security, _profile
        let strBind: (String) -> String = { bind($0) }
        let (metaCTEs, metaWhere) = metaFilterCTEs(resourceType: "Observation", meta: query.meta, bind: strBind)
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

    private func observationMissingSubquery(param: String) -> String? {
        switch param {
        case "subject", "patient": return "SELECT DISTINCT resource_id FROM idx_reference WHERE resource_type = 'Observation' AND param_name = 'subject'"
        case "code":               return "SELECT DISTINCT resource_id FROM idx_token WHERE resource_type = 'Observation' AND param_name = 'code'"
        case "status":             return "SELECT DISTINCT resource_id FROM idx_token WHERE resource_type = 'Observation' AND param_name = 'status'"
        case "category":           return "SELECT DISTINCT resource_id FROM idx_token WHERE resource_type = 'Observation' AND param_name = 'category'"
        case "identifier":         return "SELECT DISTINCT resource_id FROM idx_token WHERE resource_type = 'Observation' AND param_name = 'identifier'"
        case "encounter":          return "SELECT DISTINCT resource_id FROM idx_reference WHERE resource_type = 'Observation' AND param_name = 'encounter'"
        case "performer":          return "SELECT DISTINCT resource_id FROM idx_reference WHERE resource_type = 'Observation' AND param_name = 'performer'"
        case "component-code":     return "SELECT DISTINCT resource_id FROM idx_token WHERE resource_type = 'Observation' AND param_name = 'component-code'"
        case "date":               return "SELECT DISTINCT resource_id FROM idx_date WHERE resource_type = 'Observation' AND param_name = 'date'"
        case "value-quantity":     return "SELECT DISTINCT resource_id FROM idx_quantity WHERE resource_type = 'Observation' AND param_name = 'value-quantity'"
        case "based-on":           return "SELECT DISTINCT resource_id FROM idx_reference WHERE resource_type = 'Observation' AND param_name = 'based-on'"
        case "derived-from":       return "SELECT DISTINCT resource_id FROM idx_reference WHERE resource_type = 'Observation' AND param_name = 'derived-from'"
        case "device":             return "SELECT DISTINCT resource_id FROM idx_reference WHERE resource_type = 'Observation' AND param_name = 'device'"
        case "focus":              return "SELECT DISTINCT resource_id FROM idx_reference WHERE resource_type = 'Observation' AND param_name = 'focus'"
        case "has-member":         return "SELECT DISTINCT resource_id FROM idx_reference WHERE resource_type = 'Observation' AND param_name = 'has-member'"
        case "part-of":            return "SELECT DISTINCT resource_id FROM idx_reference WHERE resource_type = 'Observation' AND param_name = 'part-of'"
        case "specimen":           return "SELECT DISTINCT resource_id FROM idx_reference WHERE resource_type = 'Observation' AND param_name = 'specimen'"
        case "combo-code":         return "SELECT DISTINCT resource_id FROM idx_token WHERE resource_type = 'Observation' AND param_name = 'combo-code'"
        case "method":             return "SELECT DISTINCT resource_id FROM idx_token WHERE resource_type = 'Observation' AND param_name = 'method'"
        case "value-concept":      return "SELECT DISTINCT resource_id FROM idx_token WHERE resource_type = 'Observation' AND param_name = 'value-concept'"
        case "value-date":         return "SELECT DISTINCT resource_id FROM idx_date WHERE resource_type = 'Observation' AND param_name = 'value-date'"
        case "value-string":       return "SELECT DISTINCT resource_id FROM idx_string WHERE resource_type = 'Observation' AND param_name = 'value-string'"
        case "data-absent-reason":          return "SELECT DISTINCT resource_id FROM idx_token WHERE resource_type = 'Observation' AND param_name = 'data-absent-reason'"
        case "combo-data-absent-reason":    return "SELECT DISTINCT resource_id FROM idx_token WHERE resource_type = 'Observation' AND param_name = 'combo-data-absent-reason'"
        case "component-data-absent-reason": return "SELECT DISTINCT resource_id FROM idx_token WHERE resource_type = 'Observation' AND param_name = 'component-data-absent-reason'"
        case "component-value-concept":     return "SELECT DISTINCT resource_id FROM idx_token WHERE resource_type = 'Observation' AND param_name = 'component-value-concept'"
        case "component-value-quantity":    return "SELECT DISTINCT resource_id FROM idx_quantity WHERE resource_type = 'Observation' AND param_name = 'component-value-quantity'"
        case "combo-value-quantity":        return "SELECT DISTINCT resource_id FROM idx_quantity WHERE resource_type = 'Observation' AND param_name = 'combo-value-quantity'"
        case "combo-value-concept":         return "SELECT DISTINCT resource_id FROM idx_token WHERE resource_type = 'Observation' AND param_name = 'combo-value-concept'"
        case "component-code-value-quantity": return "SELECT DISTINCT resource_id FROM idx_composite WHERE resource_type = 'Observation' AND param_name = 'component-code-value-quantity'"
        case "component-code-value-concept":  return "SELECT DISTINCT resource_id FROM idx_composite WHERE resource_type = 'Observation' AND param_name = 'component-code-value-concept'"
        case "combo-code-value-quantity":     return "SELECT DISTINCT resource_id FROM idx_composite WHERE resource_type = 'Observation' AND param_name = 'combo-code-value-quantity'"
        case "combo-code-value-concept":      return "SELECT DISTINCT resource_id FROM idx_composite WHERE resource_type = 'Observation' AND param_name = 'combo-code-value-concept'"
        default:                   return nil
        }
    }

}
