import Foundation

public struct RelatedPersonSearchQuery: Sendable {

    // ── Filters ───────────────────────────────────────────────────────────────

    // token params
    public var active: [TokenParam]
    public var activeNot: [TokenParam]
    public var gender: [TokenParam]
    public var genderNot: [TokenParam]
    public var identifier: [IdentifierParam]
    public var identifierNot: [IdentifierParam]  // identifier:not modifier
    public var relationship: [TokenParam]
    public var relationshipNot: [TokenParam]
    public var phone: [TokenParam]
    public var email: [TokenParam]
    public var telecom: [TokenParam]
    public var addressUse: [TokenParam]

    // string params (single optional, supports modifiers via StringParam.parse)
    public var name: StringParam?
    public var address: StringParam?
    public var addressCity: StringParam?
    public var addressCountry: StringParam?
    public var addressPostalcode: StringParam?
    public var addressState: StringParam?

    // date params
    public var birthdate: [DateParam]

    // reference params
    public var patient: String?

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
    public var sort: SortOrder
    public var cursor: SearchCursor?

    public init(
        active: [TokenParam] = [],
        activeNot: [TokenParam] = [],
        gender: [TokenParam] = [],
        genderNot: [TokenParam] = [],
        identifier: [IdentifierParam] = [],
        identifierNot: [IdentifierParam] = [],
        relationship: [TokenParam] = [],
        relationshipNot: [TokenParam] = [],
        phone: [TokenParam] = [],
        email: [TokenParam] = [],
        telecom: [TokenParam] = [],
        addressUse: [TokenParam] = [],
        name: StringParam? = nil,
        address: StringParam? = nil,
        addressCity: StringParam? = nil,
        addressCountry: StringParam? = nil,
        addressPostalcode: StringParam? = nil,
        addressState: StringParam? = nil,
        birthdate: [DateParam] = [],
        patient: String? = nil,
        id: [String] = [],
        lastUpdated: [DateParam] = [],
        missing: [String: Bool] = [:],
        chains: [ChainedParam] = [],
        has: [HasParam] = [],
        meta: MetaSearchParams = MetaSearchParams(),
        totalMode: TotalMode = .accurate,
        count: Int = 20,
        sort: SortOrder = .lastUpdatedDescending,
        cursor: SearchCursor? = nil
    ) {
        self.active             = active
        self.activeNot          = activeNot
        self.gender             = gender
        self.genderNot          = genderNot
        self.identifier         = identifier
        self.identifierNot      = identifierNot
        self.relationship       = relationship
        self.relationshipNot    = relationshipNot
        self.phone              = phone
        self.email              = email
        self.telecom            = telecom
        self.addressUse         = addressUse
        self.name               = name
        self.address            = address
        self.addressCity        = addressCity
        self.addressCountry     = addressCountry
        self.addressPostalcode  = addressPostalcode
        self.addressState       = addressState
        self.birthdate          = birthdate
        self.patient            = patient
        self.id                 = id
        self.lastUpdated        = lastUpdated
        self.missing            = missing
        self.chains             = chains
        self.has                = has
        self.meta               = meta
        self.totalMode          = totalMode
        self.count              = count
        self.sort               = sort
        self.cursor             = cursor
    }

    public typealias TokenParam      = ObservationSearchQuery.TokenParam
    public typealias StringParam     = PatientSearchQuery.StringParam
    public typealias DateParam       = PatientSearchQuery.BirthdateParam
    public typealias SortOrder       = PatientSearchQuery.SortOrder
    public typealias SearchCursor    = PatientSearchQuery.SearchCursor
    public typealias IdentifierParam = PatientSearchQuery.IdentifierParam
    public typealias TotalMode       = PatientSearchQuery.TotalMode
}
