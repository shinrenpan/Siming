// GENERATED — do not edit directly.
// Source: Resources/fhir/search-parameters-r4.json
// Regenerate: swift run SimingGenerator

import Foundation
import ModelsR4

/// Extracts all supported search parameters from an Encounter for insertion
/// into the five idx_* index tables.
///
/// Params marked TODO are recognised by the FHIR R4 spec but not yet implemented.
public func extractEncounterSearchParams(_ enc: Encounter) -> SearchParams {
    var p = SearchParams()
    extract_Encounter_account(&p, enc)
    extract_Encounter_appointment(&p, enc)
    extract_Encounter_based_on(&p, enc)
    extract_Encounter_class(&p, enc)
    extract_Encounter_date(&p, enc)
    extract_Encounter_diagnosis(&p, enc)
    extract_Encounter_episode_of_care(&p, enc)
    extract_Encounter_identifier(&p, enc)
    extract_Encounter_length(&p, enc)
    extract_Encounter_location(&p, enc)
    extract_Encounter_location_period(&p, enc)
    extract_Encounter_part_of(&p, enc)
    extract_Encounter_participant(&p, enc)
    extract_Encounter_participant_type(&p, enc)
    extract_Encounter_patient(&p, enc)
    extract_Encounter_practitioner(&p, enc)
    extract_Encounter_reason_code(&p, enc)
    extract_Encounter_reason_reference(&p, enc)
    extract_Encounter_service_provider(&p, enc)
    extract_Encounter_special_arrangement(&p, enc)
    extract_Encounter_status(&p, enc)
    extract_Encounter_subject(&p, enc)
    extract_Encounter_type(&p, enc)
    return p
}

// account [reference] — Encounter.account
private func extract_Encounter_account(_ p: inout SearchParams, _ enc: Encounter) {
    for ref in enc.account ?? [] {
        guard let refStr = ref.reference?.value?.string else { continue }
        let parts = refStr.split(separator: "/")
        let (refType, refId): (String?, String) = parts.count == 2
            ? (String(parts[0]), String(parts[1]))
            : (nil, refStr)
        p.references.append(.init(paramName: "account", refType: refType, refId: refId))
    }
}

// appointment [reference] — Encounter.appointment
private func extract_Encounter_appointment(_ p: inout SearchParams, _ enc: Encounter) {
    for ref in enc.appointment ?? [] {
        guard let refStr = ref.reference?.value?.string else { continue }
        let parts = refStr.split(separator: "/")
        let (refType, refId): (String?, String) = parts.count == 2
            ? (String(parts[0]), String(parts[1]))
            : (nil, refStr)
        p.references.append(.init(paramName: "appointment", refType: refType, refId: refId))
    }
}

// based-on [reference] — Encounter.basedOn
private func extract_Encounter_based_on(_ p: inout SearchParams, _ enc: Encounter) {
    for ref in enc.basedOn ?? [] {
        guard let refStr = ref.reference?.value?.string else { continue }
        let parts = refStr.split(separator: "/")
        let (refType, refId): (String?, String) = parts.count == 2
            ? (String(parts[0]), String(parts[1]))
            : (nil, refStr)
        p.references.append(.init(paramName: "based-on", refType: refType, refId: refId))
    }
}

// class [token] — Encounter.class
private func extract_Encounter_class(_ p: inout SearchParams, _ enc: Encounter) {
    let c = enc.`class`.code?.value?.string ?? ""
    let s = enc.`class`.system?.value?.url.absoluteString
    p.tokens.append(.init(paramName: "class", system: s, code: c))
}

// date [date] — Encounter.period
private func extract_Encounter_date(_ p: inout SearchParams, _ enc: Encounter) {
    guard let period = enc.period else { return }
    let cal = Calendar(identifier: .gregorian)
    let start: Date
    let end: Date
    if let prim = period.start, let dt = prim.value {
        var dc = DateComponents()
        dc.year = dt.date.year; dc.month = dt.date.month.map(Int.init)
        dc.day  = dt.date.day.map(Int.init); dc.hour = 0
        start = cal.date(from: dc) ?? Date.distantPast
    } else {
        start = Date.distantPast
    }
    if let prim = period.end, let dt = prim.value {
        var dc = DateComponents()
        dc.year = dt.date.year; dc.month = dt.date.month.map(Int.init)
        dc.day  = dt.date.day.map(Int.init); dc.hour = 23; dc.minute = 59
        end = cal.date(from: dc) ?? Date.distantFuture
    } else {
        end = Date.distantFuture
    }
    p.dates.append(.init(paramName: "date", dateStart: start, dateEnd: end))
}

