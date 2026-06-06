import Foundation

public struct MedicationStatementSearchQuery: Sendable {

    // ── Filters ───────────────────────────────────────────────────────────────

    public var subject: String?                     // patient/subject reference
    public var patient: String?                     // patient reference (alias for subject)
    public var status: [TokenParam]                 // token OR: "active,completed,..."
    public var statusNot: [TokenParam]              // status:not modifier
    public var category: [TokenParam]               // CodeableConcept token OR
    public var categoryNot: [TokenParam]            // category:not modifier
    public var code: [TokenParam]                   // medication-as-CodeableConcept token OR
    public var codeNot: [TokenParam]                // code:not modifier
    public var identifier: [IdentifierParam]
    public var effective: [DateParam]               // effective[x] range filter
    public var context: String?                     // reference: "Encounter/id"
    public var source: String?                      // reference: informationSource
    public var medication: String?                  // reference: medication-as-Reference
    public var partOf: String?                      // reference: partOf
    public var id: [String]                         // _id filter (OR)
    public var lastUpdated: [DateParam]             // _lastUpdated range filter
    public var missing: [String: Bool]              // param:missing=true/false
    public var chains: [ChainedParam]               // chained search
    public var has: [HasParam]                      // _has modifier: reverse chaining

    // ── Pagination / sort ─────────────────────────────────────────────────────

    public var totalMode: TotalMode
    public var count: Int
    public var sort: SortOrder
    public var cursor: SearchCursor?

    public init(
        subject: String? = nil,
        patient: String? = nil,
        status: [TokenParam] = [],
        statusNot: [TokenParam] = [],
        category: [TokenParam] = [],
        categoryNot: [TokenParam] = [],
        code: [TokenParam] = [],
        codeNot: [TokenParam] = [],
        identifier: [IdentifierParam] = [],
        effective: [DateParam] = [],
        context: String? = nil,
        source: String? = nil,
        medication: String? = nil,
        partOf: String? = nil,
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
        self.subject      = subject
        self.patient      = patient
        self.status       = status
        self.statusNot    = statusNot
        self.category     = category
        self.categoryNot  = categoryNot
        self.code         = code
        self.codeNot      = codeNot
        self.identifier   = identifier
        self.effective    = effective
        self.context      = context
        self.source       = source
        self.medication   = medication
        self.partOf       = partOf
        self.id           = id
        self.lastUpdated  = lastUpdated
        self.missing      = missing
        self.chains       = chains
        self.has          = has
        self.totalMode    = totalMode
        self.count        = count
        self.sort         = sort
        self.cursor       = cursor
    }

    public typealias TokenParam      = ObservationSearchQuery.TokenParam
    public typealias DateParam       = PatientSearchQuery.BirthdateParam
    public typealias SortOrder       = PatientSearchQuery.SortOrder
    public typealias SearchCursor    = PatientSearchQuery.SearchCursor
    public typealias IdentifierParam = PatientSearchQuery.IdentifierParam
    public typealias TotalMode       = PatientSearchQuery.TotalMode
}
