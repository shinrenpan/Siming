import Foundation

/// Extracts the `Task.xxx` part from a multi-resource FHIRPath expression.
func taskExpr(from expression: String) -> String? {
    for part in expression.components(separatedBy: " | ") {
        var clean = part.trimmingCharacters(in: .whitespaces)
        if clean.hasPrefix("(") { clean = String(clean.dropFirst()) }
        guard clean.hasPrefix("Task.") else { continue }
        clean = clean.components(separatedBy: " as ")[0]
        clean = clean.components(separatedBy: ".where(")[0]
        return clean.trimmingCharacters(in: .whitespaces)
    }
    return nil
}

/// Returns the Swift function body for a given Task param.
func taskHandler(spec: ParamSpec, expr: String) -> String? {
    let code = spec.code
    let fn = "extract_Task_\(code.replacingOccurrences(of: "-", with: "_"))"
    let header = "// \(code) [\(spec.type)] — \(expr)"

    /// Single Reference? → idx_reference.
    func singleRef(_ path: String) -> String {
        """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ t: ModelsR4.Task) {
            guard let refStr = t.\(path)?.reference?.value?.string else { return }
            let parts = refStr.split(separator: "/")
            let (refType, refId): (String?, String) = parts.count == 2
                ? (String(parts[0]), String(parts[1]))
                : (nil, refStr)
            p.references.append(.init(paramName: "\(code)", refType: refType, refId: refId))
        }
        """
    }

    /// [Reference]? → idx_reference.
    func refArray(_ path: String) -> String {
        """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ t: ModelsR4.Task) {
            for ref in t.\(path) ?? [] {
                guard let refStr = ref.reference?.value?.string else { continue }
                let parts = refStr.split(separator: "/")
                let (refType, refId): (String?, String) = parts.count == 2
                    ? (String(parts[0]), String(parts[1]))
                    : (nil, refStr)
                p.references.append(.init(paramName: "\(code)", refType: refType, refId: refId))
            }
        }
        """
    }

    /// FHIRPrimitive<DateTime>? → idx_date point value.
    func dateTime(_ path: String) -> String {
        """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ t: ModelsR4.Task) {
            guard let prim = t.\(path), let dt = prim.value else { return }
            let cal = Calendar(identifier: .gregorian)
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
            let d = cal.date(from: dc) ?? Date()
            p.dates.append(.init(paramName: "\(code)", dateStart: d, dateEnd: d))
        }
        """
    }

    switch code {

    // ── token: status / intent / priority (required-binding codes) ───────────
    case "status":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ t: ModelsR4.Task) {
            if let v = t.status.value?.rawValue {
                p.tokens.append(.init(paramName: "\(code)",
                                      system: "http://hl7.org/fhir/task-status", code: v))
            }
        }
        """

    case "intent":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ t: ModelsR4.Task) {
            // R4 ValueSet/task-intent: only `unknown` is from the task-intent code system;
            // proposal / plan / order / … are drawn from request-intent.
            if let v = t.intent.value?.string {
                let system = v == "unknown"
                    ? "http://hl7.org/fhir/task-intent"
                    : "http://hl7.org/fhir/request-intent"
                p.tokens.append(.init(paramName: "\(code)", system: system, code: v))
            }
        }
        """

    case "priority":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ t: ModelsR4.Task) {
            if let v = t.priority?.value?.rawValue {
                p.tokens.append(.init(paramName: "\(code)",
                                      system: "http://hl7.org/fhir/request-priority", code: v))
            }
        }
        """

    // ── token: code / business-status (single CodeableConcept) ───────────────
    case "code", "business-status":
        let path = code == "code" ? "code" : "businessStatus"
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ t: ModelsR4.Task) {
            for coding in t.\(path)?.coding ?? [] {
                let c = coding.code?.value?.string ?? ""
                let s = coding.system?.value?.url.absoluteString
                p.appendToken(paramName: "\(code)", system: s, code: c, display: coding.display?.value?.string)
            }
        }
        """

    // ── token: performer — Task.performerType (CodeableConcept array) ────────
    case "performer":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ t: ModelsR4.Task) {
            for cc in t.performerType ?? [] {
                for coding in cc.coding ?? [] {
                    let c = coding.code?.value?.string ?? ""
                    let s = coding.system?.value?.url.absoluteString
                    p.appendToken(paramName: "\(code)", system: s, code: c, display: coding.display?.value?.string)
                }
            }
        }
        """

    // ── token: identifier (array) / group-identifier (single) ────────────────
    case "identifier":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ t: ModelsR4.Task) {
            for ident in t.identifier ?? [] {
                let v = ident.value?.value?.string ?? ""
                let s = ident.system?.value?.url.absoluteString
                p.tokens.append(.init(paramName: "\(code)", system: s, code: v))
            }
        }
        """

    case "group-identifier":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ t: ModelsR4.Task) {
            guard let ident = t.groupIdentifier else { return }
            let v = ident.value?.value?.string ?? ""
            let s = ident.system?.value?.url.absoluteString
            p.tokens.append(.init(paramName: "\(code)", system: s, code: v))
        }
        """

    // ── reference: subject — Task.for (any type) ─────────────────────────────
    case "subject":
        return singleRef("`for`")

    // ── reference: patient — Task.for.where(resolve() is Patient) ────────────
    // Task.for is Reference(Any), so unlike resources whose subject is always a
    // Patient or Group, only a Patient-typed reference is indexed here.
    case "patient":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ t: ModelsR4.Task) {
            guard let refStr = t.`for`?.reference?.value?.string else { return }
            let parts = refStr.split(separator: "/")
            guard parts.count == 2, parts[0] == "Patient" else { return }
            p.references.append(.init(paramName: "\(code)", refType: "Patient", refId: String(parts[1])))
        }
        """

    case "encounter": return singleRef("encounter")
    case "focus":     return singleRef("focus")
    case "owner":     return singleRef("owner")
    case "requester": return singleRef("requester")
    case "based-on":  return refArray("basedOn")
    case "part-of":   return refArray("partOf")

    // ── date: authored-on / modified (dateTime) ──────────────────────────────
    case "authored-on": return dateTime("authoredOn")
    case "modified":    return dateTime("lastModified")

    // ── date: period — Task.executionPeriod ──────────────────────────────────
    case "period":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ t: ModelsR4.Task) {
            guard let period = t.executionPeriod else { return }
            let cal = Calendar(identifier: .gregorian)
            let start: Date
            let end: Date
            if let prim = period.start, let dt = prim.value {
                var dc = DateComponents()
                dc.year = dt.date.year; dc.month = dt.date.month.map(Int.init)
                dc.day  = dt.date.day.map(Int.init)
                // A date-only bound widens to the start of the day; one carrying a time keeps it.
                // dc.timeZone is mandatory: without it the components are read in
                // the server's local zone and every indexed period shifts by the
                // host's UTC offset — right in a UTC container, wrong anywhere else.
                dc.hour   = dt.time.map { Int($0.hour) } ?? 0
                dc.minute = dt.time.map { Int($0.minute) } ?? 0
                dc.second = dt.time.map { min(Int(truncating: $0.second as NSDecimalNumber), 59) } ?? 0
                dc.timeZone = dt.timeZone ?? TimeZone(secondsFromGMT: 0)
                start = cal.date(from: dc) ?? Date.distantPast
            } else { start = Date.distantPast }
            if let prim = period.end, let dt = prim.value {
                var dc = DateComponents()
                dc.year = dt.date.year; dc.month = dt.date.month.map(Int.init)
                dc.day  = dt.date.day.map(Int.init)
                // A date-only bound widens to the end of the day; one carrying a time keeps it.
                // dc.timeZone is mandatory: without it the components are read in
                // the server's local zone and every indexed period shifts by the
                // host's UTC offset — right in a UTC container, wrong anywhere else.
                dc.hour   = dt.time.map { Int($0.hour) } ?? 23
                dc.minute = dt.time.map { Int($0.minute) } ?? 59
                dc.second = dt.time.map { min(Int(truncating: $0.second as NSDecimalNumber), 59) } ?? 59
                dc.timeZone = dt.timeZone ?? TimeZone(secondsFromGMT: 0)
                end = cal.date(from: dc) ?? Date.distantFuture
            } else { end = Date.distantFuture }
            p.dates.append(.init(paramName: "\(code)", dateStart: start, dateEnd: end))
        }
        """

    default:
        return nil
    }
}
