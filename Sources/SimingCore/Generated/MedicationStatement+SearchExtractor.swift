// GENERATED — do not edit directly.
// Source: packages/*.tgz (hl7.fhir.r4.core + tw.gov.mohw.twcore)
// Regenerate: swift run SimingGenerator

import Foundation
import ModelsR4

/// Extracts all supported search parameters from a MedicationStatement for insertion
/// into the five idx_* index tables.
///
/// Params marked TODO are recognised by the FHIR R4 spec but not yet implemented.
public func extractMedicationStatementSearchParams(_ ms: MedicationStatement) -> SearchParams {
    var p = SearchParams()
    extract_MedicationStatement__id(&p, ms)
    extract_MedicationStatement_category(&p, ms)
    extract_MedicationStatement_code(&p, ms)
    extract_MedicationStatement_context(&p, ms)
    extract_MedicationStatement_effective(&p, ms)
    extract_MedicationStatement_identifier(&p, ms)
    extract_MedicationStatement_medication(&p, ms)
    extract_MedicationStatement_part_of(&p, ms)
    extract_MedicationStatement_patient(&p, ms)
    extract_MedicationStatement_source(&p, ms)
    extract_MedicationStatement_status(&p, ms)
    extract_MedicationStatement_subject(&p, ms)
    return p
}

// TODO: unhandled — _id [token] MedicationStatement.id
private func extract_MedicationStatement__id(_ p: inout SearchParams, _ ms: MedicationStatement) {}

// category [token] — MedicationStatement.category
private func extract_MedicationStatement_category(_ p: inout SearchParams, _ ms: MedicationStatement) {
    for coding in ms.category?.coding ?? [] {
        let v = coding.code?.value?.string ?? ""
        let s = coding.system?.value?.url.absoluteString
        p.tokens.append(.init(paramName: "category", system: s, code: v))
    }
}

// code [token] — MedicationStatement.medication
private func extract_MedicationStatement_code(_ p: inout SearchParams, _ ms: MedicationStatement) {
    guard case .codeableConcept(let cc) = ms.medication else { return }
    for coding in cc.coding ?? [] {
        let v = coding.code?.value?.string ?? ""
        let s = coding.system?.value?.url.absoluteString
        p.tokens.append(.init(paramName: "code", system: s, code: v))
    }
}

// context [reference] — MedicationStatement.context
private func extract_MedicationStatement_context(_ p: inout SearchParams, _ ms: MedicationStatement) {
    guard let refStr = ms.context?.reference?.value?.string else { return }
    let parts = refStr.split(separator: "/")
    let (refType, refId): (String?, String) = parts.count == 2
        ? (String(parts[0]), String(parts[1]))
        : (nil, refStr)
    p.references.append(.init(paramName: "context", refType: refType, refId: refId))
}

// effective [date] — MedicationStatement.effective
private func extract_MedicationStatement_effective(_ p: inout SearchParams, _ ms: MedicationStatement) {
    switch ms.effective {
    case .dateTime(let prim):
        guard let dt = prim.value else { return }
        var dc = DateComponents()
        dc.year = dt.date.year; dc.month = dt.date.month.map(Int.init)
        dc.day  = dt.date.day.map(Int.init); dc.hour = 12
        dc.timeZone = dt.timeZone
        let d = Calendar(identifier: .gregorian).date(from: dc) ?? Date()
        p.dates.append(.init(paramName: "effective", dateStart: d, dateEnd: d))
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
        p.dates.append(.init(paramName: "effective", dateStart: dateStart, dateEnd: dateEnd))
    case nil:
        break
    }
}

// identifier [token] — MedicationStatement.identifier
private func extract_MedicationStatement_identifier(_ p: inout SearchParams, _ ms: MedicationStatement) {
    for ident in ms.identifier ?? [] {
        let v = ident.value?.value?.string ?? ""
        let s = ident.system?.value?.url.absoluteString
        p.tokens.append(.init(paramName: "identifier", system: s, code: v))
    }
}

// medication [reference] — MedicationStatement.medication
private func extract_MedicationStatement_medication(_ p: inout SearchParams, _ ms: MedicationStatement) {
    guard case .reference(let ref) = ms.medication,
          let refStr = ref.reference?.value?.string else { return }
    let parts = refStr.split(separator: "/")
    let (refType, refId): (String?, String) = parts.count == 2
        ? (String(parts[0]), String(parts[1]))
        : (nil, refStr)
    p.references.append(.init(paramName: "medication", refType: refType, refId: refId))
}

// part-of [reference] — MedicationStatement.partOf
private func extract_MedicationStatement_part_of(_ p: inout SearchParams, _ ms: MedicationStatement) {
    for ref in ms.partOf ?? [] {
        guard let refStr = ref.reference?.value?.string else { continue }
        let parts = refStr.split(separator: "/")
        let (refType, refId): (String?, String) = parts.count == 2
            ? (String(parts[0]), String(parts[1]))
            : (nil, refStr)
        p.references.append(.init(paramName: "part-of", refType: refType, refId: refId))
    }
}

// patient [reference] — MedicationStatement.subject
private func extract_MedicationStatement_patient(_ p: inout SearchParams, _ ms: MedicationStatement) {
    guard let refStr = ms.subject.reference?.value?.string else { return }
    let parts = refStr.split(separator: "/")
    let (refType, refId): (String?, String) = parts.count == 2
        ? (String(parts[0]), String(parts[1]))
        : (nil, refStr)
    p.references.append(.init(paramName: "patient", refType: refType, refId: refId))
}

// source [reference] — MedicationStatement.informationSource
private func extract_MedicationStatement_source(_ p: inout SearchParams, _ ms: MedicationStatement) {
    guard let refStr = ms.informationSource?.reference?.value?.string else { return }
    let parts = refStr.split(separator: "/")
    let (refType, refId): (String?, String) = parts.count == 2
        ? (String(parts[0]), String(parts[1]))
        : (nil, refStr)
    p.references.append(.init(paramName: "source", refType: refType, refId: refId))
}

// status [token] — MedicationStatement.status
private func extract_MedicationStatement_status(_ p: inout SearchParams, _ ms: MedicationStatement) {
    if let v = ms.status.value?.rawValue {
        p.tokens.append(.init(paramName: "status",
                              system: "http://hl7.org/fhir/CodeSystem/medication-statement-status",
                              code: v))
    }
}

// subject [reference] — MedicationStatement.subject
private func extract_MedicationStatement_subject(_ p: inout SearchParams, _ ms: MedicationStatement) {
    guard let refStr = ms.subject.reference?.value?.string else { return }
    let parts = refStr.split(separator: "/")
    let (refType, refId): (String?, String) = parts.count == 2
        ? (String(parts[0]), String(parts[1]))
        : (nil, refStr)
    p.references.append(.init(paramName: "subject", refType: refType, refId: refId))
}