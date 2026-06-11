// GENERATED — do not edit directly.
// Source: packages/*.tgz (hl7.fhir.r4.core + tw.gov.mohw.twcore)
// Regenerate: swift run SimingGenerator

import Foundation
import ModelsR4

/// Extracts all supported search parameters from a Goal for insertion
/// into the five idx_* index tables.
///
/// Params marked TODO are recognised by the FHIR R4 spec but not yet implemented.
public func extractGoalSearchParams(_ g: Goal) -> SearchParams {
    var p = SearchParams()
    extract_Goal_achievement_status(&p, g)
    extract_Goal_category(&p, g)
    extract_Goal_description(&p, g)
    extract_Goal_identifier(&p, g)
    extract_Goal_lifecycle_status(&p, g)
    extract_Goal_patient(&p, g)
    extract_Goal_start_date(&p, g)
    extract_Goal_subject(&p, g)
    extract_Goal_target_date(&p, g)
    return p
}

// achievement-status [token] — Goal.achievementStatus
private func extract_Goal_achievement_status(_ p: inout SearchParams, _ g: Goal) {
    for coding in g.achievementStatus?.coding ?? [] {
        let v = coding.code?.value?.string ?? ""
        let sys = coding.system?.value?.url.absoluteString
        p.tokens.append(.init(paramName: "achievement-status", system: sys, code: v))
    }
}

// category [token] — Goal.category
private func extract_Goal_category(_ p: inout SearchParams, _ g: Goal) {
    for cc in g.category ?? [] {
        for coding in cc.coding ?? [] {
            let v = coding.code?.value?.string ?? ""
            let sys = coding.system?.value?.url.absoluteString
            p.tokens.append(.init(paramName: "category", system: sys, code: v))
        }
    }
}

// description [token] — Goal.description
private func extract_Goal_description(_ p: inout SearchParams, _ g: Goal) {
    for coding in g.description_fhir.coding ?? [] {
        let v = coding.code?.value?.string ?? ""
        let sys = coding.system?.value?.url.absoluteString
        p.tokens.append(.init(paramName: "description", system: sys, code: v))
    }
    if let text = g.description_fhir.text?.value?.string {
        p.tokens.append(.init(paramName: "description", system: nil, code: text))
    }
}

// identifier [token] — Goal.identifier
private func extract_Goal_identifier(_ p: inout SearchParams, _ g: Goal) {
    for ident in g.identifier ?? [] {
        let v = ident.value?.value?.string ?? ""
        let sys = ident.system?.value?.url.absoluteString
        p.tokens.append(.init(paramName: "identifier", system: sys, code: v))
    }
}

// lifecycle-status [token] — Goal.lifecycleStatus
private func extract_Goal_lifecycle_status(_ p: inout SearchParams, _ g: Goal) {
    if let v = g.lifecycleStatus.value?.rawValue {
        p.tokens.append(.init(paramName: "lifecycle-status",
                              system: "http://hl7.org/fhir/goal-status", code: v))
    }
}

// patient [reference] — Goal.subject
private func extract_Goal_patient(_ p: inout SearchParams, _ g: Goal) {
    guard let refStr = g.subject.reference?.value?.string else { return }
    let parts = refStr.split(separator: "/")
    let (refType, refId): (String?, String) = parts.count == 2
        ? (String(parts[0]), String(parts[1]))
        : (nil, refStr)
    p.references.append(.init(paramName: "patient", refType: refType, refId: refId))
}

// start-date [date] — Goal.start
private func extract_Goal_start_date(_ p: inout SearchParams, _ g: Goal) {
    guard let startX = g.start, case .date(let prim) = startX,
          let dt = prim.value else { return }
    let cal = Calendar(identifier: .gregorian)
    var dc = DateComponents()
    dc.year = dt.year; dc.month = dt.month.map(Int.init)
    dc.day  = dt.day.map(Int.init); dc.hour = 12
    let date = cal.date(from: dc) ?? Date()
    p.dates.append(.init(paramName: "start-date", dateStart: date, dateEnd: date))
}

// subject [reference] — Goal.subject
private func extract_Goal_subject(_ p: inout SearchParams, _ g: Goal) {
    guard let refStr = g.subject.reference?.value?.string else { return }
    let parts = refStr.split(separator: "/")
    let (refType, refId): (String?, String) = parts.count == 2
        ? (String(parts[0]), String(parts[1]))
        : (nil, refStr)
    p.references.append(.init(paramName: "subject", refType: refType, refId: refId))
}

// target-date [date] — Goal.target.due.ofType(date))
private func extract_Goal_target_date(_ p: inout SearchParams, _ g: Goal) {
    let cal = Calendar(identifier: .gregorian)
    for target in g.target ?? [] {
        guard let dueX = target.due, case .date(let prim) = dueX,
              let dt = prim.value else { continue }
        var dc = DateComponents()
        dc.year = dt.year; dc.month = dt.month.map(Int.init)
        dc.day  = dt.day.map(Int.init); dc.hour = 12
        let date = cal.date(from: dc) ?? Date()
        p.dates.append(.init(paramName: "target-date", dateStart: date, dateEnd: date))
    }
}