// diagnosis [reference] — Encounter.diagnosis.condition
private func extract_Encounter_diagnosis(_ p: inout SearchParams, _ enc: Encounter) {
    for diag in enc.diagnosis ?? [] {
        guard let refStr = diag.condition.reference?.value?.string else { continue }
        let parts = refStr.split(separator: "/")
        let (refType, refId): (String?, String) = parts.count == 2
            ? (String(parts[0]), String(parts[1]))
            : (nil, refStr)
        p.references.append(.init(paramName: "diagnosis", refType: refType, refId: refId))
    }
}

// episode-of-care [reference] — Encounter.episodeOfCare
private func extract_Encounter_episode_of_care(_ p: inout SearchParams, _ enc: Encounter) {
    for ref in enc.episodeOfCare ?? [] {
        guard let refStr = ref.reference?.value?.string else { continue }
        let parts = refStr.split(separator: "/")
        let (refType, refId): (String?, String) = parts.count == 2
            ? (String(parts[0]), String(parts[1]))
            : (nil, refStr)
        p.references.append(.init(paramName: "episode-of-care", refType: refType, refId: refId))
    }
}

// identifier [token] — Encounter.identifier
private func extract_Encounter_identifier(_ p: inout SearchParams, _ enc: Encounter) {
    for ident in enc.identifier ?? [] {
        let v = ident.value?.value?.string ?? ""
        let s = ident.system?.value?.url.absoluteString
        p.tokens.append(.init(paramName: "identifier", system: s, code: v))
    }
}

// length [quantity] — Encounter.length
private func extract_Encounter_length(_ p: inout SearchParams, _ enc: Encounter) {
    guard let qty = enc.length,
          let decimalVal = qty.value?.value?.decimal else { return }
    let sys  = qty.system?.value?.url.absoluteString
    let unit = qty.code?.value?.string
    p.quantities.append(.init(paramName: "length", system: sys, code: unit,
                              value: Decimal(string: decimalVal.description) ?? 0))
}

// location [reference] — Encounter.location.location
private func extract_Encounter_location(_ p: inout SearchParams, _ enc: Encounter) {
    for loc in enc.location ?? [] {
        guard let refStr = loc.location.reference?.value?.string else { continue }
        let parts = refStr.split(separator: "/")
        let (refType, refId): (String?, String) = parts.count == 2
            ? (String(parts[0]), String(parts[1]))
            : (nil, refStr)
        p.references.append(.init(paramName: "location", refType: refType, refId: refId))
    }
}

// location-period [date] — Encounter.location.period
private func extract_Encounter_location_period(_ p: inout SearchParams, _ enc: Encounter) {
    let cal = Calendar(identifier: .gregorian)
    for loc in enc.location ?? [] {
        guard let period = loc.period else { continue }
        let start: Date
        let end: Date
        if let prim = period.start, let dt = prim.value {
            var dc = DateComponents()
            dc.year = dt.date.year; dc.month = dt.date.month.map(Int.init)
            dc.day  = dt.date.day.map(Int.init); dc.hour = 0
            start = cal.date(from: dc) ?? Date.distantPast
        } else {
            start = Date.distantPast
        }
        if let prim = period.end, let dt = prim.value {
            var dc = DateComponents()
            dc.year = dt.date.year; dc.month = dt.date.month.map(Int.init)
            dc.day  = dt.date.day.map(Int.init); dc.hour = 23; dc.minute = 59
            end = cal.date(from: dc) ?? Date.distantFuture
        } else {
            end = Date.distantFuture
        }
        p.dates.append(.init(paramName: "location-period", dateStart: start, dateEnd: end))
    }
}

// part-of [reference] — Encounter.partOf
private func extract_Encounter_part_of(_ p: inout SearchParams, _ enc: Encounter) {
    guard let refStr = enc.partOf?.reference?.value?.string else { return }
    let parts = refStr.split(separator: "/")
    let (refType, refId): (String?, String) = parts.count == 2
        ? (String(parts[0]), String(parts[1]))
        : (nil, refStr)
    p.references.append(.init(paramName: "part-of", refType: refType, refId: refId))
}

// participant [reference] — Encounter.participant.individual
private func extract_Encounter_participant(_ p: inout SearchParams, _ enc: Encounter) {
    for part in enc.participant ?? [] {
        guard let refStr = part.individual?.reference?.value?.string else { continue }
        let parts = refStr.split(separator: "/")
        let (refType, refId): (String?, String) = parts.count == 2
            ? (String(parts[0]), String(parts[1]))
            : (nil, refStr)
        p.references.append(.init(paramName: "participant", refType: refType, refId: refId))
    }
}

