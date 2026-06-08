import Foundation

/// Extracts the `MedicationRequest.xxx` part from a multi-resource FHIRPath expression.
func medicationRequestExpr(from expression: String) -> String? {
    for part in expression.components(separatedBy: " | ") {
        var clean = part.trimmingCharacters(in: .whitespaces)
        if clean.hasPrefix("(") { clean = String(clean.dropFirst()) }
        guard clean.hasPrefix("MedicationRequest.") else { continue }
        clean = clean.components(separatedBy: " as ")[0]
        clean = clean.components(separatedBy: ".where(")[0]
        return clean.trimmingCharacters(in: .whitespaces)
    }
    return nil
}

/// Returns the Swift function body for a given MedicationRequest param.
/// Switches on `spec.code` because `code` needs the medication choice-type check.
func medicationRequestHandler(spec: ParamSpec, expr: String) -> String? {
    let code = spec.code
    let fn = "extract_MedicationRequest_\(code.replacingOccurrences(of: "-", with: "_"))"
    let header = "// \(code) [\(spec.type)] — \(expr)"

    switch code {

    // ── token: status ─────────────────────────────────────────────────────────
    case "status":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ mr: MedicationRequest) {
            if let v = mr.status.value?.rawValue {
                p.tokens.append(.init(paramName: "\(code)",
                                      system: "http://hl7.org/fhir/CodeSystem/medicationrequest-status",
                                      code: v))
            }
        }
        """

    // ── token: intent ─────────────────────────────────────────────────────────
    case "intent":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ mr: MedicationRequest) {
            if let v = mr.intent.value?.rawValue {
                p.tokens.append(.init(paramName: "\(code)",
                                      system: "http://hl7.org/fhir/CodeSystem/medicationrequest-intent",
                                      code: v))
            }
        }
        """

    // ── token: priority ───────────────────────────────────────────────────────
    case "priority":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ mr: MedicationRequest) {
            if let v = mr.priority?.value?.rawValue {
                p.tokens.append(.init(paramName: "\(code)",
                                      system: "http://hl7.org/fhir/request-priority",
                                      code: v))
            }
        }
        """

    // ── token: category ───────────────────────────────────────────────────────
    case "category":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ mr: MedicationRequest) {
            for cc in mr.category ?? [] {
                for coding in cc.coding ?? [] {
                    let c = coding.code?.value?.string ?? ""
                    let s = coding.system?.value?.url.absoluteString
                    p.tokens.append(.init(paramName: "\(code)", system: s, code: c))
                }
            }
        }
        """

    // ── token: code (medication as CodeableConcept choice type) ──────────────
    case "code":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ mr: MedicationRequest) {
            guard case .codeableConcept(let cc) = mr.medication else { return }
            for coding in cc.coding ?? [] {
                let c = coding.code?.value?.string ?? ""
                let s = coding.system?.value?.url.absoluteString
                p.tokens.append(.init(paramName: "\(code)", system: s, code: c))
            }
        }
        """

    // ── token: identifier ─────────────────────────────────────────────────────
    case "identifier":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ mr: MedicationRequest) {
            for ident in mr.identifier ?? [] {
                let v = ident.value?.value?.string ?? ""
                let s = ident.system?.value?.url.absoluteString
                p.tokens.append(.init(paramName: "\(code)", system: s, code: v))
            }
        }
        """

    // ── reference: subject / patient ─────────────────────────────────────────
    case "subject", "patient":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ mr: MedicationRequest) {
            guard let refStr = mr.subject.reference?.value?.string else { return }
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
        private func \(fn)(_ p: inout SearchParams, _ mr: MedicationRequest) {
            guard let refStr = mr.encounter?.reference?.value?.string else { return }
            let parts = refStr.split(separator: "/")
            let (refType, refId): (String?, String) = parts.count == 2
                ? (String(parts[0]), String(parts[1]))
                : (nil, refStr)
            p.references.append(.init(paramName: "\(code)", refType: refType, refId: refId))
        }
        """

    // ── reference: requester ─────────────────────────────────────────────────
    case "requester":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ mr: MedicationRequest) {
            guard let refStr = mr.requester?.reference?.value?.string else { return }
            let parts = refStr.split(separator: "/")
            let (refType, refId): (String?, String) = parts.count == 2
                ? (String(parts[0]), String(parts[1]))
                : (nil, refStr)
            p.references.append(.init(paramName: "\(code)", refType: refType, refId: refId))
        }
        """

    // ── reference: intended-dispenser (dispenseRequest.performer) ───────────
    case "intended-dispenser":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ mr: MedicationRequest) {
            guard let refStr = mr.dispenseRequest?.performer?.reference?.value?.string else { return }
            let parts = refStr.split(separator: "/")
            let (refType, refId): (String?, String) = parts.count == 2
                ? (String(parts[0]), String(parts[1]))
                : (nil, refStr)
            p.references.append(.init(paramName: "\(code)", refType: refType, refId: refId))
        }
        """

    // ── reference: intended-performer ────────────────────────────────────────
    case "intended-performer":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ mr: MedicationRequest) {
            guard let refStr = mr.performer?.reference?.value?.string else { return }
            let parts = refStr.split(separator: "/")
            let (refType, refId): (String?, String) = parts.count == 2
                ? (String(parts[0]), String(parts[1]))
                : (nil, refStr)
            p.references.append(.init(paramName: "\(code)", refType: refType, refId: refId))
        }
        """

    // ── token: intended-performertype ─────────────────────────────────────────
    case "intended-performertype":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ mr: MedicationRequest) {
            for coding in mr.performerType?.coding ?? [] {
                let c = coding.code?.value?.string ?? ""
                let s = coding.system?.value?.url.absoluteString
                p.tokens.append(.init(paramName: "\(code)", system: s, code: c))
            }
        }
        """

    // ── reference: medication (as Reference) ──────────────────────────────────
    case "medication":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ mr: MedicationRequest) {
            guard case .reference(let ref) = mr.medication,
                  let refStr = ref.reference?.value?.string else { return }
            let parts = refStr.split(separator: "/")
            let (refType, refId): (String?, String) = parts.count == 2
                ? (String(parts[0]), String(parts[1]))
                : (nil, refStr)
            p.references.append(.init(paramName: "\(code)", refType: refType, refId: refId))
        }
        """

    // ── date: dosage timing events ────────────────────────────────────────────
    case "date":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ mr: MedicationRequest) {
            let cal = Calendar(identifier: .gregorian)
            for dosage in mr.dosageInstruction ?? [] {
                for evt in dosage.timing?.event ?? [] {
                    guard let dt = evt.value else { continue }
                    var dc = DateComponents()
                    dc.year = dt.date.year; dc.month = dt.date.month.map(Int.init)
                    dc.day  = dt.date.day.map(Int.init); dc.hour = 12
                    dc.timeZone = dt.timeZone
                    let d = cal.date(from: dc) ?? Date()
                    p.dates.append(.init(paramName: "date", dateStart: d, dateEnd: d))
                }
            }
        }
        """

    // ── date: authoredOn ─────────────────────────────────────────────────────
    case "authoredon":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ mr: MedicationRequest) {
            guard let prim = mr.authoredOn, let dt = prim.value else { return }
            var dc = DateComponents()
            dc.year = dt.date.year; dc.month = dt.date.month.map(Int.init)
            dc.day  = dt.date.day.map(Int.init); dc.hour = 12
            dc.timeZone = dt.timeZone
            let d = Calendar(identifier: .gregorian).date(from: dc) ?? Date()
            p.dates.append(.init(paramName: "\(code)", dateStart: d, dateEnd: d))
        }
        """

    default:
        return nil
    }
}
