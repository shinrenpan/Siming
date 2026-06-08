import Foundation

/// Extracts the `ServiceRequest.xxx` part from a multi-resource FHIRPath expression.
func serviceRequestExpr(from expression: String) -> String? {
    for part in expression.components(separatedBy: " | ") {
        var clean = part.trimmingCharacters(in: .whitespaces)
        if clean.hasPrefix("(") { clean = String(clean.dropFirst()) }
        guard clean.hasPrefix("ServiceRequest.") else { continue }
        clean = clean.components(separatedBy: " as ")[0]
        clean = clean.components(separatedBy: ".where(")[0]
        return clean.trimmingCharacters(in: .whitespaces)
    }
    return nil
}

/// Returns the Swift function body for a given ServiceRequest param.
func serviceRequestHandler(spec: ParamSpec, expr: String) -> String? {
    let code = spec.code
    let fn = "extract_ServiceRequest_\(code.replacingOccurrences(of: "-", with: "_"))"
    let header = "// \(code) [\(spec.type)] — \(expr)"

    switch code {

    // ── token: status ─────────────────────────────────────────────────────────
    case "status":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ sr: ServiceRequest) {
            if let v = sr.status.value?.rawValue {
                p.tokens.append(.init(paramName: "\(code)",
                                      system: "http://hl7.org/fhir/request-status", code: v))
            }
        }
        """

    // ── token: intent ─────────────────────────────────────────────────────────
    case "intent":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ sr: ServiceRequest) {
            if let v = sr.intent.value?.rawValue {
                p.tokens.append(.init(paramName: "\(code)",
                                      system: "http://hl7.org/fhir/request-intent", code: v))
            }
        }
        """

    // ── token: priority ───────────────────────────────────────────────────────
    case "priority":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ sr: ServiceRequest) {
            if let v = sr.priority?.value?.rawValue {
                p.tokens.append(.init(paramName: "\(code)",
                                      system: "http://hl7.org/fhir/request-priority", code: v))
            }
        }
        """

    // ── token: code ───────────────────────────────────────────────────────────
    case "code":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ sr: ServiceRequest) {
            for coding in sr.code?.coding ?? [] {
                let c = coding.code?.value?.string ?? ""
                let s = coding.system?.value?.url.absoluteString
                p.tokens.append(.init(paramName: "\(code)", system: s, code: c))
            }
        }
        """

    // ── token: category ───────────────────────────────────────────────────────
    case "category":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ sr: ServiceRequest) {
            for cat in sr.category ?? [] {
                for coding in cat.coding ?? [] {
                    let c = coding.code?.value?.string ?? ""
                    let s = coding.system?.value?.url.absoluteString
                    p.tokens.append(.init(paramName: "\(code)", system: s, code: c))
                }
            }
        }
        """

    // ── token: body-site ─────────────────────────────────────────────────────
    case "body-site":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ sr: ServiceRequest) {
            for site in sr.bodySite ?? [] {
                for coding in site.coding ?? [] {
                    let c = coding.code?.value?.string ?? ""
                    let s = coding.system?.value?.url.absoluteString
                    p.tokens.append(.init(paramName: "\(code)", system: s, code: c))
                }
            }
        }
        """

    // ── token: identifier ─────────────────────────────────────────────────────
    case "identifier":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ sr: ServiceRequest) {
            for ident in sr.identifier ?? [] {
                let v = ident.value?.value?.string ?? ""
                let s = ident.system?.value?.url.absoluteString
                p.tokens.append(.init(paramName: "\(code)", system: s, code: v))
            }
        }
        """

    // ── token: performer-type ─────────────────────────────────────────────────
    case "performer-type":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ sr: ServiceRequest) {
            for coding in sr.performerType?.coding ?? [] {
                let c = coding.code?.value?.string ?? ""
                let s = coding.system?.value?.url.absoluteString
                p.tokens.append(.init(paramName: "\(code)", system: s, code: c))
            }
        }
        """

    // ── token: requisition ────────────────────────────────────────────────────
    case "requisition":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ sr: ServiceRequest) {
            guard let req = sr.requisition else { return }
            let v = req.value?.value?.string ?? ""
            let s = req.system?.value?.url.absoluteString
            p.tokens.append(.init(paramName: "\(code)", system: s, code: v))
        }
        """

    // ── reference: patient / subject ─────────────────────────────────────────
    case "patient", "subject":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ sr: ServiceRequest) {
            guard let refStr = sr.subject.reference?.value?.string else { return }
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
        private func \(fn)(_ p: inout SearchParams, _ sr: ServiceRequest) {
            guard let refStr = sr.encounter?.reference?.value?.string else { return }
            let parts = refStr.split(separator: "/")
            let (refType, refId): (String?, String) = parts.count == 2
                ? (String(parts[0]), String(parts[1]))
                : (nil, refStr)
            p.references.append(.init(paramName: "encounter", refType: refType, refId: refId))
        }
        """

    // ── reference: requester ─────────────────────────────────────────────────
    case "requester":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ sr: ServiceRequest) {
            guard let refStr = sr.requester?.reference?.value?.string else { return }
            let parts = refStr.split(separator: "/")
            let (refType, refId): (String?, String) = parts.count == 2
                ? (String(parts[0]), String(parts[1]))
                : (nil, refStr)
            p.references.append(.init(paramName: "requester", refType: refType, refId: refId))
        }
        """

    // ── reference: performer ─────────────────────────────────────────────────
    case "performer":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ sr: ServiceRequest) {
            for ref in sr.performer ?? [] {
                guard let refStr = ref.reference?.value?.string else { continue }
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
        private func \(fn)(_ p: inout SearchParams, _ sr: ServiceRequest) {
            for ref in sr.basedOn ?? [] {
                guard let refStr = ref.reference?.value?.string else { continue }
                let parts = refStr.split(separator: "/")
                let (refType, refId): (String?, String) = parts.count == 2
                    ? (String(parts[0]), String(parts[1]))
                    : (nil, refStr)
                p.references.append(.init(paramName: "based-on", refType: refType, refId: refId))
            }
        }
        """

    // ── reference: replaces ───────────────────────────────────────────────────
    case "replaces":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ sr: ServiceRequest) {
            for ref in sr.replaces ?? [] {
                guard let refStr = ref.reference?.value?.string else { continue }
                let parts = refStr.split(separator: "/")
                let (refType, refId): (String?, String) = parts.count == 2
                    ? (String(parts[0]), String(parts[1]))
                    : (nil, refStr)
                p.references.append(.init(paramName: "replaces", refType: refType, refId: refId))
            }
        }
        """

    // ── reference: specimen ──────────────────────────────────────────────────
    case "specimen":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ sr: ServiceRequest) {
            for ref in sr.specimen ?? [] {
                guard let refStr = ref.reference?.value?.string else { continue }
                let parts = refStr.split(separator: "/")
                let (refType, refId): (String?, String) = parts.count == 2
                    ? (String(parts[0]), String(parts[1]))
                    : (nil, refStr)
                p.references.append(.init(paramName: "specimen", refType: refType, refId: refId))
            }
        }
        """

    // ── string: instantiates-canonical (canonical URL → idx_string) ─────────────
    case "instantiates-canonical":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ sr: ServiceRequest) {
            for ic in sr.instantiatesCanonical ?? [] {
                guard let url = ic.value?.url.absoluteString else { continue }
                p.strings.append(.init(paramName: "instantiates-canonical", value: url))
            }
        }
        """

    // ── string: instantiates-uri — ServiceRequest.instantiatesUri[] → idx_string ─
    case "instantiates-uri":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ sr: ServiceRequest) {
            for prim in sr.instantiatesUri ?? [] {
                guard let url = prim.value?.url.absoluteString else { continue }
                p.strings.append(.init(paramName: "instantiates-uri", value: url))
            }
        }
        """

    // ── date: authored ────────────────────────────────────────────────────────
    case "authored":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ sr: ServiceRequest) {
            guard let prim = sr.authoredOn, let dt = prim.value else { return }
            let cal = Calendar(identifier: .gregorian)
            var dc = DateComponents()
            dc.year = dt.date.year; dc.month = dt.date.month.map(Int.init)
            dc.day  = dt.date.day.map(Int.init); dc.hour = 12
            dc.timeZone = dt.timeZone
            let d = cal.date(from: dc) ?? Date()
            p.dates.append(.init(paramName: "authored", dateStart: d, dateEnd: d))
        }
        """

    // ── date: occurrence (choice type: dateTime, Period, Timing) ─────────────
    case "occurrence":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ sr: ServiceRequest) {
            let cal = Calendar(identifier: .gregorian)
            guard let occ = sr.occurrence else { return }
            switch occ {
            case .dateTime(let prim):
                guard let dt = prim.value else { return }
                var dc = DateComponents()
                dc.year = dt.date.year; dc.month = dt.date.month.map(Int.init)
                dc.day  = dt.date.day.map(Int.init); dc.hour = 12
                dc.timeZone = dt.timeZone
                let d = cal.date(from: dc) ?? Date()
                p.dates.append(.init(paramName: "occurrence", dateStart: d, dateEnd: d))
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
                p.dates.append(.init(paramName: "occurrence", dateStart: start, dateEnd: end))
            default:
                break
            }
        }
        """

    // ── token: order-detail (CodeableConcept array) ───────────────────────────
    case "order-detail":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ sr: ServiceRequest) {
            for cc in sr.orderDetail ?? [] {
                for coding in cc.coding ?? [] {
                    let c = coding.code?.value?.string ?? ""
                    let s = coding.system?.value?.url.absoluteString
                    p.tokens.append(.init(paramName: "order-detail", system: s, code: c))
                }
            }
        }
        """

    default:
        return nil
    }
}
