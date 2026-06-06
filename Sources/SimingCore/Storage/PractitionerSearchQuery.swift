import Foundation

public struct PractitionerSearchQuery: Sendable {

    // ── Filters ───────────────────────────────────────────────────────────────

    public var name: StringParam?
    public var family: StringParam?
    public var given: StringParam?
    public var identifier: [IdentifierParam]
    public var active: Bool?
    public var gender: [String]
    public var genderNot: [String]
    public var address: StringParam?
    public var addressCity: StringParam?
    public var addressState: StringParam?
    public var addressPostalCode: StringParam?
    public var addressCountry: StringParam?
    public var phone: String?
    public var email: String?
    public var communication: [TokenParam]
    public var communicationNot: [TokenParam]
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
        family: StringParam? = nil,
        given: StringParam? = nil,
        identifier: [IdentifierParam] = [],
        active: Bool? = nil,
        gender: [String] = [],
        genderNot: [String] = [],
        address: StringParam? = nil,
        addressCity: StringParam? = nil,
        addressState: StringParam? = nil,
        addressPostalCode: StringParam? = nil,
        addressCountry: StringParam? = nil,
        phone: String? = nil,
        email: String? = nil,
        communication: [TokenParam] = [],
        communicationNot: [TokenParam] = [],
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
        self.family            = family
        self.given             = given
        self.identifier        = identifier
        self.active            = active
        self.gender            = gender
        self.genderNot         = genderNot
        self.address           = address
        self.addressCity       = addressCity
        self.addressState      = addressState
        self.addressPostalCode = addressPostalCode
        self.addressCountry    = addressCountry
        self.phone             = phone
        self.email             = email
        self.communication     = communication
        self.communicationNot  = communicationNot
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
