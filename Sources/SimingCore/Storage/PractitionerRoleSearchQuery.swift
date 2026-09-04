import Foundation

public struct PractitionerRoleSearchQuery: Sendable {

    // ── Filters ───────────────────────────────────────────────────────────────

    // reference params
    public var practitioner: String?

    // system params
    public var id: [String]
    public var lastUpdated: [DateParam]
    public var missing: [String: Bool]
    public var chains: [ChainedParam]
    public var has: [HasParam]
    public var meta: MetaSearchParams           // _tag / _security / _profile

    // ── Pagination / sort ─────────────────────────────────────────────────────

    public var totalMode: TotalMode
    public var count: Int
    public var sortKeys: [SortKey]
    public var cursor: SearchCursor?

    public init(
        practitioner: String? = nil,
        id: [String] = [],
        lastUpdated: [DateParam] = [],
        missing: [String: Bool] = [:],
        chains: [ChainedParam] = [],
        has: [HasParam] = [],
        meta: MetaSearchParams = MetaSearchParams(),
        totalMode: TotalMode = .accurate,
        count: Int = 20,
        sortKeys: [SortKey] = [.default],
        cursor: SearchCursor? = nil
    ) {
        self.practitioner = practitioner
        self.id           = id
        self.lastUpdated  = lastUpdated
        self.missing      = missing
        self.chains       = chains
        self.has          = has
        self.meta         = meta
        self.totalMode    = totalMode
        self.count        = count
        self.sortKeys     = sortKeys
        self.cursor       = cursor
    }

    // ── Sort order ────────────────────────────────────────────────────────────

    /// Parses a comma-separated `_sort` value into sort keys.
    /// Only the system params are sortable — the resource's own params are not
    /// extracted yet (see the TODO markers in the generated extractor).
    public static func parseSortKeys(_ raw: String) -> [SortKey] {
        let keys = raw.split(separator: ",").compactMap { token -> SortKey? in
            let s = String(token).trimmingCharacters(in: .whitespaces)
            let desc = s.hasPrefix("-")
            let name = desc ? String(s.dropFirst()) : s
            let src: SortKeySource? = switch name {
            case "_lastUpdated": .lastUpdated
            case "_id":          .resourceId
            default:             nil
            }
            guard let src else { return nil }
            return SortKey(source: src, descending: desc)
        }
        return keys.isEmpty ? [.default] : keys
    }

    public typealias DateParam = PatientSearchQuery.BirthdateParam
    public typealias TotalMode = PatientSearchQuery.TotalMode
}
