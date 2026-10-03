import Foundation

/// Extracts the `QuestionnaireResponse.xxx` part from a multi-resource FHIRPath expression.
func questionnaireResponseExpr(from expression: String) -> String? {
    for part in expression.components(separatedBy: " | ") {
        var clean = part.trimmingCharacters(in: .whitespaces)
        if clean.hasPrefix("(") { clean = String(clean.dropFirst()) }
        guard clean.hasPrefix("QuestionnaireResponse.") else { continue }
        clean = clean.components(separatedBy: " as ")[0]
        clean = clean.components(separatedBy: ".where(")[0]
        return clean.trimmingCharacters(in: .whitespaces)
    }
    return nil
}

/// Returns the Swift function body for a given QuestionnaireResponse param.
func questionnaireResponseHandler(spec: ParamSpec, expr: String) -> String? {
    let code = spec.code
    let fn = "extract_QuestionnaireResponse_\(code.replacingOccurrences(of: "-", with: "_"))"
    let header = "// \(code) [\(spec.type)] — \(expr)"

    /// Single Reference? → idx_reference.
    func singleRef(_ path: String) -> String {
        """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ q: QuestionnaireResponse) {
            guard let refStr = q.\(path)?.reference?.value?.string else { return }
            let parts = refStr.split(separator: "/")
            let (refType, refId): (String?, String) = parts.count == 2
                ? (String(parts[0]), String(parts[1]))
                : (nil, refStr)
            p.references.append(.init(paramName: "\(code)", refType: refType, refId: refId))
        }
        """
    }

    /// [Reference]? → idx_reference.
    func refArray(_ path: String) -> String {
        """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ q: QuestionnaireResponse) {
            for ref in q.\(path) ?? [] {
                guard let refStr = ref.reference?.value?.string else { continue }
                let parts = refStr.split(separator: "/")
                let (refType, refId): (String?, String) = parts.count == 2
                    ? (String(parts[0]), String(parts[1]))
                    : (nil, refStr)
                p.references.append(.init(paramName: "\(code)", refType: refType, refId: refId))
            }
        }
        """
    }

    /// FHIRPrimitive<DateTime>? → idx_date point value.
    func dateTime(_ path: String) -> String {
        """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ q: QuestionnaireResponse) {
            guard let prim = q.\(path), let dt = prim.value else { return }
            let cal = Calendar(identifier: .gregorian)
            var dc = DateComponents()
            dc.year = dt.date.year; dc.month = dt.date.month.map(Int.init)
            dc.day  = dt.date.day.map(Int.init)
            // A dateTime carrying a time keeps it; a date-only value stays anchored at
            // midday so it sits well inside the day whatever offset it is compared against.
            // The zone must be explicit — falling through to the host's zone makes the
            // stored value depend on where the server happens to run.
            dc.hour   = dt.time.map { Int($0.hour) } ?? 12
            dc.minute = dt.time.map { Int($0.minute) } ?? 0
            dc.second = dt.time.map { min(Int(truncating: $0.second as NSDecimalNumber), 59) } ?? 0
            dc.timeZone = dt.timeZone ?? TimeZone(secondsFromGMT: 0)
            let d = cal.date(from: dc) ?? Date()
            p.dates.append(.init(paramName: "\(code)", dateStart: d, dateEnd: d))
        }
        """
    }

    switch code {

    // ── token: status (required binding) ─────────────────────────────────────
    case "status":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ q: QuestionnaireResponse) {
            if let v = q.status.value?.rawValue {
                p.tokens.append(.init(paramName: "\(code)",
                                      system: "http://hl7.org/fhir/questionnaire-answers-status", code: v))
            }
        }
        """

    // ── token: identifier (single Identifier in R4) ───────────────────────────
    case "identifier":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ q: QuestionnaireResponse) {
            guard let ident = q.identifier else { return }
            let v = ident.value?.value?.string ?? ""
            let sys = ident.system?.value?.url.absoluteString
            p.tokens.append(.init(paramName: "\(code)", system: sys, code: v))
        }
        """

    // ── reference: questionnaire — a canonical, stored in idx_string ─────────
    // Same storage as every other canonical param (instantiates-canonical): exact URL
    // match on idx_string. A versioned canonical also gets its unversioned URL, so
    // `questionnaire=url` finds every version and `questionnaire=url|1.0` only that one.
    case "questionnaire":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ q: QuestionnaireResponse) {
            guard let canonical = q.questionnaire?.value else { return }
            let url = canonical.url.absoluteString
            p.strings.append(.init(paramName: "\(code)", value: url))
            if let version = canonical.version {
                p.strings.append(.init(paramName: "\(code)", value: "\\(url)|\\(version)"))
            }
        }
        """

    // ── date: authored ────────────────────────────────────────────────────────
    case "authored": return dateTime("authored")

    // ── reference: patient — subject, only when it is a Patient ──────────────
    case "patient":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ q: QuestionnaireResponse) {
            guard let refStr = q.subject?.reference?.value?.string else { return }
            let parts = refStr.split(separator: "/")
            guard parts.count == 2, parts[0] == "Patient" else { return }
            p.references.append(.init(paramName: "\(code)", refType: "Patient", refId: String(parts[1])))
        }
        """

    // ── reference: item-subject — top-level items flagged isSubject ──────────
    case "item-subject":
        return """
        // \(code) [\(spec.type)] — \(spec.expression)
        private func \(fn)(_ p: inout SearchParams, _ q: QuestionnaireResponse) {
            let isSubject = "http://hl7.org/fhir/StructureDefinition/questionnaireresponse-isSubject"
            for item in q.item ?? [] where (item.extension ?? []).contains(where: { $0.url.value?.url.absoluteString == isSubject }) {
                for answer in item.answer ?? [] {
                    guard case .reference(let ref)? = answer.value,
                          let refStr = ref.reference?.value?.string else { continue }
                    let parts = refStr.split(separator: "/")
                    let (refType, refId): (String?, String) = parts.count == 2
                        ? (String(parts[0]), String(parts[1]))
                        : (nil, refStr)
                    p.references.append(.init(paramName: "\(code)", refType: refType, refId: refId))
                }
            }
        }
        """

    case "subject":   return singleRef("subject")
    case "author":    return singleRef("author")
    case "encounter": return singleRef("encounter")
    case "source":    return singleRef("source")
    case "based-on":  return refArray("basedOn")
    case "part-of":   return refArray("partOf")

    default:
        return nil
    }
}
