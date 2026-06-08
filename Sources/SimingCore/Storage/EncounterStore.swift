import Foundation
import Logging
import ModelsR4
import PostgresNIO

public struct EncounterStore: Sendable {
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
        public let nextCursor: EncounterSearchQuery.SearchCursor?
    }

    public struct DeleteResult: Sendable {
        public let versionId: Int64
        public let lastUpdated: Date
    }

    // ── Public API ────────────────────────────────────────────────────────────

    public func create(_ enc: Encounter) async throws -> WriteResult {
        let id = UUID().uuidString.lowercased()
        return try await write(id: id, encounter: enc, ifMatch: nil)
    }

    public func update(id: String, encounter: Encounter, ifMatch: Int64?) async throws -> WriteResult {
        return try await write(id: id, encounter: encounter, ifMatch: ifMatch)
    }

    @discardableResult
    public func delete(id: String, ifMatch: Int64?) async throws -> DeleteResult {
        try await client.withConnection { conn in
            let (versionId, lastUpdated, _) = try await deleteResource(
                conn: conn, resourceType: "Encounter", id: id, ifMatch: ifMatch, logger: logger)
            return DeleteResult(versionId: versionId, lastUpdated: lastUpdated)
        }
    }

    public func vread(id: String, versionId: Int64) async throws -> ReadResult {
        try await client.withConnection { conn in
            let rows = try await conn.query(
                """
                SELECT version_id, last_updated, content, deleted
                FROM resources
                WHERE resource_type = 'Encounter' AND id = \(id) AND version_id = \(versionId)
                """, logger: logger)
            for try await (vid, lastUpdated, content, deleted) in
                rows.decode((Int64, Date, String, Bool).self, context: .default)
            {
                if deleted { throw FHIRServerError.gone(resourceType: "Encounter", id: id) }
                let jsonData = injectMeta(into: content, versionId: vid, lastUpdated: lastUpdated)
                return ReadResult(jsonData: jsonData, versionId: vid, lastUpdated: lastUpdated)
            }
            throw FHIRServerError.notFound(resourceType: "Encounter", id: id)
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
                    WHERE resource_type = 'Encounter' AND id = \(id) AND last_updated >= \(since)
                    ORDER BY version_id DESC
                    LIMIT \(Int64(count))
                    """, logger: logger)
            } else {
                rows = try await conn.query(
                    """
                    SELECT version_id, last_updated, content, deleted
                    FROM resources
                    WHERE resource_type = 'Encounter' AND id = \(id)
                    ORDER BY version_id DESC
                    LIMIT \(Int64(count))
                    """, logger: logger)
            }
            var entries: [HistoryRawEntry] = []
            for try await (vid, lastUpdated, content, deleted) in
                rows.decode((Int64, Date, String, Bool).self, context: .default)
            {
                let jsonData: Data? = deleted ? nil : injectMeta(into: content, versionId: vid, lastUpdated: lastUpdated)
                entries.append(HistoryRawEntry(resourceType: "Encounter", id: id, versionId: vid, lastUpdated: lastUpdated, jsonData: jsonData, deleted: deleted))
            }
            if entries.isEmpty {
                if since != nil {
                    let existRows = try await conn.query(
                        """
                        SELECT 1 FROM resources WHERE resource_type = 'Encounter' AND id = \(id) LIMIT 1
                        """, logger: logger)
                    var exists = false
                    for try await _ in existRows { exists = true }
                    if !exists { throw FHIRServerError.notFound(resourceType: "Encounter", id: id) }
                } else {
                    throw FHIRServerError.notFound(resourceType: "Encounter", id: id)
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
                    WHERE resource_type = 'Encounter' AND last_updated >= \(since)
                    ORDER BY last_updated DESC, id, version_id DESC
                    LIMIT \(Int64(count))
                    """, logger: logger)
            } else {
                rows = try await conn.query(
                    """
                    SELECT id, version_id, last_updated, content, deleted
                    FROM resources
                    WHERE resource_type = 'Encounter'
                    ORDER BY last_updated DESC, id, version_id DESC
                    LIMIT \(Int64(count))
                    """, logger: logger)
            }
            var entries: [HistoryRawEntry] = []
            for try await (rid, vid, lastUpdated, content, deleted) in
                rows.decode((String, Int64, Date, String, Bool).self, context: .default)
            {
                let jsonData: Data? = deleted ? nil : injectMeta(into: content, versionId: vid, lastUpdated: lastUpdated)
                entries.append(HistoryRawEntry(resourceType: "Encounter", id: rid, versionId: vid, lastUpdated: lastUpdated, jsonData: jsonData, deleted: deleted))
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
                WHERE resource_type = 'Encounter' AND id = \(id)
                ORDER BY version_id DESC
                LIMIT 1
                """, logger: logger)
            var found: ReadResult? = nil
            for try await (versionId, lastUpdated, content, deleted) in
                rows.decode((Int64, Date, String, Bool).self, context: .default)
            {
                if deleted { throw FHIRServerError.gone(resourceType: "Encounter", id: id) }
                let jsonData = injectMeta(into: content, versionId: versionId, lastUpdated: lastUpdated)
                found = ReadResult(jsonData: jsonData, versionId: versionId, lastUpdated: lastUpdated)
            }
            guard let result = found else {
                throw FHIRServerError.notFound(resourceType: "Encounter", id: id)
            }
            return result
        }
    }

    public func search(query: EncounterSearchQuery) async throws -> SearchResult {
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

            let nextCursor: EncounterSearchQuery.SearchCursor?
            if hasNext, let lastEntry = page.last, let lastSortVal = pageSortVals.last {
                nextCursor = EncounterSearchQuery.SearchCursor(
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

    private func write(id: String, encounter: Encounter, ifMatch: Int64?) async throws -> WriteResult {
        // Validation hook — keep this call; it's one of the three open doors.
        try validate(encounter)

        var enc = encounter
        enc.id   = FHIRPrimitive(FHIRString(id))
        let originalMeta = enc.meta
        enc.meta = nil

        let jsonData   = try JSONEncoder().encode(enc)
        let jsonString = String(data: jsonData, encoding: .utf8)!
        var searchParams = extractEncounterSearchParams(enc)
        appendMetaParams(&searchParams, meta: originalMeta)

        return try await client.withConnection { conn in
            let (versionId, lastUpdated) = try await writeResource(
                conn: conn, resourceType: "Encounter", id: id,
                jsonString: jsonString, ifMatch: ifMatch, params: searchParams, logger: logger)
            let responseData = injectMeta(into: jsonString, versionId: versionId, lastUpdated: lastUpdated)
            return WriteResult(id: id, versionId: versionId, lastUpdated: lastUpdated, jsonData: responseData)
        }
    }

    private func validate(_ enc: Encounter) throws {}

    private func buildSearchSQL(query: EncounterSearchQuery) throws -> (String, PostgresBindings) {
        var binds = PostgresBindings()
        var n = 0
        func bind(_ val: some PostgresDynamicTypeEncodable) -> String {
            n += 1; binds.append(val); return "$\(n)"
        }

        var filterCTEs: [(name: String, sql: String)] = []

        // subject — idx_reference (both 'subject' and 'patient' param_names point to Encounter.subject)
        if let subject = query.subject {
            let parts = subject.split(separator: "/")
            if parts.count == 2 {
                let refTypeP = bind(String(parts[0]))
                let refIdP   = bind(String(parts[1]))
                filterCTEs.append(("f_subject", """
                    SELECT DISTINCT resource_id FROM idx_reference
                    WHERE resource_type = 'Encounter' AND param_name IN ('subject', 'patient')
                      AND ref_type = \(refTypeP) AND ref_id = \(refIdP)
                    """))
            } else {
                let refIdP = bind(subject)
                filterCTEs.append(("f_subject", """
                    SELECT DISTINCT resource_id FROM idx_reference
                    WHERE resource_type = 'Encounter' AND param_name IN ('subject', 'patient')
                      AND ref_id = \(refIdP)
                    """))
            }
        }

        // status — token OR
        if !query.status.isEmpty {
            let phs = query.status.map { bind($0) }.joined(separator: ", ")
            filterCTEs.append(("f_status", """
                SELECT DISTINCT resource_id FROM idx_token
                WHERE resource_type = 'Encounter' AND param_name = 'status'
                  AND code IN (\(phs))
                """))
        }

        // class — token OR
        if !query.encounterClass.isEmpty {
            var orClauses: [String] = []
            for tok in query.encounterClass {
                if tok.code.isEmpty, let sys = tok.system {
                    orClauses.append("system = \(bind(sys))")
                } else {
                    let codeP = bind(tok.code)
                    var sysCond = ""
                    if let sys = tok.system { sysCond = " AND system = \(bind(sys))" }
                    orClauses.append("(code = \(codeP)\(sysCond))")
                }
            }
            filterCTEs.append(("f_class", """
                SELECT DISTINCT resource_id FROM idx_token
                WHERE resource_type = 'Encounter' AND param_name = 'class'
                  AND (\(orClauses.joined(separator: " OR ")))
                """))
        }

        // type — token OR
        if !query.type.isEmpty {
            var orClauses: [String] = []
            for tok in query.type {
                if tok.code.isEmpty, let sys = tok.system {
                    orClauses.append("system = \(bind(sys))")
                } else {
                    let codeP = bind(tok.code)
                    var sysCond = ""
                    if let sys = tok.system { sysCond = " AND system = \(bind(sys))" }
                    orClauses.append("(code = \(codeP)\(sysCond))")
                }
            }
            filterCTEs.append(("f_type", """
                SELECT DISTINCT resource_id FROM idx_token
                WHERE resource_type = 'Encounter' AND param_name = 'type'
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
                    WHERE resource_type = 'Encounter' AND param_name = 'identifier'
                      AND (\(orClauses.joined(separator: " OR ")))
                    """))
            }
        }

        // participant — idx_reference
        if let participant = query.participant {
            let parts = participant.split(separator: "/")
            if parts.count == 2 {
                let refTypeP = bind(String(parts[0])); let refIdP = bind(String(parts[1]))
                filterCTEs.append(("f_participant", """
                    SELECT DISTINCT resource_id FROM idx_reference
                    WHERE resource_type = 'Encounter' AND param_name = 'participant'
                      AND ref_type = \(refTypeP) AND ref_id = \(refIdP)
                    """))
            } else {
                let refIdP = bind(participant)
                filterCTEs.append(("f_participant", """
                    SELECT DISTINCT resource_id FROM idx_reference
                    WHERE resource_type = 'Encounter' AND param_name = 'participant'
                      AND ref_id = \(refIdP)
                    """))
            }
        }

        // practitioner — idx_reference (same field, param_name='practitioner')
        if let practitioner = query.practitioner {
            let parts = practitioner.split(separator: "/")
            if parts.count == 2 {
                let refTypeP = bind(String(parts[0])); let refIdP = bind(String(parts[1]))
                filterCTEs.append(("f_practitioner", """
                    SELECT DISTINCT resource_id FROM idx_reference
                    WHERE resource_type = 'Encounter' AND param_name = 'practitioner'
                      AND ref_type = \(refTypeP) AND ref_id = \(refIdP)
                    """))
            } else {
                let refIdP = bind(practitioner)
                filterCTEs.append(("f_practitioner", """
                    SELECT DISTINCT resource_id FROM idx_reference
                    WHERE resource_type = 'Encounter' AND param_name = 'practitioner'
                      AND ref_id = \(refIdP)
                    """))
            }
        }

        // reason-code — token OR
        if !query.reasonCode.isEmpty {
            var orClauses: [String] = []
            for tok in query.reasonCode {
                if tok.code.isEmpty, let sys = tok.system {
                    orClauses.append("system = \(bind(sys))")
                } else {
                    let codeP = bind(tok.code)
                    var sysCond = ""
                    if let sys = tok.system { sysCond = " AND system = \(bind(sys))" }
                    orClauses.append("(code = \(codeP)\(sysCond))")
                }
            }
            filterCTEs.append(("f_reason_code", """
                SELECT DISTINCT resource_id FROM idx_token
                WHERE resource_type = 'Encounter' AND param_name = 'reason-code'
                  AND (\(orClauses.joined(separator: " OR ")))
                """))
        }

        // part-of — idx_reference
        if let partOf = query.partOf {
            let parts = partOf.split(separator: "/")
            if parts.count == 2 {
                let refTypeP = bind(String(parts[0])); let refIdP = bind(String(parts[1]))
                filterCTEs.append(("f_part_of", """
                    SELECT DISTINCT resource_id FROM idx_reference
                    WHERE resource_type = 'Encounter' AND param_name = 'part-of'
                      AND ref_type = \(refTypeP) AND ref_id = \(refIdP)
                    """))
            } else {
                let refIdP = bind(partOf)
                filterCTEs.append(("f_part_of", """
                    SELECT DISTINCT resource_id FROM idx_reference
                    WHERE resource_type = 'Encounter' AND param_name = 'part-of'
                      AND ref_id = \(refIdP)
                    """))
            }
        }

        // service-provider — idx_reference
        if let sp = query.serviceProvider {
            let parts = sp.split(separator: "/")
            if parts.count == 2 {
                let refTypeP = bind(String(parts[0])); let refIdP = bind(String(parts[1]))
                filterCTEs.append(("f_service_provider", """
                    SELECT DISTINCT resource_id FROM idx_reference
                    WHERE resource_type = 'Encounter' AND param_name = 'service-provider'
                      AND ref_type = \(refTypeP) AND ref_id = \(refIdP)
                    """))
            } else {
                let refIdP = bind(sp)
                filterCTEs.append(("f_service_provider", """
                    SELECT DISTINCT resource_id FROM idx_reference
                    WHERE resource_type = 'Encounter' AND param_name = 'service-provider'
                      AND ref_id = \(refIdP)
                    """))
            }
        }

        // based-on — idx_reference
        if let basedOn = query.basedOn {
            let parts = basedOn.split(separator: "/")
            if parts.count == 2 {
                let refTypeP = bind(String(parts[0])); let refIdP = bind(String(parts[1]))
                filterCTEs.append(("f_based_on", """
                    SELECT DISTINCT resource_id FROM idx_reference
                    WHERE resource_type = 'Encounter' AND param_name = 'based-on'
                      AND ref_type = \(refTypeP) AND ref_id = \(refIdP)
                    """))
            } else {
                let refIdP = bind(basedOn)
                filterCTEs.append(("f_based_on", """
                    SELECT DISTINCT resource_id FROM idx_reference
                    WHERE resource_type = 'Encounter' AND param_name = 'based-on'
                      AND ref_id = \(refIdP)
                    """))
            }
        }

        // location — idx_reference
        if let location = query.location {
            let parts = location.split(separator: "/")
            if parts.count == 2 {
                let refTypeP = bind(String(parts[0])); let refIdP = bind(String(parts[1]))
                filterCTEs.append(("f_location", """
                    SELECT DISTINCT resource_id FROM idx_reference
                    WHERE resource_type = 'Encounter' AND param_name = 'location'
                      AND ref_type = \(refTypeP) AND ref_id = \(refIdP)
                    """))
            } else {
                let refIdP = bind(location)
                filterCTEs.append(("f_location", """
                    SELECT DISTINCT resource_id FROM idx_reference
                    WHERE resource_type = 'Encounter' AND param_name = 'location'
                      AND ref_id = \(refIdP)
                    """))
            }
        }

        // diagnosis — idx_reference
        if let diagnosis = query.diagnosis {
            let parts = diagnosis.split(separator: "/")
            if parts.count == 2 {
                let refTypeP = bind(String(parts[0])); let refIdP = bind(String(parts[1]))
                filterCTEs.append(("f_diagnosis", """
                    SELECT DISTINCT resource_id FROM idx_reference
                    WHERE resource_type = 'Encounter' AND param_name = 'diagnosis'
                      AND ref_type = \(refTypeP) AND ref_id = \(refIdP)
                    """))
            } else {
                let refIdP = bind(diagnosis)
                filterCTEs.append(("f_diagnosis", """
                    SELECT DISTINCT resource_id FROM idx_reference
                    WHERE resource_type = 'Encounter' AND param_name = 'diagnosis'
                      AND ref_id = \(refIdP)
                    """))
            }
        }

        // account — idx_reference
        if let account = query.account {
            let parts = account.split(separator: "/")
            if parts.count == 2 {
                let refTypeP = bind(String(parts[0])); let refIdP = bind(String(parts[1]))
                filterCTEs.append(("f_account", """
                    SELECT DISTINCT resource_id FROM idx_reference
                    WHERE resource_type = 'Encounter' AND param_name = 'account'
                      AND ref_type = \(refTypeP) AND ref_id = \(refIdP)
                    """))
            } else {
                let refIdP = bind(account)
                filterCTEs.append(("f_account", """
                    SELECT DISTINCT resource_id FROM idx_reference
                    WHERE resource_type = 'Encounter' AND param_name = 'account'
                      AND ref_id = \(refIdP)
                    """))
            }
        }

        // appointment — idx_reference
        if let appointment = query.appointment {
            let parts = appointment.split(separator: "/")
            if parts.count == 2 {
                let refTypeP = bind(String(parts[0])); let refIdP = bind(String(parts[1]))
                filterCTEs.append(("f_appointment", """
                    SELECT DISTINCT resource_id FROM idx_reference
                    WHERE resource_type = 'Encounter' AND param_name = 'appointment'
                      AND ref_type = \(refTypeP) AND ref_id = \(refIdP)
                    """))
            } else {
                let refIdP = bind(appointment)
                filterCTEs.append(("f_appointment", """
                    SELECT DISTINCT resource_id FROM idx_reference
                    WHERE resource_type = 'Encounter' AND param_name = 'appointment'
                      AND ref_id = \(refIdP)
                    """))
            }
        }

        // episode-of-care — idx_reference
        if let eoc = query.episodeOfCare {
            let parts = eoc.split(separator: "/")
            if parts.count == 2 {
                let refTypeP = bind(String(parts[0])); let refIdP = bind(String(parts[1]))
                filterCTEs.append(("f_episode_of_care", """
                    SELECT DISTINCT resource_id FROM idx_reference
                    WHERE resource_type = 'Encounter' AND param_name = 'episode-of-care'
                      AND ref_type = \(refTypeP) AND ref_id = \(refIdP)
                    """))
            } else {
                let refIdP = bind(eoc)
                filterCTEs.append(("f_episode_of_care", """
                    SELECT DISTINCT resource_id FROM idx_reference
                    WHERE resource_type = 'Encounter' AND param_name = 'episode-of-care'
                      AND ref_id = \(refIdP)
                    """))
            }
        }

        // reason-reference — idx_reference
        if let rr = query.reasonReference {
            let parts = rr.split(separator: "/")
            if parts.count == 2 {
                let refTypeP = bind(String(parts[0])); let refIdP = bind(String(parts[1]))
                filterCTEs.append(("f_reason_reference", """
                    SELECT DISTINCT resource_id FROM idx_reference
                    WHERE resource_type = 'Encounter' AND param_name = 'reason-reference'
                      AND ref_type = \(refTypeP) AND ref_id = \(refIdP)
                    """))
            } else {
                let refIdP = bind(rr)
                filterCTEs.append(("f_reason_reference", """
                    SELECT DISTINCT resource_id FROM idx_reference
                    WHERE resource_type = 'Encounter' AND param_name = 'reason-reference'
                      AND ref_id = \(refIdP)
                    """))
            }
        }

        // participant-type — token OR
        if !query.participantType.isEmpty {
            var orClauses: [String] = []
            for tok in query.participantType {
                if tok.code.isEmpty, let sys = tok.system {
                    orClauses.append("system = \(bind(sys))")
                } else {
                    let codeP = bind(tok.code)
                    var sysCond = ""
                    if let sys = tok.system { sysCond = " AND system = \(bind(sys))" }
                    orClauses.append("(code = \(codeP)\(sysCond))")
                }
            }
            filterCTEs.append(("f_participant_type", """
                SELECT DISTINCT resource_id FROM idx_token
                WHERE resource_type = 'Encounter' AND param_name = 'participant-type'
                  AND (\(orClauses.joined(separator: " OR ")))
                """))
        }

        // special-arrangement — token OR
        if !query.specialArrangement.isEmpty {
            var orClauses: [String] = []
            for tok in query.specialArrangement {
                if tok.code.isEmpty, let sys = tok.system {
                    orClauses.append("system = \(bind(sys))")
                } else {
                    let codeP = bind(tok.code)
                    var sysCond = ""
                    if let sys = tok.system { sysCond = " AND system = \(bind(sys))" }
                    orClauses.append("(code = \(codeP)\(sysCond))")
                }
            }
            filterCTEs.append(("f_special_arrangement", """
                SELECT DISTINCT resource_id FROM idx_token
                WHERE resource_type = 'Encounter' AND param_name = 'special-arrangement'
                  AND (\(orClauses.joined(separator: " OR ")))
                """))
        }

        // length — idx_quantity numeric filter
        if !query.length.isEmpty {
            var orClauses: [String] = []
            for qp in query.length {
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
                case .ap: let lo = bind(qp.value * 0.9); let hi = bind(qp.value * 1.1); cond = "value BETWEEN \(lo) AND \(hi)"
                }
                if let sys = qp.system { cond += " AND system = \(bind(sys))" }
                if let code = qp.code  { cond += " AND code = \(bind(code))" }
                orClauses.append("(\(cond))")
            }
            filterCTEs.append(("f_length", "SELECT DISTINCT resource_id FROM idx_quantity WHERE resource_type = 'Encounter' AND param_name = 'length' AND (\(orClauses.joined(separator: " OR ")))"))
        }

        // date — idx_date range (Encounter.period → param_name='date')
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
                WHERE resource_type = 'Encounter' AND param_name = 'date' AND \(cond)
                """))
        }

        // location-period — idx_date range
        for (i, dp) in query.locationPeriod.enumerated() {
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
            filterCTEs.append(("f_loc_period\(i)", """
                SELECT DISTINCT resource_id FROM idx_date
                WHERE resource_type = 'Encounter' AND param_name = 'location-period' AND \(cond)
                """))
        }

        // ── WHERE conditions for :not modifiers and direct resource filters ─────

        var whereConditions = ["r.resource_type = 'Encounter'", "r.deleted = false"]

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
                whereConditions.append("r.id NOT IN (SELECT resource_id FROM idx_token WHERE resource_type = 'Encounter' AND param_name = 'identifier' AND (\(orClauses.joined(separator: " OR "))))")
            }
        }

        if !query.statusNot.isEmpty {
            let phs = query.statusNot.map { bind($0) }.joined(separator: ", ")
            whereConditions.append("r.id NOT IN (SELECT resource_id FROM idx_token WHERE resource_type = 'Encounter' AND param_name = 'status' AND code IN (\(phs)))")
        }

        if !query.classNot.isEmpty {
            var orClauses: [String] = []
            for tok in query.classNot {
                if tok.code.isEmpty, let sys = tok.system {
                    orClauses.append("system = \(bind(sys))")
                } else {
                    let codeP = bind(tok.code)
                    var sysCond = ""
                    if let sys = tok.system { sysCond = " AND system = \(bind(sys))" }
                    orClauses.append("(code = \(codeP)\(sysCond))")
                }
            }
            whereConditions.append("r.id NOT IN (SELECT resource_id FROM idx_token WHERE resource_type = 'Encounter' AND param_name = 'class' AND (\(orClauses.joined(separator: " OR "))))")
        }

        if !query.typeNot.isEmpty {
            var orClauses: [String] = []
            for tok in query.typeNot {
                if tok.code.isEmpty, let sys = tok.system {
                    orClauses.append("system = \(bind(sys))")
                } else {
                    let codeP = bind(tok.code)
                    var sysCond = ""
                    if let sys = tok.system { sysCond = " AND system = \(bind(sys))" }
                    orClauses.append("(code = \(codeP)\(sysCond))")
                }
            }
            whereConditions.append("r.id NOT IN (SELECT resource_id FROM idx_token WHERE resource_type = 'Encounter' AND param_name = 'type' AND (\(orClauses.joined(separator: " OR "))))")
        }

        if !query.reasonCodeNot.isEmpty {
            var orClauses: [String] = []
            for tok in query.reasonCodeNot {
                if tok.code.isEmpty, let sys = tok.system {
                    orClauses.append("system = \(bind(sys))")
                } else {
                    let codeP = bind(tok.code)
                    var sysCond = ""
                    if let sys = tok.system { sysCond = " AND system = \(bind(sys))" }
                    orClauses.append("(code = \(codeP)\(sysCond))")
                }
            }
            whereConditions.append("r.id NOT IN (SELECT resource_id FROM idx_token WHERE resource_type = 'Encounter' AND param_name = 'reason-code' AND (\(orClauses.joined(separator: " OR "))))")
        }

        if !query.participantTypeNot.isEmpty {
            var orClauses: [String] = []
            for tok in query.participantTypeNot {
                if tok.code.isEmpty, let sys = tok.system {
                    orClauses.append("system = \(bind(sys))")
                } else {
                    let codeP = bind(tok.code)
                    var sysCond = ""
                    if let sys = tok.system { sysCond = " AND system = \(bind(sys))" }
                    orClauses.append("(code = \(codeP)\(sysCond))")
                }
            }
            whereConditions.append("r.id NOT IN (SELECT resource_id FROM idx_token WHERE resource_type = 'Encounter' AND param_name = 'participant-type' AND (\(orClauses.joined(separator: " OR "))))")
        }

        if !query.specialArrangementNot.isEmpty {
            var orClauses: [String] = []
            for tok in query.specialArrangementNot {
                if tok.code.isEmpty, let sys = tok.system {
                    orClauses.append("system = \(bind(sys))")
                } else {
                    let codeP = bind(tok.code)
                    var sysCond = ""
                    if let sys = tok.system { sysCond = " AND system = \(bind(sys))" }
                    orClauses.append("(code = \(codeP)\(sysCond))")
                }
            }
            whereConditions.append("r.id NOT IN (SELECT resource_id FROM idx_token WHERE resource_type = 'Encounter' AND param_name = 'special-arrangement' AND (\(orClauses.joined(separator: " OR "))))")
        }

        for paramName in query.missing.keys.sorted() {
            if let sub = encounterMissingSubquery(param: paramName) {
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
                index: filterCTEs.count + i, sourceType: "Encounter",
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
                index: i, mainType: "Encounter",
                param: hp, bindStr: hBindStr, bindDate: hBindDate
            ) {
                filterCTEs.append((name, sql))
            }
        }

        // meta params: _tag, _security, _profile
        let strBind: (String) -> String = { bind($0) }
        let (metaCTEs, metaWhere) = metaFilterCTEs(resourceType: "Encounter", meta: query.meta, bind: strBind)
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
                "FROM idx_date WHERE resource_type = 'Encounter' AND param_name = 'date' " +
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

        case .statusAscending, .statusDescending:
            sortKeysCTE = ("sort_keys",
                "SELECT DISTINCT ON (resource_id) resource_id, code AS sv " +
                "FROM idx_token WHERE resource_type = 'Encounter' AND param_name = 'status' " +
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
            ? "FROM paged p JOIN resources r ON r.resource_type = 'Encounter' AND r.id = p.id AND r.version_id = p.version_id"
            : "FROM paged p CROSS JOIN total_count t JOIN resources r ON r.resource_type = 'Encounter' AND r.id = p.id AND r.version_id = p.version_id"

        let sql = "\(withClause)\nSELECT p.id, p.version_id, p.last_updated, r.content, \(totalExpr), \(finalSortValSQL) AS sort_val_text\n\(fromClause)\nORDER BY sort_val_text \(orderDir) NULLS LAST, p.id ASC"
        return (sql, binds)
    }

    private func buildCountSQL(query: EncounterSearchQuery) throws -> (String, PostgresBindings) {
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
                    "SELECT DISTINCT resource_id FROM idx_reference WHERE resource_type = 'Encounter' AND param_name IN ('subject', 'patient') AND ref_type = \(refTypeP) AND ref_id = \(refIdP)"))
            } else {
                let refIdP = bind(subject)
                filterCTEs.append(("f_subject",
                    "SELECT DISTINCT resource_id FROM idx_reference WHERE resource_type = 'Encounter' AND param_name IN ('subject', 'patient') AND ref_id = \(refIdP)"))
            }
        }
        if !query.status.isEmpty {
            let phs = query.status.map { bind($0) }.joined(separator: ", ")
            filterCTEs.append(("f_status",
                "SELECT DISTINCT resource_id FROM idx_token WHERE resource_type = 'Encounter' AND param_name = 'status' AND code IN (\(phs))"))
        }
        if !query.encounterClass.isEmpty {
            var orClauses: [String] = []
            for tok in query.encounterClass {
                if tok.code.isEmpty, let sys = tok.system {
                    orClauses.append("system = \(bind(sys))")
                } else {
                    let codeP = bind(tok.code)
                    var sysCond = ""
                    if let sys = tok.system { sysCond = " AND system = \(bind(sys))" }
                    orClauses.append("(code = \(codeP)\(sysCond))")
                }
            }
            filterCTEs.append(("f_class",
                "SELECT DISTINCT resource_id FROM idx_token WHERE resource_type = 'Encounter' AND param_name = 'class' AND (\(orClauses.joined(separator: " OR ")))"))
        }
        if !query.type.isEmpty {
            var orClauses: [String] = []
            for tok in query.type {
                if tok.code.isEmpty, let sys = tok.system {
                    orClauses.append("system = \(bind(sys))")
                } else {
                    let codeP = bind(tok.code)
                    var sysCond = ""
                    if let sys = tok.system { sysCond = " AND system = \(bind(sys))" }
                    orClauses.append("(code = \(codeP)\(sysCond))")
                }
            }
            filterCTEs.append(("f_type",
                "SELECT DISTINCT resource_id FROM idx_token WHERE resource_type = 'Encounter' AND param_name = 'type' AND (\(orClauses.joined(separator: " OR ")))"))
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
                    "SELECT DISTINCT resource_id FROM idx_token WHERE resource_type = 'Encounter' AND param_name = 'identifier' AND (\(orClauses.joined(separator: " OR ")))"))
            }
        }
        if let participant = query.participant {
            let parts = participant.split(separator: "/")
            if parts.count == 2 {
                let refTypeP = bind(String(parts[0])); let refIdP = bind(String(parts[1]))
                filterCTEs.append(("f_participant", "SELECT DISTINCT resource_id FROM idx_reference WHERE resource_type = 'Encounter' AND param_name = 'participant' AND ref_type = \(refTypeP) AND ref_id = \(refIdP)"))
            } else {
                let refIdP = bind(participant)
                filterCTEs.append(("f_participant", "SELECT DISTINCT resource_id FROM idx_reference WHERE resource_type = 'Encounter' AND param_name = 'participant' AND ref_id = \(refIdP)"))
            }
        }
        if let practitioner = query.practitioner {
            let parts = practitioner.split(separator: "/")
            if parts.count == 2 {
                let refTypeP = bind(String(parts[0])); let refIdP = bind(String(parts[1]))
                filterCTEs.append(("f_practitioner", "SELECT DISTINCT resource_id FROM idx_reference WHERE resource_type = 'Encounter' AND param_name = 'practitioner' AND ref_type = \(refTypeP) AND ref_id = \(refIdP)"))
            } else {
                let refIdP = bind(practitioner)
                filterCTEs.append(("f_practitioner", "SELECT DISTINCT resource_id FROM idx_reference WHERE resource_type = 'Encounter' AND param_name = 'practitioner' AND ref_id = \(refIdP)"))
            }
        }
        if !query.reasonCode.isEmpty {
            var orClauses: [String] = []
            for tok in query.reasonCode {
                if tok.code.isEmpty, let sys = tok.system {
                    orClauses.append("system = \(bind(sys))")
                } else {
                    let codeP = bind(tok.code)
                    var sysCond = ""
                    if let sys = tok.system { sysCond = " AND system = \(bind(sys))" }
                    orClauses.append("(code = \(codeP)\(sysCond))")
                }
            }
            filterCTEs.append(("f_reason_code", "SELECT DISTINCT resource_id FROM idx_token WHERE resource_type = 'Encounter' AND param_name = 'reason-code' AND (\(orClauses.joined(separator: " OR ")))"))
        }
        if let partOf = query.partOf {
            let parts = partOf.split(separator: "/")
            if parts.count == 2 {
                let refTypeP = bind(String(parts[0])); let refIdP = bind(String(parts[1]))
                filterCTEs.append(("f_part_of", "SELECT DISTINCT resource_id FROM idx_reference WHERE resource_type = 'Encounter' AND param_name = 'part-of' AND ref_type = \(refTypeP) AND ref_id = \(refIdP)"))
            } else {
                let refIdP = bind(partOf)
                filterCTEs.append(("f_part_of", "SELECT DISTINCT resource_id FROM idx_reference WHERE resource_type = 'Encounter' AND param_name = 'part-of' AND ref_id = \(refIdP)"))
            }
        }
        if let sp = query.serviceProvider {
            let parts = sp.split(separator: "/")
            if parts.count == 2 {
                let refTypeP = bind(String(parts[0])); let refIdP = bind(String(parts[1]))
                filterCTEs.append(("f_service_provider", "SELECT DISTINCT resource_id FROM idx_reference WHERE resource_type = 'Encounter' AND param_name = 'service-provider' AND ref_type = \(refTypeP) AND ref_id = \(refIdP)"))
            } else {
                let refIdP = bind(sp)
                filterCTEs.append(("f_service_provider", "SELECT DISTINCT resource_id FROM idx_reference WHERE resource_type = 'Encounter' AND param_name = 'service-provider' AND ref_id = \(refIdP)"))
            }
        }
        if let basedOn = query.basedOn {
            let parts = basedOn.split(separator: "/")
            if parts.count == 2 {
                let refTypeP = bind(String(parts[0])); let refIdP = bind(String(parts[1]))
                filterCTEs.append(("f_based_on", "SELECT DISTINCT resource_id FROM idx_reference WHERE resource_type = 'Encounter' AND param_name = 'based-on' AND ref_type = \(refTypeP) AND ref_id = \(refIdP)"))
            } else {
                let refIdP = bind(basedOn)
                filterCTEs.append(("f_based_on", "SELECT DISTINCT resource_id FROM idx_reference WHERE resource_type = 'Encounter' AND param_name = 'based-on' AND ref_id = \(refIdP)"))
            }
        }
        if let location = query.location {
            let parts = location.split(separator: "/")
            if parts.count == 2 {
                let refTypeP = bind(String(parts[0])); let refIdP = bind(String(parts[1]))
                filterCTEs.append(("f_location", "SELECT DISTINCT resource_id FROM idx_reference WHERE resource_type = 'Encounter' AND param_name = 'location' AND ref_type = \(refTypeP) AND ref_id = \(refIdP)"))
            } else {
                let refIdP = bind(location)
                filterCTEs.append(("f_location", "SELECT DISTINCT resource_id FROM idx_reference WHERE resource_type = 'Encounter' AND param_name = 'location' AND ref_id = \(refIdP)"))
            }
        }
        if let diagnosis = query.diagnosis {
            let parts = diagnosis.split(separator: "/")
            if parts.count == 2 {
                let refTypeP = bind(String(parts[0])); let refIdP = bind(String(parts[1]))
                filterCTEs.append(("f_diagnosis", "SELECT DISTINCT resource_id FROM idx_reference WHERE resource_type = 'Encounter' AND param_name = 'diagnosis' AND ref_type = \(refTypeP) AND ref_id = \(refIdP)"))
            } else {
                let refIdP = bind(diagnosis)
                filterCTEs.append(("f_diagnosis", "SELECT DISTINCT resource_id FROM idx_reference WHERE resource_type = 'Encounter' AND param_name = 'diagnosis' AND ref_id = \(refIdP)"))
            }
        }

        func refCTE(name: String, paramName: String, ref: String) -> (String, String) {
            let parts = ref.split(separator: "/")
            if parts.count == 2 {
                let tP = bind(String(parts[0])); let iP = bind(String(parts[1]))
                return (name, "SELECT DISTINCT resource_id FROM idx_reference WHERE resource_type = 'Encounter' AND param_name = '\(paramName)' AND ref_type = \(tP) AND ref_id = \(iP)")
            } else {
                let iP = bind(ref)
                return (name, "SELECT DISTINCT resource_id FROM idx_reference WHERE resource_type = 'Encounter' AND param_name = '\(paramName)' AND ref_id = \(iP)")
            }
        }
        if let v = query.account        { filterCTEs.append(refCTE(name: "f_account",         paramName: "account",           ref: v)) }
        if let v = query.appointment    { filterCTEs.append(refCTE(name: "f_appointment",      paramName: "appointment",       ref: v)) }
        if let v = query.episodeOfCare  { filterCTEs.append(refCTE(name: "f_episode_of_care",  paramName: "episode-of-care",   ref: v)) }
        if let v = query.reasonReference { filterCTEs.append(refCTE(name: "f_reason_ref",      paramName: "reason-reference",  ref: v)) }

        func tokenCTE(name: String, paramName: String, tokens: [EncounterSearchQuery.TokenParam]) -> (String, String) {
            var orClauses: [String] = []
            for tok in tokens {
                if tok.code.isEmpty, let sys = tok.system { orClauses.append("system = \(bind(sys))") }
                else { let cp = bind(tok.code); var sc = ""; if let s = tok.system { sc = " AND system = \(bind(s))" }; orClauses.append("(code = \(cp)\(sc))") }
            }
            return (name, "SELECT DISTINCT resource_id FROM idx_token WHERE resource_type = 'Encounter' AND param_name = '\(paramName)' AND (\(orClauses.joined(separator: " OR ")))")
        }
        if !query.participantType.isEmpty   { filterCTEs.append(tokenCTE(name: "f_participant_type",  paramName: "participant-type",   tokens: query.participantType)) }
        if !query.specialArrangement.isEmpty { filterCTEs.append(tokenCTE(name: "f_special_arr",     paramName: "special-arrangement", tokens: query.specialArrangement)) }

        if !query.length.isEmpty {
            var orClauses: [String] = []
            for qp in query.length {
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
                case .ap: let lo = bind(qp.value * 0.9); let hi = bind(qp.value * 1.1); cond = "value BETWEEN \(lo) AND \(hi)"
                }
                if let sys = qp.system { cond += " AND system = \(bind(sys))" }
                if let code = qp.code  { cond += " AND code = \(bind(code))" }
                orClauses.append("(\(cond))")
            }
            filterCTEs.append(("f_length", "SELECT DISTINCT resource_id FROM idx_quantity WHERE resource_type = 'Encounter' AND param_name = 'length' AND (\(orClauses.joined(separator: " OR ")))"))
        }

        for (i, dp) in query.date.enumerated() {
            let startP = bind(dp.dateStart); let endP = bind(dp.dateEnd)
            let cond: String
            switch dp.prefix {
            case .eq: cond = "date_start <= \(endP) AND date_end >= \(startP)"
            case .ne: cond = "NOT (date_start <= \(endP) AND date_end >= \(startP))"
            case .lt: cond = "date_end < \(startP)"; case .le: cond = "date_start <= \(endP)"
            case .gt: cond = "date_start > \(endP)"; case .ge: cond = "date_end >= \(startP)"
            case .sa: cond = "date_start > \(endP)"; case .eb: cond = "date_end < \(startP)"
            case .ap: cond = "date_start <= \(bind(dp.apExpandedEnd)) AND date_end >= \(bind(dp.apExpandedStart))"
            }
            filterCTEs.append(("f_date\(i)",
                "SELECT DISTINCT resource_id FROM idx_date WHERE resource_type = 'Encounter' AND param_name = 'date' AND \(cond)"))
        }
        for (i, dp) in query.locationPeriod.enumerated() {
            let startP = bind(dp.dateStart); let endP = bind(dp.dateEnd)
            let cond: String
            switch dp.prefix {
            case .eq: cond = "date_start <= \(endP) AND date_end >= \(startP)"
            case .ne: cond = "NOT (date_start <= \(endP) AND date_end >= \(startP))"
            case .lt: cond = "date_end < \(startP)"; case .le: cond = "date_start <= \(endP)"
            case .gt: cond = "date_start > \(endP)"; case .ge: cond = "date_end >= \(startP)"
            case .sa: cond = "date_start > \(endP)"; case .eb: cond = "date_end < \(startP)"
            case .ap: cond = "date_start <= \(bind(dp.apExpandedEnd)) AND date_end >= \(bind(dp.apExpandedStart))"
            }
            filterCTEs.append(("f_loc_period\(i)",
                "SELECT DISTINCT resource_id FROM idx_date WHERE resource_type = 'Encounter' AND param_name = 'location-period' AND \(cond)"))
        }

        var whereConditions = ["r.resource_type = 'Encounter'", "r.deleted = false"]
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

        func notTokenCond(paramName: String, tokens: [EncounterSearchQuery.TokenParam]) -> String {
            var orClauses: [String] = []
            for tok in tokens {
                if tok.code.isEmpty, let sys = tok.system { orClauses.append("system = \(bind(sys))") }
                else { let cp = bind(tok.code); var sc = ""; if let s = tok.system { sc = " AND system = \(bind(s))" }; orClauses.append("(code = \(cp)\(sc))") }
            }
            return "r.id NOT IN (SELECT resource_id FROM idx_token WHERE resource_type = 'Encounter' AND param_name = '\(paramName)' AND (\(orClauses.joined(separator: " OR "))))"
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
                whereConditions.append("r.id NOT IN (SELECT resource_id FROM idx_token WHERE resource_type = 'Encounter' AND param_name = 'identifier' AND (\(orClauses.joined(separator: " OR "))))")
            }
        }

        if !query.statusNot.isEmpty {
            let phs = query.statusNot.map { bind($0) }.joined(separator: ", ")
            whereConditions.append("r.id NOT IN (SELECT resource_id FROM idx_token WHERE resource_type = 'Encounter' AND param_name = 'status' AND code IN (\(phs)))")
        }
        if !query.classNot.isEmpty     { whereConditions.append(notTokenCond(paramName: "class",               tokens: query.classNot)) }
        if !query.typeNot.isEmpty      { whereConditions.append(notTokenCond(paramName: "type",                tokens: query.typeNot)) }
        if !query.reasonCodeNot.isEmpty { whereConditions.append(notTokenCond(paramName: "reason-code",        tokens: query.reasonCodeNot)) }
        if !query.participantTypeNot.isEmpty { whereConditions.append(notTokenCond(paramName: "participant-type", tokens: query.participantTypeNot)) }
        if !query.specialArrangementNot.isEmpty { whereConditions.append(notTokenCond(paramName: "special-arrangement", tokens: query.specialArrangementNot)) }

        for paramName in query.missing.keys.sorted() {
            if let sub = encounterMissingSubquery(param: paramName) {
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
                index: filterCTEs.count + i, sourceType: "Encounter",
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
                index: i, mainType: "Encounter",
                param: hp, bindStr: hBindStr, bindDate: hBindDate
            ) {
                filterCTEs.append((name, sql))
            }
        }

        // meta params: _tag, _security, _profile
        let strBind: (String) -> String = { bind($0) }
        let (metaCTEs, metaWhere) = metaFilterCTEs(resourceType: "Encounter", meta: query.meta, bind: strBind)
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

    private func encounterMissingSubquery(param: String) -> String? {
        switch param {
        case "subject", "patient":   return "SELECT DISTINCT resource_id FROM idx_reference WHERE resource_type = 'Encounter' AND param_name IN ('subject', 'patient')"
        case "status":               return "SELECT DISTINCT resource_id FROM idx_token WHERE resource_type = 'Encounter' AND param_name = 'status'"
        case "class":                return "SELECT DISTINCT resource_id FROM idx_token WHERE resource_type = 'Encounter' AND param_name = 'class'"
        case "type":                 return "SELECT DISTINCT resource_id FROM idx_token WHERE resource_type = 'Encounter' AND param_name = 'type'"
        case "identifier":           return "SELECT DISTINCT resource_id FROM idx_token WHERE resource_type = 'Encounter' AND param_name = 'identifier'"
        case "date":                 return "SELECT DISTINCT resource_id FROM idx_date WHERE resource_type = 'Encounter' AND param_name = 'date'"
        case "participant":          return "SELECT DISTINCT resource_id FROM idx_reference WHERE resource_type = 'Encounter' AND param_name = 'participant'"
        case "practitioner":         return "SELECT DISTINCT resource_id FROM idx_reference WHERE resource_type = 'Encounter' AND param_name = 'practitioner'"
        case "reason-code":          return "SELECT DISTINCT resource_id FROM idx_token WHERE resource_type = 'Encounter' AND param_name = 'reason-code'"
        case "part-of":              return "SELECT DISTINCT resource_id FROM idx_reference WHERE resource_type = 'Encounter' AND param_name = 'part-of'"
        case "service-provider":     return "SELECT DISTINCT resource_id FROM idx_reference WHERE resource_type = 'Encounter' AND param_name = 'service-provider'"
        case "based-on":             return "SELECT DISTINCT resource_id FROM idx_reference WHERE resource_type = 'Encounter' AND param_name = 'based-on'"
        case "location":             return "SELECT DISTINCT resource_id FROM idx_reference WHERE resource_type = 'Encounter' AND param_name = 'location'"
        case "diagnosis":            return "SELECT DISTINCT resource_id FROM idx_reference WHERE resource_type = 'Encounter' AND param_name = 'diagnosis'"
        case "account":              return "SELECT DISTINCT resource_id FROM idx_reference WHERE resource_type = 'Encounter' AND param_name = 'account'"
        case "appointment":          return "SELECT DISTINCT resource_id FROM idx_reference WHERE resource_type = 'Encounter' AND param_name = 'appointment'"
        case "episode-of-care":      return "SELECT DISTINCT resource_id FROM idx_reference WHERE resource_type = 'Encounter' AND param_name = 'episode-of-care'"
        case "reason-reference":     return "SELECT DISTINCT resource_id FROM idx_reference WHERE resource_type = 'Encounter' AND param_name = 'reason-reference'"
        case "location-period":      return "SELECT DISTINCT resource_id FROM idx_date WHERE resource_type = 'Encounter' AND param_name = 'location-period'"
        case "participant-type":     return "SELECT DISTINCT resource_id FROM idx_token WHERE resource_type = 'Encounter' AND param_name = 'participant-type'"
        case "special-arrangement":  return "SELECT DISTINCT resource_id FROM idx_token WHERE resource_type = 'Encounter' AND param_name = 'special-arrangement'"
        case "length":               return "SELECT DISTINCT resource_id FROM idx_quantity WHERE resource_type = 'Encounter' AND param_name = 'length'"
        default:                     return nil
        }
    }
}
