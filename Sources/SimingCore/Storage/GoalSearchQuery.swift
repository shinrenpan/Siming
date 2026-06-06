import Foundation

public struct GoalSearchQuery: Sendable {

    // ── Filters ───────────────────────────────────────────────────────────────

    // token params
    public var lifecycleStatus: [TokenParam]
    public var lifecycleStatusNot: [TokenParam]
    public var achievementStatus: [TokenParam]
    public var category: [TokenParam]
    public var categoryNot: [TokenParam]
    public var identifier: [IdentifierParam]

    // date params
    public var startDate: [DateParam]
    public var targetDate: [DateParam]

    // reference params
    public var subject: String?
    public var patient: String?

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
        lifecycleStatus: [TokenParam] = [],
        lifecycleStatusNot: [TokenParam] = [],
        achievementStatus: [TokenParam] = [],
        category: [TokenParam] = [],
        categoryNot: [TokenParam] = [],
        identifier: [IdentifierParam] = [],
        startDate: [DateParam] = [],
        targetDate: [DateParam] = [],
        subject: String? = nil,
        patient: String? = nil,
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
        self.lifecycleStatus    = lifecycleStatus
        self.lifecycleStatusNot = lifecycleStatusNot
        self.achievementStatus  = achievementStatus
        self.category           = category
        self.categoryNot        = categoryNot
        self.identifier         = identifier
        self.startDate          = startDate
        self.targetDate         = targetDate
        self.subject            = subject
        self.patient            = patient
        self.id                 = id
        self.lastUpdated        = lastUpdated
        self.missing            = missing
        self.chains             = chains
        self.has                = has
        self.totalMode          = totalMode
        self.count              = count
        self.sort               = sort
        self.cursor             = cursor
    }

    public typealias TokenParam      = ObservationSearchQuery.TokenParam
    public typealias DateParam       = PatientSearchQuery.BirthdateParam
    public typealias SortOrder       = PatientSearchQuery.SortOrder
    public typealias SearchCursor    = PatientSearchQuery.SearchCursor
    public typealias IdentifierParam = PatientSearchQuery.IdentifierParam
    public typealias TotalMode       = PatientSearchQuery.TotalMode
}
