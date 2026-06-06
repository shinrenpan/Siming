import Hummingbird
import Logging
import Prometheus
import SimingCore

public func buildRouter(
    patientStore: PatientStore,
    observationStore: ObservationStore,
    encounterStore: EncounterStore,
    conditionStore: ConditionStore,
    medicationStore: MedicationStore,
    medicationRequestStore: MedicationRequestStore,
    allergyIntoleranceStore: AllergyIntoleranceStore,
    procedureStore: ProcedureStore,
    diagnosticReportStore: DiagnosticReportStore,
    immunizationStore: ImmunizationStore,
    practitionerStore: PractitionerStore,
    organizationStore: OrganizationStore,
    locationStore: LocationStore,
    relatedPersonStore: RelatedPersonStore,
    serviceRequestStore: ServiceRequestStore,
    specimenStore: SpecimenStore,
    documentReferenceStore: DocumentReferenceStore,
    carePlanStore: CarePlanStore,
    goalStore: GoalStore,
    medicationStatementStore: MedicationStatementStore,
    registry: PrometheusCollectorRegistry,
    logger: Logger
) -> Router<BasicRequestContext> {
    let router = Router()
    router.middlewares.add(MetricsMiddleware())
    router.middlewares.add(FormatMiddleware())
    router.get("health") { _, _ in HTTPResponse.Status.ok }
    addMetadataRoutes(to: router)
    addMetricsRoute(to: router, registry: registry)
    addPatientRoutes(to: router, store: patientStore, logger: logger)
    addObservationRoutes(to: router, store: observationStore, logger: logger)
    addEncounterRoutes(to: router, store: encounterStore, logger: logger)
    addConditionRoutes(to: router, store: conditionStore, logger: logger)
    addMedicationRoutes(to: router, store: medicationStore, logger: logger)
    addMedicationRequestRoutes(to: router, store: medicationRequestStore, logger: logger)
    addAllergyIntoleranceRoutes(to: router, store: allergyIntoleranceStore, logger: logger)
    addProcedureRoutes(to: router, store: procedureStore, logger: logger)
    addDiagnosticReportRoutes(to: router, store: diagnosticReportStore, logger: logger)
    addImmunizationRoutes(to: router, store: immunizationStore, logger: logger)
    addPractitionerRoutes(to: router, store: practitionerStore, logger: logger)
    addOrganizationRoutes(to: router, store: organizationStore, logger: logger)
    addLocationRoutes(to: router, store: locationStore, logger: logger)
    addRelatedPersonRoutes(to: router, store: relatedPersonStore, logger: logger)
    addServiceRequestRoutes(to: router, store: serviceRequestStore, logger: logger)
    addSpecimenRoutes(to: router, store: specimenStore, logger: logger)
    addDocumentReferenceRoutes(to: router, store: documentReferenceStore, logger: logger)
    addCarePlanRoutes(to: router, store: carePlanStore, logger: logger)
    addGoalRoutes(to: router, store: goalStore, logger: logger)
    addMedicationStatementRoutes(to: router, store: medicationStatementStore, logger: logger)
    addCompartmentRoutes(to: router, observationStore: observationStore,
                         encounterStore: encounterStore, conditionStore: conditionStore,
                         medicationRequestStore: medicationRequestStore,
                         allergyIntoleranceStore: allergyIntoleranceStore,
                         procedureStore: procedureStore,
                         diagnosticReportStore: diagnosticReportStore,
                         immunizationStore: immunizationStore,
                         relatedPersonStore: relatedPersonStore,
                         serviceRequestStore: serviceRequestStore,
                         specimenStore: specimenStore,
                         documentReferenceStore: documentReferenceStore,
                         carePlanStore: carePlanStore,
                         goalStore: goalStore,
                         medicationStatementStore: medicationStatementStore,
                         logger: logger)
    addSystemRoutes(to: router, patientStore: patientStore, observationStore: observationStore,
                    encounterStore: encounterStore, conditionStore: conditionStore,
                    medicationStore: medicationStore,
                    medicationRequestStore: medicationRequestStore,
                    allergyIntoleranceStore: allergyIntoleranceStore,
                    procedureStore: procedureStore,
                    diagnosticReportStore: diagnosticReportStore,
                    immunizationStore: immunizationStore,
                    practitionerStore: practitionerStore,
                    organizationStore: organizationStore,
                    locationStore: locationStore,
                    relatedPersonStore: relatedPersonStore,
                    serviceRequestStore: serviceRequestStore,
                    specimenStore: specimenStore,
                    documentReferenceStore: documentReferenceStore,
                    carePlanStore: carePlanStore,
                    goalStore: goalStore,
                    medicationStatementStore: medicationStatementStore,
                    logger: logger)
    return router
}
