// GENERATED — do not edit directly.
// Source: packages/*.tgz (hl7.fhir.r4.core + tw.gov.mohw.twcore)
// Regenerate: swift run SimingGenerator

import Foundation
import ModelsR4

/// Extracts all supported search parameters from a CarePlan for insertion
/// into the five idx_* index tables.
///
/// Params marked TODO are recognised by the FHIR R4 spec but not yet implemented.
public func extractCarePlanSearchParams(_ c: CarePlan) -> SearchParams {
    var p = SearchParams()
    extract_CarePlan_activity_code(&p, c)
    extract_CarePlan_activity_date(&p, c)
    extract_CarePlan_activity_reference(&p, c)
    extract_CarePlan_based_on(&p, c)
    extract_CarePlan_care_team(&p, c)
    extract_CarePlan_category(&p, c)
    extract_CarePlan_condition(&p, c)
    extract_CarePlan_date(&p, c)
    extract_CarePlan_encounter(&p, c)
    extract_CarePlan_goal(&p, c)
    extract_CarePlan_identifier(&p, c)
    extract_CarePlan_instantiates_canonical(&p, c)
    extract_CarePlan_instantiates_uri(&p, c)
    extract_CarePlan_intent(&p, c)
    extract_CarePlan_part_of(&p, c)
    extract_CarePlan_patient(&p, c)
    extract_CarePlan_performer(&p, c)
    extract_CarePlan_replaces(&p, c)
    extract_CarePlan_status(&p, c)
    extract_CarePlan_subject(&p, c)
    return p
}

// activity-code [token] — CarePlan.activity.detail.code
private func extract_CarePlan_activity_code(_ p: inout SearchParams, _ c: CarePlan) {
    for act in c.activity ?? [] {
        for coding in act.detail?.code?.coding ?? [] {
            let v = coding.code?.value?.string ?? ""
            let sys = coding.system?.value?.url.absoluteString
            p.tokens.append(.init(paramName: "activity-code", system: sys, code: v))
        }
    }
}

// activity-date [date] — CarePlan.activity.detail.scheduled
private func extract_CarePlan_activity_date(_ p: inout SearchParams, _ c: CarePlan) {
    let cal = Calendar(identifier: .gregorian)
    for act in c.activity ?? [] {
        guard let sched = act.detail?.scheduled else { continue }
        switch sched {
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
            p.dates.append(.init(paramName: "activity-date", dateStart: start, dateEnd: end))
        case .timing(let timing):
            for evt in timing.event ?? [] {
                guard let dt = evt.value else { continue }
                var dc = DateComponents()
                dc.year = dt.date.year; dc.month = dt.date.month.map(Int.init)
                dc.day  = dt.date.day.map(Int.init); dc.hour = 0
                let d = cal.date(from: dc) ?? Date()
                p.dates.append(.init(paramName: "activity-date", dateStart: d, dateEnd: d))
            }
        case .string:
            break
        }
    }
}

// activity-reference [reference] — CarePlan.activity.reference
private func extract_CarePlan_activity_reference(_ p: inout SearchParams, _ c: CarePlan) {
    for act in c.activity ?? [] {
        guard let refStr = act.reference?.reference?.value?.string else { continue }
        let parts = refStr.split(separator: "/")
        let (refType, refId): (String?, String) = parts.count == 2
            ? (String(parts[0]), String(parts[1]))
            : (nil, refStr)
        p.references.append(.init(paramName: "activity-reference", refType: refType, refId: refId))
    }
}

// based-on [reference] — CarePlan.basedOn
private func extract_CarePlan_based_on(_ p: inout SearchParams, _ c: CarePlan) {
    for ref in c.basedOn ?? [] {
        guard let refStr = ref.reference?.value?.string else { continue }
        let parts = refStr.split(separator: "/")
        let (refType, refId): (String?, String) = parts.count == 2
            ? (String(parts[0]), String(parts[1]))
            : (nil, refStr)
        p.references.append(.init(paramName: "based-on", refType: refType, refId: refId))
    }
}

// care-team [reference] — CarePlan.careTeam
private func extract_CarePlan_care_team(_ p: inout SearchParams, _ c: CarePlan) {
    for ref in c.careTeam ?? [] {
        guard let refStr = ref.reference?.value?.string else { continue }
        let parts = refStr.split(separator: "/")
        let (refType, refId): (String?, String) = parts.count == 2
            ? (String(parts[0]), String(parts[1]))
            : (nil, refStr)
        p.references.append(.init(paramName: "care-team", refType: refType, refId: refId))
    }
}

// category [token] — CarePlan.category
private func extract_CarePlan_category(_ p: inout SearchParams, _ c: CarePlan) {
    for cc in c.category ?? [] {
        for coding in cc.coding ?? [] {
            let v = coding.code?.value?.string ?? ""
            let sys = coding.system?.value?.url.absoluteString
            p.tokens.append(.init(paramName: "category", system: sys, code: v))
        }
    }
}

// condition [reference] — CarePlan.addresses
private func extract_CarePlan_condition(_ p: inout SearchParams, _ c: CarePlan) {
    for ref in c.addresses ?? [] {
        guard let refStr = ref.reference?.value?.string else { continue }
        let parts = refStr.split(separator: "/")
        let (refType, refId): (String?, String) = parts.count == 2
            ? (String(parts[0]), String(parts[1]))
            : (nil, refStr)
        p.references.append(.init(paramName: "condition", refType: refType, refId: refId))
    }
}

