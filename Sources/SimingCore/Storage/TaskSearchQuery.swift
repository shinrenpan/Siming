import Foundation

public struct TaskSearchQuery: Sendable {

    // ── Filters ───────────────────────────────────────────────────────────────

    // token params
    public var status: [TokenParam]
    public var statusNot: [TokenParam]
    public var intent: [TokenParam]
    public var intentNot: [TokenParam]
    public var priority: [TokenParam]
    public var priorityNot: [TokenParam]
    public var code: [TokenParam]
    public var codeNot: [TokenParam]
    public var businessStatus: [TokenParam]
    public var businessStatusNot: [TokenParam]
    public var performer: [TokenParam]               // Task.performerType
    public var performerNot: [TokenParam]
    public var identifier: [IdentifierParam]
    public var identifierNot: [IdentifierParam]      // identifier:not modifier
    public var groupIdentifier: [IdentifierParam]

    // date params
    public var authoredOn: [DateParam]
    public var modified: [DateParam]
    public var period: [DateParam]

    // reference params
    public var subject: String?
    public var patient: String?
    public var encounter: String?
    public var focus: String?
    public var owner: String?
    public var requester: String?
    public var basedOn: String?
    public var partOf: String?

    // system params
    public var id: [String]
    public var lastUpdated: [DateParam]
    public var tokenTexts: [TokenTextParam]
    public var missing: [String: Bool]
    public var chains: [ChainedParam]
    public var has: [HasParam]
    public var meta: MetaSearchParams           // _tag / _security / _profile

    // ── Pagination / sort ─────────────────────────────────────────────────────

    public var totalMode: TotalMode
    public var count: Int
    public var sortKeys: [SortKey]
    public var cursor: SearchCursor?

    public init(
        status: [TokenParam] = [],
        statusNot: [TokenParam] = [],
        intent: [TokenParam] = [],
        intentNot: [TokenParam] = [],
        priority: [TokenParam] = [],
        priorityNot: [TokenParam] = [],
        code: [TokenParam] = [],
        codeNot: [TokenParam] = [],
        businessStatus: [TokenParam] = [],
        businessStatusNot: [TokenParam] = [],
        performer: [TokenParam] = [],
        performerNot: [TokenParam] = [],
        identifier: [IdentifierParam] = [],
        identifierNot: [IdentifierParam] = [],
        groupIdentifier: [IdentifierParam] = [],
        authoredOn: [DateParam] = [],
        modified: [DateParam] = [],
        period: [DateParam] = [],
        subject: String? = nil,
        patient: String? = nil,
        encounter: String? = nil,
        focus: String? = nil,
        owner: String? = nil,
        requester: String? = nil,
        basedOn: String? = nil,
        partOf: String? = nil,
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
        self.status            = status
        self.statusNot         = statusNot
        self.intent            = intent
        self.intentNot         = intentNot
        self.priority          = priority
        self.priorityNot       = priorityNot
        self.code              = code
        self.codeNot           = codeNot
        self.businessStatus    = businessStatus
        self.businessStatusNot = businessStatusNot
        self.performer         = performer
        self.performerNot      = performerNot
        self.identifier        = identifier
        self.identifierNot     = identifierNot
        self.groupIdentifier   = groupIdentifier
        self.authoredOn        = authoredOn
        self.modified          = modified
        self.period            = period
        self.subject           = subject
        self.patient           = patient
        self.encounter         = encounter
        self.focus             = focus
        self.owner             = owner
        self.requester         = requester
        self.basedOn           = basedOn
        self.partOf            = partOf
        self.id                = id
        self.lastUpdated       = lastUpdated
        self.tokenTexts        = tokenTexts
        self.missing           = missing
        self.chains            = chains
        self.has               = has
        self.meta              = meta
        self.totalMode         = totalMode
        self.count             = count
        self.sortKeys          = sortKeys
        self.cursor            = cursor
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
            case "_lastUpdated":  .lastUpdated
            case "_id":           .resourceId
            case "authored-on":   .date(paramName: "authored-on")
            case "modified":      .date(paramName: "modified")
            case "period":        .date(paramName: "period")
            case "code":          .token(paramName: "code")
            case "status":        .token(paramName: "status")
            case "priority":      .token(paramName: "priority")
            default:              nil
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
