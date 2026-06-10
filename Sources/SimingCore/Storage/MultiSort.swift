import Foundation

// ── ids CTE builder ───────────────────────────────────────────────────────
//
// Builds the inner SQL for `ids AS MATERIALIZED (…)`.
//
// When filterCTEs is non-empty, uses a LATERAL JOIN against resources_live_idx
// for an index-only current-version lookup — much faster than scanning the full
// resources table via DISTINCT ON / hash-join.
//
// When filterCTEs is empty, falls back to DISTINCT ON / full scan (no better
// index-based alternative without knowing the result set size up front).
//
// Extra conditions (beyond resource_type + deleted=false) are string-transformed:
//   r.id          → <firstCTE>.resource_id
//   r.last_updated → lat.last_updated
//
// Parameters:
//   resourceType   — SQL string literal; MUST be a compile-time constant.
//   filterCTEs     — pre-built filter CTEs; each returns resource_id rows.
//   extraConditions — WHERE conditions beyond the base resource_type+deleted guard.

public func buildIdsInner(
    resourceType: String,
    filterCTEs: [(name: String, sql: String)],
    extraConditions: [String] = []
) -> String {
    guard !filterCTEs.isEmpty else {
        // No index-backed filters — full scan via DISTINCT ON.
        var fromLines = ["FROM resources r"]
        var conds = ["r.resource_type = '\(resourceType)'", "r.deleted = false"] + extraConditions
        fromLines.append("WHERE " + conds.joined(separator: " AND "))
        fromLines.append("ORDER BY r.id, r.version_id DESC")
        return (["SELECT DISTINCT ON (r.id) r.id, r.version_id, r.last_updated"]
            + fromLines).joined(separator: "\n      ")
    }

    let first = filterCTEs[0].name
    let joinLines = filterCTEs.dropFirst().map {
        "JOIN \($0.name) ON \($0.name).resource_id = \(first).resource_id"
    }
    let joinClause = joinLines.isEmpty ? "" : "\n      " + joinLines.joined(separator: "\n      ")

    // Transform extra conditions that reference the old resources alias `r`.
    let transformedExtra = extraConditions.map { cond in
        cond
            .replacingOccurrences(of: "r.last_updated", with: "lat.last_updated")
            .replacingOccurrences(of: "r.id ", with: "\(first).resource_id ")
            .replacingOccurrences(of: "r.id)", with: "\(first).resource_id)")
    }
    let extraClause = transformedExtra.isEmpty
        ? ""
        : "\n      WHERE " + transformedExtra.joined(separator: " AND ")

    return """
        SELECT \(first).resource_id AS id, lat.version_id, lat.last_updated
        FROM \(first)\(joinClause)
        JOIN LATERAL (
          SELECT version_id, last_updated
          FROM resources
          WHERE resource_type = '\(resourceType)' AND id = \(first).resource_id AND deleted = false
          ORDER BY version_id DESC LIMIT 1
        ) lat ON TRUE\(extraClause)
        """
}

// ── Sort key source ────────────────────────────────────────────────────────
// Describes where in the index tables a sort value comes from.

public enum SortKeySource: Sendable {
    case lastUpdated                       // resources.last_updated (TIMESTAMP)
    case resourceId                        // resources.id (TEXT)
    case string(paramName: String)         // idx_string.value (TEXT)
    case date(paramName: String)           // idx_date.date_start (TIMESTAMP)
    case token(paramName: String)          // idx_token.code (TEXT)
}

public struct SortKey: Sendable {
    public let source: SortKeySource
    public let descending: Bool

    public static let `default` = SortKey(source: .lastUpdated, descending: true)

    public init(source: SortKeySource, descending: Bool) {
        self.source = source
        self.descending = descending
    }

    var isTimestamp: Bool {
        switch source {
        case .lastUpdated, .date: return true
        default: return false
        }
    }
}

// ── Shared pagination cursor ───────────────────────────────────────────────
// Replaces the per-resource SearchCursor structs.
//
// Encode format: base64url( sv_0 \x1f sv_1 \x1f … \x1f id )
//   • One value per sort key (epoch-seconds text for TIMESTAMP, raw text for TEXT).
//   • Last element is the resource id (final tiebreaker).
// Decode: split on U+001F, last = id, preceding = sort values.
//
// Old cursors (3-part "|" format) will fail decode and reset to page 1 — intended.

public struct SearchCursor: Sendable {
    public let values: [String]   // sort-key values in declaration order
    public let id: String         // resource id

    public init(values: [String], id: String) {
        self.values = values
        self.id = id
    }

