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
                dc.day  = dt.date.day.map(Int.init)
                // A dateTime carrying a time keeps it; a date-only value stays anchored at
                // midday so it sits well inside the day whatever offset it is compared against.
                // The zone must be explicit — falling through to the host's zone makes the
                // stored value depend on where the server happens to run.
                dc.hour   = dt.time.map { Int($0.hour) } ?? 12
                dc.minute = dt.time.map { Int($0.minute) } ?? 0
                dc.second = dt.time.map { min(Int(truncating: $0.second as NSDecimalNumber), 59) } ?? 0
                dc.timeZone = dt.timeZone ?? TimeZone(secondsFromGMT: 0)
                let d = Calendar(identifier: .gregorian).date(from: dc) ?? Date()
                p.dates.append(.init(paramName: "\(code)", dateStart: d, dateEnd: d))
            case .period(let period):
                let cal = Calendar(identifier: .gregorian)
                // Explicit else branches, not `cal.date(from:) ?? .distantFuture`:
                // Calendar.date(from: DateComponents()) does NOT return nil — it
                // returns year 0 — so the fallback never fires and an open-ended
                // period indexes date_end in the year 0, where no date search can
                // ever reach it.
                var dateStart = Date.distantPast
                var dateEnd   = Date.distantFuture
                var startDC = DateComponents(); var endDC = DateComponents()
                if let startStr = period.start?.value {
                    startDC.year = startStr.date.year; startDC.month = startStr.date.month.map(Int.init)
                    startDC.day  = startStr.date.day.map(Int.init)
                    // A date-only bound widens to the start of the day; one carrying a time keeps it.
                    // The zone must be explicit — `startStr.timeZone` is nil for a date-only value, and
                    // DateComponents then falls through to the host's zone.
                    startDC.hour   = startStr.time.map { Int($0.hour) } ?? 0
                    startDC.minute = startStr.time.map { Int($0.minute) } ?? 0
                    startDC.second = startStr.time.map { min(Int(truncating: $0.second as NSDecimalNumber), 59) } ?? 0
                    startDC.timeZone = startStr.timeZone ?? TimeZone(secondsFromGMT: 0)
                    dateStart = cal.date(from: startDC) ?? Date.distantPast
                }
                if let endStr = period.end?.value {
                    endDC.year = endStr.date.year; endDC.month = endStr.date.month.map(Int.init)
                    endDC.day  = endStr.date.day.map(Int.init)
                    // Mirror of the above; an unset minute would silently cut the last hour off the day.
                    endDC.hour   = endStr.time.map { Int($0.hour) } ?? 23
                    endDC.minute = endStr.time.map { Int($0.minute) } ?? 59
                    endDC.second = endStr.time.map { min(Int(truncating: $0.second as NSDecimalNumber), 59) } ?? 59
                    endDC.timeZone = endStr.timeZone ?? TimeZone(secondsFromGMT: 0)
                    dateEnd = cal.date(from: endDC) ?? Date.distantFuture
                }
                p.dates.append(.init(paramName: "\(code)", dateStart: dateStart, dateEnd: dateEnd))
            }
        }
        """

    default:
        return nil
    }
}
