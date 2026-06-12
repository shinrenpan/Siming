// GENERATED — do not edit directly.
// Source: packages/*.tgz (hl7.fhir.r4.core + tw.gov.mohw.twcore)
// Regenerate: swift run SimingGenerator

import Foundation
import ModelsR4

/// Extracts all supported search parameters from a Procedure for insertion
/// into the five idx_* index tables.
///
/// Params marked TODO are recognised by the FHIR R4 spec but not yet implemented.
public func extractProcedureSearchParams(_ proc: Procedure) -> SearchParams {
    var p = SearchParams()
    extract_Procedure_based_on(&p, proc)
    extract_Procedure_category(&p, proc)
    extract_Procedure_code(&p, proc)
    extract_Procedure_date(&p, proc)
    extract_Procedure_encounter(&p, proc)
    extract_Procedure_identifier(&p, proc)
    extract_Procedure_instantiates_canonical(&p, proc)
    extract_Procedure_instantiates_uri(&p, proc)
    extract_Procedure_location(&p, proc)
    extract_Procedure_part_of(&p, proc)
    extract_Procedure_patient(&p, proc)
    extract_Procedure_performer(&p, proc)
    extract_Procedure_reason_code(&p, proc)
    extract_Procedure_reason_reference(&p, proc)
    extract_Procedure_status(&p, proc)
    extract_Procedure_subject(&p, proc)
    return p
}

// based-on [reference] — Procedure.basedOn
private func extract_Procedure_based_on(_ p: inout SearchParams, _ proc: Procedure) {
    for ref in proc.basedOn ?? [] {
        guard let refStr = ref.reference?.value?.string else { continue }
        let parts = refStr.split(separator: "/")
        let (refType, refId): (String?, String) = parts.count == 2
            ? (String(parts[0]), String(parts[1]))
            : (nil, refStr)
        p.references.append(.init(paramName: "based-on", refType: refType, refId: refId))
    }
}

// category [token] — Procedure.category
private func extract_Procedure_category(_ p: inout SearchParams, _ proc: Procedure) {
    for coding in proc.category?.coding ?? [] {
        let c = coding.code?.value?.string ?? ""
        let s = coding.system?.value?.url.absoluteString
        p.appendToken(paramName: "category", system: s, code: c, display: coding.display?.value?.string)
    }
}

// code [token] — Procedure.code
private func extract_Procedure_code(_ p: inout SearchParams, _ proc: Procedure) {
    for coding in proc.code?.coding ?? [] {
        let c = coding.code?.value?.string ?? ""
        let s = coding.system?.value?.url.absoluteString
        p.appendToken(paramName: "code", system: s, code: c, display: coding.display?.value?.string)
    }
}

// date [date] — Procedure.performed
private func extract_Procedure_date(_ p: inout SearchParams, _ proc: Procedure) {
    let cal = Calendar(identifier: .gregorian)
    guard let performed = proc.performed else { return }
    switch performed {
    case .dateTime(let prim):
        guard let dt = prim.value else { return }
        var dc = DateComponents()
        dc.year = dt.date.year; dc.month = dt.date.month.map(Int.init)
        dc.day  = dt.date.day.map(Int.init); dc.hour = 12
        dc.timeZone = dt.timeZone
        let d = cal.date(from: dc) ?? Date()
        p.dates.append(.init(paramName: "date", dateStart: d, dateEnd: d))
    case .period(let period):
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
        p.dates.append(.init(paramName: "date", dateStart: start, dateEnd: end))
    @unknown default:
        break
    }
}

// encounter [reference] — Procedure.encounter
private func extract_Procedure_encounter(_ p: inout SearchParams, _ proc: Procedure) {
    guard let refStr = proc.encounter?.reference?.value?.string else { return }
    let parts = refStr.split(separator: "/")
    let (refType, refId): (String?, String) = parts.count == 2
        ? (String(parts[0]), String(parts[1]))
        : (nil, refStr)
    p.references.append(.init(paramName: "encounter", refType: refType, refId: refId))
}

// identifier [token] — Procedure.identifier
private func extract_Procedure_identifier(_ p: inout SearchParams, _ proc: Procedure) {
    for ident in proc.identifier ?? [] {
        let v = ident.value?.value?.string ?? ""
        let s = ident.system?.value?.url.absoluteString
        p.tokens.append(.init(paramName: "identifier", system: s, code: v))
    }
}

