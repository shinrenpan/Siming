import Foundation

func relatedPersonExpr(from expression: String) -> String? {
    for part in expression.components(separatedBy: " | ") {
        var clean = part.trimmingCharacters(in: .whitespaces)
        if clean.hasPrefix("(") { clean = String(clean.dropFirst()) }
        guard clean.hasPrefix("RelatedPerson.") else { continue }
        clean = clean.components(separatedBy: " as ")[0]
        clean = clean.components(separatedBy: ".where(")[0]
        return clean.trimmingCharacters(in: .whitespaces)
    }
    return nil
}

func relatedPersonHandler(spec: ParamSpec, expr: String) -> String? {
    let code = spec.code
    let fn = "extract_RelatedPerson_\(code.replacingOccurrences(of: "-", with: "_"))"
    let header = "// \(code) [\(spec.type)] — \(expr)"

    switch code {

    // ── token: active ─────────────────────────────────────────────────────────
    case "active":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ rp: RelatedPerson) {
            if let v = rp.active?.value?.bool {
                p.tokens.append(.init(paramName: "active", system: nil, code: v ? "true" : "false"))
            }
        }
        """

    // ── token: gender ─────────────────────────────────────────────────────────
    case "gender":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ rp: RelatedPerson) {
            if let v = rp.gender?.value?.rawValue {
                p.tokens.append(.init(paramName: "gender",
                                      system: "http://hl7.org/fhir/administrative-gender",
                                      code: v))
            }
        }
        """

    // ── token: identifier ─────────────────────────────────────────────────────
    case "identifier":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ rp: RelatedPerson) {
            for ident in rp.identifier ?? [] {
                let v = ident.value?.value?.string ?? ""
                let s = ident.system?.value?.url.absoluteString
                p.tokens.append(.init(paramName: "identifier", system: s, code: v))
            }
        }
        """

    // ── token: relationship ───────────────────────────────────────────────────
    case "relationship":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ rp: RelatedPerson) {
            for cc in rp.relationship ?? [] {
                for coding in cc.coding ?? [] {
                    let c = coding.code?.value?.string ?? ""
                    let s = coding.system?.value?.url.absoluteString
                    p.appendToken(paramName: "relationship", system: s, code: c, display: coding.display?.value?.string)
                }
            }
        }
        """

    // ── token: phone (telecom where system=phone) ─────────────────────────────
    case "phone":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ rp: RelatedPerson) {
            for tc in rp.telecom ?? [] {
                guard tc.system?.value?.rawValue == "phone" else { continue }
                if let v = tc.value?.value?.string {
                    p.tokens.append(.init(paramName: "phone", system: "phone", code: v))
                }
            }
        }
        """

    // ── token: email (telecom where system=email) ─────────────────────────────
    case "email":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ rp: RelatedPerson) {
            for tc in rp.telecom ?? [] {
                guard tc.system?.value?.rawValue == "email" else { continue }
                if let v = tc.value?.value?.string {
                    p.tokens.append(.init(paramName: "email", system: "email", code: v))
                }
            }
        }
        """

    // ── token: telecom (all entries) ──────────────────────────────────────────
    case "telecom":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ rp: RelatedPerson) {
            for tc in rp.telecom ?? [] {
                let sys = tc.system?.value?.rawValue
                if let v = tc.value?.value?.string {
                    p.tokens.append(.init(paramName: "telecom", system: sys, code: v))
                }
            }
        }
        """

    // ── token: address-use ────────────────────────────────────────────────────
    case "address-use":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ rp: RelatedPerson) {
            for addr in rp.address ?? [] {
                if let v = addr.use?.value?.rawValue {
                    p.tokens.append(.init(paramName: "address-use",
                                          system: "http://hl7.org/fhir/address-use", code: v))
                }
            }
        }
        """

    // ── string: name ──────────────────────────────────────────────────────────
    case "name", "phonetic":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ rp: RelatedPerson) {
            for hn in rp.name ?? [] {
                if let v = hn.family?.value?.string { p.strings.append(.init(paramName: "name", value: v)) }
                for given in hn.given ?? [] {
                    if let v = given.value?.string { p.strings.append(.init(paramName: "name", value: v)) }
                }
                if let v = hn.text?.value?.string { p.strings.append(.init(paramName: "name", value: v)) }
            }
        }
        """

    // ── string: address ───────────────────────────────────────────────────────
    case "address":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ rp: RelatedPerson) {
            for addr in rp.address ?? [] {
                if let v = addr.text?.value?.string       { p.strings.append(.init(paramName: "address", value: v)) }
                for line in addr.line ?? [] {
                    if let v = line.value?.string          { p.strings.append(.init(paramName: "address", value: v)) }
                }
                if let v = addr.city?.value?.string       { p.strings.append(.init(paramName: "address", value: v)) }
                if let v = addr.state?.value?.string      { p.strings.append(.init(paramName: "address", value: v)) }
                if let v = addr.postalCode?.value?.string { p.strings.append(.init(paramName: "address", value: v)) }
                if let v = addr.country?.value?.string    { p.strings.append(.init(paramName: "address", value: v)) }
            }
        }
        """

    case "address-city":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ rp: RelatedPerson) {
            for addr in rp.address ?? [] {
                if let v = addr.city?.value?.string {
                    p.strings.append(.init(paramName: "address-city", value: v))
                }
            }
        }
        """

    case "address-country":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ rp: RelatedPerson) {
            for addr in rp.address ?? [] {
                if let v = addr.country?.value?.string {
                    p.strings.append(.init(paramName: "address-country", value: v))
                }
            }
        }
        """

    case "address-postalcode":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ rp: RelatedPerson) {
            for addr in rp.address ?? [] {
                if let v = addr.postalCode?.value?.string {
                    p.strings.append(.init(paramName: "address-postalcode", value: v))
                }
            }
        }
        """

    case "address-state":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ rp: RelatedPerson) {
            for addr in rp.address ?? [] {
                if let v = addr.state?.value?.string {
                    p.strings.append(.init(paramName: "address-state", value: v))
                }
            }
        }
        """

    // ── date: birthdate ───────────────────────────────────────────────────────
    case "birthdate":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ rp: RelatedPerson) {
            guard let bd = rp.birthDate?.value else { return }
            var dc = DateComponents()
            dc.year = bd.year; dc.month = bd.month.map(Int.init)
            dc.day  = bd.day.map(Int.init)
            let cal = Calendar(identifier: .gregorian)
            let start = cal.date(from: dc) ?? Date()
            var endDc = dc
            if dc.day != nil {
                endDc.hour = 23; endDc.minute = 59; endDc.second = 59
            } else if dc.month != nil {
                endDc.day = cal.range(of: .day, in: .month, for: start)?.count ?? 28
            } else {
                endDc.month = 12; endDc.day = 31
            }
            let end = cal.date(from: endDc) ?? start
            p.dates.append(.init(paramName: "birthdate", dateStart: start, dateEnd: end))
        }
        """

    // ── reference: patient ────────────────────────────────────────────────────
    case "patient":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ rp: RelatedPerson) {
            guard let refStr = rp.patient.reference?.value?.string else { return }
            let parts = refStr.split(separator: "/")
            let (refType, refId): (String?, String) = parts.count == 2
                ? (String(parts[0]), String(parts[1]))
                : (nil, refStr)
            p.references.append(.init(paramName: "patient", refType: refType, refId: refId))
        }
        """

    default:
        return nil
    }
}
