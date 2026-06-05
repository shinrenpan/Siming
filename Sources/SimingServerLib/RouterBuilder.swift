import Hummingbird
import Logging
import Prometheus
import SimingCore

public func buildRouter(
    patientStore: PatientStore,
    observationStore: ObservationStore,
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
    addCompartmentRoutes(to: router, observationStore: observationStore, logger: logger)
    addSystemRoutes(to: router, patientStore: patientStore, observationStore: observationStore, logger: logger)
    return router
}
