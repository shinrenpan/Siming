import Foundation

/// Extracts the `Specimen.xxx` part from a multi-resource FHIRPath expression.
func specimenExpr(from expression: String) -> String? {
    for part in expression.components(separatedBy: " | ") {
        var clean = part.trimmingCharacters(in: .whitespaces)
        if clean.hasPrefix("(") { clean = String(clean.dropFirst()) }
        guard clean.hasPrefix("Specimen.") else { continue }
        clean = clean.components(separatedBy: " as ")[0]
        clean = clean.components(separatedBy: ".where(")[0]
        return clean.trimmingCharacters(in: .whitespaces)
    }
    return nil
}

/// Returns the Swift function body for a given Specimen param.
func specimenHandler(spec: ParamSpec, expr: String) -> String? {
    let code = spec.code
    let fn = "extract_Specimen_\(code.replacingOccurrences(of: "-", with: "_"))"
    let header = "// \(code) [\(spec.type)] — \(expr)"

    switch code {

    // ── token: status ─────────────────────────────────────────────────────────
    case "status":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ s: Specimen) {
            if let v = s.status?.value?.rawValue {
                p.tokens.append(.init(paramName: "\(code)",
                                      system: "http://hl7.org/fhir/specimen-status", code: v))
            }
        }
        """

    // ── token: type ───────────────────────────────────────────────────────────
    case "type":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ s: Specimen) {
            for coding in s.type?.coding ?? [] {
                let c = coding.code?.value?.string ?? ""
                let sys = coding.system?.value?.url.absoluteString
                p.tokens.append(.init(paramName: "\(code)", system: sys, code: c))
            }
        }
        """

    // ── token: accession ──────────────────────────────────────────────────────
    case "accession":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ s: Specimen) {
            guard let ident = s.accessionIdentifier else { return }
            let v = ident.value?.value?.string ?? ""
            let sys = ident.system?.value?.url.absoluteString
            p.tokens.append(.init(paramName: "\(code)", system: sys, code: v))
        }
        """

    // ── token: identifier ─────────────────────────────────────────────────────
    case "identifier":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ s: Specimen) {
            for ident in s.identifier ?? [] {
                let v = ident.value?.value?.string ?? ""
                let sys = ident.system?.value?.url.absoluteString
                p.tokens.append(.init(paramName: "\(code)", system: sys, code: v))
            }
        }
        """

    // ── token: bodysite ───────────────────────────────────────────────────────
    case "bodysite":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ s: Specimen) {
            for coding in s.collection?.bodySite?.coding ?? [] {
                let c = coding.code?.value?.string ?? ""
                let sys = coding.system?.value?.url.absoluteString
                p.tokens.append(.init(paramName: "\(code)", system: sys, code: c))
            }
        }
        """

    // ── token: container (Specimen.container.type) ────────────────────────────
    case "container":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ s: Specimen) {
            for cont in s.container ?? [] {
                for coding in cont.type?.coding ?? [] {
                    let c = coding.code?.value?.string ?? ""
                    let sys = coding.system?.value?.url.absoluteString
                    p.tokens.append(.init(paramName: "\(code)", system: sys, code: c))
                }
            }
        }
        """

    // ── token: container-id (Specimen.container.identifier) ──────────────────
    case "container-id":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ s: Specimen) {
            for cont in s.container ?? [] {
                for ident in cont.identifier ?? [] {
                    let v = ident.value?.value?.string ?? ""
                    let sys = ident.system?.value?.url.absoluteString
                    p.tokens.append(.init(paramName: "\(code)", system: sys, code: v))
                }
            }
        }
        """

    // ── date: collected ───────────────────────────────────────────────────────
    case "collected":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ s: Specimen) {
            let cal = Calendar(identifier: .gregorian)
            guard let coll = s.collection?.collected else { return }
            switch coll {
            case .dateTime(let prim):
                guard let dt = prim.value else { return }
                var dc = DateComponents()
                dc.year = dt.date.year; dc.month = dt.date.month.map(Int.init)
                dc.day  = dt.date.day.map(Int.init); dc.hour = 12
                dc.timeZone = dt.timeZone
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
            default:
                break
            }
        }
        """

    // ── reference: collector ──────────────────────────────────────────────────
    case "collector":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ s: Specimen) {
            guard let refStr = s.collection?.collector?.reference?.value?.string else { return }
            let parts = refStr.split(separator: "/")
            let (refType, refId): (String?, String) = parts.count == 2
                ? (String(parts[0]), String(parts[1]))
                : (nil, refStr)
            p.references.append(.init(paramName: "\(code)", refType: refType, refId: refId))
        }
        """

    // ── reference: subject ────────────────────────────────────────────────────
    case "subject":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ s: Specimen) {
            guard let refStr = s.subject?.reference?.value?.string else { return }
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
        private func \(fn)(_ p: inout SearchParams, _ s: Specimen) {
            guard let refStr = s.subject?.reference?.value?.string else { return }
            let parts = refStr.split(separator: "/")
            let (refType, refId): (String?, String) = parts.count == 2
                ? (String(parts[0]), String(parts[1]))
                : (nil, refStr)
            p.references.append(.init(paramName: "\(code)", refType: refType, refId: refId))
        }
        """

    // ── reference: parent ─────────────────────────────────────────────────────
    case "parent":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ s: Specimen) {
            for ref in s.parent ?? [] {
                guard let refStr = ref.reference?.value?.string else { continue }
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
