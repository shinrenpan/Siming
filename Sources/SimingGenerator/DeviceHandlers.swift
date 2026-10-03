import Foundation

/// Extracts the `Device.xxx` part from a multi-resource FHIRPath expression.
func deviceExpr(from expression: String) -> String? {
    for part in expression.components(separatedBy: " | ") {
        var clean = part.trimmingCharacters(in: .whitespaces)
        if clean.hasPrefix("(") { clean = String(clean.dropFirst()) }
        guard clean.hasPrefix("Device.") else { continue }
        clean = clean.components(separatedBy: " as ")[0]
        clean = clean.components(separatedBy: ".where(")[0]
        return clean.trimmingCharacters(in: .whitespaces)
    }
    return nil
}

/// Returns the Swift function body for a given Device param.
func deviceHandler(spec: ParamSpec, expr: String) -> String? {
    let code = spec.code
    let fn = "extract_Device_\(code.replacingOccurrences(of: "-", with: "_"))"
    let header = "// \(code) [\(spec.type)] — \(expr)"

    /// Single Reference? → idx_reference.
    func singleRef(_ path: String) -> String {
        """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ d: Device) {
            guard let refStr = d.\(path)?.reference?.value?.string else { return }
            let parts = refStr.split(separator: "/")
            let (refType, refId): (String?, String) = parts.count == 2
                ? (String(parts[0]), String(parts[1]))
                : (nil, refStr)
            p.references.append(.init(paramName: "\(code)", refType: refType, refId: refId))
        }
        """
    }

    /// FHIRPrimitive<FHIRString>? → idx_string.
    func singleString(_ path: String) -> String {
        """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ d: Device) {
            if let v = d.\(path)?.value?.string { p.strings.append(.init(paramName: "\(code)", value: v)) }
        }
        """
    }

    /// [DeviceUdiCarrier] field → idx_string.
    func udiString(_ field: String) -> String {
        """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ d: Device) {
            for udi in d.udiCarrier ?? [] {
                if let v = udi.\(field)?.value?.string { p.strings.append(.init(paramName: "\(code)", value: v)) }
            }
        }
        """
    }

    switch code {

    // ── token: status (required binding) ─────────────────────────────────────
    case "status":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ d: Device) {
            if let v = d.status?.value?.rawValue {
                p.tokens.append(.init(paramName: "\(code)",
                                      system: "http://hl7.org/fhir/device-status", code: v))
            }
        }
        """

    // ── token: type ───────────────────────────────────────────────────────────
    case "type":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ d: Device) {
            for coding in d.type?.coding ?? [] {
                let c = coding.code?.value?.string ?? ""
                let s = coding.system?.value?.url.absoluteString
                p.appendToken(paramName: "\(code)", system: s, code: c, display: coding.display?.value?.string)
            }
            p.appendConceptText(paramName: "\(code)", d.type?.text?.value?.string)
        }
        """

    // ── token: identifier ─────────────────────────────────────────────────────
    case "identifier":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ d: Device) {
            for ident in d.identifier ?? [] {
                let v = ident.value?.value?.string ?? ""
                let sys = ident.system?.value?.url.absoluteString
                p.tokens.append(.init(paramName: "\(code)", system: sys, code: v))
            }
        }
        """

    // ── string: device-name (deviceName.name | type.coding.display | type.text) ─
    case "device-name":
        return """
        // \(code) [\(spec.type)] — \(spec.expression)
        private func \(fn)(_ p: inout SearchParams, _ d: Device) {
            for dn in d.deviceName ?? [] {
                if let v = dn.name.value?.string { p.strings.append(.init(paramName: "\(code)", value: v)) }
            }
            for coding in d.type?.coding ?? [] {
                if let v = coding.display?.value?.string { p.strings.append(.init(paramName: "\(code)", value: v)) }
            }
            if let v = d.type?.text?.value?.string { p.strings.append(.init(paramName: "\(code)", value: v)) }
        }
        """

    // ── string: manufacturer / model / udi-carrier / udi-di ───────────────────
    case "manufacturer": return singleString("manufacturer")
    case "model":        return singleString("modelNumber")
    case "udi-carrier":  return udiString("carrierHRF")
    case "udi-di":       return udiString("deviceIdentifier")

    // ── uri: url (idx_string, exact match) ────────────────────────────────────
    case "url":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ d: Device) {
            if let v = d.url?.value?.url.absoluteString { p.strings.append(.init(paramName: "\(code)", value: v)) }
        }
        """

    // ── reference: patient / organization (owner) / location ──────────────────
    case "patient":      return singleRef("patient")
    case "organization": return singleRef("owner")
    case "location":     return singleRef("location")

    default:
        return nil
    }
}
