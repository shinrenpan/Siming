// GENERATED — do not edit directly.
// Source: packages/*.tgz (hl7.fhir.r4.core + tw.gov.mohw.twcore)
// Regenerate: swift run SimingGenerator

import Foundation
import ModelsR4

/// Extracts all supported search parameters from a Task for insertion
/// into the five idx_* index tables.
///
/// Params marked TODO are recognised by the FHIR R4 spec but not yet implemented.
public func extractTaskSearchParams(_ t: ModelsR4.Task) -> SearchParams {
    var p = SearchParams()
    extract_Task_authored_on(&p, t)
    extract_Task_based_on(&p, t)
    extract_Task_business_status(&p, t)
    extract_Task_code(&p, t)
    extract_Task_encounter(&p, t)
    extract_Task_focus(&p, t)
    extract_Task_group_identifier(&p, t)
    extract_Task_identifier(&p, t)
    extract_Task_intent(&p, t)
    extract_Task_modified(&p, t)
    extract_Task_owner(&p, t)
    extract_Task_part_of(&p, t)
    extract_Task_patient(&p, t)
    extract_Task_performer(&p, t)
    extract_Task_period(&p, t)
    extract_Task_priority(&p, t)
    extract_Task_requester(&p, t)
    extract_Task_status(&p, t)
    extract_Task_subject(&p, t)
    return p
}

// authored-on [date] — Task.authoredOn
private func extract_Task_authored_on(_ p: inout SearchParams, _ t: ModelsR4.Task) {
    guard let prim = t.authoredOn, let dt = prim.value else { return }
    let cal = Calendar(identifier: .gregorian)
    var dc = DateComponents()
    dc.year = dt.date.year; dc.month = dt.date.month.map(Int.init)
    dc.day  = dt.date.day.map(Int.init)
    // A dateTime carrying a time keeps it; a date-only value stays anchored at
    // midday so it sits well inside the day whatever offset it is compared against.
    // The zone must be explicit — falling through to the host's zone makes the
    // stored value depend on where the server happens to run.
    dc.hour   = dt.time.map { Int($0.hour) } ?? 12
    dc.minute = dt.time.map { Int($0.minute) } ?? 0
    dc.second = dt.time.map { min(Int(truncating: $0.second as NSDecimalNumber), 59) } ?? 0
    dc.timeZone = dt.timeZone ?? TimeZone(secondsFromGMT: 0)
    let d = cal.date(from: dc) ?? Date()
    p.dates.append(.init(paramName: "authored-on", dateStart: d, dateEnd: d))
}

// based-on [reference] — Task.basedOn
private func extract_Task_based_on(_ p: inout SearchParams, _ t: ModelsR4.Task) {
    for ref in t.basedOn ?? [] {
        guard let refStr = ref.reference?.value?.string else { continue }
        let parts = refStr.split(separator: "/")
        let (refType, refId): (String?, String) = parts.count == 2
            ? (String(parts[0]), String(parts[1]))
            : (nil, refStr)
        p.references.append(.init(paramName: "based-on", refType: refType, refId: refId))
    }
}

// business-status [token] — Task.businessStatus
private func extract_Task_business_status(_ p: inout SearchParams, _ t: ModelsR4.Task) {
    for coding in t.businessStatus?.coding ?? [] {
        let c = coding.code?.value?.string ?? ""
        let s = coding.system?.value?.url.absoluteString
        p.appendToken(paramName: "business-status", system: s, code: c, display: coding.display?.value?.string)
    }
}

// code [token] — Task.code
private func extract_Task_code(_ p: inout SearchParams, _ t: ModelsR4.Task) {
    for coding in t.code?.coding ?? [] {
        let c = coding.code?.value?.string ?? ""
        let s = coding.system?.value?.url.absoluteString
        p.appendToken(paramName: "code", system: s, code: c, display: coding.display?.value?.string)
    }
}

// encounter [reference] — Task.encounter
private func extract_Task_encounter(_ p: inout SearchParams, _ t: ModelsR4.Task) {
    guard let refStr = t.encounter?.reference?.value?.string else { return }
    let parts = refStr.split(separator: "/")
    let (refType, refId): (String?, String) = parts.count == 2
        ? (String(parts[0]), String(parts[1]))
        : (nil, refStr)
    p.references.append(.init(paramName: "encounter", refType: refType, refId: refId))
}

