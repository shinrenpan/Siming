import Foundation
import HTTPTypes
import Hummingbird
import ModelsR4
import NIOCore
import SimingCore

private let validateMaxBodyBytes = 4 * 1024 * 1024
private let validateFhirJSON = "application/fhir+json"
private let validateSupportedTypes: Set<String> = [
    "AllergyIntolerance", "Appointment", "CarePlan", "Condition",
    "DiagnosticReport", "DocumentReference", "Encounter",
    "FamilyMemberHistory", "Goal", "Immunization", "Location",
    "Medication", "MedicationAdministration", "MedicationRequest",
    "MedicationStatement", "Observation", "Organization", "Patient",
    "Practitioner", "Procedure", "RelatedPerson", "ServiceRequest", "Specimen",
]

/// Registers `POST /{ResourceType}/$validate` for all 23 resource types.
/// Validates terminology bindings without storing. Returns OperationOutcome.
/// HTTP 200 OK always (per FHIR R4 §3.6.2); 400 only for malformed JSON.
public func addValidateRoutes(to router: Router<BasicRequestContext>, terminology: TerminologyIndex) {
    for rt in validateSupportedTypes.sorted() {
        let resourceType = rt
        let group = router.group(.init(stringLiteral: rt))
        group.post("$validate") { request, _ in
            guard (request.headers[.contentType] ?? "").contains("application/fhir+json")
                    || (request.headers[.contentType] ?? "").contains("application/json")
            else {
                return try validateErrorResponse(
                    message: "Content-Type must be application/fhir+json",
                    status: .unsupportedMediaType
                )
            }

            var req = request
            let bodyBuffer = try await req.collectBody(upTo: validateMaxBodyBytes)
            let data = Data(bodyBuffer.readableBytesView)

            guard let jsonObj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return try validateErrorResponse(
                    message: "Request body is not valid JSON",
                    status: .badRequest
                )
            }

            do {
                try validateCodes(resourceType: resourceType, json: jsonObj, terminology: terminology)
            } catch let e as TerminologyValidationError {
                let issues = e.violations.map { msg in
                    OperationOutcomeIssue(
                        code: FHIRPrimitive(.codeInvalid),
                        diagnostics: FHIRPrimitive(FHIRString(msg)),
                        severity: FHIRPrimitive(.error)
                    )
                }
                let outcome = OperationOutcome(issue: issues)
                return try validateOutcomeResponse(outcome, status: .ok)
            }

            // All checks passed
            let outcome = OperationOutcome(issue: [
                OperationOutcomeIssue(
                    code: FHIRPrimitive(.informational),
                    diagnostics: FHIRPrimitive(FHIRString("Validation passed")),
                    severity: FHIRPrimitive(.information)
                )
            ])
            return try validateOutcomeResponse(outcome, status: .ok)
        }
    }
}

private func validateOutcomeResponse(_ outcome: OperationOutcome, status: HTTPResponse.Status) throws -> Response {
    let data = try JSONEncoder().encode(outcome)
    var headers = HTTPFields()
    headers[.contentType] = validateFhirJSON
    return Response(status: status, headers: headers,
                    body: ResponseBody(byteBuffer: ByteBuffer(bytes: data)))
}

private func validateErrorResponse(message: String, status: HTTPResponse.Status) throws -> Response {
    let outcome = buildOutcome(severity: .error, code: .invalid, diagnostics: message)
    return try validateOutcomeResponse(outcome, status: status)
}
