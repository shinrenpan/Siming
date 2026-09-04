import Foundation

func practitionerRoleExpr(from expression: String) -> String? {
    for part in expression.components(separatedBy: " | ") {
        var clean = part.trimmingCharacters(in: .whitespaces)
        if clean.hasPrefix("(") { clean = String(clean.dropFirst()) }
        guard clean.hasPrefix("PractitionerRole.") else { continue }
        clean = clean.components(separatedBy: " as ")[0]
        clean = clean.components(separatedBy: ".where(")[0]
        return clean.trimmingCharacters(in: .whitespaces)
    }
    return nil
}

func practitionerRoleHandler(spec: ParamSpec, expr: String) -> String? {
    let code = spec.code
    let fn = "extract_PractitionerRole_\(code.replacingOccurrences(of: "-", with: "_"))"
    let header = "// \(code) [\(spec.type)] — \(expr)"

    switch code {

    // ── reference: practitioner ───────────────────────────────────────────────
    case "practitioner":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ role: PractitionerRole) {
            guard let refStr = role.practitioner?.reference?.value?.string else { return }
            let parts = refStr.split(separator: "/")
            let (refType, refId): (String?, String) = parts.count == 2
                ? (String(parts[0]), String(parts[1]))
                : (nil, refStr)
            p.references.append(.init(paramName: "practitioner", refType: refType, refId: refId))
        }
        """

    default:
        return nil
    }
}