// focus [reference] — Task.focus
private func extract_Task_focus(_ p: inout SearchParams, _ t: ModelsR4.Task) {
    guard let refStr = t.focus?.reference?.value?.string else { return }
    let parts = refStr.split(separator: "/")
    let (refType, refId): (String?, String) = parts.count == 2
        ? (String(parts[0]), String(parts[1]))
        : (nil, refStr)
    p.references.append(.init(paramName: "focus", refType: refType, refId: refId))
}

// group-identifier [token] — Task.groupIdentifier
private func extract_Task_group_identifier(_ p: inout SearchParams, _ t: ModelsR4.Task) {
    guard let ident = t.groupIdentifier else { return }
    let v = ident.value?.value?.string ?? ""
    let s = ident.system?.value?.url.absoluteString
    p.tokens.append(.init(paramName: "group-identifier", system: s, code: v))
}

// identifier [token] — Task.identifier
private func extract_Task_identifier(_ p: inout SearchParams, _ t: ModelsR4.Task) {
    for ident in t.identifier ?? [] {
        let v = ident.value?.value?.string ?? ""
        let s = ident.system?.value?.url.absoluteString
        p.tokens.append(.init(paramName: "identifier", system: s, code: v))
    }
}

// intent [token] — Task.intent
private func extract_Task_intent(_ p: inout SearchParams, _ t: ModelsR4.Task) {
    if let v = t.intent.value?.string {
        p.tokens.append(.init(paramName: "intent",
                              system: "http://hl7.org/fhir/task-intent", code: v))
    }
}

// modified [date] — Task.lastModified
private func extract_Task_modified(_ p: inout SearchParams, _ t: ModelsR4.Task) {
    guard let prim = t.lastModified, let dt = prim.value else { return }
    let cal = Calendar(identifier: .gregorian)
    var dc = DateComponents()
    dc.year = dt.date.year; dc.month = dt.date.month.map(Int.init)
    dc.day  = dt.date.day.map(Int.init)
    // A dateTime carrying a time keeps it; a date-only value stays anchored at
    // midday so it sits well inside the day whatever offset it is compared against.
    // The zone must be explicit — falling through to the host's zone makes the
    // stored value depend on where the server happens to run.
    dc.hour   = dt.time.map { Int($0.hour) } ?? 12
    dc.minute = dt.time.map { Int($0.minute) } ?? 0
    dc.second = dt.time.map { min(Int(truncating: $0.second as NSDecimalNumber), 59) } ?? 0
    dc.timeZone = dt.timeZone ?? TimeZone(secondsFromGMT: 0)
    let d = cal.date(from: dc) ?? Date()
    p.dates.append(.init(paramName: "modified", dateStart: d, dateEnd: d))
}

// owner [reference] — Task.owner
private func extract_Task_owner(_ p: inout SearchParams, _ t: ModelsR4.Task) {
    guard let refStr = t.owner?.reference?.value?.string else { return }
    let parts = refStr.split(separator: "/")
    let (refType, refId): (String?, String) = parts.count == 2
        ? (String(parts[0]), String(parts[1]))
        : (nil, refStr)
    p.references.append(.init(paramName: "owner", refType: refType, refId: refId))
}

// part-of [reference] — Task.partOf
private func extract_Task_part_of(_ p: inout SearchParams, _ t: ModelsR4.Task) {
    for ref in t.partOf ?? [] {
        guard let refStr = ref.reference?.value?.string else { continue }
        let parts = refStr.split(separator: "/")
        let (refType, refId): (String?, String) = parts.count == 2
            ? (String(parts[0]), String(parts[1]))
            : (nil, refStr)
        p.references.append(.init(paramName: "part-of", refType: refType, refId: refId))
    }
}

// patient [reference] — Task.for
private func extract_Task_patient(_ p: inout SearchParams, _ t: ModelsR4.Task) {
    guard let refStr = t.`for`?.reference?.value?.string else { return }
    let parts = refStr.split(separator: "/")
    guard parts.count == 2, parts[0] == "Patient" else { return }
    p.references.append(.init(paramName: "patient", refType: "Patient", refId: String(parts[1])))
}

