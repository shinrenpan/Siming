import Foundation

private let generatedHeader = """
// GENERATED — do not edit directly.
// Source: Resources/fhir/search-parameters-r4.json
// Regenerate: swift run SimingGenerator
"""

func generateObservationExtractor(params: [ParamSpec]) -> String {
    let fnPrefix = "extract_Observation_"

    let resolved: [(ParamSpec, String?)] = params.map { spec in
        (spec, observationExpr(from: spec.expression))
    }

    let dispatchLines = resolved.map { spec, _ in
        let swiftCode = spec.code.replacingOccurrences(of: "-", with: "_")
        return "    \(fnPrefix)\(swiftCode)(&p, obs)"
    }.joined(separator: "\n")

    let functionBodies = resolved.map { spec, expr -> String in
        let swiftCode = spec.code.replacingOccurrences(of: "-", with: "_")
        let fn = "\(fnPrefix)\(swiftCode)"

        if let e = expr, let body = observationHandler(spec: spec, expr: e) {
            return body
        }
        return """
        // TODO: unhandled — \(spec.code) [\(spec.type)] \(spec.expression)
        private func \(fn)(_ p: inout SearchParams, _ obs: Observation) {}
        """
    }.joined(separator: "\n\n")

    return """
    \(generatedHeader)

    import Foundation
    import ModelsR4

    /// Extracts all supported search parameters from an Observation for insertion
    /// into the five idx_* index tables.
    ///
    /// Params marked TODO are recognised by the FHIR R4 spec but not yet implemented.
    public func extractObservationSearchParams(_ obs: Observation) -> SearchParams {
        var p = SearchParams()
    \(dispatchLines)
        return p
    }

    \(functionBodies)
    """
}

func generateEncounterExtractor(params: [ParamSpec]) -> String {
    let fnPrefix = "extract_Encounter_"

    let resolved: [(ParamSpec, String?)] = params.map { spec in
        (spec, encounterExpr(from: spec.expression))
    }

    let dispatchLines = resolved.map { spec, _ in
        let swiftCode = spec.code.replacingOccurrences(of: "-", with: "_")
        return "    \(fnPrefix)\(swiftCode)(&p, enc)"
    }.joined(separator: "\n")

    let functionBodies = resolved.map { spec, expr -> String in
        let swiftCode = spec.code.replacingOccurrences(of: "-", with: "_")
        let fn = "\(fnPrefix)\(swiftCode)"
        if let e = expr, let body = encounterHandler(spec: spec, expr: e) {
            return body
        }
        return """
        // TODO: unhandled — \(spec.code) [\(spec.type)] \(spec.expression)
        private func \(fn)(_ p: inout SearchParams, _ enc: Encounter) {}
        """
    }.joined(separator: "\n\n")

    return """
    \(generatedHeader)

    import Foundation
    import ModelsR4

    /// Extracts all supported search parameters from an Encounter for insertion
    /// into the five idx_* index tables.
    ///
    /// Params marked TODO are recognised by the FHIR R4 spec but not yet implemented.
    public func extractEncounterSearchParams(_ enc: Encounter) -> SearchParams {
        var p = SearchParams()
    \(dispatchLines)
        return p
    }

    \(functionBodies)
    """
}

func generateConditionExtractor(params: [ParamSpec]) -> String {
    let fnPrefix = "extract_Condition_"

    let resolved: [(ParamSpec, String?)] = params.map { spec in
        (spec, conditionExpr(from: spec.expression))
    }

    let dispatchLines = resolved.map { spec, _ in
        let swiftCode = spec.code.replacingOccurrences(of: "-", with: "_")
        return "    \(fnPrefix)\(swiftCode)(&p, cond)"
    }.joined(separator: "\n")

    let functionBodies = resolved.map { spec, expr -> String in
        let swiftCode = spec.code.replacingOccurrences(of: "-", with: "_")
        let fn = "\(fnPrefix)\(swiftCode)"
        if let e = expr, let body = conditionHandler(spec: spec, expr: e) {
            return body
        }
        return """
        // TODO: unhandled — \(spec.code) [\(spec.type)] \(spec.expression)
        private func \(fn)(_ p: inout SearchParams, _ cond: Condition) {}
        """
    }.joined(separator: "\n\n")

    return """
    \(generatedHeader)

    import Foundation
    import ModelsR4

    /// Extracts all supported search parameters from a Condition for insertion
    /// into the five idx_* index tables.
    ///
    /// Params marked TODO are recognised by the FHIR R4 spec but not yet implemented.
    public func extractConditionSearchParams(_ cond: Condition) -> SearchParams {
        var p = SearchParams()
    \(dispatchLines)
        return p
    }

    \(functionBodies)
    """
}

func generatePatientExtractor(params: [ParamSpec]) -> String {
    let fnPrefix = "extract_Patient_"

    // Build (param, resolved patient-specific expression) pairs.
    let resolved: [(ParamSpec, String?)] = params.map { spec in
        (spec, patientExpr(from: spec.expression))
    }

    let dispatchLines = resolved.map { spec, _ in
        let swiftCode = spec.code.replacingOccurrences(of: "-", with: "_")
        return "    \(fnPrefix)\(swiftCode)(&p, patient)"
    }.joined(separator: "\n")

    let functionBodies = resolved.map { spec, expr -> String in
        let swiftCode = spec.code.replacingOccurrences(of: "-", with: "_")
        let fn = "\(fnPrefix)\(swiftCode)"

        if let e = expr, let body = patientHandler(spec: spec, expr: e) {
            return body
        }
        // Unhandled — emit a TODO stub so the file still compiles.
        return """
        // TODO: unhandled — \(spec.code) [\(spec.type)] \(spec.expression)
        private func \(fn)(_ p: inout SearchParams, _ patient: Patient) {}
        """
    }.joined(separator: "\n\n")

    return """
    \(generatedHeader)

    import Foundation
    import ModelsR4

    /// Extracts all supported search parameters from a Patient for insertion
    /// into the five idx_* index tables.
    ///
    /// Params marked TODO are recognised by the FHIR R4 spec but not yet implemented.
    public func extractPatientSearchParams(_ patient: Patient) -> SearchParams {
        var p = SearchParams()
    \(dispatchLines)
        return p
    }

    \(functionBodies)
    """
}
