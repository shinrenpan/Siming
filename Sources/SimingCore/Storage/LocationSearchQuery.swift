import Foundation

public struct LocationSearchQuery: Sendable {

    // ── Filters ───────────────────────────────────────────────────────────────

    public var name: StringParam?
    public var identifier: [IdentifierParam]
    public var identifierNot: [IdentifierParam]  // identifier:not modifier
    public var status: [TokenParam]
    public var endpoint: String?
    public var statusNot: [TokenParam]
    public var type: [TokenParam]
    public var typeNot: [TokenParam]
    public var operationalStatus: [TokenParam]
    public var operationalStatusNot: [TokenParam]  // operational-status:not modifier
    public var address: StringParam?
    public var addressCity: StringParam?
    public var addressState: StringParam?
    public var addressPostalCode: StringParam?
    public var addressCountry: StringParam?
    public var organization: String?
    public var partof: String?
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
        name: StringParam? = nil,
        identifier: [IdentifierParam] = [],
        identifierNot: [IdentifierParam] = [],
        status: [TokenParam] = [],
        statusNot: [TokenParam] = [],
        type: [TokenParam] = [],
        typeNot: [TokenParam] = [],
        operationalStatus: [TokenParam] = [],
        operationalStatusNot: [TokenParam] = [],
        address: StringParam? = nil,
        addressCity: StringParam? = nil,
        addressState: StringParam? = nil,
        addressPostalCode: StringParam? = nil,
        addressCountry: StringParam? = nil,
        organization: String? = nil,
        partof: String? = nil,
        endpoint: String? = nil,
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
        self.name              = name
        self.identifier        = identifier
        self.identifierNot     = identifierNot
        self.status            = status
        self.endpoint          = endpoint
        self.statusNot         = statusNot
        self.type              = type
        self.typeNot           = typeNot
        self.operationalStatus    = operationalStatus
        self.operationalStatusNot = operationalStatusNot
        self.address              = address
        self.addressCity       = addressCity
        self.addressState      = addressState
        self.addressPostalCode = addressPostalCode
        self.addressCountry    = addressCountry
        self.organization      = organization
        self.partof            = partof
        self.id                = id
        self.lastUpdated       = lastUpdated
        self.tokenTexts        = tokenTexts
        self.missing           = missing
        self.chains            = chains
        self.has               = has
        self.meta              = meta
        self.totalMode         = totalMode
        self.count             = count
        self.sortKeys       = sortKeys
        self.cursor            = cursor
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
            case "name":  .string(paramName: "name")
            case "status":  .token(paramName: "status")
            default:                nil
            }
            guard let src else { return nil }
            return SortKey(source: src, descending: desc)
        }
        return keys.isEmpty ? [.default] : keys
    }

    public typealias TokenParam      = ObservationSearchQuery.TokenParam
    public typealias StringParam     = PatientSearchQuery.StringParam
    public typealias DateParam       = PatientSearchQuery.BirthdateParam
    public typealias IdentifierParam = PatientSearchQuery.IdentifierParam
    public typealias TotalMode       = PatientSearchQuery.TotalMode
}
