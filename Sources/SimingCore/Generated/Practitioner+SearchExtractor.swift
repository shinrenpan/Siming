// GENERATED — do not edit directly.
// Source: Resources/fhir/search-parameters-r4.json
// Regenerate: swift run SimingGenerator

import Foundation
import ModelsR4

/// Extracts all supported search parameters from a Practitioner for insertion
/// into the five idx_* index tables.
///
/// Params marked TODO are recognised by the FHIR R4 spec but not yet implemented.
public func extractPractitionerSearchParams(_ prac: Practitioner) -> SearchParams {
    var p = SearchParams()
    extract_Practitioner_active(&p, prac)
    extract_Practitioner_address(&p, prac)
    extract_Practitioner_address_city(&p, prac)
    extract_Practitioner_address_country(&p, prac)
    extract_Practitioner_address_postalcode(&p, prac)
    extract_Practitioner_address_state(&p, prac)
    extract_Practitioner_address_use(&p, prac)
    extract_Practitioner_communication(&p, prac)
    extract_Practitioner_email(&p, prac)
    extract_Practitioner_family(&p, prac)
    extract_Practitioner_gender(&p, prac)
    extract_Practitioner_given(&p, prac)
    extract_Practitioner_identifier(&p, prac)
    extract_Practitioner_name(&p, prac)
    extract_Practitioner_phone(&p, prac)
    extract_Practitioner_phonetic(&p, prac)
    extract_Practitioner_telecom(&p, prac)
    return p
}

// active [token] — Practitioner.active
private func extract_Practitioner_active(_ p: inout SearchParams, _ prac: Practitioner) {
    if let v = prac.active?.value?.bool {
        p.tokens.append(.init(paramName: "active", system: nil, code: v ? "true" : "false"))
    }
}

// address [string] — Practitioner.address
private func extract_Practitioner_address(_ p: inout SearchParams, _ prac: Practitioner) {
    for addr in prac.address ?? [] {
        if let v = addr.text?.value?.string      { p.strings.append(.init(paramName: "address", value: v)) }
        for line in addr.line ?? [] {
            if let v = line.value?.string         { p.strings.append(.init(paramName: "address", value: v)) }
        }
        if let v = addr.city?.value?.string       { p.strings.append(.init(paramName: "address", value: v)) }
        if let v = addr.state?.value?.string      { p.strings.append(.init(paramName: "address", value: v)) }
        if let v = addr.postalCode?.value?.string { p.strings.append(.init(paramName: "address", value: v)) }
        if let v = addr.country?.value?.string    { p.strings.append(.init(paramName: "address", value: v)) }
    }
}

// address-city [string] — Practitioner.address.city
private func extract_Practitioner_address_city(_ p: inout SearchParams, _ prac: Practitioner) {
    for addr in prac.address ?? [] {
        if let v = addr.city?.value?.string { p.strings.append(.init(paramName: "address-city", value: v)) }
    }
}

// address-country [string] — Practitioner.address.country
private func extract_Practitioner_address_country(_ p: inout SearchParams, _ prac: Practitioner) {
    for addr in prac.address ?? [] {
        if let v = addr.country?.value?.string { p.strings.append(.init(paramName: "address-country", value: v)) }
    }
}

// address-postalcode [string] — Practitioner.address.postalCode
private func extract_Practitioner_address_postalcode(_ p: inout SearchParams, _ prac: Practitioner) {
    for addr in prac.address ?? [] {
        if let v = addr.postalCode?.value?.string { p.strings.append(.init(paramName: "address-postalcode", value: v)) }
    }
}

// address-state [string] — Practitioner.address.state
private func extract_Practitioner_address_state(_ p: inout SearchParams, _ prac: Practitioner) {
    for addr in prac.address ?? [] {
        if let v = addr.state?.value?.string { p.strings.append(.init(paramName: "address-state", value: v)) }
    }
}

// address-use [token] — Practitioner.address.use
private func extract_Practitioner_address_use(_ p: inout SearchParams, _ prac: Practitioner) {
    for addr in prac.address ?? [] {
        if let v = addr.use?.value?.rawValue {
            p.tokens.append(.init(paramName: "address-use",
                                  system: "http://hl7.org/fhir/address-use", code: v))
        }
    }
}