// participant-type [token] — Encounter.participant.type
private func extract_Encounter_participant_type(_ p: inout SearchParams, _ enc: Encounter) {
    for part in enc.participant ?? [] {
        for cc in part.type ?? [] {
            for coding in cc.coding ?? [] {
                let c = coding.code?.value?.string ?? ""
                let s = coding.system?.value?.url.absoluteString
                p.tokens.append(.init(paramName: "participant-type", system: s, code: c))
            }
        }
    }
}

// patient [reference] — Encounter.subject
private func extract_Encounter_patient(_ p: inout SearchParams, _ enc: Encounter) {
    guard let refStr = enc.subject?.reference?.value?.string else { return }
    let parts = refStr.split(separator: "/")
    let (refType, refId): (String?, String) = parts.count == 2
        ? (String(parts[0]), String(parts[1]))
        : (nil, refStr)
    p.references.append(.init(paramName: "patient", refType: refType, refId: refId))
}

// practitioner [reference] — Encounter.participant.individual
private func extract_Encounter_practitioner(_ p: inout SearchParams, _ enc: Encounter) {
    for part in enc.participant ?? [] {
        guard let refStr = part.individual?.reference?.value?.string else { continue }
        let parts = refStr.split(separator: "/")
        let (refType, refId): (String?, String) = parts.count == 2
            ? (String(parts[0]), String(parts[1]))
            : (nil, refStr)
        p.references.append(.init(paramName: "practitioner", refType: refType, refId: refId))
    }
}

// reason-code [token] — Encounter.reasonCode
private func extract_Encounter_reason_code(_ p: inout SearchParams, _ enc: Encounter) {
    for cc in enc.reasonCode ?? [] {
        for coding in cc.coding ?? [] {
            let c = coding.code?.value?.string ?? ""
            let s = coding.system?.value?.url.absoluteString
            p.tokens.append(.init(paramName: "reason-code", system: s, code: c))
        }
    }
}

// reason-reference [reference] — Encounter.reasonReference
private func extract_Encounter_reason_reference(_ p: inout SearchParams, _ enc: Encounter) {
    for ref in enc.reasonReference ?? [] {
        guard let refStr = ref.reference?.value?.string else { continue }
        let parts = refStr.split(separator: "/")
        let (refType, refId): (String?, String) = parts.count == 2
            ? (String(parts[0]), String(parts[1]))
            : (nil, refStr)
        p.references.append(.init(paramName: "reason-reference", refType: refType, refId: refId))
    }
}

// service-provider [reference] — Encounter.serviceProvider
private func extract_Encounter_service_provider(_ p: inout SearchParams, _ enc: Encounter) {
    guard let refStr = enc.serviceProvider?.reference?.value?.string else { return }
    let parts = refStr.split(separator: "/")
    let (refType, refId): (String?, String) = parts.count == 2
        ? (String(parts[0]), String(parts[1]))
        : (nil, refStr)
    p.references.append(.init(paramName: "service-provider", refType: refType, refId: refId))
}

// special-arrangement [token] — Encounter.hospitalization.specialArrangement
private func extract_Encounter_special_arrangement(_ p: inout SearchParams, _ enc: Encounter) {
    for cc in enc.hospitalization?.specialArrangement ?? [] {
        for coding in cc.coding ?? [] {
            let c = coding.code?.value?.string ?? ""
            let s = coding.system?.value?.url.absoluteString
            p.tokens.append(.init(paramName: "special-arrangement", system: s, code: c))
        }
    }
}

// status [token] — Encounter.status
private func extract_Encounter_status(_ p: inout SearchParams, _ enc: Encounter) {
    if let v = enc.status.value?.rawValue {
        p.tokens.append(.init(paramName: "status",
                              system: "http://hl7.org/fhir/encounter-status", code: v))
    }
}

// subject [reference] — Encounter.subject
private func extract_Encounter_subject(_ p: inout SearchParams, _ enc: Encounter) {
    guard let refStr = enc.subject?.reference?.value?.string else { return }
    let parts = refStr.split(separator: "/")
    let (refType, refId): (String?, String) = parts.count == 2
        ? (String(parts[0]), String(parts[1]))
        : (nil, refStr)
    p.references.append(.init(paramName: "subject", refType: refType, refId: refId))
}

// type [token] — Encounter.type
private func extract_Encounter_type(_ p: inout SearchParams, _ enc: Encounter) {
    for cc in enc.type ?? [] {
        for coding in cc.coding ?? [] {
            let c = coding.code?.value?.string ?? ""
            let s = coding.system?.value?.url.absoluteString
            p.tokens.append(.init(paramName: "type", system: s, code: c))
        }
    }
}