// performer [token] — Task.performerType
private func extract_Task_performer(_ p: inout SearchParams, _ t: ModelsR4.Task) {
    for cc in t.performerType ?? [] {
        for coding in cc.coding ?? [] {
            let c = coding.code?.value?.string ?? ""
            let s = coding.system?.value?.url.absoluteString
            p.appendToken(paramName: "performer", system: s, code: c, display: coding.display?.value?.string)
        }
    }
}

// period [date] — Task.executionPeriod
private func extract_Task_period(_ p: inout SearchParams, _ t: ModelsR4.Task) {
    guard let period = t.executionPeriod else { return }
    let cal = Calendar(identifier: .gregorian)
    let start: Date
    let end: Date
    if let prim = period.start, let dt = prim.value {
        var dc = DateComponents()
        dc.year = dt.date.year; dc.month = dt.date.month.map(Int.init)
        dc.day  = dt.date.day.map(Int.init)
        // A date-only bound widens to the start of the day; one carrying a time keeps it.
        // dc.timeZone is mandatory: without it the components are read in
        // the server's local zone and every indexed period shifts by the
        // host's UTC offset — right in a UTC container, wrong anywhere else.
        dc.hour   = dt.time.map { Int($0.hour) } ?? 0
        dc.minute = dt.time.map { Int($0.minute) } ?? 0
        dc.second = dt.time.map { min(Int(truncating: $0.second as NSDecimalNumber), 59) } ?? 0
        dc.timeZone = dt.timeZone ?? TimeZone(secondsFromGMT: 0)
        start = cal.date(from: dc) ?? Date.distantPast
    } else { start = Date.distantPast }
    if let prim = period.end, let dt = prim.value {
        var dc = DateComponents()
        dc.year = dt.date.year; dc.month = dt.date.month.map(Int.init)
        dc.day  = dt.date.day.map(Int.init)
        // A date-only bound widens to the end of the day; one carrying a time keeps it.
        // dc.timeZone is mandatory: without it the components are read in
        // the server's local zone and every indexed period shifts by the
        // host's UTC offset — right in a UTC container, wrong anywhere else.
        dc.hour   = dt.time.map { Int($0.hour) } ?? 23
        dc.minute = dt.time.map { Int($0.minute) } ?? 59
        dc.second = dt.time.map { min(Int(truncating: $0.second as NSDecimalNumber), 59) } ?? 59
        dc.timeZone = dt.timeZone ?? TimeZone(secondsFromGMT: 0)
        end = cal.date(from: dc) ?? Date.distantFuture
    } else { end = Date.distantFuture }
    p.dates.append(.init(paramName: "period", dateStart: start, dateEnd: end))
}

// priority [token] — Task.priority
private func extract_Task_priority(_ p: inout SearchParams, _ t: ModelsR4.Task) {
    if let v = t.priority?.value?.rawValue {
        p.tokens.append(.init(paramName: "priority",
                              system: "http://hl7.org/fhir/request-priority", code: v))
    }
}

// requester [reference] — Task.requester
private func extract_Task_requester(_ p: inout SearchParams, _ t: ModelsR4.Task) {
    guard let refStr = t.requester?.reference?.value?.string else { return }
    let parts = refStr.split(separator: "/")
    let (refType, refId): (String?, String) = parts.count == 2
        ? (String(parts[0]), String(parts[1]))
        : (nil, refStr)
    p.references.append(.init(paramName: "requester", refType: refType, refId: refId))
}

// status [token] — Task.status
private func extract_Task_status(_ p: inout SearchParams, _ t: ModelsR4.Task) {
    if let v = t.status.value?.rawValue {
        p.tokens.append(.init(paramName: "status",
                              system: "http://hl7.org/fhir/task-status", code: v))
    }
}

// subject [reference] — Task.for
private func extract_Task_subject(_ p: inout SearchParams, _ t: ModelsR4.Task) {
    guard let refStr = t.`for`?.reference?.value?.string else { return }
    let parts = refStr.split(separator: "/")
    let (refType, refId): (String?, String) = parts.count == 2
        ? (String(parts[0]), String(parts[1]))
        : (nil, refStr)
    p.references.append(.init(paramName: "subject", refType: refType, refId: refId))
}