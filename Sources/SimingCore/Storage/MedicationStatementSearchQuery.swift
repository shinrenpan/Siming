import Foundation

public struct MedicationStatementSearchQuery: Sendable {

    // ── Filters ───────────────────────────────────────────────────────────────

    public var subject: String?                     // patient/subject reference
    public var patient: String?                     // patient reference (alias for subject)
    public var status: [TokenParam]                 // token OR: "active,completed,..."
    public var statusNot: [TokenParam]              // status:not modifier
    public var category: [TokenParam]               // CodeableConcept token OR
    public var categoryNot: [TokenParam]            // category:not modifier
    public var code: [TokenParam]                   // medication-as-CodeableConcept token OR
    public var codeNot: [TokenParam]                // code:not modifier
    public var identifier: [IdentifierParam]
    public var identifierNot: [IdentifierParam]  // identifier:not modifier
    public var effective: [DateParam]               // effective[x] range filter
    public var context: String?                     // reference: "Encounter/id"
    public var source: String?                      // reference: informationSource
    public var medication: String?                  // reference: medication-as-Reference
    public var partOf: String?                      // reference: partOf
    public var id: [String]                         // _id filter (OR)
    public var lastUpdated: [DateParam]             // _lastUpdated range filter
    public var tokenTexts: [TokenTextParam]         // param:text=value modifier
    public var missing: [String: Bool]              // param:missing=true/false
    public var chains: [ChainedParam]               // chained search
    public var has: [HasParam]                      // _has modifier: reverse chaining
    public var meta: MetaSearchParams               // _tag / _security / _profile

    // ── Pagination / sort ─────────────────────────────────────────────────────

    public var totalMode: TotalMode
    public var count: Int
    public var sortKeys: [SortKey]
    public var cursor: SearchCursor?

    public init(
        subject: String? = nil,
        patient: String? = nil,
        status: [TokenParam] = [],
        statusNot: [TokenParam] = [],
        category: [TokenParam] = [],
        categoryNot: [TokenParam] = [],
        code: [TokenParam] = [],
        codeNot: [TokenParam] = [],
        identifier: [IdentifierParam] = [],
        identifierNot: [IdentifierParam] = [],
        effective: [DateParam] = [],
        context: String? = nil,
        source: String? = nil,
        medication: String? = nil,
        partOf: String? = nil,
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
        self.subject      = subject
        self.patient      = patient
        self.status       = status
        self.statusNot    = statusNot
        self.category     = category
        self.categoryNot  = categoryNot
        self.code         = code
        self.codeNot      = codeNot
        self.identifier      = identifier
        self.identifierNot   = identifierNot
        self.effective    = effective
        self.context      = context
        self.source       = source
        self.medication   = medication
        self.partOf       = partOf
        self.id           = id
        self.lastUpdated  = lastUpdated
        self.tokenTexts   = tokenTexts
        self.missing      = missing
        self.chains       = chains
        self.has          = has
        self.meta         = meta
        self.totalMode    = totalMode
        self.count        = count
        self.sortKeys       = sortKeys
        self.cursor       = cursor
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
            case "effective":  .date(paramName: "effective")
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
