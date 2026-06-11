import Foundation

/// Extracts the `Goal.xxx` part from a multi-resource FHIRPath expression.
func goalExpr(from expression: String) -> String? {
    for part in expression.components(separatedBy: " | ") {
        var clean = part.trimmingCharacters(in: .whitespaces)
        if clean.hasPrefix("(") { clean = String(clean.dropFirst()) }
        guard clean.hasPrefix("Goal.") else { continue }
        clean = clean.components(separatedBy: " as ")[0]
        clean = clean.components(separatedBy: ".where(")[0]
        return clean.trimmingCharacters(in: .whitespaces)
    }
    // Handle single-expression form: "(Goal.start as date)" → "Goal.start"
    let s = expression.trimmingCharacters(in: .whitespaces)
    if s.hasPrefix("(Goal.") {
        let inner = String(s.dropFirst())  // remove leading (
        let part = inner.components(separatedBy: " as ")[0]
        return part.trimmingCharacters(in: .whitespaces)
    }
    return nil
}

/// Returns the Swift function body for a given Goal param.
func goalHandler(spec: ParamSpec, expr: String) -> String? {
    let code = spec.code
    let fn = "extract_Goal_\(code.replacingOccurrences(of: "-", with: "_"))"
    let header = "// \(code) [\(spec.type)] — \(expr)"

    switch code {

    // ── token: lifecycle-status (REQUIRED) ────────────────────────────────────
    case "lifecycle-status":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ g: Goal) {
            if let v = g.lifecycleStatus.value?.rawValue {
                p.tokens.append(.init(paramName: "\(code)",
                                      system: "http://hl7.org/fhir/goal-status", code: v))
            }
        }
        """

    // ── token: achievement-status ─────────────────────────────────────────────
    case "achievement-status":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ g: Goal) {
            for coding in g.achievementStatus?.coding ?? [] {
                let v = coding.code?.value?.string ?? ""
                let sys = coding.system?.value?.url.absoluteString
                p.tokens.append(.init(paramName: "\(code)", system: sys, code: v))
            }
        }
        """

    // ── token: category ───────────────────────────────────────────────────────
    case "category":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ g: Goal) {
            for cc in g.category ?? [] {
                for coding in cc.coding ?? [] {
                    let v = coding.code?.value?.string ?? ""
                    let sys = coding.system?.value?.url.absoluteString
                    p.tokens.append(.init(paramName: "\(code)", system: sys, code: v))
                }
            }
        }
        """

    // ── token: identifier ─────────────────────────────────────────────────────
    case "identifier":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ g: Goal) {
            for ident in g.identifier ?? [] {
                let v = ident.value?.value?.string ?? ""
                let sys = ident.system?.value?.url.absoluteString
                p.tokens.append(.init(paramName: "\(code)", system: sys, code: v))
            }
        }
        """

    // ── date: start-date ((Goal.start as date) — StartX union) ───────────────
    case "start-date":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ g: Goal) {
            guard let startX = g.start, case .date(let prim) = startX,
                  let dt = prim.value else { return }
            let cal = Calendar(identifier: .gregorian)
            var dc = DateComponents()
            dc.year = dt.year; dc.month = dt.month.map(Int.init)
            dc.day  = dt.day.map(Int.init); dc.hour = 12
            let date = cal.date(from: dc) ?? Date()
            p.dates.append(.init(paramName: "\(code)", dateStart: date, dateEnd: date))
        }
        """

    // ── date: target-date ((Goal.target.due as date) — DueX union in array) ──
    case "target-date":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ g: Goal) {
            let cal = Calendar(identifier: .gregorian)
            for target in g.target ?? [] {
                guard let dueX = target.due, case .date(let prim) = dueX,
                      let dt = prim.value else { continue }
                var dc = DateComponents()
                dc.year = dt.year; dc.month = dt.month.map(Int.init)
                dc.day  = dt.day.map(Int.init); dc.hour = 12
                let date = cal.date(from: dc) ?? Date()
                p.dates.append(.init(paramName: "\(code)", dateStart: date, dateEnd: date))
            }
        }
        """

    // ── reference: subject (REQUIRED) ────────────────────────────────────────
    case "subject":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ g: Goal) {
            guard let refStr = g.subject.reference?.value?.string else { return }
            let parts = refStr.split(separator: "/")
            let (refType, refId): (String?, String) = parts.count == 2
                ? (String(parts[0]), String(parts[1]))
                : (nil, refStr)
            p.references.append(.init(paramName: "\(code)", refType: refType, refId: refId))
        }
        """

    // ── token: description (REQUIRED CodeableConcept — FHIRModels renames to description_fhir) ──
    case "description":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ g: Goal) {
            for coding in g.description_fhir.coding ?? [] {
                let v = coding.code?.value?.string ?? ""
                let sys = coding.system?.value?.url.absoluteString
                p.tokens.append(.init(paramName: "\(code)", system: sys, code: v))
            }
            if let text = g.description_fhir.text?.value?.string {
                p.tokens.append(.init(paramName: "\(code)", system: nil, code: text))
            }
        }
        """

    // ── reference: patient (same field as subject, filtered to Patient) ───────
    case "patient":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ g: Goal) {
            guard let refStr = g.subject.reference?.value?.string else { return }
            let parts = refStr.split(separator: "/")
            let (refType, refId): (String?, String) = parts.count == 2
                ? (String(parts[0]), String(parts[1]))
                : (nil, refStr)
            p.references.append(.init(paramName: "\(code)", refType: refType, refId: refId))
        }
        """

    default:
        return nil
    }
}
