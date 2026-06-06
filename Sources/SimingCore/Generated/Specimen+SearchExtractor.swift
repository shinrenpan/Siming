// GENERATED — do not edit directly.
// Source: Resources/fhir/search-parameters-r4.json
// Regenerate: swift run SimingGenerator

import Foundation
import ModelsR4

/// Extracts all supported search parameters from a Specimen for insertion
/// into the five idx_* index tables.
///
/// Params marked TODO are recognised by the FHIR R4 spec but not yet implemented.
public func extractSpecimenSearchParams(_ s: Specimen) -> SearchParams {
    var p = SearchParams()
    extract_Specimen_accession(&p, s)
    extract_Specimen_bodysite(&p, s)
    extract_Specimen_collected(&p, s)
    extract_Specimen_collector(&p, s)
    extract_Specimen_container(&p, s)
    extract_Specimen_container_id(&p, s)
    extract_Specimen_identifier(&p, s)
    extract_Specimen_parent(&p, s)
    extract_Specimen_patient(&p, s)
    extract_Specimen_status(&p, s)
    extract_Specimen_subject(&p, s)
    extract_Specimen_type(&p, s)
    return p
}

// accession [token] — Specimen.accessionIdentifier
private func extract_Specimen_accession(_ p: inout SearchParams, _ s: Specimen) {
    guard let ident = s.accessionIdentifier else { return }
    let v = ident.value?.value?.string ?? ""
    let sys = ident.system?.value?.url.absoluteString
    p.tokens.append(.init(paramName: "accession", system: sys, code: v))
}

// bodysite [token] — Specimen.collection.bodySite
private func extract_Specimen_bodysite(_ p: inout SearchParams, _ s: Specimen) {
    for coding in s.collection?.bodySite?.coding ?? [] {
        let c = coding.code?.value?.string ?? ""
        let sys = coding.system?.value?.url.absoluteString
        p.tokens.append(.init(paramName: "bodysite", system: sys, code: c))
    }
}

// collected [date] — Specimen.collection.collected
private func extract_Specimen_collected(_ p: inout SearchParams, _ s: Specimen) {
    let cal = Calendar(identifier: .gregorian)
    guard let coll = s.collection?.collected else { return }
    switch coll {
    case .dateTime(let prim):
        guard let dt = prim.value else { return }
        var dc = DateComponents()
        dc.year = dt.date.year; dc.month = dt.date.month.map(Int.init)
        dc.day  = dt.date.day.map(Int.init); dc.hour = 12
        dc.timeZone = dt.timeZone
        let d = cal.date(from: dc) ?? Date()
        p.dates.append(.init(paramName: "collected", dateStart: d, dateEnd: d))
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
        p.dates.append(.init(paramName: "collected", dateStart: start, dateEnd: end))
    default:
        break
    }
}

// collector [reference] — Specimen.collection.collector
private func extract_Specimen_collector(_ p: inout SearchParams, _ s: Specimen) {
    guard let refStr = s.collection?.collector?.reference?.value?.string else { return }
    let parts = refStr.split(separator: "/")
    let (refType, refId): (String?, String) = parts.count == 2
        ? (String(parts[0]), String(parts[1]))
        : (nil, refStr)
    p.references.append(.init(paramName: "collector", refType: refType, refId: refId))
}

// container [token] — Specimen.container.type
private func extract_Specimen_container(_ p: inout SearchParams, _ s: Specimen) {
    for cont in s.container ?? [] {
        for coding in cont.type?.coding ?? [] {
            let c = coding.code?.value?.string ?? ""
            let sys = coding.system?.value?.url.absoluteString
            p.tokens.append(.init(paramName: "container", system: sys, code: c))
        }
    }
}

// container-id [token] — Specimen.container.identifier
private func extract_Specimen_container_id(_ p: inout SearchParams, _ s: Specimen) {
    for cont in s.container ?? [] {
        for ident in cont.identifier ?? [] {
            let v = ident.value?.value?.string ?? ""
            let sys = ident.system?.value?.url.absoluteString
            p.tokens.append(.init(paramName: "container-id", system: sys, code: v))
        }
    }
}

// identifier [token] — Specimen.identifier
private func extract_Specimen_identifier(_ p: inout SearchParams, _ s: Specimen) {
    for ident in s.identifier ?? [] {
        let v = ident.value?.value?.string ?? ""
        let sys = ident.system?.value?.url.absoluteString
        p.tokens.append(.init(paramName: "identifier", system: sys, code: v))
    }
}

// parent [reference] — Specimen.parent
private func extract_Specimen_parent(_ p: inout SearchParams, _ s: Specimen) {
    for ref in s.parent ?? [] {
        guard let refStr = ref.reference?.value?.string else { continue }
        let parts = refStr.split(separator: "/")
        let (refType, refId): (String?, String) = parts.count == 2
            ? (String(parts[0]), String(parts[1]))
            : (nil, refStr)
        p.references.append(.init(paramName: "parent", refType: refType, refId: refId))
    }
}

// patient [reference] — Specimen.subject
private func extract_Specimen_patient(_ p: inout SearchParams, _ s: Specimen) {
    guard let refStr = s.subject?.reference?.value?.string else { return }
    let parts = refStr.split(separator: "/")
    let (refType, refId): (String?, String) = parts.count == 2
        ? (String(parts[0]), String(parts[1]))
        : (nil, refStr)
    p.references.append(.init(paramName: "patient", refType: refType, refId: refId))
}

// status [token] — Specimen.status
private func extract_Specimen_status(_ p: inout SearchParams, _ s: Specimen) {
    if let v = s.status?.value?.rawValue {
        p.tokens.append(.init(paramName: "status",
                              system: "http://hl7.org/fhir/specimen-status", code: v))
    }
}

// subject [reference] — Specimen.subject
private func extract_Specimen_subject(_ p: inout SearchParams, _ s: Specimen) {
    guard let refStr = s.subject?.reference?.value?.string else { return }
    let parts = refStr.split(separator: "/")
    let (refType, refId): (String?, String) = parts.count == 2
        ? (String(parts[0]), String(parts[1]))
        : (nil, refStr)
    p.references.append(.init(paramName: "subject", refType: refType, refId: refId))
}

// type [token] — Specimen.type
private func extract_Specimen_type(_ p: inout SearchParams, _ s: Specimen) {
    for coding in s.type?.coding ?? [] {
        let c = coding.code?.value?.string ?? ""
        let sys = coding.system?.value?.url.absoluteString
        p.tokens.append(.init(paramName: "type", system: sys, code: c))
    }
}