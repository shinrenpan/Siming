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
                p.appendToken(paramName: "\(code)", system: s, code: c, display: coding.display?.value?.string)
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
                p.appendToken(paramName: "\(code)", system: s, code: c, display: coding.display?.value?.string)
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
                p.appendToken(paramName: "\(code)", system: s, code: c, display: coding.display?.value?.string)
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

    // ── date: last-date → lastOccurrence (DateTime) ───────────────────────────
    case "last-date":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ ai: AllergyIntolerance) {
            guard let prim = ai.lastOccurrence, let dt = prim.value else { return }
            var dc = DateComponents()
            dc.year = dt.date.year; dc.month = dt.date.month.map(Int.init)
            dc.day  = dt.date.day.map(Int.init); dc.hour = 12
            dc.timeZone = dt.timeZone
            let d = Calendar(identifier: .gregorian).date(from: dc) ?? Date()
            p.dates.append(.init(paramName: "last-date", dateStart: d, dateEnd: d))
        }
        """

    // ── token: manifestation → reaction[].manifestation[].coding ─────────────
    case "manifestation":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ ai: AllergyIntolerance) {
            for reaction in ai.reaction ?? [] {
                for cc in reaction.manifestation {
                    for coding in cc.coding ?? [] {
                        let c = coding.code?.value?.string ?? ""
                        let s = coding.system?.value?.url.absoluteString
                        p.appendToken(paramName: "manifestation", system: s, code: c, display: coding.display?.value?.string)
                    }
                }
            }
        }
        """

    // ── date: onset → reaction[].onset (DateTime) ────────────────────────────
    case "onset":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ ai: AllergyIntolerance) {
            for reaction in ai.reaction ?? [] {
                guard let prim = reaction.onset, let dt = prim.value else { continue }
                var dc = DateComponents()
                dc.year = dt.date.year; dc.month = dt.date.month.map(Int.init)
                dc.day  = dt.date.day.map(Int.init); dc.hour = 12
                dc.timeZone = dt.timeZone
                let d = Calendar(identifier: .gregorian).date(from: dc) ?? Date()
                p.dates.append(.init(paramName: "onset", dateStart: d, dateEnd: d))
            }
        }
        """

    // ── token: route → reaction[].exposureRoute.coding ───────────────────────
    case "route":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ ai: AllergyIntolerance) {
            for reaction in ai.reaction ?? [] {
                for coding in reaction.exposureRoute?.coding ?? [] {
                    let c = coding.code?.value?.string ?? ""
                    let s = coding.system?.value?.url.absoluteString
                    p.appendToken(paramName: "route", system: s, code: c, display: coding.display?.value?.string)
                }
            }
        }
        """

    // ── token: severity → reaction[].severity (enum) ─────────────────────────
    case "severity":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ ai: AllergyIntolerance) {
            for reaction in ai.reaction ?? [] {
                if let v = reaction.severity?.value?.rawValue {
                    p.tokens.append(.init(paramName: "severity",
                                          system: "http://hl7.org/fhir/reaction-event-severity",
                                          code: v))
                }
            }
        }
        """

    // ── reference: asserter ───────────────────────────────────────────────────
    case "asserter":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ ai: AllergyIntolerance) {
            guard let refStr = ai.asserter?.reference?.value?.string else { return }
            let parts = refStr.split(separator: "/")
            let (refType, refId): (String?, String) = parts.count == 2
                ? (String(parts[0]), String(parts[1]))
                : (nil, refStr)
            p.references.append(.init(paramName: "asserter", refType: refType, refId: refId))
        }
        """

    // ── reference: recorder ───────────────────────────────────────────────────
    case "recorder":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ ai: AllergyIntolerance) {
            guard let refStr = ai.recorder?.reference?.value?.string else { return }
            let parts = refStr.split(separator: "/")
            let (refType, refId): (String?, String) = parts.count == 2
                ? (String(parts[0]), String(parts[1]))
                : (nil, refStr)
            p.references.append(.init(paramName: "recorder", refType: refType, refId: refId))
        }
        """

    default:
        return nil
    }
}
