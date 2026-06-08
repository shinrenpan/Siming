import Foundation

public struct ProcedureSearchQuery: Sendable {

    // ── Filters ───────────────────────────────────────────────────────────────

    public var subject: String?                     // patient/subject reference
    public var status: [TokenParam]                 // token OR
    public var statusNot: [TokenParam]              // status:not modifier
    public var code: [TokenParam]                   // token OR
    public var codeNot: [TokenParam]                // code:not modifier
    public var category: [TokenParam]               // token OR
    public var categoryNot: [TokenParam]            // category:not modifier
    public var identifier: [IdentifierParam]
    public var encounter: String?                   // encounter reference
    public var performer: String?                   // performer reference
    public var basedOn: String?                     // Procedure.basedOn reference
    public var instantiatesCanonical: [String]      // Procedure.instantiatesCanonical (exact URL match)
    public var instantiatesUri: [String]            // Procedure.instantiatesUri (exact URL match)
    public var location: String?                    // Procedure.location reference
    public var partOf: String?                      // Procedure.partOf reference
    public var reasonCode: [TokenParam]             // Procedure.reasonCode token OR
    public var reasonCodeNot: [TokenParam]          // reason-code:not modifier
    public var reasonReference: String?             // Procedure.reasonReference reference
    public var date: [DateParam]                    // performed date range
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
        code: [TokenParam] = [],
        codeNot: [TokenParam] = [],
        category: [TokenParam] = [],
        categoryNot: [TokenParam] = [],
        identifier: [IdentifierParam] = [],
        encounter: String? = nil,
        performer: String? = nil,
        basedOn: String? = nil,
        instantiatesCanonical: [String] = [],
        instantiatesUri: [String] = [],
        location: String? = nil,
        partOf: String? = nil,
        reasonCode: [TokenParam] = [],
        reasonCodeNot: [TokenParam] = [],
        reasonReference: String? = nil,
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
        self.subject     = subject
        self.status      = status
        self.statusNot   = statusNot
        self.code        = code
        self.codeNot     = codeNot
        self.category    = category
        self.categoryNot = categoryNot
        self.identifier  = identifier
        self.encounter             = encounter
        self.performer             = performer
        self.basedOn               = basedOn
        self.instantiatesCanonical = instantiatesCanonical
        self.instantiatesUri       = instantiatesUri
        self.location              = location
        self.partOf                = partOf
        self.reasonCode            = reasonCode
        self.reasonCodeNot         = reasonCodeNot
        self.reasonReference       = reasonReference
        self.date                  = date
        self.id                    = id
        self.lastUpdated = lastUpdated
        self.missing     = missing
        self.chains      = chains
        self.has         = has
        self.totalMode   = totalMode
        self.count       = count
        self.sort        = sort
        self.cursor      = cursor
    }

    public typealias TokenParam      = ObservationSearchQuery.TokenParam
    public typealias DateParam       = PatientSearchQuery.BirthdateParam
    public typealias SortOrder       = PatientSearchQuery.SortOrder
    public typealias SearchCursor    = PatientSearchQuery.SearchCursor
    public typealias IdentifierParam = PatientSearchQuery.IdentifierParam
    public typealias TotalMode       = PatientSearchQuery.TotalMode
}
