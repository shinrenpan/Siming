import Foundation

public struct AllergyIntoleranceSearchQuery: Sendable {

    // ── Filters ───────────────────────────────────────────────────────────────

    public var subject: String?                         // patient reference
    public var clinicalStatus: [TokenParam]             // token OR
    public var clinicalStatusNot: [TokenParam]          // clinical-status:not modifier
    public var verificationStatus: [TokenParam]         // token OR
    public var verificationStatusNot: [TokenParam]      // verification-status:not modifier
    public var type: [TokenParam]                       // token OR: "allergy,intolerance"
    public var typeNot: [TokenParam]                    // type:not modifier
    public var category: [TokenParam]                   // token OR: "food,medication,environment,biologic"
    public var categoryNot: [TokenParam]                // category:not modifier
    public var criticality: [TokenParam]                // token OR: "low,high,unable-to-assess"
    public var criticalityNot: [TokenParam]             // criticality:not modifier
    public var code: [TokenParam]                       // CodeableConcept token OR
    public var codeNot: [TokenParam]                    // code:not modifier
    public var manifestation: [TokenParam]              // reaction.manifestation token OR
    public var manifestationNot: [TokenParam]           // manifestation:not modifier
    public var severity: [TokenParam]                   // reaction.severity token OR
    public var severityNot: [TokenParam]                // severity:not modifier
    public var route: [TokenParam]                      // reaction.exposureRoute token OR
    public var routeNot: [TokenParam]                   // route:not modifier
    public var identifier: [IdentifierParam]
    public var date: [DateParam]                        // recordedDate range filter
    public var lastDate: [DateParam]                    // lastOccurrence range filter
    public var onset: [DateParam]                       // reaction.onset range filter
    public var id: [String]                             // _id filter (OR)
    public var lastUpdated: [DateParam]                 // _lastUpdated range filter
    public var missing: [String: Bool]                  // param:missing=true/false
    public var chains: [ChainedParam]                   // chained search: patient.name=Wang, etc.
    public var has: [HasParam]                          // _has modifier: reverse chaining

    // ── Pagination / sort ─────────────────────────────────────────────────────

    public var totalMode: TotalMode
    public var count: Int
    public var sort: SortOrder
    public var cursor: SearchCursor?

    public init(
        subject: String? = nil,
        clinicalStatus: [TokenParam] = [],
        clinicalStatusNot: [TokenParam] = [],
        verificationStatus: [TokenParam] = [],
        verificationStatusNot: [TokenParam] = [],
        type: [TokenParam] = [],
        typeNot: [TokenParam] = [],
        category: [TokenParam] = [],
        categoryNot: [TokenParam] = [],
        criticality: [TokenParam] = [],
        criticalityNot: [TokenParam] = [],
        code: [TokenParam] = [],
        codeNot: [TokenParam] = [],
        manifestation: [TokenParam] = [],
        manifestationNot: [TokenParam] = [],
        severity: [TokenParam] = [],
        severityNot: [TokenParam] = [],
        route: [TokenParam] = [],
        routeNot: [TokenParam] = [],
        identifier: [IdentifierParam] = [],
        date: [DateParam] = [],
        lastDate: [DateParam] = [],
        onset: [DateParam] = [],
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
        self.clinicalStatus       = clinicalStatus
        self.clinicalStatusNot    = clinicalStatusNot
        self.verificationStatus   = verificationStatus
        self.verificationStatusNot = verificationStatusNot
        self.type                 = type
        self.typeNot              = typeNot
        self.category             = category
        self.categoryNot          = categoryNot
        self.criticality          = criticality
        self.criticalityNot       = criticalityNot
        self.code                 = code
        self.codeNot              = codeNot
        self.manifestation        = manifestation
        self.manifestationNot     = manifestationNot
        self.severity             = severity
        self.severityNot          = severityNot
        self.route                = route
        self.routeNot             = routeNot
        self.identifier           = identifier
        self.date                 = date
        self.lastDate             = lastDate
        self.onset                = onset
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
