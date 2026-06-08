// GENERATED — do not edit directly.
// Source: Resources/fhir/search-parameters-r4.json
// Regenerate: swift run SimingGenerator

import Foundation
import ModelsR4

/// Extracts all supported search parameters from an Observation for insertion
/// into the five idx_* index tables.
///
/// Params marked TODO are recognised by the FHIR R4 spec but not yet implemented.
public func extractObservationSearchParams(_ obs: Observation) -> SearchParams {
    var p = SearchParams()
    extract_Observation_based_on(&p, obs)
    extract_Observation_category(&p, obs)
    extract_Observation_code(&p, obs)
    extract_Observation_code_value_concept(&p, obs)
    extract_Observation_code_value_date(&p, obs)
    extract_Observation_code_value_quantity(&p, obs)
    extract_Observation_code_value_string(&p, obs)
    extract_Observation_combo_code(&p, obs)
    extract_Observation_combo_code_value_concept(&p, obs)
    extract_Observation_combo_code_value_quantity(&p, obs)
    extract_Observation_combo_data_absent_reason(&p, obs)
    extract_Observation_combo_value_concept(&p, obs)
    extract_Observation_combo_value_quantity(&p, obs)
    extract_Observation_component_code(&p, obs)
    extract_Observation_component_code_value_concept(&p, obs)
    extract_Observation_component_code_value_quantity(&p, obs)
    extract_Observation_component_data_absent_reason(&p, obs)
    extract_Observation_component_value_concept(&p, obs)
    extract_Observation_component_value_quantity(&p, obs)
    extract_Observation_data_absent_reason(&p, obs)
    extract_Observation_date(&p, obs)
    extract_Observation_derived_from(&p, obs)
    extract_Observation_device(&p, obs)
    extract_Observation_encounter(&p, obs)
    extract_Observation_focus(&p, obs)
    extract_Observation_has_member(&p, obs)
    extract_Observation_identifier(&p, obs)
    extract_Observation_method(&p, obs)
    extract_Observation_part_of(&p, obs)
    extract_Observation_patient(&p, obs)
    extract_Observation_performer(&p, obs)
    extract_Observation_specimen(&p, obs)
    extract_Observation_status(&p, obs)
    extract_Observation_subject(&p, obs)
    extract_Observation_value_concept(&p, obs)
    extract_Observation_value_date(&p, obs)
    extract_Observation_value_quantity(&p, obs)
    extract_Observation_value_string(&p, obs)
    return p
}

// based-on [reference] — Observation.basedOn
private func extract_Observation_based_on(_ p: inout SearchParams, _ obs: Observation) {
    for ref in obs.basedOn ?? [] {
        guard let refStr = ref.reference?.value?.string else { continue }
        let parts = refStr.split(separator: "/")
        let (refType, refId): (String?, String) = parts.count == 2
            ? (String(parts[0]), String(parts[1]))
            : (nil, refStr)
        p.references.append(.init(paramName: "based-on", refType: refType, refId: refId))
    }
}

// category [token] — Observation.category
private func extract_Observation_category(_ p: inout SearchParams, _ obs: Observation) {
    for cc in obs.category ?? [] {
        for coding in cc.coding ?? [] {
            let c = coding.code?.value?.string ?? ""
            let s = coding.system?.value?.url.absoluteString
            p.tokens.append(.init(paramName: "category", system: s, code: c))
        }
    }
}

// code [token] — Observation.code
private func extract_Observation_code(_ p: inout SearchParams, _ obs: Observation) {
    for coding in obs.code.coding ?? [] {
        let c = coding.code?.value?.string ?? ""
        let s = coding.system?.value?.url.absoluteString
        p.tokens.append(.init(paramName: "code", system: s, code: c))
    }
    if let text = obs.code.text?.value?.string {
        p.tokens.append(.init(paramName: "code", system: nil, code: text))
    }
}

// TODO: unhandled — code-value-concept [composite] Observation
private func extract_Observation_code_value_concept(_ p: inout SearchParams, _ obs: Observation) {}

