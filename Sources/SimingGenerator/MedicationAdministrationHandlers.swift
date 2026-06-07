import Foundation

/// Extracts the `MedicationAdministration.xxx` part from a multi-resource FHIRPath expression.
func medicationAdministrationExpr(from expression: String) -> String? {
    for part in expression.components(separatedBy: " | ") {
        var clean = part.trimmingCharacters(in: .whitespaces)
        if clean.hasPrefix("(") { clean = String(clean.dropFirst()) }
        guard clean.hasPrefix("MedicationAdministration.") else { continue }
        clean = clean.components(separatedBy: " as ")[0]
        clean = clean.components(separatedBy: ".where(")[0]
        return clean.trimmingCharacters(in: .whitespaces)
    }
    return nil
}

/// Returns the Swift function body for a given MedicationAdministration param.
func medicationAdministrationHandler(spec: ParamSpec, expr: String) -> String? {
    let code = spec.code
    let fn = "extract_MedicationAdministration_\(code.replacingOccurrences(of: "-", with: "_"))"
    let header = "// \(code) [\(spec.type)] — \(expr)"

    switch code {

    // ── token: status ─────────────────────────────────────────────────────────
    case "status":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ ma: MedicationAdministration) {
            if let v = ma.status.value?.rawValue {
                p.tokens.append(.init(paramName: "\(code)", system: nil, code: v))
            }
        }
        """

    // ── token: code (medication as CodeableConcept) ───────────────────────────
    case "code":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ ma: MedicationAdministration) {
            guard case .codeableConcept(let cc) = ma.medication else { return }
            for coding in cc.coding ?? [] {
                let v = coding.code?.value?.string ?? ""
                let s = coding.system?.value?.url.absoluteString
                p.tokens.append(.init(paramName: "\(code)", system: s, code: v))
            }
        }
        """

    // ── token: identifier ─────────────────────────────────────────────────────
    case "identifier":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ ma: MedicationAdministration) {
            for ident in ma.identifier ?? [] {
                let v = ident.value?.value?.string ?? ""
                let s = ident.system?.value?.url.absoluteString
                p.tokens.append(.init(paramName: "\(code)", system: s, code: v))
            }
        }
        """

    // ── token: reason-given (reasonCode) ─────────────────────────────────────
    case "reason-given":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ ma: MedicationAdministration) {
            for cc in ma.reasonCode ?? [] {
                for coding in cc.coding ?? [] {
                    let v = coding.code?.value?.string ?? ""
                    let s = coding.system?.value?.url.absoluteString
                    p.tokens.append(.init(paramName: "\(code)", system: s, code: v))
                }
            }
        }
        """

    // ── token: reason-not-given (statusReason) ───────────────────────────────
    case "reason-not-given":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ ma: MedicationAdministration) {
            for cc in ma.statusReason ?? [] {
                for coding in cc.coding ?? [] {
                    let v = coding.code?.value?.string ?? ""
                    let s = coding.system?.value?.url.absoluteString
                    p.tokens.append(.init(paramName: "\(code)", system: s, code: v))
                }
            }
        }
        """

    // ── reference: subject ────────────────────────────────────────────────────
    case "subject":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ ma: MedicationAdministration) {
            guard let refStr = ma.subject.reference?.value?.string else { return }
            let parts = refStr.split(separator: "/")
            let (refType, refId): (String?, String) = parts.count == 2
                ? (String(parts[0]), String(parts[1]))
                : (nil, refStr)
            p.references.append(.init(paramName: "\(code)", refType: refType, refId: refId))
        }
        """

    // ── reference: patient (alias for subject restricted to Patient) ──────────
    case "patient":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ ma: MedicationAdministration) {
            guard let refStr = ma.subject.reference?.value?.string else { return }
            let parts = refStr.split(separator: "/")
            let (refType, refId): (String?, String) = parts.count == 2
                ? (String(parts[0]), String(parts[1]))
                : (nil, refStr)
            p.references.append(.init(paramName: "\(code)", refType: refType, refId: refId))
        }
        """

    // ── reference: context (Encounter/EpisodeOfCare) ─────────────────────────
    case "context":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ ma: MedicationAdministration) {
            guard let refStr = ma.context?.reference?.value?.string else { return }
            let parts = refStr.split(separator: "/")
            let (refType, refId): (String?, String) = parts.count == 2
                ? (String(parts[0]), String(parts[1]))
                : (nil, refStr)
            p.references.append(.init(paramName: "\(code)", refType: refType, refId: refId))
        }
        """

    // ── reference: device ─────────────────────────────────────────────────────
    case "device":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ ma: MedicationAdministration) {
            for ref in ma.device ?? [] {
                guard let refStr = ref.reference?.value?.string else { continue }
                let parts = refStr.split(separator: "/")
                let (refType, refId): (String?, String) = parts.count == 2
                    ? (String(parts[0]), String(parts[1]))
                    : (nil, refStr)
                p.references.append(.init(paramName: "\(code)", refType: refType, refId: refId))
            }
        }
        """

    // ── reference: medication (medication as Reference) ───────────────────────
    case "medication":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ ma: MedicationAdministration) {
            guard case .reference(let ref) = ma.medication,
                  let refStr = ref.reference?.value?.string else { return }
            let parts = refStr.split(separator: "/")
            let (refType, refId): (String?, String) = parts.count == 2
                ? (String(parts[0]), String(parts[1]))
                : (nil, refStr)
            p.references.append(.init(paramName: "\(code)", refType: refType, refId: refId))
        }
        """

    // ── reference: performer (performer[].actor) ──────────────────────────────
    case "performer":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ ma: MedicationAdministration) {
            for perf in ma.performer ?? [] {
                guard let refStr = perf.actor.reference?.value?.string else { continue }
                let parts = refStr.split(separator: "/")
                let (refType, refId): (String?, String) = parts.count == 2
                    ? (String(parts[0]), String(parts[1]))
                    : (nil, refStr)
                p.references.append(.init(paramName: "\(code)", refType: refType, refId: refId))
            }
        }
        """

    // ── reference: request (MedicationRequest) ────────────────────────────────
    case "request":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ ma: MedicationAdministration) {
            guard let refStr = ma.request?.reference?.value?.string else { return }
            let parts = refStr.split(separator: "/")
            let (refType, refId): (String?, String) = parts.count == 2
                ? (String(parts[0]), String(parts[1]))
                : (nil, refStr)
            p.references.append(.init(paramName: "\(code)", refType: refType, refId: refId))
        }
        """

    // ── date: effective-time (EffectiveX union — dateTime or Period, REQUIRED) ─
    case "effective-time":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ ma: MedicationAdministration) {
            switch ma.effective {
            case .dateTime(let prim):
                guard let dt = prim.value else { return }
                var dc = DateComponents()
                dc.year = dt.date.year; dc.month = dt.date.month.map(Int.init)
                dc.day  = dt.date.day.map(Int.init); dc.hour = 12
                dc.timeZone = dt.timeZone
                let d = Calendar(identifier: .gregorian).date(from: dc) ?? Date()
                p.dates.append(.init(paramName: "\(code)", dateStart: d, dateEnd: d))
            case .period(let period):
                let cal = Calendar(identifier: .gregorian)
                var startDC = DateComponents(); var endDC = DateComponents()
                if let startStr = period.start?.value {
                    startDC.year = startStr.date.year; startDC.month = startStr.date.month.map(Int.init)
                    startDC.day  = startStr.date.day.map(Int.init); startDC.hour = 0
                    startDC.timeZone = startStr.timeZone
                }
                if let endStr = period.end?.value {
                    endDC.year = endStr.date.year; endDC.month = endStr.date.month.map(Int.init)
                    endDC.day  = endStr.date.day.map(Int.init); endDC.hour = 23
                    endDC.timeZone = endStr.timeZone
                }
                let dateStart = cal.date(from: startDC) ?? Date.distantPast
                let dateEnd   = cal.date(from: endDC)   ?? Date.distantFuture
                p.dates.append(.init(paramName: "\(code)", dateStart: dateStart, dateEnd: dateEnd))
            }
        }
        """

    default:
        return nil
    }
}
