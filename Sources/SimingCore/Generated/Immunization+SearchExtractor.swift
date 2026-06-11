// GENERATED — do not edit directly.
// Source: packages/*.tgz (hl7.fhir.r4.core + tw.gov.mohw.twcore)
// Regenerate: swift run SimingGenerator

import Foundation
import ModelsR4

/// Extracts all supported search parameters from an Immunization for insertion
/// into the five idx_* index tables.
///
/// Params marked TODO are recognised by the FHIR R4 spec but not yet implemented.
public func extractImmunizationSearchParams(_ imm: Immunization) -> SearchParams {
    var p = SearchParams()
    extract_Immunization_date(&p, imm)
    extract_Immunization_identifier(&p, imm)
    extract_Immunization_location(&p, imm)
    extract_Immunization_lot_number(&p, imm)
    extract_Immunization_manufacturer(&p, imm)
    extract_Immunization_patient(&p, imm)
    extract_Immunization_performer(&p, imm)
    extract_Immunization_reaction(&p, imm)
    extract_Immunization_reaction_date(&p, imm)
    extract_Immunization_reason_code(&p, imm)
    extract_Immunization_reason_reference(&p, imm)
    extract_Immunization_series(&p, imm)
    extract_Immunization_status(&p, imm)
    extract_Immunization_status_reason(&p, imm)
    extract_Immunization_target_disease(&p, imm)
    extract_Immunization_vaccine_code(&p, imm)
    return p
}

// date [date] — Immunization.occurrence
private func extract_Immunization_date(_ p: inout SearchParams, _ imm: Immunization) {
    let cal = Calendar(identifier: .gregorian)
    switch imm.occurrence {
    case .dateTime(let prim):
        guard let dt = prim.value else { return }
        var dc = DateComponents()
        dc.year = dt.date.year; dc.month = dt.date.month.map(Int.init)
        dc.day  = dt.date.day.map(Int.init); dc.hour = 12
        dc.timeZone = dt.timeZone
        let d = cal.date(from: dc) ?? Date()
        p.dates.append(.init(paramName: "date", dateStart: d, dateEnd: d))
    default:
        break
    }
}

// identifier [token] — Immunization.identifier
private func extract_Immunization_identifier(_ p: inout SearchParams, _ imm: Immunization) {
    for ident in imm.identifier ?? [] {
        let v = ident.value?.value?.string ?? ""
        let s = ident.system?.value?.url.absoluteString
        p.tokens.append(.init(paramName: "identifier", system: s, code: v))
    }
}

// location [reference] — Immunization.location
private func extract_Immunization_location(_ p: inout SearchParams, _ imm: Immunization) {
    guard let refStr = imm.location?.reference?.value?.string else { return }
    let parts = refStr.split(separator: "/")
    let (refType, refId): (String?, String) = parts.count == 2
        ? (String(parts[0]), String(parts[1]))
        : (nil, refStr)
    p.references.append(.init(paramName: "location", refType: refType, refId: refId))
}

// lot-number [string] — Immunization.lotNumber
private func extract_Immunization_lot_number(_ p: inout SearchParams, _ imm: Immunization) {
    if let v = imm.lotNumber?.value?.string {
        p.strings.append(.init(paramName: "lot-number", value: v))
    }
}

// manufacturer [reference] — Immunization.manufacturer
private func extract_Immunization_manufacturer(_ p: inout SearchParams, _ imm: Immunization) {
    guard let refStr = imm.manufacturer?.reference?.value?.string else { return }
    let parts = refStr.split(separator: "/")
    let (refType, refId): (String?, String) = parts.count == 2
        ? (String(parts[0]), String(parts[1]))
        : (nil, refStr)
    p.references.append(.init(paramName: "manufacturer", refType: refType, refId: refId))
}

// patient [reference] — Immunization.patient
private func extract_Immunization_patient(_ p: inout SearchParams, _ imm: Immunization) {
    guard let refStr = imm.patient.reference?.value?.string else { return }
    let parts = refStr.split(separator: "/")
    let (refType, refId): (String?, String) = parts.count == 2
        ? (String(parts[0]), String(parts[1]))
        : (nil, refStr)
    p.references.append(.init(paramName: "patient", refType: refType, refId: refId))
}

// performer [reference] — Immunization.performer.actor
private func extract_Immunization_performer(_ p: inout SearchParams, _ imm: Immunization) {
    for perf in imm.performer ?? [] {
        guard let refStr = perf.actor.reference?.value?.string else { continue }
        let parts = refStr.split(separator: "/")
        let (refType, refId): (String?, String) = parts.count == 2
            ? (String(parts[0]), String(parts[1]))
            : (nil, refStr)
        p.references.append(.init(paramName: "performer", refType: refType, refId: refId))
    }
}

