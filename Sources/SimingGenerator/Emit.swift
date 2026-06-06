import Foundation

private let generatedHeader = """
// GENERATED — do not edit directly.
// Source: Resources/fhir/search-parameters-r4.json
// Regenerate: swift run SimingGenerator
"""

func generateGoalExtractor(params: [ParamSpec]) -> String {
    let fnPrefix = "extract_Goal_"

    let resolved: [(ParamSpec, String?)] = params.map { spec in
        (spec, goalExpr(from: spec.expression))
    }

    let dispatchLines = resolved.map { spec, _ in
        let swiftCode = spec.code.replacingOccurrences(of: "-", with: "_")
        return "    \(fnPrefix)\(swiftCode)(&p, g)"
    }.joined(separator: "\n")

    let functionBodies = resolved.map { spec, expr -> String in
        let swiftCode = spec.code.replacingOccurrences(of: "-", with: "_")
        let fn = "\(fnPrefix)\(swiftCode)"
        if let e = expr, let body = goalHandler(spec: spec, expr: e) {
            return body
        }
        return """
        // TODO: unhandled — \(spec.code) [\(spec.type)] \(spec.expression)
        private func \(fn)(_ p: inout SearchParams, _ g: Goal) {}
        """
    }.joined(separator: "\n\n")

    return """
    \(generatedHeader)

    import Foundation
    import ModelsR4

    /// Extracts all supported search parameters from a Goal for insertion
    /// into the five idx_* index tables.
    ///
    /// Params marked TODO are recognised by the FHIR R4 spec but not yet implemented.
    public func extractGoalSearchParams(_ g: Goal) -> SearchParams {
        var p = SearchParams()
    \(dispatchLines)
        return p
    }

    \(functionBodies)
    """
}

func generateCarePlanExtractor(params: [ParamSpec]) -> String {
    let fnPrefix = "extract_CarePlan_"

    let resolved: [(ParamSpec, String?)] = params.map { spec in
        (spec, carePlanExpr(from: spec.expression))
    }

    let dispatchLines = resolved.map { spec, _ in
        let swiftCode = spec.code.replacingOccurrences(of: "-", with: "_")
        return "    \(fnPrefix)\(swiftCode)(&p, c)"
    }.joined(separator: "\n")

    let functionBodies = resolved.map { spec, expr -> String in
        let swiftCode = spec.code.replacingOccurrences(of: "-", with: "_")
        let fn = "\(fnPrefix)\(swiftCode)"
        if let e = expr, let body = carePlanHandler(spec: spec, expr: e) {
            return body
        }
        return """
        // TODO: unhandled — \(spec.code) [\(spec.type)] \(spec.expression)
        private func \(fn)(_ p: inout SearchParams, _ c: CarePlan) {}
        """
    }.joined(separator: "\n\n")

    return """
    \(generatedHeader)

    import Foundation
    import ModelsR4

    /// Extracts all supported search parameters from a CarePlan for insertion
    /// into the five idx_* index tables.
    ///
    /// Params marked TODO are recognised by the FHIR R4 spec but not yet implemented.
    public func extractCarePlanSearchParams(_ c: CarePlan) -> SearchParams {
        var p = SearchParams()
    \(dispatchLines)
        return p
    }

    \(functionBodies)
    """
}

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

func generateMedicationExtractor(params: [ParamSpec]) -> String {
    let fnPrefix = "extract_Medication_"

    let resolved: [(ParamSpec, String?)] = params.map { spec in
        (spec, medicationExpr(from: spec.expression))
    }

    let dispatchLines = resolved.map { spec, _ in
        let swiftCode = spec.code.replacingOccurrences(of: "-", with: "_")
        return "    \(fnPrefix)\(swiftCode)(&p, med)"
    }.joined(separator: "\n")

    let functionBodies = resolved.map { spec, expr -> String in
        let swiftCode = spec.code.replacingOccurrences(of: "-", with: "_")
        let fn = "\(fnPrefix)\(swiftCode)"
        if let e = expr, let body = medicationHandler(spec: spec, expr: e) {
            return body
        }
        return """
        // TODO: unhandled — \(spec.code) [\(spec.type)] \(spec.expression)
        private func \(fn)(_ p: inout SearchParams, _ med: Medication) {}
        """
    }.joined(separator: "\n\n")

    return """
    \(generatedHeader)

    import Foundation
    import ModelsR4

    /// Extracts all supported search parameters from a Medication for insertion
    /// into the five idx_* index tables.
    ///
    /// Params marked TODO are recognised by the FHIR R4 spec but not yet implemented.
    public func extractMedicationSearchParams(_ med: Medication) -> SearchParams {
        var p = SearchParams()
    \(dispatchLines)
        return p
    }

    \(functionBodies)
    """
}

