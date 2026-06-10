import Foundation

public struct ImmunizationSearchQuery: Sendable {

    // ── Filters ───────────────────────────────────────────────────────────────

    public var subject: String?                     // patient reference
    public var status: [TokenParam]                 // token OR
    public var statusNot: [TokenParam]              // status:not modifier
    public var vaccineCode: [TokenParam]            // vaccine-code token OR
    public var vaccineCodeNot: [TokenParam]         // vaccine-code:not modifier
    public var identifier: [IdentifierParam]
    public var identifierNot: [IdentifierParam]     // identifier:not modifier
    public var performer: String?                   // performer reference
    public var location: String?                    // Immunization.location reference
    public var manufacturer: String?                // Immunization.manufacturer reference
    public var reaction: String?                    // Immunization.reaction.detail reference
    public var reactionDate: [DateParam]            // Immunization.reaction.date range
    public var reasonCode: [TokenParam]             // Immunization.reasonCode token OR
    public var reasonCodeNot: [TokenParam]          // reason-code:not modifier
    public var reasonReference: String?             // Immunization.reasonReference reference
    public var series: StringParam?                  // Immunization.protocolApplied.series string
    public var statusReason: [TokenParam]           // Immunization.statusReason token OR
    public var statusReasonNot: [TokenParam]        // status-reason:not modifier
    public var targetDisease: [TokenParam]          // Immunization.protocolApplied.targetDisease token OR
    public var targetDiseaseNot: [TokenParam]       // target-disease:not modifier
    public var lotNumber: StringParam?               // lot-number string search
    public var date: [DateParam]                    // occurrence date range
    public var id: [String]                         // _id filter (OR)
    public var meta: MetaSearchParams = MetaSearchParams()  // _tag / _security / _profile
    public var lastUpdated: [DateParam]             // _lastUpdated range filter
    public var tokenTexts: [TokenTextParam]         // param:text=value modifier
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
        identifierNot: [IdentifierParam] = [],
        performer: String? = nil,
        location: String? = nil,
        manufacturer: String? = nil,
        reaction: String? = nil,
        reactionDate: [DateParam] = [],
        reasonCode: [TokenParam] = [],
        reasonCodeNot: [TokenParam] = [],
        reasonReference: String? = nil,
        series: StringParam? = nil,
        statusReason: [TokenParam] = [],
        statusReasonNot: [TokenParam] = [],
        targetDisease: [TokenParam] = [],
        targetDiseaseNot: [TokenParam] = [],
        lotNumber: StringParam? = nil,
        date: [DateParam] = [],
        id: [String] = [],
        lastUpdated: [DateParam] = [],
        tokenTexts: [TokenTextParam] = [],
        missing: [String: Bool] = [:],
        chains: [ChainedParam] = [],
        has: [HasParam] = [],
        totalMode: TotalMode = .accurate,
        count: Int = 20,
        sort: SortOrder = .lastUpdatedDescending,
        cursor: SearchCursor? = nil
    ) {
        self.subject         = subject
        self.status          = status
        self.statusNot       = statusNot
        self.vaccineCode     = vaccineCode
        self.vaccineCodeNot  = vaccineCodeNot
        self.identifier      = identifier
        self.identifierNot   = identifierNot
        self.performer       = performer
        self.location        = location
        self.manufacturer    = manufacturer
        self.reaction        = reaction
        self.reactionDate    = reactionDate
        self.reasonCode      = reasonCode
        self.reasonCodeNot   = reasonCodeNot
        self.reasonReference = reasonReference
        self.series          = series
        self.statusReason    = statusReason
        self.statusReasonNot = statusReasonNot
        self.targetDisease   = targetDisease
        self.targetDiseaseNot = targetDiseaseNot
        self.lotNumber       = lotNumber
        self.date            = date
        self.id              = id
        self.lastUpdated     = lastUpdated
        self.tokenTexts      = tokenTexts
        self.missing         = missing
        self.chains          = chains
        self.has             = has
        self.totalMode       = totalMode
        self.count           = count
        self.sort            = sort
        self.cursor          = cursor
    }

    public typealias StringParam     = PatientSearchQuery.StringParam
    public typealias TokenParam      = ObservationSearchQuery.TokenParam
    public typealias DateParam       = PatientSearchQuery.BirthdateParam
    public typealias SortOrder       = PatientSearchQuery.SortOrder
    public typealias SearchCursor    = PatientSearchQuery.SearchCursor
    public typealias IdentifierParam = PatientSearchQuery.IdentifierParam
    public typealias TotalMode       = PatientSearchQuery.TotalMode
}
