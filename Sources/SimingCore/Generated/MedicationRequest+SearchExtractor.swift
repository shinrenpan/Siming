// GENERATED — do not edit directly.
// Source: Resources/fhir/search-parameters-r4.json
// Regenerate: swift run SimingGenerator

import Foundation
import ModelsR4

/// Extracts all supported search parameters from a MedicationRequest for insertion
/// into the five idx_* index tables.
///
/// Params marked TODO are recognised by the FHIR R4 spec but not yet implemented.
public func extractMedicationRequestSearchParams(_ mr: MedicationRequest) -> SearchParams {
    var p = SearchParams()
    extract_MedicationRequest_authoredon(&p, mr)
    extract_MedicationRequest_category(&p, mr)
    extract_MedicationRequest_code(&p, mr)
    extract_MedicationRequest_date(&p, mr)
    extract_MedicationRequest_encounter(&p, mr)
    extract_MedicationRequest_identifier(&p, mr)
    extract_MedicationRequest_intended_dispenser(&p, mr)
    extract_MedicationRequest_intended_performer(&p, mr)
    extract_MedicationRequest_intended_performertype(&p, mr)
    extract_MedicationRequest_intent(&p, mr)
    extract_MedicationRequest_medication(&p, mr)
    extract_MedicationRequest_patient(&p, mr)
    extract_MedicationRequest_priority(&p, mr)
    extract_MedicationRequest_requester(&p, mr)
    extract_MedicationRequest_status(&p, mr)
    extract_MedicationRequest_subject(&p, mr)
    return p
}

// authoredon [date] — MedicationRequest.authoredOn
private func extract_MedicationRequest_authoredon(_ p: inout SearchParams, _ mr: MedicationRequest) {
    guard let prim = mr.authoredOn, let dt = prim.value else { return }
    var dc = DateComponents()
    dc.year = dt.date.year; dc.month = dt.date.month.map(Int.init)
    dc.day  = dt.date.day.map(Int.init); dc.hour = 12
    dc.timeZone = dt.timeZone
    let d = Calendar(identifier: .gregorian).date(from: dc) ?? Date()
    p.dates.append(.init(paramName: "authoredon", dateStart: d, dateEnd: d))
}

// category [token] — MedicationRequest.category
private func extract_MedicationRequest_category(_ p: inout SearchParams, _ mr: MedicationRequest) {
    for cc in mr.category ?? [] {
        for coding in cc.coding ?? [] {
            let c = coding.code?.value?.string ?? ""
            let s = coding.system?.value?.url.absoluteString
            p.tokens.append(.init(paramName: "category", system: s, code: c))
        }
    }
}

// code [token] — MedicationRequest.medication
private func extract_MedicationRequest_code(_ p: inout SearchParams, _ mr: MedicationRequest) {
    guard case .codeableConcept(let cc) = mr.medication else { return }
    for coding in cc.coding ?? [] {
        let c = coding.code?.value?.string ?? ""
        let s = coding.system?.value?.url.absoluteString
        p.tokens.append(.init(paramName: "code", system: s, code: c))
    }
}

// date [date] — MedicationRequest.dosageInstruction.timing.event
private func extract_MedicationRequest_date(_ p: inout SearchParams, _ mr: MedicationRequest) {
    let cal = Calendar(identifier: .gregorian)
    for dosage in mr.dosageInstruction ?? [] {
        for evt in dosage.timing?.event ?? [] {
            guard let dt = evt.value else { continue }
            var dc = DateComponents()
            dc.year = dt.date.year; dc.month = dt.date.month.map(Int.init)
            dc.day  = dt.date.day.map(Int.init); dc.hour = 12
            dc.timeZone = dt.timeZone
            let d = cal.date(from: dc) ?? Date()
            p.dates.append(.init(paramName: "date", dateStart: d, dateEnd: d))
        }
    }
}

// encounter [reference] — MedicationRequest.encounter
private func extract_MedicationRequest_encounter(_ p: inout SearchParams, _ mr: MedicationRequest) {
    guard let refStr = mr.encounter?.reference?.value?.string else { return }
    let parts = refStr.split(separator: "/")
    let (refType, refId): (String?, String) = parts.count == 2
        ? (String(parts[0]), String(parts[1]))
        : (nil, refStr)
    p.references.append(.init(paramName: "encounter", refType: refType, refId: refId))
}

// identifier [token] — MedicationRequest.identifier
private func extract_MedicationRequest_identifier(_ p: inout SearchParams, _ mr: MedicationRequest) {
    for ident in mr.identifier ?? [] {
        let v = ident.value?.value?.string ?? ""
        let s = ident.system?.value?.url.absoluteString
        p.tokens.append(.init(paramName: "identifier", system: s, code: v))
    }
}

