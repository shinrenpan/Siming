import Foundation

/// Extracts the `Condition.xxx` base path from a multi-resource FHIRPath expression.
func conditionExpr(from expression: String) -> String? {
    for part in expression.components(separatedBy: " | ") {
        var clean = part.trimmingCharacters(in: .whitespaces)
        if clean.hasPrefix("(") { clean = String(clean.dropFirst()) }
        guard clean.hasPrefix("Condition.") else { continue }
        clean = clean.components(separatedBy: ".where(")[0]
        return clean.trimmingCharacters(in: .whitespaces)
    }
    return nil
}

/// Returns the Swift function body for a given Condition param.
/// Switches on `spec.code` because multiple params share the same expression root
/// (e.g. onset-date / onset-age both derive from Condition.onset).
func conditionHandler(spec: ParamSpec, expr: String) -> String? {
    let code = spec.code
    let fn = "extract_Condition_\(code.replacingOccurrences(of: "-", with: "_"))"
    let header = "// \(code) [\(spec.type)] — \(expr)"

    switch code {

    // ── token: code ───────────────────────────────────────────────────────────
    case "code":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ cond: Condition) {
            for coding in cond.code?.coding ?? [] {
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
        private func \(fn)(_ p: inout SearchParams, _ cond: Condition) {
            for cc in cond.category ?? [] {
                for coding in cc.coding ?? [] {
                    let c = coding.code?.value?.string ?? ""
                    let s = coding.system?.value?.url.absoluteString
                    p.appendToken(paramName: "\(code)", system: s, code: c, display: coding.display?.value?.string)
                }
            }
        }
        """

    // ── token: clinical-status ────────────────────────────────────────────────
    case "clinical-status":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ cond: Condition) {
            for coding in cond.clinicalStatus?.coding ?? [] {
                let c = coding.code?.value?.string ?? ""
                let s = coding.system?.value?.url.absoluteString
                p.appendToken(paramName: "\(code)", system: s, code: c, display: coding.display?.value?.string)
            }
        }
        """

    // ── token: verification-status ────────────────────────────────────────────
    case "verification-status":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ cond: Condition) {
            for coding in cond.verificationStatus?.coding ?? [] {
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
        private func \(fn)(_ p: inout SearchParams, _ cond: Condition) {
            for ident in cond.identifier ?? [] {
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
        private func \(fn)(_ p: inout SearchParams, _ cond: Condition) {
            guard let refStr = cond.subject.reference?.value?.string else { return }
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
        private func \(fn)(_ p: inout SearchParams, _ cond: Condition) {
            guard let refStr = cond.encounter?.reference?.value?.string else { return }
            let parts = refStr.split(separator: "/")
            let (refType, refId): (String?, String) = parts.count == 2
                ? (String(parts[0]), String(parts[1]))
                : (nil, refStr)
            p.references.append(.init(paramName: "encounter", refType: refType, refId: refId))
        }
        """

    // ── date: onset-date (dateTime or Period) ─────────────────────────────────
    case "onset-date":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ cond: Condition) {
            let cal = Calendar(identifier: .gregorian)
            guard let onset = cond.onset else { return }
            switch onset {
            case .dateTime(let prim):
                guard let dt = prim.value else { return }
                var dc = DateComponents()
                dc.year = dt.date.year; dc.month = dt.date.month.map(Int.init)
                dc.day  = dt.date.day.map(Int.init); dc.hour = 12
                let d = cal.date(from: dc) ?? Date()
                p.dates.append(.init(paramName: "\(code)", dateStart: d, dateEnd: d))
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
                p.dates.append(.init(paramName: "\(code)", dateStart: start, dateEnd: end))
            @unknown default:
                break
            }
        }
        """

    // ── date: abatement-date (dateTime or Period) ─────────────────────────────
    case "abatement-date":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ cond: Condition) {
            let cal = Calendar(identifier: .gregorian)
            guard let abatement = cond.abatement else { return }
            switch abatement {
            case .dateTime(let prim):
                guard let dt = prim.value else { return }
                var dc = DateComponents()
                dc.year = dt.date.year; dc.month = dt.date.month.map(Int.init)
                dc.day  = dt.date.day.map(Int.init); dc.hour = 12
                let d = cal.date(from: dc) ?? Date()
                p.dates.append(.init(paramName: "\(code)", dateStart: d, dateEnd: d))
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
                p.dates.append(.init(paramName: "\(code)", dateStart: start, dateEnd: end))
            @unknown default:
                break
            }
        }
        """

    // ── reference: asserter ──────────────────────────────────────────────────
    case "asserter":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ cond: Condition) {
            guard let refStr = cond.asserter?.reference?.value?.string else { return }
            let parts = refStr.split(separator: "/")
            let (refType, refId): (String?, String) = parts.count == 2
                ? (String(parts[0]), String(parts[1]))
                : (nil, refStr)
            p.references.append(.init(paramName: "asserter", refType: refType, refId: refId))
        }
        """

    // ── token: body-site ─────────────────────────────────────────────────────
    case "body-site":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ cond: Condition) {
            for cc in cond.bodySite ?? [] {
                for coding in cc.coding ?? [] {
                    let c = coding.code?.value?.string ?? ""
                    let s = coding.system?.value?.url.absoluteString
                    p.appendToken(paramName: "\(code)", system: s, code: c, display: coding.display?.value?.string)
                }
            }
        }
        """

    // ── token: evidence (evidence.code) ─────────────────────────────────────
    case "evidence":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ cond: Condition) {
            for ev in cond.evidence ?? [] {
                for cc in ev.code ?? [] {
                    for coding in cc.coding ?? [] {
                        let c = coding.code?.value?.string ?? ""
                        let s = coding.system?.value?.url.absoluteString
                        p.appendToken(paramName: "\(code)", system: s, code: c, display: coding.display?.value?.string)
                    }
                }
            }
        }
        """

    // ── reference: evidence-detail ───────────────────────────────────────────
    case "evidence-detail":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ cond: Condition) {
            for ev in cond.evidence ?? [] {
                for ref in ev.detail ?? [] {
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

    // ── string: onset-info (onset as string) ─────────────────────────────────
    case "onset-info":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ cond: Condition) {
            guard let onset = cond.onset, case .string(let prim) = onset,
                  let s = prim.value?.string else { return }
            p.strings.append(.init(paramName: "\(code)", value: s))
        }
        """

    // ── string: abatement-string (abatement as string) ───────────────────────
    case "abatement-string":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ cond: Condition) {
            guard let abatement = cond.abatement, case .string(let prim) = abatement,
                  let s = prim.value?.string else { return }
            p.strings.append(.init(paramName: "\(code)", value: s))
        }
        """

    // ── token: severity ──────────────────────────────────────────────────────
    case "severity":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ cond: Condition) {
            for coding in cond.severity?.coding ?? [] {
                let c = coding.code?.value?.string ?? ""
                let s = coding.system?.value?.url.absoluteString
                p.appendToken(paramName: "\(code)", system: s, code: c, display: coding.display?.value?.string)
            }
        }
        """

    // ── token: stage (stage.summary) ─────────────────────────────────────────
    case "stage":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ cond: Condition) {
            for stage in cond.stage ?? [] {
                for coding in stage.summary?.coding ?? [] {
                    let c = coding.code?.value?.string ?? ""
                    let s = coding.system?.value?.url.absoluteString
                    p.appendToken(paramName: "\(code)", system: s, code: c, display: coding.display?.value?.string)
                }
            }
        }
        """

    // ── date: recorded-date ───────────────────────────────────────────────────
    case "recorded-date":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ cond: Condition) {
            guard let prim = cond.recordedDate, let dt = prim.value else { return }
            var dc = DateComponents()
            dc.year = dt.date.year; dc.month = dt.date.month.map(Int.init)
            dc.day  = dt.date.day.map(Int.init); dc.hour = 12
            dc.timeZone = dt.timeZone
            let d = Calendar(identifier: .gregorian).date(from: dc) ?? Date()
            p.dates.append(.init(paramName: "\(code)", dateStart: d, dateEnd: d))
        }
        """

    // ── quantity: onset-age (onset as Age) ───────────────────────────────────
    case "onset-age":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ cond: Condition) {
            guard let onset = cond.onset, case .age(let age) = onset,
                  let decimalVal = age.value?.value?.decimal else { return }
            let sys  = age.system?.value?.url.absoluteString
            let unit = age.code?.value?.string
            p.quantities.append(.init(paramName: "onset-age", system: sys, code: unit,
                                      value: Decimal(string: decimalVal.description) ?? 0))
        }
        """

    // ── quantity: abatement-age (abatement as Age) ────────────────────────────
    case "abatement-age":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ cond: Condition) {
            guard let abatement = cond.abatement, case .age(let age) = abatement,
                  let decimalVal = age.value?.value?.decimal else { return }
            let sys  = age.system?.value?.url.absoluteString
            let unit = age.code?.value?.string
            p.quantities.append(.init(paramName: "abatement-age", system: sys, code: unit,
                                      value: Decimal(string: decimalVal.description) ?? 0))
        }
        """

    default:
        return nil
    }
}