// instantiates-canonical [reference] — Procedure.instantiatesCanonical
private func extract_Procedure_instantiates_canonical(_ p: inout SearchParams, _ proc: Procedure) {
    for ic in proc.instantiatesCanonical ?? [] {
        guard let url = ic.value?.url.absoluteString else { continue }
        p.strings.append(.init(paramName: "instantiates-canonical", value: url))
    }
}

// instantiates-uri [uri] — Procedure.instantiatesUri
private func extract_Procedure_instantiates_uri(_ p: inout SearchParams, _ proc: Procedure) {
    for iu in proc.instantiatesUri ?? [] {
        guard let url = iu.value?.url.absoluteString else { continue }
        p.strings.append(.init(paramName: "instantiates-uri", value: url))
    }
}

// location [reference] — Procedure.location
private func extract_Procedure_location(_ p: inout SearchParams, _ proc: Procedure) {
    guard let refStr = proc.location?.reference?.value?.string else { return }
    let parts = refStr.split(separator: "/")
    let (refType, refId): (String?, String) = parts.count == 2
        ? (String(parts[0]), String(parts[1]))
        : (nil, refStr)
    p.references.append(.init(paramName: "location", refType: refType, refId: refId))
}

// part-of [reference] — Procedure.partOf
private func extract_Procedure_part_of(_ p: inout SearchParams, _ proc: Procedure) {
    for ref in proc.partOf ?? [] {
        guard let refStr = ref.reference?.value?.string else { continue }
        let parts = refStr.split(separator: "/")
        let (refType, refId): (String?, String) = parts.count == 2
            ? (String(parts[0]), String(parts[1]))
            : (nil, refStr)
        p.references.append(.init(paramName: "part-of", refType: refType, refId: refId))
    }
}

// patient [reference] — Procedure.subject
private func extract_Procedure_patient(_ p: inout SearchParams, _ proc: Procedure) {
    guard let refStr = proc.subject.reference?.value?.string else { return }
    let parts = refStr.split(separator: "/")
    let (refType, refId): (String?, String) = parts.count == 2
        ? (String(parts[0]), String(parts[1]))
        : (nil, refStr)
    p.references.append(.init(paramName: "patient", refType: refType, refId: refId))
}

// performer [reference] — Procedure.performer.actor
private func extract_Procedure_performer(_ p: inout SearchParams, _ proc: Procedure) {
    for perf in proc.performer ?? [] {
        guard let refStr = perf.actor.reference?.value?.string else { continue }
        let parts = refStr.split(separator: "/")
        let (refType, refId): (String?, String) = parts.count == 2
            ? (String(parts[0]), String(parts[1]))
            : (nil, refStr)
        p.references.append(.init(paramName: "performer", refType: refType, refId: refId))
    }
}

// reason-code [token] — Procedure.reasonCode
private func extract_Procedure_reason_code(_ p: inout SearchParams, _ proc: Procedure) {
    for cc in proc.reasonCode ?? [] {
        for coding in cc.coding ?? [] {
            let c = coding.code?.value?.string ?? ""
            let s = coding.system?.value?.url.absoluteString
            p.appendToken(paramName: "reason-code", system: s, code: c, display: coding.display?.value?.string)
        }
    }
}

// reason-reference [reference] — Procedure.reasonReference
private func extract_Procedure_reason_reference(_ p: inout SearchParams, _ proc: Procedure) {
    for ref in proc.reasonReference ?? [] {
        guard let refStr = ref.reference?.value?.string else { continue }
        let parts = refStr.split(separator: "/")
        let (refType, refId): (String?, String) = parts.count == 2
            ? (String(parts[0]), String(parts[1]))
            : (nil, refStr)
        p.references.append(.init(paramName: "reason-reference", refType: refType, refId: refId))
    }
}

// status [token] — Procedure.status
private func extract_Procedure_status(_ p: inout SearchParams, _ proc: Procedure) {
    if let v = proc.status.value?.rawValue {
        p.tokens.append(.init(paramName: "status",
                              system: "http://hl7.org/fhir/event-status", code: v))
    }
}

// subject [reference] — Procedure.subject
private func extract_Procedure_subject(_ p: inout SearchParams, _ proc: Procedure) {
    guard let refStr = proc.subject.reference?.value?.string else { return }
    let parts = refStr.split(separator: "/")
    let (refType, refId): (String?, String) = parts.count == 2
        ? (String(parts[0]), String(parts[1]))
        : (nil, refStr)
    p.references.append(.init(paramName: "subject", refType: refType, refId: refId))
}