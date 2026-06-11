// GENERATED — do not edit directly.
// Source: packages/*.tgz (hl7.fhir.r4.core + tw.gov.mohw.twcore)
// Regenerate: swift run SimingGenerator

import Foundation
import ModelsR4

/// Extracts all supported search parameters from a RelatedPerson for insertion
/// into the five idx_* index tables.
///
/// Params marked TODO are recognised by the FHIR R4 spec but not yet implemented.
public func extractRelatedPersonSearchParams(_ rp: RelatedPerson) -> SearchParams {
    var p = SearchParams()
    extract_RelatedPerson__id(&p, rp)
    extract_RelatedPerson_active(&p, rp)
    extract_RelatedPerson_address(&p, rp)
    extract_RelatedPerson_address_city(&p, rp)
    extract_RelatedPerson_address_country(&p, rp)
    extract_RelatedPerson_address_postalcode(&p, rp)
    extract_RelatedPerson_address_state(&p, rp)
    extract_RelatedPerson_address_use(&p, rp)
    extract_RelatedPerson_birthdate(&p, rp)
    extract_RelatedPerson_email(&p, rp)
    extract_RelatedPerson_gender(&p, rp)
    extract_RelatedPerson_identifier(&p, rp)
    extract_RelatedPerson_name(&p, rp)
    extract_RelatedPerson_patient(&p, rp)
    extract_RelatedPerson_phone(&p, rp)
    extract_RelatedPerson_phonetic(&p, rp)
    extract_RelatedPerson_relationship(&p, rp)
    extract_RelatedPerson_telecom(&p, rp)
    return p
}

// TODO: unhandled — _id [token] RelatedPerson.id
private func extract_RelatedPerson__id(_ p: inout SearchParams, _ rp: RelatedPerson) {}

// active [token] — RelatedPerson.active
private func extract_RelatedPerson_active(_ p: inout SearchParams, _ rp: RelatedPerson) {
    if let v = rp.active?.value?.bool {
        p.tokens.append(.init(paramName: "active", system: nil, code: v ? "true" : "false"))
    }
}

// address [string] — RelatedPerson.address
private func extract_RelatedPerson_address(_ p: inout SearchParams, _ rp: RelatedPerson) {
    for addr in rp.address ?? [] {
        if let v = addr.text?.value?.string       { p.strings.append(.init(paramName: "address", value: v)) }
        for line in addr.line ?? [] {
            if let v = line.value?.string          { p.strings.append(.init(paramName: "address", value: v)) }
        }
        if let v = addr.city?.value?.string       { p.strings.append(.init(paramName: "address", value: v)) }
        if let v = addr.state?.value?.string      { p.strings.append(.init(paramName: "address", value: v)) }
        if let v = addr.postalCode?.value?.string { p.strings.append(.init(paramName: "address", value: v)) }
        if let v = addr.country?.value?.string    { p.strings.append(.init(paramName: "address", value: v)) }
    }
}

// address-city [string] — RelatedPerson.address.city
private func extract_RelatedPerson_address_city(_ p: inout SearchParams, _ rp: RelatedPerson) {
    for addr in rp.address ?? [] {
        if let v = addr.city?.value?.string {
            p.strings.append(.init(paramName: "address-city", value: v))
        }
    }
}

// address-country [string] — RelatedPerson.address.country
private func extract_RelatedPerson_address_country(_ p: inout SearchParams, _ rp: RelatedPerson) {
    for addr in rp.address ?? [] {
        if let v = addr.country?.value?.string {
            p.strings.append(.init(paramName: "address-country", value: v))
        }
    }
}

// address-postalcode [string] — RelatedPerson.address.postalCode
private func extract_RelatedPerson_address_postalcode(_ p: inout SearchParams, _ rp: RelatedPerson) {
    for addr in rp.address ?? [] {
        if let v = addr.postalCode?.value?.string {
            p.strings.append(.init(paramName: "address-postalcode", value: v))
        }
    }
}

// address-state [string] — RelatedPerson.address.state
private func extract_RelatedPerson_address_state(_ p: inout SearchParams, _ rp: RelatedPerson) {
    for addr in rp.address ?? [] {
        if let v = addr.state?.value?.string {
            p.strings.append(.init(paramName: "address-state", value: v))
        }
    }
}

// address-use [token] — RelatedPerson.address.use
private func extract_RelatedPerson_address_use(_ p: inout SearchParams, _ rp: RelatedPerson) {
    for addr in rp.address ?? [] {
        if let v = addr.use?.value?.rawValue {
            p.tokens.append(.init(paramName: "address-use",
                                  system: "http://hl7.org/fhir/address-use", code: v))
        }
    }
}

