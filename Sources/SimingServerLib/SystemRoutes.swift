import Foundation
import Hummingbird
import Logging
import NIOCore
import SimingCore

public func addSystemRoutes(
    to router: Router<BasicRequestContext>,
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
    logger: Logger
) {
    // GET /_history — system-level history across all resource types
    // Supports: _since, _count, _type (comma-separated resource type filter)
    router.get("_history") { request, _ in
        let qp = request.uri.queryParameters
        let since: Date? = qp["_since"].flatMap { parseFHIRInstant(String($0)) }
        let count = min(qp["_count"].flatMap { Int($0) } ?? 50, 100)

        // _type: filter by resource type (e.g. _type=Patient,Observation)
        let typeFilter: Set<String>?
        if let typeParam = qp["_type"].map(String.init), !typeParam.isEmpty {
            typeFilter = Set(typeParam.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) })
        } else {
            typeFilter = nil
        }
        func include(_ type: String) -> Bool { typeFilter == nil || typeFilter!.contains(type) }

        async let patientEntries   = include("Patient")             ? patientStore.typeHistory(since: since, count: count)             : []
        async let obsEntries       = include("Observation")         ? observationStore.typeHistory(since: since, count: count)         : []
        async let encEntries       = include("Encounter")           ? encounterStore.typeHistory(since: since, count: count)           : []
        async let conEntries       = include("Condition")           ? conditionStore.typeHistory(since: since, count: count)           : []
        async let medBaseEntries   = include("Medication")          ? medicationStore.typeHistory(since: since, count: count)          : []
        async let medEntries       = include("MedicationRequest")   ? medicationRequestStore.typeHistory(since: since, count: count)   : []
        async let allergyEntries   = include("AllergyIntolerance")  ? allergyIntoleranceStore.typeHistory(since: since, count: count)  : []
        async let procEntries      = include("Procedure")           ? procedureStore.typeHistory(since: since, count: count)           : []
        async let drEntries        = include("DiagnosticReport")    ? diagnosticReportStore.typeHistory(since: since, count: count)    : []
        async let immEntries       = include("Immunization")        ? immunizationStore.typeHistory(since: since, count: count)        : []
        async let pracEntries      = include("Practitioner")        ? practitionerStore.typeHistory(since: since, count: count)        : []
        async let orgEntries       = include("Organization")        ? organizationStore.typeHistory(since: since, count: count)        : []
        async let locEntries       = include("Location")            ? locationStore.typeHistory(since: since, count: count)            : []

        let all = try await (
            patientEntries + obsEntries + encEntries + conEntries + medBaseEntries + medEntries + allergyEntries
            + procEntries + drEntries + immEntries + pracEntries + orgEntries + locEntries
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
