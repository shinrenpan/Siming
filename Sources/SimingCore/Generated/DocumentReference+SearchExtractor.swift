// GENERATED — do not edit directly.
// Source: Resources/fhir/search-parameters-r4.json
// Regenerate: swift run SimingGenerator

import Foundation
import ModelsR4

/// Extracts all supported search parameters from a DocumentReference for insertion
/// into the five idx_* index tables.
///
/// Params marked TODO are recognised by the FHIR R4 spec but not yet implemented.
public func extractDocumentReferenceSearchParams(_ d: DocumentReference) -> SearchParams {
    var p = SearchParams()
    extract_DocumentReference_authenticator(&p, d)
    extract_DocumentReference_author(&p, d)
    extract_DocumentReference_category(&p, d)
    extract_DocumentReference_contenttype(&p, d)
    extract_DocumentReference_custodian(&p, d)
    extract_DocumentReference_date(&p, d)
    extract_DocumentReference_description(&p, d)
    extract_DocumentReference_encounter(&p, d)
    extract_DocumentReference_event(&p, d)
    extract_DocumentReference_facility(&p, d)
    extract_DocumentReference_format(&p, d)
    extract_DocumentReference_identifier(&p, d)
    extract_DocumentReference_language(&p, d)
    extract_DocumentReference_location(&p, d)
    extract_DocumentReference_patient(&p, d)
    extract_DocumentReference_period(&p, d)
    extract_DocumentReference_related(&p, d)
    extract_DocumentReference_relatesto(&p, d)
    extract_DocumentReference_relation(&p, d)
    extract_DocumentReference_relationship(&p, d)
    extract_DocumentReference_security_label(&p, d)
    extract_DocumentReference_setting(&p, d)
    extract_DocumentReference_status(&p, d)
    extract_DocumentReference_subject(&p, d)
    extract_DocumentReference_type(&p, d)
    return p
}

// authenticator [reference] — DocumentReference.authenticator
private func extract_DocumentReference_authenticator(_ p: inout SearchParams, _ d: DocumentReference) {
    guard let refStr = d.authenticator?.reference?.value?.string else { return }
    let parts = refStr.split(separator: "/")
    let (refType, refId): (String?, String) = parts.count == 2
        ? (String(parts[0]), String(parts[1]))
        : (nil, refStr)
    p.references.append(.init(paramName: "authenticator", refType: refType, refId: refId))
}

// author [reference] — DocumentReference.author
private func extract_DocumentReference_author(_ p: inout SearchParams, _ d: DocumentReference) {
    for ref in d.author ?? [] {
        guard let refStr = ref.reference?.value?.string else { continue }
        let parts = refStr.split(separator: "/")
        let (refType, refId): (String?, String) = parts.count == 2
            ? (String(parts[0]), String(parts[1]))
            : (nil, refStr)
        p.references.append(.init(paramName: "author", refType: refType, refId: refId))
    }
}

// category [token] — DocumentReference.category
private func extract_DocumentReference_category(_ p: inout SearchParams, _ d: DocumentReference) {
    for cc in d.category ?? [] {
        for coding in cc.coding ?? [] {
            let c = coding.code?.value?.string ?? ""
            let sys = coding.system?.value?.url.absoluteString
            p.tokens.append(.init(paramName: "category", system: sys, code: c))
        }
    }
}

// contenttype [token] — DocumentReference.content.attachment.contentType
private func extract_DocumentReference_contenttype(_ p: inout SearchParams, _ d: DocumentReference) {
    for item in d.content {
        guard let v = item.attachment.contentType?.value?.string, !v.isEmpty else { continue }
        p.tokens.append(.init(paramName: "contenttype", system: nil, code: v))
    }
}

// custodian [reference] — DocumentReference.custodian
private func extract_DocumentReference_custodian(_ p: inout SearchParams, _ d: DocumentReference) {
    guard let refStr = d.custodian?.reference?.value?.string else { return }
    let parts = refStr.split(separator: "/")
    let (refType, refId): (String?, String) = parts.count == 2
        ? (String(parts[0]), String(parts[1]))
        : (nil, refStr)
    p.references.append(.init(paramName: "custodian", refType: refType, refId: refId))
}

