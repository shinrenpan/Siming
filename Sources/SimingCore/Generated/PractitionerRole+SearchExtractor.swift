// GENERATED — do not edit directly.
// Source: packages/*.tgz (hl7.fhir.r4.core + tw.gov.mohw.twcore)
// Regenerate: swift run SimingGenerator

import Foundation
import ModelsR4

/// Extracts all supported search parameters from a PractitionerRole for insertion
/// into the five idx_* index tables.
///
/// Params marked TODO are recognised by the FHIR R4 spec but not yet implemented.
public func extractPractitionerRoleSearchParams(_ role: PractitionerRole) -> SearchParams {
    var p = SearchParams()
    extract_PractitionerRole_active(&p, role)
    extract_PractitionerRole_date(&p, role)
    extract_PractitionerRole_email(&p, role)
    extract_PractitionerRole_endpoint(&p, role)
    extract_PractitionerRole_identifier(&p, role)
    extract_PractitionerRole_location(&p, role)
    extract_PractitionerRole_organization(&p, role)
    extract_PractitionerRole_phone(&p, role)
    extract_PractitionerRole_practitioner(&p, role)
    extract_PractitionerRole_role(&p, role)
    extract_PractitionerRole_service(&p, role)
    extract_PractitionerRole_specialty(&p, role)
    extract_PractitionerRole_telecom(&p, role)
    return p
}

// TODO: unhandled — active [token] PractitionerRole.active
private func extract_PractitionerRole_active(_ p: inout SearchParams, _ role: PractitionerRole) {}

// TODO: unhandled — date [date] PractitionerRole.period
private func extract_PractitionerRole_date(_ p: inout SearchParams, _ role: PractitionerRole) {}

// TODO: unhandled — email [token] Patient.telecom.where(system='email') | Person.telecom.where(system='email') | Practitioner.telecom.where(system='email') | PractitionerRole.telecom.where(system='email') | RelatedPerson.telecom.where(system='email')
private func extract_PractitionerRole_email(_ p: inout SearchParams, _ role: PractitionerRole) {}

// TODO: unhandled — endpoint [reference] PractitionerRole.endpoint
private func extract_PractitionerRole_endpoint(_ p: inout SearchParams, _ role: PractitionerRole) {}

// TODO: unhandled — identifier [token] PractitionerRole.identifier
private func extract_PractitionerRole_identifier(_ p: inout SearchParams, _ role: PractitionerRole) {}

// TODO: unhandled — location [reference] PractitionerRole.location
private func extract_PractitionerRole_location(_ p: inout SearchParams, _ role: PractitionerRole) {}

// TODO: unhandled — organization [reference] PractitionerRole.organization
private func extract_PractitionerRole_organization(_ p: inout SearchParams, _ role: PractitionerRole) {}

// TODO: unhandled — phone [token] Patient.telecom.where(system='phone') | Person.telecom.where(system='phone') | Practitioner.telecom.where(system='phone') | PractitionerRole.telecom.where(system='phone') | RelatedPerson.telecom.where(system='phone')
private func extract_PractitionerRole_phone(_ p: inout SearchParams, _ role: PractitionerRole) {}

// practitioner [reference] — PractitionerRole.practitioner
private func extract_PractitionerRole_practitioner(_ p: inout SearchParams, _ role: PractitionerRole) {
    guard let refStr = role.practitioner?.reference?.value?.string else { return }
    let parts = refStr.split(separator: "/")
    let (refType, refId): (String?, String) = parts.count == 2
        ? (String(parts[0]), String(parts[1]))
        : (nil, refStr)
    p.references.append(.init(paramName: "practitioner", refType: refType, refId: refId))
}

// TODO: unhandled — role [token] PractitionerRole.code
private func extract_PractitionerRole_role(_ p: inout SearchParams, _ role: PractitionerRole) {}

// TODO: unhandled — service [reference] PractitionerRole.healthcareService
private func extract_PractitionerRole_service(_ p: inout SearchParams, _ role: PractitionerRole) {}

// TODO: unhandled — specialty [token] PractitionerRole.specialty
private func extract_PractitionerRole_specialty(_ p: inout SearchParams, _ role: PractitionerRole) {}

// TODO: unhandled — telecom [token] Patient.telecom | Person.telecom | Practitioner.telecom | PractitionerRole.telecom | RelatedPerson.telecom
private func extract_PractitionerRole_telecom(_ p: inout SearchParams, _ role: PractitionerRole) {}