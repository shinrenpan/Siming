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

    // ── reference: participant / practitioner (both index same field) ────────
    case "Encounter.participant.individual":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ enc: Encounter) {
            for part in enc.participant ?? [] {
                guard let refStr = part.individual?.reference?.value?.string else { continue }
                let parts = refStr.split(separator: "/")
                let (refType, refId): (String?, String) = parts.count == 2
                    ? (String(parts[0]), String(parts[1]))
                    : (nil, refStr)
                p.references.append(.init(paramName: "\(code)", refType: refType, refId: refId))
            }
        }
        """

    // ── token: reason-code ────────────────────────────────────────────────────
    case "Encounter.reasonCode":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ enc: Encounter) {
            for cc in enc.reasonCode ?? [] {
                for coding in cc.coding ?? [] {
                    let c = coding.code?.value?.string ?? ""
                    let s = coding.system?.value?.url.absoluteString
                    p.tokens.append(.init(paramName: "\(code)", system: s, code: c))
                }
            }
        }
        """

    // ── reference: part-of ────────────────────────────────────────────────────
    case "Encounter.partOf":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ enc: Encounter) {
            guard let refStr = enc.partOf?.reference?.value?.string else { return }
            let parts = refStr.split(separator: "/")
            let (refType, refId): (String?, String) = parts.count == 2
                ? (String(parts[0]), String(parts[1]))
                : (nil, refStr)
            p.references.append(.init(paramName: "\(code)", refType: refType, refId: refId))
        }
        """

    // ── reference: service-provider ───────────────────────────────────────────
    case "Encounter.serviceProvider":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ enc: Encounter) {
            guard let refStr = enc.serviceProvider?.reference?.value?.string else { return }
            let parts = refStr.split(separator: "/")
            let (refType, refId): (String?, String) = parts.count == 2
                ? (String(parts[0]), String(parts[1]))
                : (nil, refStr)
            p.references.append(.init(paramName: "\(code)", refType: refType, refId: refId))
        }
        """

    // ── reference: based-on ──────────────────────────────────────────────────
    case "Encounter.basedOn":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ enc: Encounter) {
            for ref in enc.basedOn ?? [] {
                guard let refStr = ref.reference?.value?.string else { continue }
                let parts = refStr.split(separator: "/")
                let (refType, refId): (String?, String) = parts.count == 2
                    ? (String(parts[0]), String(parts[1]))
                    : (nil, refStr)
                p.references.append(.init(paramName: "\(code)", refType: refType, refId: refId))
            }
        }
        """

    // ── reference: location ───────────────────────────────────────────────────
    case "Encounter.location.location":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ enc: Encounter) {
            for loc in enc.location ?? [] {
                guard let refStr = loc.location.reference?.value?.string else { continue }
                let parts = refStr.split(separator: "/")
                let (refType, refId): (String?, String) = parts.count == 2
                    ? (String(parts[0]), String(parts[1]))
                    : (nil, refStr)
                p.references.append(.init(paramName: "\(code)", refType: refType, refId: refId))
            }
        }
        """

    // ── reference: diagnosis ──────────────────────────────────────────────────
    case "Encounter.diagnosis.condition":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ enc: Encounter) {
            for diag in enc.diagnosis ?? [] {
                guard let refStr = diag.condition.reference?.value?.string else { continue }
                let parts = refStr.split(separator: "/")
                let (refType, refId): (String?, String) = parts.count == 2
                    ? (String(parts[0]), String(parts[1]))
                    : (nil, refStr)
                p.references.append(.init(paramName: "\(code)", refType: refType, refId: refId))
            }
        }
        """

    // ── reference: account ────────────────────────────────────────────────────
    case "Encounter.account":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ enc: Encounter) {
            for ref in enc.account ?? [] {
                guard let refStr = ref.reference?.value?.string else { continue }
                let parts = refStr.split(separator: "/")
                let (refType, refId): (String?, String) = parts.count == 2
                    ? (String(parts[0]), String(parts[1]))
                    : (nil, refStr)
                p.references.append(.init(paramName: "\(code)", refType: refType, refId: refId))
            }
        }
        """

    // ── reference: appointment ────────────────────────────────────────────────
    case "Encounter.appointment":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ enc: Encounter) {
            for ref in enc.appointment ?? [] {
                guard let refStr = ref.reference?.value?.string else { continue }
                let parts = refStr.split(separator: "/")
                let (refType, refId): (String?, String) = parts.count == 2
                    ? (String(parts[0]), String(parts[1]))
                    : (nil, refStr)
                p.references.append(.init(paramName: "\(code)", refType: refType, refId: refId))
            }
        }
        """

    // ── reference: episode-of-care ────────────────────────────────────────────
    case "Encounter.episodeOfCare":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ enc: Encounter) {
            for ref in enc.episodeOfCare ?? [] {
                guard let refStr = ref.reference?.value?.string else { continue }
                let parts = refStr.split(separator: "/")
                let (refType, refId): (String?, String) = parts.count == 2
                    ? (String(parts[0]), String(parts[1]))
                    : (nil, refStr)
                p.references.append(.init(paramName: "\(code)", refType: refType, refId: refId))
            }
        }
        """

    // ── reference: reason-reference ───────────────────────────────────────────
    case "Encounter.reasonReference":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ enc: Encounter) {
            for ref in enc.reasonReference ?? [] {
                guard let refStr = ref.reference?.value?.string else { continue }
                let parts = refStr.split(separator: "/")
                let (refType, refId): (String?, String) = parts.count == 2
                    ? (String(parts[0]), String(parts[1]))
                    : (nil, refStr)
                p.references.append(.init(paramName: "\(code)", refType: refType, refId: refId))
            }
        }
        """

    // ── date: location-period ─────────────────────────────────────────────────
    case "Encounter.location.period":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ enc: Encounter) {
            let cal = Calendar(identifier: .gregorian)
            for loc in enc.location ?? [] {
                guard let period = loc.period else { continue }
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
        }
        """

    // ── token: participant-type ────────────────────────────────────────────────
    case "Encounter.participant.type":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ enc: Encounter) {
            for part in enc.participant ?? [] {
                for cc in part.type ?? [] {
                    for coding in cc.coding ?? [] {
                        let c = coding.code?.value?.string ?? ""
                        let s = coding.system?.value?.url.absoluteString
                        p.tokens.append(.init(paramName: "\(code)", system: s, code: c))
                    }
                }
            }
        }
        """

    // ── token: special-arrangement ────────────────────────────────────────────
    case "Encounter.hospitalization.specialArrangement":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ enc: Encounter) {
            for cc in enc.hospitalization?.specialArrangement ?? [] {
                for coding in cc.coding ?? [] {
                    let c = coding.code?.value?.string ?? ""
                    let s = coding.system?.value?.url.absoluteString
                    p.tokens.append(.init(paramName: "\(code)", system: s, code: c))
                }
            }
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

    // ── quantity: length (Duration extends Quantity) ──────────────────────────
    case "Encounter.length":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ enc: Encounter) {
            guard let qty = enc.length,
                  let decimalVal = qty.value?.value?.decimal else { return }
            let sys  = qty.system?.value?.url.absoluteString
            let unit = qty.code?.value?.string
            p.quantities.append(.init(paramName: "length", system: sys, code: unit,
                                      value: Decimal(string: decimalVal.description) ?? 0))
        }
        """

    default:
        return nil
    }
}
