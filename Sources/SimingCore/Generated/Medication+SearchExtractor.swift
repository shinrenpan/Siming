// GENERATED — do not edit directly.
// Source: Resources/fhir/search-parameters-r4.json
// Regenerate: swift run SimingGenerator

import Foundation
import ModelsR4

/// Extracts all supported search parameters from a Medication for insertion
/// into the five idx_* index tables.
///
/// Params marked TODO are recognised by the FHIR R4 spec but not yet implemented.
public func extractMedicationSearchParams(_ med: Medication) -> SearchParams {
    var p = SearchParams()
    extract_Medication_code(&p, med)
    extract_Medication_expiration_date(&p, med)
    extract_Medication_form(&p, med)
    extract_Medication_identifier(&p, med)
    extract_Medication_ingredient(&p, med)
    extract_Medication_ingredient_code(&p, med)
    extract_Medication_lot_number(&p, med)
    extract_Medication_manufacturer(&p, med)
    extract_Medication_status(&p, med)
    return p
}

// code [token] — Medication.code
private func extract_Medication_code(_ p: inout SearchParams, _ med: Medication) {
    for coding in med.code?.coding ?? [] {
        let c = coding.code?.value?.string ?? ""
        let s = coding.system?.value?.url.absoluteString
        p.appendToken(paramName: "code", system: s, code: c, display: coding.display?.value?.string)
    }
}

// expiration-date [date] — Medication.batch.expirationDate
private func extract_Medication_expiration_date(_ p: inout SearchParams, _ med: Medication) {
    guard let prim = med.batch?.expirationDate, let dt = prim.value else { return }
    var dc = DateComponents()
    dc.year = dt.date.year; dc.month = dt.date.month.map(Int.init)
    dc.day  = dt.date.day.map(Int.init); dc.hour = 12
    dc.timeZone = dt.timeZone
    let d = Calendar(identifier: .gregorian).date(from: dc) ?? Date()
    p.dates.append(.init(paramName: "expiration-date", dateStart: d, dateEnd: d))
}

// form [token] — Medication.form
private func extract_Medication_form(_ p: inout SearchParams, _ med: Medication) {
    for coding in med.form?.coding ?? [] {
        let c = coding.code?.value?.string ?? ""
        let s = coding.system?.value?.url.absoluteString
        p.appendToken(paramName: "form", system: s, code: c, display: coding.display?.value?.string)
    }
}

// identifier [token] — Medication.identifier
private func extract_Medication_identifier(_ p: inout SearchParams, _ med: Medication) {
    for ident in med.identifier ?? [] {
        let v = ident.value?.value?.string ?? ""
        let s = ident.system?.value?.url.absoluteString
        p.tokens.append(.init(paramName: "identifier", system: s, code: v))
    }
}

// ingredient [reference] — Medication.ingredient.item
private func extract_Medication_ingredient(_ p: inout SearchParams, _ med: Medication) {
    for ing in med.ingredient ?? [] {
        guard case .reference(let ref) = ing.item else { continue }
        guard let refStr = ref.reference?.value?.string else { continue }
        let parts = refStr.split(separator: "/")
        let (refType, refId): (String?, String) = parts.count == 2
            ? (String(parts[0]), String(parts[1]))
            : (nil, refStr)
        p.references.append(.init(paramName: "ingredient", refType: refType, refId: refId))
    }
}

// ingredient-code [token] — Medication.ingredient.item
private func extract_Medication_ingredient_code(_ p: inout SearchParams, _ med: Medication) {
    for ing in med.ingredient ?? [] {
        guard case .codeableConcept(let cc) = ing.item else { continue }
        for coding in cc.coding ?? [] {
            let c = coding.code?.value?.string ?? ""
            let s = coding.system?.value?.url.absoluteString
            p.appendToken(paramName: "ingredient-code", system: s, code: c, display: coding.display?.value?.string)
        }
    }
}

// lot-number [token] — Medication.batch.lotNumber
private func extract_Medication_lot_number(_ p: inout SearchParams, _ med: Medication) {
    if let v = med.batch?.lotNumber?.value?.string {
        p.tokens.append(.init(paramName: "lot-number", system: nil, code: v))
    }
}

// manufacturer [reference] — Medication.manufacturer
private func extract_Medication_manufacturer(_ p: inout SearchParams, _ med: Medication) {
    guard let refStr = med.manufacturer?.reference?.value?.string else { return }
    let parts = refStr.split(separator: "/")
    let (refType, refId): (String?, String) = parts.count == 2
        ? (String(parts[0]), String(parts[1]))
        : (nil, refStr)
    p.references.append(.init(paramName: "manufacturer", refType: refType, refId: refId))
}

// status [token] — Medication.status
private func extract_Medication_status(_ p: inout SearchParams, _ med: Medication) {
    if let v = med.status?.value?.rawValue {
        p.tokens.append(.init(paramName: "status",
                              system: "http://hl7.org/fhir/CodeSystem/medication-status",
                              code: v))
    }
}