// TODO: unhandled — code-value-date [composite] Observation
private func extract_Observation_code_value_date(_ p: inout SearchParams, _ obs: Observation) {}

// TODO: unhandled — code-value-quantity [composite] Observation
private func extract_Observation_code_value_quantity(_ p: inout SearchParams, _ obs: Observation) {}

// TODO: unhandled — code-value-string [composite] Observation
private func extract_Observation_code_value_string(_ p: inout SearchParams, _ obs: Observation) {}

// combo-code [token] — Observation.code
private func extract_Observation_combo_code(_ p: inout SearchParams, _ obs: Observation) {
    for coding in obs.code.coding ?? [] {
        let c = coding.code?.value?.string ?? ""
        let s = coding.system?.value?.url.absoluteString
        p.tokens.append(.init(paramName: "combo-code", system: s, code: c))
    }
    for comp in obs.component ?? [] {
        for coding in comp.code.coding ?? [] {
            let c = coding.code?.value?.string ?? ""
            let s = coding.system?.value?.url.absoluteString
            p.tokens.append(.init(paramName: "combo-code", system: s, code: c))
        }
    }
}

// TODO: unhandled — combo-code-value-concept [composite] Observation | Observation.component
private func extract_Observation_combo_code_value_concept(_ p: inout SearchParams, _ obs: Observation) {}

// TODO: unhandled — combo-code-value-quantity [composite] Observation | Observation.component
private func extract_Observation_combo_code_value_quantity(_ p: inout SearchParams, _ obs: Observation) {}

// combo-data-absent-reason [token] — Observation.dataAbsentReason
private func extract_Observation_combo_data_absent_reason(_ p: inout SearchParams, _ obs: Observation) {
    for coding in obs.dataAbsentReason?.coding ?? [] {
        let c = coding.code?.value?.string ?? ""
        let s = coding.system?.value?.url.absoluteString
        p.tokens.append(.init(paramName: "combo-data-absent-reason", system: s, code: c))
    }
    for comp in obs.component ?? [] {
        for coding in comp.dataAbsentReason?.coding ?? [] {
            let c = coding.code?.value?.string ?? ""
            let s = coding.system?.value?.url.absoluteString
            p.tokens.append(.init(paramName: "combo-data-absent-reason", system: s, code: c))
        }
    }
}

// combo-value-concept [token] — Observation.value
private func extract_Observation_combo_value_concept(_ p: inout SearchParams, _ obs: Observation) {
    guard case .quantity(let q) = obs.value else { return }
    guard let decimalVal = q.value?.value?.decimal else { return }
    let sys  = q.system?.value?.url.absoluteString
    let unit = q.code?.value?.string
    p.quantities.append(.init(paramName: "combo-value-concept", system: sys, code: unit,
                              value: Decimal(string: decimalVal.description) ?? 0))
}

// combo-value-quantity [quantity] — Observation.value
private func extract_Observation_combo_value_quantity(_ p: inout SearchParams, _ obs: Observation) {
    guard case .quantity(let q) = obs.value else { return }
    guard let decimalVal = q.value?.value?.decimal else { return }
    let sys  = q.system?.value?.url.absoluteString
    let unit = q.code?.value?.string
    p.quantities.append(.init(paramName: "combo-value-quantity", system: sys, code: unit,
                              value: Decimal(string: decimalVal.description) ?? 0))
}

// component-code [token] — Observation.component.code
private func extract_Observation_component_code(_ p: inout SearchParams, _ obs: Observation) {
    for comp in obs.component ?? [] {
        for coding in comp.code.coding ?? [] {
            let c = coding.code?.value?.string ?? ""
            let s = coding.system?.value?.url.absoluteString
            p.tokens.append(.init(paramName: "component-code", system: s, code: c))
        }
    }
}

// TODO: unhandled — component-code-value-concept [composite] Observation.component
private func extract_Observation_component_code_value_concept(_ p: inout SearchParams, _ obs: Observation) {}