// reaction [reference] — Immunization.reaction.detail
private func extract_Immunization_reaction(_ p: inout SearchParams, _ imm: Immunization) {
    for rxn in imm.reaction ?? [] {
        guard let refStr = rxn.detail?.reference?.value?.string else { continue }
        let parts = refStr.split(separator: "/")
        let (refType, refId): (String?, String) = parts.count == 2
            ? (String(parts[0]), String(parts[1]))
            : (nil, refStr)
        p.references.append(.init(paramName: "reaction", refType: refType, refId: refId))
    }
}

// reaction-date [date] — Immunization.reaction.date
private func extract_Immunization_reaction_date(_ p: inout SearchParams, _ imm: Immunization) {
    let cal = Calendar(identifier: .gregorian)
    for rxn in imm.reaction ?? [] {
        guard let prim = rxn.date, let dt = prim.value else { continue }
        var dc = DateComponents()
        dc.year = dt.date.year; dc.month = dt.date.month.map(Int.init)
        dc.day  = dt.date.day.map(Int.init); dc.hour = 12
        dc.timeZone = dt.timeZone
        let d = cal.date(from: dc) ?? Date()
        p.dates.append(.init(paramName: "reaction-date", dateStart: d, dateEnd: d))
    }
}

// reason-code [token] — Immunization.reasonCode
private func extract_Immunization_reason_code(_ p: inout SearchParams, _ imm: Immunization) {
    for cc in imm.reasonCode ?? [] {
        for coding in cc.coding ?? [] {
            let c = coding.code?.value?.string ?? ""
            let s = coding.system?.value?.url.absoluteString
            p.appendToken(paramName: "reason-code", system: s, code: c, display: coding.display?.value?.string)
        }
    }
}

// reason-reference [reference] — Immunization.reasonReference
private func extract_Immunization_reason_reference(_ p: inout SearchParams, _ imm: Immunization) {
    for ref in imm.reasonReference ?? [] {
        guard let refStr = ref.reference?.value?.string else { continue }
        let parts = refStr.split(separator: "/")
        let (refType, refId): (String?, String) = parts.count == 2
            ? (String(parts[0]), String(parts[1]))
            : (nil, refStr)
        p.references.append(.init(paramName: "reason-reference", refType: refType, refId: refId))
    }
}

// series [string] — Immunization.protocolApplied.series
private func extract_Immunization_series(_ p: inout SearchParams, _ imm: Immunization) {
    for pa in imm.protocolApplied ?? [] {
        if let v = pa.series?.value?.string {
            p.strings.append(.init(paramName: "series", value: v))
        }
    }
}

// status [token] — Immunization.status
private func extract_Immunization_status(_ p: inout SearchParams, _ imm: Immunization) {
    if let v = imm.status.value?.rawValue {
        p.tokens.append(.init(paramName: "status",
                              system: "http://hl7.org/fhir/event-status", code: v))
    }
}

// status-reason [token] — Immunization.statusReason
private func extract_Immunization_status_reason(_ p: inout SearchParams, _ imm: Immunization) {
    for coding in imm.statusReason?.coding ?? [] {
        let c = coding.code?.value?.string ?? ""
        let s = coding.system?.value?.url.absoluteString
        p.appendToken(paramName: "status-reason", system: s, code: c, display: coding.display?.value?.string)
    }
}

// target-disease [token] — Immunization.protocolApplied.targetDisease
private func extract_Immunization_target_disease(_ p: inout SearchParams, _ imm: Immunization) {
    for pa in imm.protocolApplied ?? [] {
        for cc in pa.targetDisease ?? [] {
            for coding in cc.coding ?? [] {
                let c = coding.code?.value?.string ?? ""
                let s = coding.system?.value?.url.absoluteString
                p.appendToken(paramName: "target-disease", system: s, code: c, display: coding.display?.value?.string)
            }
        }
    }
}

// vaccine-code [token] — Immunization.vaccineCode
private func extract_Immunization_vaccine_code(_ p: inout SearchParams, _ imm: Immunization) {
    for coding in imm.vaccineCode.coding ?? [] {
        let c = coding.code?.value?.string ?? ""
        let s = coding.system?.value?.url.absoluteString
        p.appendToken(paramName: "vaccine-code", system: s, code: c, display: coding.display?.value?.string)
    }
}