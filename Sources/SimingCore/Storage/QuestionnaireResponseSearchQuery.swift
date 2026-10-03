import Foundation

public struct QuestionnaireResponseSearchQuery: Sendable {

    // ── Filters ───────────────────────────────────────────────────────────────

    // token params
    public var status: [TokenParam]
    public var statusNot: [TokenParam]
    public var identifier: [IdentifierParam]
    public var identifierNot: [IdentifierParam]  // identifier:not modifier

    // canonical (idx_string exact match)
    public var questionnaire: [String]

    // date params
    public var authored: [DateParam]

    // reference params
    public var subject: String?
    public var patient: String?
    public var author: String?
    public var encounter: String?
    public var source: String?
    public var basedOn: String?
    public var partOf: String?
    public var itemSubject: String?

    // system params
    public var id: [String]
    public var lastUpdated: [DateParam]
    public var tokenTexts: [TokenTextParam]
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
        status: [TokenParam] = [],
        statusNot: [TokenParam] = [],
        identifier: [IdentifierParam] = [],
        identifierNot: [IdentifierParam] = [],
        questionnaire: [String] = [],
        authored: [DateParam] = [],
        subject: String? = nil,
        patient: String? = nil,
        author: String? = nil,
        encounter: String? = nil,
        source: String? = nil,
        basedOn: String? = nil,
        partOf: String? = nil,
        itemSubject: String? = nil,
        id: [String] = [],
        lastUpdated: [DateParam] = [],
        tokenTexts: [TokenTextParam] = [],
        missing: [String: Bool] = [:],
        chains: [ChainedParam] = [],
        has: [HasParam] = [],
        meta: MetaSearchParams = MetaSearchParams(),
        totalMode: TotalMode = .accurate,
        count: Int = 20,
        sortKeys: [SortKey] = [.default],
        cursor: SearchCursor? = nil
    ) {
        self.status        = status
        self.statusNot     = statusNot
        self.identifier    = identifier
        self.identifierNot = identifierNot
        self.questionnaire = questionnaire
        self.authored      = authored
        self.subject       = subject
        self.patient       = patient
        self.author        = author
        self.encounter     = encounter
        self.source        = source
        self.basedOn       = basedOn
        self.partOf        = partOf
        self.itemSubject   = itemSubject
        self.id            = id
        self.lastUpdated   = lastUpdated
        self.tokenTexts    = tokenTexts
        self.missing       = missing
        self.chains        = chains
        self.has           = has
        self.meta          = meta
        self.totalMode     = totalMode
        self.count         = count
        self.sortKeys      = sortKeys
        self.cursor        = cursor
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
            case "authored":        .date(paramName: "authored")
            case "status":          .token(paramName: "status")
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