func generateMedicationRequestExtractor(params: [ParamSpec]) -> String {
    let fnPrefix = "extract_MedicationRequest_"

    let resolved: [(ParamSpec, String?)] = params.map { spec in
        (spec, medicationRequestExpr(from: spec.expression))
    }

    let dispatchLines = resolved.map { spec, _ in
        let swiftCode = spec.code.replacingOccurrences(of: "-", with: "_")
        return "    \(fnPrefix)\(swiftCode)(&p, mr)"
    }.joined(separator: "\n")

    let functionBodies = resolved.map { spec, expr -> String in
        let swiftCode = spec.code.replacingOccurrences(of: "-", with: "_")
        let fn = "\(fnPrefix)\(swiftCode)"
        if let e = expr, let body = medicationRequestHandler(spec: spec, expr: e) {
            return body
        }
        return """
        // TODO: unhandled — \(spec.code) [\(spec.type)] \(spec.expression)
        private func \(fn)(_ p: inout SearchParams, _ mr: MedicationRequest) {}
        """
    }.joined(separator: "\n\n")

    return """
    \(generatedHeader)

    import Foundation
    import ModelsR4

    /// Extracts all supported search parameters from a MedicationRequest for insertion
    /// into the five idx_* index tables.
    ///
    /// Params marked TODO are recognised by the FHIR R4 spec but not yet implemented.
    public func extractMedicationRequestSearchParams(_ mr: MedicationRequest) -> SearchParams {
        var p = SearchParams()
    \(dispatchLines)
        return p
    }

    \(functionBodies)
    """
}

func generateAllergyIntoleranceExtractor(params: [ParamSpec]) -> String {
    let fnPrefix = "extract_AllergyIntolerance_"

    let resolved: [(ParamSpec, String?)] = params.map { spec in
        (spec, allergyIntoleranceExpr(from: spec.expression))
    }

    let dispatchLines = resolved.map { spec, _ in
        let swiftCode = spec.code.replacingOccurrences(of: "-", with: "_")
        return "    \(fnPrefix)\(swiftCode)(&p, ai)"
    }.joined(separator: "\n")

    let functionBodies = resolved.map { spec, expr -> String in
        let swiftCode = spec.code.replacingOccurrences(of: "-", with: "_")
        let fn = "\(fnPrefix)\(swiftCode)"
        if let e = expr, let body = allergyIntoleranceHandler(spec: spec, expr: e) {
            return body
        }
        return """
        // TODO: unhandled — \(spec.code) [\(spec.type)] \(spec.expression)
        private func \(fn)(_ p: inout SearchParams, _ ai: AllergyIntolerance) {}
        """
    }.joined(separator: "\n\n")

    return """
    \(generatedHeader)

    import Foundation
    import ModelsR4

    /// Extracts all supported search parameters from an AllergyIntolerance for insertion
    /// into the five idx_* index tables.
    ///
    /// Params marked TODO are recognised by the FHIR R4 spec but not yet implemented.
    public func extractAllergyIntoleranceSearchParams(_ ai: AllergyIntolerance) -> SearchParams {
        var p = SearchParams()
    \(dispatchLines)
        return p
    }

    \(functionBodies)
    """
}

func generateProcedureExtractor(params: [ParamSpec]) -> String {
    let fnPrefix = "extract_Procedure_"

    let resolved: [(ParamSpec, String?)] = params.map { spec in
        (spec, procedureExpr(from: spec.expression))
    }

    let dispatchLines = resolved.map { spec, _ in
        let swiftCode = spec.code.replacingOccurrences(of: "-", with: "_")
        return "    \(fnPrefix)\(swiftCode)(&p, proc)"
    }.joined(separator: "\n")

    let functionBodies = resolved.map { spec, expr -> String in
        let swiftCode = spec.code.replacingOccurrences(of: "-", with: "_")
        let fn = "\(fnPrefix)\(swiftCode)"
        if let e = expr, let body = procedureHandler(spec: spec, expr: e) {
            return body
        }
        return """
        // TODO: unhandled — \(spec.code) [\(spec.type)] \(spec.expression)
        private func \(fn)(_ p: inout SearchParams, _ proc: Procedure) {}
        """
    }.joined(separator: "\n\n")

    return """
    \(generatedHeader)

    import Foundation
    import ModelsR4

    /// Extracts all supported search parameters from a Procedure for insertion
    /// into the five idx_* index tables.
    ///
    /// Params marked TODO are recognised by the FHIR R4 spec but not yet implemented.
    public func extractProcedureSearchParams(_ proc: Procedure) -> SearchParams {
        var p = SearchParams()
    \(dispatchLines)
        return p
    }

    \(functionBodies)
    """
}

