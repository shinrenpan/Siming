import Foundation

/// Extracts the `AllergyIntolerance.xxx` part from a multi-resource FHIRPath expression.
func allergyIntoleranceExpr(from expression: String) -> String? {
    for part in expression.components(separatedBy: " | ") {
        var clean = part.trimmingCharacters(in: .whitespaces)
        if clean.hasPrefix("(") { clean = String(clean.dropFirst()) }
        guard clean.hasPrefix("AllergyIntolerance.") else { continue }
        clean = clean.components(separatedBy: " as ")[0]
        clean = clean.components(separatedBy: ".where(")[0]
        return clean.trimmingCharacters(in: .whitespaces)
    }
    return nil
}

/// Returns the Swift function body for a given AllergyIntolerance param.
/// Switches on `spec.code` because `date` needs to know it maps to recordedDate.
func allergyIntoleranceHandler(spec: ParamSpec, expr: String) -> String? {
    let code = spec.code
    let fn = "extract_AllergyIntolerance_\(code.replacingOccurrences(of: "-", with: "_"))"
    let header = "// \(code) [\(spec.type)] — \(expr)"

    switch code {

    // ── token: clinical-status (CodeableConcept) ──────────────────────────────
    case "clinical-status":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ ai: AllergyIntolerance) {
            for coding in ai.clinicalStatus?.coding ?? [] {
                let c = coding.code?.value?.string ?? ""
                let s = coding.system?.value?.url.absoluteString
                p.tokens.append(.init(paramName: "\(code)", system: s, code: c))
            }
        }
        """

    // ── token: verification-status (CodeableConcept) ──────────────────────────
    case "verification-status":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ ai: AllergyIntolerance) {
            for coding in ai.verificationStatus?.coding ?? [] {
                let c = coding.code?.value?.string ?? ""
                let s = coding.system?.value?.url.absoluteString
                p.tokens.append(.init(paramName: "\(code)", system: s, code: c))
            }
        }
        """

    // ── token: type (enum primitive) ──────────────────────────────────────────
    case "type":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ ai: AllergyIntolerance) {
            if let v = ai.type?.value?.rawValue {
                p.tokens.append(.init(paramName: "\(code)",
                                      system: "http://hl7.org/fhir/allergy-intolerance-type",
                                      code: v))
            }
        }
        """

    // ── token: criticality (enum primitive) ───────────────────────────────────
    case "criticality":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ ai: AllergyIntolerance) {
            if let v = ai.criticality?.value?.rawValue {
                p.tokens.append(.init(paramName: "\(code)",
                                      system: "http://hl7.org/fhir/allergy-intolerance-criticality",
                                      code: v))
            }
        }
        """

    // ── token: category (array of enum primitives) ────────────────────────────
    case "category":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ ai: AllergyIntolerance) {
            for prim in ai.category ?? [] {
                if let v = prim.value?.rawValue {
                    p.tokens.append(.init(paramName: "\(code)",
                                          system: "http://hl7.org/fhir/allergy-intolerance-category",
                                          code: v))
                }
            }
        }
        """

    // ── token: code (CodeableConcept) ─────────────────────────────────────────
    case "code":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ ai: AllergyIntolerance) {
            for coding in ai.code?.coding ?? [] {
                let c = coding.code?.value?.string ?? ""
                let s = coding.system?.value?.url.absoluteString
                p.tokens.append(.init(paramName: "\(code)", system: s, code: c))
            }
        }
        """

    // ── token: identifier ─────────────────────────────────────────────────────
    case "identifier":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ ai: AllergyIntolerance) {
            for ident in ai.identifier ?? [] {
                let v = ident.value?.value?.string ?? ""
                let s = ident.system?.value?.url.absoluteString
                p.tokens.append(.init(paramName: "\(code)", system: s, code: v))
            }
        }
        """

    // ── reference: patient (non-optional) ────────────────────────────────────
    case "patient":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ ai: AllergyIntolerance) {
            guard let refStr = ai.patient.reference?.value?.string else { return }
            let parts = refStr.split(separator: "/")
            let (refType, refId): (String?, String) = parts.count == 2
                ? (String(parts[0]), String(parts[1]))
                : (nil, refStr)
            p.references.append(.init(paramName: "\(code)", refType: refType, refId: refId))
        }
        """

    // ── date: date → recordedDate ─────────────────────────────────────────────
    case "date":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ ai: AllergyIntolerance) {
            guard let prim = ai.recordedDate, let dt = prim.value else { return }
            var dc = DateComponents()
            dc.year = dt.date.year; dc.month = dt.date.month.map(Int.init)
            dc.day  = dt.date.day.map(Int.init); dc.hour = 12
            dc.timeZone = dt.timeZone
            let d = Calendar(identifier: .gregorian).date(from: dc) ?? Date()
            p.dates.append(.init(paramName: "\(code)", dateStart: d, dateEnd: d))
        }
        """

    default:
        return nil
    }
}
