import Foundation

public struct CarePlanSearchQuery: Sendable {

    // ── Filters ───────────────────────────────────────────────────────────────

    // token params
    public var status: [TokenParam]
    public var statusNot: [TokenParam]
    public var intent: [TokenParam]
    public var intentNot: [TokenParam]
    public var category: [TokenParam]
    public var categoryNot: [TokenParam]
    public var identifier: [IdentifierParam]
    public var identifierNot: [IdentifierParam]  // identifier:not modifier
    public var activityCode: [TokenParam]
    public var activityCodeNot: [TokenParam]  // activity-code:not modifier

    // date params
    public var date: [DateParam]
    public var activityDate: [DateParam]
    public var activityDateNot: [DateParam]

    // string params
    public var instantiatesCanonical: [String]
    public var instantiatesUri: [String]

    // reference params
    public var subject: String?
    public var patient: String?
    public var encounter: String?
    public var careTeam: String?
    public var condition: String?
    public var goal: String?
    public var basedOn: String?
    public var partOf: String?
    public var replaces: String?
    public var performer: String?
    public var activityReference: String?

    // system params
    public var id: [String]
    public var meta: MetaSearchParams = MetaSearchParams()  // _tag / _security / _profile
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
        category: [TokenParam] = [],
        categoryNot: [TokenParam] = [],
        identifier: [IdentifierParam] = [],
        identifierNot: [IdentifierParam] = [],
        activityCode: [TokenParam] = [],
        activityCodeNot: [TokenParam] = [],
        date: [DateParam] = [],
        activityDate: [DateParam] = [],
        activityDateNot: [DateParam] = [],
        instantiatesCanonical: [String] = [],
        instantiatesUri: [String] = [],
        subject: String? = nil,
        patient: String? = nil,
        encounter: String? = nil,
        careTeam: String? = nil,
        condition: String? = nil,
        goal: String? = nil,
        basedOn: String? = nil,
        partOf: String? = nil,
        replaces: String? = nil,
        performer: String? = nil,
        activityReference: String? = nil,
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
        self.status            = status
        self.statusNot         = statusNot
        self.intent            = intent
        self.intentNot         = intentNot
        self.category          = category
        self.categoryNot       = categoryNot
        self.identifier        = identifier
        self.identifierNot     = identifierNot
        self.activityCode           = activityCode
        self.activityCodeNot        = activityCodeNot
        self.date                   = date
        self.activityDate           = activityDate
        self.activityDateNot        = activityDateNot
        self.instantiatesCanonical  = instantiatesCanonical
        self.instantiatesUri        = instantiatesUri
        self.subject                = subject
        self.patient           = patient
        self.encounter         = encounter
        self.careTeam          = careTeam
        self.condition         = condition
        self.goal              = goal
        self.basedOn           = basedOn
        self.partOf            = partOf
        self.replaces          = replaces
        self.performer         = performer
        self.activityReference = activityReference
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
    public typealias DateParam       = PatientSearchQuery.BirthdateParam
    public typealias SortOrder       = PatientSearchQuery.SortOrder
    public typealias SearchCursor    = PatientSearchQuery.SearchCursor
    public typealias IdentifierParam = PatientSearchQuery.IdentifierParam
    public typealias TotalMode       = PatientSearchQuery.TotalMode
}
