/// Immutable index of CodeSystem and ValueSet resources loaded from FHIR IG packages.
/// Built once at startup; safe for concurrent reads.
public struct TerminologyIndex: Sendable {
    // CodeSystem URL → all codes (flattened, including nested concept hierarchies)
    let codeSystems: [String: Set<String>]

    // Extensional ValueSet URL → valid (system, code) pairs
    let valueSets: [String: Set<TermCode>]

    // ValueSet URLs whose compose.include contains a filter — intensional, skip validation
    let intensionalValueSets: Set<String>

    public var codeSystemCount: Int { codeSystems.count }
    public var valueSetCount: Int { valueSets.count }
    public var intensionalCount: Int { intensionalValueSets.count }

    public init(
        codeSystems: [String: Set<String>],
        valueSets: [String: Set<TermCode>],
        intensionalValueSets: Set<String>
    ) {
        self.codeSystems = codeSystems
        self.valueSets = valueSets
        self.intensionalValueSets = intensionalValueSets
    }

    public static let empty = TerminologyIndex(
        codeSystems: [:], valueSets: [:], intensionalValueSets: []
    )

    /// Returns `true` when `code` is a valid member of the ValueSet at `url`.
    /// Unknown ValueSets and intensional ValueSets always return `true` (conservative pass-through).
    public func isValid(valueSet url: String, system: String, code: String) -> Bool {
        if intensionalValueSets.contains(url) { return true }
        guard let codes = valueSets[url] else { return true }
        return codes.contains(TermCode(system: system, code: code))
    }

    /// Returns `true` when the ValueSet contains `code` in any system.
    /// Used for FHIR `code` type fields where the system is implicit.
    /// Unknown and intensional ValueSets always return `true`.
    public func hasCode(valueSet url: String, code: String) -> Bool {
        if intensionalValueSets.contains(url) { return true }
        guard let codes = valueSets[url] else { return true }
        return codes.contains(where: { $0.code == code })
    }
}

public struct TermCode: Hashable, Sendable {
    public let system: String
    public let code: String

    public init(system: String, code: String) {
        self.system = system
        self.code = code
    }
}