// communication [token] — Practitioner.communication
private func extract_Practitioner_communication(_ p: inout SearchParams, _ prac: Practitioner) {
    for comm in prac.communication ?? [] {
        for coding in comm.coding ?? [] {
            let c = coding.code?.value?.string ?? ""
            let s = coding.system?.value?.url.absoluteString
            p.tokens.append(.init(paramName: "communication", system: s, code: c))
        }
    }
}

// email [token] — Practitioner.telecom
private func extract_Practitioner_email(_ p: inout SearchParams, _ prac: Practitioner) {
    for cp in prac.telecom ?? [] {
        let s = cp.system?.value?.rawValue
        let v = cp.value?.value?.string ?? ""
        p.tokens.append(.init(paramName: "email", system: s, code: v))
    }
}

// family [string] — Practitioner.name.family
private func extract_Practitioner_family(_ p: inout SearchParams, _ prac: Practitioner) {
    for name in prac.name ?? [] {
        if let v = name.family?.value?.string { p.strings.append(.init(paramName: "family", value: v)) }
    }
}

// gender [token] — Practitioner.gender
private func extract_Practitioner_gender(_ p: inout SearchParams, _ prac: Practitioner) {
    if let v = prac.gender?.value?.rawValue {
        p.tokens.append(.init(paramName: "gender",
                              system: "http://hl7.org/fhir/administrative-gender", code: v))
    }
}

// given [string] — Practitioner.name.given
private func extract_Practitioner_given(_ p: inout SearchParams, _ prac: Practitioner) {
    for name in prac.name ?? [] {
        for given in name.given ?? [] {
            if let v = given.value?.string { p.strings.append(.init(paramName: "given", value: v)) }
        }
    }
}

// identifier [token] — Practitioner.identifier
private func extract_Practitioner_identifier(_ p: inout SearchParams, _ prac: Practitioner) {
    for ident in prac.identifier ?? [] {
        let v = ident.value?.value?.string ?? ""
        let s = ident.system?.value?.url.absoluteString
        p.tokens.append(.init(paramName: "identifier", system: s, code: v))
    }
}

// name [string] — Practitioner.name
private func extract_Practitioner_name(_ p: inout SearchParams, _ prac: Practitioner) {
    for name in prac.name ?? [] {
        if let v = name.text?.value?.string   { p.strings.append(.init(paramName: "name", value: v)) }
        if let v = name.family?.value?.string { p.strings.append(.init(paramName: "name", value: v)) }
        for given in name.given ?? [] {
            if let v = given.value?.string { p.strings.append(.init(paramName: "name", value: v)) }
        }
    }
}

// phone [token] — Practitioner.telecom
private func extract_Practitioner_phone(_ p: inout SearchParams, _ prac: Practitioner) {
    for cp in prac.telecom ?? [] {
        let s = cp.system?.value?.rawValue
        let v = cp.value?.value?.string ?? ""
        p.tokens.append(.init(paramName: "phone", system: s, code: v))
    }
}

// phonetic [string] — Practitioner.name
private func extract_Practitioner_phonetic(_ p: inout SearchParams, _ prac: Practitioner) {
    for name in prac.name ?? [] {
        if let v = name.text?.value?.string   { p.strings.append(.init(paramName: "phonetic", value: v)) }
        if let v = name.family?.value?.string { p.strings.append(.init(paramName: "phonetic", value: v)) }
        for given in name.given ?? [] {
            if let v = given.value?.string { p.strings.append(.init(paramName: "phonetic", value: v)) }
        }
    }
}

// telecom [token] — Practitioner.telecom
private func extract_Practitioner_telecom(_ p: inout SearchParams, _ prac: Practitioner) {
    for cp in prac.telecom ?? [] {
        let s = cp.system?.value?.rawValue
        let v = cp.value?.value?.string ?? ""
        p.tokens.append(.init(paramName: "telecom", system: s, code: v))
    }
}