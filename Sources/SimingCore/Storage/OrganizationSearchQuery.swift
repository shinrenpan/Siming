import Foundation

public struct OrganizationSearchQuery: Sendable {

    // ── Filters ───────────────────────────────────────────────────────────────

    public var name: StringParam?
    public var identifier: [IdentifierParam]
    public var active: Bool?
    public var type: [TokenParam]
    public var typeNot: [TokenParam]
    public var address: StringParam?
    public var addressCity: StringParam?
    public var addressState: StringParam?
    public var addressPostalCode: StringParam?
    public var addressCountry: StringParam?
    public var partof: String?
    public var id: [String]
    public var lastUpdated: [DateParam]
    public var missing: [String: Bool]
    public var chains: [ChainedParam]
    public var has: [HasParam]

    // ── Pagination / sort ─────────────────────────────────────────────────────

    public var totalMode: TotalMode
    public var count: Int
    public var sort: SortOrder
    public var cursor: SearchCursor?

    public init(
        name: StringParam? = nil,
        identifier: [IdentifierParam] = [],
        active: Bool? = nil,
        type: [TokenParam] = [],
        typeNot: [TokenParam] = [],
        address: StringParam? = nil,
        addressCity: StringParam? = nil,
        addressState: StringParam? = nil,
        addressPostalCode: StringParam? = nil,
        addressCountry: StringParam? = nil,
        partof: String? = nil,
        id: [String] = [],
        lastUpdated: [DateParam] = [],
        missing: [String: Bool] = [:],
        chains: [ChainedParam] = [],
        has: [HasParam] = [],
        totalMode: TotalMode = .accurate,
        count: Int = 20,
        sort: SortOrder = .lastUpdatedDescending,
        cursor: SearchCursor? = nil
    ) {
        self.name              = name
        self.identifier        = identifier
        self.active            = active
        self.type              = type
        self.typeNot           = typeNot
        self.address           = address
        self.addressCity       = addressCity
        self.addressState      = addressState
        self.addressPostalCode = addressPostalCode
        self.addressCountry    = addressCountry
        self.partof            = partof
        self.id                = id
        self.lastUpdated       = lastUpdated
        self.missing           = missing
        self.chains            = chains
        self.has               = has
        self.totalMode         = totalMode
        self.count             = count
        self.sort              = sort
        self.cursor            = cursor
    }

    public typealias TokenParam      = ObservationSearchQuery.TokenParam
    public typealias StringParam     = PatientSearchQuery.StringParam
    public typealias DateParam       = PatientSearchQuery.BirthdateParam
    public typealias SortOrder       = PatientSearchQuery.SortOrder
    public typealias SearchCursor    = PatientSearchQuery.SearchCursor
    public typealias IdentifierParam = PatientSearchQuery.IdentifierParam
    public typealias TotalMode       = PatientSearchQuery.TotalMode
}
