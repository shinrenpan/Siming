import Foundation

/// Extracts the `DocumentReference.xxx` part from a multi-resource FHIRPath expression.
func documentReferenceExpr(from expression: String) -> String? {
    for part in expression.components(separatedBy: " | ") {
        var clean = part.trimmingCharacters(in: .whitespaces)
        if clean.hasPrefix("(") { clean = String(clean.dropFirst()) }
        guard clean.hasPrefix("DocumentReference.") else { continue }
        clean = clean.components(separatedBy: " as ")[0]
        clean = clean.components(separatedBy: ".where(")[0]
        return clean.trimmingCharacters(in: .whitespaces)
    }
    return nil
}

/// Returns the Swift function body for a given DocumentReference param.
func documentReferenceHandler(spec: ParamSpec, expr: String) -> String? {
    let code = spec.code
    let fn = "extract_DocumentReference_\(code.replacingOccurrences(of: "-", with: "_"))"
    let header = "// \(code) [\(spec.type)] — \(expr)"

    switch code {

    // ── token: status (REQUIRED field) ───────────────────────────────────────
    case "status":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ d: DocumentReference) {
            if let v = d.status.value?.rawValue {
                p.tokens.append(.init(paramName: "\(code)",
                                      system: "http://hl7.org/fhir/document-reference-status", code: v))
            }
        }
        """

    // ── token: type ───────────────────────────────────────────────────────────
    case "type":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ d: DocumentReference) {
            for coding in d.type?.coding ?? [] {
                let c = coding.code?.value?.string ?? ""
                let sys = coding.system?.value?.url.absoluteString
                p.tokens.append(.init(paramName: "\(code)", system: sys, code: c))
            }
        }
        """

    // ── token: category ───────────────────────────────────────────────────────
    case "category":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ d: DocumentReference) {
            for cc in d.category ?? [] {
                for coding in cc.coding ?? [] {
                    let c = coding.code?.value?.string ?? ""
                    let sys = coding.system?.value?.url.absoluteString
                    p.tokens.append(.init(paramName: "\(code)", system: sys, code: c))
                }
            }
        }
        """

    // ── token: identifier (masterIdentifier + identifier) ────────────────────
    case "identifier":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ d: DocumentReference) {
            if let mi = d.masterIdentifier {
                let v = mi.value?.value?.string ?? ""
                let sys = mi.system?.value?.url.absoluteString
                p.tokens.append(.init(paramName: "\(code)", system: sys, code: v))
            }
            for ident in d.identifier ?? [] {
                let v = ident.value?.value?.string ?? ""
                let sys = ident.system?.value?.url.absoluteString
                p.tokens.append(.init(paramName: "\(code)", system: sys, code: v))
            }
        }
        """

    // ── token: security-label ─────────────────────────────────────────────────
    case "security-label":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ d: DocumentReference) {
            for cc in d.securityLabel ?? [] {
                for coding in cc.coding ?? [] {
                    let c = coding.code?.value?.string ?? ""
                    let sys = coding.system?.value?.url.absoluteString
                    p.tokens.append(.init(paramName: "\(code)", system: sys, code: c))
                }
            }
        }
        """

    // ── token: facility (context.facilityType) ────────────────────────────────
    case "facility":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ d: DocumentReference) {
            for coding in d.context?.facilityType?.coding ?? [] {
                let c = coding.code?.value?.string ?? ""
                let sys = coding.system?.value?.url.absoluteString
                p.tokens.append(.init(paramName: "\(code)", system: sys, code: c))
            }
        }
        """

    // ── token: event (context.event) ─────────────────────────────────────────
    case "event":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ d: DocumentReference) {
            for cc in d.context?.event ?? [] {
                for coding in cc.coding ?? [] {
                    let c = coding.code?.value?.string ?? ""
                    let sys = coding.system?.value?.url.absoluteString
                    p.tokens.append(.init(paramName: "\(code)", system: sys, code: c))
                }
            }
        }
        """

    // ── date: date (Instant type) ─────────────────────────────────────────────
    case "date":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ d: DocumentReference) {
            guard let prim = d.date, let inst = prim.value else { return }
            var dc = DateComponents()
            dc.year = inst.date.year; dc.month = Int(inst.date.month)
            dc.day  = Int(inst.date.day); dc.hour = 12
            dc.timeZone = inst.timeZone
            let date = Calendar(identifier: .gregorian).date(from: dc) ?? Date()
            p.dates.append(.init(paramName: "\(code)", dateStart: date, dateEnd: date))
        }
        """

    // ── date: period (context.period — a Period, not a choice type) ───────────
    case "period":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ d: DocumentReference) {
            guard let period = d.context?.period else { return }
            let cal = Calendar(identifier: .gregorian)
            let start: Date
            let end: Date
            if let prim = period.start, let dt = prim.value {
                var dc = DateComponents()
                dc.year = dt.date.year; dc.month = dt.date.month.map(Int.init)
                dc.day  = dt.date.day.map(Int.init); dc.hour = 0
                start = cal.date(from: dc) ?? Date.distantPast
            } else { start = Date.distantPast }
            if let prim = period.end, let dt = prim.value {
                var dc = DateComponents()
                dc.year = dt.date.year; dc.month = dt.date.month.map(Int.init)
                dc.day  = dt.date.day.map(Int.init); dc.hour = 23; dc.minute = 59
                end = cal.date(from: dc) ?? Date.distantFuture
            } else { end = Date.distantFuture }
            p.dates.append(.init(paramName: "\(code)", dateStart: start, dateEnd: end))
        }
        """

    // ── string: description ───────────────────────────────────────────────────
    case "description":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ d: DocumentReference) {
            if let v = d.description_fhir?.value?.string {
                p.strings.append(.init(paramName: "\(code)", value: v))
            }
        }
        """

    // ── reference: subject ────────────────────────────────────────────────────
    case "subject":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ d: DocumentReference) {
            guard let refStr = d.subject?.reference?.value?.string else { return }
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
        private func \(fn)(_ p: inout SearchParams, _ d: DocumentReference) {
            guard let refStr = d.subject?.reference?.value?.string else { return }
            let parts = refStr.split(separator: "/")
            let (refType, refId): (String?, String) = parts.count == 2
                ? (String(parts[0]), String(parts[1]))
                : (nil, refStr)
            p.references.append(.init(paramName: "\(code)", refType: refType, refId: refId))
        }
        """

    // ── reference: author (array) ─────────────────────────────────────────────
    case "author":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ d: DocumentReference) {
            for ref in d.author ?? [] {
                guard let refStr = ref.reference?.value?.string else { continue }
                let parts = refStr.split(separator: "/")
                let (refType, refId): (String?, String) = parts.count == 2
                    ? (String(parts[0]), String(parts[1]))
                    : (nil, refStr)
                p.references.append(.init(paramName: "\(code)", refType: refType, refId: refId))
            }
        }
        """

    // ── reference: encounter (context.encounter — array) ─────────────────────
    case "encounter":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ d: DocumentReference) {
            for ref in d.context?.encounter ?? [] {
                guard let refStr = ref.reference?.value?.string else { continue }
                let parts = refStr.split(separator: "/")
                let (refType, refId): (String?, String) = parts.count == 2
                    ? (String(parts[0]), String(parts[1]))
                    : (nil, refStr)
                p.references.append(.init(paramName: "\(code)", refType: refType, refId: refId))
            }
        }
        """

    // ── reference: authenticator ─────────────────────────────────────────────
    case "authenticator":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ d: DocumentReference) {
            guard let refStr = d.authenticator?.reference?.value?.string else { return }
            let parts = refStr.split(separator: "/")
            let (refType, refId): (String?, String) = parts.count == 2
                ? (String(parts[0]), String(parts[1]))
                : (nil, refStr)
            p.references.append(.init(paramName: "\(code)", refType: refType, refId: refId))
        }
        """

    // ── token: contenttype (content[*].attachment.contentType) ───────────────
    case "contenttype":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ d: DocumentReference) {
            for item in d.content {
                guard let v = item.attachment.contentType?.value?.string, !v.isEmpty else { continue }
                p.tokens.append(.init(paramName: "\(code)", system: nil, code: v))
            }
        }
        """

    // ── token: format (content[*].format — Coding) ───────────────────────────
    case "format":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ d: DocumentReference) {
            for item in d.content {
                guard let coding = item.format else { continue }
                let c = coding.code?.value?.string ?? ""
                let sys = coding.system?.value?.url.absoluteString
                p.tokens.append(.init(paramName: "\(code)", system: sys, code: c))
            }
        }
        """

    // ── token: language (content[*].attachment.language) ─────────────────────
    case "language":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ d: DocumentReference) {
            for item in d.content {
                guard let v = item.attachment.language?.value?.string, !v.isEmpty else { continue }
                p.tokens.append(.init(paramName: "\(code)", system: nil, code: v))
            }
        }
        """

    // ── composite: relationship (relatesTo[]: relation code + target ref) ──────
    // Stores per-entry (relation_code, target_ref) tuples into idx_composite so
    // that tuple matching is exact — avoids false positives when a document has
    // multiple relatesTo entries with different codes and targets.
    case "relationship":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ d: DocumentReference) {
            for rel in d.relatesTo ?? [] {
                guard let relCode = rel.code.value?.rawValue,
                      let refStr  = rel.target.reference?.value?.string else { continue }
                p.composites.append(.init(paramName: "relationship",
                    code1System: "http://hl7.org/fhir/document-relationship-type",
                    code1Code: relCode, string2: refStr))
            }
        }
        """

    // ── reference: relatesto (relatesTo[].target) ────────────────────────────
    case "relatesto":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ d: DocumentReference) {
            for rel in d.relatesTo ?? [] {
                guard let refStr = rel.target.reference?.value?.string else { continue }
                let parts = refStr.split(separator: "/")
                let (refType, refId): (String?, String) = parts.count == 2
                    ? (String(parts[0]), String(parts[1]))
                    : (nil, refStr)
                p.references.append(.init(paramName: "relatesto", refType: refType, refId: refId))
            }
        }
        """

    // ── token: relation (relatesTo[].code) ───────────────────────────────────
    case "relation":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ d: DocumentReference) {
            for rel in d.relatesTo ?? [] {
                if let v = rel.code.value?.rawValue {
                    p.tokens.append(.init(paramName: "relation",
                                          system: "http://hl7.org/fhir/document-relationship-type", code: v))
                }
            }
        }
        """

    // ── reference: related (context.related[]) ────────────────────────────────
    case "related":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ d: DocumentReference) {
            for ref in d.context?.related ?? [] {
                guard let refStr = ref.reference?.value?.string else { continue }
                let parts = refStr.split(separator: "/")
                let (refType, refId): (String?, String) = parts.count == 2
                    ? (String(parts[0]), String(parts[1]))
                    : (nil, refStr)
                p.references.append(.init(paramName: "related", refType: refType, refId: refId))
            }
        }
        """

    // ── string: location (content[*].attachment.url — uri type) ─────────────
    case "location":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ d: DocumentReference) {
            for item in d.content {
                guard let url = item.attachment.url?.value?.url.absoluteString, !url.isEmpty else { continue }
                p.strings.append(.init(paramName: "location", value: url))
            }
        }
        """

    // ── reference: custodian ──────────────────────────────────────────────────
    case "custodian":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ d: DocumentReference) {
            guard let refStr = d.custodian?.reference?.value?.string else { return }
            let parts = refStr.split(separator: "/")
            let (refType, refId): (String?, String) = parts.count == 2
                ? (String(parts[0]), String(parts[1]))
                : (nil, refStr)
            p.references.append(.init(paramName: "\(code)", refType: refType, refId: refId))
        }
        """

    // ── token: setting (context.practiceSetting) ──────────────────────────────
    case "setting":
        return """
        \(header)
        private func \(fn)(_ p: inout SearchParams, _ d: DocumentReference) {
            for coding in d.context?.practiceSetting?.coding ?? [] {
                let c = coding.code?.value?.string ?? ""
                let sys = coding.system?.value?.url.absoluteString
                p.tokens.append(.init(paramName: "\(code)", system: sys, code: c))
            }
        }
        """

    default:
        return nil
    }
}
