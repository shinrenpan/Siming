import Foundation

public struct EncounterSearchQuery: Sendable {

    // ── Filters ───────────────────────────────────────────────────────────────

    public var subject: String?              // patient/subject reference (compartment or direct search)
    public var status: [String]             // token OR: "planned,arrived,in-progress,finished,..."
    public var statusNot: [String]          // status:not modifier
    public var encounterClass: [TokenParam] // class token OR (Swift `class` is reserved — stored as "class")
    public var classNot: [TokenParam]       // class:not modifier
    public var type: [TokenParam]           // CodeableConcept token OR
    public var typeNot: [TokenParam]        // type:not modifier
    public var date: [DateParam]            // Encounter.period range filter (stored as param_name='date')
    public var identifier: [IdentifierParam]
    public var id: [String]                 // _id filter (OR)
    public var lastUpdated: [DateParam]     // _lastUpdated range filter
    public var missing: [String: Bool]      // param:missing=true/false
    public var chains: [ChainedParam]       // chained search: subject.name=Wang, etc.
    public var has: [HasParam]              // _has modifier: reverse chaining

    // ── Pagination / sort ─────────────────────────────────────────────────────

    public var totalMode: TotalMode
    public var count: Int
    public var sort: SortOrder
    public var cursor: SearchCursor?

    public init(
        subject: String? = nil,
        status: [String] = [],
        statusNot: [String] = [],
        encounterClass: [TokenParam] = [],
        classNot: [TokenParam] = [],
        type: [TokenParam] = [],
        typeNot: [TokenParam] = [],
        date: [DateParam] = [],
        identifier: [IdentifierParam] = [],
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
        self.subject        = subject
        self.status         = status
        self.statusNot      = statusNot
        self.encounterClass = encounterClass
        self.classNot       = classNot
        self.type           = type
        self.typeNot        = typeNot
        self.date           = date
        self.identifier     = identifier
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
    public typealias DateParam       = PatientSearchQuery.BirthdateParam
    public typealias SortOrder       = PatientSearchQuery.SortOrder
    public typealias SearchCursor    = PatientSearchQuery.SearchCursor
    public typealias IdentifierParam = PatientSearchQuery.IdentifierParam
    public typealias TotalMode       = PatientSearchQuery.TotalMode
}