    public func encode() -> String {
        let payload = (values + [id]).joined(separator: "\u{1f}")
        return Data(payload.utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    public static func decode(_ raw: String) -> SearchCursor? {
        var b64 = raw
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while b64.count % 4 != 0 { b64 += "=" }
        guard let data = Data(base64Encoded: b64),
              let s = String(data: data, encoding: .utf8) else { return nil }
        let parts = s.split(separator: "\u{1f}", omittingEmptySubsequences: false).map(String.init)
        guard parts.count >= 2 else { return nil }
        return SearchCursor(values: Array(parts.dropLast()), id: parts.last!)
    }
}

// ── Multi-sort SQL result ──────────────────────────────────────────────────

public struct MultiSortResult {
    /// Sort-key CTEs to append AFTER `ids AS MATERIALIZED` in the WITH clause.
    public let sortCTEs: [(name: String, sql: String)]
    /// Body for `paged AS (…)`. Selects:
    ///   id, version_id, last_updated, sv_0, sv_1, …, sort_val_concat
    /// where sort_val_concat is the U+001F-joined cursor value string (values + id).
    public let pagedBody: String
    /// ORDER BY fragment for the outer SELECT, e.g. "p.sv_0 DESC NULLS LAST, p.id ASC".
    public let outerOrderBy: String
}

// ── Multi-sort SQL builder ─────────────────────────────────────────────────
//
// Builds the `paged` CTE and its supporting sort-key CTEs.  The caller:
//   1. Appends sortResult.sortCTEs after `ids AS MATERIALIZED`.
//   2. Appends `paged AS (\(sortResult.pagedBody))`.
//   3. Uses `ORDER BY \(sortResult.outerOrderBy)` in the outer SELECT.
//   4. Reads `p.sort_val_concat` as the cursor-value column (6th SELECT column).
//
// The paged CTE is generated as a flat SELECT directly from `idsAlias` with optional
// LEFT JOINs for index-based sort keys — no nested subquery — so PostgreSQL can
// apply Top-N sort optimisation on the MATERIALIZED ids CTE.
//
// Cursor WHERE uses the same column expressions as ORDER BY (not aliases), which
// is required since column aliases are not visible in the same SELECT's WHERE.
//
// Parameters:
//   sortKeys    — parsed keys; falls back to [SortKey.default] when empty.
//   resourceType — SQL string literal — MUST be a compile-time constant, never user input.
//   idsAlias     — name of the MATERIALIZED CTE providing (id, version_id, last_updated).
//   cursor       — decoded cursor from the previous page, nil for page 1.
//   limitBind    — pre-bound "$N" for LIMIT.
//   bindString   — appends a String binding, returns "$N".
//   bindDate     — appends a Date binding, returns "$N".

public func buildMultiSort(
    sortKeys: [SortKey],
    resourceType: String,
    idsAlias ids: String,
    cursor: SearchCursor?,
    limitBind: String,
    bindString: (String) -> String,
    bindDate: (Date) -> String
) -> MultiSortResult {

    let keys = sortKeys.isEmpty ? [SortKey.default] : sortKeys

    // Each Slot carries both the SQL expression for ORDER BY / WHERE
    // and the alias used in the outer SELECT.
    struct Slot {
        let expr: String        // actual SQL expression (usable in WHERE / ORDER BY)
        let colName: String     // SELECT alias "sv_N"
        let orderDir: String    // "ASC" or "DESC"
        let nullsLast: Bool
        let concatExpr: String  // expression for sort_val_concat
        let isTimestamp: Bool
        let cteAlias: String?   // non-nil → needs a LEFT JOIN
    }

    var sortCTEs: [(name: String, sql: String)] = []
    var slots: [Slot] = []
    var cteIdx = 0

    for (i, key) in keys.enumerated() {
        let dir = key.descending ? "DESC" : "ASC"
        let sv = "sv_\(i)"

        switch key.source {
        case .lastUpdated:
            slots.append(Slot(
                expr: "\(ids).last_updated",
                colName: sv,
                orderDir: dir, nullsLast: true,
                concatExpr: "COALESCE(CAST(EXTRACT(EPOCH FROM \(ids).last_updated) AS text), '')",
                isTimestamp: true, cteAlias: nil
            ))

        case .resourceId:
            slots.append(Slot(
                expr: "\(ids).id",
                colName: sv,
                orderDir: dir, nullsLast: false,
                concatExpr: "\(ids).id",
                isTimestamp: false, cteAlias: nil
            ))

        case .string(let param):
            let alias = "sk_\(cteIdx)"; cteIdx += 1
            sortCTEs.append((alias,
                "SELECT DISTINCT ON (resource_id) resource_id, value AS sv " +
                "FROM idx_string WHERE resource_type = '\(resourceType)' AND param_name = '\(param)' " +
                "ORDER BY resource_id, value ASC"
            ))
            slots.append(Slot(
                expr: "COALESCE(\(alias).sv, '')",
                colName: sv,
                orderDir: dir, nullsLast: true,
                concatExpr: "COALESCE(\(alias).sv, '')",
                isTimestamp: false, cteAlias: alias
            ))

        case .date(let param):
            let alias = "sk_\(cteIdx)"; cteIdx += 1
            sortCTEs.append((alias,
                "SELECT DISTINCT ON (resource_id) resource_id, date_start AS sv " +
                "FROM idx_date WHERE resource_type = '\(resourceType)' AND param_name = '\(param)' " +
                "ORDER BY resource_id, date_start ASC"
            ))
            slots.append(Slot(
                expr: "\(alias).sv",
                colName: sv,
                orderDir: dir, nullsLast: true,
                concatExpr: "COALESCE(CAST(EXTRACT(EPOCH FROM \(alias).sv) AS text), '')",
                isTimestamp: true, cteAlias: alias
            ))

        case .token(let param):
            let alias = "sk_\(cteIdx)"; cteIdx += 1
            sortCTEs.append((alias,
                "SELECT DISTINCT ON (resource_id) resource_id, code AS sv " +
                "FROM idx_token WHERE resource_type = '\(resourceType)' AND param_name = '\(param)' " +
                "ORDER BY resource_id, code ASC"
            ))
            slots.append(Slot(
                expr: "COALESCE(\(alias).sv, '')",
                colName: sv,
                orderDir: dir, nullsLast: true,
                concatExpr: "COALESCE(\(alias).sv, '')",
                isTimestamp: false, cteAlias: alias
            ))
        }
    }

    // ── Cursor WHERE: expanded tuple comparison ──────────────────────────
    // Uses expr (the actual SQL expressions) not colName aliases, because
    // aliases defined in the same SELECT are not visible in WHERE.
    var cursorWhere = ""
    if let cur = cursor {
        let valBinds: [String] = slots.enumerated().map { (i, slot) in
            let raw = i < cur.values.count ? cur.values[i] : ""
            return slot.isTimestamp
                ? bindDate(Date(timeIntervalSince1970: Double(raw) ?? 0))
                : bindString(raw)
        }
        let idBind = bindString(cur.id)

        // One OR-term per sort key (equality prefix + ordering comparison)
        // plus a final term for the id-only tiebreaker.
        var terms: [String] = []
        for i in 0..<slots.count {
            var conds: [String] = []
            for j in 0..<i {
                if slots[j].isTimestamp { conds.append("\(slots[j].expr) IS NOT NULL") }
                conds.append("\(slots[j].expr) = \(valBinds[j])")
            }
            if slots[i].isTimestamp { conds.append("\(slots[i].expr) IS NOT NULL") }
            let op = keys[i].descending ? "<" : ">"
            conds.append("\(slots[i].expr) \(op) \(valBinds[i])")
            terms.append("(\(conds.joined(separator: " AND ")))")
        }
        var conds: [String] = []
        for (j, slot) in slots.enumerated() {
            if slot.isTimestamp { conds.append("\(slot.expr) IS NOT NULL") }
            conds.append("\(slot.expr) = \(valBinds[j])")
        }
        conds.append("\(ids).id > \(idBind)")
        terms.append("(\(conds.joined(separator: " AND ")))")
        cursorWhere = terms.joined(separator: "\n      OR ")
    }

    // ── JOINs for index-backed sort keys ─────────────────────────────────
    let joinLines = slots.compactMap { $0.cteAlias }.map {
        "LEFT JOIN \($0) ON \($0).resource_id = \(ids).id"
    }
    let joinClause = joinLines.isEmpty ? "" : "\n  " + joinLines.joined(separator: "\n  ")

    // ── SELECT list ───────────────────────────────────────────────────────
    let svSelects = slots.map { "\($0.expr) AS \($0.colName)" }.joined(separator: ",\n    ")
    let concatSQL = (slots.map { $0.concatExpr } + ["\(ids).id"]).joined(separator: " || CHR(31) || ")

    // ── ORDER BY ─────────────────────────────────────────────────────────
    let innerOrderBy = (slots.map { "\($0.expr) \($0.orderDir)\($0.nullsLast ? " NULLS LAST" : "")" }
        + ["\(ids).id ASC"]).joined(separator: ", ")
    let outerOrderBy = (slots.map { "p.\($0.colName) \($0.orderDir)\($0.nullsLast ? " NULLS LAST" : "")" }
        + ["p.id ASC"]).joined(separator: ", ")

    // ── WHERE ─────────────────────────────────────────────────────────────
    let whereClause = cursorWhere.isEmpty ? "" : "\n  WHERE \(cursorWhere)"

    // ── Paged CTE body ────────────────────────────────────────────────────
    // Flat SELECT from ids (+ optional LEFT JOINs) — no nested subquery —
    // so PostgreSQL can apply Top-N sort on the MATERIALIZED ids CTE.
    let pagedBody = """
        SELECT \(ids).id, \(ids).version_id, \(ids).last_updated,
            \(svSelects),
            \(concatSQL) AS sort_val_concat
        FROM \(ids)\(joinClause)\(whereClause)
        ORDER BY \(innerOrderBy)
        LIMIT \(limitBind)
        """

    return MultiSortResult(sortCTEs: sortCTEs, pagedBody: pagedBody, outerOrderBy: outerOrderBy)
}
