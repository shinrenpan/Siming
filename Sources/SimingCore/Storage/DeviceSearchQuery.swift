import Foundation

public struct DeviceSearchQuery: Sendable {

    // ── Filters ───────────────────────────────────────────────────────────────

    // token params
    public var status: [TokenParam]
    public var statusNot: [TokenParam]
    public var type: [TokenParam]
    public var typeNot: [TokenParam]
    public var identifier: [IdentifierParam]
    public var identifierNot: [IdentifierParam]  // identifier:not modifier

    // string params
    public var deviceName: StringParam?
    public var manufacturer: StringParam?
    public var model: StringParam?
    public var udiCarrier: StringParam?
    public var udiDi: StringParam?

    // uri params
    public var url: [String]                    // Device.url (exact URL match)

    // reference params
    public var patient: String?
    public var organization: String?
    public var location: String?

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
        identifier: [IdentifierParam] = [],
        identifierNot: [IdentifierParam] = [],
        deviceName: StringParam? = nil,
        manufacturer: StringParam? = nil,
        model: StringParam? = nil,
        udiCarrier: StringParam? = nil,
        udiDi: StringParam? = nil,
        url: [String] = [],
        patient: String? = nil,
        organization: String? = nil,
        location: String? = nil,
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
        self.type          = type
        self.typeNot       = typeNot
        self.identifier    = identifier
        self.identifierNot = identifierNot
        self.deviceName    = deviceName
        self.manufacturer  = manufacturer
        self.model         = model
        self.udiCarrier    = udiCarrier
        self.udiDi         = udiDi
        self.url           = url
        self.patient       = patient
        self.organization  = organization
        self.location      = location
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
            case "status":          .token(paramName: "status")
            case "device-name":     .string(paramName: "device-name")
            case "manufacturer":    .string(paramName: "manufacturer")
            case "model":           .string(paramName: "model")
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
