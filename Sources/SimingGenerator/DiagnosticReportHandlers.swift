import Foundation

/// Extracts the `DiagnosticReport.xxx` part from a multi-resource FHIRPath expression.
func diagnosticReportExpr(from expression: String) -> String? {
    for part in expression.components(separatedBy: " | ") {
        var clean = part.trimmingCharacters(in: .whitespaces)
        if clean.hasPrefix("(") { clean = String(clean.dropFirst()) }
        guard clean.hasPrefix("DiagnosticReport.") else { continue }
        clean = clean.components(separatedBy: " as ")[0]
        clean = clean.components(separatedBy: ".where(")[0]
        return clean.trimmingCharacters(in: .whitespaces)
    }
    return nil
}

/// Returns the Swift function body for a given DiagnosticReport param.
/// Switches on `spec.code` because patient/subject share the same expression root.
func diagnosticReportHandler(spec: ParamSpec, expr: String) -> String? {
    let code = spec.code
    let fn = "extract_DiagnosticReport_\(code.replacingOccurrences(of: "-", with: "_"))"
    let header = "// \(code) [\(spec.type)] — \(expr)"

    switch code {

    // ── token: status ─────────────────────────────────────────────────────────
    case "status":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ dr: DiagnosticReport) {
            if let v = dr.status.value?.rawValue {
                p.tokens.append(.init(paramName: "\(code)",
                                      system: "http://hl7.org/fhir/diagnostic-report-status", code: v))
            }
        }
        """

    // ── token: code ───────────────────────────────────────────────────────────
    case "code":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ dr: DiagnosticReport) {
            for coding in dr.code.coding ?? [] {
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
        private func \(fn)(_ p: inout SearchParams, _ dr: DiagnosticReport) {
            for cc in dr.category ?? [] {
                for coding in cc.coding ?? [] {
                    let c = coding.code?.value?.string ?? ""
                    let s = coding.system?.value?.url.absoluteString
                    p.appendToken(paramName: "\(code)", system: s, code: c, display: coding.display?.value?.string)
                }
            }
        }
        """

    // ── token: identifier ─────────────────────────────────────────────────────
    case "identifier":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ dr: DiagnosticReport) {
            for ident in dr.identifier ?? [] {
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
        private func \(fn)(_ p: inout SearchParams, _ dr: DiagnosticReport) {
            guard let refStr = dr.subject?.reference?.value?.string else { return }
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
        private func \(fn)(_ p: inout SearchParams, _ dr: DiagnosticReport) {
            guard let refStr = dr.encounter?.reference?.value?.string else { return }
            let parts = refStr.split(separator: "/")
            let (refType, refId): (String?, String) = parts.count == 2
                ? (String(parts[0]), String(parts[1]))
                : (nil, refStr)
            p.references.append(.init(paramName: "encounter", refType: refType, refId: refId))
        }
        """

    // ── reference: performer (array of references) ───────────────────────────
    case "performer":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ dr: DiagnosticReport) {
            for ref in dr.performer ?? [] {
                guard let refStr = ref.reference?.value?.string else { continue }
                let parts = refStr.split(separator: "/")
                let (refType, refId): (String?, String) = parts.count == 2
                    ? (String(parts[0]), String(parts[1]))
                    : (nil, refStr)
                p.references.append(.init(paramName: "performer", refType: refType, refId: refId))
            }
        }
        """

    // ── date: effective (choice type: dateTime or Period) ────────────────────
    case "date":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ dr: DiagnosticReport) {
            let cal = Calendar(identifier: .gregorian)
            guard let effective = dr.effective else { return }
            switch effective {
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
            }
        }
        """

    // ── reference: based-on ──────────────────────────────────────────────────
    case "based-on":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ dr: DiagnosticReport) {
            for ref in dr.basedOn ?? [] {
                guard let refStr = ref.reference?.value?.string else { continue }
                let parts = refStr.split(separator: "/")
                let (refType, refId): (String?, String) = parts.count == 2
                    ? (String(parts[0]), String(parts[1]))
                    : (nil, refStr)
                p.references.append(.init(paramName: "based-on", refType: refType, refId: refId))
            }
        }
        """

    // ── token: conclusion ─────────────────────────────────────────────────────
    case "conclusion":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ dr: DiagnosticReport) {
            for cc in dr.conclusionCode ?? [] {
                for coding in cc.coding ?? [] {
                    let c = coding.code?.value?.string ?? ""
                    let s = coding.system?.value?.url.absoluteString
                    p.appendToken(paramName: "conclusion", system: s, code: c, display: coding.display?.value?.string)
                }
            }
        }
        """

    // ── reference: media ──────────────────────────────────────────────────────
    case "media":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ dr: DiagnosticReport) {
            for m in dr.media ?? [] {
                guard let refStr = m.link.reference?.value?.string else { continue }
                let parts = refStr.split(separator: "/")
                let (refType, refId): (String?, String) = parts.count == 2
                    ? (String(parts[0]), String(parts[1]))
                    : (nil, refStr)
                p.references.append(.init(paramName: "media", refType: refType, refId: refId))
            }
        }
        """

    // ── reference: result ─────────────────────────────────────────────────────
    case "result":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ dr: DiagnosticReport) {
            for ref in dr.result ?? [] {
                guard let refStr = ref.reference?.value?.string else { continue }
                let parts = refStr.split(separator: "/")
                let (refType, refId): (String?, String) = parts.count == 2
                    ? (String(parts[0]), String(parts[1]))
                    : (nil, refStr)
                p.references.append(.init(paramName: "result", refType: refType, refId: refId))
            }
        }
        """

    // ── reference: results-interpreter ───────────────────────────────────────
    case "results-interpreter":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ dr: DiagnosticReport) {
            for ref in dr.resultsInterpreter ?? [] {
                guard let refStr = ref.reference?.value?.string else { continue }
                let parts = refStr.split(separator: "/")
                let (refType, refId): (String?, String) = parts.count == 2
                    ? (String(parts[0]), String(parts[1]))
                    : (nil, refStr)
                p.references.append(.init(paramName: "results-interpreter", refType: refType, refId: refId))
            }
        }
        """

    // ── reference: specimen ───────────────────────────────────────────────────
    case "specimen":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ dr: DiagnosticReport) {
            for ref in dr.specimen ?? [] {
                guard let refStr = ref.reference?.value?.string else { continue }
                let parts = refStr.split(separator: "/")
                let (refType, refId): (String?, String) = parts.count == 2
                    ? (String(parts[0]), String(parts[1]))
                    : (nil, refStr)
                p.references.append(.init(paramName: "specimen", refType: refType, refId: refId))
            }
        }
        """

    // ── date: issued (Instant — all components non-optional) ────────────────
    case "issued":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ dr: DiagnosticReport) {
            guard let prim = dr.issued, let inst = prim.value else { return }
            var dc = DateComponents()
            dc.year = inst.date.year; dc.month = Int(inst.date.month)
            dc.day  = Int(inst.date.day); dc.hour = 12
            dc.timeZone = inst.timeZone
            let d = Calendar(identifier: .gregorian).date(from: dc) ?? Date()
            p.dates.append(.init(paramName: "\(code)", dateStart: d, dateEnd: d))
        }
        """

    default:
        return nil
    }
}
