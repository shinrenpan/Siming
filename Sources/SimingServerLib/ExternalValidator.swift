import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Optional sidecar for deep StructureDefinition / profile validation.
/// Calls the HL7 FHIR Validator service (inferno-resource-validator).
/// Configure via VALIDATOR_URL env var or config.yml `validator.url`.
/// When nil, $validate runs terminology-only checks.
///
/// Session caching: the validator service returns a sessionId after the first
/// call (which loads FHIR R4 core + TW Core IG, ~10 s). Subsequent calls reuse
/// the session and complete in < 1 s.
public actor ExternalValidator {
    public nonisolated let baseURL: String
    public nonisolated let igPackage: String
    private var sessionId: String?

    public init(baseURL: String, igPackage: String = "tw.gov.mohw.twcore#1.0.0") {
        self.baseURL = baseURL
        self.igPackage = igPackage
    }

    /// Validates a FHIR resource against the configured IG.
    /// `profiles`: additional profile URLs to validate against (e.g. from ?profile= query param).
    /// Returns validation issues (ERROR + WARNING only; INFORMATION filtered out).
    /// Throws on network or HTTP errors — callers should catch and degrade gracefully.
    public func validate(resourceData: Data, profiles: [String] = []) async throws -> [ExternalValidationIssue] {
        let resourceString = String(data: resourceData, encoding: .utf8) ?? "{}"

        var cliContext: [String: Any] = ["sv": "4.0.1", "igs": [igPackage]]
        if !profiles.isEmpty { cliContext["profiles"] = profiles }

        var body: [String: Any] = [
            "cliContext": cliContext,
            "filesToValidate": [
                ["fileName": "resource.json", "fileContent": resourceString, "fileType": "json"]
            ]
        ]
        if let sid = sessionId { body["sessionId"] = sid }

        var req = URLRequest(url: URL(string: "\(baseURL)/validate")!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        req.timeoutInterval = sessionId == nil ? 120 : 30  // first call loads IGs

        let (data, response) = try await URLSession.shared.data(for: req)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw ExternalValidatorError.unexpectedStatus
        }

        let resp = try JSONDecoder().decode(ValidatorServiceResponse.self, from: data)
        if let sid = resp.sessionId { sessionId = sid }

        return resp.outcomes
            .flatMap { $0.issues }
            .filter { $0.level != "INFORMATION" }
    }
}

public enum ExternalValidatorError: Error {
    case unexpectedStatus
}

public struct ExternalValidationIssue: Codable, Sendable {
    public let level: String
    public let message: String
    public let location: String?
}

private struct ValidatorServiceResponse: Codable {
    let outcomes: [ValidatorOutcome]
    let sessionId: String?
}

private struct ValidatorOutcome: Codable {
    let issues: [ExternalValidationIssue]
}
