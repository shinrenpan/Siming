import Hummingbird
import Logging
import Prometheus
import SimingCore

public func buildRouter(
    patientStore: PatientStore,
    observationStore: ObservationStore,
    encounterStore: EncounterStore,
    conditionStore: ConditionStore,
    medicationRequestStore: MedicationRequestStore,
    allergyIntoleranceStore: AllergyIntoleranceStore,
    procedureStore: ProcedureStore,
    diagnosticReportStore: DiagnosticReportStore,
    immunizationStore: ImmunizationStore,
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
    addMedicationRequestRoutes(to: router, store: medicationRequestStore, logger: logger)
    addAllergyIntoleranceRoutes(to: router, store: allergyIntoleranceStore, logger: logger)
    addProcedureRoutes(to: router, store: procedureStore, logger: logger)
    addDiagnosticReportRoutes(to: router, store: diagnosticReportStore, logger: logger)
    addImmunizationRoutes(to: router, store: immunizationStore, logger: logger)
    addCompartmentRoutes(to: router, observationStore: observationStore,
                         encounterStore: encounterStore, conditionStore: conditionStore,
                         medicationRequestStore: medicationRequestStore,
                         allergyIntoleranceStore: allergyIntoleranceStore,
                         procedureStore: procedureStore,
                         diagnosticReportStore: diagnosticReportStore,
                         immunizationStore: immunizationStore, logger: logger)
    addSystemRoutes(to: router, patientStore: patientStore, observationStore: observationStore,
                    encounterStore: encounterStore, conditionStore: conditionStore,
                    medicationRequestStore: medicationRequestStore,
                    allergyIntoleranceStore: allergyIntoleranceStore,
                    procedureStore: procedureStore,
                    diagnosticReportStore: diagnosticReportStore,
                    immunizationStore: immunizationStore, logger: logger)
    return router
}
