// GENERATED — do not edit directly.
// Source: Resources/fhir/search-parameters-r4.json
// Regenerate: swift run SimingGenerator

import Foundation
import ModelsR4

/// Extracts all supported search parameters from a Location for insertion
/// into the five idx_* index tables.
///
/// Params marked TODO are recognised by the FHIR R4 spec but not yet implemented.
public func extractLocationSearchParams(_ loc: Location) -> SearchParams {
    var p = SearchParams()
    extract_Location_address(&p, loc)
    extract_Location_address_city(&p, loc)
    extract_Location_address_country(&p, loc)
    extract_Location_address_postalcode(&p, loc)
    extract_Location_address_state(&p, loc)
    extract_Location_address_use(&p, loc)
    extract_Location_endpoint(&p, loc)
    extract_Location_identifier(&p, loc)
    extract_Location_name(&p, loc)
    extract_Location_near(&p, loc)
    extract_Location_operational_status(&p, loc)
    extract_Location_organization(&p, loc)
    extract_Location_partof(&p, loc)
    extract_Location_status(&p, loc)
    extract_Location_type(&p, loc)
    return p
}

// address [string] — Location.address
private func extract_Location_address(_ p: inout SearchParams, _ loc: Location) {
    guard let addr = loc.address else { return }
    if let v = addr.text?.value?.string      { p.strings.append(.init(paramName: "address", value: v)) }
    for line in addr.line ?? [] {
        if let v = line.value?.string         { p.strings.append(.init(paramName: "address", value: v)) }
    }
    if let v = addr.city?.value?.string       { p.strings.append(.init(paramName: "address", value: v)) }
    if let v = addr.state?.value?.string      { p.strings.append(.init(paramName: "address", value: v)) }
    if let v = addr.postalCode?.value?.string { p.strings.append(.init(paramName: "address", value: v)) }
    if let v = addr.country?.value?.string    { p.strings.append(.init(paramName: "address", value: v)) }
}

// address-city [string] — Location.address.city
private func extract_Location_address_city(_ p: inout SearchParams, _ loc: Location) {
    if let v = loc.address?.city?.value?.string {
        p.strings.append(.init(paramName: "address-city", value: v))
    }
}

// address-country [string] — Location.address.country
private func extract_Location_address_country(_ p: inout SearchParams, _ loc: Location) {
    if let v = loc.address?.country?.value?.string {
        p.strings.append(.init(paramName: "address-country", value: v))
    }
}

// address-postalcode [string] — Location.address.postalCode
private func extract_Location_address_postalcode(_ p: inout SearchParams, _ loc: Location) {
    if let v = loc.address?.postalCode?.value?.string {
        p.strings.append(.init(paramName: "address-postalcode", value: v))
    }
}

// address-state [string] — Location.address.state
private func extract_Location_address_state(_ p: inout SearchParams, _ loc: Location) {
    if let v = loc.address?.state?.value?.string {
        p.strings.append(.init(paramName: "address-state", value: v))
    }
}

// address-use [token] — Location.address.use
private func extract_Location_address_use(_ p: inout SearchParams, _ loc: Location) {
    if let v = loc.address?.use?.value?.rawValue {
        p.tokens.append(.init(paramName: "address-use",
                              system: "http://hl7.org/fhir/address-use", code: v))
    }
}

// endpoint [reference] — Location.endpoint
private func extract_Location_endpoint(_ p: inout SearchParams, _ loc: Location) {
    for ref in loc.endpoint ?? [] {
        guard let refStr = ref.reference?.value?.string else { continue }
        let parts = refStr.split(separator: "/")
        let (refType, refId): (String?, String) = parts.count == 2
            ? (String(parts[0]), String(parts[1]))
            : (nil, refStr)
        p.references.append(.init(paramName: "endpoint", refType: refType, refId: refId))
    }
}

// identifier [token] — Location.identifier
private func extract_Location_identifier(_ p: inout SearchParams, _ loc: Location) {
    for ident in loc.identifier ?? [] {
        let v = ident.value?.value?.string ?? ""
        let s = ident.system?.value?.url.absoluteString
        p.tokens.append(.init(paramName: "identifier", system: s, code: v))
    }
}

// name [string] — Location.name
private func extract_Location_name(_ p: inout SearchParams, _ loc: Location) {
    if let v = loc.name?.value?.string { p.strings.append(.init(paramName: "name", value: v)) }
    for alias in loc.alias ?? [] {
        if let v = alias.value?.string { p.strings.append(.init(paramName: "name", value: v)) }
    }
}

// TODO: unhandled — near [special] Location.position
private func extract_Location_near(_ p: inout SearchParams, _ loc: Location) {}

// operational-status [token] — Location.operationalStatus
private func extract_Location_operational_status(_ p: inout SearchParams, _ loc: Location) {
    if let coding = loc.operationalStatus {
        let c = coding.code?.value?.string ?? ""
        let s = coding.system?.value?.url.absoluteString
        p.appendToken(paramName: "operational-status", system: s, code: c, display: coding.display?.value?.string)
    }
}

// organization [reference] — Location.managingOrganization
private func extract_Location_organization(_ p: inout SearchParams, _ loc: Location) {
    guard let refStr = loc.managingOrganization?.reference?.value?.string else { return }
    let parts = refStr.split(separator: "/")
    let (refType, refId): (String?, String) = parts.count == 2
        ? (String(parts[0]), String(parts[1]))
        : (nil, refStr)
    p.references.append(.init(paramName: "organization", refType: refType, refId: refId))
}

// partof [reference] — Location.partOf
private func extract_Location_partof(_ p: inout SearchParams, _ loc: Location) {
    guard let refStr = loc.partOf?.reference?.value?.string else { return }
    let parts = refStr.split(separator: "/")
    let (refType, refId): (String?, String) = parts.count == 2
        ? (String(parts[0]), String(parts[1]))
        : (nil, refStr)
    p.references.append(.init(paramName: "partof", refType: refType, refId: refId))
}

// status [token] — Location.status
private func extract_Location_status(_ p: inout SearchParams, _ loc: Location) {
    if let v = loc.status?.value?.rawValue {
        p.tokens.append(.init(paramName: "status",
                              system: "http://hl7.org/fhir/location-status", code: v))
    }
}

// type [token] — Location.type
private func extract_Location_type(_ p: inout SearchParams, _ loc: Location) {
    for t in loc.type ?? [] {
        for coding in t.coding ?? [] {
            let c = coding.code?.value?.string ?? ""
            let s = coding.system?.value?.url.absoluteString
            p.appendToken(paramName: "type", system: s, code: c, display: coding.display?.value?.string)
        }
    }
}