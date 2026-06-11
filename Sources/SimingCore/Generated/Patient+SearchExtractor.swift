// GENERATED — do not edit directly.
// Source: packages/*.tgz (hl7.fhir.r4.core + tw.gov.mohw.twcore)
// Regenerate: swift run SimingGenerator

import Foundation
import ModelsR4

/// Extracts all supported search parameters from a Patient for insertion
/// into the five idx_* index tables.
///
/// Params marked TODO are recognised by the FHIR R4 spec but not yet implemented.
public func extractPatientSearchParams(_ patient: Patient) -> SearchParams {
    var p = SearchParams()
    extract_Patient__id(&p, patient)
    extract_Patient_active(&p, patient)
    extract_Patient_address(&p, patient)
    extract_Patient_address_city(&p, patient)
    extract_Patient_address_country(&p, patient)
    extract_Patient_address_postalcode(&p, patient)
    extract_Patient_address_state(&p, patient)
    extract_Patient_address_use(&p, patient)
    extract_Patient_birthdate(&p, patient)
    extract_Patient_death_date(&p, patient)
    extract_Patient_deceased(&p, patient)
    extract_Patient_email(&p, patient)
    extract_Patient_family(&p, patient)
    extract_Patient_gender(&p, patient)
    extract_Patient_general_practitioner(&p, patient)
    extract_Patient_given(&p, patient)
    extract_Patient_identifier(&p, patient)
    extract_Patient_language(&p, patient)
    extract_Patient_link(&p, patient)
    extract_Patient_name(&p, patient)
    extract_Patient_organization(&p, patient)
    extract_Patient_phone(&p, patient)
    extract_Patient_phonetic(&p, patient)
    extract_Patient_telecom(&p, patient)
    return p
}

// TODO: unhandled — _id [token] Patient.id
private func extract_Patient__id(_ p: inout SearchParams, _ patient: Patient) {}

// active [token] — Patient.active
private func extract_Patient_active(_ p: inout SearchParams, _ patient: Patient) {
    if let v = patient.active?.value?.bool {
        p.tokens.append(.init(paramName: "active", system: nil, code: v ? "true" : "false"))
    }
}

// address [string] — Patient.address
private func extract_Patient_address(_ p: inout SearchParams, _ patient: Patient) {
    for addr in patient.address ?? [] {
        if let v = addr.text?.value?.string       { p.strings.append(.init(paramName: "address", value: v)) }
        for line in addr.line ?? [] {
            if let v = line.value?.string          { p.strings.append(.init(paramName: "address", value: v)) }
        }
        if let v = addr.city?.value?.string        { p.strings.append(.init(paramName: "address", value: v)) }
        if let v = addr.state?.value?.string       { p.strings.append(.init(paramName: "address", value: v)) }
        if let v = addr.postalCode?.value?.string  { p.strings.append(.init(paramName: "address", value: v)) }
        if let v = addr.country?.value?.string     { p.strings.append(.init(paramName: "address", value: v)) }
    }
}

// address-city [string] — Patient.address.city
private func extract_Patient_address_city(_ p: inout SearchParams, _ patient: Patient) {
    for addr in patient.address ?? [] {
        if let v = addr.city?.value?.string { p.strings.append(.init(paramName: "address-city", value: v)) }
    }
}

// address-country [string] — Patient.address.country
private func extract_Patient_address_country(_ p: inout SearchParams, _ patient: Patient) {
    for addr in patient.address ?? [] {
        if let v = addr.country?.value?.string { p.strings.append(.init(paramName: "address-country", value: v)) }
    }
}

// address-postalcode [string] — Patient.address.postalCode
private func extract_Patient_address_postalcode(_ p: inout SearchParams, _ patient: Patient) {
    for addr in patient.address ?? [] {
        if let v = addr.postalCode?.value?.string { p.strings.append(.init(paramName: "address-postalcode", value: v)) }
    }
}