// TODO: unhandled — component-code-value-quantity [composite] Observation.component
private func extract_Observation_component_code_value_quantity(_ p: inout SearchParams, _ obs: Observation) {}

// component-data-absent-reason [token] — Observation.component.dataAbsentReason
private func extract_Observation_component_data_absent_reason(_ p: inout SearchParams, _ obs: Observation) {
    for comp in obs.component ?? [] {
        for coding in comp.dataAbsentReason?.coding ?? [] {
            let c = coding.code?.value?.string ?? ""
            let s = coding.system?.value?.url.absoluteString
            p.tokens.append(.init(paramName: "component-data-absent-reason", system: s, code: c))
        }
    }
}

// component-value-concept [token] — Observation.component.value
private func extract_Observation_component_value_concept(_ p: inout SearchParams, _ obs: Observation) {
    for comp in obs.component ?? [] {
        guard case .codeableConcept(let cc) = comp.value else { continue }
        for coding in cc.coding ?? [] {
            let c = coding.code?.value?.string ?? ""
            let s = coding.system?.value?.url.absoluteString
            p.tokens.append(.init(paramName: "component-value-concept", system: s, code: c))
        }
    }
}

// TODO: unhandled — component-value-quantity [quantity] (Observation.component.value as Quantity) | (Observation.component.value as SampledData)
private func extract_Observation_component_value_quantity(_ p: inout SearchParams, _ obs: Observation) {}

// data-absent-reason [token] — Observation.dataAbsentReason
private func extract_Observation_data_absent_reason(_ p: inout SearchParams, _ obs: Observation) {
    for coding in obs.dataAbsentReason?.coding ?? [] {
        let c = coding.code?.value?.string ?? ""
        let s = coding.system?.value?.url.absoluteString
        p.tokens.append(.init(paramName: "data-absent-reason", system: s, code: c))
    }
}

// date [date] — Observation.effective
private func extract_Observation_date(_ p: inout SearchParams, _ obs: Observation) {
    guard let eff = obs.effective else { return }
    switch eff {
    case .dateTime(let prim):
        guard let dt = prim.value else { return }
        var dc = DateComponents()
        dc.year     = dt.date.year
        dc.month    = dt.date.month.map(Int.init)
        dc.day      = dt.date.day.map(Int.init)
        dc.hour     = dt.time.map { Int($0.hour) } ?? 12
        dc.minute   = dt.time.map { Int($0.minute) }
        dc.timeZone = dt.timeZone
        let d = Calendar(identifier: .gregorian).date(from: dc) ?? Date()
        p.dates.append(.init(paramName: "date", dateStart: d, dateEnd: d))
    case .period(let period):
        let start = period.start.flatMap { prim -> Date? in
            guard let dt = prim.value else { return nil }
            var dc = DateComponents()
            dc.year = dt.date.year; dc.month = dt.date.month.map(Int.init)
            dc.day  = dt.date.day.map(Int.init); dc.hour = 0
            return Calendar(identifier: .gregorian).date(from: dc)
        } ?? Date.distantPast
        let end = period.end.flatMap { prim -> Date? in
            guard let dt = prim.value else { return nil }
            var dc = DateComponents()
            dc.year = dt.date.year; dc.month = dt.date.month.map(Int.init)
            dc.day  = dt.date.day.map(Int.init); dc.hour = 23; dc.minute = 59
            return Calendar(identifier: .gregorian).date(from: dc)
        } ?? Date.distantFuture
        p.dates.append(.init(paramName: "date", dateStart: start, dateEnd: end))
    case .instant(let prim):
        guard let inst = prim.value else { return }
        var dc = DateComponents()
        dc.year     = inst.date.year
        dc.month    = Int(inst.date.month)
        dc.day      = Int(inst.date.day)
        dc.hour     = Int(inst.time.hour)
        dc.minute   = Int(inst.time.minute)
        dc.timeZone = inst.timeZone
        let d = Calendar(identifier: .gregorian).date(from: dc) ?? Date()
        p.dates.append(.init(paramName: "date", dateStart: d, dateEnd: d))
    case .timing:
        break  // TODO: Timing is complex
    }
}

