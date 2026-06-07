import Foundation
import Hummingbird
import Logging
import NIOCore
import SimingCore

private let maxCount = 100
private let fhirJSON = "application/fhir+json"

/// Patient compartment searches for Observation, Encounter, Condition, MedicationRequest, AllergyIntolerance,
/// Procedure, DiagnosticReport, Immunization, RelatedPerson, ServiceRequest, Specimen, DocumentReference, CarePlan, Goal, MedicationStatement, FamilyMemberHistory, Appointment, MedicationAdministration.
/// Forces subject/patient=Patient/:patientId server-side; client cannot override.
public func addCompartmentRoutes(
    to router: Router<BasicRequestContext>,
    observationStore: ObservationStore,
    encounterStore: EncounterStore,
    conditionStore: ConditionStore,
    medicationRequestStore: MedicationRequestStore,
    allergyIntoleranceStore: AllergyIntoleranceStore,
    procedureStore: ProcedureStore,
    diagnosticReportStore: DiagnosticReportStore,
    immunizationStore: ImmunizationStore,
    relatedPersonStore: RelatedPersonStore,
    serviceRequestStore: ServiceRequestStore,
    specimenStore: SpecimenStore,
    documentReferenceStore: DocumentReferenceStore,
    carePlanStore: CarePlanStore,
    goalStore: GoalStore,
    medicationStatementStore: MedicationStatementStore,
    familyMemberHistoryStore: FamilyMemberHistoryStore,
    appointmentStore: AppointmentStore,
    medicationAdministrationStore: MedicationAdministrationStore,
    logger: Logger
) {
    let group = router.group("Patient")

    group.get(":id/Observation") { request, context in
        let patientId = context.parameters.get("id") ?? ""
        let pairs = request.uri.queryParameters.map { (key: $0.key, value: $0.value) }
        if isStrictHandling(request) {
            let bad = unknownParams(in: pairs, known: knownObservationParams)
            if !bad.isEmpty { throw FHIRRouteError.unknownParams(bad) }
        }
        var query = parseObservationQuery(from: pairs)
        query.subject = "Patient/\(patientId)"
        let elements = parseElements(from: pairs)
        let summary = parseSummary(from: pairs)
        let result = try await observationStore.search(query: query)

        let base = selfURL(request)
        let baseURL = serverBaseURL(request)
        if summary == .count {
            let bundleData = buildBundleJSON(entries: [], total: result.total,
                                             selfURL: base, nextURL: nil)
            var headers = HTTPFields()
            headers[.contentType] = fhirJSON
            return Response(status: .ok, headers: headers,
                            body: ResponseBody(byteBuffer: ByteBuffer(bytes: bundleData)))
        }
        let nextURL = result.nextCursor.map { nextPageURL(selfURL: base, cursor: $0, count: query.count) }
        let entries = result.entries.map { e -> (fullUrl: String, json: Data) in
            var json = e.jsonWithMeta
            if let s = summary, s != .false {
                json = applySummary(json, mode: s, summaryFields: observationSummaryFields)
            }
            if let elems = elements { json = applyElements(json, elements: elems) }
            return ("\(baseURL)/Observation/\(e.id)", json)
        }
        let bundleData = buildBundleJSON(entries: entries, total: result.total,
                                         selfURL: base, nextURL: nextURL)
        var headers = HTTPFields()
        headers[.contentType] = fhirJSON
        return Response(status: .ok, headers: headers,
                        body: ResponseBody(byteBuffer: ByteBuffer(bytes: bundleData)))
    }

    // POST /Patient/:patientId/Observation/_search — compartment form-encoded search
    group.post(":id/Observation/_search") { request, context in
        let patientId = context.parameters.get("id") ?? ""
        let ct = request.headers[.contentType] ?? ""
        guard ct.contains("application/x-www-form-urlencoded") else {
            throw FHIRRouteError.invalidBody("Content-Type must be application/x-www-form-urlencoded for _search")
        }
        var req = request
        let bodyBuffer = try await req.collectBody(upTo: 1 * 1024 * 1024)
        let urlPairs = request.uri.queryParameters.map { (key: $0.key, value: $0.value) }
        let pairs = urlPairs + parseFormPairs(from: bodyBuffer)
        if isStrictHandling(request) {
            let bad = unknownParams(in: pairs, known: knownObservationParams)
            if !bad.isEmpty { throw FHIRRouteError.unknownParams(bad) }
        }
        var query = parseObservationQuery(from: pairs)
        query.subject = "Patient/\(patientId)"
        let elements = parseElements(from: pairs)
        let summary = parseSummary(from: pairs)
        let result = try await observationStore.search(query: query)

        let base = selfURL(request)
        let baseURL = serverBaseURL(request)
        if summary == .count {
            let bundleData = buildBundleJSON(entries: [], total: result.total,
                                             selfURL: base, nextURL: nil)
            var headers = HTTPFields()
            headers[.contentType] = fhirJSON
            return Response(status: .ok, headers: headers,
                            body: ResponseBody(byteBuffer: ByteBuffer(bytes: bundleData)))
        }
        let nextURL = result.nextCursor.map { nextPageURL(selfURL: base, cursor: $0, count: query.count) }
        let entries = result.entries.map { e -> (fullUrl: String, json: Data) in
            var json = e.jsonWithMeta
            if let s = summary, s != .false {
                json = applySummary(json, mode: s, summaryFields: observationSummaryFields)
            }
            if let elems = elements { json = applyElements(json, elements: elems) }
            return ("\(baseURL)/Observation/\(e.id)", json)
        }
        let bundleData = buildBundleJSON(entries: entries, total: result.total,
                                         selfURL: base, nextURL: nextURL)
        var headers = HTTPFields()
        headers[.contentType] = fhirJSON
        return Response(status: .ok, headers: headers,
                        body: ResponseBody(byteBuffer: ByteBuffer(bytes: bundleData)))
    }

    // GET /Patient/:patientId/Encounter — compartment search
    group.get(":id/Encounter") { request, context in
        let patientId = context.parameters.get("id") ?? ""
        let pairs = request.uri.queryParameters.map { (key: $0.key, value: $0.value) }
        if isStrictHandling(request) {
            let bad = unknownParams(in: pairs, known: knownEncounterParams)
            if !bad.isEmpty { throw FHIRRouteError.unknownParams(bad) }
        }
        var query = parseEncounterQuery(from: pairs)
        query.subject = "Patient/\(patientId)"
        let elements = parseElements(from: pairs)
        let summary = parseSummary(from: pairs)
        let result = try await encounterStore.search(query: query)

        let base = selfURL(request)
        let baseURL = serverBaseURL(request)
        if summary == .count {
            let bundleData = buildBundleJSON(entries: [], total: result.total, selfURL: base, nextURL: nil)
            var headers = HTTPFields()
            headers[.contentType] = fhirJSON
            return Response(status: .ok, headers: headers,
                            body: ResponseBody(byteBuffer: ByteBuffer(bytes: bundleData)))
        }
        let nextURL = result.nextCursor.map { nextPageURL(selfURL: base, cursor: $0, count: query.count) }
        let entries = result.entries.map { e -> (fullUrl: String, json: Data) in
            var json = e.jsonWithMeta
            if let s = summary, s != .false {
                json = applySummary(json, mode: s, summaryFields: encounterSummaryFields)
            }
            if let elems = elements { json = applyElements(json, elements: elems) }
            return ("\(baseURL)/Encounter/\(e.id)", json)
        }
        let bundleData = buildBundleJSON(entries: entries, total: result.total, selfURL: base, nextURL: nextURL)
        var headers = HTTPFields()
        headers[.contentType] = fhirJSON
        return Response(status: .ok, headers: headers,
                        body: ResponseBody(byteBuffer: ByteBuffer(bytes: bundleData)))
    }

    // POST /Patient/:patientId/Encounter/_search — compartment form-encoded search
    group.post(":id/Encounter/_search") { request, context in
        let patientId = context.parameters.get("id") ?? ""
        let ct = request.headers[.contentType] ?? ""
        guard ct.contains("application/x-www-form-urlencoded") else {
            throw FHIRRouteError.invalidBody("Content-Type must be application/x-www-form-urlencoded for _search")
        }
        var req = request
        let bodyBuffer = try await req.collectBody(upTo: 1 * 1024 * 1024)
        let urlPairs = request.uri.queryParameters.map { (key: $0.key, value: $0.value) }
        let pairs = urlPairs + parseFormPairs(from: bodyBuffer)
        if isStrictHandling(request) {
            let bad = unknownParams(in: pairs, known: knownEncounterParams)
            if !bad.isEmpty { throw FHIRRouteError.unknownParams(bad) }
        }
        var query = parseEncounterQuery(from: pairs)
        query.subject = "Patient/\(patientId)"
        let elements = parseElements(from: pairs)
        let summary = parseSummary(from: pairs)
        let result = try await encounterStore.search(query: query)

        let base = selfURL(request)
        let baseURL = serverBaseURL(request)
        if summary == .count {
            let bundleData = buildBundleJSON(entries: [], total: result.total, selfURL: base, nextURL: nil)
            var headers = HTTPFields()
            headers[.contentType] = fhirJSON
            return Response(status: .ok, headers: headers,
                            body: ResponseBody(byteBuffer: ByteBuffer(bytes: bundleData)))
        }
        let nextURL = result.nextCursor.map { nextPageURL(selfURL: base, cursor: $0, count: query.count) }
        let entries = result.entries.map { e -> (fullUrl: String, json: Data) in
            var json = e.jsonWithMeta
            if let s = summary, s != .false {
                json = applySummary(json, mode: s, summaryFields: encounterSummaryFields)
            }
            if let elems = elements { json = applyElements(json, elements: elems) }
            return ("\(baseURL)/Encounter/\(e.id)", json)
        }
        let bundleData = buildBundleJSON(entries: entries, total: result.total, selfURL: base, nextURL: nextURL)
        var headers = HTTPFields()
        headers[.contentType] = fhirJSON
        return Response(status: .ok, headers: headers,
                        body: ResponseBody(byteBuffer: ByteBuffer(bytes: bundleData)))
    }

    // GET /Patient/:patientId/Condition — compartment search
    group.get(":id/Condition") { request, context in
        let patientId = context.parameters.get("id") ?? ""
        let pairs = request.uri.queryParameters.map { (key: $0.key, value: $0.value) }
        if isStrictHandling(request) {
            let bad = unknownParams(in: pairs, known: knownConditionParams)
            if !bad.isEmpty { throw FHIRRouteError.unknownParams(bad) }
        }
        var query = parseConditionQuery(from: pairs)
        query.subject = "Patient/\(patientId)"
        let elements = parseElements(from: pairs)
        let summary = parseSummary(from: pairs)
        let result = try await conditionStore.search(query: query)

        let base = selfURL(request)
        let baseURL = serverBaseURL(request)
        if summary == .count {
            let bundleData = buildBundleJSON(entries: [], total: result.total, selfURL: base, nextURL: nil)
            var headers = HTTPFields()
            headers[.contentType] = fhirJSON
            return Response(status: .ok, headers: headers,
                            body: ResponseBody(byteBuffer: ByteBuffer(bytes: bundleData)))
        }
        let nextURL = result.nextCursor.map { nextPageURL(selfURL: base, cursor: $0, count: query.count) }
        let entries = result.entries.map { e -> (fullUrl: String, json: Data) in
            var json = e.jsonWithMeta
            if let s = summary, s != .false {
                json = applySummary(json, mode: s, summaryFields: conditionSummaryFields)
            }
            if let elems = elements { json = applyElements(json, elements: elems) }
            return ("\(baseURL)/Condition/\(e.id)", json)
        }
        let bundleData = buildBundleJSON(entries: entries, total: result.total, selfURL: base, nextURL: nextURL)
        var headers = HTTPFields()
        headers[.contentType] = fhirJSON
        return Response(status: .ok, headers: headers,
                        body: ResponseBody(byteBuffer: ByteBuffer(bytes: bundleData)))
    }

    // POST /Patient/:patientId/Condition/_search — compartment form-encoded search
    group.post(":id/Condition/_search") { request, context in
        let patientId = context.parameters.get("id") ?? ""
        let ct = request.headers[.contentType] ?? ""
        guard ct.contains("application/x-www-form-urlencoded") else {
            throw FHIRRouteError.invalidBody("Content-Type must be application/x-www-form-urlencoded for _search")
        }
        var req = request
        let bodyBuffer = try await req.collectBody(upTo: 1 * 1024 * 1024)
        let urlPairs = request.uri.queryParameters.map { (key: $0.key, value: $0.value) }
        let pairs = urlPairs + parseFormPairs(from: bodyBuffer)
        if isStrictHandling(request) {
            let bad = unknownParams(in: pairs, known: knownConditionParams)
            if !bad.isEmpty { throw FHIRRouteError.unknownParams(bad) }
        }
        var query = parseConditionQuery(from: pairs)
        query.subject = "Patient/\(patientId)"
        let elements = parseElements(from: pairs)
        let summary = parseSummary(from: pairs)
        let result = try await conditionStore.search(query: query)

        let base = selfURL(request)
        let baseURL = serverBaseURL(request)
        if summary == .count {
            let bundleData = buildBundleJSON(entries: [], total: result.total, selfURL: base, nextURL: nil)
            var headers = HTTPFields()
            headers[.contentType] = fhirJSON
            return Response(status: .ok, headers: headers,
                            body: ResponseBody(byteBuffer: ByteBuffer(bytes: bundleData)))
        }
        let nextURL = result.nextCursor.map { nextPageURL(selfURL: base, cursor: $0, count: query.count) }
        let entries = result.entries.map { e -> (fullUrl: String, json: Data) in
            var json = e.jsonWithMeta
            if let s = summary, s != .false {
                json = applySummary(json, mode: s, summaryFields: conditionSummaryFields)
            }
            if let elems = elements { json = applyElements(json, elements: elems) }
            return ("\(baseURL)/Condition/\(e.id)", json)
        }
        let bundleData = buildBundleJSON(entries: entries, total: result.total, selfURL: base, nextURL: nextURL)
        var headers = HTTPFields()
        headers[.contentType] = fhirJSON
        return Response(status: .ok, headers: headers,
                        body: ResponseBody(byteBuffer: ByteBuffer(bytes: bundleData)))
    }

    // POST /Patient/:patientId/MedicationRequest/_search — compartment form-encoded search
    group.post(":id/MedicationRequest/_search") { request, context in
        let patientId = context.parameters.get("id") ?? ""
        let ct = request.headers[.contentType] ?? ""
        guard ct.contains("application/x-www-form-urlencoded") else {
            throw FHIRRouteError.invalidBody("Content-Type must be application/x-www-form-urlencoded for _search")
        }
        var req = request
        let bodyBuffer = try await req.collectBody(upTo: 1 * 1024 * 1024)
        let urlPairs = request.uri.queryParameters.map { (key: $0.key, value: $0.value) }
        let pairs = urlPairs + parseFormPairs(from: bodyBuffer)
        if isStrictHandling(request) {
            let bad = unknownParams(in: pairs, known: knownMedicationRequestParams)
            if !bad.isEmpty { throw FHIRRouteError.unknownParams(bad) }
        }
        var query = parseMedicationRequestQuery(from: pairs)
        query.subject = "Patient/\(patientId)"
        let elements = parseElements(from: pairs)
        let summary = parseSummary(from: pairs)
        let result = try await medicationRequestStore.search(query: query)

        let base = selfURL(request)
        let baseURL = serverBaseURL(request)
        if summary == .count {
            let bundleData = buildBundleJSON(entries: [], total: result.total, selfURL: base, nextURL: nil)
            var headers = HTTPFields()
            headers[.contentType] = fhirJSON
            return Response(status: .ok, headers: headers,
                            body: ResponseBody(byteBuffer: ByteBuffer(bytes: bundleData)))
        }
        let nextURL = result.nextCursor.map { nextPageURL(selfURL: base, cursor: $0, count: query.count) }
        let entries = result.entries.map { e -> (fullUrl: String, json: Data) in
            var json = e.jsonWithMeta
            if let s = summary, s != .false {
                json = applySummary(json, mode: s, summaryFields: medicationRequestSummaryFields)
            }
            if let elems = elements { json = applyElements(json, elements: elems) }
            return ("\(baseURL)/MedicationRequest/\(e.id)", json)
        }
        let bundleData = buildBundleJSON(entries: entries, total: result.total, selfURL: base, nextURL: nextURL)
        var headers = HTTPFields()
        headers[.contentType] = fhirJSON
        return Response(status: .ok, headers: headers,
                        body: ResponseBody(byteBuffer: ByteBuffer(bytes: bundleData)))
    }

    // GET /Patient/:patientId/MedicationRequest — compartment search
    group.get(":id/MedicationRequest") { request, context in
        let patientId = context.parameters.get("id") ?? ""
        let pairs = request.uri.queryParameters.map { (key: $0.key, value: $0.value) }
        if isStrictHandling(request) {
            let bad = unknownParams(in: pairs, known: knownMedicationRequestParams)
            if !bad.isEmpty { throw FHIRRouteError.unknownParams(bad) }
        }
        var query = parseMedicationRequestQuery(from: pairs)
        query.subject = "Patient/\(patientId)"
        let elements = parseElements(from: pairs)
        let summary = parseSummary(from: pairs)
        let result = try await medicationRequestStore.search(query: query)

        let base = selfURL(request)
        let baseURL = serverBaseURL(request)
        if summary == .count {
            let bundleData = buildBundleJSON(entries: [], total: result.total, selfURL: base, nextURL: nil)
            var headers = HTTPFields()
            headers[.contentType] = fhirJSON
            return Response(status: .ok, headers: headers,
                            body: ResponseBody(byteBuffer: ByteBuffer(bytes: bundleData)))
        }
        let nextURL = result.nextCursor.map { nextPageURL(selfURL: base, cursor: $0, count: query.count) }
        let entries = result.entries.map { e -> (fullUrl: String, json: Data) in
            var json = e.jsonWithMeta
            if let s = summary, s != .false {
                json = applySummary(json, mode: s, summaryFields: medicationRequestSummaryFields)
            }
            if let elems = elements { json = applyElements(json, elements: elems) }
            return ("\(baseURL)/MedicationRequest/\(e.id)", json)
        }
        let bundleData = buildBundleJSON(entries: entries, total: result.total, selfURL: base, nextURL: nextURL)
        var headers = HTTPFields()
        headers[.contentType] = fhirJSON
        return Response(status: .ok, headers: headers,
                        body: ResponseBody(byteBuffer: ByteBuffer(bytes: bundleData)))
    }

    // POST /Patient/:patientId/AllergyIntolerance/_search — compartment form-encoded search
    group.post(":id/AllergyIntolerance/_search") { request, context in
        let patientId = context.parameters.get("id") ?? ""
        let ct = request.headers[.contentType] ?? ""
        guard ct.contains("application/x-www-form-urlencoded") else {
            throw FHIRRouteError.invalidBody("Content-Type must be application/x-www-form-urlencoded for _search")
        }
        var req = request
        let bodyBuffer = try await req.collectBody(upTo: 1 * 1024 * 1024)
        let urlPairs = request.uri.queryParameters.map { (key: $0.key, value: $0.value) }
        let pairs = urlPairs + parseFormPairs(from: bodyBuffer)
        if isStrictHandling(request) {
            let bad = unknownParams(in: pairs, known: knownAllergyIntoleranceParams)
            if !bad.isEmpty { throw FHIRRouteError.unknownParams(bad) }
        }
        var query = parseAllergyIntoleranceQuery(from: pairs)
        query.subject = "Patient/\(patientId)"
        let elements = parseElements(from: pairs)
        let summary = parseSummary(from: pairs)
        let result = try await allergyIntoleranceStore.search(query: query)

        let base = selfURL(request)
        let baseURL = serverBaseURL(request)
        if summary == .count {
            let bundleData = buildBundleJSON(entries: [], total: result.total, selfURL: base, nextURL: nil)
            var headers = HTTPFields()
            headers[.contentType] = fhirJSON
            return Response(status: .ok, headers: headers,
                            body: ResponseBody(byteBuffer: ByteBuffer(bytes: bundleData)))
        }
        let nextURL = result.nextCursor.map { nextPageURL(selfURL: base, cursor: $0, count: query.count) }
        let entries = result.entries.map { e -> (fullUrl: String, json: Data) in
            var json = e.jsonWithMeta
            if let s = summary, s != .false {
                json = applySummary(json, mode: s, summaryFields: allergyIntoleranceSummaryFields)
            }
            if let elems = elements { json = applyElements(json, elements: elems) }
            return ("\(baseURL)/AllergyIntolerance/\(e.id)", json)
        }
        let bundleData = buildBundleJSON(entries: entries, total: result.total, selfURL: base, nextURL: nextURL)
        var headers = HTTPFields()
        headers[.contentType] = fhirJSON
        return Response(status: .ok, headers: headers,
                        body: ResponseBody(byteBuffer: ByteBuffer(bytes: bundleData)))
    }

    // GET /Patient/:patientId/AllergyIntolerance — compartment search
    group.get(":id/AllergyIntolerance") { request, context in
        let patientId = context.parameters.get("id") ?? ""
        let pairs = request.uri.queryParameters.map { (key: $0.key, value: $0.value) }
        if isStrictHandling(request) {
            let bad = unknownParams(in: pairs, known: knownAllergyIntoleranceParams)
            if !bad.isEmpty { throw FHIRRouteError.unknownParams(bad) }
        }
        var query = parseAllergyIntoleranceQuery(from: pairs)
        query.subject = "Patient/\(patientId)"
        let elements = parseElements(from: pairs)
        let summary = parseSummary(from: pairs)
        let result = try await allergyIntoleranceStore.search(query: query)

        let base = selfURL(request)
        let baseURL = serverBaseURL(request)
        if summary == .count {
            let bundleData = buildBundleJSON(entries: [], total: result.total, selfURL: base, nextURL: nil)
            var headers = HTTPFields()
            headers[.contentType] = fhirJSON
            return Response(status: .ok, headers: headers,
                            body: ResponseBody(byteBuffer: ByteBuffer(bytes: bundleData)))
        }
        let nextURL = result.nextCursor.map { nextPageURL(selfURL: base, cursor: $0, count: query.count) }
        let entries = result.entries.map { e -> (fullUrl: String, json: Data) in
            var json = e.jsonWithMeta
            if let s = summary, s != .false {
                json = applySummary(json, mode: s, summaryFields: allergyIntoleranceSummaryFields)
            }
            if let elems = elements { json = applyElements(json, elements: elems) }
            return ("\(baseURL)/AllergyIntolerance/\(e.id)", json)
        }
        let bundleData = buildBundleJSON(entries: entries, total: result.total, selfURL: base, nextURL: nextURL)
        var headers = HTTPFields()
        headers[.contentType] = fhirJSON
        return Response(status: .ok, headers: headers,
                        body: ResponseBody(byteBuffer: ByteBuffer(bytes: bundleData)))
    }

    // GET /Patient/:patientId/Procedure — compartment search
    group.get(":id/Procedure") { request, context in
        let patientId = context.parameters.get("id") ?? ""
        let pairs = request.uri.queryParameters.map { (key: $0.key, value: $0.value) }
        if isStrictHandling(request) {
            let bad = unknownParams(in: pairs, known: knownProcedureParams)
            if !bad.isEmpty { throw FHIRRouteError.unknownParams(bad) }
        }
        var query = parseProcedureQuery(from: pairs)
        query.subject = "Patient/\(patientId)"
        let elements = parseElements(from: pairs)
        let summary = parseSummary(from: pairs)
        let result = try await procedureStore.search(query: query)

        let base = selfURL(request)
        let baseURL = serverBaseURL(request)
        if summary == .count {
            let bundleData = buildBundleJSON(entries: [], total: result.total, selfURL: base, nextURL: nil)
            var headers = HTTPFields()
            headers[.contentType] = fhirJSON
            return Response(status: .ok, headers: headers,
                            body: ResponseBody(byteBuffer: ByteBuffer(bytes: bundleData)))
        }
        let nextURL = result.nextCursor.map { nextPageURL(selfURL: base, cursor: $0, count: query.count) }
        let entries = result.entries.map { e -> (fullUrl: String, json: Data) in
            var json = e.jsonWithMeta
            if let s = summary, s != .false {
                json = applySummary(json, mode: s, summaryFields: procedureSummaryFields)
            }
            if let elems = elements { json = applyElements(json, elements: elems) }
            return ("\(baseURL)/Procedure/\(e.id)", json)
        }
        let bundleData = buildBundleJSON(entries: entries, total: result.total, selfURL: base, nextURL: nextURL)
        var headers = HTTPFields()
        headers[.contentType] = fhirJSON
        return Response(status: .ok, headers: headers,
                        body: ResponseBody(byteBuffer: ByteBuffer(bytes: bundleData)))
    }

    // POST /Patient/:patientId/Procedure/_search — compartment form-encoded search
    group.post(":id/Procedure/_search") { request, context in
        let patientId = context.parameters.get("id") ?? ""
        let ct = request.headers[.contentType] ?? ""
        guard ct.contains("application/x-www-form-urlencoded") else {
            throw FHIRRouteError.invalidBody("Content-Type must be application/x-www-form-urlencoded for _search")
        }
        var req = request
        let bodyBuffer = try await req.collectBody(upTo: 1 * 1024 * 1024)
        let urlPairs = request.uri.queryParameters.map { (key: $0.key, value: $0.value) }
        let pairs = urlPairs + parseFormPairs(from: bodyBuffer)
        if isStrictHandling(request) {
            let bad = unknownParams(in: pairs, known: knownProcedureParams)
            if !bad.isEmpty { throw FHIRRouteError.unknownParams(bad) }
        }
        var query = parseProcedureQuery(from: pairs)
        query.subject = "Patient/\(patientId)"
        let elements = parseElements(from: pairs)
        let summary = parseSummary(from: pairs)
        let result = try await procedureStore.search(query: query)

        let base = selfURL(request)
        let baseURL = serverBaseURL(request)
        if summary == .count {
            let bundleData = buildBundleJSON(entries: [], total: result.total, selfURL: base, nextURL: nil)
            var headers = HTTPFields()
            headers[.contentType] = fhirJSON
            return Response(status: .ok, headers: headers,
                            body: ResponseBody(byteBuffer: ByteBuffer(bytes: bundleData)))
        }
        let nextURL = result.nextCursor.map { nextPageURL(selfURL: base, cursor: $0, count: query.count) }
        let entries = result.entries.map { e -> (fullUrl: String, json: Data) in
            var json = e.jsonWithMeta
            if let s = summary, s != .false {
                json = applySummary(json, mode: s, summaryFields: procedureSummaryFields)
            }
            if let elems = elements { json = applyElements(json, elements: elems) }
            return ("\(baseURL)/Procedure/\(e.id)", json)
        }
        let bundleData = buildBundleJSON(entries: entries, total: result.total, selfURL: base, nextURL: nextURL)
        var headers = HTTPFields()
        headers[.contentType] = fhirJSON
        return Response(status: .ok, headers: headers,
                        body: ResponseBody(byteBuffer: ByteBuffer(bytes: bundleData)))
    }

    // GET /Patient/:patientId/DiagnosticReport — compartment search
    group.get(":id/DiagnosticReport") { request, context in
        let patientId = context.parameters.get("id") ?? ""
        let pairs = request.uri.queryParameters.map { (key: $0.key, value: $0.value) }
        if isStrictHandling(request) {
            let bad = unknownParams(in: pairs, known: knownDiagnosticReportParams)
            if !bad.isEmpty { throw FHIRRouteError.unknownParams(bad) }
        }
        var query = parseDiagnosticReportQuery(from: pairs)
        query.subject = "Patient/\(patientId)"
        let elements = parseElements(from: pairs)
        let summary = parseSummary(from: pairs)
        let result = try await diagnosticReportStore.search(query: query)

        let base = selfURL(request)
        let baseURL = serverBaseURL(request)
        if summary == .count {
            let bundleData = buildBundleJSON(entries: [], total: result.total, selfURL: base, nextURL: nil)
            var headers = HTTPFields()
            headers[.contentType] = fhirJSON
            return Response(status: .ok, headers: headers,
                            body: ResponseBody(byteBuffer: ByteBuffer(bytes: bundleData)))
        }
        let nextURL = result.nextCursor.map { nextPageURL(selfURL: base, cursor: $0, count: query.count) }
        let entries = result.entries.map { e -> (fullUrl: String, json: Data) in
            var json = e.jsonWithMeta
            if let s = summary, s != .false {
                json = applySummary(json, mode: s, summaryFields: diagnosticReportSummaryFields)
            }
            if let elems = elements { json = applyElements(json, elements: elems) }
            return ("\(baseURL)/DiagnosticReport/\(e.id)", json)
        }
        let bundleData = buildBundleJSON(entries: entries, total: result.total, selfURL: base, nextURL: nextURL)
        var headers = HTTPFields()
        headers[.contentType] = fhirJSON
        return Response(status: .ok, headers: headers,
                        body: ResponseBody(byteBuffer: ByteBuffer(bytes: bundleData)))
    }

    // POST /Patient/:patientId/DiagnosticReport/_search — compartment form-encoded search
    group.post(":id/DiagnosticReport/_search") { request, context in
        let patientId = context.parameters.get("id") ?? ""
        let ct = request.headers[.contentType] ?? ""
        guard ct.contains("application/x-www-form-urlencoded") else {
            throw FHIRRouteError.invalidBody("Content-Type must be application/x-www-form-urlencoded for _search")
        }
        var req = request
        let bodyBuffer = try await req.collectBody(upTo: 1 * 1024 * 1024)
        let urlPairs = request.uri.queryParameters.map { (key: $0.key, value: $0.value) }
        let pairs = urlPairs + parseFormPairs(from: bodyBuffer)
        if isStrictHandling(request) {
            let bad = unknownParams(in: pairs, known: knownDiagnosticReportParams)
            if !bad.isEmpty { throw FHIRRouteError.unknownParams(bad) }
        }
        var query = parseDiagnosticReportQuery(from: pairs)
        query.subject = "Patient/\(patientId)"
        let elements = parseElements(from: pairs)
        let summary = parseSummary(from: pairs)
        let result = try await diagnosticReportStore.search(query: query)

        let base = selfURL(request)
        let baseURL = serverBaseURL(request)
        if summary == .count {
            let bundleData = buildBundleJSON(entries: [], total: result.total, selfURL: base, nextURL: nil)
            var headers = HTTPFields()
            headers[.contentType] = fhirJSON
            return Response(status: .ok, headers: headers,
                            body: ResponseBody(byteBuffer: ByteBuffer(bytes: bundleData)))
        }
        let nextURL = result.nextCursor.map { nextPageURL(selfURL: base, cursor: $0, count: query.count) }
        let entries = result.entries.map { e -> (fullUrl: String, json: Data) in
            var json = e.jsonWithMeta
            if let s = summary, s != .false {
                json = applySummary(json, mode: s, summaryFields: diagnosticReportSummaryFields)
            }
            if let elems = elements { json = applyElements(json, elements: elems) }
            return ("\(baseURL)/DiagnosticReport/\(e.id)", json)
        }
        let bundleData = buildBundleJSON(entries: entries, total: result.total, selfURL: base, nextURL: nextURL)
        var headers = HTTPFields()
        headers[.contentType] = fhirJSON
        return Response(status: .ok, headers: headers,
                        body: ResponseBody(byteBuffer: ByteBuffer(bytes: bundleData)))
    }

    // GET /Patient/:patientId/Immunization — compartment search
    group.get(":id/Immunization") { request, context in
        let patientId = context.parameters.get("id") ?? ""
        let pairs = request.uri.queryParameters.map { (key: $0.key, value: $0.value) }
        if isStrictHandling(request) {
            let bad = unknownParams(in: pairs, known: knownImmunizationParams)
            if !bad.isEmpty { throw FHIRRouteError.unknownParams(bad) }
        }
        var query = parseImmunizationQuery(from: pairs)
        query.subject = "Patient/\(patientId)"
        let elements = parseElements(from: pairs)
        let summary = parseSummary(from: pairs)
        let result = try await immunizationStore.search(query: query)

        let base = selfURL(request)
        let baseURL = serverBaseURL(request)
        if summary == .count {
            let bundleData = buildBundleJSON(entries: [], total: result.total, selfURL: base, nextURL: nil)
            var headers = HTTPFields()
            headers[.contentType] = fhirJSON
            return Response(status: .ok, headers: headers,
                            body: ResponseBody(byteBuffer: ByteBuffer(bytes: bundleData)))
        }
        let nextURL = result.nextCursor.map { nextPageURL(selfURL: base, cursor: $0, count: query.count) }
        let entries = result.entries.map { e -> (fullUrl: String, json: Data) in
            var json = e.jsonWithMeta
            if let s = summary, s != .false {
                json = applySummary(json, mode: s, summaryFields: immunizationSummaryFields)
            }
            if let elems = elements { json = applyElements(json, elements: elems) }
            return ("\(baseURL)/Immunization/\(e.id)", json)
        }
        let bundleData = buildBundleJSON(entries: entries, total: result.total, selfURL: base, nextURL: nextURL)
        var headers = HTTPFields()
        headers[.contentType] = fhirJSON
        return Response(status: .ok, headers: headers,
                        body: ResponseBody(byteBuffer: ByteBuffer(bytes: bundleData)))
    }

    // POST /Patient/:patientId/Immunization/_search — compartment form-encoded search
    group.post(":id/Immunization/_search") { request, context in
        let patientId = context.parameters.get("id") ?? ""
        let ct = request.headers[.contentType] ?? ""
        guard ct.contains("application/x-www-form-urlencoded") else {
            throw FHIRRouteError.invalidBody("Content-Type must be application/x-www-form-urlencoded for _search")
        }
        var req = request
        let bodyBuffer = try await req.collectBody(upTo: 1 * 1024 * 1024)
        let urlPairs = request.uri.queryParameters.map { (key: $0.key, value: $0.value) }
        let pairs = urlPairs + parseFormPairs(from: bodyBuffer)
        if isStrictHandling(request) {
            let bad = unknownParams(in: pairs, known: knownImmunizationParams)
            if !bad.isEmpty { throw FHIRRouteError.unknownParams(bad) }
        }
        var query = parseImmunizationQuery(from: pairs)
        query.subject = "Patient/\(patientId)"
        let elements = parseElements(from: pairs)
        let summary = parseSummary(from: pairs)
        let result = try await immunizationStore.search(query: query)

        let base = selfURL(request)
        let baseURL = serverBaseURL(request)
        if summary == .count {
            let bundleData = buildBundleJSON(entries: [], total: result.total, selfURL: base, nextURL: nil)
            var headers = HTTPFields()
            headers[.contentType] = fhirJSON
            return Response(status: .ok, headers: headers,
                            body: ResponseBody(byteBuffer: ByteBuffer(bytes: bundleData)))
        }
        let nextURL = result.nextCursor.map { nextPageURL(selfURL: base, cursor: $0, count: query.count) }
        let entries = result.entries.map { e -> (fullUrl: String, json: Data) in
            var json = e.jsonWithMeta
            if let s = summary, s != .false {
                json = applySummary(json, mode: s, summaryFields: immunizationSummaryFields)
            }
            if let elems = elements { json = applyElements(json, elements: elems) }
            return ("\(baseURL)/Immunization/\(e.id)", json)
        }
        let bundleData = buildBundleJSON(entries: entries, total: result.total, selfURL: base, nextURL: nextURL)
        var headers = HTTPFields()
        headers[.contentType] = fhirJSON
        return Response(status: .ok, headers: headers,
                        body: ResponseBody(byteBuffer: ByteBuffer(bytes: bundleData)))
    }

    // GET /Patient/:patientId/RelatedPerson — compartment search
    group.get(":id/RelatedPerson") { request, context in
        let patientId = context.parameters.get("id") ?? ""
        let pairs = request.uri.queryParameters.map { (key: $0.key, value: $0.value) }
        if isStrictHandling(request) {
            let bad = unknownParams(in: pairs, known: knownRelatedPersonParams)
            if !bad.isEmpty { throw FHIRRouteError.unknownParams(bad) }
        }
        var query = parseRelatedPersonQuery(from: pairs)
        query.patient = "Patient/\(patientId)"
        let elements = parseElements(from: pairs)
        let summary = parseSummary(from: pairs)
        let result = try await relatedPersonStore.search(query: query)

        let base = selfURL(request)
        let baseURL = serverBaseURL(request)
        if summary == .count {
            let bundleData = buildBundleJSON(entries: [], total: result.total, selfURL: base, nextURL: nil)
            var headers = HTTPFields()
            headers[.contentType] = fhirJSON
            return Response(status: .ok, headers: headers,
                            body: ResponseBody(byteBuffer: ByteBuffer(bytes: bundleData)))
        }
        let nextURL = result.nextCursor.map { nextPageURL(selfURL: base, cursor: $0, count: query.count) }
        let entries = result.entries.map { e -> (fullUrl: String, json: Data) in
            var json = e.jsonWithMeta
            if let s = summary, s != .false {
                json = applySummary(json, mode: s, summaryFields: relatedPersonSummaryFields)
            }
            if let elems = elements { json = applyElements(json, elements: elems) }
            return ("\(baseURL)/RelatedPerson/\(e.id)", json)
        }
        let bundleData = buildBundleJSON(entries: entries, total: result.total, selfURL: base, nextURL: nextURL)
        var headers = HTTPFields()
        headers[.contentType] = fhirJSON
        return Response(status: .ok, headers: headers,
                        body: ResponseBody(byteBuffer: ByteBuffer(bytes: bundleData)))
    }

    // POST /Patient/:patientId/RelatedPerson/_search — compartment form-encoded search
    group.post(":id/RelatedPerson/_search") { request, context in
        let patientId = context.parameters.get("id") ?? ""
        let ct = request.headers[.contentType] ?? ""
        guard ct.contains("application/x-www-form-urlencoded") else {
            throw FHIRRouteError.invalidBody("Content-Type must be application/x-www-form-urlencoded for _search")
        }
        var req = request
        let bodyBuffer = try await req.collectBody(upTo: 1 * 1024 * 1024)
        let urlPairs = request.uri.queryParameters.map { (key: $0.key, value: $0.value) }
        let pairs = urlPairs + parseFormPairs(from: bodyBuffer)
        if isStrictHandling(request) {
            let bad = unknownParams(in: pairs, known: knownRelatedPersonParams)
            if !bad.isEmpty { throw FHIRRouteError.unknownParams(bad) }
        }
        var query = parseRelatedPersonQuery(from: pairs)
        query.patient = "Patient/\(patientId)"
        let elements = parseElements(from: pairs)
        let summary = parseSummary(from: pairs)
        let result = try await relatedPersonStore.search(query: query)

        let base = selfURL(request)
        let baseURL = serverBaseURL(request)
        if summary == .count {
            let bundleData = buildBundleJSON(entries: [], total: result.total, selfURL: base, nextURL: nil)
            var headers = HTTPFields()
            headers[.contentType] = fhirJSON
            return Response(status: .ok, headers: headers,
                            body: ResponseBody(byteBuffer: ByteBuffer(bytes: bundleData)))
        }
        let nextURL = result.nextCursor.map { nextPageURL(selfURL: base, cursor: $0, count: query.count) }
        let entries = result.entries.map { e -> (fullUrl: String, json: Data) in
            var json = e.jsonWithMeta
            if let s = summary, s != .false {
                json = applySummary(json, mode: s, summaryFields: relatedPersonSummaryFields)
            }
            if let elems = elements { json = applyElements(json, elements: elems) }
            return ("\(baseURL)/RelatedPerson/\(e.id)", json)
        }
        let bundleData = buildBundleJSON(entries: entries, total: result.total, selfURL: base, nextURL: nextURL)
        var headers = HTTPFields()
        headers[.contentType] = fhirJSON
        return Response(status: .ok, headers: headers,
                        body: ResponseBody(byteBuffer: ByteBuffer(bytes: bundleData)))
    }

    // GET /Patient/:patientId/ServiceRequest — compartment search
    group.get(":id/ServiceRequest") { request, context in
        let patientId = context.parameters.get("id") ?? ""
        let pairs = request.uri.queryParameters.map { (key: $0.key, value: $0.value) }
        if isStrictHandling(request) {
            let bad = unknownParams(in: pairs, known: knownServiceRequestParams)
            if !bad.isEmpty { throw FHIRRouteError.unknownParams(bad) }
        }
        var query = parseServiceRequestQuery(from: pairs)
        query.patient = "Patient/\(patientId)"
        let elements = parseElements(from: pairs)
        let summary = parseSummary(from: pairs)
        let result = try await serviceRequestStore.search(query: query)

        let base = selfURL(request)
        let baseURL = serverBaseURL(request)
        let nextURL = result.nextCursor.map { nextServiceRequestPageURL(selfURL: base, cursor: $0, count: query.count) }
        let entries = result.entries.map { e -> (fullUrl: String, json: Data) in
            var json = e.jsonWithMeta
            if let s = summary, s != .false {
                json = applySummary(json, mode: s, summaryFields: serviceRequestSummaryFields)
            }
            if let elems = elements { json = applyElements(json, elements: elems) }
            return ("\(baseURL)/ServiceRequest/\(e.id)", json)
        }
        let bundleData = buildBundleJSON(entries: entries, total: result.total, selfURL: base, nextURL: nextURL)
        var headers = HTTPFields()
        headers[.contentType] = fhirJSON
        return Response(status: .ok, headers: headers,
                        body: ResponseBody(byteBuffer: ByteBuffer(bytes: bundleData)))
    }

    // POST /Patient/:patientId/ServiceRequest/_search — compartment form-encoded search
    group.post(":id/ServiceRequest/_search") { request, context in
        let patientId = context.parameters.get("id") ?? ""
        let ct = request.headers[.contentType] ?? ""
        guard ct.contains("application/x-www-form-urlencoded") else {
            throw FHIRRouteError.invalidBody("Content-Type must be application/x-www-form-urlencoded for _search")
        }
        var req = request
        let bodyBuffer = try await req.collectBody(upTo: 4 * 1024 * 1024)
        let urlPairs = request.uri.queryParameters.map { (key: $0.key, value: $0.value) }
        let pairs = urlPairs + parseFormPairs(from: bodyBuffer)
        if isStrictHandling(request) {
            let bad = unknownParams(in: pairs, known: knownServiceRequestParams)
            if !bad.isEmpty { throw FHIRRouteError.unknownParams(bad) }
        }
        var query = parseServiceRequestQuery(from: pairs)
        query.patient = "Patient/\(patientId)"
        let elements = parseElements(from: pairs)
        let summary = parseSummary(from: pairs)
        let result = try await serviceRequestStore.search(query: query)

        let base = selfURL(request)
        let baseURL = serverBaseURL(request)
        let nextURL = result.nextCursor.map { nextServiceRequestPageURL(selfURL: base, cursor: $0, count: query.count) }
        let entries = result.entries.map { e -> (fullUrl: String, json: Data) in
            var json = e.jsonWithMeta
            if let s = summary, s != .false {
                json = applySummary(json, mode: s, summaryFields: serviceRequestSummaryFields)
            }
            if let elems = elements { json = applyElements(json, elements: elems) }
            return ("\(baseURL)/ServiceRequest/\(e.id)", json)
        }
        let bundleData = buildBundleJSON(entries: entries, total: result.total, selfURL: base, nextURL: nextURL)
        var headers = HTTPFields()
        headers[.contentType] = fhirJSON
        return Response(status: .ok, headers: headers,
                        body: ResponseBody(byteBuffer: ByteBuffer(bytes: bundleData)))
    }

    // GET /Patient/:patientId/Specimen — compartment search
    group.get(":id/Specimen") { request, context in
        let patientId = context.parameters.get("id") ?? ""
        let pairs = request.uri.queryParameters.map { (key: $0.key, value: $0.value) }
        if isStrictHandling(request) {
            let bad = unknownParams(in: pairs, known: knownSpecimenParams)
            if !bad.isEmpty { throw FHIRRouteError.unknownParams(bad) }
        }
        var query = parseSpecimenQuery(from: pairs)
        query.subject = "Patient/\(patientId)"
        let elements = parseElements(from: pairs)
        let summary = parseSummary(from: pairs)
        let result = try await specimenStore.search(query: query)

        let base = selfURL(request)
        let baseURL = serverBaseURL(request)
        let nextURL = result.nextCursor.map { nextSpecimenPageURL(selfURL: base, cursor: $0, count: query.count) }
        let entries = result.entries.map { e -> (fullUrl: String, json: Data) in
            var json = e.jsonWithMeta
            if let s = summary, s != .false {
                json = applySummary(json, mode: s, summaryFields: specimenSummaryFields)
            }
            if let elems = elements { json = applyElements(json, elements: elems) }
            return ("\(baseURL)/Specimen/\(e.id)", json)
        }
        let bundleData = buildBundleJSON(entries: entries, total: result.total, selfURL: base, nextURL: nextURL)
        var headers = HTTPFields()
        headers[.contentType] = fhirJSON
        return Response(status: .ok, headers: headers,
                        body: ResponseBody(byteBuffer: ByteBuffer(bytes: bundleData)))
    }

    // POST /Patient/:patientId/Specimen/_search — compartment form-encoded search
    group.post(":id/Specimen/_search") { request, context in
        let patientId = context.parameters.get("id") ?? ""
        let ct = request.headers[.contentType] ?? ""
        guard ct.contains("application/x-www-form-urlencoded") else {
            throw FHIRRouteError.invalidBody("Content-Type must be application/x-www-form-urlencoded for _search")
        }
        var req = request
        let bodyBuffer = try await req.collectBody(upTo: 4 * 1024 * 1024)
        let urlPairs = request.uri.queryParameters.map { (key: $0.key, value: $0.value) }
        let pairs = urlPairs + parseFormPairs(from: bodyBuffer)
        if isStrictHandling(request) {
            let bad = unknownParams(in: pairs, known: knownSpecimenParams)
            if !bad.isEmpty { throw FHIRRouteError.unknownParams(bad) }
        }
        var query = parseSpecimenQuery(from: pairs)
        query.subject = "Patient/\(patientId)"
        let elements = parseElements(from: pairs)
        let summary = parseSummary(from: pairs)
        let result = try await specimenStore.search(query: query)

        let base = selfURL(request)
        let baseURL = serverBaseURL(request)
        let nextURL = result.nextCursor.map { nextSpecimenPageURL(selfURL: base, cursor: $0, count: query.count) }
        let entries = result.entries.map { e -> (fullUrl: String, json: Data) in
            var json = e.jsonWithMeta
            if let s = summary, s != .false {
                json = applySummary(json, mode: s, summaryFields: specimenSummaryFields)
            }
            if let elems = elements { json = applyElements(json, elements: elems) }
            return ("\(baseURL)/Specimen/\(e.id)", json)
        }
        let bundleData = buildBundleJSON(entries: entries, total: result.total, selfURL: base, nextURL: nextURL)
        var headers = HTTPFields()
        headers[.contentType] = fhirJSON
        return Response(status: .ok, headers: headers,
                        body: ResponseBody(byteBuffer: ByteBuffer(bytes: bundleData)))
    }

    // GET /Patient/:patientId/DocumentReference — compartment search
    group.get(":id/DocumentReference") { request, context in
        let patientId = context.parameters.get("id") ?? ""
        let pairs = request.uri.queryParameters.map { (key: $0.key, value: $0.value) }
        if isStrictHandling(request) {
            let bad = unknownParams(in: pairs, known: knownDocumentReferenceParams)
            if !bad.isEmpty { throw FHIRRouteError.unknownParams(bad) }
        }
        var query = parseDocumentReferenceQuery(from: pairs)
        query.subject = "Patient/\(patientId)"
        let elements = parseElements(from: pairs)
        let summary = parseSummary(from: pairs)
        let result = try await documentReferenceStore.search(query: query)

        let base = selfURL(request)
        let baseURL = serverBaseURL(request)
        let nextURL = result.nextCursor.map { nextDocumentReferencePageURL(selfURL: base, cursor: $0, count: query.count) }
        let entries = result.entries.map { e -> (fullUrl: String, json: Data) in
            var json = e.jsonWithMeta
            if let s = summary, s != .false {
                json = applySummary(json, mode: s, summaryFields: documentReferenceSummaryFields)
            }
            if let elems = elements { json = applyElements(json, elements: elems) }
            return ("\(baseURL)/DocumentReference/\(e.id)", json)
        }
        let bundleData = buildBundleJSON(entries: entries, total: result.total, selfURL: base, nextURL: nextURL)
        var headers = HTTPFields()
        headers[.contentType] = fhirJSON
        return Response(status: .ok, headers: headers,
                        body: ResponseBody(byteBuffer: ByteBuffer(bytes: bundleData)))
    }

    // POST /Patient/:patientId/DocumentReference/_search — compartment form-encoded search
    group.post(":id/DocumentReference/_search") { request, context in
        let patientId = context.parameters.get("id") ?? ""
        let ct = request.headers[.contentType] ?? ""
        guard ct.contains("application/x-www-form-urlencoded") else {
            throw FHIRRouteError.invalidBody("Content-Type must be application/x-www-form-urlencoded for _search")
        }
        var req = request
        let bodyBuffer = try await req.collectBody(upTo: 4 * 1024 * 1024)
        let urlPairs = request.uri.queryParameters.map { (key: $0.key, value: $0.value) }
        let pairs = urlPairs + parseFormPairs(from: bodyBuffer)
        if isStrictHandling(request) {
            let bad = unknownParams(in: pairs, known: knownDocumentReferenceParams)
            if !bad.isEmpty { throw FHIRRouteError.unknownParams(bad) }
        }
        var query = parseDocumentReferenceQuery(from: pairs)
        query.subject = "Patient/\(patientId)"
        let elements = parseElements(from: pairs)
        let summary = parseSummary(from: pairs)
        let result = try await documentReferenceStore.search(query: query)

        let base = selfURL(request)
        let baseURL = serverBaseURL(request)
        let nextURL = result.nextCursor.map { nextDocumentReferencePageURL(selfURL: base, cursor: $0, count: query.count) }
        let entries = result.entries.map { e -> (fullUrl: String, json: Data) in
            var json = e.jsonWithMeta
            if let s = summary, s != .false {
                json = applySummary(json, mode: s, summaryFields: documentReferenceSummaryFields)
            }
            if let elems = elements { json = applyElements(json, elements: elems) }
            return ("\(baseURL)/DocumentReference/\(e.id)", json)
        }
        let bundleData = buildBundleJSON(entries: entries, total: result.total, selfURL: base, nextURL: nextURL)
        var headers = HTTPFields()
        headers[.contentType] = fhirJSON
        return Response(status: .ok, headers: headers,
                        body: ResponseBody(byteBuffer: ByteBuffer(bytes: bundleData)))
    }

    // GET /Patient/:patientId/CarePlan — compartment search
    group.get(":id/CarePlan") { request, context in
        let patientId = context.parameters.get("id") ?? ""
        let pairs = request.uri.queryParameters.map { (key: $0.key, value: $0.value) }
        if isStrictHandling(request) {
            let bad = unknownParams(in: pairs, known: knownCarePlanParams)
            if !bad.isEmpty { throw FHIRRouteError.unknownParams(bad) }
        }
        var query = parseCarePlanQuery(from: pairs)
        query.subject = "Patient/\(patientId)"
        let elements = parseElements(from: pairs)
        let summary = parseSummary(from: pairs)
        let result = try await carePlanStore.search(query: query)

        let base = selfURL(request)
        let baseURL = serverBaseURL(request)
        let nextURL = result.nextCursor.map { nextCarePlanPageURL(selfURL: base, cursor: $0, count: query.count) }
        let entries = result.entries.map { e -> (fullUrl: String, json: Data) in
            var json = e.jsonWithMeta
            if let s = summary, s != .false {
                json = applySummary(json, mode: s, summaryFields: carePlanSummaryFields)
            }
            if let elems = elements { json = applyElements(json, elements: elems) }
            return ("\(baseURL)/CarePlan/\(e.id)", json)
        }
        let bundleData = buildBundleJSON(entries: entries, total: result.total, selfURL: base, nextURL: nextURL)
        var headers = HTTPFields()
        headers[.contentType] = fhirJSON
        return Response(status: .ok, headers: headers,
                        body: ResponseBody(byteBuffer: ByteBuffer(bytes: bundleData)))
    }

    // POST /Patient/:patientId/CarePlan/_search — compartment form-encoded search
    group.post(":id/CarePlan/_search") { request, context in
        let patientId = context.parameters.get("id") ?? ""
        let ct = request.headers[.contentType] ?? ""
        guard ct.contains("application/x-www-form-urlencoded") else {
            throw FHIRRouteError.invalidBody("Content-Type must be application/x-www-form-urlencoded for _search")
        }
        var req = request
        let bodyBuffer = try await req.collectBody(upTo: 4 * 1024 * 1024)
        let urlPairs = request.uri.queryParameters.map { (key: $0.key, value: $0.value) }
        let pairs = urlPairs + parseFormPairs(from: bodyBuffer)
        if isStrictHandling(request) {
            let bad = unknownParams(in: pairs, known: knownCarePlanParams)
            if !bad.isEmpty { throw FHIRRouteError.unknownParams(bad) }
        }
        var query = parseCarePlanQuery(from: pairs)
        query.subject = "Patient/\(patientId)"
        let elements = parseElements(from: pairs)
        let summary = parseSummary(from: pairs)
        let result = try await carePlanStore.search(query: query)

        let base = selfURL(request)
        let baseURL = serverBaseURL(request)
        let nextURL = result.nextCursor.map { nextCarePlanPageURL(selfURL: base, cursor: $0, count: query.count) }
        let entries = result.entries.map { e -> (fullUrl: String, json: Data) in
            var json = e.jsonWithMeta
            if let s = summary, s != .false {
                json = applySummary(json, mode: s, summaryFields: carePlanSummaryFields)
            }
            if let elems = elements { json = applyElements(json, elements: elems) }
            return ("\(baseURL)/CarePlan/\(e.id)", json)
        }
        let bundleData = buildBundleJSON(entries: entries, total: result.total, selfURL: base, nextURL: nextURL)
        var headers = HTTPFields()
        headers[.contentType] = fhirJSON
        return Response(status: .ok, headers: headers,
                        body: ResponseBody(byteBuffer: ByteBuffer(bytes: bundleData)))
    }

    // GET /Patient/:patientId/Goal — compartment search
    group.get(":id/Goal") { request, context in
        let patientId = context.parameters.get("id") ?? ""
        let pairs = request.uri.queryParameters.map { (key: $0.key, value: $0.value) }
        if isStrictHandling(request) {
            let bad = unknownParams(in: pairs, known: knownGoalParams)
            if !bad.isEmpty { throw FHIRRouteError.unknownParams(bad) }
        }
        var query = parseGoalQuery(from: pairs)
        query.subject = "Patient/\(patientId)"
        let elements = parseElements(from: pairs)
        let summary = parseSummary(from: pairs)
        let result = try await goalStore.search(query: query)

        let base = selfURL(request)
        let baseURL = serverBaseURL(request)
        if summary == .count {
            let bundleData = buildBundleJSON(entries: [], total: result.total, selfURL: base, nextURL: nil)
            var headers = HTTPFields()
            headers[.contentType] = fhirJSON
            return Response(status: .ok, headers: headers,
                            body: ResponseBody(byteBuffer: ByteBuffer(bytes: bundleData)))
        }
        let nextURL = result.nextCursor.map { nextGoalPageURL(selfURL: base, cursor: $0, count: query.count) }
        let entries = result.entries.map { e -> (fullUrl: String, json: Data) in
            var json = e.jsonWithMeta
            if let s = summary, s != .false {
                json = applySummary(json, mode: s, summaryFields: goalSummaryFields)
            }
            if let elems = elements { json = applyElements(json, elements: elems) }
            return ("\(baseURL)/Goal/\(e.id)", json)
        }
        let bundleData = buildBundleJSON(entries: entries, total: result.total, selfURL: base, nextURL: nextURL)
        var headers = HTTPFields()
        headers[.contentType] = fhirJSON
        return Response(status: .ok, headers: headers,
                        body: ResponseBody(byteBuffer: ByteBuffer(bytes: bundleData)))
    }

    // POST /Patient/:patientId/Goal/_search — compartment form-encoded search
    group.post(":id/Goal/_search") { request, context in
        let patientId = context.parameters.get("id") ?? ""
        let ct = request.headers[.contentType] ?? ""
        guard ct.contains("application/x-www-form-urlencoded") else {
            throw FHIRRouteError.invalidBody("Content-Type must be application/x-www-form-urlencoded for _search")
        }
        var req = request
        let bodyBuffer = try await req.collectBody(upTo: 4 * 1024 * 1024)
        let urlPairs = request.uri.queryParameters.map { (key: $0.key, value: $0.value) }
        let pairs = urlPairs + parseFormPairs(from: bodyBuffer)
        if isStrictHandling(request) {
            let bad = unknownParams(in: pairs, known: knownGoalParams)
            if !bad.isEmpty { throw FHIRRouteError.unknownParams(bad) }
        }
        var query = parseGoalQuery(from: pairs)
        query.subject = "Patient/\(patientId)"
        let elements = parseElements(from: pairs)
        let summary = parseSummary(from: pairs)
        let result = try await goalStore.search(query: query)

        let base = selfURL(request)
        let baseURL = serverBaseURL(request)
        if summary == .count {
            let bundleData = buildBundleJSON(entries: [], total: result.total, selfURL: base, nextURL: nil)
            var headers = HTTPFields()
            headers[.contentType] = fhirJSON
            return Response(status: .ok, headers: headers,
                            body: ResponseBody(byteBuffer: ByteBuffer(bytes: bundleData)))
        }
        let nextURL = result.nextCursor.map { nextGoalPageURL(selfURL: base, cursor: $0, count: query.count) }
        let entries = result.entries.map { e -> (fullUrl: String, json: Data) in
            var json = e.jsonWithMeta
            if let s = summary, s != .false {
                json = applySummary(json, mode: s, summaryFields: goalSummaryFields)
            }
            if let elems = elements { json = applyElements(json, elements: elems) }
            return ("\(baseURL)/Goal/\(e.id)", json)
        }
        let bundleData = buildBundleJSON(entries: entries, total: result.total, selfURL: base, nextURL: nextURL)
        var headers = HTTPFields()
        headers[.contentType] = fhirJSON
        return Response(status: .ok, headers: headers,
                        body: ResponseBody(byteBuffer: ByteBuffer(bytes: bundleData)))
    }

    // GET /Patient/:patientId/MedicationStatement — compartment search
    group.get(":id/MedicationStatement") { request, context in
        let patientId = context.parameters.get("id") ?? ""
        let pairs = request.uri.queryParameters.map { (key: $0.key, value: $0.value) }
        if isStrictHandling(request) {
            let bad = unknownParams(in: pairs, known: knownMedicationStatementParams)
            if !bad.isEmpty { throw FHIRRouteError.unknownParams(bad) }
        }
        var query = parseMedicationStatementQuery(from: pairs)
        query.subject = "Patient/\(patientId)"
        let elements = parseElements(from: pairs)
        let summary = parseSummary(from: pairs)
        let result = try await medicationStatementStore.search(query: query)

        let base = selfURL(request)
        let baseURL = serverBaseURL(request)
        if summary == .count {
            let bundleData = buildBundleJSON(entries: [], total: result.total, selfURL: base, nextURL: nil)
            var headers = HTTPFields()
            headers[.contentType] = fhirJSON
            return Response(status: .ok, headers: headers,
                            body: ResponseBody(byteBuffer: ByteBuffer(bytes: bundleData)))
        }
        let nextURL = result.nextCursor.map { nextMedicationStatementPageURL(selfURL: base, cursor: $0, count: query.count) }
        let entries = result.entries.map { e -> (fullUrl: String, json: Data) in
            var json = e.jsonWithMeta
            if let s = summary, s != .false {
                json = applySummary(json, mode: s, summaryFields: medicationStatementSummaryFields)
            }
            if let elems = elements { json = applyElements(json, elements: elems) }
            return ("\(baseURL)/MedicationStatement/\(e.id)", json)
        }
        let bundleData = buildBundleJSON(entries: entries, total: result.total, selfURL: base, nextURL: nextURL)
        var headers = HTTPFields()
        headers[.contentType] = fhirJSON
        return Response(status: .ok, headers: headers,
                        body: ResponseBody(byteBuffer: ByteBuffer(bytes: bundleData)))
    }

    // GET /Patient/:patientId/FamilyMemberHistory — compartment search
    group.get(":id/FamilyMemberHistory") { request, context in
        let patientId = context.parameters.get("id") ?? ""
        let pairs = request.uri.queryParameters.map { (key: $0.key, value: $0.value) }
        if isStrictHandling(request) {
            let bad = unknownParams(in: pairs, known: knownFamilyMemberHistoryParams)
            if !bad.isEmpty { throw FHIRRouteError.unknownParams(bad) }
        }
        var query = parseFamilyMemberHistoryQuery(from: pairs)
        query.patient = "Patient/\(patientId)"
        let elements = parseElements(from: pairs)
        let summary = parseSummary(from: pairs)
        let result = try await familyMemberHistoryStore.search(query: query)

        let base = selfURL(request)
        let baseURL = serverBaseURL(request)
        if summary == .count {
            let bundleData = buildBundleJSON(entries: [], total: result.total, selfURL: base, nextURL: nil)
            var headers = HTTPFields()
            headers[.contentType] = fhirJSON
            return Response(status: .ok, headers: headers,
                            body: ResponseBody(byteBuffer: ByteBuffer(bytes: bundleData)))
        }
        let nextURL = result.nextCursor.map { nextFamilyMemberHistoryPageURL(selfURL: base, cursor: $0, count: query.count) }
        let entries = result.entries.map { e -> (fullUrl: String, json: Data) in
            var json = e.jsonWithMeta
            if let s = summary, s != .false {
                json = applySummary(json, mode: s, summaryFields: familyMemberHistorySummaryFields)
            }
            if let elems = elements { json = applyElements(json, elements: elems) }
            return ("\(baseURL)/FamilyMemberHistory/\(e.id)", json)
        }
        let bundleData = buildBundleJSON(entries: entries, total: result.total, selfURL: base, nextURL: nextURL)
        var headers = HTTPFields()
        headers[.contentType] = fhirJSON
        return Response(status: .ok, headers: headers,
                        body: ResponseBody(byteBuffer: ByteBuffer(bytes: bundleData)))
    }

    // POST /Patient/:patientId/FamilyMemberHistory/_search — compartment form-encoded search
    group.post(":id/FamilyMemberHistory/_search") { request, context in
        let patientId = context.parameters.get("id") ?? ""
        let ct = request.headers[.contentType] ?? ""
        guard ct.contains("application/x-www-form-urlencoded") else {
            throw FHIRRouteError.invalidBody("Content-Type must be application/x-www-form-urlencoded for _search")
        }
        var req = request
        let bodyBuffer = try await req.collectBody(upTo: 4 * 1024 * 1024)
        let urlPairs = request.uri.queryParameters.map { (key: $0.key, value: $0.value) }
        let pairs = urlPairs + parseFormPairs(from: bodyBuffer)
        if isStrictHandling(request) {
            let bad = unknownParams(in: pairs, known: knownFamilyMemberHistoryParams)
            if !bad.isEmpty { throw FHIRRouteError.unknownParams(bad) }
        }
        var query = parseFamilyMemberHistoryQuery(from: pairs)
        query.patient = "Patient/\(patientId)"
        let elements = parseElements(from: pairs)
        let summary = parseSummary(from: pairs)
        let result = try await familyMemberHistoryStore.search(query: query)

        let base = selfURL(request)
        let baseURL = serverBaseURL(request)
        if summary == .count {
            let bundleData = buildBundleJSON(entries: [], total: result.total, selfURL: base, nextURL: nil)
            var headers = HTTPFields()
            headers[.contentType] = fhirJSON
            return Response(status: .ok, headers: headers,
                            body: ResponseBody(byteBuffer: ByteBuffer(bytes: bundleData)))
        }
        let nextURL = result.nextCursor.map { nextFamilyMemberHistoryPageURL(selfURL: base, cursor: $0, count: query.count) }
        let entries = result.entries.map { e -> (fullUrl: String, json: Data) in
            var json = e.jsonWithMeta
            if let s = summary, s != .false {
                json = applySummary(json, mode: s, summaryFields: familyMemberHistorySummaryFields)
            }
            if let elems = elements { json = applyElements(json, elements: elems) }
            return ("\(baseURL)/FamilyMemberHistory/\(e.id)", json)
        }
        let bundleData = buildBundleJSON(entries: entries, total: result.total, selfURL: base, nextURL: nextURL)
        var headers = HTTPFields()
        headers[.contentType] = fhirJSON
        return Response(status: .ok, headers: headers,
                        body: ResponseBody(byteBuffer: ByteBuffer(bytes: bundleData)))
    }

    // POST /Patient/:patientId/MedicationStatement/_search — compartment form-encoded search
    group.post(":id/MedicationStatement/_search") { request, context in
        let patientId = context.parameters.get("id") ?? ""
        let ct = request.headers[.contentType] ?? ""
        guard ct.contains("application/x-www-form-urlencoded") else {
            throw FHIRRouteError.invalidBody("Content-Type must be application/x-www-form-urlencoded for _search")
        }
        var req = request
        let bodyBuffer = try await req.collectBody(upTo: 4 * 1024 * 1024)
        let urlPairs = request.uri.queryParameters.map { (key: $0.key, value: $0.value) }
        let pairs = urlPairs + parseFormPairs(from: bodyBuffer)
        if isStrictHandling(request) {
            let bad = unknownParams(in: pairs, known: knownMedicationStatementParams)
            if !bad.isEmpty { throw FHIRRouteError.unknownParams(bad) }
        }
        var query = parseMedicationStatementQuery(from: pairs)
        query.subject = "Patient/\(patientId)"
        let elements = parseElements(from: pairs)
        let summary = parseSummary(from: pairs)
        let result = try await medicationStatementStore.search(query: query)

        let base = selfURL(request)
        let baseURL = serverBaseURL(request)
        if summary == .count {
            let bundleData = buildBundleJSON(entries: [], total: result.total, selfURL: base, nextURL: nil)
            var headers = HTTPFields()
            headers[.contentType] = fhirJSON
            return Response(status: .ok, headers: headers,
                            body: ResponseBody(byteBuffer: ByteBuffer(bytes: bundleData)))
        }
        let nextURL = result.nextCursor.map { nextMedicationStatementPageURL(selfURL: base, cursor: $0, count: query.count) }
        let entries = result.entries.map { e -> (fullUrl: String, json: Data) in
            var json = e.jsonWithMeta
            if let s = summary, s != .false {
                json = applySummary(json, mode: s, summaryFields: medicationStatementSummaryFields)
            }
            if let elems = elements { json = applyElements(json, elements: elems) }
            return ("\(baseURL)/MedicationStatement/\(e.id)", json)
        }
        let bundleData = buildBundleJSON(entries: entries, total: result.total, selfURL: base, nextURL: nextURL)
        var headers = HTTPFields()
        headers[.contentType] = fhirJSON
        return Response(status: .ok, headers: headers,
                        body: ResponseBody(byteBuffer: ByteBuffer(bytes: bundleData)))
    }

    // GET /Patient/:patientId/Appointment — compartment search
    group.get(":id/Appointment") { request, context in
        let patientId = context.parameters.get("id") ?? ""
        let pairs = request.uri.queryParameters.map { (key: $0.key, value: $0.value) }
        if isStrictHandling(request) {
            let bad = unknownParams(in: pairs, known: knownAppointmentParams)
            if !bad.isEmpty { throw FHIRRouteError.unknownParams(bad) }
        }
        var query = parseAppointmentQuery(from: pairs)
        query.patient = "Patient/\(patientId)"
        let elements = parseElements(from: pairs)
        let summary = parseSummary(from: pairs)
        let result = try await appointmentStore.search(query: query)

        let base = selfURL(request)
        let baseURL = serverBaseURL(request)
        if summary == .count {
            let bundleData = buildBundleJSON(entries: [], total: result.total, selfURL: base, nextURL: nil)
            var headers = HTTPFields()
            headers[.contentType] = fhirJSON
            return Response(status: .ok, headers: headers,
                            body: ResponseBody(byteBuffer: ByteBuffer(bytes: bundleData)))
        }
        let nextURL = result.nextCursor.map { nextAppointmentPageURL(selfURL: base, cursor: $0, count: query.count) }
        let entries = result.entries.map { e -> (fullUrl: String, json: Data) in
            var json = e.jsonWithMeta
            if let s = summary, s != .false {
                json = applySummary(json, mode: s, summaryFields: appointmentSummaryFields)
            }
            if let elems = elements { json = applyElements(json, elements: elems) }
            return ("\(baseURL)/Appointment/\(e.id)", json)
        }
        let bundleData = buildBundleJSON(entries: entries, total: result.total, selfURL: base, nextURL: nextURL)
        var headers = HTTPFields()
        headers[.contentType] = fhirJSON
        return Response(status: .ok, headers: headers,
                        body: ResponseBody(byteBuffer: ByteBuffer(bytes: bundleData)))
    }

    // POST /Patient/:patientId/Appointment/_search — compartment form-encoded search
    group.post(":id/Appointment/_search") { request, context in
        let patientId = context.parameters.get("id") ?? ""
        let ct = request.headers[.contentType] ?? ""
        guard ct.contains("application/x-www-form-urlencoded") else {
            throw FHIRRouteError.invalidBody("Content-Type must be application/x-www-form-urlencoded for _search")
        }
        var req = request
        let bodyBuffer = try await req.collectBody(upTo: 4 * 1024 * 1024)
        let urlPairs = request.uri.queryParameters.map { (key: $0.key, value: $0.value) }
        let pairs = urlPairs + parseFormPairs(from: bodyBuffer)
        if isStrictHandling(request) {
            let bad = unknownParams(in: pairs, known: knownAppointmentParams)
            if !bad.isEmpty { throw FHIRRouteError.unknownParams(bad) }
        }
        var query = parseAppointmentQuery(from: pairs)
        query.patient = "Patient/\(patientId)"
        let elements = parseElements(from: pairs)
        let summary = parseSummary(from: pairs)
        let result = try await appointmentStore.search(query: query)

        let base = selfURL(request)
        let baseURL = serverBaseURL(request)
        if summary == .count {
            let bundleData = buildBundleJSON(entries: [], total: result.total, selfURL: base, nextURL: nil)
            var headers = HTTPFields()
            headers[.contentType] = fhirJSON
            return Response(status: .ok, headers: headers,
                            body: ResponseBody(byteBuffer: ByteBuffer(bytes: bundleData)))
        }
        let nextURL = result.nextCursor.map { nextAppointmentPageURL(selfURL: base, cursor: $0, count: query.count) }
        let entries = result.entries.map { e -> (fullUrl: String, json: Data) in
            var json = e.jsonWithMeta
            if let s = summary, s != .false {
                json = applySummary(json, mode: s, summaryFields: appointmentSummaryFields)
            }
            if let elems = elements { json = applyElements(json, elements: elems) }
            return ("\(baseURL)/Appointment/\(e.id)", json)
        }
        let bundleData = buildBundleJSON(entries: entries, total: result.total, selfURL: base, nextURL: nextURL)
        var headers = HTTPFields()
        headers[.contentType] = fhirJSON
        return Response(status: .ok, headers: headers,
                        body: ResponseBody(byteBuffer: ByteBuffer(bytes: bundleData)))
    }

    // GET /Patient/:patientId/MedicationAdministration — compartment search
    group.get(":id/MedicationAdministration") { request, context in
        let patientId = context.parameters.get("id") ?? ""
        let pairs = request.uri.queryParameters.map { (key: $0.key, value: $0.value) }
        if isStrictHandling(request) {
            let bad = unknownParams(in: pairs, known: knownMedicationAdministrationParams)
            if !bad.isEmpty { throw FHIRRouteError.unknownParams(bad) }
        }
        var query = parseMedicationAdministrationQuery(from: pairs)
        query.patient = "Patient/\(patientId)"
        let elements = parseElements(from: pairs)
        let summary = parseSummary(from: pairs)
        let result = try await medicationAdministrationStore.search(query: query)

        let base = selfURL(request)
        let baseURL = serverBaseURL(request)
        if summary == .count {
            let bundleData = buildBundleJSON(entries: [], total: result.total, selfURL: base, nextURL: nil)
            var headers = HTTPFields()
            headers[.contentType] = fhirJSON
            return Response(status: .ok, headers: headers,
                            body: ResponseBody(byteBuffer: ByteBuffer(bytes: bundleData)))
        }
        let nextURL = result.nextCursor.map { nextMedicationAdministrationPageURL(selfURL: base, cursor: $0, count: query.count) }
        let entries = result.entries.map { e -> (fullUrl: String, json: Data) in
            var json = e.jsonWithMeta
            if let s = summary, s != .false {
                json = applySummary(json, mode: s, summaryFields: medicationAdministrationSummaryFields)
            }
            if let elems = elements { json = applyElements(json, elements: elems) }
            return ("\(baseURL)/MedicationAdministration/\(e.id)", json)
        }
        let bundleData = buildBundleJSON(entries: entries, total: result.total, selfURL: base, nextURL: nextURL)
        var headers = HTTPFields()
        headers[.contentType] = fhirJSON
        return Response(status: .ok, headers: headers,
                        body: ResponseBody(byteBuffer: ByteBuffer(bytes: bundleData)))
    }

    // POST /Patient/:patientId/MedicationAdministration/_search — compartment form-encoded search
    group.post(":id/MedicationAdministration/_search") { request, context in
        let patientId = context.parameters.get("id") ?? ""
        let ct = request.headers[.contentType] ?? ""
        guard ct.contains("application/x-www-form-urlencoded") else {
            throw FHIRRouteError.invalidBody("Content-Type must be application/x-www-form-urlencoded for _search")
        }
        var req = request
        let bodyBuffer = try await req.collectBody(upTo: 4 * 1024 * 1024)
        let urlPairs = request.uri.queryParameters.map { (key: $0.key, value: $0.value) }
        let pairs = urlPairs + parseFormPairs(from: bodyBuffer)
        if isStrictHandling(request) {
            let bad = unknownParams(in: pairs, known: knownMedicationAdministrationParams)
            if !bad.isEmpty { throw FHIRRouteError.unknownParams(bad) }
        }
        var query = parseMedicationAdministrationQuery(from: pairs)
        query.patient = "Patient/\(patientId)"
        let elements = parseElements(from: pairs)
        let summary = parseSummary(from: pairs)
        let result = try await medicationAdministrationStore.search(query: query)

        let base = selfURL(request)
        let baseURL = serverBaseURL(request)
        if summary == .count {
            let bundleData = buildBundleJSON(entries: [], total: result.total, selfURL: base, nextURL: nil)
            var headers = HTTPFields()
            headers[.contentType] = fhirJSON
            return Response(status: .ok, headers: headers,
                            body: ResponseBody(byteBuffer: ByteBuffer(bytes: bundleData)))
        }
        let nextURL = result.nextCursor.map { nextMedicationAdministrationPageURL(selfURL: base, cursor: $0, count: query.count) }
        let entries = result.entries.map { e -> (fullUrl: String, json: Data) in
            var json = e.jsonWithMeta
            if let s = summary, s != .false {
                json = applySummary(json, mode: s, summaryFields: medicationAdministrationSummaryFields)
            }
            if let elems = elements { json = applyElements(json, elements: elems) }
            return ("\(baseURL)/MedicationAdministration/\(e.id)", json)
        }
        let bundleData = buildBundleJSON(entries: entries, total: result.total, selfURL: base, nextURL: nextURL)
        var headers = HTTPFields()
        headers[.contentType] = fhirJSON
        return Response(status: .ok, headers: headers,
                        body: ResponseBody(byteBuffer: ByteBuffer(bytes: bundleData)))
    }
}

// ── Helpers ───────────────────────────────────────────────────────────────────

private func selfURL(_ request: Request) -> String {
    let authority = request.head.authority ?? "localhost"
    return "http://\(authority)\(request.uri)"
}

private func nextPageURL(selfURL: String, cursor: ObservationSearchQuery.SearchCursor, count: Int) -> String {
    guard let urlComponents = URLComponents(string: selfURL) else { return selfURL }
    var components = urlComponents
    var items = (components.queryItems ?? []).filter { $0.name != "_cursor" }
    items.append(URLQueryItem(name: "_cursor", value: cursor.encode()))
    if !items.contains(where: { $0.name == "_count" }) {
        items.append(URLQueryItem(name: "_count", value: String(count)))
    }
    components.queryItems = items
    return components.string ?? selfURL
}
