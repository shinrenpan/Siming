import Foundation

public struct ConditionSearchQuery: Sendable {

    // ── Filters ───────────────────────────────────────────────────────────────

    public var subject: String?                      // patient/subject reference
    public var encounter: String?                    // encounter reference
    public var clinicalStatus: [TokenParam]          // token OR: "active,recurrence,relapse,..."
    public var clinicalStatusNot: [TokenParam]       // clinical-status:not modifier
    public var verificationStatus: [TokenParam]      // token OR: "unconfirmed,confirmed,refuted,..."
    public var verificationStatusNot: [TokenParam]   // verification-status:not modifier
    public var category: [TokenParam]                // CodeableConcept token OR
    public var categoryNot: [TokenParam]             // category:not modifier
    public var code: [TokenParam]                    // CodeableConcept token OR
    public var codeNot: [TokenParam]                 // code:not modifier
    public var identifier: [IdentifierParam]
    public var onsetDate: [DateParam]                // onset-date range filter
    public var abatementDate: [DateParam]            // abatement-date range filter
    public var recordedDate: [DateParam]             // recorded-date range filter
    public var id: [String]                          // _id filter (OR)
    public var lastUpdated: [DateParam]              // _lastUpdated range filter
    public var missing: [String: Bool]               // param:missing=true/false
    public var chains: [ChainedParam]                // chained search: subject.name=Wang, etc.
    public var has: [HasParam]                       // _has modifier: reverse chaining

    // ── Pagination / sort ─────────────────────────────────────────────────────

    public var totalMode: TotalMode
    public var count: Int
    public var sort: SortOrder
    public var cursor: SearchCursor?

    public init(
        subject: String? = nil,
        encounter: String? = nil,
        clinicalStatus: [TokenParam] = [],
        clinicalStatusNot: [TokenParam] = [],
        verificationStatus: [TokenParam] = [],
        verificationStatusNot: [TokenParam] = [],
        category: [TokenParam] = [],
        categoryNot: [TokenParam] = [],
        code: [TokenParam] = [],
        codeNot: [TokenParam] = [],
        identifier: [IdentifierParam] = [],
        onsetDate: [DateParam] = [],
        abatementDate: [DateParam] = [],
        recordedDate: [DateParam] = [],
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
        self.subject              = subject
        self.encounter            = encounter
        self.clinicalStatus       = clinicalStatus
        self.clinicalStatusNot    = clinicalStatusNot
        self.verificationStatus   = verificationStatus
        self.verificationStatusNot = verificationStatusNot
        self.category             = category
        self.categoryNot          = categoryNot
        self.code                 = code
        self.codeNot              = codeNot
        self.identifier           = identifier
        self.onsetDate            = onsetDate
        self.abatementDate        = abatementDate
        self.recordedDate         = recordedDate
        self.id                   = id
        self.lastUpdated          = lastUpdated
        self.missing              = missing
        self.chains               = chains
        self.has                  = has
        self.totalMode            = totalMode
        self.count                = count
        self.sort                 = sort
        self.cursor               = cursor
    }

    public typealias TokenParam      = ObservationSearchQuery.TokenParam
    public typealias DateParam       = PatientSearchQuery.BirthdateParam
    public typealias SortOrder       = PatientSearchQuery.SortOrder
    public typealias SearchCursor    = PatientSearchQuery.SearchCursor
    public typealias IdentifierParam = PatientSearchQuery.IdentifierParam
    public typealias TotalMode       = PatientSearchQuery.TotalMode
}