func generateDiagnosticReportExtractor(params: [ParamSpec]) -> String {
    let fnPrefix = "extract_DiagnosticReport_"

    let resolved: [(ParamSpec, String?)] = params.map { spec in
        (spec, diagnosticReportExpr(from: spec.expression))
    }

    let dispatchLines = resolved.map { spec, _ in
        let swiftCode = spec.code.replacingOccurrences(of: "-", with: "_")
        return "    \(fnPrefix)\(swiftCode)(&p, dr)"
    }.joined(separator: "\n")

    let functionBodies = resolved.map { spec, expr -> String in
        let swiftCode = spec.code.replacingOccurrences(of: "-", with: "_")
        let fn = "\(fnPrefix)\(swiftCode)"
        if let e = expr, let body = diagnosticReportHandler(spec: spec, expr: e) {
            return body
        }
        return """
        // TODO: unhandled — \(spec.code) [\(spec.type)] \(spec.expression)
        private func \(fn)(_ p: inout SearchParams, _ dr: DiagnosticReport) {}
        """
    }.joined(separator: "\n\n")

    return """
    \(generatedHeader)

    import Foundation
    import ModelsR4

    /// Extracts all supported search parameters from a DiagnosticReport for insertion
    /// into the five idx_* index tables.
    ///
    /// Params marked TODO are recognised by the FHIR R4 spec but not yet implemented.
    public func extractDiagnosticReportSearchParams(_ dr: DiagnosticReport) -> SearchParams {
        var p = SearchParams()
    \(dispatchLines)
        return p
    }

    \(functionBodies)
    """
}

func generateImmunizationExtractor(params: [ParamSpec]) -> String {
    let fnPrefix = "extract_Immunization_"

    let resolved: [(ParamSpec, String?)] = params.map { spec in
        (spec, immunizationExpr(from: spec.expression))
    }

    let dispatchLines = resolved.map { spec, _ in
        let swiftCode = spec.code.replacingOccurrences(of: "-", with: "_")
        return "    \(fnPrefix)\(swiftCode)(&p, imm)"
    }.joined(separator: "\n")

    let functionBodies = resolved.map { spec, expr -> String in
        let swiftCode = spec.code.replacingOccurrences(of: "-", with: "_")
        let fn = "\(fnPrefix)\(swiftCode)"
        if let e = expr, let body = immunizationHandler(spec: spec, expr: e) {
            return body
        }
        return """
        // TODO: unhandled — \(spec.code) [\(spec.type)] \(spec.expression)
        private func \(fn)(_ p: inout SearchParams, _ imm: Immunization) {}
        """
    }.joined(separator: "\n\n")

    return """
    \(generatedHeader)

    import Foundation
    import ModelsR4

    /// Extracts all supported search parameters from an Immunization for insertion
    /// into the five idx_* index tables.
    ///
    /// Params marked TODO are recognised by the FHIR R4 spec but not yet implemented.
    public func extractImmunizationSearchParams(_ imm: Immunization) -> SearchParams {
        var p = SearchParams()
    \(dispatchLines)
        return p
    }

    \(functionBodies)
    """
}

func generatePractitionerExtractor(params: [ParamSpec]) -> String {
    let fnPrefix = "extract_Practitioner_"

    let resolved: [(ParamSpec, String?)] = params.map { spec in
        (spec, practitionerExpr(from: spec.expression))
    }

    let dispatchLines = resolved.map { spec, _ in
        let swiftCode = spec.code.replacingOccurrences(of: "-", with: "_")
        return "    \(fnPrefix)\(swiftCode)(&p, prac)"
    }.joined(separator: "\n")

    let functionBodies = resolved.map { spec, expr -> String in
        let swiftCode = spec.code.replacingOccurrences(of: "-", with: "_")
        let fn = "\(fnPrefix)\(swiftCode)"
        if let e = expr, let body = practitionerHandler(spec: spec, expr: e) {
            return body
        }
        return """
        // TODO: unhandled — \(spec.code) [\(spec.type)] \(spec.expression)
        private func \(fn)(_ p: inout SearchParams, _ prac: Practitioner) {}
        """
    }.joined(separator: "\n\n")

    return """
    \(generatedHeader)

    import Foundation
    import ModelsR4

    /// Extracts all supported search parameters from a Practitioner for insertion
    /// into the five idx_* index tables.
    ///
    /// Params marked TODO are recognised by the FHIR R4 spec but not yet implemented.
    public func extractPractitionerSearchParams(_ prac: Practitioner) -> SearchParams {
        var p = SearchParams()
    \(dispatchLines)
        return p
    }

    \(functionBodies)
    """
}

