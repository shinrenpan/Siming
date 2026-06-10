import Foundation

public struct FamilyMemberHistorySearchQuery: Sendable {

    // ── Filters ───────────────────────────────────────────────────────────────

    public var patient: String?                      // patient reference (REQUIRED field)
    public var status: [TokenParam]                  // token OR: "partial,completed,..."
    public var statusNot: [TokenParam]               // status:not modifier
    public var relationship: [TokenParam]            // CodeableConcept token OR
    public var relationshipNot: [TokenParam]         // relationship:not modifier
    public var sex: [TokenParam]                     // CodeableConcept token OR
    public var sexNot: [TokenParam]                  // sex:not modifier
    public var code: [TokenParam]                    // condition[].code token OR
    public var codeNot: [TokenParam]                 // code:not modifier
    public var identifier: [IdentifierParam]
    public var identifierNot: [IdentifierParam]  // identifier:not modifier
    public var date: [DateParam]                     // date range filter
    public var instantiatesCanonical: [String]       // instantiates-canonical (canonical URL)
    public var instantiatesUri: [String]             // instantiates-uri (URI)
    public var id: [String]                          // _id filter (OR)
    public var lastUpdated: [DateParam]              // _lastUpdated range filter
    public var tokenTexts: [TokenTextParam]          // param:text=value modifier
    public var missing: [String: Bool]               // param:missing=true/false
    public var chains: [ChainedParam]                // chained search
    public var has: [HasParam]                       // _has modifier: reverse chaining
    public var meta: MetaSearchParams                // _tag / _security / _profile

    // ── Pagination / sort ─────────────────────────────────────────────────────

    public var totalMode: TotalMode
    public var count: Int
    public var sortKeys: [SortKey]
    public var cursor: SearchCursor?

    public init(
        patient: String? = nil,
        status: [TokenParam] = [],
        statusNot: [TokenParam] = [],
        relationship: [TokenParam] = [],
        relationshipNot: [TokenParam] = [],
        sex: [TokenParam] = [],
        sexNot: [TokenParam] = [],
        code: [TokenParam] = [],
        codeNot: [TokenParam] = [],
        identifier: [IdentifierParam] = [],
        identifierNot: [IdentifierParam] = [],
        date: [DateParam] = [],
        instantiatesCanonical: [String] = [],
        instantiatesUri: [String] = [],
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
        self.patient         = patient
        self.status          = status
        self.statusNot       = statusNot
        self.relationship    = relationship
        self.relationshipNot = relationshipNot
        self.sex             = sex
        self.sexNot          = sexNot
        self.code            = code
        self.codeNot         = codeNot
        self.identifier             = identifier
        self.identifierNot          = identifierNot
        self.date                   = date
        self.instantiatesCanonical  = instantiatesCanonical
        self.instantiatesUri        = instantiatesUri
        self.id                     = id
        self.lastUpdated     = lastUpdated
        self.tokenTexts      = tokenTexts
        self.missing         = missing
        self.chains          = chains
        self.has             = has
        self.meta            = meta
        self.totalMode       = totalMode
        self.count           = count
        self.sortKeys       = sortKeys
        self.cursor          = cursor
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
            case "date":  .date(paramName: "date")
            case "code":  .token(paramName: "code")
            case "status":  .token(paramName: "status")
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