// date [date] — DocumentReference.date
private func extract_DocumentReference_date(_ p: inout SearchParams, _ d: DocumentReference) {
    guard let prim = d.date, let inst = prim.value else { return }
    var dc = DateComponents()
    dc.year = inst.date.year; dc.month = Int(inst.date.month)
    dc.day  = Int(inst.date.day); dc.hour = 12
    dc.timeZone = inst.timeZone
    let date = Calendar(identifier: .gregorian).date(from: dc) ?? Date()
    p.dates.append(.init(paramName: "date", dateStart: date, dateEnd: date))
}

// description [string] — DocumentReference.description
private func extract_DocumentReference_description(_ p: inout SearchParams, _ d: DocumentReference) {
    if let v = d.description_fhir?.value?.string {
        p.strings.append(.init(paramName: "description", value: v))
    }
}

// encounter [reference] — DocumentReference.context.encounter
private func extract_DocumentReference_encounter(_ p: inout SearchParams, _ d: DocumentReference) {
    for ref in d.context?.encounter ?? [] {
        guard let refStr = ref.reference?.value?.string else { continue }
        let parts = refStr.split(separator: "/")
        let (refType, refId): (String?, String) = parts.count == 2
            ? (String(parts[0]), String(parts[1]))
            : (nil, refStr)
        p.references.append(.init(paramName: "encounter", refType: refType, refId: refId))
    }
}

// event [token] — DocumentReference.context.event
private func extract_DocumentReference_event(_ p: inout SearchParams, _ d: DocumentReference) {
    for cc in d.context?.event ?? [] {
        for coding in cc.coding ?? [] {
            let c = coding.code?.value?.string ?? ""
            let sys = coding.system?.value?.url.absoluteString
            p.tokens.append(.init(paramName: "event", system: sys, code: c))
        }
    }
}

// facility [token] — DocumentReference.context.facilityType
private func extract_DocumentReference_facility(_ p: inout SearchParams, _ d: DocumentReference) {
    for coding in d.context?.facilityType?.coding ?? [] {
        let c = coding.code?.value?.string ?? ""
        let sys = coding.system?.value?.url.absoluteString
        p.tokens.append(.init(paramName: "facility", system: sys, code: c))
    }
}

// format [token] — DocumentReference.content.format
private func extract_DocumentReference_format(_ p: inout SearchParams, _ d: DocumentReference) {
    for item in d.content {
        guard let coding = item.format else { continue }
        let c = coding.code?.value?.string ?? ""
        let sys = coding.system?.value?.url.absoluteString
        p.tokens.append(.init(paramName: "format", system: sys, code: c))
    }
}

// identifier [token] — DocumentReference.masterIdentifier
private func extract_DocumentReference_identifier(_ p: inout SearchParams, _ d: DocumentReference) {
    if let mi = d.masterIdentifier {
        let v = mi.value?.value?.string ?? ""
        let sys = mi.system?.value?.url.absoluteString
        p.tokens.append(.init(paramName: "identifier", system: sys, code: v))
    }
    for ident in d.identifier ?? [] {
        let v = ident.value?.value?.string ?? ""
        let sys = ident.system?.value?.url.absoluteString
        p.tokens.append(.init(paramName: "identifier", system: sys, code: v))
    }
}

// language [token] — DocumentReference.content.attachment.language
private func extract_DocumentReference_language(_ p: inout SearchParams, _ d: DocumentReference) {
    for item in d.content {
        guard let v = item.attachment.language?.value?.string, !v.isEmpty else { continue }
        p.tokens.append(.init(paramName: "language", system: nil, code: v))
    }
}

// TODO: unhandled — location [uri] DocumentReference.content.attachment.url
private func extract_DocumentReference_location(_ p: inout SearchParams, _ d: DocumentReference) {}

// patient [reference] — DocumentReference.subject
private func extract_DocumentReference_patient(_ p: inout SearchParams, _ d: DocumentReference) {
    guard let refStr = d.subject?.reference?.value?.string else { return }
    let parts = refStr.split(separator: "/")
    let (refType, refId): (String?, String) = parts.count == 2
        ? (String(parts[0]), String(parts[1]))
        : (nil, refStr)
    p.references.append(.init(paramName: "patient", refType: refType, refId: refId))
}

