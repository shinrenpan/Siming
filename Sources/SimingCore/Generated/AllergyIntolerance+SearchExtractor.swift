// GENERATED — do not edit directly.
// Source: packages/*.tgz (hl7.fhir.r4.core + tw.gov.mohw.twcore)
// Regenerate: swift run SimingGenerator

import Foundation
import ModelsR4

/// Extracts all supported search parameters from an AllergyIntolerance for insertion
/// into the five idx_* index tables.
///
/// Params marked TODO are recognised by the FHIR R4 spec but not yet implemented.
public func extractAllergyIntoleranceSearchParams(_ ai: AllergyIntolerance) -> SearchParams {
    var p = SearchParams()
    extract_AllergyIntolerance__id(&p, ai)
    extract_AllergyIntolerance_asserter(&p, ai)
    extract_AllergyIntolerance_category(&p, ai)
    extract_AllergyIntolerance_clinical_status(&p, ai)
    extract_AllergyIntolerance_code(&p, ai)
    extract_AllergyIntolerance_criticality(&p, ai)
    extract_AllergyIntolerance_date(&p, ai)
    extract_AllergyIntolerance_identifier(&p, ai)
    extract_AllergyIntolerance_last_date(&p, ai)
    extract_AllergyIntolerance_manifestation(&p, ai)
    extract_AllergyIntolerance_onset(&p, ai)
    extract_AllergyIntolerance_patient(&p, ai)
    extract_AllergyIntolerance_recorder(&p, ai)
    extract_AllergyIntolerance_route(&p, ai)
    extract_AllergyIntolerance_severity(&p, ai)
    extract_AllergyIntolerance_type(&p, ai)
    extract_AllergyIntolerance_verification_status(&p, ai)
    return p
}

// TODO: unhandled — _id [token] AllergyIntolerance.id
private func extract_AllergyIntolerance__id(_ p: inout SearchParams, _ ai: AllergyIntolerance) {}

// asserter [reference] — AllergyIntolerance.asserter
private func extract_AllergyIntolerance_asserter(_ p: inout SearchParams, _ ai: AllergyIntolerance) {
    guard let refStr = ai.asserter?.reference?.value?.string else { return }
    let parts = refStr.split(separator: "/")
    let (refType, refId): (String?, String) = parts.count == 2
        ? (String(parts[0]), String(parts[1]))
        : (nil, refStr)
    p.references.append(.init(paramName: "asserter", refType: refType, refId: refId))
}

// category [token] — AllergyIntolerance.category
private func extract_AllergyIntolerance_category(_ p: inout SearchParams, _ ai: AllergyIntolerance) {
    for prim in ai.category ?? [] {
        if let v = prim.value?.rawValue {
            p.tokens.append(.init(paramName: "category",
                                  system: "http://hl7.org/fhir/allergy-intolerance-category",
                                  code: v))
        }
    }
}

// clinical-status [token] — AllergyIntolerance.clinicalStatus
private func extract_AllergyIntolerance_clinical_status(_ p: inout SearchParams, _ ai: AllergyIntolerance) {
    for coding in ai.clinicalStatus?.coding ?? [] {
        let c = coding.code?.value?.string ?? ""
        let s = coding.system?.value?.url.absoluteString
        p.appendToken(paramName: "clinical-status", system: s, code: c, display: coding.display?.value?.string)
    }
}

// code [token] — AllergyIntolerance.code
private func extract_AllergyIntolerance_code(_ p: inout SearchParams, _ ai: AllergyIntolerance) {
    for coding in ai.code?.coding ?? [] {
        let c = coding.code?.value?.string ?? ""
        let s = coding.system?.value?.url.absoluteString
        p.appendToken(paramName: "code", system: s, code: c, display: coding.display?.value?.string)
    }
}

// criticality [token] — AllergyIntolerance.criticality
private func extract_AllergyIntolerance_criticality(_ p: inout SearchParams, _ ai: AllergyIntolerance) {
    if let v = ai.criticality?.value?.rawValue {
        p.tokens.append(.init(paramName: "criticality",
                              system: "http://hl7.org/fhir/allergy-intolerance-criticality",
                              code: v))
    }
}

// date [date] — AllergyIntolerance.recordedDate
private func extract_AllergyIntolerance_date(_ p: inout SearchParams, _ ai: AllergyIntolerance) {
    guard let prim = ai.recordedDate, let dt = prim.value else { return }
    var dc = DateComponents()
    dc.year = dt.date.year; dc.month = dt.date.month.map(Int.init)
    dc.day  = dt.date.day.map(Int.init); dc.hour = 12
    dc.timeZone = dt.timeZone
    let d = Calendar(identifier: .gregorian).date(from: dc) ?? Date()
    p.dates.append(.init(paramName: "date", dateStart: d, dateEnd: d))
}

