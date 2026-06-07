import Foundation
import Logging
import PostgresNIO

/// Holds every resource store. Pass one value instead of 23+ individual parameters.
/// Adding a future resource only requires adding one property here; wiring files stay stable.
public struct StoreContainer: Sendable {
    public let patient: PatientStore
    public let observation: ObservationStore
    public let encounter: EncounterStore
    public let condition: ConditionStore
    public let medication: MedicationStore
    public let medicationRequest: MedicationRequestStore
    public let allergyIntolerance: AllergyIntoleranceStore
    public let procedure: ProcedureStore
    public let diagnosticReport: DiagnosticReportStore
    public let immunization: ImmunizationStore
    public let practitioner: PractitionerStore
    public let organization: OrganizationStore
    public let location: LocationStore
    public let relatedPerson: RelatedPersonStore
    public let serviceRequest: ServiceRequestStore
    public let specimen: SpecimenStore
    public let documentReference: DocumentReferenceStore
    public let carePlan: CarePlanStore
    public let goal: GoalStore
    public let medicationStatement: MedicationStatementStore
    public let familyMemberHistory: FamilyMemberHistoryStore
    public let appointment: AppointmentStore
    public let medicationAdministration: MedicationAdministrationStore

    public init(client: PostgresClient, logger: Logger) {
        patient                = PatientStore(client: client, logger: logger)
        observation            = ObservationStore(client: client, logger: logger)
        encounter              = EncounterStore(client: client, logger: logger)
        condition              = ConditionStore(client: client, logger: logger)
        medication             = MedicationStore(client: client, logger: logger)
        medicationRequest      = MedicationRequestStore(client: client, logger: logger)
        allergyIntolerance     = AllergyIntoleranceStore(client: client, logger: logger)
        procedure              = ProcedureStore(client: client, logger: logger)
        diagnosticReport       = DiagnosticReportStore(client: client, logger: logger)
        immunization           = ImmunizationStore(client: client, logger: logger)
        practitioner           = PractitionerStore(client: client, logger: logger)
        organization           = OrganizationStore(client: client, logger: logger)
        location               = LocationStore(client: client, logger: logger)
        relatedPerson          = RelatedPersonStore(client: client, logger: logger)
        serviceRequest         = ServiceRequestStore(client: client, logger: logger)
        specimen               = SpecimenStore(client: client, logger: logger)
        documentReference      = DocumentReferenceStore(client: client, logger: logger)
        carePlan               = CarePlanStore(client: client, logger: logger)
        goal                   = GoalStore(client: client, logger: logger)
        medicationStatement    = MedicationStatementStore(client: client, logger: logger)
        familyMemberHistory    = FamilyMemberHistoryStore(client: client, logger: logger)
        appointment            = AppointmentStore(client: client, logger: logger)
        medicationAdministration = MedicationAdministrationStore(client: client, logger: logger)
    }
}