// derived-from [reference] — Observation.derivedFrom
private func extract_Observation_derived_from(_ p: inout SearchParams, _ obs: Observation) {
    for ref in obs.derivedFrom ?? [] {
        guard let refStr = ref.reference?.value?.string else { continue }
        let parts = refStr.split(separator: "/")
        let (refType, refId): (String?, String) = parts.count == 2
            ? (String(parts[0]), String(parts[1]))
            : (nil, refStr)
        p.references.append(.init(paramName: "derived-from", refType: refType, refId: refId))
    }
}

// device [reference] — Observation.device
private func extract_Observation_device(_ p: inout SearchParams, _ obs: Observation) {
    guard let refStr = obs.device?.reference?.value?.string else { return }
    let parts = refStr.split(separator: "/")
    let (refType, refId): (String?, String) = parts.count == 2
        ? (String(parts[0]), String(parts[1]))
        : (nil, refStr)
    p.references.append(.init(paramName: "device", refType: refType, refId: refId))
}

// encounter [reference] — Observation.encounter
private func extract_Observation_encounter(_ p: inout SearchParams, _ obs: Observation) {
    guard let refStr = obs.encounter?.reference?.value?.string else { return }
    let parts = refStr.split(separator: "/")
    let (refType, refId): (String?, String) = parts.count == 2
        ? (String(parts[0]), String(parts[1]))
        : (nil, refStr)
    p.references.append(.init(paramName: "encounter", refType: refType, refId: refId))
}

// focus [reference] — Observation.focus
private func extract_Observation_focus(_ p: inout SearchParams, _ obs: Observation) {
    for ref in obs.focus ?? [] {
        guard let refStr = ref.reference?.value?.string else { continue }
        let parts = refStr.split(separator: "/")
        let (refType, refId): (String?, String) = parts.count == 2
            ? (String(parts[0]), String(parts[1]))
            : (nil, refStr)
        p.references.append(.init(paramName: "focus", refType: refType, refId: refId))
    }
}

// has-member [reference] — Observation.hasMember
private func extract_Observation_has_member(_ p: inout SearchParams, _ obs: Observation) {
    for ref in obs.hasMember ?? [] {
        guard let refStr = ref.reference?.value?.string else { continue }
        let parts = refStr.split(separator: "/")
        let (refType, refId): (String?, String) = parts.count == 2
            ? (String(parts[0]), String(parts[1]))
            : (nil, refStr)
        p.references.append(.init(paramName: "has-member", refType: refType, refId: refId))
    }
}

// identifier [token] — Observation.identifier
private func extract_Observation_identifier(_ p: inout SearchParams, _ obs: Observation) {
    for ident in obs.identifier ?? [] {
        let v = ident.value?.value?.string ?? ""
        let s = ident.system?.value?.url.absoluteString
        p.tokens.append(.init(paramName: "identifier", system: s, code: v))
    }
}

// method [token] — Observation.method
private func extract_Observation_method(_ p: inout SearchParams, _ obs: Observation) {
    for coding in obs.method?.coding ?? [] {
        let c = coding.code?.value?.string ?? ""
        let s = coding.system?.value?.url.absoluteString
        p.tokens.append(.init(paramName: "method", system: s, code: c))
    }
}

// part-of [reference] — Observation.partOf
private func extract_Observation_part_of(_ p: inout SearchParams, _ obs: Observation) {
    for ref in obs.partOf ?? [] {
        guard let refStr = ref.reference?.value?.string else { continue }
        let parts = refStr.split(separator: "/")
        let (refType, refId): (String?, String) = parts.count == 2
            ? (String(parts[0]), String(parts[1]))
            : (nil, refStr)
        p.references.append(.init(paramName: "part-of", refType: refType, refId: refId))
    }
}

