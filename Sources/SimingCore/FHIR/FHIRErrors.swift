import Foundation
import ModelsR4

public enum FHIRServerError: Error {
    case unsupportedMediaType
    case invalidBody(String)
    case notFound(resourceType: String, id: String)
    case gone(resourceType: String, id: String)
    case versionConflict(id: String, expected: Int64, actual: Int64?)
    case multipleMatches(resourceType: String)
    /// A search parameter the server supports, given a value it cannot parse.
    /// Always a 400 — silently dropping the filter would answer a different
    /// question with a 200, which the client cannot detect.
    case invalidSearchValue(param: String, value: String)
}

// Build a minimal OperationOutcome. Never return ad-hoc JSON errors.
public func buildOutcome(
    severity: IssueSeverity,
    code: IssueType,
    diagnostics: String
) -> OperationOutcome {
    OperationOutcome(issue: [
        OperationOutcomeIssue(
            code: FHIRPrimitive(code),
            diagnostics: FHIRPrimitive(FHIRString(diagnostics)),
            severity: FHIRPrimitive(severity)
        )
    ])
}
