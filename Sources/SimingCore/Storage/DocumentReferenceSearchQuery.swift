import Foundation

public struct DocumentReferenceSearchQuery: Sendable {

    // ── Filters ───────────────────────────────────────────────────────────────

    // token params
    public var status: [TokenParam]
    public var statusNot: [TokenParam]
    public var type: [TokenParam]
    public var typeNot: [TokenParam]
    public var category: [TokenParam]
    public var categoryNot: [TokenParam]
    public var identifier: [IdentifierParam]
    public var securityLabel: [TokenParam]
    public var securityLabelNot: [TokenParam]
    public var facility: [TokenParam]
    public var event: [TokenParam]

    // date params
    public var date: [DateParam]
    public var period: [DateParam]

    // string params
    public var description: [String]

    // reference params
    public var subject: String?
    public var patient: String?
    public var author: String?
    public var encounter: String?

    // system params
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
        status: [TokenParam] = [],
        statusNot: [TokenParam] = [],
        type: [TokenParam] = [],
        typeNot: [TokenParam] = [],
        category: [TokenParam] = [],
        categoryNot: [TokenParam] = [],
        identifier: [IdentifierParam] = [],
        securityLabel: [TokenParam] = [],
        securityLabelNot: [TokenParam] = [],
        facility: [TokenParam] = [],
        event: [TokenParam] = [],
        date: [DateParam] = [],
        period: [DateParam] = [],
        description: [String] = [],
        subject: String? = nil,
        patient: String? = nil,
        author: String? = nil,
        encounter: String? = nil,
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
        self.status           = status
        self.statusNot        = statusNot
        self.type             = type
        self.typeNot          = typeNot
        self.category         = category
        self.categoryNot      = categoryNot
        self.identifier       = identifier
        self.securityLabel    = securityLabel
        self.securityLabelNot = securityLabelNot
        self.facility         = facility
        self.event            = event
        self.date             = date
        self.period           = period
        self.description      = description
        self.subject          = subject
        self.patient          = patient
        self.author           = author
        self.encounter        = encounter
        self.id               = id
        self.lastUpdated      = lastUpdated
        self.missing          = missing
        self.chains           = chains
        self.has              = has
        self.totalMode        = totalMode
        self.count            = count
        self.sort             = sort
        self.cursor           = cursor
    }

    public typealias TokenParam      = ObservationSearchQuery.TokenParam
    public typealias DateParam       = PatientSearchQuery.BirthdateParam
    public typealias SortOrder       = PatientSearchQuery.SortOrder
    public typealias SearchCursor    = PatientSearchQuery.SearchCursor
    public typealias IdentifierParam = PatientSearchQuery.IdentifierParam
    public typealias TotalMode       = PatientSearchQuery.TotalMode
}