// patient [reference] — Observation.subject
private func extract_Observation_patient(_ p: inout SearchParams, _ obs: Observation) {
    guard let refStr = obs.subject?.reference?.value?.string else { return }
    let parts = refStr.split(separator: "/")
    let (refType, refId): (String?, String) = parts.count == 2
        ? (String(parts[0]), String(parts[1]))
        : (nil, refStr)
    p.references.append(.init(paramName: "patient", refType: refType, refId: refId))
}

// performer [reference] — Observation.performer
private func extract_Observation_performer(_ p: inout SearchParams, _ obs: Observation) {
    for ref in obs.performer ?? [] {
        guard let refStr = ref.reference?.value?.string else { continue }
        let parts = refStr.split(separator: "/")
        let (refType, refId): (String?, String) = parts.count == 2
            ? (String(parts[0]), String(parts[1]))
            : (nil, refStr)
        p.references.append(.init(paramName: "performer", refType: refType, refId: refId))
    }
}

// specimen [reference] — Observation.specimen
private func extract_Observation_specimen(_ p: inout SearchParams, _ obs: Observation) {
    guard let refStr = obs.specimen?.reference?.value?.string else { return }
    let parts = refStr.split(separator: "/")
    let (refType, refId): (String?, String) = parts.count == 2
        ? (String(parts[0]), String(parts[1]))
        : (nil, refStr)
    p.references.append(.init(paramName: "specimen", refType: refType, refId: refId))
}

// status [token] — Observation.status
private func extract_Observation_status(_ p: inout SearchParams, _ obs: Observation) {
    if let v = obs.status.value?.rawValue {
        p.tokens.append(.init(paramName: "status",
                              system: "http://hl7.org/fhir/observation-status", code: v))
    }
}

// subject [reference] — Observation.subject
private func extract_Observation_subject(_ p: inout SearchParams, _ obs: Observation) {
    guard let refStr = obs.subject?.reference?.value?.string else { return }
    let parts = refStr.split(separator: "/")
    let (refType, refId): (String?, String) = parts.count == 2
        ? (String(parts[0]), String(parts[1]))
        : (nil, refStr)
    p.references.append(.init(paramName: "subject", refType: refType, refId: refId))
}

// value-concept [token] — Observation.value
private func extract_Observation_value_concept(_ p: inout SearchParams, _ obs: Observation) {
    guard case .codeableConcept(let cc) = obs.value else { return }
    for coding in cc.coding ?? [] {
        let c = coding.code?.value?.string ?? ""
        let s = coding.system?.value?.url.absoluteString
        p.tokens.append(.init(paramName: "value-concept", system: s, code: c))
    }
}

// value-date [date] — Observation.value
private func extract_Observation_value_date(_ p: inout SearchParams, _ obs: Observation) {
    guard case .dateTime(let prim) = obs.value, let dt = prim.value else { return }
    let cal = Calendar(identifier: .gregorian)
    var dc = DateComponents()
    dc.year = dt.date.year; dc.month = dt.date.month.map(Int.init)
    dc.day  = dt.date.day.map(Int.init); dc.hour = 12
    dc.timeZone = dt.timeZone
    let date = cal.date(from: dc) ?? Date()
    p.dates.append(.init(paramName: "value-date", dateStart: date, dateEnd: date))
}

// value-quantity [quantity] — Observation.value
private func extract_Observation_value_quantity(_ p: inout SearchParams, _ obs: Observation) {
    guard case .quantity(let q) = obs.value else { return }
    guard let decimalVal = q.value?.value?.decimal else { return }
    let sys  = q.system?.value?.url.absoluteString
    let unit = q.code?.value?.string
    p.quantities.append(.init(paramName: "value-quantity", system: sys, code: unit,
                              value: Decimal(string: decimalVal.description) ?? 0))
}

// value-string [string] — Observation.value
private func extract_Observation_value_string(_ p: inout SearchParams, _ obs: Observation) {
    guard case .string(let prim) = obs.value, let s = prim.value?.string else { return }
    p.strings.append(.init(paramName: "value-string", value: s))
}