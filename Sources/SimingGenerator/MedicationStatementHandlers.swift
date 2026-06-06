import Foundation

/// Extracts the `MedicationStatement.xxx` part from a multi-resource FHIRPath expression.
func medicationStatementExpr(from expression: String) -> String? {
    for part in expression.components(separatedBy: " | ") {
        var clean = part.trimmingCharacters(in: .whitespaces)
        if clean.hasPrefix("(") { clean = String(clean.dropFirst()) }
        guard clean.hasPrefix("MedicationStatement.") else { continue }
        clean = clean.components(separatedBy: " as ")[0]
        clean = clean.components(separatedBy: ".where(")[0]
        return clean.trimmingCharacters(in: .whitespaces)
    }
    return nil
}

/// Returns the Swift function body for a given MedicationStatement param.
func medicationStatementHandler(spec: ParamSpec, expr: String) -> String? {
    let code = spec.code
    let fn = "extract_MedicationStatement_\(code.replacingOccurrences(of: "-", with: "_"))"
    let header = "// \(code) [\(spec.type)] — \(expr)"

    switch code {

    // ── token: status (REQUIRED) ──────────────────────────────────────────────
    case "status":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ ms: MedicationStatement) {
            if let v = ms.status.value?.rawValue {
                p.tokens.append(.init(paramName: "\(code)",
                                      system: "http://hl7.org/fhir/CodeSystem/medication-statement-status",
                                      code: v))
            }
        }
        """

    // ── token: category (singular CodeableConcept) ────────────────────────────
    case "category":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ ms: MedicationStatement) {
            for coding in ms.category?.coding ?? [] {
                let v = coding.code?.value?.string ?? ""
                let s = coding.system?.value?.url.absoluteString
                p.tokens.append(.init(paramName: "\(code)", system: s, code: v))
            }
        }
        """

    // ── token: code (medication as CodeableConcept choice type) ──────────────
    case "code":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ ms: MedicationStatement) {
            guard case .codeableConcept(let cc) = ms.medication else { return }
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
        private func \(fn)(_ p: inout SearchParams, _ ms: MedicationStatement) {
            for ident in ms.identifier ?? [] {
                let v = ident.value?.value?.string ?? ""
                let s = ident.system?.value?.url.absoluteString
                p.tokens.append(.init(paramName: "\(code)", system: s, code: v))
            }
        }
        """

    // ── reference: subject (REQUIRED) ────────────────────────────────────────
    case "subject":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ ms: MedicationStatement) {
            guard let refStr = ms.subject.reference?.value?.string else { return }
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
        private func \(fn)(_ p: inout SearchParams, _ ms: MedicationStatement) {
            guard let refStr = ms.subject.reference?.value?.string else { return }
            let parts = refStr.split(separator: "/")
            let (refType, refId): (String?, String) = parts.count == 2
                ? (String(parts[0]), String(parts[1]))
                : (nil, refStr)
            p.references.append(.init(paramName: "\(code)", refType: refType, refId: refId))
        }
        """

    // ── reference: context (Encounter) ───────────────────────────────────────
    case "context":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ ms: MedicationStatement) {
            guard let refStr = ms.context?.reference?.value?.string else { return }
            let parts = refStr.split(separator: "/")
            let (refType, refId): (String?, String) = parts.count == 2
                ? (String(parts[0]), String(parts[1]))
                : (nil, refStr)
            p.references.append(.init(paramName: "\(code)", refType: refType, refId: refId))
        }
        """

    // ── reference: source (informationSource) ────────────────────────────────
    case "source":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ ms: MedicationStatement) {
            guard let refStr = ms.informationSource?.reference?.value?.string else { return }
            let parts = refStr.split(separator: "/")
            let (refType, refId): (String?, String) = parts.count == 2
                ? (String(parts[0]), String(parts[1]))
                : (nil, refStr)
            p.references.append(.init(paramName: "\(code)", refType: refType, refId: refId))
        }
        """

    // ── reference: medication (medication as Reference choice type) ───────────
    case "medication":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ ms: MedicationStatement) {
            guard case .reference(let ref) = ms.medication,
                  let refStr = ref.reference?.value?.string else { return }
            let parts = refStr.split(separator: "/")
            let (refType, refId): (String?, String) = parts.count == 2
                ? (String(parts[0]), String(parts[1]))
                : (nil, refStr)
            p.references.append(.init(paramName: "\(code)", refType: refType, refId: refId))
        }
        """

    // ── reference: part-of ────────────────────────────────────────────────────
    case "part-of":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ ms: MedicationStatement) {
            for ref in ms.partOf ?? [] {
                guard let refStr = ref.reference?.value?.string else { continue }
                let parts = refStr.split(separator: "/")
                let (refType, refId): (String?, String) = parts.count == 2
                    ? (String(parts[0]), String(parts[1]))
                    : (nil, refStr)
                p.references.append(.init(paramName: "\(code)", refType: refType, refId: refId))
            }
        }
        """

    // ── date: effective (EffectiveX union — dateTime or Period) ──────────────
    case "effective":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ ms: MedicationStatement) {
            switch ms.effective {
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
            case nil:
                break
            }
        }
        """

    default:
        return nil
    }
}
