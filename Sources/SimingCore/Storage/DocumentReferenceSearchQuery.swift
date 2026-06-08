import Foundation

public struct DocumentReferenceSearchQuery: Sendable {

    // ── Filters ───────────────────────────────────────────────────────────────

    // token params
    public var status: [TokenParam]
    public var statusNot: [TokenParam]
    public var type: [TokenParam]
    public var typeNot: [TokenParam]
    public var category: [TokenParam]
    public var categoryNot: [TokenParam]
    public var identifier: [IdentifierParam]
    public var securityLabel: [TokenParam]
    public var securityLabelNot: [TokenParam]
    public var facility: [TokenParam]
    public var event: [TokenParam]
    public var contentType: [TokenParam]
    public var contentTypeNot: [TokenParam]
    public var format: [TokenParam]
    public var formatNot: [TokenParam]
    public var language: [TokenParam]
    public var languageNot: [TokenParam]
    public var setting: [TokenParam]
    public var settingNot: [TokenParam]

    // date params
    public var date: [DateParam]
    public var period: [DateParam]

    // string params
    public var description: [String]
    public var location: [String]     // content[*].attachment.url (uri type — exact match)

    // reference params
    public var subject: String?
    public var patient: String?
    public var author: String?
    public var encounter: String?
    public var custodian: String?
    public var authenticator: String?
    public var relatesto: String?
    public var related: String?              // DocumentReference.context.related[] reference

    // relatesto relation token
    public var relation: [TokenParam]
    public var relationNot: [TokenParam]

    // system params
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
        status: [TokenParam] = [],
        statusNot: [TokenParam] = [],
        type: [TokenParam] = [],
        typeNot: [TokenParam] = [],
        category: [TokenParam] = [],
        categoryNot: [TokenParam] = [],
        identifier: [IdentifierParam] = [],
        securityLabel: [TokenParam] = [],
        securityLabelNot: [TokenParam] = [],
        facility: [TokenParam] = [],
        event: [TokenParam] = [],
        contentType: [TokenParam] = [],
        contentTypeNot: [TokenParam] = [],
        format: [TokenParam] = [],
        formatNot: [TokenParam] = [],
        language: [TokenParam] = [],
        languageNot: [TokenParam] = [],
        setting: [TokenParam] = [],
        settingNot: [TokenParam] = [],
        date: [DateParam] = [],
        period: [DateParam] = [],
        description: [String] = [],
        location: [String] = [],
        subject: String? = nil,
        patient: String? = nil,
        author: String? = nil,
        encounter: String? = nil,
        custodian: String? = nil,
        authenticator: String? = nil,
        relatesto: String? = nil,
        related: String? = nil,
        relation: [TokenParam] = [],
        relationNot: [TokenParam] = [],
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
        self.status           = status
        self.statusNot        = statusNot
        self.type             = type
        self.typeNot          = typeNot
        self.category         = category
        self.categoryNot      = categoryNot
        self.identifier       = identifier
        self.securityLabel    = securityLabel
        self.securityLabelNot = securityLabelNot
        self.facility         = facility
        self.event            = event
        self.contentType      = contentType
        self.contentTypeNot   = contentTypeNot
        self.format           = format
        self.formatNot        = formatNot
        self.language         = language
        self.languageNot      = languageNot
        self.setting          = setting
        self.settingNot       = settingNot
        self.date             = date
        self.period           = period
        self.description      = description
        self.location         = location
        self.subject          = subject
        self.patient          = patient
        self.author           = author
        self.encounter        = encounter
        self.custodian        = custodian
        self.authenticator    = authenticator
        self.relatesto        = relatesto
        self.related          = related
        self.relation         = relation
        self.relationNot      = relationNot
        self.id               = id
        self.lastUpdated      = lastUpdated
        self.missing          = missing
        self.chains           = chains
        self.has              = has
        self.totalMode        = totalMode
        self.count            = count
        self.sort             = sort
        self.cursor           = cursor
    }

    public typealias TokenParam      = ObservationSearchQuery.TokenParam
    public typealias DateParam       = PatientSearchQuery.BirthdateParam
    public typealias SortOrder       = PatientSearchQuery.SortOrder
    public typealias SearchCursor    = PatientSearchQuery.SearchCursor
    public typealias IdentifierParam = PatientSearchQuery.IdentifierParam
    public typealias TotalMode       = PatientSearchQuery.TotalMode
}
