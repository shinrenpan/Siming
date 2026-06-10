import Foundation

/// Extracts the `Observation.xxx` part from a multi-resource expression.
/// Also strips `.where(resolve() is Patient)` predicates and `(... as Type)` casts.
func observationExpr(from expression: String) -> String? {
    for part in expression.components(separatedBy: " | ") {
        var clean = part.trimmingCharacters(in: .whitespaces)
        // Strip leading "(" from cast expressions like "(Observation.value as Quantity)"
        if clean.hasPrefix("(") { clean = String(clean.dropFirst()) }
        guard clean.hasPrefix("Observation.") else { continue }
        // Strip " as SomeType"
        clean = clean.components(separatedBy: " as ")[0]
        // Strip ".where(...)" predicates
        clean = clean.components(separatedBy: ".where(")[0]
        return clean.trimmingCharacters(in: .whitespaces)
    }
    return nil
}

/// Returns the Swift function body for a given Observation expression,
/// or nil if the expression is not (yet) handled.
func observationHandler(spec: ParamSpec, expr: String) -> String? {
    let code = spec.code
    let fn = "extract_Observation_\(code.replacingOccurrences(of: "-", with: "_"))"
    let header = "// \(code) [\(spec.type)] — \(expr)"

    // ── code-based overrides (expr dispatch gives wrong type for these) ─────────

    // combo-code: must index BOTH obs.code AND component[].code
    if code == "combo-code" {
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ obs: Observation) {
            for coding in obs.code.coding ?? [] {
                let c = coding.code?.value?.string ?? ""
                let s = coding.system?.value?.url.absoluteString
                p.appendToken(paramName: "combo-code", system: s, code: c, display: coding.display?.value?.string)
            }
            for comp in obs.component ?? [] {
                for coding in comp.code.coding ?? [] {
                    let c = coding.code?.value?.string ?? ""
                    let s = coding.system?.value?.url.absoluteString
                    p.appendToken(paramName: "combo-code", system: s, code: c, display: coding.display?.value?.string)
                }
            }
        }
        """
    }

    // data-absent-reason: obs.dataAbsentReason → idx_token
    if code == "data-absent-reason" {
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ obs: Observation) {
            for coding in obs.dataAbsentReason?.coding ?? [] {
                let c = coding.code?.value?.string ?? ""
                let s = coding.system?.value?.url.absoluteString
                p.appendToken(paramName: "data-absent-reason", system: s, code: c, display: coding.display?.value?.string)
            }
        }
        """
    }

    // combo-data-absent-reason: obs.dataAbsentReason | obs.component[].dataAbsentReason
    if code == "combo-data-absent-reason" {
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ obs: Observation) {
            for coding in obs.dataAbsentReason?.coding ?? [] {
                let c = coding.code?.value?.string ?? ""
                let s = coding.system?.value?.url.absoluteString
                p.appendToken(paramName: "combo-data-absent-reason", system: s, code: c, display: coding.display?.value?.string)
            }
            for comp in obs.component ?? [] {
                for coding in comp.dataAbsentReason?.coding ?? [] {
                    let c = coding.code?.value?.string ?? ""
                    let s = coding.system?.value?.url.absoluteString
                    p.appendToken(paramName: "combo-data-absent-reason", system: s, code: c, display: coding.display?.value?.string)
                }
            }
        }
        """
    }

    // component-value-concept: obs.component[].value as CodeableConcept → idx_token
    if code == "component-value-concept" {
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ obs: Observation) {
            for comp in obs.component ?? [] {
                guard case .codeableConcept(let cc) = comp.value else { continue }
                for coding in cc.coding ?? [] {
                    let c = coding.code?.value?.string ?? ""
                    let s = coding.system?.value?.url.absoluteString
                    p.appendToken(paramName: "component-value-concept", system: s, code: c, display: coding.display?.value?.string)
                }
            }
        }
        """
    }

    // value-concept: obs.value as CodeableConcept → idx_token
    if code == "value-concept" {
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ obs: Observation) {
            guard case .codeableConcept(let cc) = obs.value else { return }
            for coding in cc.coding ?? [] {
                let c = coding.code?.value?.string ?? ""
                let s = coding.system?.value?.url.absoluteString
                p.appendToken(paramName: "value-concept", system: s, code: c, display: coding.display?.value?.string)
            }
        }
        """
    }

    // value-date: obs.value as DateTime → idx_date
    if code == "value-date" {
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ obs: Observation) {
            guard case .dateTime(let prim) = obs.value, let dt = prim.value else { return }
            let cal = Calendar(identifier: .gregorian)
            var dc = DateComponents()
            dc.year = dt.date.year; dc.month = dt.date.month.map(Int.init)
            dc.day  = dt.date.day.map(Int.init); dc.hour = 12
            dc.timeZone = dt.timeZone
            let date = cal.date(from: dc) ?? Date()
            p.dates.append(.init(paramName: "value-date", dateStart: date, dateEnd: date))
        }
        """
    }

    // value-string: obs.value as string → idx_string
    if code == "value-string" {
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ obs: Observation) {
            guard case .string(let prim) = obs.value, let s = prim.value?.string else { return }
            p.strings.append(.init(paramName: "value-string", value: s))
        }
        """
    }

    // component-value-quantity: obs.component[].value as Quantity → idx_quantity
    if code == "component-value-quantity" {
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ obs: Observation) {
            for comp in obs.component ?? [] {
                guard case .quantity(let q) = comp.value,
                      let decimalVal = q.value?.value?.decimal else { continue }
                let sys  = q.system?.value?.url.absoluteString
                let unit = q.code?.value?.string
                p.quantities.append(.init(paramName: "component-value-quantity", system: sys, code: unit,
                                          value: Decimal(string: decimalVal.description) ?? 0))
            }
        }
        """
    }

    // component-code-value-quantity: each component (code, valueQuantity) → idx_composite
    if code == "component-code-value-quantity" {
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ obs: Observation) {
            for comp in obs.component ?? [] {
                guard case .quantity(let q) = comp.value,
                      let decimalVal = q.value?.value?.decimal else { continue }
                let val  = NSDecimalNumber(decimal: decimalVal).doubleValue
                let qSys = q.system?.value?.url.absoluteString
                let qCod = q.code?.value?.string
                for coding in comp.code.coding ?? [] {
                    let c1 = coding.code?.value?.string ?? ""
                    let s1 = coding.system?.value?.url.absoluteString
                    p.composites.append(.init(paramName: "component-code-value-quantity",
                        code1System: s1, code1Code: c1, code2System: qSys, code2Code: qCod, value2: val))
                }
            }
        }
        """
    }

    // component-code-value-concept: each component (code, valueConcept) → idx_composite
    if code == "component-code-value-concept" {
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ obs: Observation) {
            for comp in obs.component ?? [] {
                guard case .codeableConcept(let cc) = comp.value else { continue }
                for coding in comp.code.coding ?? [] {
                    let c1 = coding.code?.value?.string ?? ""
                    let s1 = coding.system?.value?.url.absoluteString
                    for vc in cc.coding ?? [] {
                        let c2 = vc.code?.value?.string ?? ""
                        let s2 = vc.system?.value?.url.absoluteString
                        p.composites.append(.init(paramName: "component-code-value-concept",
                            code1System: s1, code1Code: c1, code2System: s2, code2Code: c2))
                    }
                }
            }
        }
        """
    }

    // combo-code-value-quantity: root (obs.code, obs.valueQuantity) + each component → idx_composite
    if code == "combo-code-value-quantity" {
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ obs: Observation) {
            func appendQuantityPair(_ code1: String, _ sys1: String?, _ q: Quantity) {
                guard let decimalVal = q.value?.value?.decimal else { return }
                let val  = NSDecimalNumber(decimal: decimalVal).doubleValue
                let qSys = q.system?.value?.url.absoluteString
                let qCod = q.code?.value?.string
                p.composites.append(.init(paramName: "combo-code-value-quantity",
                    code1System: sys1, code1Code: code1, code2System: qSys, code2Code: qCod, value2: val))
            }
            if case .quantity(let q) = obs.value {
                for coding in obs.code.coding ?? [] {
                    appendQuantityPair(coding.code?.value?.string ?? "", coding.system?.value?.url.absoluteString, q)
                }
            }
            for comp in obs.component ?? [] {
                guard case .quantity(let q) = comp.value else { continue }
                for coding in comp.code.coding ?? [] {
                    appendQuantityPair(coding.code?.value?.string ?? "", coding.system?.value?.url.absoluteString, q)
                }
            }
        }
        """
    }

    // combo-code-value-concept: root (obs.code, obs.valueConcept) + each component → idx_composite
    if code == "combo-code-value-concept" {
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ obs: Observation) {
            func appendConceptPair(_ code1: String, _ sys1: String?, _ cc: CodeableConcept) {
                for vc in cc.coding ?? [] {
                    let c2 = vc.code?.value?.string ?? ""
                    let s2 = vc.system?.value?.url.absoluteString
                    p.composites.append(.init(paramName: "combo-code-value-concept",
                        code1System: sys1, code1Code: code1, code2System: s2, code2Code: c2))
                }
            }
            if case .codeableConcept(let cc) = obs.value {
                for coding in obs.code.coding ?? [] {
                    appendConceptPair(coding.code?.value?.string ?? "", coding.system?.value?.url.absoluteString, cc)
                }
            }
            for comp in obs.component ?? [] {
                guard case .codeableConcept(let cc) = comp.value else { continue }
                for coding in comp.code.coding ?? [] {
                    appendConceptPair(coding.code?.value?.string ?? "", coding.system?.value?.url.absoluteString, cc)
                }
            }
        }
        """
    }

    // combo-value-concept: obs.value as CodeableConcept | obs.component[].value as CodeableConcept → idx_token
    if code == "combo-value-concept" {
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ obs: Observation) {
            if case .codeableConcept(let cc) = obs.value {
                for coding in cc.coding ?? [] {
                    let c = coding.code?.value?.string ?? ""
                    let s = coding.system?.value?.url.absoluteString
                    p.appendToken(paramName: "combo-value-concept", system: s, code: c, display: coding.display?.value?.string)
                }
            }
            for comp in obs.component ?? [] {
                guard case .codeableConcept(let cc) = comp.value else { continue }
                for coding in cc.coding ?? [] {
                    let c = coding.code?.value?.string ?? ""
                    let s = coding.system?.value?.url.absoluteString
                    p.appendToken(paramName: "combo-value-concept", system: s, code: c, display: coding.display?.value?.string)
                }
            }
        }
        """
    }

    // combo-value-quantity: obs.value as Quantity | obs.component[].value as Quantity → idx_quantity
    if code == "combo-value-quantity" {
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ obs: Observation) {
            if case .quantity(let q) = obs.value,
               let decimalVal = q.value?.value?.decimal {
                let sys  = q.system?.value?.url.absoluteString
                let unit = q.code?.value?.string
                p.quantities.append(.init(paramName: "combo-value-quantity", system: sys, code: unit,
                                          value: Decimal(string: decimalVal.description) ?? 0))
            }
            for comp in obs.component ?? [] {
                guard case .quantity(let q) = comp.value,
                      let decimalVal = q.value?.value?.decimal else { continue }
                let sys  = q.system?.value?.url.absoluteString
                let unit = q.code?.value?.string
                p.quantities.append(.init(paramName: "combo-value-quantity", system: sys, code: unit,
                                          value: Decimal(string: decimalVal.description) ?? 0))
            }
        }
        """
    }

    // part-of: obs.partOf[] → idx_reference
    if code == "part-of" {
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ obs: Observation) {
            for ref in obs.partOf ?? [] {
                guard let refStr = ref.reference?.value?.string else { continue }
                let parts = refStr.split(separator: "/")
                let (refType, refId): (String?, String) = parts.count == 2
                    ? (String(parts[0]), String(parts[1]))
                    : (nil, refStr)
                p.references.append(.init(paramName: "part-of", refType: refType, refId: refId))
            }
        }
        """
    }

    switch expr {

    // ── token: code ───────────────────────────────────────────────────────────
    case "Observation.code":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ obs: Observation) {
            for coding in obs.code.coding ?? [] {
                let c = coding.code?.value?.string ?? ""
                let s = coding.system?.value?.url.absoluteString
                p.appendToken(paramName: "\(code)", system: s, code: c, display: coding.display?.value?.string)
            }
            if let text = obs.code.text?.value?.string {
                p.tokens.append(.init(paramName: "\(code)", system: nil, code: text))
            }
            p.appendConceptText(paramName: "\(code)", obs.code.text?.value?.string)
        }
        """

    // ── token: status ─────────────────────────────────────────────────────────
    case "Observation.status":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ obs: Observation) {
            if let v = obs.status.value?.rawValue {
                p.tokens.append(.init(paramName: "\(code)",
                                      system: "http://hl7.org/fhir/observation-status", code: v))
            }
        }
        """

    // ── token: category ───────────────────────────────────────────────────────
    case "Observation.category":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ obs: Observation) {
            for cc in obs.category ?? [] {
                for coding in cc.coding ?? [] {
                    let c = coding.code?.value?.string ?? ""
                    let s = coding.system?.value?.url.absoluteString
                    p.appendToken(paramName: "\(code)", system: s, code: c, display: coding.display?.value?.string)
                }
                p.appendConceptText(paramName: "\(code)", cc.text?.value?.string)
            }
        }
        """

    // ── token: identifier ─────────────────────────────────────────────────────
    case "Observation.identifier":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ obs: Observation) {
            for ident in obs.identifier ?? [] {
                let v = ident.value?.value?.string ?? ""
                let s = ident.system?.value?.url.absoluteString
                p.tokens.append(.init(paramName: "\(code)", system: s, code: v))
            }
        }
        """

    // ── token: method ─────────────────────────────────────────────────────────
    case "Observation.method":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ obs: Observation) {
            for coding in obs.method?.coding ?? [] {
                let c = coding.code?.value?.string ?? ""
                let s = coding.system?.value?.url.absoluteString
                p.appendToken(paramName: "\(code)", system: s, code: c, display: coding.display?.value?.string)
            }
        }
        """

    // ── token: component-data-absent-reason ──────────────────────────────────
    case "Observation.component.dataAbsentReason":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ obs: Observation) {
            for comp in obs.component ?? [] {
                for coding in comp.dataAbsentReason?.coding ?? [] {
                    let c = coding.code?.value?.string ?? ""
                    let s = coding.system?.value?.url.absoluteString
                    p.appendToken(paramName: "\(code)", system: s, code: c, display: coding.display?.value?.string)
                }
            }
        }
        """

    // ── token: combo-code (code | component.code) ─────────────────────────────
    case "Observation.component.code":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ obs: Observation) {
            for comp in obs.component ?? [] {
                for coding in comp.code.coding ?? [] {
                    let c = coding.code?.value?.string ?? ""
                    let s = coding.system?.value?.url.absoluteString
                    p.appendToken(paramName: "\(code)", system: s, code: c, display: coding.display?.value?.string)
                }
            }
        }
        """

    // ── date: effective ───────────────────────────────────────────────────────
    case "Observation.effective":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ obs: Observation) {
            guard let eff = obs.effective else { return }
            switch eff {
            case .dateTime(let prim):
                guard let dt = prim.value else { return }
                var dc = DateComponents()
                dc.year     = dt.date.year
                dc.month    = dt.date.month.map(Int.init)
                dc.day      = dt.date.day.map(Int.init)
                dc.hour     = dt.time.map { Int($0.hour) } ?? 12
                dc.minute   = dt.time.map { Int($0.minute) }
                dc.timeZone = dt.timeZone
                let d = Calendar(identifier: .gregorian).date(from: dc) ?? Date()
                p.dates.append(.init(paramName: "\(code)", dateStart: d, dateEnd: d))
            case .period(let period):
                let start = period.start.flatMap { prim -> Date? in
                    guard let dt = prim.value else { return nil }
                    var dc = DateComponents()
                    dc.year = dt.date.year; dc.month = dt.date.month.map(Int.init)
                    dc.day  = dt.date.day.map(Int.init); dc.hour = 0
                    return Calendar(identifier: .gregorian).date(from: dc)
                } ?? Date.distantPast
                let end = period.end.flatMap { prim -> Date? in
                    guard let dt = prim.value else { return nil }
                    var dc = DateComponents()
                    dc.year = dt.date.year; dc.month = dt.date.month.map(Int.init)
                    dc.day  = dt.date.day.map(Int.init); dc.hour = 23; dc.minute = 59
                    return Calendar(identifier: .gregorian).date(from: dc)
                } ?? Date.distantFuture
                p.dates.append(.init(paramName: "\(code)", dateStart: start, dateEnd: end))
            case .instant(let prim):
                guard let inst = prim.value else { return }
                var dc = DateComponents()
                dc.year     = inst.date.year
                dc.month    = Int(inst.date.month)
                dc.day      = Int(inst.date.day)
                dc.hour     = Int(inst.time.hour)
                dc.minute   = Int(inst.time.minute)
                dc.timeZone = inst.timeZone
                let d = Calendar(identifier: .gregorian).date(from: dc) ?? Date()
                p.dates.append(.init(paramName: "\(code)", dateStart: d, dateEnd: d))
            case .timing:
                break  // TODO: Timing is complex
            }
        }
        """

    // ── reference: subject / patient (both resolve to Observation.subject) ────
    case "Observation.subject":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ obs: Observation) {
            guard let refStr = obs.subject?.reference?.value?.string else { return }
            let parts = refStr.split(separator: "/")
            let (refType, refId): (String?, String) = parts.count == 2
                ? (String(parts[0]), String(parts[1]))
                : (nil, refStr)
            p.references.append(.init(paramName: "\(code)", refType: refType, refId: refId))
        }
        """

    // ── reference: encounter ──────────────────────────────────────────────────
    case "Observation.encounter":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ obs: Observation) {
            guard let refStr = obs.encounter?.reference?.value?.string else { return }
            let parts = refStr.split(separator: "/")
            let (refType, refId): (String?, String) = parts.count == 2
                ? (String(parts[0]), String(parts[1]))
                : (nil, refStr)
            p.references.append(.init(paramName: "\(code)", refType: refType, refId: refId))
        }
        """

    // ── reference: performer (array) ──────────────────────────────────────────
    case "Observation.performer":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ obs: Observation) {
            for ref in obs.performer ?? [] {
                guard let refStr = ref.reference?.value?.string else { continue }
                let parts = refStr.split(separator: "/")
                let (refType, refId): (String?, String) = parts.count == 2
                    ? (String(parts[0]), String(parts[1]))
                    : (nil, refStr)
                p.references.append(.init(paramName: "\(code)", refType: refType, refId: refId))
            }
        }
        """

    // ── reference: basedOn (array) ────────────────────────────────────────────
    case "Observation.basedOn":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ obs: Observation) {
            for ref in obs.basedOn ?? [] {
                guard let refStr = ref.reference?.value?.string else { continue }
                let parts = refStr.split(separator: "/")
                let (refType, refId): (String?, String) = parts.count == 2
                    ? (String(parts[0]), String(parts[1]))
                    : (nil, refStr)
                p.references.append(.init(paramName: "\(code)", refType: refType, refId: refId))
            }
        }
        """

    // ── reference: specimen, device ───────────────────────────────────────────
    case "Observation.specimen", "Observation.device":
        let prop = expr == "Observation.specimen" ? "specimen" : "device"
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ obs: Observation) {
            guard let refStr = obs.\(prop)?.reference?.value?.string else { return }
            let parts = refStr.split(separator: "/")
            let (refType, refId): (String?, String) = parts.count == 2
                ? (String(parts[0]), String(parts[1]))
                : (nil, refStr)
            p.references.append(.init(paramName: "\(code)", refType: refType, refId: refId))
        }
        """

    // ── reference: hasMember, derivedFrom (arrays) ───────────────────────────
    case "Observation.hasMember", "Observation.derivedFrom":
        let prop = expr == "Observation.hasMember" ? "hasMember" : "derivedFrom"
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ obs: Observation) {
            for ref in obs.\(prop) ?? [] {
                guard let refStr = ref.reference?.value?.string else { continue }
                let parts = refStr.split(separator: "/")
                let (refType, refId): (String?, String) = parts.count == 2
                    ? (String(parts[0]), String(parts[1]))
                    : (nil, refStr)
                p.references.append(.init(paramName: "\(code)", refType: refType, refId: refId))
            }
        }
        """

    // ── reference: focus (array) ─────────────────────────────────────────────
    case "Observation.focus":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ obs: Observation) {
            for ref in obs.focus ?? [] {
                guard let refStr = ref.reference?.value?.string else { continue }
                let parts = refStr.split(separator: "/")
                let (refType, refId): (String?, String) = parts.count == 2
                    ? (String(parts[0]), String(parts[1]))
                    : (nil, refStr)
                p.references.append(.init(paramName: "\(code)", refType: refType, refId: refId))
            }
        }
        """

    // ── quantity: value (as Quantity) ─────────────────────────────────────────
    case "Observation.value":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ obs: Observation) {
            guard case .quantity(let q) = obs.value else { return }
            guard let decimalVal = q.value?.value?.decimal else { return }
            let sys  = q.system?.value?.url.absoluteString
            let unit = q.code?.value?.string
            p.quantities.append(.init(paramName: "\(code)", system: sys, code: unit,
                                      value: Decimal(string: decimalVal.description) ?? 0))
        }
        """

    default:
        return nil
    }
}