func generateLocationExtractor(params: [ParamSpec]) -> String {
    let fnPrefix = "extract_Location_"

    let resolved: [(ParamSpec, String?)] = params.map { spec in
        (spec, locationExpr(from: spec.expression))
    }

    let dispatchLines = resolved.map { spec, _ in
        let swiftCode = spec.code.replacingOccurrences(of: "-", with: "_")
        return "    \(fnPrefix)\(swiftCode)(&p, loc)"
    }.joined(separator: "\n")

    let functionBodies = resolved.map { spec, expr -> String in
        let swiftCode = spec.code.replacingOccurrences(of: "-", with: "_")
        let fn = "\(fnPrefix)\(swiftCode)"
        if let e = expr, let body = locationHandler(spec: spec, expr: e) {
            return body
        }
        return """
        // TODO: unhandled — \(spec.code) [\(spec.type)] \(spec.expression)
        private func \(fn)(_ p: inout SearchParams, _ loc: Location) {}
        """
    }.joined(separator: "\n\n")

    return """
    \(generatedHeader)

    import Foundation
    import ModelsR4

    /// Extracts all supported search parameters from a Location for insertion
    /// into the five idx_* index tables.
    ///
    /// Params marked TODO are recognised by the FHIR R4 spec but not yet implemented.
    public func extractLocationSearchParams(_ loc: Location) -> SearchParams {
        var p = SearchParams()
    \(dispatchLines)
        return p
    }

    \(functionBodies)
    """
}

func generateOrganizationExtractor(params: [ParamSpec]) -> String {
    let fnPrefix = "extract_Organization_"

    let resolved: [(ParamSpec, String?)] = params.map { spec in
        (spec, organizationExpr(from: spec.expression))
    }

    let dispatchLines = resolved.map { spec, _ in
        let swiftCode = spec.code.replacingOccurrences(of: "-", with: "_")
        return "    \(fnPrefix)\(swiftCode)(&p, org)"
    }.joined(separator: "\n")

    let functionBodies = resolved.map { spec, expr -> String in
        let swiftCode = spec.code.replacingOccurrences(of: "-", with: "_")
        let fn = "\(fnPrefix)\(swiftCode)"
        if let e = expr, let body = organizationHandler(spec: spec, expr: e) {
            return body
        }
        return """
        // TODO: unhandled — \(spec.code) [\(spec.type)] \(spec.expression)
        private func \(fn)(_ p: inout SearchParams, _ org: Organization) {}
        """
    }.joined(separator: "\n\n")

    return """
    \(generatedHeader)

    import Foundation
    import ModelsR4

    /// Extracts all supported search parameters from an Organization for insertion
    /// into the five idx_* index tables.
    ///
    /// Params marked TODO are recognised by the FHIR R4 spec but not yet implemented.
    public func extractOrganizationSearchParams(_ org: Organization) -> SearchParams {
        var p = SearchParams()
    \(dispatchLines)
        return p
    }

    \(functionBodies)
    """
}

func generateSpecimenExtractor(params: [ParamSpec]) -> String {
    let fnPrefix = "extract_Specimen_"

    let resolved: [(ParamSpec, String?)] = params.map { spec in
        (spec, specimenExpr(from: spec.expression))
    }

    let dispatchLines = resolved.map { spec, _ in
        let swiftCode = spec.code.replacingOccurrences(of: "-", with: "_")
        return "    \(fnPrefix)\(swiftCode)(&p, s)"
    }.joined(separator: "\n")

    let functionBodies = resolved.map { spec, expr -> String in
        let swiftCode = spec.code.replacingOccurrences(of: "-", with: "_")
        let fn = "\(fnPrefix)\(swiftCode)"
        if let e = expr, let body = specimenHandler(spec: spec, expr: e) {
            return body
        }
        return """
        // TODO: unhandled — \(spec.code) [\(spec.type)] \(spec.expression)
        private func \(fn)(_ p: inout SearchParams, _ s: Specimen) {}
        """
    }.joined(separator: "\n\n")

    return """
    \(generatedHeader)

    import Foundation
    import ModelsR4

    /// Extracts all supported search parameters from a Specimen for insertion
    /// into the five idx_* index tables.
    ///
    /// Params marked TODO are recognised by the FHIR R4 spec but not yet implemented.
    public func extractSpecimenSearchParams(_ s: Specimen) -> SearchParams {
        var p = SearchParams()
    \(dispatchLines)
        return p
    }

    \(functionBodies)
    """
}

