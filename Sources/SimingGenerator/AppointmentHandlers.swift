import Foundation

/// Extracts the `Appointment.xxx` part from a multi-resource FHIRPath expression.
func appointmentExpr(from expression: String) -> String? {
    for part in expression.components(separatedBy: " | ") {
        var clean = part.trimmingCharacters(in: .whitespaces)
        if clean.hasPrefix("(") { clean = String(clean.dropFirst()) }
        guard clean.hasPrefix("Appointment.") else { continue }
        clean = clean.components(separatedBy: " as ")[0]
        clean = clean.components(separatedBy: ".where(")[0]
        return clean.trimmingCharacters(in: .whitespaces)
    }
    return nil
}

/// Returns the Swift function body for a given Appointment param.
func appointmentHandler(spec: ParamSpec, expr: String) -> String? {
    let code = spec.code
    let fn = "extract_Appointment_\(code.replacingOccurrences(of: "-", with: "_"))"
    let header = "// \(code) [\(spec.type)] — \(expr)"

    switch code {

    // ── token: status (REQUIRED) ─────────────────────────────────────────────
    case "status":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ appt: Appointment) {
            if let v = appt.status.value?.rawValue {
                p.tokens.append(.init(paramName: "\(code)", system: nil, code: v))
            }
        }
        """

    // ── token: identifier ─────────────────────────────────────────────────────
    case "identifier":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ appt: Appointment) {
            for ident in appt.identifier ?? [] {
                let v = ident.value?.value?.string ?? ""
                let s = ident.system?.value?.url.absoluteString
                p.tokens.append(.init(paramName: "\(code)", system: s, code: v))
            }
        }
        """

    // ── token: service-type ───────────────────────────────────────────────────
    case "service-type":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ appt: Appointment) {
            for cc in appt.serviceType ?? [] {
                for coding in cc.coding ?? [] {
                    let v = coding.code?.value?.string ?? ""
                    let s = coding.system?.value?.url.absoluteString
                    p.tokens.append(.init(paramName: "\(code)", system: s, code: v))
                }
            }
        }
        """

    // ── token: service-category ───────────────────────────────────────────────
    case "service-category":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ appt: Appointment) {
            for cc in appt.serviceCategory ?? [] {
                for coding in cc.coding ?? [] {
                    let v = coding.code?.value?.string ?? ""
                    let s = coding.system?.value?.url.absoluteString
                    p.tokens.append(.init(paramName: "\(code)", system: s, code: v))
                }
            }
        }
        """

    // ── token: specialty ──────────────────────────────────────────────────────
    case "specialty":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ appt: Appointment) {
            for cc in appt.specialty ?? [] {
                for coding in cc.coding ?? [] {
                    let v = coding.code?.value?.string ?? ""
                    let s = coding.system?.value?.url.absoluteString
                    p.tokens.append(.init(paramName: "\(code)", system: s, code: v))
                }
            }
        }
        """

    // ── token: appointment-type ───────────────────────────────────────────────
    case "appointment-type":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ appt: Appointment) {
            for coding in appt.appointmentType?.coding ?? [] {
                let v = coding.code?.value?.string ?? ""
                let s = coding.system?.value?.url.absoluteString
                p.tokens.append(.init(paramName: "\(code)", system: s, code: v))
            }
        }
        """

    // ── token: reason-code ────────────────────────────────────────────────────
    case "reason-code":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ appt: Appointment) {
            for cc in appt.reasonCode ?? [] {
                for coding in cc.coding ?? [] {
                    let v = coding.code?.value?.string ?? ""
                    let s = coding.system?.value?.url.absoluteString
                    p.tokens.append(.init(paramName: "\(code)", system: s, code: v))
                }
            }
        }
        """

    // ── token: part-status (Appointment.participant[].status) ─────────────────
    case "part-status":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ appt: Appointment) {
            for participant in appt.participant {
                if let v = participant.status.value?.rawValue {
                    p.tokens.append(.init(paramName: "\(code)", system: nil, code: v))
                }
            }
        }
        """

    // ── reference: patient / practitioner / location / actor ─────────────────
    // All come from Appointment.participant[].actor (generator strips .where()).
    // ref_type preserved — search filters by ref_type for type-specific params.
    case "patient", "practitioner", "location", "actor":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ appt: Appointment) {
            for participant in appt.participant {
                guard let refStr = participant.actor?.reference?.value?.string else { continue }
                let parts = refStr.split(separator: "/")
                let (refType, refId): (String?, String) = parts.count == 2
                    ? (String(parts[0]), String(parts[1]))
                    : (nil, refStr)
                p.references.append(.init(paramName: "\(code)", refType: refType, refId: refId))
            }
        }
        """

    // ── reference: slot ───────────────────────────────────────────────────────
    case "slot":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ appt: Appointment) {
            for ref in appt.slot ?? [] {
                guard let refStr = ref.reference?.value?.string else { continue }
                let parts = refStr.split(separator: "/")
                let (refType, refId): (String?, String) = parts.count == 2
                    ? (String(parts[0]), String(parts[1]))
                    : (nil, refStr)
                p.references.append(.init(paramName: "\(code)", refType: refType, refId: refId))
            }
        }
        """

    // ── reference: based-on ───────────────────────────────────────────────────
    case "based-on":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ appt: Appointment) {
            for ref in appt.basedOn ?? [] {
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
    case "reason-reference":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ appt: Appointment) {
            for ref in appt.reasonReference ?? [] {
                guard let refStr = ref.reference?.value?.string else { continue }
                let parts = refStr.split(separator: "/")
                let (refType, refId): (String?, String) = parts.count == 2
                    ? (String(parts[0]), String(parts[1]))
                    : (nil, refStr)
                p.references.append(.init(paramName: "\(code)", refType: refType, refId: refId))
            }
        }
        """

    // ── reference: supporting-info (supportingInformation — array of references) ─
    case "supporting-info":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ appt: Appointment) {
            for ref in appt.supportingInformation ?? [] {
                guard let refStr = ref.reference?.value?.string else { continue }
                let parts = refStr.split(separator: "/")
                let (refType, refId): (String?, String) = parts.count == 2
                    ? (String(parts[0]), String(parts[1]))
                    : (nil, refStr)
                p.references.append(.init(paramName: "\(code)", refType: refType, refId: refId))
            }
        }
        """

    // ── date: date (Appointment.start — Instant type) ─────────────────────────
    case "date":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ appt: Appointment) {
            guard let inst = appt.start?.value else { return }
            var dc = DateComponents()
            dc.year     = inst.date.year
            dc.month    = Int(inst.date.month)
            dc.day      = Int(inst.date.day)
            dc.hour     = Int(inst.time.hour)
            dc.minute   = Int(inst.time.minute)
            dc.second   = Int(truncating: inst.time.second as NSDecimalNumber)
            dc.timeZone = inst.timeZone
            let d = Calendar(identifier: .gregorian).date(from: dc) ?? Date()
            p.dates.append(.init(paramName: "\(code)", dateStart: d, dateEnd: d))
        }
        """

    default:
        return nil
    }
}
