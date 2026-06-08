import Foundation

public struct EncounterSearchQuery: Sendable {

    // ── Filters ───────────────────────────────────────────────────────────────

    public var subject: String?              // patient/subject reference (compartment or direct search)
    public var status: [String]             // token OR: "planned,arrived,in-progress,finished,..."
    public var statusNot: [String]          // status:not modifier
    public var encounterClass: [TokenParam] // class token OR (Swift `class` is reserved — stored as "class")
    public var classNot: [TokenParam]       // class:not modifier
    public var type: [TokenParam]           // CodeableConcept token OR
    public var typeNot: [TokenParam]        // type:not modifier
    public var date: [DateParam]            // Encounter.period range filter (stored as param_name='date')
    public var identifier: [IdentifierParam]
    public var identifierNot: [IdentifierParam]  // identifier:not modifier
    public var participant: String?         // Encounter.participant.individual reference
    public var practitioner: String?        // Encounter.participant.individual (Practitioner only)
    public var reasonCode: [TokenParam]     // Encounter.reasonCode token OR
    public var reasonCodeNot: [TokenParam]  // reason-code:not modifier
    public var partOf: String?              // Encounter.partOf reference
    public var serviceProvider: String?     // Encounter.serviceProvider reference
    public var basedOn: String?             // Encounter.basedOn reference
    public var location: String?            // Encounter.location.location reference
    public var diagnosis: String?           // Encounter.diagnosis.condition reference
    public var account: String?             // Encounter.account reference
    public var appointment: String?         // Encounter.appointment reference
    public var episodeOfCare: String?       // Encounter.episodeOfCare reference
    public var reasonReference: String?     // Encounter.reasonReference reference
    public var locationPeriod: [DateParam]  // Encounter.location.period range filter
    public var participantType: [TokenParam]    // Encounter.participant.type token OR
    public var participantTypeNot: [TokenParam] // participant-type:not modifier
    public var specialArrangement: [TokenParam]    // Encounter.hospitalization.specialArrangement token OR
    public var specialArrangementNot: [TokenParam] // special-arrangement:not modifier
    public var length: [QuantityParam]             // Encounter.length quantity filter
    public var id: [String]                 // _id filter (OR)
    public var lastUpdated: [DateParam]     // _lastUpdated range filter
    public var missing: [String: Bool]      // param:missing=true/false
    public var chains: [ChainedParam]       // chained search: subject.name=Wang, etc.
    public var has: [HasParam]              // _has modifier: reverse chaining

    // ── Pagination / sort ─────────────────────────────────────────────────────

    public var totalMode: TotalMode
    public var count: Int
    public var sort: SortOrder
    public var cursor: SearchCursor?

    public init(
        subject: String? = nil,
        status: [String] = [],
        statusNot: [String] = [],
        encounterClass: [TokenParam] = [],
        classNot: [TokenParam] = [],
        type: [TokenParam] = [],
        typeNot: [TokenParam] = [],
        date: [DateParam] = [],
        identifier: [IdentifierParam] = [],
        identifierNot: [IdentifierParam] = [],
        participant: String? = nil,
        practitioner: String? = nil,
        reasonCode: [TokenParam] = [],
        reasonCodeNot: [TokenParam] = [],
        partOf: String? = nil,
        serviceProvider: String? = nil,
        basedOn: String? = nil,
        location: String? = nil,
        diagnosis: String? = nil,
        account: String? = nil,
        appointment: String? = nil,
        episodeOfCare: String? = nil,
        reasonReference: String? = nil,
        locationPeriod: [DateParam] = [],
        participantType: [TokenParam] = [],
        participantTypeNot: [TokenParam] = [],
        specialArrangement: [TokenParam] = [],
        specialArrangementNot: [TokenParam] = [],
        length: [QuantityParam] = [],
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
        self.subject         = subject
        self.status          = status
        self.statusNot       = statusNot
        self.encounterClass  = encounterClass
        self.classNot        = classNot
        self.type            = type
        self.typeNot         = typeNot
        self.date            = date
        self.identifier      = identifier
        self.identifierNot   = identifierNot
        self.participant     = participant
        self.practitioner    = practitioner
        self.reasonCode      = reasonCode
        self.reasonCodeNot   = reasonCodeNot
        self.partOf          = partOf
        self.serviceProvider = serviceProvider
        self.basedOn         = basedOn
        self.location        = location
        self.diagnosis       = diagnosis
        self.account         = account
        self.appointment     = appointment
        self.episodeOfCare   = episodeOfCare
        self.reasonReference = reasonReference
        self.locationPeriod  = locationPeriod
        self.participantType    = participantType
        self.participantTypeNot = participantTypeNot
        self.specialArrangement    = specialArrangement
        self.specialArrangementNot = specialArrangementNot
        self.length          = length
        self.id              = id
        self.lastUpdated     = lastUpdated
        self.missing         = missing
        self.chains          = chains
        self.has             = has
        self.totalMode       = totalMode
        self.count           = count
        self.sort            = sort
        self.cursor          = cursor
    }

    public typealias TokenParam      = ObservationSearchQuery.TokenParam
    public typealias QuantityParam   = ObservationSearchQuery.QuantityParam
    public typealias DateParam       = PatientSearchQuery.BirthdateParam
    public typealias SortOrder       = PatientSearchQuery.SortOrder
    public typealias SearchCursor    = PatientSearchQuery.SearchCursor
    public typealias IdentifierParam = PatientSearchQuery.IdentifierParam
    public typealias TotalMode       = PatientSearchQuery.TotalMode
}