// intended-dispenser [reference] — MedicationRequest.dispenseRequest.performer
private func extract_MedicationRequest_intended_dispenser(_ p: inout SearchParams, _ mr: MedicationRequest) {
    guard let refStr = mr.dispenseRequest?.performer?.reference?.value?.string else { return }
    let parts = refStr.split(separator: "/")
    let (refType, refId): (String?, String) = parts.count == 2
        ? (String(parts[0]), String(parts[1]))
        : (nil, refStr)
    p.references.append(.init(paramName: "intended-dispenser", refType: refType, refId: refId))
}

// intended-performer [reference] — MedicationRequest.performer
private func extract_MedicationRequest_intended_performer(_ p: inout SearchParams, _ mr: MedicationRequest) {
    guard let refStr = mr.performer?.reference?.value?.string else { return }
    let parts = refStr.split(separator: "/")
    let (refType, refId): (String?, String) = parts.count == 2
        ? (String(parts[0]), String(parts[1]))
        : (nil, refStr)
    p.references.append(.init(paramName: "intended-performer", refType: refType, refId: refId))
}

// intended-performertype [token] — MedicationRequest.performerType
private func extract_MedicationRequest_intended_performertype(_ p: inout SearchParams, _ mr: MedicationRequest) {
    for coding in mr.performerType?.coding ?? [] {
        let c = coding.code?.value?.string ?? ""
        let s = coding.system?.value?.url.absoluteString
        p.tokens.append(.init(paramName: "intended-performertype", system: s, code: c))
    }
}

// intent [token] — MedicationRequest.intent
private func extract_MedicationRequest_intent(_ p: inout SearchParams, _ mr: MedicationRequest) {
    if let v = mr.intent.value?.rawValue {
        p.tokens.append(.init(paramName: "intent",
                              system: "http://hl7.org/fhir/CodeSystem/medicationrequest-intent",
                              code: v))
    }
}

// medication [reference] — MedicationRequest.medication
private func extract_MedicationRequest_medication(_ p: inout SearchParams, _ mr: MedicationRequest) {
    guard case .reference(let ref) = mr.medication,
          let refStr = ref.reference?.value?.string else { return }
    let parts = refStr.split(separator: "/")
    let (refType, refId): (String?, String) = parts.count == 2
        ? (String(parts[0]), String(parts[1]))
        : (nil, refStr)
    p.references.append(.init(paramName: "medication", refType: refType, refId: refId))
}

// patient [reference] — MedicationRequest.subject
private func extract_MedicationRequest_patient(_ p: inout SearchParams, _ mr: MedicationRequest) {
    guard let refStr = mr.subject.reference?.value?.string else { return }
    let parts = refStr.split(separator: "/")
    let (refType, refId): (String?, String) = parts.count == 2
        ? (String(parts[0]), String(parts[1]))
        : (nil, refStr)
    p.references.append(.init(paramName: "patient", refType: refType, refId: refId))
}

// priority [token] — MedicationRequest.priority
private func extract_MedicationRequest_priority(_ p: inout SearchParams, _ mr: MedicationRequest) {
    if let v = mr.priority?.value?.rawValue {
        p.tokens.append(.init(paramName: "priority",
                              system: "http://hl7.org/fhir/request-priority",
                              code: v))
    }
}

// requester [reference] — MedicationRequest.requester
private func extract_MedicationRequest_requester(_ p: inout SearchParams, _ mr: MedicationRequest) {
    guard let refStr = mr.requester?.reference?.value?.string else { return }
    let parts = refStr.split(separator: "/")
    let (refType, refId): (String?, String) = parts.count == 2
        ? (String(parts[0]), String(parts[1]))
        : (nil, refStr)
    p.references.append(.init(paramName: "requester", refType: refType, refId: refId))
}

// status [token] — MedicationRequest.status
private func extract_MedicationRequest_status(_ p: inout SearchParams, _ mr: MedicationRequest) {
    if let v = mr.status.value?.rawValue {
        p.tokens.append(.init(paramName: "status",
                              system: "http://hl7.org/fhir/CodeSystem/medicationrequest-status",
                              code: v))
    }
}

// subject [reference] — MedicationRequest.subject
private func extract_MedicationRequest_subject(_ p: inout SearchParams, _ mr: MedicationRequest) {
    guard let refStr = mr.subject.reference?.value?.string else { return }
    let parts = refStr.split(separator: "/")
    let (refType, refId): (String?, String) = parts.count == 2
        ? (String(parts[0]), String(parts[1]))
        : (nil, refStr)
    p.references.append(.init(paramName: "subject", refType: refType, refId: refId))
}