// period [date] — DocumentReference.context.period
private func extract_DocumentReference_period(_ p: inout SearchParams, _ d: DocumentReference) {
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
    p.dates.append(.init(paramName: "period", dateStart: start, dateEnd: end))
}

// related [reference] — DocumentReference.context.related
private func extract_DocumentReference_related(_ p: inout SearchParams, _ d: DocumentReference) {
    for ref in d.context?.related ?? [] {
        guard let refStr = ref.reference?.value?.string else { continue }
        let parts = refStr.split(separator: "/")
        let (refType, refId): (String?, String) = parts.count == 2
            ? (String(parts[0]), String(parts[1]))
            : (nil, refStr)
        p.references.append(.init(paramName: "related", refType: refType, refId: refId))
    }
}

// relatesto [reference] — DocumentReference.relatesTo.target
private func extract_DocumentReference_relatesto(_ p: inout SearchParams, _ d: DocumentReference) {
    for rel in d.relatesTo ?? [] {
        guard let refStr = rel.target.reference?.value?.string else { continue }
        let parts = refStr.split(separator: "/")
        let (refType, refId): (String?, String) = parts.count == 2
            ? (String(parts[0]), String(parts[1]))
            : (nil, refStr)
        p.references.append(.init(paramName: "relatesto", refType: refType, refId: refId))
    }
}

// relation [token] — DocumentReference.relatesTo.code
private func extract_DocumentReference_relation(_ p: inout SearchParams, _ d: DocumentReference) {
    for rel in d.relatesTo ?? [] {
        if let v = rel.code.value?.rawValue {
            p.tokens.append(.init(paramName: "relation",
                                  system: "http://hl7.org/fhir/document-relationship-type", code: v))
        }
    }
}

// TODO: unhandled — relationship [composite] DocumentReference.relatesTo
private func extract_DocumentReference_relationship(_ p: inout SearchParams, _ d: DocumentReference) {}

// security-label [token] — DocumentReference.securityLabel
private func extract_DocumentReference_security_label(_ p: inout SearchParams, _ d: DocumentReference) {
    for cc in d.securityLabel ?? [] {
        for coding in cc.coding ?? [] {
            let c = coding.code?.value?.string ?? ""
            let sys = coding.system?.value?.url.absoluteString
            p.tokens.append(.init(paramName: "security-label", system: sys, code: c))
        }
    }
}

// setting [token] — DocumentReference.context.practiceSetting
private func extract_DocumentReference_setting(_ p: inout SearchParams, _ d: DocumentReference) {
    for coding in d.context?.practiceSetting?.coding ?? [] {
        let c = coding.code?.value?.string ?? ""
        let sys = coding.system?.value?.url.absoluteString
        p.tokens.append(.init(paramName: "setting", system: sys, code: c))
    }
}

// status [token] — DocumentReference.status
private func extract_DocumentReference_status(_ p: inout SearchParams, _ d: DocumentReference) {
    if let v = d.status.value?.rawValue {
        p.tokens.append(.init(paramName: "status",
                              system: "http://hl7.org/fhir/document-reference-status", code: v))
    }
}

// subject [reference] — DocumentReference.subject
private func extract_DocumentReference_subject(_ p: inout SearchParams, _ d: DocumentReference) {
    guard let refStr = d.subject?.reference?.value?.string else { return }
    let parts = refStr.split(separator: "/")
    let (refType, refId): (String?, String) = parts.count == 2
        ? (String(parts[0]), String(parts[1]))
        : (nil, refStr)
    p.references.append(.init(paramName: "subject", refType: refType, refId: refId))
}

// type [token] — DocumentReference.type
private func extract_DocumentReference_type(_ p: inout SearchParams, _ d: DocumentReference) {
    for coding in d.type?.coding ?? [] {
        let c = coding.code?.value?.string ?? ""
        let sys = coding.system?.value?.url.absoluteString
        p.tokens.append(.init(paramName: "type", system: sys, code: c))
    }
}