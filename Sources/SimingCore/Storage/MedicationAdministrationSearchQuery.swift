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
    public var identifierNot: [IdentifierParam]  // identifier:not modifier
    public var effectiveTime: [DateParam]         // effective-time date range

    public var id: [String]
    public var lastUpdated: [DateParam]
    public var tokenTexts: [TokenTextParam]
    public var missing: [String: Bool]
    public var chains: [ChainedParam]
    public var has: [HasParam]
    public var meta: MetaSearchParams               // _tag / _security / _profile

    // ── Pagination / sort ─────────────────────────────────────────────────────

    public var totalMode: TotalMode
    public var count: Int
    public var sortKeys: [SortKey]
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
        identifierNot: [IdentifierParam] = [],
        effectiveTime: [DateParam] = [],
        id: [String] = [],
        lastUpdated: [DateParam] = [],
        tokenTexts: [TokenTextParam] = [],
        missing: [String: Bool] = [:],
        chains: [ChainedParam] = [],
        has: [HasParam] = [],
        meta: MetaSearchParams = MetaSearchParams(),
        totalMode: TotalMode = .accurate,
        count: Int = 20,
        sortKeys: [SortKey] = [.default],
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
        self.identifier        = identifier
        self.identifierNot     = identifierNot
        self.effectiveTime  = effectiveTime
        self.id             = id
        self.lastUpdated    = lastUpdated
        self.tokenTexts     = tokenTexts
        self.missing        = missing
        self.chains         = chains
        self.has            = has
        self.meta           = meta
        self.totalMode      = totalMode
        self.count          = count
        self.sortKeys       = sortKeys
        self.cursor         = cursor
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
            case "effective-time":  .date(paramName: "effective-time")
            case "status":  .token(paramName: "status")
            case "code":  .token(paramName: "code")
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
