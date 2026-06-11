// GENERATED — do not edit directly.
// Source: packages/*.tgz (hl7.fhir.r4.core + tw.gov.mohw.twcore)
// Regenerate: swift run SimingGenerator

import Foundation
import ModelsR4

/// Extracts all supported search parameters from a MedicationAdministration for insertion
/// into the five idx_* index tables.
public func extractMedicationAdministrationSearchParams(_ ma: MedicationAdministration) -> SearchParams {
    var p = SearchParams()
    extract_MedicationAdministration_code(&p, ma)
    extract_MedicationAdministration_context(&p, ma)
    extract_MedicationAdministration_device(&p, ma)
    extract_MedicationAdministration_effective_time(&p, ma)
    extract_MedicationAdministration_identifier(&p, ma)
    extract_MedicationAdministration_medication(&p, ma)
    extract_MedicationAdministration_patient(&p, ma)
    extract_MedicationAdministration_performer(&p, ma)
    extract_MedicationAdministration_reason_given(&p, ma)
    extract_MedicationAdministration_reason_not_given(&p, ma)
    extract_MedicationAdministration_request(&p, ma)
    extract_MedicationAdministration_status(&p, ma)
    extract_MedicationAdministration_subject(&p, ma)
    return p
}

// code [token] — MedicationAdministration.medication
private func extract_MedicationAdministration_code(_ p: inout SearchParams, _ ma: MedicationAdministration) {
    guard case .codeableConcept(let cc) = ma.medication else { return }
    for coding in cc.coding ?? [] {
        let v = coding.code?.value?.string ?? ""
        let s = coding.system?.value?.url.absoluteString
        p.tokens.append(.init(paramName: "code", system: s, code: v))
    }
}

// context [reference] — MedicationAdministration.context
private func extract_MedicationAdministration_context(_ p: inout SearchParams, _ ma: MedicationAdministration) {
    guard let refStr = ma.context?.reference?.value?.string else { return }
    let parts = refStr.split(separator: "/")
    let (refType, refId): (String?, String) = parts.count == 2
        ? (String(parts[0]), String(parts[1]))
        : (nil, refStr)
    p.references.append(.init(paramName: "context", refType: refType, refId: refId))
}

// device [reference] — MedicationAdministration.device
private func extract_MedicationAdministration_device(_ p: inout SearchParams, _ ma: MedicationAdministration) {
    for ref in ma.device ?? [] {
        guard let refStr = ref.reference?.value?.string else { continue }
        let parts = refStr.split(separator: "/")
        let (refType, refId): (String?, String) = parts.count == 2
            ? (String(parts[0]), String(parts[1]))
            : (nil, refStr)
        p.references.append(.init(paramName: "device", refType: refType, refId: refId))
    }
}

// effective-time [date] — MedicationAdministration.effective
private func extract_MedicationAdministration_effective_time(_ p: inout SearchParams, _ ma: MedicationAdministration) {
    switch ma.effective {
    case .dateTime(let prim):
        guard let dt = prim.value else { return }
        var dc = DateComponents()
        dc.year = dt.date.year; dc.month = dt.date.month.map(Int.init)
        dc.day  = dt.date.day.map(Int.init); dc.hour = 12
        dc.timeZone = dt.timeZone
        let d = Calendar(identifier: .gregorian).date(from: dc) ?? Date()
        p.dates.append(.init(paramName: "effective-time", dateStart: d, dateEnd: d))
    case .period(let period):
        let cal = Calendar(identifier: .gregorian)
        var startDC = DateComponents(); var endDC = DateComponents()
        if let startStr = period.start?.value {
            startDC.year = startStr.date.year; startDC.month = startStr.date.month.map(Int.init)
            startDC.day  = startStr.date.day.map(Int.init); startDC.hour = 0
            startDC.timeZone = startStr.timeZone
        }
        if let endStr = period.end?.value {
            endDC.year = endStr.date.year; endDC.month = endStr.date.month.map(Int.init)
            endDC.day  = endStr.date.day.map(Int.init); endDC.hour = 23
            endDC.timeZone = endStr.timeZone
        }
        let dateStart = cal.date(from: startDC) ?? Date.distantPast
        let dateEnd   = cal.date(from: endDC)   ?? Date.distantFuture
        p.dates.append(.init(paramName: "effective-time", dateStart: dateStart, dateEnd: dateEnd))
    }
}

