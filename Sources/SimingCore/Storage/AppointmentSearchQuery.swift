import Foundation

public struct AppointmentSearchQuery: Sendable {

    // ── Filters ───────────────────────────────────────────────────────────────

    public var patient: String?                      // participant.actor (Patient) — injected server-side for compartment
    public var actor: String?                        // participant.actor (any reference)
    public var practitioner: String?                 // participant.actor (Practitioner)
    public var location: String?                     // participant.actor (Location)
    public var status: [TokenParam]                  // token OR: proposed | pending | booked | arrived | fulfilled | ...
    public var statusNot: [TokenParam]               // status:not modifier
    public var identifier: [IdentifierParam]
    public var identifierNot: [IdentifierParam]      // identifier:not modifier
    public var date: [DateParam]                     // Appointment.start date range
    public var serviceType: [TokenParam]             // service-type CodeableConcept token OR
    public var serviceTypeNot: [TokenParam]          // service-type:not modifier
    public var appointmentType: [TokenParam]         // appointment-type CodeableConcept token OR
    public var appointmentTypeNot: [TokenParam]      // appointment-type:not modifier
    public var specialty: [TokenParam]               // specialty CodeableConcept token OR
    public var specialtyNot: [TokenParam]            // specialty:not modifier
    public var reasonCode: [TokenParam]              // reason-code CodeableConcept token OR
    public var reasonCodeNot: [TokenParam]           // reason-code:not modifier
    public var serviceCategory: [TokenParam]         // service-category CodeableConcept token OR
    public var serviceCategoryNot: [TokenParam]      // service-category:not modifier
    public var partStatus: [TokenParam]              // part-status: participant.status token OR
    public var partStatusNot: [TokenParam]           // part-status:not modifier
    public var supportingInfo: String?               // supporting-info reference (supportingInformation)
    public var basedOn: String?                      // based-on reference (ServiceRequest)
    public var reasonReference: String?              // reason-reference reference (Condition/Procedure)
    public var id: [String]                          // _id filter (OR)
    public var meta: MetaSearchParams = MetaSearchParams()  // _tag / _security / _profile
    public var lastUpdated: [DateParam]              // _lastUpdated range filter
    public var missing: [String: Bool]               // param:missing=true/false
    public var chains: [ChainedParam]                // chained search
    public var has: [HasParam]                       // _has modifier: reverse chaining

    // ── Pagination / sort ─────────────────────────────────────────────────────

    public var totalMode: TotalMode
    public var count: Int
    public var sort: SortOrder
    public var cursor: SearchCursor?

    public init(
        patient: String? = nil,
        actor: String? = nil,
        practitioner: String? = nil,
        location: String? = nil,
        status: [TokenParam] = [],
        statusNot: [TokenParam] = [],
        identifier: [IdentifierParam] = [],
        identifierNot: [IdentifierParam] = [],
        date: [DateParam] = [],
        serviceType: [TokenParam] = [],
        serviceTypeNot: [TokenParam] = [],
        appointmentType: [TokenParam] = [],
        appointmentTypeNot: [TokenParam] = [],
        specialty: [TokenParam] = [],
        specialtyNot: [TokenParam] = [],
        reasonCode: [TokenParam] = [],
        reasonCodeNot: [TokenParam] = [],
        serviceCategory: [TokenParam] = [],
        serviceCategoryNot: [TokenParam] = [],
        partStatus: [TokenParam] = [],
        partStatusNot: [TokenParam] = [],
        supportingInfo: String? = nil,
        basedOn: String? = nil,
        reasonReference: String? = nil,
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
        self.patient          = patient
        self.actor            = actor
        self.practitioner     = practitioner
        self.location         = location
        self.status           = status
        self.statusNot        = statusNot
        self.identifier       = identifier
        self.identifierNot    = identifierNot
        self.date             = date
        self.serviceType      = serviceType
        self.serviceTypeNot   = serviceTypeNot
        self.appointmentType  = appointmentType
        self.appointmentTypeNot = appointmentTypeNot
        self.specialty        = specialty
        self.specialtyNot     = specialtyNot
        self.reasonCode       = reasonCode
        self.reasonCodeNot    = reasonCodeNot
        self.serviceCategory  = serviceCategory
        self.serviceCategoryNot = serviceCategoryNot
        self.partStatus       = partStatus
        self.partStatusNot    = partStatusNot
        self.supportingInfo   = supportingInfo
        self.basedOn          = basedOn
        self.reasonReference  = reasonReference
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
