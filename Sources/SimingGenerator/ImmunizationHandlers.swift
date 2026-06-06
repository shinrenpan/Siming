import Foundation

/// Extracts the `Immunization.xxx` part from a multi-resource FHIRPath expression.
func immunizationExpr(from expression: String) -> String? {
    for part in expression.components(separatedBy: " | ") {
        var clean = part.trimmingCharacters(in: .whitespaces)
        if clean.hasPrefix("(") { clean = String(clean.dropFirst()) }
        guard clean.hasPrefix("Immunization.") else { continue }
        clean = clean.components(separatedBy: " as ")[0]
        clean = clean.components(separatedBy: ".where(")[0]
        return clean.trimmingCharacters(in: .whitespaces)
    }
    return nil
}

/// Returns the Swift function body for a given Immunization param.
func immunizationHandler(spec: ParamSpec, expr: String) -> String? {
    let code = spec.code
    let fn = "extract_Immunization_\(code.replacingOccurrences(of: "-", with: "_"))"
    let header = "// \(code) [\(spec.type)] — \(expr)"

    switch code {

    // ── token: status ─────────────────────────────────────────────────────────
    case "status":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ imm: Immunization) {
            if let v = imm.status.value?.rawValue {
                p.tokens.append(.init(paramName: "\(code)",
                                      system: "http://hl7.org/fhir/event-status", code: v))
            }
        }
        """

    // ── token: vaccine-code ───────────────────────────────────────────────────
    case "vaccine-code":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ imm: Immunization) {
            for coding in imm.vaccineCode.coding ?? [] {
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
        private func \(fn)(_ p: inout SearchParams, _ imm: Immunization) {
            for ident in imm.identifier ?? [] {
                let v = ident.value?.value?.string ?? ""
                let s = ident.system?.value?.url.absoluteString
                p.tokens.append(.init(paramName: "\(code)", system: s, code: v))
            }
        }
        """

    // ── reference: patient ────────────────────────────────────────────────────
    case "patient":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ imm: Immunization) {
            guard let refStr = imm.patient.reference?.value?.string else { return }
            let parts = refStr.split(separator: "/")
            let (refType, refId): (String?, String) = parts.count == 2
                ? (String(parts[0]), String(parts[1]))
                : (nil, refStr)
            p.references.append(.init(paramName: "patient", refType: refType, refId: refId))
        }
        """

    // ── reference: performer (actor) ─────────────────────────────────────────
    case "performer":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ imm: Immunization) {
            for perf in imm.performer ?? [] {
                guard let refStr = perf.actor.reference?.value?.string else { continue }
                let parts = refStr.split(separator: "/")
                let (refType, refId): (String?, String) = parts.count == 2
                    ? (String(parts[0]), String(parts[1]))
                    : (nil, refStr)
                p.references.append(.init(paramName: "performer", refType: refType, refId: refId))
            }
        }
        """

    // ── string: lot-number ────────────────────────────────────────────────────
    case "lot-number":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ imm: Immunization) {
            if let v = imm.lotNumber?.value?.string {
                p.strings.append(.init(paramName: "\(code)", value: v))
            }
        }
        """

    // ── date: occurrence (choice type: dateTime or string) ───────────────────
    case "date":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ imm: Immunization) {
            let cal = Calendar(identifier: .gregorian)
            switch imm.occurrence {
            case .dateTime(let prim):
                guard let dt = prim.value else { return }
                var dc = DateComponents()
                dc.year = dt.date.year; dc.month = dt.date.month.map(Int.init)
                dc.day  = dt.date.day.map(Int.init); dc.hour = 12
                dc.timeZone = dt.timeZone
                let d = cal.date(from: dc) ?? Date()
                p.dates.append(.init(paramName: "date", dateStart: d, dateEnd: d))
            default:
                break
            }
        }
        """

    default:
        return nil
    }
}
