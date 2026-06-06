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
    addCompartmentRoutes(to: router, observationStore: observationStore,
                         encounterStore: encounterStore, conditionStore: conditionStore,
                         medicationRequestStore: medicationRequestStore,
                         allergyIntoleranceStore: allergyIntoleranceStore, logger: logger)
    addSystemRoutes(to: router, patientStore: patientStore, observationStore: observationStore, logger: logger)
    return router
}
