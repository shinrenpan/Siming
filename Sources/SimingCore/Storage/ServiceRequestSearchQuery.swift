import Foundation

public struct ServiceRequestSearchQuery: Sendable {

    // ── Filters ───────────────────────────────────────────────────────────────

    // token params
    public var status: [TokenParam]
    public var statusNot: [TokenParam]
    public var intent: [TokenParam]
    public var intentNot: [TokenParam]
    public var priority: [TokenParam]
    public var priorityNot: [TokenParam]
    public var code: [TokenParam]
    public var codeNot: [TokenParam]
    public var category: [TokenParam]
    public var categoryNot: [TokenParam]
    public var bodySite: [TokenParam]
    public var identifier: [IdentifierParam]
    public var performerType: [TokenParam]
    public var requisition: [TokenParam]

    // string params
    public var orderDetail: StringParam?  // free-text search on orderDetail

    // date params
    public var authored: [DateParam]
    public var occurrence: [DateParam]

    // reference params
    public var subject: String?
    public var patient: String?
    public var encounter: String?
    public var requester: String?
    public var performer: String?
    public var basedOn: String?
    public var replaces: String?
    public var specimen: String?

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
        intent: [TokenParam] = [],
        intentNot: [TokenParam] = [],
        priority: [TokenParam] = [],
        priorityNot: [TokenParam] = [],
        code: [TokenParam] = [],
        codeNot: [TokenParam] = [],
        category: [TokenParam] = [],
        categoryNot: [TokenParam] = [],
        bodySite: [TokenParam] = [],
        identifier: [IdentifierParam] = [],
        performerType: [TokenParam] = [],
        requisition: [TokenParam] = [],
        orderDetail: StringParam? = nil,
        authored: [DateParam] = [],
        occurrence: [DateParam] = [],
        subject: String? = nil,
        patient: String? = nil,
        encounter: String? = nil,
        requester: String? = nil,
        performer: String? = nil,
        basedOn: String? = nil,
        replaces: String? = nil,
        specimen: String? = nil,
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
        self.status         = status
        self.statusNot      = statusNot
        self.intent         = intent
        self.intentNot      = intentNot
        self.priority       = priority
        self.priorityNot    = priorityNot
        self.code           = code
        self.codeNot        = codeNot
        self.category       = category
        self.categoryNot    = categoryNot
        self.bodySite       = bodySite
        self.identifier     = identifier
        self.performerType  = performerType
        self.requisition    = requisition
        self.orderDetail    = orderDetail
        self.authored       = authored
        self.occurrence     = occurrence
        self.subject        = subject
        self.patient        = patient
        self.encounter      = encounter
        self.requester      = requester
        self.performer      = performer
        self.basedOn        = basedOn
        self.replaces       = replaces
        self.specimen       = specimen
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