// address-state [string] — Patient.address.state
private func extract_Patient_address_state(_ p: inout SearchParams, _ patient: Patient) {
    for addr in patient.address ?? [] {
        if let v = addr.state?.value?.string { p.strings.append(.init(paramName: "address-state", value: v)) }
    }
}

// address-use [token] — Patient.address.use
private func extract_Patient_address_use(_ p: inout SearchParams, _ patient: Patient) {
    for addr in patient.address ?? [] {
        if let v = addr.use?.value?.rawValue {
            p.tokens.append(.init(paramName: "address-use",
                                  system: "http://hl7.org/fhir/address-use", code: v))
        }
    }
}

// birthdate [date] — Patient.birthDate
private func extract_Patient_birthdate(_ p: inout SearchParams, _ patient: Patient) {
    guard let bd = patient.birthDate?.value else { return }
    var dc = DateComponents()
    dc.year  = bd.year
    dc.month = bd.month.map(Int.init)
    dc.day   = bd.day.map(Int.init)
    dc.hour  = 12
    let date = Calendar(identifier: .gregorian).date(from: dc) ?? Date()
    p.dates.append(.init(paramName: "birthdate", dateStart: date, dateEnd: date))
}

// death-date [date] — Patient.deceased
private func extract_Patient_death_date(_ p: inout SearchParams, _ patient: Patient) {
    guard case .dateTime(let prim) = patient.deceased, let dt = prim.value else { return }
    var dc = DateComponents()
    dc.year = dt.date.year; dc.month = dt.date.month.map(Int.init)
    dc.day  = dt.date.day.map(Int.init); dc.hour = 12
    dc.timeZone = dt.timeZone
    let d = Calendar(identifier: .gregorian).date(from: dc) ?? Date()
    p.dates.append(.init(paramName: "death-date", dateStart: d, dateEnd: d))
}

// deceased [token] — Patient.deceased
private func extract_Patient_deceased(_ p: inout SearchParams, _ patient: Patient) {
    switch patient.deceased {
    case .boolean(let prim):
        guard let v = prim.value?.bool else { return }
        p.tokens.append(.init(paramName: "deceased", system: nil, code: v ? "true" : "false"))
    case .dateTime:
        p.tokens.append(.init(paramName: "deceased", system: nil, code: "true"))
    case nil:
        break
    }
}

// email [token] — Patient.telecom
private func extract_Patient_email(_ p: inout SearchParams, _ patient: Patient) {
    for cp in patient.telecom ?? [] {
        let cpSystem = cp.system?.value?.rawValue
        let cpValue  = cp.value?.value?.string ?? ""
        p.tokens.append(.init(paramName: "email", system: cpSystem, code: cpValue))
    }
}

// family [string] — Patient.name.family
private func extract_Patient_family(_ p: inout SearchParams, _ patient: Patient) {
    for name in patient.name ?? [] {
        if let v = name.family?.value?.string { p.strings.append(.init(paramName: "family", value: v)) }
    }
}

// gender [token] — Patient.gender
private func extract_Patient_gender(_ p: inout SearchParams, _ patient: Patient) {
    if let v = patient.gender?.value?.rawValue {
        p.tokens.append(.init(paramName: "gender",
                              system: "http://hl7.org/fhir/administrative-gender", code: v))
    }
}

// general-practitioner [reference] — Patient.generalPractitioner
private func extract_Patient_general_practitioner(_ p: inout SearchParams, _ patient: Patient) {
    for ref in patient.generalPractitioner ?? [] {
        guard let refStr = ref.reference?.value?.string else { continue }
        let parts = refStr.split(separator: "/")
        let (refType, refId): (String?, String) = parts.count == 2
            ? (String(parts[0]), String(parts[1]))
            : (nil, refStr)
        p.references.append(.init(paramName: "general-practitioner", refType: refType, refId: refId))
    }
}

