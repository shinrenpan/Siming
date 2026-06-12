import Foundation

/// Extracts the `Procedure.xxx` part from a multi-resource FHIRPath expression.
func procedureExpr(from expression: String) -> String? {
    for part in expression.components(separatedBy: " | ") {
        var clean = part.trimmingCharacters(in: .whitespaces)
        if clean.hasPrefix("(") { clean = String(clean.dropFirst()) }
        guard clean.hasPrefix("Procedure.") else { continue }
        clean = clean.components(separatedBy: " as ")[0]
        clean = clean.components(separatedBy: ".where(")[0]
        return clean.trimmingCharacters(in: .whitespaces)
    }
    return nil
}

/// Returns the Swift function body for a given Procedure param.
/// Switches on `spec.code` because multiple params (patient/subject) share the same expression.
func procedureHandler(spec: ParamSpec, expr: String) -> String? {
    let code = spec.code
    let fn = "extract_Procedure_\(code.replacingOccurrences(of: "-", with: "_"))"
    let header = "// \(code) [\(spec.type)] — \(expr)"

    switch code {

    // ── token: status ─────────────────────────────────────────────────────────
    case "status":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ proc: Procedure) {
            if let v = proc.status.value?.rawValue {
                p.tokens.append(.init(paramName: "\(code)",
                                      system: "http://hl7.org/fhir/event-status", code: v))
            }
        }
        """

    // ── token: code ───────────────────────────────────────────────────────────
    case "code":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ proc: Procedure) {
            for coding in proc.code?.coding ?? [] {
                let c = coding.code?.value?.string ?? ""
                let s = coding.system?.value?.url.absoluteString
                p.appendToken(paramName: "\(code)", system: s, code: c, display: coding.display?.value?.string)
            }
        }
        """

    // ── token: category ───────────────────────────────────────────────────────
    case "category":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ proc: Procedure) {
            for coding in proc.category?.coding ?? [] {
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
        private func \(fn)(_ p: inout SearchParams, _ proc: Procedure) {
            for ident in proc.identifier ?? [] {
                let v = ident.value?.value?.string ?? ""
                let s = ident.system?.value?.url.absoluteString
                p.tokens.append(.init(paramName: "\(code)", system: s, code: v))
            }
        }
        """

    // ── reference: patient / subject ─────────────────────────────────────────
    case "patient", "subject":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ proc: Procedure) {
            guard let refStr = proc.subject.reference?.value?.string else { return }
            let parts = refStr.split(separator: "/")
            let (refType, refId): (String?, String) = parts.count == 2
                ? (String(parts[0]), String(parts[1]))
                : (nil, refStr)
            p.references.append(.init(paramName: "\(code)", refType: refType, refId: refId))
        }
        """

    // ── reference: encounter ─────────────────────────────────────────────────
    case "encounter":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ proc: Procedure) {
            guard let refStr = proc.encounter?.reference?.value?.string else { return }
            let parts = refStr.split(separator: "/")
            let (refType, refId): (String?, String) = parts.count == 2
                ? (String(parts[0]), String(parts[1]))
                : (nil, refStr)
            p.references.append(.init(paramName: "encounter", refType: refType, refId: refId))
        }
        """

    // ── reference: performer (actor) ─────────────────────────────────────────
    case "performer":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ proc: Procedure) {
            for perf in proc.performer ?? [] {
                guard let refStr = perf.actor.reference?.value?.string else { continue }
                let parts = refStr.split(separator: "/")
                let (refType, refId): (String?, String) = parts.count == 2
                    ? (String(parts[0]), String(parts[1]))
                    : (nil, refStr)
                p.references.append(.init(paramName: "performer", refType: refType, refId: refId))
            }
        }
        """

    // ── reference: based-on ──────────────────────────────────────────────────
    case "based-on":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ proc: Procedure) {
            for ref in proc.basedOn ?? [] {
                guard let refStr = ref.reference?.value?.string else { continue }
                let parts = refStr.split(separator: "/")
                let (refType, refId): (String?, String) = parts.count == 2
                    ? (String(parts[0]), String(parts[1]))
                    : (nil, refStr)
                p.references.append(.init(paramName: "based-on", refType: refType, refId: refId))
            }
        }
        """

    // ── string: instantiates-canonical ───────────────────────────────────────
    case "instantiates-canonical":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ proc: Procedure) {
            for ic in proc.instantiatesCanonical ?? [] {
                guard let url = ic.value?.url.absoluteString else { continue }
                p.strings.append(.init(paramName: "instantiates-canonical", value: url))
            }
        }
        """

    // ── string: instantiates-uri ──────────────────────────────────────────────
    case "instantiates-uri":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ proc: Procedure) {
            for iu in proc.instantiatesUri ?? [] {
                guard let url = iu.value?.url.absoluteString else { continue }
                p.strings.append(.init(paramName: "instantiates-uri", value: url))
            }
        }
        """

    // ── reference: location ───────────────────────────────────────────────────
    case "location":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ proc: Procedure) {
            guard let refStr = proc.location?.reference?.value?.string else { return }
            let parts = refStr.split(separator: "/")
            let (refType, refId): (String?, String) = parts.count == 2
                ? (String(parts[0]), String(parts[1]))
                : (nil, refStr)
            p.references.append(.init(paramName: "location", refType: refType, refId: refId))
        }
        """

    // ── reference: part-of ────────────────────────────────────────────────────
    case "part-of":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ proc: Procedure) {
            for ref in proc.partOf ?? [] {
                guard let refStr = ref.reference?.value?.string else { continue }
                let parts = refStr.split(separator: "/")
                let (refType, refId): (String?, String) = parts.count == 2
                    ? (String(parts[0]), String(parts[1]))
                    : (nil, refStr)
                p.references.append(.init(paramName: "part-of", refType: refType, refId: refId))
            }
        }
        """

    // ── token: reason-code ────────────────────────────────────────────────────
    case "reason-code":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ proc: Procedure) {
            for cc in proc.reasonCode ?? [] {
                for coding in cc.coding ?? [] {
                    let c = coding.code?.value?.string ?? ""
                    let s = coding.system?.value?.url.absoluteString
                    p.appendToken(paramName: "reason-code", system: s, code: c, display: coding.display?.value?.string)
                }
            }
        }
        """

    // ── reference: reason-reference ───────────────────────────────────────────
    case "reason-reference":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ proc: Procedure) {
            for ref in proc.reasonReference ?? [] {
                guard let refStr = ref.reference?.value?.string else { continue }
                let parts = refStr.split(separator: "/")
                let (refType, refId): (String?, String) = parts.count == 2
                    ? (String(parts[0]), String(parts[1]))
                    : (nil, refStr)
                p.references.append(.init(paramName: "reason-reference", refType: refType, refId: refId))
            }
        }
        """

    // ── date: performed (choice type: dateTime or Period) ────────────────────
    case "date":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ proc: Procedure) {
            let cal = Calendar(identifier: .gregorian)
            guard let performed = proc.performed else { return }
            switch performed {
            case .dateTime(let prim):
                guard let dt = prim.value else { return }
                var dc = DateComponents()
                dc.year = dt.date.year; dc.month = dt.date.month.map(Int.init)
                dc.day  = dt.date.day.map(Int.init); dc.hour = 12
                dc.timeZone = dt.timeZone
                let d = cal.date(from: dc) ?? Date()
                p.dates.append(.init(paramName: "date", dateStart: d, dateEnd: d))
            case .period(let period):
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
                p.dates.append(.init(paramName: "date", dateStart: start, dateEnd: end))
            default:
                break
            }
        }
        """

    default:
        return nil
    }
}
