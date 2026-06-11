// GENERATED — do not edit directly.
// Source: packages/*.tgz (hl7.fhir.r4.core + tw.gov.mohw.twcore)
// Regenerate: swift run SimingGenerator

import Foundation
import ModelsR4

/// Extracts all supported search parameters from a DiagnosticReport for insertion
/// into the five idx_* index tables.
///
/// Params marked TODO are recognised by the FHIR R4 spec but not yet implemented.
public func extractDiagnosticReportSearchParams(_ dr: DiagnosticReport) -> SearchParams {
    var p = SearchParams()
    extract_DiagnosticReport_based_on(&p, dr)
    extract_DiagnosticReport_category(&p, dr)
    extract_DiagnosticReport_code(&p, dr)
    extract_DiagnosticReport_conclusion(&p, dr)
    extract_DiagnosticReport_date(&p, dr)
    extract_DiagnosticReport_encounter(&p, dr)
    extract_DiagnosticReport_identifier(&p, dr)
    extract_DiagnosticReport_issued(&p, dr)
    extract_DiagnosticReport_media(&p, dr)
    extract_DiagnosticReport_patient(&p, dr)
    extract_DiagnosticReport_performer(&p, dr)
    extract_DiagnosticReport_result(&p, dr)
    extract_DiagnosticReport_results_interpreter(&p, dr)
    extract_DiagnosticReport_specimen(&p, dr)
    extract_DiagnosticReport_status(&p, dr)
    extract_DiagnosticReport_subject(&p, dr)
    return p
}

// based-on [reference] — DiagnosticReport.basedOn
private func extract_DiagnosticReport_based_on(_ p: inout SearchParams, _ dr: DiagnosticReport) {
    for ref in dr.basedOn ?? [] {
        guard let refStr = ref.reference?.value?.string else { continue }
        let parts = refStr.split(separator: "/")
        let (refType, refId): (String?, String) = parts.count == 2
            ? (String(parts[0]), String(parts[1]))
            : (nil, refStr)
        p.references.append(.init(paramName: "based-on", refType: refType, refId: refId))
    }
}

// category [token] — DiagnosticReport.category
private func extract_DiagnosticReport_category(_ p: inout SearchParams, _ dr: DiagnosticReport) {
    for cc in dr.category ?? [] {
        for coding in cc.coding ?? [] {
            let c = coding.code?.value?.string ?? ""
            let s = coding.system?.value?.url.absoluteString
            p.appendToken(paramName: "category", system: s, code: c, display: coding.display?.value?.string)
        }
    }
}

// code [token] — DiagnosticReport.code
private func extract_DiagnosticReport_code(_ p: inout SearchParams, _ dr: DiagnosticReport) {
    for coding in dr.code.coding ?? [] {
        let c = coding.code?.value?.string ?? ""
        let s = coding.system?.value?.url.absoluteString
        p.appendToken(paramName: "code", system: s, code: c, display: coding.display?.value?.string)
    }
}

// conclusion [token] — DiagnosticReport.conclusionCode
private func extract_DiagnosticReport_conclusion(_ p: inout SearchParams, _ dr: DiagnosticReport) {
    for cc in dr.conclusionCode ?? [] {
        for coding in cc.coding ?? [] {
            let c = coding.code?.value?.string ?? ""
            let s = coding.system?.value?.url.absoluteString
            p.appendToken(paramName: "conclusion", system: s, code: c, display: coding.display?.value?.string)
        }
    }
}

// date [date] — DiagnosticReport.effective
private func extract_DiagnosticReport_date(_ p: inout SearchParams, _ dr: DiagnosticReport) {
    let cal = Calendar(identifier: .gregorian)
    guard let effective = dr.effective else { return }
    switch effective {
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
    }
}

// encounter [reference] — DiagnosticReport.encounter
private func extract_DiagnosticReport_encounter(_ p: inout SearchParams, _ dr: DiagnosticReport) {
    guard let refStr = dr.encounter?.reference?.value?.string else { return }
    let parts = refStr.split(separator: "/")
    let (refType, refId): (String?, String) = parts.count == 2
        ? (String(parts[0]), String(parts[1]))
        : (nil, refStr)
    p.references.append(.init(paramName: "encounter", refType: refType, refId: refId))
}

// identifier [token] — DiagnosticReport.identifier
private func extract_DiagnosticReport_identifier(_ p: inout SearchParams, _ dr: DiagnosticReport) {
    for ident in dr.identifier ?? [] {
        let v = ident.value?.value?.string ?? ""
        let s = ident.system?.value?.url.absoluteString
        p.tokens.append(.init(paramName: "identifier", system: s, code: v))
    }
}

