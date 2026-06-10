import Foundation

func practitionerExpr(from expression: String) -> String? {
    for part in expression.components(separatedBy: " | ") {
        var clean = part.trimmingCharacters(in: .whitespaces)
        if clean.hasPrefix("(") { clean = String(clean.dropFirst()) }
        guard clean.hasPrefix("Practitioner.") else { continue }
        clean = clean.components(separatedBy: " as ")[0]
        clean = clean.components(separatedBy: ".where(")[0]
        return clean.trimmingCharacters(in: .whitespaces)
    }
    return nil
}

func practitionerHandler(spec: ParamSpec, expr: String) -> String? {
    let code = spec.code
    let fn = "extract_Practitioner_\(code.replacingOccurrences(of: "-", with: "_"))"
    let header = "// \(code) [\(spec.type)] — \(expr)"

    switch expr {

    // ── string: name ─────────────────────────────────────────────────────────
    case "Practitioner.name":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ prac: Practitioner) {
            for name in prac.name ?? [] {
                if let v = name.text?.value?.string   { p.strings.append(.init(paramName: "\(code)", value: v)) }
                if let v = name.family?.value?.string { p.strings.append(.init(paramName: "\(code)", value: v)) }
                for given in name.given ?? [] {
                    if let v = given.value?.string { p.strings.append(.init(paramName: "\(code)", value: v)) }
                }
            }
        }
        """

    case "Practitioner.name.family":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ prac: Practitioner) {
            for name in prac.name ?? [] {
                if let v = name.family?.value?.string { p.strings.append(.init(paramName: "\(code)", value: v)) }
            }
        }
        """

    case "Practitioner.name.given":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ prac: Practitioner) {
            for name in prac.name ?? [] {
                for given in name.given ?? [] {
                    if let v = given.value?.string { p.strings.append(.init(paramName: "\(code)", value: v)) }
                }
            }
        }
        """

    // ── token: identifier ─────────────────────────────────────────────────────
    case "Practitioner.identifier":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ prac: Practitioner) {
            for ident in prac.identifier ?? [] {
                let v = ident.value?.value?.string ?? ""
                let s = ident.system?.value?.url.absoluteString
                p.tokens.append(.init(paramName: "\(code)", system: s, code: v))
            }
        }
        """

    // ── token: active ─────────────────────────────────────────────────────────
    case "Practitioner.active":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ prac: Practitioner) {
            if let v = prac.active?.value?.bool {
                p.tokens.append(.init(paramName: "\(code)", system: nil, code: v ? "true" : "false"))
            }
        }
        """

    // ── token: gender ─────────────────────────────────────────────────────────
    case "Practitioner.gender":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ prac: Practitioner) {
            if let v = prac.gender?.value?.rawValue {
                p.tokens.append(.init(paramName: "\(code)",
                                      system: "http://hl7.org/fhir/administrative-gender", code: v))
            }
        }
        """

    // ── token: communication ──────────────────────────────────────────────────
    case "Practitioner.communication":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ prac: Practitioner) {
            for comm in prac.communication ?? [] {
                for coding in comm.coding ?? [] {
                    let c = coding.code?.value?.string ?? ""
                    let s = coding.system?.value?.url.absoluteString
                    p.appendToken(paramName: "\(code)", system: s, code: c, display: coding.display?.value?.string)
                }
            }
        }
        """

    // ── token: telecom ────────────────────────────────────────────────────────
    case "Practitioner.telecom":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ prac: Practitioner) {
            for cp in prac.telecom ?? [] {
                let s = cp.system?.value?.rawValue
                let v = cp.value?.value?.string ?? ""
                p.tokens.append(.init(paramName: "\(code)", system: s, code: v))
            }
        }
        """

    // ── string: address ───────────────────────────────────────────────────────
    case "Practitioner.address":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ prac: Practitioner) {
            for addr in prac.address ?? [] {
                if let v = addr.text?.value?.string      { p.strings.append(.init(paramName: "\(code)", value: v)) }
                for line in addr.line ?? [] {
                    if let v = line.value?.string         { p.strings.append(.init(paramName: "\(code)", value: v)) }
                }
                if let v = addr.city?.value?.string       { p.strings.append(.init(paramName: "\(code)", value: v)) }
                if let v = addr.state?.value?.string      { p.strings.append(.init(paramName: "\(code)", value: v)) }
                if let v = addr.postalCode?.value?.string { p.strings.append(.init(paramName: "\(code)", value: v)) }
                if let v = addr.country?.value?.string    { p.strings.append(.init(paramName: "\(code)", value: v)) }
            }
        }
        """

    case "Practitioner.address.city":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ prac: Practitioner) {
            for addr in prac.address ?? [] {
                if let v = addr.city?.value?.string { p.strings.append(.init(paramName: "\(code)", value: v)) }
            }
        }
        """

    case "Practitioner.address.country":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ prac: Practitioner) {
            for addr in prac.address ?? [] {
                if let v = addr.country?.value?.string { p.strings.append(.init(paramName: "\(code)", value: v)) }
            }
        }
        """

    case "Practitioner.address.postalCode":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ prac: Practitioner) {
            for addr in prac.address ?? [] {
                if let v = addr.postalCode?.value?.string { p.strings.append(.init(paramName: "\(code)", value: v)) }
            }
        }
        """

    case "Practitioner.address.state":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ prac: Practitioner) {
            for addr in prac.address ?? [] {
                if let v = addr.state?.value?.string { p.strings.append(.init(paramName: "\(code)", value: v)) }
            }
        }
        """

    case "Practitioner.address.use":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ prac: Practitioner) {
            for addr in prac.address ?? [] {
                if let v = addr.use?.value?.rawValue {
                    p.tokens.append(.init(paramName: "\(code)",
                                          system: "http://hl7.org/fhir/address-use", code: v))
                }
            }
        }
        """

    default:
        return nil
    }
}
