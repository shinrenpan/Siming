// GENERATED — do not edit directly.
// Source: packages/*.tgz (hl7.fhir.r4.core + tw.gov.mohw.twcore)
// Regenerate: swift run SimingGenerator

import Foundation
import ModelsR4

/// Extracts all supported search parameters from a Device for insertion
/// into the five idx_* index tables.
///
/// Params marked TODO are recognised by the FHIR R4 spec but not yet implemented.
public func extractDeviceSearchParams(_ d: Device) -> SearchParams {
    var p = SearchParams()
    extract_Device_device_name(&p, d)
    extract_Device_identifier(&p, d)
    extract_Device_location(&p, d)
    extract_Device_manufacturer(&p, d)
    extract_Device_model(&p, d)
    extract_Device_organization(&p, d)
    extract_Device_patient(&p, d)
    extract_Device_status(&p, d)
    extract_Device_type(&p, d)
    extract_Device_udi_carrier(&p, d)
    extract_Device_udi_di(&p, d)
    extract_Device_url(&p, d)
    return p
}

// device-name [string] — Device.deviceName.name | Device.type.coding.display | Device.type.text
private func extract_Device_device_name(_ p: inout SearchParams, _ d: Device) {
    for dn in d.deviceName ?? [] {
        if let v = dn.name.value?.string { p.strings.append(.init(paramName: "device-name", value: v)) }
    }
    for coding in d.type?.coding ?? [] {
        if let v = coding.display?.value?.string { p.strings.append(.init(paramName: "device-name", value: v)) }
    }
    if let v = d.type?.text?.value?.string { p.strings.append(.init(paramName: "device-name", value: v)) }
}

// identifier [token] — Device.identifier
private func extract_Device_identifier(_ p: inout SearchParams, _ d: Device) {
    for ident in d.identifier ?? [] {
        let v = ident.value?.value?.string ?? ""
        let sys = ident.system?.value?.url.absoluteString
        p.tokens.append(.init(paramName: "identifier", system: sys, code: v))
    }
}

// location [reference] — Device.location
private func extract_Device_location(_ p: inout SearchParams, _ d: Device) {
    guard let refStr = d.location?.reference?.value?.string else { return }
    let parts = refStr.split(separator: "/")
    let (refType, refId): (String?, String) = parts.count == 2
        ? (String(parts[0]), String(parts[1]))
        : (nil, refStr)
    p.references.append(.init(paramName: "location", refType: refType, refId: refId))
}

// manufacturer [string] — Device.manufacturer
private func extract_Device_manufacturer(_ p: inout SearchParams, _ d: Device) {
    if let v = d.manufacturer?.value?.string { p.strings.append(.init(paramName: "manufacturer", value: v)) }
}

// model [string] — Device.modelNumber
private func extract_Device_model(_ p: inout SearchParams, _ d: Device) {
    if let v = d.modelNumber?.value?.string { p.strings.append(.init(paramName: "model", value: v)) }
}

// organization [reference] — Device.owner
private func extract_Device_organization(_ p: inout SearchParams, _ d: Device) {
    guard let refStr = d.owner?.reference?.value?.string else { return }
    let parts = refStr.split(separator: "/")
    let (refType, refId): (String?, String) = parts.count == 2
        ? (String(parts[0]), String(parts[1]))
        : (nil, refStr)
    p.references.append(.init(paramName: "organization", refType: refType, refId: refId))
}

// patient [reference] — Device.patient
private func extract_Device_patient(_ p: inout SearchParams, _ d: Device) {
    guard let refStr = d.patient?.reference?.value?.string else { return }
    let parts = refStr.split(separator: "/")
    let (refType, refId): (String?, String) = parts.count == 2
        ? (String(parts[0]), String(parts[1]))
        : (nil, refStr)
    p.references.append(.init(paramName: "patient", refType: refType, refId: refId))
}

// status [token] — Device.status
private func extract_Device_status(_ p: inout SearchParams, _ d: Device) {
    if let v = d.status?.value?.rawValue {
        p.tokens.append(.init(paramName: "status",
                              system: "http://hl7.org/fhir/device-status", code: v))
    }
}

// type [token] — Device.type
private func extract_Device_type(_ p: inout SearchParams, _ d: Device) {
    for coding in d.type?.coding ?? [] {
        let c = coding.code?.value?.string ?? ""
        let s = coding.system?.value?.url.absoluteString
        p.appendToken(paramName: "type", system: s, code: c, display: coding.display?.value?.string)
    }
    p.appendConceptText(paramName: "type", d.type?.text?.value?.string)
}

// udi-carrier [string] — Device.udiCarrier.carrierHRF
private func extract_Device_udi_carrier(_ p: inout SearchParams, _ d: Device) {
    for udi in d.udiCarrier ?? [] {
        if let v = udi.carrierHRF?.value?.string { p.strings.append(.init(paramName: "udi-carrier", value: v)) }
    }
}

// udi-di [string] — Device.udiCarrier.deviceIdentifier
private func extract_Device_udi_di(_ p: inout SearchParams, _ d: Device) {
    for udi in d.udiCarrier ?? [] {
        if let v = udi.deviceIdentifier?.value?.string { p.strings.append(.init(paramName: "udi-di", value: v)) }
    }
}

// url [uri] — Device.url
private func extract_Device_url(_ p: inout SearchParams, _ d: Device) {
    if let v = d.url?.value?.url.absoluteString { p.strings.append(.init(paramName: "url", value: v)) }
}