// birthdate [date] — RelatedPerson.birthDate
private func extract_RelatedPerson_birthdate(_ p: inout SearchParams, _ rp: RelatedPerson) {
    guard let bd = rp.birthDate?.value else { return }
    var dc = DateComponents()
    dc.year = bd.year; dc.month = bd.month.map(Int.init)
    dc.day  = bd.day.map(Int.init)
    let cal = Calendar(identifier: .gregorian)
    let start = cal.date(from: dc) ?? Date()
    var endDc = dc
    if dc.day != nil {
        endDc.hour = 23; endDc.minute = 59; endDc.second = 59
    } else if dc.month != nil {
        endDc.day = cal.range(of: .day, in: .month, for: start)?.count ?? 28
    } else {
        endDc.month = 12; endDc.day = 31
    }
    let end = cal.date(from: endDc) ?? start
    p.dates.append(.init(paramName: "birthdate", dateStart: start, dateEnd: end))
}

// email [token] — RelatedPerson.telecom
private func extract_RelatedPerson_email(_ p: inout SearchParams, _ rp: RelatedPerson) {
    for tc in rp.telecom ?? [] {
        guard tc.system?.value?.rawValue == "email" else { continue }
        if let v = tc.value?.value?.string {
            p.tokens.append(.init(paramName: "email", system: "email", code: v))
        }
    }
}

// gender [token] — RelatedPerson.gender
private func extract_RelatedPerson_gender(_ p: inout SearchParams, _ rp: RelatedPerson) {
    if let v = rp.gender?.value?.rawValue {
        p.tokens.append(.init(paramName: "gender",
                              system: "http://hl7.org/fhir/administrative-gender",
                              code: v))
    }
}

// identifier [token] — RelatedPerson.identifier
private func extract_RelatedPerson_identifier(_ p: inout SearchParams, _ rp: RelatedPerson) {
    for ident in rp.identifier ?? [] {
        let v = ident.value?.value?.string ?? ""
        let s = ident.system?.value?.url.absoluteString
        p.tokens.append(.init(paramName: "identifier", system: s, code: v))
    }
}

// name [string] — RelatedPerson.name
private func extract_RelatedPerson_name(_ p: inout SearchParams, _ rp: RelatedPerson) {
    for hn in rp.name ?? [] {
        if let v = hn.family?.value?.string { p.strings.append(.init(paramName: "name", value: v)) }
        for given in hn.given ?? [] {
            if let v = given.value?.string { p.strings.append(.init(paramName: "name", value: v)) }
        }
        if let v = hn.text?.value?.string { p.strings.append(.init(paramName: "name", value: v)) }
    }
}

// patient [reference] — RelatedPerson.patient
private func extract_RelatedPerson_patient(_ p: inout SearchParams, _ rp: RelatedPerson) {
    guard let refStr = rp.patient.reference?.value?.string else { return }
    let parts = refStr.split(separator: "/")
    let (refType, refId): (String?, String) = parts.count == 2
        ? (String(parts[0]), String(parts[1]))
        : (nil, refStr)
    p.references.append(.init(paramName: "patient", refType: refType, refId: refId))
}

// phone [token] — RelatedPerson.telecom
private func extract_RelatedPerson_phone(_ p: inout SearchParams, _ rp: RelatedPerson) {
    for tc in rp.telecom ?? [] {
        guard tc.system?.value?.rawValue == "phone" else { continue }
        if let v = tc.value?.value?.string {
            p.tokens.append(.init(paramName: "phone", system: "phone", code: v))
        }
    }
}

// phonetic [string] — RelatedPerson.name
private func extract_RelatedPerson_phonetic(_ p: inout SearchParams, _ rp: RelatedPerson) {
    for hn in rp.name ?? [] {
        if let v = hn.family?.value?.string { p.strings.append(.init(paramName: "name", value: v)) }
        for given in hn.given ?? [] {
            if let v = given.value?.string { p.strings.append(.init(paramName: "name", value: v)) }
        }
        if let v = hn.text?.value?.string { p.strings.append(.init(paramName: "name", value: v)) }
    }
}

// relationship [token] — RelatedPerson.relationship
private func extract_RelatedPerson_relationship(_ p: inout SearchParams, _ rp: RelatedPerson) {
    for cc in rp.relationship ?? [] {
        for coding in cc.coding ?? [] {
            let c = coding.code?.value?.string ?? ""
            let s = coding.system?.value?.url.absoluteString
            p.appendToken(paramName: "relationship", system: s, code: c, display: coding.display?.value?.string)
        }
    }
}

// telecom [token] — RelatedPerson.telecom
private func extract_RelatedPerson_telecom(_ p: inout SearchParams, _ rp: RelatedPerson) {
    for tc in rp.telecom ?? [] {
        let sys = tc.system?.value?.rawValue
        if let v = tc.value?.value?.string {
            p.tokens.append(.init(paramName: "telecom", system: sys, code: v))
        }
    }
}