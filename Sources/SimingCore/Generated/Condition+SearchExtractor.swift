// GENERATED — do not edit directly.
// Source: Resources/fhir/search-parameters-r4.json
// Regenerate: swift run SimingGenerator

import Foundation
import ModelsR4

/// Extracts all supported search parameters from a Condition for insertion
/// into the five idx_* index tables.
///
/// Params marked TODO are recognised by the FHIR R4 spec but not yet implemented.
public func extractConditionSearchParams(_ cond: Condition) -> SearchParams {
    var p = SearchParams()
    extract_Condition_abatement_age(&p, cond)
    extract_Condition_abatement_date(&p, cond)
    extract_Condition_abatement_string(&p, cond)
    extract_Condition_asserter(&p, cond)
    extract_Condition_body_site(&p, cond)
    extract_Condition_category(&p, cond)
    extract_Condition_clinical_status(&p, cond)
    extract_Condition_code(&p, cond)
    extract_Condition_encounter(&p, cond)
    extract_Condition_evidence(&p, cond)
    extract_Condition_evidence_detail(&p, cond)
    extract_Condition_identifier(&p, cond)
    extract_Condition_onset_age(&p, cond)
    extract_Condition_onset_date(&p, cond)
    extract_Condition_onset_info(&p, cond)
    extract_Condition_patient(&p, cond)
    extract_Condition_recorded_date(&p, cond)
    extract_Condition_severity(&p, cond)
    extract_Condition_stage(&p, cond)
    extract_Condition_subject(&p, cond)
    extract_Condition_verification_status(&p, cond)
    return p
}

// TODO: unhandled — abatement-age [quantity] Condition.abatement.as(Age) | Condition.abatement.as(Range)
private func extract_Condition_abatement_age(_ p: inout SearchParams, _ cond: Condition) {}

// abatement-date [date] — Condition.abatement.as(dateTime)
private func extract_Condition_abatement_date(_ p: inout SearchParams, _ cond: Condition) {
    let cal = Calendar(identifier: .gregorian)
    guard let abatement = cond.abatement else { return }
    switch abatement {
    case .dateTime(let prim):
        guard let dt = prim.value else { return }
        var dc = DateComponents()
        dc.year = dt.date.year; dc.month = dt.date.month.map(Int.init)
        dc.day  = dt.date.day.map(Int.init); dc.hour = 12
        let d = cal.date(from: dc) ?? Date()
        p.dates.append(.init(paramName: "abatement-date", dateStart: d, dateEnd: d))
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
        p.dates.append(.init(paramName: "abatement-date", dateStart: start, dateEnd: end))
    default:
        break
    }
}

// TODO: unhandled — abatement-string [string] Condition.abatement.as(string)
private func extract_Condition_abatement_string(_ p: inout SearchParams, _ cond: Condition) {}

// TODO: unhandled — asserter [reference] Condition.asserter
private func extract_Condition_asserter(_ p: inout SearchParams, _ cond: Condition) {}

// TODO: unhandled — body-site [token] Condition.bodySite
private func extract_Condition_body_site(_ p: inout SearchParams, _ cond: Condition) {}

// category [token] — Condition.category
private func extract_Condition_category(_ p: inout SearchParams, _ cond: Condition) {
    for cc in cond.category ?? [] {
        for coding in cc.coding ?? [] {
            let c = coding.code?.value?.string ?? ""
            let s = coding.system?.value?.url.absoluteString
            p.tokens.append(.init(paramName: "category", system: s, code: c))
        }
    }
}

// clinical-status [token] — Condition.clinicalStatus
private func extract_Condition_clinical_status(_ p: inout SearchParams, _ cond: Condition) {
    for coding in cond.clinicalStatus?.coding ?? [] {
        let c = coding.code?.value?.string ?? ""
        let s = coding.system?.value?.url.absoluteString
        p.tokens.append(.init(paramName: "clinical-status", system: s, code: c))
    }
}

// code [token] — Condition.code
private func extract_Condition_code(_ p: inout SearchParams, _ cond: Condition) {
    for coding in cond.code?.coding ?? [] {
        let c = coding.code?.value?.string ?? ""
        let s = coding.system?.value?.url.absoluteString
        p.tokens.append(.init(paramName: "code", system: s, code: c))
    }
}