func generateServiceRequestExtractor(params: [ParamSpec]) -> String {
    let fnPrefix = "extract_ServiceRequest_"

    let resolved: [(ParamSpec, String?)] = params.map { spec in
        (spec, serviceRequestExpr(from: spec.expression))
    }

    let dispatchLines = resolved.map { spec, _ in
        let swiftCode = spec.code.replacingOccurrences(of: "-", with: "_")
        return "    \(fnPrefix)\(swiftCode)(&p, sr)"
    }.joined(separator: "\n")

    let functionBodies = resolved.map { spec, expr -> String in
        let swiftCode = spec.code.replacingOccurrences(of: "-", with: "_")
        let fn = "\(fnPrefix)\(swiftCode)"
        if let e = expr, let body = serviceRequestHandler(spec: spec, expr: e) {
            return body
        }
        return """
        // TODO: unhandled — \(spec.code) [\(spec.type)] \(spec.expression)
        private func \(fn)(_ p: inout SearchParams, _ sr: ServiceRequest) {}
        """
    }.joined(separator: "\n\n")

    return """
    \(generatedHeader)

    import Foundation
    import ModelsR4

    /// Extracts all supported search parameters from a ServiceRequest for insertion
    /// into the five idx_* index tables.
    ///
    /// Params marked TODO are recognised by the FHIR R4 spec but not yet implemented.
    public func extractServiceRequestSearchParams(_ sr: ServiceRequest) -> SearchParams {
        var p = SearchParams()
    \(dispatchLines)
        return p
    }

    \(functionBodies)
    """
}

func generateRelatedPersonExtractor(params: [ParamSpec]) -> String {
    let fnPrefix = "extract_RelatedPerson_"

    let resolved: [(ParamSpec, String?)] = params.map { spec in
        (spec, relatedPersonExpr(from: spec.expression))
    }

    let dispatchLines = resolved.map { spec, _ in
        let swiftCode = spec.code.replacingOccurrences(of: "-", with: "_")
        return "    \(fnPrefix)\(swiftCode)(&p, rp)"
    }.joined(separator: "\n")

    let functionBodies = resolved.map { spec, expr -> String in
        let swiftCode = spec.code.replacingOccurrences(of: "-", with: "_")
        let fn = "\(fnPrefix)\(swiftCode)"
        if let e = expr, let body = relatedPersonHandler(spec: spec, expr: e) {
            return body
        }
        return """
        // TODO: unhandled — \(spec.code) [\(spec.type)] \(spec.expression)
        private func \(fn)(_ p: inout SearchParams, _ rp: RelatedPerson) {}
        """
    }.joined(separator: "\n\n")

    return """
    \(generatedHeader)

    import Foundation
    import ModelsR4

    /// Extracts all supported search parameters from a RelatedPerson for insertion
    /// into the five idx_* index tables.
    ///
    /// Params marked TODO are recognised by the FHIR R4 spec but not yet implemented.
    public func extractRelatedPersonSearchParams(_ rp: RelatedPerson) -> SearchParams {
        var p = SearchParams()
    \(dispatchLines)
        return p
    }

    \(functionBodies)
    """
}

func generateDocumentReferenceExtractor(params: [ParamSpec]) -> String {
    let fnPrefix = "extract_DocumentReference_"

    let resolved: [(ParamSpec, String?)] = params.map { spec in
        (spec, documentReferenceExpr(from: spec.expression))
    }

    let dispatchLines = resolved.map { spec, _ in
        let swiftCode = spec.code.replacingOccurrences(of: "-", with: "_")
        return "    \(fnPrefix)\(swiftCode)(&p, d)"
    }.joined(separator: "\n")

    let functionBodies = resolved.map { spec, expr -> String in
        let swiftCode = spec.code.replacingOccurrences(of: "-", with: "_")
        let fn = "\(fnPrefix)\(swiftCode)"
        if let e = expr, let body = documentReferenceHandler(spec: spec, expr: e) {
            return body
        }
        return """
        // TODO: unhandled — \(spec.code) [\(spec.type)] \(spec.expression)
        private func \(fn)(_ p: inout SearchParams, _ d: DocumentReference) {}
        """
    }.joined(separator: "\n\n")

    return """
    \(generatedHeader)

    import Foundation
    import ModelsR4

    /// Extracts all supported search parameters from a DocumentReference for insertion
    /// into the five idx_* index tables.
    ///
    /// Params marked TODO are recognised by the FHIR R4 spec but not yet implemented.
    public func extractDocumentReferenceSearchParams(_ d: DocumentReference) -> SearchParams {
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
