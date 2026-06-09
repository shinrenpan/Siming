import Foundation

public struct SpecimenSearchQuery: Sendable {

    // ── Filters ───────────────────────────────────────────────────────────────

    // token params
    public var status: [TokenParam]
    public var statusNot: [TokenParam]
    public var type: [TokenParam]
    public var typeNot: [TokenParam]
    public var accession: [TokenParam]
    public var accessionNot: [TokenParam]
    public var identifier: [IdentifierParam]
    public var identifierNot: [IdentifierParam]  // identifier:not modifier
    public var bodysite: [TokenParam]
    public var bodysiteNot: [TokenParam]
    public var container: [TokenParam]
    public var containerNot: [TokenParam]
    public var containerId: [TokenParam]
    public var containerIdNot: [TokenParam]

    // date params
    public var collected: [DateParam]

    // reference params
    public var subject: String?
    public var patient: String?
    public var collector: String?
    public var parent: String?

    // system params
    public var id: [String]
    public var lastUpdated: [DateParam]
    public var missing: [String: Bool]
    public var chains: [ChainedParam]
    public var has: [HasParam]
    public var meta: MetaSearchParams           // _tag / _security / _profile

    // ── Pagination / sort ─────────────────────────────────────────────────────

    public var totalMode: TotalMode
    public var count: Int
    public var sort: SortOrder
    public var cursor: SearchCursor?

    public init(
        status: [TokenParam] = [],
        statusNot: [TokenParam] = [],
        type: [TokenParam] = [],
        typeNot: [TokenParam] = [],
        accession: [TokenParam] = [],
        accessionNot: [TokenParam] = [],
        identifier: [IdentifierParam] = [],
        identifierNot: [IdentifierParam] = [],
        bodysite: [TokenParam] = [],
        bodysiteNot: [TokenParam] = [],
        container: [TokenParam] = [],
        containerNot: [TokenParam] = [],
        containerId: [TokenParam] = [],
        containerIdNot: [TokenParam] = [],
        collected: [DateParam] = [],
        subject: String? = nil,
        patient: String? = nil,
        collector: String? = nil,
        parent: String? = nil,
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
        self.status         = status
        self.statusNot      = statusNot
        self.type           = type
        self.typeNot        = typeNot
        self.accession      = accession
        self.accessionNot   = accessionNot
        self.identifier     = identifier
        self.identifierNot  = identifierNot
        self.bodysite       = bodysite
        self.bodysiteNot    = bodysiteNot
        self.container      = container
        self.containerNot   = containerNot
        self.containerId    = containerId
        self.containerIdNot = containerIdNot
        self.collected      = collected
        self.subject        = subject
        self.patient        = patient
        self.collector      = collector
        self.parent         = parent
        self.id             = id
        self.lastUpdated    = lastUpdated
        self.missing        = missing
        self.chains         = chains
        self.has            = has
        self.meta           = meta
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
