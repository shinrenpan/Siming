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
    medicationRequestStore: MedicationRequestStore,
    allergyIntoleranceStore: AllergyIntoleranceStore,
    logger: Logger
) {
    // GET /_history — system-level history across all resource types
    router.get("_history") { request, _ in
        let qp = request.uri.queryParameters
        let since: Date? = qp["_since"].flatMap { parseFHIRInstant(String($0)) }
        let count = min(qp["_count"].flatMap { Int($0) } ?? 50, 100)

        async let patientEntries   = patientStore.typeHistory(since: since, count: count)
        async let obsEntries       = observationStore.typeHistory(since: since, count: count)
        async let encEntries       = encounterStore.typeHistory(since: since, count: count)
        async let conEntries       = conditionStore.typeHistory(since: since, count: count)
        async let medEntries       = medicationRequestStore.typeHistory(since: since, count: count)
        async let allergyEntries   = allergyIntoleranceStore.typeHistory(since: since, count: count)

        let all = try await (
            patientEntries + obsEntries + encEntries + conEntries + medEntries + allergyEntries
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
