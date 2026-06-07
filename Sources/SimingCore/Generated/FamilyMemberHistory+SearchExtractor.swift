// GENERATED — do not edit directly.
// Source: Resources/fhir/search-parameters-r4.json
// Regenerate: swift run SimingGenerator

import Foundation
import ModelsR4

/// Extracts all supported search parameters from a FamilyMemberHistory for insertion
/// into the five idx_* index tables.
///
/// Params marked TODO are recognised by the FHIR R4 spec but not yet implemented.
public func extractFamilyMemberHistorySearchParams(_ fmh: FamilyMemberHistory) -> SearchParams {
    var p = SearchParams()
    extract_FamilyMemberHistory_code(&p, fmh)
    extract_FamilyMemberHistory_date(&p, fmh)
    extract_FamilyMemberHistory_identifier(&p, fmh)
    extract_FamilyMemberHistory_instantiates_canonical(&p, fmh)
    extract_FamilyMemberHistory_instantiates_uri(&p, fmh)
    extract_FamilyMemberHistory_patient(&p, fmh)
    extract_FamilyMemberHistory_relationship(&p, fmh)
    extract_FamilyMemberHistory_sex(&p, fmh)
    extract_FamilyMemberHistory_status(&p, fmh)
    return p
}

// code [token] — FamilyMemberHistory.condition.code
private func extract_FamilyMemberHistory_code(_ p: inout SearchParams, _ fmh: FamilyMemberHistory) {
    for condition in fmh.condition ?? [] {
        for coding in condition.code.coding ?? [] {
            let v = coding.code?.value?.string ?? ""
            let s = coding.system?.value?.url.absoluteString
            p.tokens.append(.init(paramName: "code", system: s, code: v))
        }
    }
}

// date [date] — FamilyMemberHistory.date
private func extract_FamilyMemberHistory_date(_ p: inout SearchParams, _ fmh: FamilyMemberHistory) {
    guard let prim = fmh.date, let dt = prim.value else { return }
    var dc = DateComponents()
    dc.year = dt.date.year; dc.month = dt.date.month.map(Int.init)
    dc.day  = dt.date.day.map(Int.init); dc.hour = 12
    dc.timeZone = dt.timeZone
    let d = Calendar(identifier: .gregorian).date(from: dc) ?? Date()
    p.dates.append(.init(paramName: "date", dateStart: d, dateEnd: d))
}

// identifier [token] — FamilyMemberHistory.identifier
private func extract_FamilyMemberHistory_identifier(_ p: inout SearchParams, _ fmh: FamilyMemberHistory) {
    for ident in fmh.identifier ?? [] {
        let v = ident.value?.value?.string ?? ""
        let s = ident.system?.value?.url.absoluteString
        p.tokens.append(.init(paramName: "identifier", system: s, code: v))
    }
}

// instantiates-canonical [reference] — FamilyMemberHistory.instantiatesCanonical
private func extract_FamilyMemberHistory_instantiates_canonical(_ p: inout SearchParams, _ fmh: FamilyMemberHistory) {
    for ic in fmh.instantiatesCanonical ?? [] {
        guard let url = ic.value?.url.absoluteString else { continue }
        p.strings.append(.init(paramName: "instantiates-canonical", value: url))
    }
}

// instantiates-uri [uri] — FamilyMemberHistory.instantiatesUri
private func extract_FamilyMemberHistory_instantiates_uri(_ p: inout SearchParams, _ fmh: FamilyMemberHistory) {
    for iu in fmh.instantiatesUri ?? [] {
        guard let url = iu.value?.url.absoluteString else { continue }
        p.strings.append(.init(paramName: "instantiates-uri", value: url))
    }
}

// patient [reference] — FamilyMemberHistory.patient
private func extract_FamilyMemberHistory_patient(_ p: inout SearchParams, _ fmh: FamilyMemberHistory) {
    guard let refStr = fmh.patient.reference?.value?.string else { return }
    let parts = refStr.split(separator: "/")
    let (refType, refId): (String?, String) = parts.count == 2
        ? (String(parts[0]), String(parts[1]))
        : (nil, refStr)
    p.references.append(.init(paramName: "patient", refType: refType, refId: refId))
}

// relationship [token] — FamilyMemberHistory.relationship
private func extract_FamilyMemberHistory_relationship(_ p: inout SearchParams, _ fmh: FamilyMemberHistory) {
    for coding in fmh.relationship.coding ?? [] {
        let v = coding.code?.value?.string ?? ""
        let s = coding.system?.value?.url.absoluteString
        p.tokens.append(.init(paramName: "relationship", system: s, code: v))
    }
}

// sex [token] — FamilyMemberHistory.sex
private func extract_FamilyMemberHistory_sex(_ p: inout SearchParams, _ fmh: FamilyMemberHistory) {
    for coding in fmh.sex?.coding ?? [] {
        let v = coding.code?.value?.string ?? ""
        let s = coding.system?.value?.url.absoluteString
        p.tokens.append(.init(paramName: "sex", system: s, code: v))
    }
}

// status [token] — FamilyMemberHistory.status
private func extract_FamilyMemberHistory_status(_ p: inout SearchParams, _ fmh: FamilyMemberHistory) {
    if let v = fmh.status.value?.rawValue {
        p.tokens.append(.init(paramName: "status",
                              system: "http://hl7.org/fhir/history-status", code: v))
    }
}