// identifier [token] — MedicationAdministration.identifier
private func extract_MedicationAdministration_identifier(_ p: inout SearchParams, _ ma: MedicationAdministration) {
    for ident in ma.identifier ?? [] {
        let v = ident.value?.value?.string ?? ""
        let s = ident.system?.value?.url.absoluteString
        p.tokens.append(.init(paramName: "identifier", system: s, code: v))
    }
}

// medication [reference] — MedicationAdministration.medication
private func extract_MedicationAdministration_medication(_ p: inout SearchParams, _ ma: MedicationAdministration) {
    guard case .reference(let ref) = ma.medication,
          let refStr = ref.reference?.value?.string else { return }
    let parts = refStr.split(separator: "/")
    let (refType, refId): (String?, String) = parts.count == 2
        ? (String(parts[0]), String(parts[1]))
        : (nil, refStr)
    p.references.append(.init(paramName: "medication", refType: refType, refId: refId))
}

// patient [reference] — MedicationAdministration.subject
private func extract_MedicationAdministration_patient(_ p: inout SearchParams, _ ma: MedicationAdministration) {
    guard let refStr = ma.subject.reference?.value?.string else { return }
    let parts = refStr.split(separator: "/")
    let (refType, refId): (String?, String) = parts.count == 2
        ? (String(parts[0]), String(parts[1]))
        : (nil, refStr)
    p.references.append(.init(paramName: "patient", refType: refType, refId: refId))
}

// performer [reference] — MedicationAdministration.performer.actor
private func extract_MedicationAdministration_performer(_ p: inout SearchParams, _ ma: MedicationAdministration) {
    for perf in ma.performer ?? [] {
        guard let refStr = perf.actor.reference?.value?.string else { continue }
        let parts = refStr.split(separator: "/")
        let (refType, refId): (String?, String) = parts.count == 2
            ? (String(parts[0]), String(parts[1]))
            : (nil, refStr)
        p.references.append(.init(paramName: "performer", refType: refType, refId: refId))
    }
}

// reason-given [token] — MedicationAdministration.reasonCode
private func extract_MedicationAdministration_reason_given(_ p: inout SearchParams, _ ma: MedicationAdministration) {
    for cc in ma.reasonCode ?? [] {
        for coding in cc.coding ?? [] {
            let v = coding.code?.value?.string ?? ""
            let s = coding.system?.value?.url.absoluteString
            p.tokens.append(.init(paramName: "reason-given", system: s, code: v))
        }
    }
}

// reason-not-given [token] — MedicationAdministration.statusReason
private func extract_MedicationAdministration_reason_not_given(_ p: inout SearchParams, _ ma: MedicationAdministration) {
    for cc in ma.statusReason ?? [] {
        for coding in cc.coding ?? [] {
            let v = coding.code?.value?.string ?? ""
            let s = coding.system?.value?.url.absoluteString
            p.tokens.append(.init(paramName: "reason-not-given", system: s, code: v))
        }
    }
}

// request [reference] — MedicationAdministration.request
private func extract_MedicationAdministration_request(_ p: inout SearchParams, _ ma: MedicationAdministration) {
    guard let refStr = ma.request?.reference?.value?.string else { return }
    let parts = refStr.split(separator: "/")
    let (refType, refId): (String?, String) = parts.count == 2
        ? (String(parts[0]), String(parts[1]))
        : (nil, refStr)
    p.references.append(.init(paramName: "request", refType: refType, refId: refId))
}

// status [token] — MedicationAdministration.status
private func extract_MedicationAdministration_status(_ p: inout SearchParams, _ ma: MedicationAdministration) {
    if let v = ma.status.value?.rawValue {
        p.tokens.append(.init(paramName: "status", system: nil, code: v))
    }
}

// subject [reference] — MedicationAdministration.subject
private func extract_MedicationAdministration_subject(_ p: inout SearchParams, _ ma: MedicationAdministration) {
    guard let refStr = ma.subject.reference?.value?.string else { return }
    let parts = refStr.split(separator: "/")
    let (refType, refId): (String?, String) = parts.count == 2
        ? (String(parts[0]), String(parts[1]))
        : (nil, refStr)
    p.references.append(.init(paramName: "subject", refType: refType, refId: refId))
}