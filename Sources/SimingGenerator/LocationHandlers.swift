import Foundation

func locationExpr(from expression: String) -> String? {
    for part in expression.components(separatedBy: " | ") {
        var clean = part.trimmingCharacters(in: .whitespaces)
        if clean.hasPrefix("(") { clean = String(clean.dropFirst()) }
        guard clean.hasPrefix("Location.") else { continue }
        clean = clean.components(separatedBy: " as ")[0]
        clean = clean.components(separatedBy: ".where(")[0]
        return clean.trimmingCharacters(in: .whitespaces)
    }
    return nil
}

func locationHandler(spec: ParamSpec, expr: String) -> String? {
    let code = spec.code
    let fn = "extract_Location_\(code.replacingOccurrences(of: "-", with: "_"))"
    let header = "// \(code) [\(spec.type)] — \(expr)"

    switch code {

    // ── string: name (also indexes alias) ─────────────────────────────────────
    case "name":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ loc: Location) {
            if let v = loc.name?.value?.string { p.strings.append(.init(paramName: "name", value: v)) }
            for alias in loc.alias ?? [] {
                if let v = alias.value?.string { p.strings.append(.init(paramName: "name", value: v)) }
            }
        }
        """

    // ── token: identifier ─────────────────────────────────────────────────────
    case "identifier":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ loc: Location) {
            for ident in loc.identifier ?? [] {
                let v = ident.value?.value?.string ?? ""
                let s = ident.system?.value?.url.absoluteString
                p.tokens.append(.init(paramName: "identifier", system: s, code: v))
            }
        }
        """

    // ── token: status ─────────────────────────────────────────────────────────
    case "status":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ loc: Location) {
            if let v = loc.status?.value?.rawValue {
                p.tokens.append(.init(paramName: "status",
                                      system: "http://hl7.org/fhir/location-status", code: v))
            }
        }
        """

    // ── token: operational-status ─────────────────────────────────────────────
    case "operational-status":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ loc: Location) {
            if let coding = loc.operationalStatus {
                let c = coding.code?.value?.string ?? ""
                let s = coding.system?.value?.url.absoluteString
                p.tokens.append(.init(paramName: "operational-status", system: s, code: c))
            }
        }
        """

    // ── token: type ───────────────────────────────────────────────────────────
    case "type":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ loc: Location) {
            for t in loc.type ?? [] {
                for coding in t.coding ?? [] {
                    let c = coding.code?.value?.string ?? ""
                    let s = coding.system?.value?.url.absoluteString
                    p.tokens.append(.init(paramName: "type", system: s, code: c))
                }
            }
        }
        """

    // ── string: address (Location has singular address, not array) ────────────
    case "address":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ loc: Location) {
            guard let addr = loc.address else { return }
            if let v = addr.text?.value?.string      { p.strings.append(.init(paramName: "address", value: v)) }
            for line in addr.line ?? [] {
                if let v = line.value?.string         { p.strings.append(.init(paramName: "address", value: v)) }
            }
            if let v = addr.city?.value?.string       { p.strings.append(.init(paramName: "address", value: v)) }
            if let v = addr.state?.value?.string      { p.strings.append(.init(paramName: "address", value: v)) }
            if let v = addr.postalCode?.value?.string { p.strings.append(.init(paramName: "address", value: v)) }
            if let v = addr.country?.value?.string    { p.strings.append(.init(paramName: "address", value: v)) }
        }
        """

    case "address-city":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ loc: Location) {
            if let v = loc.address?.city?.value?.string {
                p.strings.append(.init(paramName: "address-city", value: v))
            }
        }
        """

    case "address-country":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ loc: Location) {
            if let v = loc.address?.country?.value?.string {
                p.strings.append(.init(paramName: "address-country", value: v))
            }
        }
        """

    case "address-postalcode":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ loc: Location) {
            if let v = loc.address?.postalCode?.value?.string {
                p.strings.append(.init(paramName: "address-postalcode", value: v))
            }
        }
        """

    case "address-state":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ loc: Location) {
            if let v = loc.address?.state?.value?.string {
                p.strings.append(.init(paramName: "address-state", value: v))
            }
        }
        """

    case "address-use":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ loc: Location) {
            if let v = loc.address?.use?.value?.rawValue {
                p.tokens.append(.init(paramName: "address-use",
                                      system: "http://hl7.org/fhir/address-use", code: v))
            }
        }
        """

    // ── reference: organization (managingOrganization) ────────────────────────
    case "organization":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ loc: Location) {
            guard let refStr = loc.managingOrganization?.reference?.value?.string else { return }
            let parts = refStr.split(separator: "/")
            let (refType, refId): (String?, String) = parts.count == 2
                ? (String(parts[0]), String(parts[1]))
                : (nil, refStr)
            p.references.append(.init(paramName: "organization", refType: refType, refId: refId))
        }
        """

    // ── reference: partof ─────────────────────────────────────────────────────
    case "partof":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ loc: Location) {
            guard let refStr = loc.partOf?.reference?.value?.string else { return }
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
        private func \(fn)(_ p: inout SearchParams, _ loc: Location) {
            for ref in loc.endpoint ?? [] {
                guard let refStr = ref.reference?.value?.string else { continue }
                let parts = refStr.split(separator: "/")
                let (refType, refId): (String?, String) = parts.count == 2
                    ? (String(parts[0]), String(parts[1]))
                    : (nil, refStr)
                p.references.append(.init(paramName: "endpoint", refType: refType, refId: refId))
            }
        }
        """

    // ── skip: near (geospatial) ───────────────────────────────────────────────
    case "near":
        return nil

    default:
        return nil
    }
}
