import Foundation

/// Extracts the `CarePlan.xxx` part from a multi-resource FHIRPath expression.
func carePlanExpr(from expression: String) -> String? {
    for part in expression.components(separatedBy: " | ") {
        var clean = part.trimmingCharacters(in: .whitespaces)
        if clean.hasPrefix("(") { clean = String(clean.dropFirst()) }
        guard clean.hasPrefix("CarePlan.") else { continue }
        clean = clean.components(separatedBy: " as ")[0]
        clean = clean.components(separatedBy: ".where(")[0]
        return clean.trimmingCharacters(in: .whitespaces)
    }
    return nil
}

/// Returns the Swift function body for a given CarePlan param.
func carePlanHandler(spec: ParamSpec, expr: String) -> String? {
    let code = spec.code
    let fn = "extract_CarePlan_\(code.replacingOccurrences(of: "-", with: "_"))"
    let header = "// \(code) [\(spec.type)] — \(expr)"

    switch code {

    // ── token: status (REQUIRED) ──────────────────────────────────────────────
    case "status":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ c: CarePlan) {
            if let v = c.status.value?.rawValue {
                p.tokens.append(.init(paramName: "\(code)",
                                      system: "http://hl7.org/fhir/request-status", code: v))
            }
        }
        """

    // ── token: intent (REQUIRED) ──────────────────────────────────────────────
    case "intent":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ c: CarePlan) {
            if let v = c.intent.value?.rawValue {
                p.tokens.append(.init(paramName: "\(code)",
                                      system: "http://hl7.org/fhir/request-intent", code: v))
            }
        }
        """

    // ── token: category ───────────────────────────────────────────────────────
    case "category":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ c: CarePlan) {
            for cc in c.category ?? [] {
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
        private func \(fn)(_ p: inout SearchParams, _ c: CarePlan) {
            for ident in c.identifier ?? [] {
                let v = ident.value?.value?.string ?? ""
                let sys = ident.system?.value?.url.absoluteString
                p.tokens.append(.init(paramName: "\(code)", system: sys, code: v))
            }
        }
        """

    // ── token: activity-code (nested via activity.detail.code) ───────────────
    case "activity-code":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ c: CarePlan) {
            for act in c.activity ?? [] {
                for coding in act.detail?.code?.coding ?? [] {
                    let v = coding.code?.value?.string ?? ""
                    let sys = coding.system?.value?.url.absoluteString
                    p.tokens.append(.init(paramName: "\(code)", system: sys, code: v))
                }
            }
        }
        """

    // ── date: date (period) ───────────────────────────────────────────────────
    case "date":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ c: CarePlan) {
            guard let period = c.period else { return }
            let cal = Calendar(identifier: .gregorian)
            let start: Date
            let end: Date
            if let prim = period.start, let dt = prim.value {
                var dc = DateComponents()
                dc.year = dt.date.year; dc.month = dt.date.month.map(Int.init)
                dc.day  = dt.date.day.map(Int.init); dc.hour = 0
                start = cal.date(from: dc) ?? Date.distantPast
            } else { start = Date.distantPast }
            if let prim = period.end, let dt = prim.value {
                var dc = DateComponents()
                dc.year = dt.date.year; dc.month = dt.date.month.map(Int.init)
                dc.day  = dt.date.day.map(Int.init); dc.hour = 23; dc.minute = 59
                end = cal.date(from: dc) ?? Date.distantFuture
            } else { end = Date.distantFuture }
            p.dates.append(.init(paramName: "\(code)", dateStart: start, dateEnd: end))
        }
        """

    // ── reference: subject (REQUIRED) ────────────────────────────────────────
    case "subject":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ c: CarePlan) {
            guard let refStr = c.subject.reference?.value?.string else { return }
            let parts = refStr.split(separator: "/")
            let (refType, refId): (String?, String) = parts.count == 2
                ? (String(parts[0]), String(parts[1]))
                : (nil, refStr)
            p.references.append(.init(paramName: "\(code)", refType: refType, refId: refId))
        }
        """

    // ── reference: patient (same field as subject, filtered to Patient) ───────
    case "patient":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ c: CarePlan) {
            guard let refStr = c.subject.reference?.value?.string else { return }
            let parts = refStr.split(separator: "/")
            let (refType, refId): (String?, String) = parts.count == 2
                ? (String(parts[0]), String(parts[1]))
                : (nil, refStr)
            p.references.append(.init(paramName: "\(code)", refType: refType, refId: refId))
        }
        """

    // ── reference: encounter (single) ────────────────────────────────────────
    case "encounter":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ c: CarePlan) {
            guard let refStr = c.encounter?.reference?.value?.string else { return }
            let parts = refStr.split(separator: "/")
            let (refType, refId): (String?, String) = parts.count == 2
                ? (String(parts[0]), String(parts[1]))
                : (nil, refStr)
            p.references.append(.init(paramName: "\(code)", refType: refType, refId: refId))
        }
        """

    // ── reference: care-team (array) ─────────────────────────────────────────
    case "care-team":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ c: CarePlan) {
            for ref in c.careTeam ?? [] {
                guard let refStr = ref.reference?.value?.string else { continue }
                let parts = refStr.split(separator: "/")
                let (refType, refId): (String?, String) = parts.count == 2
                    ? (String(parts[0]), String(parts[1]))
                    : (nil, refStr)
                p.references.append(.init(paramName: "\(code)", refType: refType, refId: refId))
            }
        }
        """

    // ── reference: condition (addresses — array) ──────────────────────────────
    case "condition":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ c: CarePlan) {
            for ref in c.addresses ?? [] {
                guard let refStr = ref.reference?.value?.string else { continue }
                let parts = refStr.split(separator: "/")
                let (refType, refId): (String?, String) = parts.count == 2
                    ? (String(parts[0]), String(parts[1]))
                    : (nil, refStr)
                p.references.append(.init(paramName: "\(code)", refType: refType, refId: refId))
            }
        }
        """

    // ── reference: goal (array) ───────────────────────────────────────────────
    case "goal":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ c: CarePlan) {
            for ref in c.goal ?? [] {
                guard let refStr = ref.reference?.value?.string else { continue }
                let parts = refStr.split(separator: "/")
                let (refType, refId): (String?, String) = parts.count == 2
                    ? (String(parts[0]), String(parts[1]))
                    : (nil, refStr)
                p.references.append(.init(paramName: "\(code)", refType: refType, refId: refId))
            }
        }
        """

    // ── reference: based-on (array) ───────────────────────────────────────────
    case "based-on":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ c: CarePlan) {
            for ref in c.basedOn ?? [] {
                guard let refStr = ref.reference?.value?.string else { continue }
                let parts = refStr.split(separator: "/")
                let (refType, refId): (String?, String) = parts.count == 2
                    ? (String(parts[0]), String(parts[1]))
                    : (nil, refStr)
                p.references.append(.init(paramName: "\(code)", refType: refType, refId: refId))
            }
        }
        """

    // ── reference: part-of (array) ────────────────────────────────────────────
    case "part-of":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ c: CarePlan) {
            for ref in c.partOf ?? [] {
                guard let refStr = ref.reference?.value?.string else { continue }
                let parts = refStr.split(separator: "/")
                let (refType, refId): (String?, String) = parts.count == 2
                    ? (String(parts[0]), String(parts[1]))
                    : (nil, refStr)
                p.references.append(.init(paramName: "\(code)", refType: refType, refId: refId))
            }
        }
        """

    // ── reference: replaces (array) ───────────────────────────────────────────
    case "replaces":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ c: CarePlan) {
            for ref in c.replaces ?? [] {
                guard let refStr = ref.reference?.value?.string else { continue }
                let parts = refStr.split(separator: "/")
                let (refType, refId): (String?, String) = parts.count == 2
                    ? (String(parts[0]), String(parts[1]))
                    : (nil, refStr)
                p.references.append(.init(paramName: "\(code)", refType: refType, refId: refId))
            }
        }
        """

    // ── reference: performer (activity.detail.performer — array of arrays) ────
    case "performer":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ c: CarePlan) {
            for act in c.activity ?? [] {
                for ref in act.detail?.performer ?? [] {
                    guard let refStr = ref.reference?.value?.string else { continue }
                    let parts = refStr.split(separator: "/")
                    let (refType, refId): (String?, String) = parts.count == 2
                        ? (String(parts[0]), String(parts[1]))
                        : (nil, refStr)
                    p.references.append(.init(paramName: "\(code)", refType: refType, refId: refId))
                }
            }
        }
        """

    // ── reference: activity-reference (activity.reference) ───────────────────
    case "activity-reference":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ c: CarePlan) {
            for act in c.activity ?? [] {
                guard let refStr = act.reference?.reference?.value?.string else { continue }
                let parts = refStr.split(separator: "/")
                let (refType, refId): (String?, String) = parts.count == 2
                    ? (String(parts[0]), String(parts[1]))
                    : (nil, refStr)
                p.references.append(.init(paramName: "\(code)", refType: refType, refId: refId))
            }
        }
        """

    default:
        return nil
    }
}
