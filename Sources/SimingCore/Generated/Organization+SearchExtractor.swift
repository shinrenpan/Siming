// GENERATED — do not edit directly.
// Source: Resources/fhir/search-parameters-r4.json
// Regenerate: swift run SimingGenerator

import Foundation
import ModelsR4

/// Extracts all supported search parameters from an Organization for insertion
/// into the five idx_* index tables.
///
/// Params marked TODO are recognised by the FHIR R4 spec but not yet implemented.
public func extractOrganizationSearchParams(_ org: Organization) -> SearchParams {
    var p = SearchParams()
    extract_Organization_active(&p, org)
    extract_Organization_address(&p, org)
    extract_Organization_address_city(&p, org)
    extract_Organization_address_country(&p, org)
    extract_Organization_address_postalcode(&p, org)
    extract_Organization_address_state(&p, org)
    extract_Organization_address_use(&p, org)
    extract_Organization_endpoint(&p, org)
    extract_Organization_identifier(&p, org)
    extract_Organization_name(&p, org)
    extract_Organization_partof(&p, org)
    extract_Organization_phonetic(&p, org)
    extract_Organization_type(&p, org)
    return p
}

// active [token] — Organization.active
private func extract_Organization_active(_ p: inout SearchParams, _ org: Organization) {
    if let v = org.active?.value?.bool {
        p.tokens.append(.init(paramName: "active", system: nil, code: v ? "true" : "false"))
    }
}

// address [string] — Organization.address
private func extract_Organization_address(_ p: inout SearchParams, _ org: Organization) {
    for addr in org.address ?? [] {
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

// address-city [string] — Organization.address.city
private func extract_Organization_address_city(_ p: inout SearchParams, _ org: Organization) {
    for addr in org.address ?? [] {
        if let v = addr.city?.value?.string { p.strings.append(.init(paramName: "address-city", value: v)) }
    }
}

// address-country [string] — Organization.address.country
private func extract_Organization_address_country(_ p: inout SearchParams, _ org: Organization) {
    for addr in org.address ?? [] {
        if let v = addr.country?.value?.string { p.strings.append(.init(paramName: "address-country", value: v)) }
    }
}

// address-postalcode [string] — Organization.address.postalCode
private func extract_Organization_address_postalcode(_ p: inout SearchParams, _ org: Organization) {
    for addr in org.address ?? [] {
        if let v = addr.postalCode?.value?.string { p.strings.append(.init(paramName: "address-postalcode", value: v)) }
    }
}

// address-state [string] — Organization.address.state
private func extract_Organization_address_state(_ p: inout SearchParams, _ org: Organization) {
    for addr in org.address ?? [] {
        if let v = addr.state?.value?.string { p.strings.append(.init(paramName: "address-state", value: v)) }
    }
}

// address-use [token] — Organization.address.use
private func extract_Organization_address_use(_ p: inout SearchParams, _ org: Organization) {
    for addr in org.address ?? [] {
        if let v = addr.use?.value?.rawValue {
            p.tokens.append(.init(paramName: "address-use",
                                  system: "http://hl7.org/fhir/address-use", code: v))
        }
    }
}

// endpoint [reference] — Organization.endpoint
private func extract_Organization_endpoint(_ p: inout SearchParams, _ org: Organization) {
    for ref in org.endpoint ?? [] {
        guard let refStr = ref.reference?.value?.string else { continue }
        let parts = refStr.split(separator: "/")
        let (refType, refId): (String?, String) = parts.count == 2
            ? (String(parts[0]), String(parts[1]))
            : (nil, refStr)
        p.references.append(.init(paramName: "endpoint", refType: refType, refId: refId))
    }
}

// identifier [token] — Organization.identifier
private func extract_Organization_identifier(_ p: inout SearchParams, _ org: Organization) {
    for ident in org.identifier ?? [] {
        let v = ident.value?.value?.string ?? ""
        let s = ident.system?.value?.url.absoluteString
        p.tokens.append(.init(paramName: "identifier", system: s, code: v))
    }
}

// name [string] — Organization.name
private func extract_Organization_name(_ p: inout SearchParams, _ org: Organization) {
    if let v = org.name?.value?.string { p.strings.append(.init(paramName: "name", value: v)) }
    for alias in org.alias ?? [] {
        if let v = alias.value?.string { p.strings.append(.init(paramName: "name", value: v)) }
    }
}

// partof [reference] — Organization.partOf
private func extract_Organization_partof(_ p: inout SearchParams, _ org: Organization) {
    guard let refStr = org.partOf?.reference?.value?.string else { return }
    let parts = refStr.split(separator: "/")
    let (refType, refId): (String?, String) = parts.count == 2
        ? (String(parts[0]), String(parts[1]))
        : (nil, refStr)
    p.references.append(.init(paramName: "partof", refType: refType, refId: refId))
}

// phonetic [string] — Organization.name
private func extract_Organization_phonetic(_ p: inout SearchParams, _ org: Organization) {
    if let v = org.name?.value?.string { p.strings.append(.init(paramName: "phonetic", value: v)) }
    for alias in org.alias ?? [] {
        if let v = alias.value?.string { p.strings.append(.init(paramName: "phonetic", value: v)) }
    }
}

// type [token] — Organization.type
private func extract_Organization_type(_ p: inout SearchParams, _ org: Organization) {
    for t in org.type ?? [] {
        for coding in t.coding ?? [] {
            let c = coding.code?.value?.string ?? ""
            let s = coding.system?.value?.url.absoluteString
            p.tokens.append(.init(paramName: "type", system: s, code: c))
        }
    }
}