// date [date] — CarePlan.period
private func extract_CarePlan_date(_ p: inout SearchParams, _ c: CarePlan) {
    guard let period = c.period else { return }
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
    p.dates.append(.init(paramName: "date", dateStart: start, dateEnd: end))
}

// encounter [reference] — CarePlan.encounter
private func extract_CarePlan_encounter(_ p: inout SearchParams, _ c: CarePlan) {
    guard let refStr = c.encounter?.reference?.value?.string else { return }
    let parts = refStr.split(separator: "/")
    let (refType, refId): (String?, String) = parts.count == 2
        ? (String(parts[0]), String(parts[1]))
        : (nil, refStr)
    p.references.append(.init(paramName: "encounter", refType: refType, refId: refId))
}

// goal [reference] — CarePlan.goal
private func extract_CarePlan_goal(_ p: inout SearchParams, _ c: CarePlan) {
    for ref in c.goal ?? [] {
        guard let refStr = ref.reference?.value?.string else { continue }
        let parts = refStr.split(separator: "/")
        let (refType, refId): (String?, String) = parts.count == 2
            ? (String(parts[0]), String(parts[1]))
            : (nil, refStr)
        p.references.append(.init(paramName: "goal", refType: refType, refId: refId))
    }
}

// identifier [token] — CarePlan.identifier
private func extract_CarePlan_identifier(_ p: inout SearchParams, _ c: CarePlan) {
    for ident in c.identifier ?? [] {
        let v = ident.value?.value?.string ?? ""
        let sys = ident.system?.value?.url.absoluteString
        p.tokens.append(.init(paramName: "identifier", system: sys, code: v))
    }
}

// instantiates-canonical [reference] — CarePlan.instantiatesCanonical
private func extract_CarePlan_instantiates_canonical(_ p: inout SearchParams, _ c: CarePlan) {
    for ic in c.instantiatesCanonical ?? [] {
        guard let url = ic.value?.url.absoluteString else { continue }
        p.strings.append(.init(paramName: "instantiates-canonical", value: url))
    }
}

// instantiates-uri [uri] — CarePlan.instantiatesUri
private func extract_CarePlan_instantiates_uri(_ p: inout SearchParams, _ c: CarePlan) {
    for iu in c.instantiatesUri ?? [] {
        guard let url = iu.value?.url.absoluteString else { continue }
        p.strings.append(.init(paramName: "instantiates-uri", value: url))
    }
}

// intent [token] — CarePlan.intent
private func extract_CarePlan_intent(_ p: inout SearchParams, _ c: CarePlan) {
    if let v = c.intent.value?.rawValue {
        p.tokens.append(.init(paramName: "intent",
                              system: "http://hl7.org/fhir/request-intent", code: v))
    }
}

// part-of [reference] — CarePlan.partOf
private func extract_CarePlan_part_of(_ p: inout SearchParams, _ c: CarePlan) {
    for ref in c.partOf ?? [] {
        guard let refStr = ref.reference?.value?.string else { continue }
        let parts = refStr.split(separator: "/")
        let (refType, refId): (String?, String) = parts.count == 2
            ? (String(parts[0]), String(parts[1]))
            : (nil, refStr)
        p.references.append(.init(paramName: "part-of", refType: refType, refId: refId))
    }
}

// patient [reference] — CarePlan.subject
private func extract_CarePlan_patient(_ p: inout SearchParams, _ c: CarePlan) {
    guard let refStr = c.subject.reference?.value?.string else { return }
    let parts = refStr.split(separator: "/")
    let (refType, refId): (String?, String) = parts.count == 2
        ? (String(parts[0]), String(parts[1]))
        : (nil, refStr)
    p.references.append(.init(paramName: "patient", refType: refType, refId: refId))
}

// performer [reference] — CarePlan.activity.detail.performer
private func extract_CarePlan_performer(_ p: inout SearchParams, _ c: CarePlan) {
    for act in c.activity ?? [] {
        for ref in act.detail?.performer ?? [] {
            guard let refStr = ref.reference?.value?.string else { continue }
            let parts = refStr.split(separator: "/")
            let (refType, refId): (String?, String) = parts.count == 2
                ? (String(parts[0]), String(parts[1]))
                : (nil, refStr)
            p.references.append(.init(paramName: "performer", refType: refType, refId: refId))
        }
    }
}

// replaces [reference] — CarePlan.replaces
private func extract_CarePlan_replaces(_ p: inout SearchParams, _ c: CarePlan) {
    for ref in c.replaces ?? [] {
        guard let refStr = ref.reference?.value?.string else { continue }
        let parts = refStr.split(separator: "/")
        let (refType, refId): (String?, String) = parts.count == 2
            ? (String(parts[0]), String(parts[1]))
            : (nil, refStr)
        p.references.append(.init(paramName: "replaces", refType: refType, refId: refId))
    }
}

// status [token] — CarePlan.status
private func extract_CarePlan_status(_ p: inout SearchParams, _ c: CarePlan) {
    if let v = c.status.value?.rawValue {
        p.tokens.append(.init(paramName: "status",
                              system: "http://hl7.org/fhir/request-status", code: v))
    }
}

// subject [reference] — CarePlan.subject
private func extract_CarePlan_subject(_ p: inout SearchParams, _ c: CarePlan) {
    guard let refStr = c.subject.reference?.value?.string else { return }
    let parts = refStr.split(separator: "/")
    let (refType, refId): (String?, String) = parts.count == 2
        ? (String(parts[0]), String(parts[1]))
        : (nil, refStr)
    p.references.append(.init(paramName: "subject", refType: refType, refId: refId))
}