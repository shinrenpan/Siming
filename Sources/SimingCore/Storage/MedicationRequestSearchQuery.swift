import Foundation

public struct MedicationRequestSearchQuery: Sendable {

    // ── Filters ───────────────────────────────────────────────────────────────

    public var subject: String?                     // patient/subject reference
    public var status: [TokenParam]                 // token OR: "active,completed,..."
    public var statusNot: [TokenParam]              // status:not modifier
    public var intent: [TokenParam]                 // token OR: "proposal,plan,order,..."
    public var intentNot: [TokenParam]              // intent:not modifier
    public var category: [TokenParam]               // CodeableConcept token OR
    public var categoryNot: [TokenParam]            // category:not modifier
    public var code: [TokenParam]                   // medication-as-CodeableConcept token OR
    public var codeNot: [TokenParam]                // code:not modifier
    public var priority: [TokenParam]               // token OR: "routine,urgent,asap,stat"
    public var priorityNot: [TokenParam]            // priority:not modifier
    public var identifier: [IdentifierParam]
    public var identifierNot: [IdentifierParam]     // identifier:not modifier
    public var date: [DateParam]                    // date (dosage timing events) range filter
    public var authoredOn: [DateParam]              // authoredon range filter
    public var encounter: String?                   // reference: "Encounter/id"
    public var requester: String?                   // reference: "Practitioner/id" etc.
    public var intendedDispenser: String?           // MedicationRequest.dispenseRequest.performer reference
    public var intendedPerformer: String?           // MedicationRequest.performer reference
    public var intendedPerformerType: [TokenParam]    // MedicationRequest.performerType token OR
    public var intendedPerformerTypeNot: [TokenParam] // intended-performertype:not modifier
    public var medication: String?                  // MedicationRequest.medication as Reference
    public var id: [String]                         // _id filter (OR)
    public var meta: MetaSearchParams = MetaSearchParams()  // _tag / _security / _profile
    public var lastUpdated: [DateParam]             // _lastUpdated range filter
    public var tokenTexts: [TokenTextParam]         // param:text=value modifier
    public var missing: [String: Bool]              // param:missing=true/false
    public var chains: [ChainedParam]               // chained search: subject.name=Wang, etc.
    public var has: [HasParam]                      // _has modifier: reverse chaining

    // ── Pagination / sort ─────────────────────────────────────────────────────

    public var totalMode: TotalMode
    public var count: Int
    public var sortKeys: [SortKey]
    public var cursor: SearchCursor?

    public init(
        subject: String? = nil,
        status: [TokenParam] = [],
        statusNot: [TokenParam] = [],
        intent: [TokenParam] = [],
        intentNot: [TokenParam] = [],
        category: [TokenParam] = [],
        categoryNot: [TokenParam] = [],
        code: [TokenParam] = [],
        codeNot: [TokenParam] = [],
        priority: [TokenParam] = [],
        priorityNot: [TokenParam] = [],
        identifier: [IdentifierParam] = [],
        identifierNot: [IdentifierParam] = [],
        date: [DateParam] = [],
        authoredOn: [DateParam] = [],
        encounter: String? = nil,
        requester: String? = nil,
        intendedDispenser: String? = nil,
        intendedPerformer: String? = nil,
        intendedPerformerType: [TokenParam] = [],
        intendedPerformerTypeNot: [TokenParam] = [],
        medication: String? = nil,
        id: [String] = [],
        lastUpdated: [DateParam] = [],
        tokenTexts: [TokenTextParam] = [],
        missing: [String: Bool] = [:],
        chains: [ChainedParam] = [],
        has: [HasParam] = [],
        totalMode: TotalMode = .accurate,
        count: Int = 20,
        sortKeys: [SortKey] = [.default],
        cursor: SearchCursor? = nil
    ) {
        self.subject      = subject
        self.status       = status
        self.statusNot    = statusNot
        self.intent       = intent
        self.intentNot    = intentNot
        self.category     = category
        self.categoryNot  = categoryNot
        self.code         = code
        self.codeNot      = codeNot
        self.priority     = priority
        self.priorityNot  = priorityNot
        self.identifier   = identifier
        self.identifierNot = identifierNot
        self.date         = date
        self.authoredOn   = authoredOn
        self.encounter    = encounter
        self.requester    = requester
        self.intendedDispenser        = intendedDispenser
        self.intendedPerformer        = intendedPerformer
        self.intendedPerformerType    = intendedPerformerType
        self.intendedPerformerTypeNot = intendedPerformerTypeNot
        self.medication   = medication
        self.id           = id
        self.lastUpdated  = lastUpdated
        self.tokenTexts   = tokenTexts
        self.missing      = missing
        self.chains       = chains
        self.has          = has
        self.totalMode    = totalMode
        self.count        = count
        self.sortKeys       = sortKeys
        self.cursor       = cursor
    }

    // ── Sort order ────────────────────────────────────────────────────────────

    /// Parses a comma-separated `_sort` value into sort keys.
    /// Unrecognised tokens are ignored; empty result falls back to `[.default]`.
    public static func parseSortKeys(_ raw: String) -> [SortKey] {
        let keys = raw.split(separator: ",").compactMap { token -> SortKey? in
            let s = String(token).trimmingCharacters(in: .whitespaces)
            let desc = s.hasPrefix("-")
            let name = desc ? String(s.dropFirst()) : s
            let src: SortKeySource? = switch name {
            case "_lastUpdated":    .lastUpdated
            case "_id":             .resourceId
            case "authoredon":  .date(paramName: "authoredon")
            case "code":  .token(paramName: "code")
            case "status":  .token(paramName: "status")
            default:                nil
            }
            guard let src else { return nil }
            return SortKey(source: src, descending: desc)
        }
        return keys.isEmpty ? [.default] : keys
    }

    public typealias TokenParam      = ObservationSearchQuery.TokenParam
    public typealias DateParam       = PatientSearchQuery.BirthdateParam
    public typealias IdentifierParam = PatientSearchQuery.IdentifierParam
    public typealias TotalMode       = PatientSearchQuery.TotalMode
}
