// GENERATED — do not edit directly.
// Source: Resources/fhir/search-parameters-r4.json
// Regenerate: swift run SimingGenerator

import Foundation
import ModelsR4

/// Extracts all supported search parameters from a ServiceRequest for insertion
/// into the five idx_* index tables.
///
/// Params marked TODO are recognised by the FHIR R4 spec but not yet implemented.
public func extractServiceRequestSearchParams(_ sr: ServiceRequest) -> SearchParams {
    var p = SearchParams()
    extract_ServiceRequest_authored(&p, sr)
    extract_ServiceRequest_based_on(&p, sr)
    extract_ServiceRequest_body_site(&p, sr)
    extract_ServiceRequest_category(&p, sr)
    extract_ServiceRequest_code(&p, sr)
    extract_ServiceRequest_encounter(&p, sr)
    extract_ServiceRequest_identifier(&p, sr)
    extract_ServiceRequest_instantiates_canonical(&p, sr)
    extract_ServiceRequest_instantiates_uri(&p, sr)
    extract_ServiceRequest_intent(&p, sr)
    extract_ServiceRequest_occurrence(&p, sr)
    extract_ServiceRequest_patient(&p, sr)
    extract_ServiceRequest_performer(&p, sr)
    extract_ServiceRequest_performer_type(&p, sr)
    extract_ServiceRequest_priority(&p, sr)
    extract_ServiceRequest_replaces(&p, sr)
    extract_ServiceRequest_requester(&p, sr)
    extract_ServiceRequest_requisition(&p, sr)
    extract_ServiceRequest_specimen(&p, sr)
    extract_ServiceRequest_status(&p, sr)
    extract_ServiceRequest_subject(&p, sr)
    return p
}

// authored [date] — ServiceRequest.authoredOn
private func extract_ServiceRequest_authored(_ p: inout SearchParams, _ sr: ServiceRequest) {
    guard let prim = sr.authoredOn, let dt = prim.value else { return }
    let cal = Calendar(identifier: .gregorian)
    var dc = DateComponents()
    dc.year = dt.date.year; dc.month = dt.date.month.map(Int.init)
    dc.day  = dt.date.day.map(Int.init); dc.hour = 12
    dc.timeZone = dt.timeZone
    let d = cal.date(from: dc) ?? Date()
    p.dates.append(.init(paramName: "authored", dateStart: d, dateEnd: d))
}

// based-on [reference] — ServiceRequest.basedOn
private func extract_ServiceRequest_based_on(_ p: inout SearchParams, _ sr: ServiceRequest) {
    for ref in sr.basedOn ?? [] {
        guard let refStr = ref.reference?.value?.string else { continue }
        let parts = refStr.split(separator: "/")
        let (refType, refId): (String?, String) = parts.count == 2
            ? (String(parts[0]), String(parts[1]))
            : (nil, refStr)
        p.references.append(.init(paramName: "based-on", refType: refType, refId: refId))
    }
}

// body-site [token] — ServiceRequest.bodySite
private func extract_ServiceRequest_body_site(_ p: inout SearchParams, _ sr: ServiceRequest) {
    for site in sr.bodySite ?? [] {
        for coding in site.coding ?? [] {
            let c = coding.code?.value?.string ?? ""
            let s = coding.system?.value?.url.absoluteString
            p.tokens.append(.init(paramName: "body-site", system: s, code: c))
        }
    }
}

// category [token] — ServiceRequest.category
private func extract_ServiceRequest_category(_ p: inout SearchParams, _ sr: ServiceRequest) {
    for cat in sr.category ?? [] {
        for coding in cat.coding ?? [] {
            let c = coding.code?.value?.string ?? ""
            let s = coding.system?.value?.url.absoluteString
            p.tokens.append(.init(paramName: "category", system: s, code: c))
        }
    }
}

// code [token] — ServiceRequest.code
private func extract_ServiceRequest_code(_ p: inout SearchParams, _ sr: ServiceRequest) {
    for coding in sr.code?.coding ?? [] {
        let c = coding.code?.value?.string ?? ""
        let s = coding.system?.value?.url.absoluteString
        p.tokens.append(.init(paramName: "code", system: s, code: c))
    }
}

// encounter [reference] — ServiceRequest.encounter
private func extract_ServiceRequest_encounter(_ p: inout SearchParams, _ sr: ServiceRequest) {
    guard let refStr = sr.encounter?.reference?.value?.string else { return }
    let parts = refStr.split(separator: "/")
    let (refType, refId): (String?, String) = parts.count == 2
        ? (String(parts[0]), String(parts[1]))
        : (nil, refStr)
    p.references.append(.init(paramName: "encounter", refType: refType, refId: refId))
}

// identifier [token] — ServiceRequest.identifier
private func extract_ServiceRequest_identifier(_ p: inout SearchParams, _ sr: ServiceRequest) {
    for ident in sr.identifier ?? [] {
        let v = ident.value?.value?.string ?? ""
        let s = ident.system?.value?.url.absoluteString
        p.tokens.append(.init(paramName: "identifier", system: s, code: v))
    }
}

// instantiates-canonical [reference] — ServiceRequest.instantiatesCanonical
private func extract_ServiceRequest_instantiates_canonical(_ p: inout SearchParams, _ sr: ServiceRequest) {
    // TODO: canonical reference indexing not implemented
}

// instantiates-uri [uri] — ServiceRequest.instantiatesUri
private func extract_ServiceRequest_instantiates_uri(_ p: inout SearchParams, _ sr: ServiceRequest) {
    for prim in sr.instantiatesUri ?? [] {
        guard let url = prim.value?.url.absoluteString else { continue }
        p.strings.append(.init(paramName: "instantiates-uri", value: url))
    }
}