// identifier [token] — AllergyIntolerance.identifier
private func extract_AllergyIntolerance_identifier(_ p: inout SearchParams, _ ai: AllergyIntolerance) {
    for ident in ai.identifier ?? [] {
        let v = ident.value?.value?.string ?? ""
        let s = ident.system?.value?.url.absoluteString
        p.tokens.append(.init(paramName: "identifier", system: s, code: v))
    }
}

// last-date [date] — AllergyIntolerance.lastOccurrence
private func extract_AllergyIntolerance_last_date(_ p: inout SearchParams, _ ai: AllergyIntolerance) {
    guard let prim = ai.lastOccurrence, let dt = prim.value else { return }
    var dc = DateComponents()
    dc.year = dt.date.year; dc.month = dt.date.month.map(Int.init)
    dc.day  = dt.date.day.map(Int.init); dc.hour = 12
    dc.timeZone = dt.timeZone
    let d = Calendar(identifier: .gregorian).date(from: dc) ?? Date()
    p.dates.append(.init(paramName: "last-date", dateStart: d, dateEnd: d))
}

// manifestation [token] — AllergyIntolerance.reaction.manifestation
private func extract_AllergyIntolerance_manifestation(_ p: inout SearchParams, _ ai: AllergyIntolerance) {
    for reaction in ai.reaction ?? [] {
        for cc in reaction.manifestation {
            for coding in cc.coding ?? [] {
                let c = coding.code?.value?.string ?? ""
                let s = coding.system?.value?.url.absoluteString
                p.appendToken(paramName: "manifestation", system: s, code: c, display: coding.display?.value?.string)
            }
        }
    }
}

// onset [date] — AllergyIntolerance.reaction.onset
private func extract_AllergyIntolerance_onset(_ p: inout SearchParams, _ ai: AllergyIntolerance) {
    for reaction in ai.reaction ?? [] {
        guard let prim = reaction.onset, let dt = prim.value else { continue }
        var dc = DateComponents()
        dc.year = dt.date.year; dc.month = dt.date.month.map(Int.init)
        dc.day  = dt.date.day.map(Int.init); dc.hour = 12
        dc.timeZone = dt.timeZone
        let d = Calendar(identifier: .gregorian).date(from: dc) ?? Date()
        p.dates.append(.init(paramName: "onset", dateStart: d, dateEnd: d))
    }
}

// patient [reference] — AllergyIntolerance.patient
private func extract_AllergyIntolerance_patient(_ p: inout SearchParams, _ ai: AllergyIntolerance) {
    guard let refStr = ai.patient.reference?.value?.string else { return }
    let parts = refStr.split(separator: "/")
    let (refType, refId): (String?, String) = parts.count == 2
        ? (String(parts[0]), String(parts[1]))
        : (nil, refStr)
    p.references.append(.init(paramName: "patient", refType: refType, refId: refId))
}

// recorder [reference] — AllergyIntolerance.recorder
private func extract_AllergyIntolerance_recorder(_ p: inout SearchParams, _ ai: AllergyIntolerance) {
    guard let refStr = ai.recorder?.reference?.value?.string else { return }
    let parts = refStr.split(separator: "/")
    let (refType, refId): (String?, String) = parts.count == 2
        ? (String(parts[0]), String(parts[1]))
        : (nil, refStr)
    p.references.append(.init(paramName: "recorder", refType: refType, refId: refId))
}

// route [token] — AllergyIntolerance.reaction.exposureRoute
private func extract_AllergyIntolerance_route(_ p: inout SearchParams, _ ai: AllergyIntolerance) {
    for reaction in ai.reaction ?? [] {
        for coding in reaction.exposureRoute?.coding ?? [] {
            let c = coding.code?.value?.string ?? ""
            let s = coding.system?.value?.url.absoluteString
            p.appendToken(paramName: "route", system: s, code: c, display: coding.display?.value?.string)
        }
    }
}

// severity [token] — AllergyIntolerance.reaction.severity
private func extract_AllergyIntolerance_severity(_ p: inout SearchParams, _ ai: AllergyIntolerance) {
    for reaction in ai.reaction ?? [] {
        if let v = reaction.severity?.value?.rawValue {
            p.tokens.append(.init(paramName: "severity",
                                  system: "http://hl7.org/fhir/reaction-event-severity",
                                  code: v))
        }
    }
}

// type [token] — AllergyIntolerance.type
private func extract_AllergyIntolerance_type(_ p: inout SearchParams, _ ai: AllergyIntolerance) {
    if let v = ai.type?.value?.rawValue {
        p.tokens.append(.init(paramName: "type",
                              system: "http://hl7.org/fhir/allergy-intolerance-type",
                              code: v))
    }
}

// verification-status [token] — AllergyIntolerance.verificationStatus
private func extract_AllergyIntolerance_verification_status(_ p: inout SearchParams, _ ai: AllergyIntolerance) {
    for coding in ai.verificationStatus?.coding ?? [] {
        let c = coding.code?.value?.string ?? ""
        let s = coding.system?.value?.url.absoluteString
        p.appendToken(paramName: "verification-status", system: s, code: c, display: coding.display?.value?.string)
    }
}