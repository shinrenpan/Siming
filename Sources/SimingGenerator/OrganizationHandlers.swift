import Foundation

func organizationExpr(from expression: String) -> String? {
    for part in expression.components(separatedBy: " | ") {
        var clean = part.trimmingCharacters(in: .whitespaces)
        if clean.hasPrefix("(") { clean = String(clean.dropFirst()) }
        guard clean.hasPrefix("Organization.") else { continue }
        clean = clean.components(separatedBy: " as ")[0]
        clean = clean.components(separatedBy: ".where(")[0]
        return clean.trimmingCharacters(in: .whitespaces)
    }
    return nil
}

func organizationHandler(spec: ParamSpec, expr: String) -> String? {
    let code = spec.code
    let fn = "extract_Organization_\(code.replacingOccurrences(of: "-", with: "_"))"
    let header = "// \(code) [\(spec.type)] — \(expr)"

    switch code {

    // ── string: name (also indexes alias) ─────────────────────────────────────
    case "name":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ org: Organization) {
            if let v = org.name?.value?.string { p.strings.append(.init(paramName: "name", value: v)) }
            for alias in org.alias ?? [] {
                if let v = alias.value?.string { p.strings.append(.init(paramName: "name", value: v)) }
            }
        }
        """

    // ── token: identifier ─────────────────────────────────────────────────────
    case "identifier":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ org: Organization) {
            for ident in org.identifier ?? [] {
                let v = ident.value?.value?.string ?? ""
                let s = ident.system?.value?.url.absoluteString
                p.tokens.append(.init(paramName: "identifier", system: s, code: v))
            }
        }
        """

    // ── token: active ─────────────────────────────────────────────────────────
    case "active":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ org: Organization) {
            if let v = org.active?.value?.bool {
                p.tokens.append(.init(paramName: "active", system: nil, code: v ? "true" : "false"))
            }
        }
        """

    // ── token: type ───────────────────────────────────────────────────────────
    case "type":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ org: Organization) {
            for t in org.type ?? [] {
                for coding in t.coding ?? [] {
                    let c = coding.code?.value?.string ?? ""
                    let s = coding.system?.value?.url.absoluteString
                    p.tokens.append(.init(paramName: "type", system: s, code: c))
                }
            }
        }
        """

    // ── string: address ───────────────────────────────────────────────────────
    case "address":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ org: Organization) {
            for addr in org.address ?? [] {
                if let v = addr.text?.value?.string      { p.strings.append(.init(paramName: "address", value: v)) }
                for line in addr.line ?? [] {
                    if let v = line.value?.string         { p.strings.append(.init(paramName: "address", value: v)) }
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
        private func \(fn)(_ p: inout SearchParams, _ org: Organization) {
            for addr in org.address ?? [] {
                if let v = addr.city?.value?.string { p.strings.append(.init(paramName: "address-city", value: v)) }
            }
        }
        """

    case "address-country":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ org: Organization) {
            for addr in org.address ?? [] {
                if let v = addr.country?.value?.string { p.strings.append(.init(paramName: "address-country", value: v)) }
            }
        }
        """

    case "address-postalcode":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ org: Organization) {
            for addr in org.address ?? [] {
                if let v = addr.postalCode?.value?.string { p.strings.append(.init(paramName: "address-postalcode", value: v)) }
            }
        }
        """

    case "address-state":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ org: Organization) {
            for addr in org.address ?? [] {
                if let v = addr.state?.value?.string { p.strings.append(.init(paramName: "address-state", value: v)) }
            }
        }
        """

    case "address-use":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ org: Organization) {
            for addr in org.address ?? [] {
                if let v = addr.use?.value?.rawValue {
                    p.tokens.append(.init(paramName: "address-use",
                                          system: "http://hl7.org/fhir/address-use", code: v))
                }
            }
        }
        """

    // ── reference: partof ─────────────────────────────────────────────────────
    case "partof":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ org: Organization) {
            guard let refStr = org.partOf?.reference?.value?.string else { return }
            let parts = refStr.split(separator: "/")
            let (refType, refId): (String?, String) = parts.count == 2
                ? (String(parts[0]), String(parts[1]))
                : (nil, refStr)
            p.references.append(.init(paramName: "partof", refType: refType, refId: refId))
        }
        """

    // ── reference: endpoint (array) ───────────────────────────────────────────
    case "endpoint":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ org: Organization) {
            for ref in org.endpoint ?? [] {
                guard let refStr = ref.reference?.value?.string else { continue }
                let parts = refStr.split(separator: "/")
                let (refType, refId): (String?, String) = parts.count == 2
                    ? (String(parts[0]), String(parts[1]))
                    : (nil, refStr)
                p.references.append(.init(paramName: "endpoint", refType: refType, refId: refId))
            }
        }
        """

    // ── string: phonetic (alias for name — server-side phonetic algorithm) ───
    case "phonetic":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ org: Organization) {
            if let v = org.name?.value?.string { p.strings.append(.init(paramName: "phonetic", value: v)) }
            for alias in org.alias ?? [] {
                if let v = alias.value?.string { p.strings.append(.init(paramName: "phonetic", value: v)) }
            }
        }
        """

    default:
        return nil
    }
}
