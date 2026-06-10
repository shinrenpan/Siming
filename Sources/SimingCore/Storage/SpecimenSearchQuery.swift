import Foundation

public struct SpecimenSearchQuery: Sendable {

    // ── Filters ───────────────────────────────────────────────────────────────

    // token params
    public var status: [TokenParam]
    public var statusNot: [TokenParam]
    public var type: [TokenParam]
    public var typeNot: [TokenParam]
    public var accession: [TokenParam]
    public var accessionNot: [TokenParam]
    public var identifier: [IdentifierParam]
    public var identifierNot: [IdentifierParam]  // identifier:not modifier
    public var bodysite: [TokenParam]
    public var bodysiteNot: [TokenParam]
    public var container: [TokenParam]
    public var containerNot: [TokenParam]
    public var containerId: [TokenParam]
    public var containerIdNot: [TokenParam]

    // date params
    public var collected: [DateParam]

    // reference params
    public var subject: String?
    public var patient: String?
    public var collector: String?
    public var parent: String?

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
        type: [TokenParam] = [],
        typeNot: [TokenParam] = [],
        accession: [TokenParam] = [],
        accessionNot: [TokenParam] = [],
        identifier: [IdentifierParam] = [],
        identifierNot: [IdentifierParam] = [],
        bodysite: [TokenParam] = [],
        bodysiteNot: [TokenParam] = [],
        container: [TokenParam] = [],
        containerNot: [TokenParam] = [],
        containerId: [TokenParam] = [],
        containerIdNot: [TokenParam] = [],
        collected: [DateParam] = [],
        subject: String? = nil,
        patient: String? = nil,
        collector: String? = nil,
        parent: String? = nil,
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
        self.status         = status
        self.statusNot      = statusNot
        self.type           = type
        self.typeNot        = typeNot
        self.accession      = accession
        self.accessionNot   = accessionNot
        self.identifier     = identifier
        self.identifierNot  = identifierNot
        self.bodysite       = bodysite
        self.bodysiteNot    = bodysiteNot
        self.container      = container
        self.containerNot   = containerNot
        self.containerId    = containerId
        self.containerIdNot = containerIdNot
        self.collected      = collected
        self.subject        = subject
        self.patient        = patient
        self.collector      = collector
        self.parent         = parent
        self.id             = id
        self.lastUpdated    = lastUpdated
        self.tokenTexts     = tokenTexts
        self.missing        = missing
        self.chains         = chains
        self.has            = has
        self.meta           = meta
        self.totalMode      = totalMode
        self.count          = count
        self.sortKeys       = sortKeys
        self.cursor         = cursor
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
            case "collected":  .date(paramName: "collected")
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
