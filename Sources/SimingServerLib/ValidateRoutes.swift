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
/// Validates terminology bindings (always) and StructureDefinition profiles
/// (when externalValidator is configured). Returns OperationOutcome.
/// HTTP 200 OK always (per FHIR R4 §3.6.2); 400/415 only for malformed requests.
public func addValidateRoutes(
    to router: Router<BasicRequestContext>,
    terminology: TerminologyIndex,
    externalValidator: ExternalValidator? = nil
) {
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

            var issues: [OperationOutcomeIssue] = []

            // 1. Terminology binding validation (fast, local)
            do {
                try validateCodes(resourceType: resourceType, json: jsonObj, terminology: terminology)
            } catch let e as TerminologyValidationError {
                issues += e.violations.map { msg in
                    OperationOutcomeIssue(
                        code: FHIRPrimitive(.codeInvalid),
                        diagnostics: FHIRPrimitive(FHIRString(msg)),
                        severity: FHIRPrimitive(.error)
                    )
                }
            }

            // 2. External StructureDefinition / profile validation (optional, async)
            if let validator = externalValidator {
                do {
                    // Read ?profile= query param (comma-separated or repeated) per FHIR R4 §3.6.2
                    let profiles = request.uri.queryParameters[values: "profile"].map(String.init)
                    let extIssues = try await validator.validate(resourceData: data, profiles: profiles)
                    for issue in extIssues {
                        let severity: IssueSeverity = issue.level == "ERROR" ? .error : .warning
                        let code: IssueType = issue.level == "ERROR" ? .structure : .invariant
                        let diagnostics = [issue.location, issue.message]
                            .compactMap { $0 }.joined(separator: ": ")
                        issues.append(OperationOutcomeIssue(
                            code: FHIRPrimitive(code),
                            diagnostics: FHIRPrimitive(FHIRString(diagnostics)),
                            severity: FHIRPrimitive(severity)
                        ))
                    }
                } catch {
                    // Validator unreachable — degrade gracefully
                    issues.append(OperationOutcomeIssue(
                        code: FHIRPrimitive(.transient),
                        diagnostics: FHIRPrimitive(FHIRString("External validator unavailable: profile validation skipped")),
                        severity: FHIRPrimitive(.warning)
                    ))
                }
            }

            if issues.isEmpty {
                issues = [OperationOutcomeIssue(
                    code: FHIRPrimitive(.informational),
                    diagnostics: FHIRPrimitive(FHIRString("Validation passed")),
                    severity: FHIRPrimitive(.information)
                )]
            }

            return try validateOutcomeResponse(OperationOutcome(issue: issues), status: .ok)
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