// given [string] — Patient.name.given
private func extract_Patient_given(_ p: inout SearchParams, _ patient: Patient) {
    for name in patient.name ?? [] {
        for given in name.given ?? [] {
            if let v = given.value?.string { p.strings.append(.init(paramName: "given", value: v)) }
        }
    }
}

// identifier [token] — Patient.identifier
private func extract_Patient_identifier(_ p: inout SearchParams, _ patient: Patient) {
    for ident in patient.identifier ?? [] {
        let identValue  = ident.value?.value?.string ?? ""
        let identSystem = ident.system?.value?.url.absoluteString
        p.tokens.append(.init(paramName: "identifier", system: identSystem, code: identValue))
    }
}

// language [token] — Patient.communication.language
private func extract_Patient_language(_ p: inout SearchParams, _ patient: Patient) {
    for comm in patient.communication ?? [] {
        for coding in comm.language.coding ?? [] {
            let c = coding.code?.value?.string ?? ""
            let s = coding.system?.value?.url.absoluteString
            p.appendToken(paramName: "language", system: s, code: c, display: coding.display?.value?.string)
        }
        if let text = comm.language.text?.value?.string {
            p.tokens.append(.init(paramName: "language", system: nil, code: text))
        }
    }
}

// link [reference] — Patient.link.other
private func extract_Patient_link(_ p: inout SearchParams, _ patient: Patient) {
    for link in patient.link ?? [] {
        guard let refStr = link.other.reference?.value?.string else { continue }
        let parts = refStr.split(separator: "/")
        let (refType, refId): (String?, String) = parts.count == 2
            ? (String(parts[0]), String(parts[1]))
            : (nil, refStr)
        p.references.append(.init(paramName: "link", refType: refType, refId: refId))
    }
}

// name [string] — Patient.name
private func extract_Patient_name(_ p: inout SearchParams, _ patient: Patient) {
    for name in patient.name ?? [] {
        if let v = name.text?.value?.string   { p.strings.append(.init(paramName: "name", value: v)) }
        if let v = name.family?.value?.string { p.strings.append(.init(paramName: "name", value: v)) }
        for given in name.given ?? [] {
            if let v = given.value?.string { p.strings.append(.init(paramName: "name", value: v)) }
        }
    }
}

// organization [reference] — Patient.managingOrganization
private func extract_Patient_organization(_ p: inout SearchParams, _ patient: Patient) {
    guard let refStr = patient.managingOrganization?.reference?.value?.string else { return }
    let parts = refStr.split(separator: "/")
    let (refType, refId): (String?, String) = parts.count == 2
        ? (String(parts[0]), String(parts[1]))
        : (nil, refStr)
    p.references.append(.init(paramName: "organization", refType: refType, refId: refId))
}

// phone [token] — Patient.telecom
private func extract_Patient_phone(_ p: inout SearchParams, _ patient: Patient) {
    for cp in patient.telecom ?? [] {
        let cpSystem = cp.system?.value?.rawValue
        let cpValue  = cp.value?.value?.string ?? ""
        p.tokens.append(.init(paramName: "phone", system: cpSystem, code: cpValue))
    }
}

// phonetic [string] — Patient.name
private func extract_Patient_phonetic(_ p: inout SearchParams, _ patient: Patient) {
    for name in patient.name ?? [] {
        if let v = name.text?.value?.string   { p.strings.append(.init(paramName: "phonetic", value: v)) }
        if let v = name.family?.value?.string { p.strings.append(.init(paramName: "phonetic", value: v)) }
        for given in name.given ?? [] {
            if let v = given.value?.string { p.strings.append(.init(paramName: "phonetic", value: v)) }
        }
    }
}

// telecom [token] — Patient.telecom
private func extract_Patient_telecom(_ p: inout SearchParams, _ patient: Patient) {
    for cp in patient.telecom ?? [] {
        let cpSystem = cp.system?.value?.rawValue
        let cpValue  = cp.value?.value?.string ?? ""
        p.tokens.append(.init(paramName: "telecom", system: cpSystem, code: cpValue))
    }
}