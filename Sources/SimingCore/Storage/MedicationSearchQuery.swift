import Foundation

public struct MedicationSearchQuery: Sendable {

    // ── Filters ───────────────────────────────────────────────────────────────

    public var code: [TokenParam]
    public var codeNot: [TokenParam]
    public var status: [TokenParam]
    public var statusNot: [TokenParam]
    public var form: [TokenParam]
    public var identifier: [IdentifierParam]
    public var identifierNot: [IdentifierParam]  // identifier:not modifier
    public var ingredientCode: [TokenParam]
    public var lotNumber: [TokenParam]
    public var manufacturer: String?
    public var ingredient: String?
    public var expirationDate: [DateParam]
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
        code: [TokenParam] = [],
        codeNot: [TokenParam] = [],
        status: [TokenParam] = [],
        statusNot: [TokenParam] = [],
        form: [TokenParam] = [],
        identifier: [IdentifierParam] = [],
        identifierNot: [IdentifierParam] = [],
        ingredientCode: [TokenParam] = [],
        lotNumber: [TokenParam] = [],
        manufacturer: String? = nil,
        ingredient: String? = nil,
        expirationDate: [DateParam] = [],
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
        self.code           = code
        self.codeNot        = codeNot
        self.status         = status
        self.statusNot      = statusNot
        self.form           = form
        self.identifier     = identifier
        self.identifierNot  = identifierNot
        self.ingredientCode = ingredientCode
        self.lotNumber      = lotNumber
        self.manufacturer   = manufacturer
        self.ingredient     = ingredient
        self.expirationDate = expirationDate
        self.id             = id
        self.lastUpdated    = lastUpdated
        self.missing        = missing
        self.chains         = chains
        self.has            = has
        self.totalMode      = totalMode
        self.count          = count
        self.sort           = sort
        self.cursor         = cursor
    }

    public typealias TokenParam      = ObservationSearchQuery.TokenParam
    public typealias StringParam     = PatientSearchQuery.StringParam
    public typealias DateParam       = PatientSearchQuery.BirthdateParam
    public typealias SortOrder       = PatientSearchQuery.SortOrder
    public typealias SearchCursor    = PatientSearchQuery.SearchCursor
    public typealias IdentifierParam = PatientSearchQuery.IdentifierParam
    public typealias TotalMode       = PatientSearchQuery.TotalMode
}
