import Foundation

public struct MedicationAdministrationSearchQuery: Sendable {

    // ── Filters ───────────────────────────────────────────────────────────────

    public var subject: String?                   // MedicationAdministration.subject (any reference)
    public var patient: String?                   // subject restricted to Patient — injected for compartment
    public var context: String?                   // MedicationAdministration.context (Encounter/EpisodeOfCare)
    public var request: String?                   // MedicationAdministration.request (MedicationRequest)
    public var performer: String?                 // performer[].actor
    public var device: String?                    // MedicationAdministration.device[]
    public var medication: String?                // medication as Reference
    public var status: [TokenParam]               // token OR
    public var statusNot: [TokenParam]            // status:not modifier
    public var code: [TokenParam]                 // medication as CodeableConcept token OR
    public var codeNot: [TokenParam]              // code:not modifier
    public var reasonGiven: [TokenParam]          // reason-given (reasonCode) token OR
    public var reasonGivenNot: [TokenParam]       // reason-given:not modifier
    public var reasonNotGiven: [TokenParam]       // reason-not-given (statusReason) token OR
    public var reasonNotGivenNot: [TokenParam]    // reason-not-given:not modifier
    public var identifier: [IdentifierParam]
    public var effectiveTime: [DateParam]         // effective-time date range

    public var id: [String]
    public var lastUpdated: [DateParam]
    public var missing: [String: Bool]
    public var chains: [ChainedParam]
    public var has: [HasParam]

    // ── Pagination / sort ─────────────────────────────────────────────────────

    public var totalMode: TotalMode
    public var count: Int
    public var sort: SortOrder
    public var cursor: SearchCursor?

    public init(
        subject: String? = nil,
        patient: String? = nil,
        context: String? = nil,
        request: String? = nil,
        performer: String? = nil,
        device: String? = nil,
        medication: String? = nil,
        status: [TokenParam] = [],
        statusNot: [TokenParam] = [],
        code: [TokenParam] = [],
        codeNot: [TokenParam] = [],
        reasonGiven: [TokenParam] = [],
        reasonGivenNot: [TokenParam] = [],
        reasonNotGiven: [TokenParam] = [],
        reasonNotGivenNot: [TokenParam] = [],
        identifier: [IdentifierParam] = [],
        effectiveTime: [DateParam] = [],
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
        self.patient        = patient
        self.context        = context
        self.request        = request
        self.performer      = performer
        self.device         = device
        self.medication     = medication
        self.status         = status
        self.statusNot      = statusNot
        self.code           = code
        self.codeNot        = codeNot
        self.reasonGiven    = reasonGiven
        self.reasonGivenNot = reasonGivenNot
        self.reasonNotGiven    = reasonNotGiven
        self.reasonNotGivenNot = reasonNotGivenNot
        self.identifier     = identifier
        self.effectiveTime  = effectiveTime
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
