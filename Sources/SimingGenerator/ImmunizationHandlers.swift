import Foundation

/// Extracts the `Immunization.xxx` part from a multi-resource FHIRPath expression.
func immunizationExpr(from expression: String) -> String? {
    for part in expression.components(separatedBy: " | ") {
        var clean = part.trimmingCharacters(in: .whitespaces)
        if clean.hasPrefix("(") { clean = String(clean.dropFirst()) }
        guard clean.hasPrefix("Immunization.") else { continue }
        clean = clean.components(separatedBy: " as ")[0]
        clean = clean.components(separatedBy: ".where(")[0]
        return clean.trimmingCharacters(in: .whitespaces)
    }
    return nil
}

/// Returns the Swift function body for a given Immunization param.
func immunizationHandler(spec: ParamSpec, expr: String) -> String? {
    let code = spec.code
    let fn = "extract_Immunization_\(code.replacingOccurrences(of: "-", with: "_"))"
    let header = "// \(code) [\(spec.type)] — \(expr)"

    switch code {

    // ── token: status ─────────────────────────────────────────────────────────
    case "status":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ imm: Immunization) {
            if let v = imm.status.value?.rawValue {
                p.tokens.append(.init(paramName: "\(code)",
                                      system: "http://hl7.org/fhir/event-status", code: v))
            }
        }
        """

    // ── token: vaccine-code ───────────────────────────────────────────────────
    case "vaccine-code":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ imm: Immunization) {
            for coding in imm.vaccineCode.coding ?? [] {
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
        private func \(fn)(_ p: inout SearchParams, _ imm: Immunization) {
            for ident in imm.identifier ?? [] {
                let v = ident.value?.value?.string ?? ""
                let s = ident.system?.value?.url.absoluteString
                p.tokens.append(.init(paramName: "\(code)", system: s, code: v))
            }
        }
        """

    // ── reference: patient ────────────────────────────────────────────────────
    case "patient":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ imm: Immunization) {
            guard let refStr = imm.patient.reference?.value?.string else { return }
            let parts = refStr.split(separator: "/")
            let (refType, refId): (String?, String) = parts.count == 2
                ? (String(parts[0]), String(parts[1]))
                : (nil, refStr)
            p.references.append(.init(paramName: "patient", refType: refType, refId: refId))
        }
        """

    // ── reference: performer (actor) ─────────────────────────────────────────
    case "performer":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ imm: Immunization) {
            for perf in imm.performer ?? [] {
                guard let refStr = perf.actor.reference?.value?.string else { continue }
                let parts = refStr.split(separator: "/")
                let (refType, refId): (String?, String) = parts.count == 2
                    ? (String(parts[0]), String(parts[1]))
                    : (nil, refStr)
                p.references.append(.init(paramName: "performer", refType: refType, refId: refId))
            }
        }
        """

    // ── string: lot-number ────────────────────────────────────────────────────
    case "lot-number":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ imm: Immunization) {
            if let v = imm.lotNumber?.value?.string {
                p.strings.append(.init(paramName: "\(code)", value: v))
            }
        }
        """

    // ── date: occurrence (choice type: dateTime or string) ───────────────────
    case "date":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ imm: Immunization) {
            let cal = Calendar(identifier: .gregorian)
            switch imm.occurrence {
            case .dateTime(let prim):
                guard let dt = prim.value else { return }
                var dc = DateComponents()
                dc.year = dt.date.year; dc.month = dt.date.month.map(Int.init)
                dc.day  = dt.date.day.map(Int.init); dc.hour = 12
                dc.timeZone = dt.timeZone
                let d = cal.date(from: dc) ?? Date()
                p.dates.append(.init(paramName: "date", dateStart: d, dateEnd: d))
            default:
                break
            }
        }
        """

    // ── reference: location ───────────────────────────────────────────────────
    case "location":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ imm: Immunization) {
            guard let refStr = imm.location?.reference?.value?.string else { return }
            let parts = refStr.split(separator: "/")
            let (refType, refId): (String?, String) = parts.count == 2
                ? (String(parts[0]), String(parts[1]))
                : (nil, refStr)
            p.references.append(.init(paramName: "location", refType: refType, refId: refId))
        }
        """

    // ── reference: manufacturer ───────────────────────────────────────────────
    case "manufacturer":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ imm: Immunization) {
            guard let refStr = imm.manufacturer?.reference?.value?.string else { return }
            let parts = refStr.split(separator: "/")
            let (refType, refId): (String?, String) = parts.count == 2
                ? (String(parts[0]), String(parts[1]))
                : (nil, refStr)
            p.references.append(.init(paramName: "manufacturer", refType: refType, refId: refId))
        }
        """

    // ── reference: reaction (detail) ─────────────────────────────────────────
    case "reaction":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ imm: Immunization) {
            for rxn in imm.reaction ?? [] {
                guard let refStr = rxn.detail?.reference?.value?.string else { continue }
                let parts = refStr.split(separator: "/")
                let (refType, refId): (String?, String) = parts.count == 2
                    ? (String(parts[0]), String(parts[1]))
                    : (nil, refStr)
                p.references.append(.init(paramName: "reaction", refType: refType, refId: refId))
            }
        }
        """

    // ── date: reaction-date ───────────────────────────────────────────────────
    case "reaction-date":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ imm: Immunization) {
            let cal = Calendar(identifier: .gregorian)
            for rxn in imm.reaction ?? [] {
                guard let prim = rxn.date, let dt = prim.value else { continue }
                var dc = DateComponents()
                dc.year = dt.date.year; dc.month = dt.date.month.map(Int.init)
                dc.day  = dt.date.day.map(Int.init); dc.hour = 12
                dc.timeZone = dt.timeZone
                let d = cal.date(from: dc) ?? Date()
                p.dates.append(.init(paramName: "reaction-date", dateStart: d, dateEnd: d))
            }
        }
        """

    // ── token: reason-code ────────────────────────────────────────────────────
    case "reason-code":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ imm: Immunization) {
            for cc in imm.reasonCode ?? [] {
                for coding in cc.coding ?? [] {
                    let c = coding.code?.value?.string ?? ""
                    let s = coding.system?.value?.url.absoluteString
                    p.appendToken(paramName: "reason-code", system: s, code: c, display: coding.display?.value?.string)
                }
            }
        }
        """

    // ── reference: reason-reference ──────────────────────────────────────────
    case "reason-reference":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ imm: Immunization) {
            for ref in imm.reasonReference ?? [] {
                guard let refStr = ref.reference?.value?.string else { continue }
                let parts = refStr.split(separator: "/")
                let (refType, refId): (String?, String) = parts.count == 2
                    ? (String(parts[0]), String(parts[1]))
                    : (nil, refStr)
                p.references.append(.init(paramName: "reason-reference", refType: refType, refId: refId))
            }
        }
        """

    // ── string: series ────────────────────────────────────────────────────────
    case "series":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ imm: Immunization) {
            for pa in imm.protocolApplied ?? [] {
                if let v = pa.series?.value?.string {
                    p.strings.append(.init(paramName: "series", value: v))
                }
            }
        }
        """

    // ── token: status-reason ─────────────────────────────────────────────────
    case "status-reason":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ imm: Immunization) {
            for coding in imm.statusReason?.coding ?? [] {
                let c = coding.code?.value?.string ?? ""
                let s = coding.system?.value?.url.absoluteString
                p.appendToken(paramName: "status-reason", system: s, code: c, display: coding.display?.value?.string)
            }
        }
        """

    // ── token: target-disease ─────────────────────────────────────────────────
    case "target-disease":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ imm: Immunization) {
            for pa in imm.protocolApplied ?? [] {
                for cc in pa.targetDisease ?? [] {
                    for coding in cc.coding ?? [] {
                        let c = coding.code?.value?.string ?? ""
                        let s = coding.system?.value?.url.absoluteString
                        p.appendToken(paramName: "target-disease", system: s, code: c, display: coding.display?.value?.string)
                    }
                }
            }
        }
        """

    default:
        return nil
    }
}
