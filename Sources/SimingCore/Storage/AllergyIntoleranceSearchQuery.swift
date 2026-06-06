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
    public var identifier: [IdentifierParam]
    public var date: [DateParam]                        // recordedDate range filter
    public var id: [String]                             // _id filter (OR)
    public var lastUpdated: [DateParam]                 // _lastUpdated range filter
    public var missing: [String: Bool]                  // param:missing=true/false

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
        identifier: [IdentifierParam] = [],
        date: [DateParam] = [],
        id: [String] = [],
        lastUpdated: [DateParam] = [],
        missing: [String: Bool] = [:],
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
        self.identifier           = identifier
        self.date                 = date
        self.id                   = id
        self.lastUpdated          = lastUpdated
        self.missing              = missing
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
