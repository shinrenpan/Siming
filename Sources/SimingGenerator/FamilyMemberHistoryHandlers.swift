import Foundation

/// Extracts the `FamilyMemberHistory.xxx` part from a multi-resource FHIRPath expression.
func familyMemberHistoryExpr(from expression: String) -> String? {
    for part in expression.components(separatedBy: " | ") {
        var clean = part.trimmingCharacters(in: .whitespaces)
        if clean.hasPrefix("(") { clean = String(clean.dropFirst()) }
        guard clean.hasPrefix("FamilyMemberHistory.") else { continue }
        clean = clean.components(separatedBy: " as ")[0]
        clean = clean.components(separatedBy: ".where(")[0]
        return clean.trimmingCharacters(in: .whitespaces)
    }
    return nil
}

/// Returns the Swift function body for a given FamilyMemberHistory param.
func familyMemberHistoryHandler(spec: ParamSpec, expr: String) -> String? {
    let code = spec.code
    let fn = "extract_FamilyMemberHistory_\(code.replacingOccurrences(of: "-", with: "_"))"
    let header = "// \(code) [\(spec.type)] — \(expr)"

    switch code {

    // ── token: status (REQUIRED) ──────────────────────────────────────────────
    case "status":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ fmh: FamilyMemberHistory) {
            if let v = fmh.status.value?.rawValue {
                p.tokens.append(.init(paramName: "\(code)",
                                      system: "http://hl7.org/fhir/history-status", code: v))
            }
        }
        """

    // ── token: relationship (REQUIRED CodeableConcept) ────────────────────────
    case "relationship":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ fmh: FamilyMemberHistory) {
            for coding in fmh.relationship.coding ?? [] {
                let v = coding.code?.value?.string ?? ""
                let s = coding.system?.value?.url.absoluteString
                p.tokens.append(.init(paramName: "\(code)", system: s, code: v))
            }
        }
        """

    // ── token: sex ────────────────────────────────────────────────────────────
    case "sex":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ fmh: FamilyMemberHistory) {
            for coding in fmh.sex?.coding ?? [] {
                let v = coding.code?.value?.string ?? ""
                let s = coding.system?.value?.url.absoluteString
                p.tokens.append(.init(paramName: "\(code)", system: s, code: v))
            }
        }
        """

    // ── token: code (condition[].code) ────────────────────────────────────────
    case "code":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ fmh: FamilyMemberHistory) {
            for condition in fmh.condition ?? [] {
                for coding in condition.code.coding ?? [] {
                    let v = coding.code?.value?.string ?? ""
                    let s = coding.system?.value?.url.absoluteString
                    p.tokens.append(.init(paramName: "\(code)", system: s, code: v))
                }
            }
        }
        """

    // ── token: identifier ─────────────────────────────────────────────────────
    case "identifier":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ fmh: FamilyMemberHistory) {
            for ident in fmh.identifier ?? [] {
                let v = ident.value?.value?.string ?? ""
                let s = ident.system?.value?.url.absoluteString
                p.tokens.append(.init(paramName: "\(code)", system: s, code: v))
            }
        }
        """

    // ── reference: patient (REQUIRED) ────────────────────────────────────────
    case "patient":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ fmh: FamilyMemberHistory) {
            guard let refStr = fmh.patient.reference?.value?.string else { return }
            let parts = refStr.split(separator: "/")
            let (refType, refId): (String?, String) = parts.count == 2
                ? (String(parts[0]), String(parts[1]))
                : (nil, refStr)
            p.references.append(.init(paramName: "\(code)", refType: refType, refId: refId))
        }
        """

    // ── date: date (when history was recorded) ────────────────────────────────
    case "date":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ fmh: FamilyMemberHistory) {
            guard let prim = fmh.date, let dt = prim.value else { return }
            var dc = DateComponents()
            dc.year = dt.date.year; dc.month = dt.date.month.map(Int.init)
            dc.day  = dt.date.day.map(Int.init); dc.hour = 12
            dc.timeZone = dt.timeZone
            let d = Calendar(identifier: .gregorian).date(from: dc) ?? Date()
            p.dates.append(.init(paramName: "\(code)", dateStart: d, dateEnd: d))
        }
        """

    // ── string: instantiates-canonical (canonical URL array → idx_string) ───────
    case "instantiates-canonical":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ fmh: FamilyMemberHistory) {
            for ic in fmh.instantiatesCanonical ?? [] {
                guard let url = ic.value?.url.absoluteString else { continue }
                p.strings.append(.init(paramName: "instantiates-canonical", value: url))
            }
        }
        """

    // ── string: instantiates-uri (URI array → idx_string) ───────────────────────
    case "instantiates-uri":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ fmh: FamilyMemberHistory) {
            for iu in fmh.instantiatesUri ?? [] {
                guard let url = iu.value?.url.absoluteString else { continue }
                p.strings.append(.init(paramName: "instantiates-uri", value: url))
            }
        }
        """

    default:
        return nil
    }
}
