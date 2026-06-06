import Foundation

public struct ImmunizationSearchQuery: Sendable {

    // ── Filters ───────────────────────────────────────────────────────────────

    public var subject: String?                     // patient reference
    public var status: [TokenParam]                 // token OR
    public var statusNot: [TokenParam]              // status:not modifier
    public var vaccineCode: [TokenParam]            // vaccine-code token OR
    public var vaccineCodeNot: [TokenParam]         // vaccine-code:not modifier
    public var identifier: [IdentifierParam]
    public var performer: String?                   // performer reference
    public var lotNumber: String?                   // lot-number string search
    public var date: [DateParam]                    // occurrence date range
    public var id: [String]                         // _id filter (OR)
    public var lastUpdated: [DateParam]             // _lastUpdated range filter
    public var missing: [String: Bool]              // param:missing=true/false
    public var chains: [ChainedParam]               // chained search
    public var has: [HasParam]                      // _has reverse chaining

    // ── Pagination / sort ─────────────────────────────────────────────────────

    public var totalMode: TotalMode
    public var count: Int
    public var sort: SortOrder
    public var cursor: SearchCursor?

    public init(
        subject: String? = nil,
        status: [TokenParam] = [],
        statusNot: [TokenParam] = [],
        vaccineCode: [TokenParam] = [],
        vaccineCodeNot: [TokenParam] = [],
        identifier: [IdentifierParam] = [],
        performer: String? = nil,
        lotNumber: String? = nil,
        date: [DateParam] = [],
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
        self.subject       = subject
        self.status        = status
        self.statusNot     = statusNot
        self.vaccineCode   = vaccineCode
        self.vaccineCodeNot = vaccineCodeNot
        self.identifier    = identifier
        self.performer     = performer
        self.lotNumber     = lotNumber
        self.date          = date
        self.id            = id
        self.lastUpdated   = lastUpdated
        self.missing       = missing
        self.chains        = chains
        self.has           = has
        self.totalMode     = totalMode
        self.count         = count
        self.sort          = sort
        self.cursor        = cursor
    }

    public typealias TokenParam      = ObservationSearchQuery.TokenParam
    public typealias DateParam       = PatientSearchQuery.BirthdateParam
    public typealias SortOrder       = PatientSearchQuery.SortOrder
    public typealias SearchCursor    = PatientSearchQuery.SearchCursor
    public typealias IdentifierParam = PatientSearchQuery.IdentifierParam
    public typealias TotalMode       = PatientSearchQuery.TotalMode
}
