import Hummingbird
import Logging
import Prometheus
import SimingCore

public func buildRouter(
    stores: StoreContainer,
    registry: PrometheusCollectorRegistry,
    logger: Logger
) -> Router<BasicRequestContext> {
    let router = Router()
    router.middlewares.add(MetricsMiddleware())
    router.middlewares.add(FormatMiddleware())
    router.get("health") { _, _ in HTTPResponse.Status.ok }
    addMetadataRoutes(to: router)
    addMetricsRoute(to: router, registry: registry)
    addPatientRoutes(to: router, store: stores.patient, logger: logger)
    addObservationRoutes(to: router, store: stores.observation, logger: logger)
    addEncounterRoutes(to: router, store: stores.encounter, logger: logger)
    addConditionRoutes(to: router, store: stores.condition, logger: logger)
    addMedicationRoutes(to: router, store: stores.medication, logger: logger)
    addMedicationRequestRoutes(to: router, store: stores.medicationRequest, logger: logger)
    addAllergyIntoleranceRoutes(to: router, store: stores.allergyIntolerance, logger: logger)
    addProcedureRoutes(to: router, store: stores.procedure, logger: logger)
    addDiagnosticReportRoutes(to: router, store: stores.diagnosticReport, logger: logger)
    addImmunizationRoutes(to: router, store: stores.immunization, logger: logger)
    addPractitionerRoutes(to: router, store: stores.practitioner, logger: logger)
    addOrganizationRoutes(to: router, store: stores.organization, logger: logger)
    addLocationRoutes(to: router, store: stores.location, logger: logger)
    addRelatedPersonRoutes(to: router, store: stores.relatedPerson, logger: logger)
    addServiceRequestRoutes(to: router, store: stores.serviceRequest, logger: logger)
    addSpecimenRoutes(to: router, store: stores.specimen, logger: logger)
    addDocumentReferenceRoutes(to: router, store: stores.documentReference, logger: logger)
    addCarePlanRoutes(to: router, store: stores.carePlan, logger: logger)
    addGoalRoutes(to: router, store: stores.goal, logger: logger)
    addMedicationStatementRoutes(to: router, store: stores.medicationStatement, logger: logger)
    addFamilyMemberHistoryRoutes(to: router, store: stores.familyMemberHistory, logger: logger)
    addAppointmentRoutes(to: router, store: stores.appointment, logger: logger)
    addMedicationAdministrationRoutes(to: router, store: stores.medicationAdministration, logger: logger)
    addCompartmentRoutes(to: router, stores: stores, logger: logger)
    addSystemRoutes(to: router, stores: stores, logger: logger)
    return router
}
