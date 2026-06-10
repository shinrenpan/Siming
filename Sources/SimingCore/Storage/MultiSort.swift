import Foundation

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
// The paged CTE produces correct keyset pagination via an expanded tuple
// comparison (N+1 OR terms) that handles mixed ASC/DESC sort keys.
// TIMESTAMP columns use IS NOT NULL guards in cursor conditions (consistent
// with existing single-sort behaviour for resources that lack a date index row).
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

    struct Slot {
        let innerExpr: String    // "…expr… AS sv_N"
        let colName: String      // "sv_N"
        let orderDir: String     // "ASC" or "DESC"
        let nullsLast: Bool
        let concatExpr: String   // expression for sort_val_concat (epoch text for TIMESTAMP)
        let isTimestamp: Bool
        let cteAlias: String?    // non-nil → needs a LEFT JOIN
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
                innerExpr: "\(ids).last_updated AS \(sv)",
                colName: sv,
                orderDir: dir, nullsLast: true,
                concatExpr: "COALESCE(CAST(EXTRACT(EPOCH FROM \(sv)) AS text), '')",
                isTimestamp: true, cteAlias: nil
            ))

        case .resourceId:
            slots.append(Slot(
                innerExpr: "\(ids).id AS \(sv)",
                colName: sv,
                orderDir: dir, nullsLast: false,
                concatExpr: sv,
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
                innerExpr: "COALESCE(\(alias).sv, '') AS \(sv)",
                colName: sv,
                orderDir: dir, nullsLast: true,
                concatExpr: sv,
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
                innerExpr: "\(alias).sv AS \(sv)",
                colName: sv,
                orderDir: dir, nullsLast: true,
                concatExpr: "COALESCE(CAST(EXTRACT(EPOCH FROM \(sv)) AS text), '')",
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
                innerExpr: "COALESCE(\(alias).sv, '') AS \(sv)",
                colName: sv,
                orderDir: dir, nullsLast: true,
                concatExpr: sv,
                isTimestamp: false, cteAlias: alias
            ))
        }
    }

    // ── Cursor WHERE: expanded tuple comparison ──────────────────────────
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
                if slots[j].isTimestamp { conds.append("\(slots[j].colName) IS NOT NULL") }
                conds.append("\(slots[j].colName) = \(valBinds[j])")
            }
            if slots[i].isTimestamp { conds.append("\(slots[i].colName) IS NOT NULL") }
            let op = keys[i].descending ? "<" : ">"
            conds.append("\(slots[i].colName) \(op) \(valBinds[i])")
            terms.append("(\(conds.joined(separator: " AND ")))")
        }
        var conds: [String] = []
        for (j, slot) in slots.enumerated() {
            if slot.isTimestamp { conds.append("\(slot.colName) IS NOT NULL") }
            conds.append("\(slot.colName) = \(valBinds[j])")
        }
        conds.append("id > \(idBind)")
        terms.append("(\(conds.joined(separator: " AND ")))")
        cursorWhere = terms.joined(separator: "\n      OR ")
    }

    // ── Inner subquery ───────────────────────────────────────────────────
    let joinLines = sortCTEs.map { "LEFT JOIN \($0.name) ON \($0.name).resource_id = \(ids).id" }
    let joinClause = joinLines.isEmpty ? "" : "\n      " + joinLines.joined(separator: "\n      ")

    let innerCols = (["\(ids).id", "\(ids).version_id", "\(ids).last_updated"]
        + slots.map { $0.innerExpr }).joined(separator: ",\n        ")
    let innerSQL = "SELECT \(innerCols)\n      FROM \(ids)\(joinClause)"

    // ── sort_val_concat: U+001F-delimited sort values + id ───────────────
    let concatSQL = (slots.map { $0.concatExpr } + ["id"]).joined(separator: " || CHR(31) || ")

    // ── ORDER BY ─────────────────────────────────────────────────────────
    func orderPart(_ prefix: String, _ slot: Slot) -> String {
        "\(prefix)\(slot.colName) \(slot.orderDir)\(slot.nullsLast ? " NULLS LAST" : "")"
    }
    let innerOrderBy = (slots.map { orderPart("", $0) } + ["id ASC"]).joined(separator: ", ")
    let outerOrderBy = (slots.map { orderPart("p.", $0) } + ["p.id ASC"]).joined(separator: ", ")

    // ── Paged CTE body ───────────────────────────────────────────────────
    let svCols = (["id", "version_id", "last_updated"] + slots.map { $0.colName }).joined(separator: ", ")
    let whereClause = cursorWhere.isEmpty ? "" : "\n    WHERE \(cursorWhere)"

    let pagedBody = """
        SELECT \(svCols),
            \(concatSQL) AS sort_val_concat
        FROM (
          \(innerSQL)
        ) sub\(whereClause)
        ORDER BY \(innerOrderBy)
        LIMIT \(limitBind)
        """

    return MultiSortResult(sortCTEs: sortCTEs, pagedBody: pagedBody, outerOrderBy: outerOrderBy)
}
