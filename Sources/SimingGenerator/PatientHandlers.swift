import Foundation

/// Extracts the `Patient.xxx` part from a multi-resource expression like
/// "Patient.name | Person.name | Practitioner.name".
func patientExpr(from expression: String) -> String? {
    for part in expression.components(separatedBy: " | ") {
        var clean = part.trimmingCharacters(in: .whitespaces)
        if clean.hasPrefix("(") { clean = String(clean.dropFirst()) }
        guard clean.hasPrefix("Patient.") else { continue }
        clean = clean.components(separatedBy: " as ")[0]
        clean = clean.components(separatedBy: ".where(")[0]
        if let r = clean.range(of: ".exists()") { clean = String(clean[..<r.lowerBound]) }
        clean = clean.components(separatedBy: " and ")[0]
        return clean.trimmingCharacters(in: .whitespaces)
    }
    return nil
}

/// Returns the Swift function body string for a given Patient expression,
/// or nil if the expression is not (yet) handled.
func patientHandler(spec: ParamSpec, expr: String) -> String? {
    let code = spec.code
    let fn = "extract_Patient_\(code.replacingOccurrences(of: "-", with: "_"))"
    let header = "// \(code) [\(spec.type)] — \(expr)"

    switch expr {

    // ── string: name ────────────────────────────────────────────────────────
    case "Patient.name", "Patient.name | Patient.name":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ patient: Patient) {
            for name in patient.name ?? [] {
                if let v = name.text?.value?.string   { p.strings.append(.init(paramName: "\(code)", value: v)) }
                if let v = name.family?.value?.string { p.strings.append(.init(paramName: "\(code)", value: v)) }
                for given in name.given ?? [] {
                    if let v = given.value?.string { p.strings.append(.init(paramName: "\(code)", value: v)) }
                }
            }
        }
        """

    case "Patient.name.family":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ patient: Patient) {
            for name in patient.name ?? [] {
                if let v = name.family?.value?.string { p.strings.append(.init(paramName: "\(code)", value: v)) }
            }
        }
        """

    case "Patient.name.given":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ patient: Patient) {
            for name in patient.name ?? [] {
                for given in name.given ?? [] {
                    if let v = given.value?.string { p.strings.append(.init(paramName: "\(code)", value: v)) }
                }
            }
        }
        """

    // ── token: identifier ───────────────────────────────────────────────────
    case "Patient.identifier":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ patient: Patient) {
            for ident in patient.identifier ?? [] {
                let identValue  = ident.value?.value?.string ?? ""
                let identSystem = ident.system?.value?.url.absoluteString
                p.tokens.append(.init(paramName: "\(code)", system: identSystem, code: identValue))
            }
        }
        """

    // ── date: birthDate ─────────────────────────────────────────────────────
    case "Patient.birthDate":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ patient: Patient) {
            guard let bd = patient.birthDate?.value else { return }
            var dc = DateComponents()
            dc.year  = bd.year
            dc.month = bd.month.map(Int.init)
            dc.day   = bd.day.map(Int.init)
            dc.hour  = 12
            let date = Calendar(identifier: .gregorian).date(from: dc) ?? Date()
            p.dates.append(.init(paramName: "\(code)", dateStart: date, dateEnd: date))
        }
        """

    // ── token: gender ────────────────────────────────────────────────────────
    case "Patient.gender":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ patient: Patient) {
            if let v = patient.gender?.value?.rawValue {
                p.tokens.append(.init(paramName: "\(code)",
                                      system: "http://hl7.org/fhir/administrative-gender", code: v))
            }
        }
        """

    // ── token: active ────────────────────────────────────────────────────────
    case "Patient.active":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ patient: Patient) {
            if let v = patient.active?.value?.bool {
                p.tokens.append(.init(paramName: "\(code)", system: nil, code: v ? "true" : "false"))
            }
        }
        """

    // ── string: address ──────────────────────────────────────────────────────
    case "Patient.address":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ patient: Patient) {
            for addr in patient.address ?? [] {
                if let v = addr.text?.value?.string       { p.strings.append(.init(paramName: "\(code)", value: v)) }
                for line in addr.line ?? [] {
                    if let v = line.value?.string          { p.strings.append(.init(paramName: "\(code)", value: v)) }
                }
                if let v = addr.city?.value?.string        { p.strings.append(.init(paramName: "\(code)", value: v)) }
                if let v = addr.state?.value?.string       { p.strings.append(.init(paramName: "\(code)", value: v)) }
                if let v = addr.postalCode?.value?.string  { p.strings.append(.init(paramName: "\(code)", value: v)) }
                if let v = addr.country?.value?.string     { p.strings.append(.init(paramName: "\(code)", value: v)) }
            }
        }
        """

    case "Patient.address.city":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ patient: Patient) {
            for addr in patient.address ?? [] {
                if let v = addr.city?.value?.string { p.strings.append(.init(paramName: "\(code)", value: v)) }
            }
        }
        """

    case "Patient.address.country":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ patient: Patient) {
            for addr in patient.address ?? [] {
                if let v = addr.country?.value?.string { p.strings.append(.init(paramName: "\(code)", value: v)) }
            }
        }
        """

    case "Patient.address.postalCode":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ patient: Patient) {
            for addr in patient.address ?? [] {
                if let v = addr.postalCode?.value?.string { p.strings.append(.init(paramName: "\(code)", value: v)) }
            }
        }
        """

    case "Patient.address.state":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ patient: Patient) {
            for addr in patient.address ?? [] {
                if let v = addr.state?.value?.string { p.strings.append(.init(paramName: "\(code)", value: v)) }
            }
        }
        """

    case "Patient.address.use":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ patient: Patient) {
            for addr in patient.address ?? [] {
                if let v = addr.use?.value?.rawValue {
                    p.tokens.append(.init(paramName: "\(code)",
                                          system: "http://hl7.org/fhir/address-use", code: v))
                }
            }
        }
        """

    // ── reference: generalPractitioner ──────────────────────────────────────
    case "Patient.generalPractitioner":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ patient: Patient) {
            for ref in patient.generalPractitioner ?? [] {
                guard let refStr = ref.reference?.value?.string else { continue }
                let parts = refStr.split(separator: "/")
                let (refType, refId): (String?, String) = parts.count == 2
                    ? (String(parts[0]), String(parts[1]))
                    : (nil, refStr)
                p.references.append(.init(paramName: "\(code)", refType: refType, refId: refId))
            }
        }
        """

    // ── reference: managingOrganization ─────────────────────────────────────
    case "Patient.managingOrganization":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ patient: Patient) {
            guard let refStr = patient.managingOrganization?.reference?.value?.string else { return }
            let parts = refStr.split(separator: "/")
            let (refType, refId): (String?, String) = parts.count == 2
                ? (String(parts[0]), String(parts[1]))
                : (nil, refStr)
            p.references.append(.init(paramName: "\(code)", refType: refType, refId: refId))
        }
        """

    // ── reference: link.other ────────────────────────────────────────────────
    case "Patient.link.other":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ patient: Patient) {
            for link in patient.link ?? [] {
                guard let refStr = link.other.reference?.value?.string else { continue }
                let parts = refStr.split(separator: "/")
                let (refType, refId): (String?, String) = parts.count == 2
                    ? (String(parts[0]), String(parts[1]))
                    : (nil, refStr)
                p.references.append(.init(paramName: "\(code)", refType: refType, refId: refId))
            }
        }
        """

    // ── token: language ──────────────────────────────────────────────────────
    case "Patient.communication.language":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ patient: Patient) {
            for comm in patient.communication ?? [] {
                for coding in comm.language.coding ?? [] {
                    let c = coding.code?.value?.string ?? ""
                    let s = coding.system?.value?.url.absoluteString
                    p.tokens.append(.init(paramName: "\(code)", system: s, code: c))
                }
                if let text = comm.language.text?.value?.string {
                    p.tokens.append(.init(paramName: "\(code)", system: nil, code: text))
                }
            }
        }
        """

    // ── token: telecom ───────────────────────────────────────────────────────
    case "Patient.telecom":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ patient: Patient) {
            for cp in patient.telecom ?? [] {
                let cpSystem = cp.system?.value?.rawValue
                let cpValue  = cp.value?.value?.string ?? ""
                p.tokens.append(.init(paramName: "\(code)", system: cpSystem, code: cpValue))
            }
        }
        """

    // ── deceased / death-date (choice type: boolean or dateTime) ─────────────
    case "Patient.deceased":
        switch code {
        case "death-date":
            return """
            \(header)
            private func \(fn)(_ p: inout SearchParams, _ patient: Patient) {
                guard case .dateTime(let prim) = patient.deceased, let dt = prim.value else { return }
                var dc = DateComponents()
                dc.year = dt.date.year; dc.month = dt.date.month.map(Int.init)
                dc.day  = dt.date.day.map(Int.init); dc.hour = 12
                dc.timeZone = dt.timeZone
                let d = Calendar(identifier: .gregorian).date(from: dc) ?? Date()
                p.dates.append(.init(paramName: "death-date", dateStart: d, dateEnd: d))
            }
            """
        case "deceased":
            return """
            \(header)
            private func \(fn)(_ p: inout SearchParams, _ patient: Patient) {
                switch patient.deceased {
                case .boolean(let prim):
                    guard let v = prim.value?.bool else { return }
                    p.tokens.append(.init(paramName: "deceased", system: nil, code: v ? "true" : "false"))
                case .dateTime:
                    p.tokens.append(.init(paramName: "deceased", system: nil, code: "true"))
                case nil:
                    break
                }
            }
            """
        default: return nil
        }

    default:
        return nil
    }
}
