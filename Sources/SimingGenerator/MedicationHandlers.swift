import Foundation

/// Extracts the `Medication.xxx` part from a multi-resource FHIRPath expression.
/// Guards against `MedicationRequest.`, `MedicationAdministration.`, etc.
func medicationExpr(from expression: String) -> String? {
    for part in expression.components(separatedBy: " | ") {
        var clean = part.trimmingCharacters(in: .whitespaces)
        if clean.hasPrefix("(") { clean = String(clean.dropFirst()) }
        guard clean.hasPrefix("Medication.") else { continue }
        clean = clean.components(separatedBy: " as ")[0]
        clean = clean.components(separatedBy: ".where(")[0]
        return clean.trimmingCharacters(in: .whitespaces)
    }
    return nil
}

/// Returns the Swift function body for a given Medication search param.
func medicationHandler(spec: ParamSpec, expr: String) -> String? {
    let code = spec.code
    let fn = "extract_Medication_\(code.replacingOccurrences(of: "-", with: "_"))"
    let header = "// \(code) [\(spec.type)] — \(expr)"

    switch code {

    // ── token: code ───────────────────────────────────────────────────────────
    case "code":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ med: Medication) {
            for coding in med.code?.coding ?? [] {
                let c = coding.code?.value?.string ?? ""
                let s = coding.system?.value?.url.absoluteString
                p.appendToken(paramName: "code", system: s, code: c, display: coding.display?.value?.string)
            }
        }
        """

    // ── token: status ─────────────────────────────────────────────────────────
    case "status":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ med: Medication) {
            if let v = med.status?.value?.rawValue {
                p.tokens.append(.init(paramName: "status",
                                      system: "http://hl7.org/fhir/CodeSystem/medication-status",
                                      code: v))
            }
        }
        """

    // ── token: form ───────────────────────────────────────────────────────────
    case "form":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ med: Medication) {
            for coding in med.form?.coding ?? [] {
                let c = coding.code?.value?.string ?? ""
                let s = coding.system?.value?.url.absoluteString
                p.appendToken(paramName: "form", system: s, code: c, display: coding.display?.value?.string)
            }
        }
        """

    // ── token: identifier ─────────────────────────────────────────────────────
    case "identifier":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ med: Medication) {
            for ident in med.identifier ?? [] {
                let v = ident.value?.value?.string ?? ""
                let s = ident.system?.value?.url.absoluteString
                p.tokens.append(.init(paramName: "identifier", system: s, code: v))
            }
        }
        """

    // ── token: lot-number ─────────────────────────────────────────────────────
    case "lot-number":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ med: Medication) {
            if let v = med.batch?.lotNumber?.value?.string {
                p.tokens.append(.init(paramName: "lot-number", system: nil, code: v))
            }
        }
        """

    // ── token: ingredient-code ────────────────────────────────────────────────
    case "ingredient-code":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ med: Medication) {
            for ing in med.ingredient ?? [] {
                guard case .codeableConcept(let cc) = ing.item else { continue }
                for coding in cc.coding ?? [] {
                    let c = coding.code?.value?.string ?? ""
                    let s = coding.system?.value?.url.absoluteString
                    p.appendToken(paramName: "ingredient-code", system: s, code: c, display: coding.display?.value?.string)
                }
            }
        }
        """

    // ── reference: manufacturer ───────────────────────────────────────────────
    case "manufacturer":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ med: Medication) {
            guard let refStr = med.manufacturer?.reference?.value?.string else { return }
            let parts = refStr.split(separator: "/")
            let (refType, refId): (String?, String) = parts.count == 2
                ? (String(parts[0]), String(parts[1]))
                : (nil, refStr)
            p.references.append(.init(paramName: "manufacturer", refType: refType, refId: refId))
        }
        """

    // ── reference: ingredient ─────────────────────────────────────────────────
    case "ingredient":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ med: Medication) {
            for ing in med.ingredient ?? [] {
                guard case .reference(let ref) = ing.item else { continue }
                guard let refStr = ref.reference?.value?.string else { continue }
                let parts = refStr.split(separator: "/")
                let (refType, refId): (String?, String) = parts.count == 2
                    ? (String(parts[0]), String(parts[1]))
                    : (nil, refStr)
                p.references.append(.init(paramName: "ingredient", refType: refType, refId: refId))
            }
        }
        """

    // ── date: expiration-date ─────────────────────────────────────────────────
    case "expiration-date":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ med: Medication) {
            guard let prim = med.batch?.expirationDate, let dt = prim.value else { return }
            var dc = DateComponents()
            dc.year = dt.date.year; dc.month = dt.date.month.map(Int.init)
            dc.day  = dt.date.day.map(Int.init); dc.hour = 12
            dc.timeZone = dt.timeZone
            let d = Calendar(identifier: .gregorian).date(from: dc) ?? Date()
            p.dates.append(.init(paramName: "expiration-date", dateStart: d, dateEnd: d))
        }
        """

    default:
        return nil
    }
}
