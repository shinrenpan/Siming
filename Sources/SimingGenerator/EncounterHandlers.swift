import Foundation

/// Extracts the `Encounter.xxx` part from a multi-resource FHIRPath expression.
func encounterExpr(from expression: String) -> String? {
    for part in expression.components(separatedBy: " | ") {
        var clean = part.trimmingCharacters(in: .whitespaces)
        if clean.hasPrefix("(") { clean = String(clean.dropFirst()) }
        guard clean.hasPrefix("Encounter.") else { continue }
        clean = clean.components(separatedBy: " as ")[0]
        clean = clean.components(separatedBy: ".where(")[0]
        return clean.trimmingCharacters(in: .whitespaces)
    }
    return nil
}

/// Returns the Swift function body for a given Encounter expression,
/// or nil if the expression is not (yet) handled.
func encounterHandler(spec: ParamSpec, expr: String) -> String? {
    let code = spec.code
    let fn = "extract_Encounter_\(code.replacingOccurrences(of: "-", with: "_"))"
    let header = "// \(code) [\(spec.type)] — \(expr)"

    switch expr {

    // ── token: status ─────────────────────────────────────────────────────────
    case "Encounter.status":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ enc: Encounter) {
            if let v = enc.status.value?.rawValue {
                p.tokens.append(.init(paramName: "\(code)",
                                      system: "http://hl7.org/fhir/encounter-status", code: v))
            }
        }
        """

    // ── token: class (Swift reserved word — use backtick) ────────────────────
    case "Encounter.class":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ enc: Encounter) {
            let c = enc.`class`.code?.value?.string ?? ""
            let s = enc.`class`.system?.value?.url.absoluteString
            p.tokens.append(.init(paramName: "\(code)", system: s, code: c))
        }
        """

    // ── token: type ───────────────────────────────────────────────────────────
    case "Encounter.type":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ enc: Encounter) {
            for cc in enc.type ?? [] {
                for coding in cc.coding ?? [] {
                    let c = coding.code?.value?.string ?? ""
                    let s = coding.system?.value?.url.absoluteString
                    p.tokens.append(.init(paramName: "\(code)", system: s, code: c))
                }
            }
        }
        """

    // ── token: identifier ─────────────────────────────────────────────────────
    case "Encounter.identifier":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ enc: Encounter) {
            for ident in enc.identifier ?? [] {
                let v = ident.value?.value?.string ?? ""
                let s = ident.system?.value?.url.absoluteString
                p.tokens.append(.init(paramName: "\(code)", system: s, code: v))
            }
        }
        """

    // ── reference: subject / patient ─────────────────────────────────────────
    case "Encounter.subject":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ enc: Encounter) {
            guard let refStr = enc.subject?.reference?.value?.string else { return }
            let parts = refStr.split(separator: "/")
            let (refType, refId): (String?, String) = parts.count == 2
                ? (String(parts[0]), String(parts[1]))
                : (nil, refStr)
            p.references.append(.init(paramName: "\(code)", refType: refType, refId: refId))
        }
        """

    // ── date: period (Encounter.period → start/end) ───────────────────────────
    case "Encounter.period":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ enc: Encounter) {
            guard let period = enc.period else { return }
            let cal = Calendar(identifier: .gregorian)
            let start: Date
            let end: Date
            if let prim = period.start, let dt = prim.value {
                var dc = DateComponents()
                dc.year = dt.date.year; dc.month = dt.date.month.map(Int.init)
                dc.day  = dt.date.day.map(Int.init); dc.hour = 0
                start = cal.date(from: dc) ?? Date.distantPast
            } else {
                start = Date.distantPast
            }
            if let prim = period.end, let dt = prim.value {
                var dc = DateComponents()
                dc.year = dt.date.year; dc.month = dt.date.month.map(Int.init)
                dc.day  = dt.date.day.map(Int.init); dc.hour = 23; dc.minute = 59
                end = cal.date(from: dc) ?? Date.distantFuture
            } else {
                end = Date.distantFuture
            }
            p.dates.append(.init(paramName: "\(code)", dateStart: start, dateEnd: end))
        }
        """

    default:
        return nil
    }
}
