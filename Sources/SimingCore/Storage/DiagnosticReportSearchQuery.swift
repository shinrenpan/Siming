import Foundation

public struct DiagnosticReportSearchQuery: Sendable {

    // ── Filters ───────────────────────────────────────────────────────────────

    public var subject: String?                     // patient/subject reference
    public var status: [TokenParam]                 // token OR
    public var statusNot: [TokenParam]              // status:not modifier
    public var code: [TokenParam]                   // token OR
    public var codeNot: [TokenParam]                // code:not modifier
    public var category: [TokenParam]               // token OR
    public var categoryNot: [TokenParam]            // category:not modifier
    public var identifier: [IdentifierParam]
    public var identifierNot: [IdentifierParam]     // identifier:not modifier
    public var encounter: String?                   // encounter reference
    public var performer: String?                   // performer reference
    public var basedOn: String?                     // DiagnosticReport.basedOn reference
    public var conclusion: [TokenParam]             // DiagnosticReport.conclusionCode token OR
    public var conclusionNot: [TokenParam]          // conclusion:not modifier
    public var media: String?                       // DiagnosticReport.media[].link reference
    public var result: String?                      // DiagnosticReport.result reference
    public var resultsInterpreter: String?          // DiagnosticReport.resultsInterpreter reference
    public var specimen: String?                    // DiagnosticReport.specimen reference
    public var date: [DateParam]                    // effective date range
    public var issued: [DateParam]                  // issued date range
    public var id: [String]                         // _id filter (OR)
    public var meta: MetaSearchParams = MetaSearchParams()  // _tag / _security / _profile
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
        identifierNot: [IdentifierParam] = [],
        encounter: String? = nil,
        performer: String? = nil,
        basedOn: String? = nil,
        conclusion: [TokenParam] = [],
        conclusionNot: [TokenParam] = [],
        media: String? = nil,
        result: String? = nil,
        resultsInterpreter: String? = nil,
        specimen: String? = nil,
        date: [DateParam] = [],
        issued: [DateParam] = [],
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
        self.identifierNot = identifierNot
        self.encounter          = encounter
        self.performer          = performer
        self.basedOn            = basedOn
        self.conclusion         = conclusion
        self.conclusionNot      = conclusionNot
        self.media              = media
        self.result             = result
        self.resultsInterpreter = resultsInterpreter
        self.specimen           = specimen
        self.date               = date
        self.issued             = issued
        self.id                 = id
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
