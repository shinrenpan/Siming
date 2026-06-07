import Foundation
import Hummingbird
import Logging
import NIOCore
import SimingCore

public func addSystemRoutes(
    to router: Router<BasicRequestContext>,
    stores: StoreContainer,
    logger: Logger
) {
    // GET /_history — system-level history across all resource types
    // Supports: _since, _count, _type (comma-separated resource type filter)
    router.get("_history") { request, _ in
        let qp = request.uri.queryParameters
        let since: Date? = qp["_since"].flatMap { parseFHIRInstant(String($0)) }
        let count = min(qp["_count"].flatMap { Int($0) } ?? 50, 100)

        let typeFilter: Set<String>?
        if let typeParam = qp["_type"].map(String.init), !typeParam.isEmpty {
            typeFilter = Set(typeParam.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) })
        } else {
            typeFilter = nil
        }
        func include(_ type: String) -> Bool { typeFilter == nil || typeFilter!.contains(type) }

        async let patientEntries   = include("Patient")                  ? stores.patient.typeHistory(since: since, count: count)                  : []
        async let obsEntries       = include("Observation")              ? stores.observation.typeHistory(since: since, count: count)              : []
        async let encEntries       = include("Encounter")                ? stores.encounter.typeHistory(since: since, count: count)                : []
        async let conEntries       = include("Condition")                ? stores.condition.typeHistory(since: since, count: count)                : []
        async let medBaseEntries   = include("Medication")               ? stores.medication.typeHistory(since: since, count: count)               : []
        async let medEntries       = include("MedicationRequest")        ? stores.medicationRequest.typeHistory(since: since, count: count)        : []
        async let allergyEntries   = include("AllergyIntolerance")       ? stores.allergyIntolerance.typeHistory(since: since, count: count)       : []
        async let procEntries      = include("Procedure")                ? stores.procedure.typeHistory(since: since, count: count)                : []
        async let drEntries        = include("DiagnosticReport")         ? stores.diagnosticReport.typeHistory(since: since, count: count)         : []
        async let immEntries       = include("Immunization")             ? stores.immunization.typeHistory(since: since, count: count)             : []
        async let pracEntries      = include("Practitioner")             ? stores.practitioner.typeHistory(since: since, count: count)             : []
        async let orgEntries       = include("Organization")             ? stores.organization.typeHistory(since: since, count: count)             : []
        async let locEntries       = include("Location")                 ? stores.location.typeHistory(since: since, count: count)                 : []
        async let rpEntries        = include("RelatedPerson")            ? stores.relatedPerson.typeHistory(since: since, count: count)            : []
        async let srEntries        = include("ServiceRequest")           ? stores.serviceRequest.typeHistory(since: since, count: count)           : []
        async let specEntries      = include("Specimen")                 ? stores.specimen.typeHistory(since: since, count: count)                 : []
        async let docRefEntries    = include("DocumentReference")        ? stores.documentReference.typeHistory(since: since, count: count)        : []
        async let carePlanEntries  = include("CarePlan")                 ? stores.carePlan.typeHistory(since: since, count: count)                 : []
        async let goalEntries      = include("Goal")                     ? stores.goal.typeHistory(since: since, count: count)                     : []
        async let msEntries        = include("MedicationStatement")      ? stores.medicationStatement.typeHistory(since: since, count: count)      : []
        async let fmhEntries       = include("FamilyMemberHistory")      ? stores.familyMemberHistory.typeHistory(since: since, count: count)      : []
        async let apptEntries      = include("Appointment")              ? stores.appointment.typeHistory(since: since, count: count)              : []
        async let maEntries        = include("MedicationAdministration") ? stores.medicationAdministration.typeHistory(since: since, count: count) : []

        let all = try await (
            patientEntries + obsEntries + encEntries + conEntries + medBaseEntries + medEntries + allergyEntries
            + procEntries + drEntries + immEntries + pracEntries + orgEntries + locEntries + rpEntries
            + srEntries + specEntries + docRefEntries + carePlanEntries + goalEntries + msEntries
            + fmhEntries + apptEntries + maEntries
        )
        .sorted { $0.lastUpdated > $1.lastUpdated }
        .prefix(count)

        let authority = request.head.authority ?? "localhost"
        let baseURL = "http://\(authority)"
        let bundleData = buildHistoryBundleJSON(entries: Array(all), baseURL: baseURL)
        var headers = HTTPFields()
        headers[.contentType] = "application/fhir+json"
        return Response(status: .ok, headers: headers,
                        body: ResponseBody(byteBuffer: ByteBuffer(bytes: bundleData)))
    }
}
