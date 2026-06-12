import Foundation

/// Validates all `required` binding fields in a resource JSON object.
/// Uses `fhirRequiredBindings` (generated) and `TerminologyIndex` (loaded at startup).
///
/// Throws `TerminologyValidationError` listing every violated path.
/// Conservative: unknown ValueSets and intensional ValueSets always pass.
public func validateCodes(
    resourceType: String,
    json: [String: Any],
    terminology: TerminologyIndex
) throws {
    guard let rules = fhirRequiredBindings[resourceType], !rules.isEmpty else { return }

    // Group rules by path so multi-VS paths use OR semantics (sliced bindings).
    var byPath: [String: [BindingRule]] = [:]
    for rule in rules {
        byPath[rule.path, default: []].append(rule)
    }

    var violations: [String] = []

    for (path, pathRules) in byPath.sorted(by: { $0.key < $1.key }) {
        // Strip resource type prefix: "Patient.gender" → ["gender"]
        let components = path.split(separator: ".").dropFirst().map(String.init)
        guard !components.isEmpty else { continue }

        let kind = pathRules[0].kind
        let valueSets = pathRules.map(\.valueSet)

        // Collect all (system, code) pairs at this path
        let pairs = extractCodePairs(from: json, pathComponents: components, kind: kind)
        // If path resolves to nothing, skip (field is absent / optional)
        guard !pairs.isEmpty else { continue }

        for (system, code) in pairs {
            // OR semantics: valid if in ANY of the bound ValueSets
            let valid = valueSets.contains { vs in
                kind == .codeableConcept
                    ? terminology.isValid(valueSet: vs, system: system, code: code)
                    : terminology.hasCode(valueSet: vs, code: code)
            }
            if !valid {
                violations.append("\(path): '\(code)' not valid in any of \(valueSets)")
            }
        }
    }

    if !violations.isEmpty {
        throw TerminologyValidationError(violations: violations)
    }
}

/// Recursively walks `json` along `pathComponents`, handling arrays at any level.
/// Returns all (system, code) leaf pairs found.
private func extractCodePairs(
    from value: Any,
    pathComponents: [String],
    kind: BindingKind
) -> [(system: String, code: String)] {
    if let array = value as? [Any] {
        return array.flatMap { extractCodePairs(from: $0, pathComponents: pathComponents, kind: kind) }
    }
    guard let obj = value as? [String: Any] else { return [] }
    guard let key = pathComponents.first else { return [] }
    let rest = Array(pathComponents.dropFirst())

    guard let child = obj[key] else { return [] }

    if rest.isEmpty {
        // Leaf node
        return extractLeaf(child, kind: kind)
    }
    return extractCodePairs(from: child, pathComponents: rest, kind: kind)
}

private func extractLeaf(_ value: Any, kind: BindingKind) -> [(system: String, code: String)] {
    switch kind {
    case .code:
        if let array = value as? [Any] {
            return array.compactMap { $0 as? String }.map { ("", $0) }
        }
        if let str = value as? String { return [("", str)] }
        return []

    case .codeableConcept:
        func fromCodable(_ obj: [String: Any]) -> [(String, String)] {
            guard let codings = obj["coding"] as? [[String: Any]] else { return [] }
            return codings.compactMap { c -> (String, String)? in
                guard let code = c["code"] as? String else { return nil }
                let system = c["system"] as? String ?? ""
                return (system, code)
            }
        }
        if let array = value as? [[String: Any]] { return array.flatMap(fromCodable) }
        if let obj = value as? [String: Any] { return fromCodable(obj) }
        return []
    }
}

// ── Error type ────────────────────────────────────────────────────────────────

public struct TerminologyValidationError: Error, Sendable {
    public let violations: [String]
}