// intent [token] — ServiceRequest.intent
private func extract_ServiceRequest_intent(_ p: inout SearchParams, _ sr: ServiceRequest) {
    if let v = sr.intent.value?.rawValue {
        p.tokens.append(.init(paramName: "intent",
                              system: "http://hl7.org/fhir/request-intent", code: v))
    }
}

// occurrence [date] — ServiceRequest.occurrence
private func extract_ServiceRequest_occurrence(_ p: inout SearchParams, _ sr: ServiceRequest) {
    let cal = Calendar(identifier: .gregorian)
    guard let occ = sr.occurrence else { return }
    switch occ {
    case .dateTime(let prim):
        guard let dt = prim.value else { return }
        var dc = DateComponents()
        dc.year = dt.date.year; dc.month = dt.date.month.map(Int.init)
        dc.day  = dt.date.day.map(Int.init); dc.hour = 12
        dc.timeZone = dt.timeZone
        let d = cal.date(from: dc) ?? Date()
        p.dates.append(.init(paramName: "occurrence", dateStart: d, dateEnd: d))
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
        p.dates.append(.init(paramName: "occurrence", dateStart: start, dateEnd: end))
    default:
        break
    }
}

// patient [reference] — ServiceRequest.subject
private func extract_ServiceRequest_patient(_ p: inout SearchParams, _ sr: ServiceRequest) {
    guard let refStr = sr.subject.reference?.value?.string else { return }
    let parts = refStr.split(separator: "/")
    let (refType, refId): (String?, String) = parts.count == 2
        ? (String(parts[0]), String(parts[1]))
        : (nil, refStr)
    p.references.append(.init(paramName: "patient", refType: refType, refId: refId))
}

// performer [reference] — ServiceRequest.performer
private func extract_ServiceRequest_performer(_ p: inout SearchParams, _ sr: ServiceRequest) {
    for ref in sr.performer ?? [] {
        guard let refStr = ref.reference?.value?.string else { continue }
        let parts = refStr.split(separator: "/")
        let (refType, refId): (String?, String) = parts.count == 2
            ? (String(parts[0]), String(parts[1]))
            : (nil, refStr)
        p.references.append(.init(paramName: "performer", refType: refType, refId: refId))
    }
}

// performer-type [token] — ServiceRequest.performerType
private func extract_ServiceRequest_performer_type(_ p: inout SearchParams, _ sr: ServiceRequest) {
    for coding in sr.performerType?.coding ?? [] {
        let c = coding.code?.value?.string ?? ""
        let s = coding.system?.value?.url.absoluteString
        p.tokens.append(.init(paramName: "performer-type", system: s, code: c))
    }
}

// priority [token] — ServiceRequest.priority
private func extract_ServiceRequest_priority(_ p: inout SearchParams, _ sr: ServiceRequest) {
    if let v = sr.priority?.value?.rawValue {
        p.tokens.append(.init(paramName: "priority",
                              system: "http://hl7.org/fhir/request-priority", code: v))
    }
}

// replaces [reference] — ServiceRequest.replaces
private func extract_ServiceRequest_replaces(_ p: inout SearchParams, _ sr: ServiceRequest) {
    for ref in sr.replaces ?? [] {
        guard let refStr = ref.reference?.value?.string else { continue }
        let parts = refStr.split(separator: "/")
        let (refType, refId): (String?, String) = parts.count == 2
            ? (String(parts[0]), String(parts[1]))
            : (nil, refStr)
        p.references.append(.init(paramName: "replaces", refType: refType, refId: refId))
    }
}

// requester [reference] — ServiceRequest.requester
private func extract_ServiceRequest_requester(_ p: inout SearchParams, _ sr: ServiceRequest) {
    guard let refStr = sr.requester?.reference?.value?.string else { return }
    let parts = refStr.split(separator: "/")
    let (refType, refId): (String?, String) = parts.count == 2
        ? (String(parts[0]), String(parts[1]))
        : (nil, refStr)
    p.references.append(.init(paramName: "requester", refType: refType, refId: refId))
}

// requisition [token] — ServiceRequest.requisition
private func extract_ServiceRequest_requisition(_ p: inout SearchParams, _ sr: ServiceRequest) {
    guard let req = sr.requisition else { return }
    let v = req.value?.value?.string ?? ""
    let s = req.system?.value?.url.absoluteString
    p.tokens.append(.init(paramName: "requisition", system: s, code: v))
}

// specimen [reference] — ServiceRequest.specimen
private func extract_ServiceRequest_specimen(_ p: inout SearchParams, _ sr: ServiceRequest) {
    for ref in sr.specimen ?? [] {
        guard let refStr = ref.reference?.value?.string else { continue }
        let parts = refStr.split(separator: "/")
        let (refType, refId): (String?, String) = parts.count == 2
            ? (String(parts[0]), String(parts[1]))
            : (nil, refStr)
        p.references.append(.init(paramName: "specimen", refType: refType, refId: refId))
    }
}

// status [token] — ServiceRequest.status
private func extract_ServiceRequest_status(_ p: inout SearchParams, _ sr: ServiceRequest) {
    if let v = sr.status.value?.rawValue {
        p.tokens.append(.init(paramName: "status",
                              system: "http://hl7.org/fhir/request-status", code: v))
    }
}

// subject [reference] — ServiceRequest.subject
private func extract_ServiceRequest_subject(_ p: inout SearchParams, _ sr: ServiceRequest) {
    guard let refStr = sr.subject.reference?.value?.string else { return }
    let parts = refStr.split(separator: "/")
    let (refType, refId): (String?, String) = parts.count == 2
        ? (String(parts[0]), String(parts[1]))
        : (nil, refStr)
    p.references.append(.init(paramName: "subject", refType: refType, refId: refId))
}