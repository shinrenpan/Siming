import Foundation

public struct GoalSearchQuery: Sendable {

    // ── Filters ───────────────────────────────────────────────────────────────

    // token params
    public var lifecycleStatus: [TokenParam]
    public var lifecycleStatusNot: [TokenParam]
    public var achievementStatus: [TokenParam]
    public var achievementStatusNot: [TokenParam]  // achievement-status:not modifier
    public var category: [TokenParam]
    public var categoryNot: [TokenParam]
    public var identifier: [IdentifierParam]
    public var identifierNot: [IdentifierParam]  // identifier:not modifier

    // date params
    public var startDate: [DateParam]
    public var targetDate: [DateParam]

    // reference params
    public var subject: String?
    public var patient: String?

    // system params
    public var id: [String]
    public var meta: MetaSearchParams = MetaSearchParams()  // _tag / _security / _profile
    public var lastUpdated: [DateParam]
    public var tokenTexts: [TokenTextParam]
    public var missing: [String: Bool]
    public var chains: [ChainedParam]
    public var has: [HasParam]

    // ── Pagination / sort ─────────────────────────────────────────────────────

    public var totalMode: TotalMode
    public var count: Int
    public var sortKeys: [SortKey]
    public var cursor: SearchCursor?

    public init(
        lifecycleStatus: [TokenParam] = [],
        lifecycleStatusNot: [TokenParam] = [],
        achievementStatus: [TokenParam] = [],
        achievementStatusNot: [TokenParam] = [],
        category: [TokenParam] = [],
        categoryNot: [TokenParam] = [],
        identifier: [IdentifierParam] = [],
        identifierNot: [IdentifierParam] = [],
        startDate: [DateParam] = [],
        targetDate: [DateParam] = [],
        subject: String? = nil,
        patient: String? = nil,
        id: [String] = [],
        lastUpdated: [DateParam] = [],
        tokenTexts: [TokenTextParam] = [],
        missing: [String: Bool] = [:],
        chains: [ChainedParam] = [],
        has: [HasParam] = [],
        totalMode: TotalMode = .accurate,
        count: Int = 20,
        sortKeys: [SortKey] = [.default],
        cursor: SearchCursor? = nil
    ) {
        self.lifecycleStatus    = lifecycleStatus
        self.lifecycleStatusNot = lifecycleStatusNot
        self.achievementStatus    = achievementStatus
        self.achievementStatusNot = achievementStatusNot
        self.category             = category
        self.categoryNot        = categoryNot
        self.identifier         = identifier
        self.identifierNot      = identifierNot
        self.startDate          = startDate
        self.targetDate         = targetDate
        self.subject            = subject
        self.patient            = patient
        self.id                 = id
        self.lastUpdated        = lastUpdated
        self.tokenTexts         = tokenTexts
        self.missing            = missing
        self.chains             = chains
        self.has                = has
        self.totalMode          = totalMode
        self.count              = count
        self.sortKeys       = sortKeys
        self.cursor             = cursor
    }

    // ── Sort order ────────────────────────────────────────────────────────────

    /// Parses a comma-separated `_sort` value into sort keys.
    /// Unrecognised tokens are ignored; empty result falls back to `[.default]`.
    public static func parseSortKeys(_ raw: String) -> [SortKey] {
        let keys = raw.split(separator: ",").compactMap { token -> SortKey? in
            let s = String(token).trimmingCharacters(in: .whitespaces)
            let desc = s.hasPrefix("-")
            let name = desc ? String(s.dropFirst()) : s
            let src: SortKeySource? = switch name {
            case "_lastUpdated":    .lastUpdated
            case "_id":             .resourceId
            case "start-date":  .date(paramName: "start-date")
            case "lifecycle-status":  .token(paramName: "lifecycle-status")
            default:                nil
            }
            guard let src else { return nil }
            return SortKey(source: src, descending: desc)
        }
        return keys.isEmpty ? [.default] : keys
    }

    public typealias TokenParam      = ObservationSearchQuery.TokenParam
    public typealias DateParam       = PatientSearchQuery.BirthdateParam
    public typealias IdentifierParam = PatientSearchQuery.IdentifierParam
    public typealias TotalMode       = PatientSearchQuery.TotalMode
}