// issued [date] — DiagnosticReport.issued
private func extract_DiagnosticReport_issued(_ p: inout SearchParams, _ dr: DiagnosticReport) {
    guard let prim = dr.issued, let inst = prim.value else { return }
    var dc = DateComponents()
    dc.year = inst.date.year; dc.month = Int(inst.date.month)
    dc.day  = Int(inst.date.day); dc.hour = 12
    dc.timeZone = inst.timeZone
    let d = Calendar(identifier: .gregorian).date(from: dc) ?? Date()
    p.dates.append(.init(paramName: "issued", dateStart: d, dateEnd: d))
}

// media [reference] — DiagnosticReport.media.link
private func extract_DiagnosticReport_media(_ p: inout SearchParams, _ dr: DiagnosticReport) {
    for m in dr.media ?? [] {
        guard let refStr = m.link.reference?.value?.string else { continue }
        let parts = refStr.split(separator: "/")
        let (refType, refId): (String?, String) = parts.count == 2
            ? (String(parts[0]), String(parts[1]))
            : (nil, refStr)
        p.references.append(.init(paramName: "media", refType: refType, refId: refId))
    }
}

// patient [reference] — DiagnosticReport.subject
private func extract_DiagnosticReport_patient(_ p: inout SearchParams, _ dr: DiagnosticReport) {
    guard let refStr = dr.subject?.reference?.value?.string else { return }
    let parts = refStr.split(separator: "/")
    let (refType, refId): (String?, String) = parts.count == 2
        ? (String(parts[0]), String(parts[1]))
        : (nil, refStr)
    p.references.append(.init(paramName: "patient", refType: refType, refId: refId))
}

// performer [reference] — DiagnosticReport.performer
private func extract_DiagnosticReport_performer(_ p: inout SearchParams, _ dr: DiagnosticReport) {
    for ref in dr.performer ?? [] {
        guard let refStr = ref.reference?.value?.string else { continue }
        let parts = refStr.split(separator: "/")
        let (refType, refId): (String?, String) = parts.count == 2
            ? (String(parts[0]), String(parts[1]))
            : (nil, refStr)
        p.references.append(.init(paramName: "performer", refType: refType, refId: refId))
    }
}

// result [reference] — DiagnosticReport.result
private func extract_DiagnosticReport_result(_ p: inout SearchParams, _ dr: DiagnosticReport) {
    for ref in dr.result ?? [] {
        guard let refStr = ref.reference?.value?.string else { continue }
        let parts = refStr.split(separator: "/")
        let (refType, refId): (String?, String) = parts.count == 2
            ? (String(parts[0]), String(parts[1]))
            : (nil, refStr)
        p.references.append(.init(paramName: "result", refType: refType, refId: refId))
    }
}

// results-interpreter [reference] — DiagnosticReport.resultsInterpreter
private func extract_DiagnosticReport_results_interpreter(_ p: inout SearchParams, _ dr: DiagnosticReport) {
    for ref in dr.resultsInterpreter ?? [] {
        guard let refStr = ref.reference?.value?.string else { continue }
        let parts = refStr.split(separator: "/")
        let (refType, refId): (String?, String) = parts.count == 2
            ? (String(parts[0]), String(parts[1]))
            : (nil, refStr)
        p.references.append(.init(paramName: "results-interpreter", refType: refType, refId: refId))
    }
}

// specimen [reference] — DiagnosticReport.specimen
private func extract_DiagnosticReport_specimen(_ p: inout SearchParams, _ dr: DiagnosticReport) {
    for ref in dr.specimen ?? [] {
        guard let refStr = ref.reference?.value?.string else { continue }
        let parts = refStr.split(separator: "/")
        let (refType, refId): (String?, String) = parts.count == 2
            ? (String(parts[0]), String(parts[1]))
            : (nil, refStr)
        p.references.append(.init(paramName: "specimen", refType: refType, refId: refId))
    }
}

// status [token] — DiagnosticReport.status
private func extract_DiagnosticReport_status(_ p: inout SearchParams, _ dr: DiagnosticReport) {
    if let v = dr.status.value?.rawValue {
        p.tokens.append(.init(paramName: "status",
                              system: "http://hl7.org/fhir/diagnostic-report-status", code: v))
    }
}

// subject [reference] — DiagnosticReport.subject
private func extract_DiagnosticReport_subject(_ p: inout SearchParams, _ dr: DiagnosticReport) {
    guard let refStr = dr.subject?.reference?.value?.string else { return }
    let parts = refStr.split(separator: "/")
    let (refType, refId): (String?, String) = parts.count == 2
        ? (String(parts[0]), String(parts[1]))
        : (nil, refStr)
    p.references.append(.init(paramName: "subject", refType: refType, refId: refId))
}