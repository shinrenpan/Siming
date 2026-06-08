import Foundation

public struct FamilyMemberHistorySearchQuery: Sendable {

    // ── Filters ───────────────────────────────────────────────────────────────

    public var patient: String?                      // patient reference (REQUIRED field)
    public var status: [TokenParam]                  // token OR: "partial,completed,..."
    public var statusNot: [TokenParam]               // status:not modifier
    public var relationship: [TokenParam]            // CodeableConcept token OR
    public var relationshipNot: [TokenParam]         // relationship:not modifier
    public var sex: [TokenParam]                     // CodeableConcept token OR
    public var sexNot: [TokenParam]                  // sex:not modifier
    public var code: [TokenParam]                    // condition[].code token OR
    public var codeNot: [TokenParam]                 // code:not modifier
    public var identifier: [IdentifierParam]
    public var identifierNot: [IdentifierParam]  // identifier:not modifier
    public var date: [DateParam]                     // date range filter
    public var instantiatesCanonical: [String]       // instantiates-canonical (canonical URL)
    public var instantiatesUri: [String]             // instantiates-uri (URI)
    public var id: [String]                          // _id filter (OR)
    public var lastUpdated: [DateParam]              // _lastUpdated range filter
    public var missing: [String: Bool]               // param:missing=true/false
    public var chains: [ChainedParam]                // chained search
    public var has: [HasParam]                       // _has modifier: reverse chaining
    public var meta: MetaSearchParams                // _tag / _security / _profile

    // ── Pagination / sort ─────────────────────────────────────────────────────

    public var totalMode: TotalMode
    public var count: Int
    public var sort: SortOrder
    public var cursor: SearchCursor?

    public init(
        patient: String? = nil,
        status: [TokenParam] = [],
        statusNot: [TokenParam] = [],
        relationship: [TokenParam] = [],
        relationshipNot: [TokenParam] = [],
        sex: [TokenParam] = [],
        sexNot: [TokenParam] = [],
        code: [TokenParam] = [],
        codeNot: [TokenParam] = [],
        identifier: [IdentifierParam] = [],
        identifierNot: [IdentifierParam] = [],
        date: [DateParam] = [],
        instantiatesCanonical: [String] = [],
        instantiatesUri: [String] = [],
        id: [String] = [],
        lastUpdated: [DateParam] = [],
        missing: [String: Bool] = [:],
        chains: [ChainedParam] = [],
        has: [HasParam] = [],
        meta: MetaSearchParams = MetaSearchParams(),
        totalMode: TotalMode = .accurate,
        count: Int = 20,
        sort: SortOrder = .lastUpdatedDescending,
        cursor: SearchCursor? = nil
    ) {
        self.patient         = patient
        self.status          = status
        self.statusNot       = statusNot
        self.relationship    = relationship
        self.relationshipNot = relationshipNot
        self.sex             = sex
        self.sexNot          = sexNot
        self.code            = code
        self.codeNot         = codeNot
        self.identifier             = identifier
        self.identifierNot          = identifierNot
        self.date                   = date
        self.instantiatesCanonical  = instantiatesCanonical
        self.instantiatesUri        = instantiatesUri
        self.id                     = id
        self.lastUpdated     = lastUpdated
        self.missing         = missing
        self.chains          = chains
        self.has             = has
        self.meta            = meta
        self.totalMode       = totalMode
        self.count           = count
        self.sort            = sort
        self.cursor          = cursor
    }

    public typealias TokenParam      = ObservationSearchQuery.TokenParam
    public typealias DateParam       = PatientSearchQuery.BirthdateParam
    public typealias SortOrder       = PatientSearchQuery.SortOrder
    public typealias SearchCursor    = PatientSearchQuery.SearchCursor
    public typealias IdentifierParam = PatientSearchQuery.IdentifierParam
    public typealias TotalMode       = PatientSearchQuery.TotalMode
}