// encounter [reference] — Condition.encounter
private func extract_Condition_encounter(_ p: inout SearchParams, _ cond: Condition) {
    guard let refStr = cond.encounter?.reference?.value?.string else { return }
    let parts = refStr.split(separator: "/")
    let (refType, refId): (String?, String) = parts.count == 2
        ? (String(parts[0]), String(parts[1]))
        : (nil, refStr)
    p.references.append(.init(paramName: "encounter", refType: refType, refId: refId))
}

// TODO: unhandled — evidence [token] Condition.evidence.code
private func extract_Condition_evidence(_ p: inout SearchParams, _ cond: Condition) {}

// TODO: unhandled — evidence-detail [reference] Condition.evidence.detail
private func extract_Condition_evidence_detail(_ p: inout SearchParams, _ cond: Condition) {}

// identifier [token] — Condition.identifier
private func extract_Condition_identifier(_ p: inout SearchParams, _ cond: Condition) {
    for ident in cond.identifier ?? [] {
        let v = ident.value?.value?.string ?? ""
        let s = ident.system?.value?.url.absoluteString
        p.tokens.append(.init(paramName: "identifier", system: s, code: v))
    }
}

// TODO: unhandled — onset-age [quantity] Condition.onset.as(Age) | Condition.onset.as(Range)
private func extract_Condition_onset_age(_ p: inout SearchParams, _ cond: Condition) {}

// onset-date [date] — Condition.onset.as(dateTime)
private func extract_Condition_onset_date(_ p: inout SearchParams, _ cond: Condition) {
    let cal = Calendar(identifier: .gregorian)
    guard let onset = cond.onset else { return }
    switch onset {
    case .dateTime(let prim):
        guard let dt = prim.value else { return }
        var dc = DateComponents()
        dc.year = dt.date.year; dc.month = dt.date.month.map(Int.init)
        dc.day  = dt.date.day.map(Int.init); dc.hour = 12
        let d = cal.date(from: dc) ?? Date()
        p.dates.append(.init(paramName: "onset-date", dateStart: d, dateEnd: d))
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
        p.dates.append(.init(paramName: "onset-date", dateStart: start, dateEnd: end))
    default:
        break
    }
}

// TODO: unhandled — onset-info [string] Condition.onset.as(string)
private func extract_Condition_onset_info(_ p: inout SearchParams, _ cond: Condition) {}

// patient [reference] — Condition.subject
private func extract_Condition_patient(_ p: inout SearchParams, _ cond: Condition) {
    guard let refStr = cond.subject.reference?.value?.string else { return }
    let parts = refStr.split(separator: "/")
    let (refType, refId): (String?, String) = parts.count == 2
        ? (String(parts[0]), String(parts[1]))
        : (nil, refStr)
    p.references.append(.init(paramName: "patient", refType: refType, refId: refId))
}

// recorded-date [date] — Condition.recordedDate
private func extract_Condition_recorded_date(_ p: inout SearchParams, _ cond: Condition) {
    guard let prim = cond.recordedDate, let dt = prim.value else { return }
    var dc = DateComponents()
    dc.year = dt.date.year; dc.month = dt.date.month.map(Int.init)
    dc.day  = dt.date.day.map(Int.init); dc.hour = 12
    dc.timeZone = dt.timeZone
    let d = Calendar(identifier: .gregorian).date(from: dc) ?? Date()
    p.dates.append(.init(paramName: "recorded-date", dateStart: d, dateEnd: d))
}

// TODO: unhandled — severity [token] Condition.severity
private func extract_Condition_severity(_ p: inout SearchParams, _ cond: Condition) {}

// TODO: unhandled — stage [token] Condition.stage.summary
private func extract_Condition_stage(_ p: inout SearchParams, _ cond: Condition) {}

// subject [reference] — Condition.subject
private func extract_Condition_subject(_ p: inout SearchParams, _ cond: Condition) {
    guard let refStr = cond.subject.reference?.value?.string else { return }
    let parts = refStr.split(separator: "/")
    let (refType, refId): (String?, String) = parts.count == 2
        ? (String(parts[0]), String(parts[1]))
        : (nil, refStr)
    p.references.append(.init(paramName: "subject", refType: refType, refId: refId))
}

// verification-status [token] — Condition.verificationStatus
private func extract_Condition_verification_status(_ p: inout SearchParams, _ cond: Condition) {
    for coding in cond.verificationStatus?.coding ?? [] {
        let c = coding.code?.value?.string ?? ""
        let s = coding.system?.value?.url.absoluteString
        p.tokens.append(.init(paramName: "verification-status", system: s, code: c))
    }
}