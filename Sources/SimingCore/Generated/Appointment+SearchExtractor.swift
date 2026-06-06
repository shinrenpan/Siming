// GENERATED — do not edit directly.
// Source: Resources/fhir/search-parameters-r4.json
// Regenerate: swift run SimingGenerator

import Foundation
import ModelsR4

/// Extracts all supported search parameters from an Appointment for insertion
/// into the five idx_* index tables.
public func extractAppointmentSearchParams(_ appt: Appointment) -> SearchParams {
    var p = SearchParams()
    extract_Appointment_actor(&p, appt)
    extract_Appointment_appointment_type(&p, appt)
    extract_Appointment_based_on(&p, appt)
    extract_Appointment_date(&p, appt)
    extract_Appointment_identifier(&p, appt)
    extract_Appointment_location(&p, appt)
    extract_Appointment_part_status(&p, appt)
    extract_Appointment_patient(&p, appt)
    extract_Appointment_practitioner(&p, appt)
    extract_Appointment_reason_code(&p, appt)
    extract_Appointment_reason_reference(&p, appt)
    extract_Appointment_service_category(&p, appt)
    extract_Appointment_service_type(&p, appt)
    extract_Appointment_slot(&p, appt)
    extract_Appointment_specialty(&p, appt)
    extract_Appointment_status(&p, appt)
    extract_Appointment_supporting_info(&p, appt)
    return p
}

// actor [reference] — Appointment.participant.actor
private func extract_Appointment_actor(_ p: inout SearchParams, _ appt: Appointment) {
    for participant in appt.participant {
        guard let refStr = participant.actor?.reference?.value?.string else { continue }
        let parts = refStr.split(separator: "/")
        let (refType, refId): (String?, String) = parts.count == 2
            ? (String(parts[0]), String(parts[1]))
            : (nil, refStr)
        p.references.append(.init(paramName: "actor", refType: refType, refId: refId))
    }
}

// appointment-type [token] — Appointment.appointmentType
private func extract_Appointment_appointment_type(_ p: inout SearchParams, _ appt: Appointment) {
    for coding in appt.appointmentType?.coding ?? [] {
        let v = coding.code?.value?.string ?? ""
        let s = coding.system?.value?.url.absoluteString
        p.tokens.append(.init(paramName: "appointment-type", system: s, code: v))
    }
}

// based-on [reference] — Appointment.basedOn
private func extract_Appointment_based_on(_ p: inout SearchParams, _ appt: Appointment) {
    for ref in appt.basedOn ?? [] {
        guard let refStr = ref.reference?.value?.string else { continue }
        let parts = refStr.split(separator: "/")
        let (refType, refId): (String?, String) = parts.count == 2
            ? (String(parts[0]), String(parts[1]))
            : (nil, refStr)
        p.references.append(.init(paramName: "based-on", refType: refType, refId: refId))
    }
}

// date [date] — Appointment.start
private func extract_Appointment_date(_ p: inout SearchParams, _ appt: Appointment) {
    guard let inst = appt.start?.value else { return }
    var dc = DateComponents()
    dc.year     = inst.date.year
    dc.month    = Int(inst.date.month)
    dc.day      = Int(inst.date.day)
    dc.hour     = Int(inst.time.hour)
    dc.minute   = Int(inst.time.minute)
    dc.second   = Int(truncating: inst.time.second as NSDecimalNumber)
    dc.timeZone = inst.timeZone
    let d = Calendar(identifier: .gregorian).date(from: dc) ?? Date()
    p.dates.append(.init(paramName: "date", dateStart: d, dateEnd: d))
}

// identifier [token] — Appointment.identifier
private func extract_Appointment_identifier(_ p: inout SearchParams, _ appt: Appointment) {
    for ident in appt.identifier ?? [] {
        let v = ident.value?.value?.string ?? ""
        let s = ident.system?.value?.url.absoluteString
        p.tokens.append(.init(paramName: "identifier", system: s, code: v))
    }
}

// location [reference] — Appointment.participant.actor
private func extract_Appointment_location(_ p: inout SearchParams, _ appt: Appointment) {
    for participant in appt.participant {
        guard let refStr = participant.actor?.reference?.value?.string else { continue }
        let parts = refStr.split(separator: "/")
        let (refType, refId): (String?, String) = parts.count == 2
            ? (String(parts[0]), String(parts[1]))
            : (nil, refStr)
        p.references.append(.init(paramName: "location", refType: refType, refId: refId))
    }
}

// part-status [token] — Appointment.participant.status
private func extract_Appointment_part_status(_ p: inout SearchParams, _ appt: Appointment) {
    for participant in appt.participant {
        if let v = participant.status.value?.rawValue {
            p.tokens.append(.init(paramName: "part-status", system: nil, code: v))
        }
    }
}

// patient [reference] — Appointment.participant.actor
private func extract_Appointment_patient(_ p: inout SearchParams, _ appt: Appointment) {
    for participant in appt.participant {
        guard let refStr = participant.actor?.reference?.value?.string else { continue }
        let parts = refStr.split(separator: "/")
        let (refType, refId): (String?, String) = parts.count == 2
            ? (String(parts[0]), String(parts[1]))
            : (nil, refStr)
        p.references.append(.init(paramName: "patient", refType: refType, refId: refId))
    }
}

// practitioner [reference] — Appointment.participant.actor
private func extract_Appointment_practitioner(_ p: inout SearchParams, _ appt: Appointment) {
    for participant in appt.participant {
        guard let refStr = participant.actor?.reference?.value?.string else { continue }
        let parts = refStr.split(separator: "/")
        let (refType, refId): (String?, String) = parts.count == 2
            ? (String(parts[0]), String(parts[1]))
            : (nil, refStr)
        p.references.append(.init(paramName: "practitioner", refType: refType, refId: refId))
    }
}

// reason-code [token] — Appointment.reasonCode
private func extract_Appointment_reason_code(_ p: inout SearchParams, _ appt: Appointment) {
    for cc in appt.reasonCode ?? [] {
        for coding in cc.coding ?? [] {
            let v = coding.code?.value?.string ?? ""
            let s = coding.system?.value?.url.absoluteString
            p.tokens.append(.init(paramName: "reason-code", system: s, code: v))
        }
    }
}

// reason-reference [reference] — Appointment.reasonReference
private func extract_Appointment_reason_reference(_ p: inout SearchParams, _ appt: Appointment) {
    for ref in appt.reasonReference ?? [] {
        guard let refStr = ref.reference?.value?.string else { continue }
        let parts = refStr.split(separator: "/")
        let (refType, refId): (String?, String) = parts.count == 2
            ? (String(parts[0]), String(parts[1]))
            : (nil, refStr)
        p.references.append(.init(paramName: "reason-reference", refType: refType, refId: refId))
    }
}

// service-category [token] — Appointment.serviceCategory
private func extract_Appointment_service_category(_ p: inout SearchParams, _ appt: Appointment) {
    for cc in appt.serviceCategory ?? [] {
        for coding in cc.coding ?? [] {
            let v = coding.code?.value?.string ?? ""
            let s = coding.system?.value?.url.absoluteString
            p.tokens.append(.init(paramName: "service-category", system: s, code: v))
        }
    }
}

// service-type [token] — Appointment.serviceType
private func extract_Appointment_service_type(_ p: inout SearchParams, _ appt: Appointment) {
    for cc in appt.serviceType ?? [] {
        for coding in cc.coding ?? [] {
            let v = coding.code?.value?.string ?? ""
            let s = coding.system?.value?.url.absoluteString
            p.tokens.append(.init(paramName: "service-type", system: s, code: v))
        }
    }
}

// slot [reference] — Appointment.slot
private func extract_Appointment_slot(_ p: inout SearchParams, _ appt: Appointment) {
    for ref in appt.slot ?? [] {
        guard let refStr = ref.reference?.value?.string else { continue }
        let parts = refStr.split(separator: "/")
        let (refType, refId): (String?, String) = parts.count == 2
            ? (String(parts[0]), String(parts[1]))
            : (nil, refStr)
        p.references.append(.init(paramName: "slot", refType: refType, refId: refId))
    }
}

// specialty [token] — Appointment.specialty
private func extract_Appointment_specialty(_ p: inout SearchParams, _ appt: Appointment) {
    for cc in appt.specialty ?? [] {
        for coding in cc.coding ?? [] {
            let v = coding.code?.value?.string ?? ""
            let s = coding.system?.value?.url.absoluteString
            p.tokens.append(.init(paramName: "specialty", system: s, code: v))
        }
    }
}

// status [token] — Appointment.status
private func extract_Appointment_status(_ p: inout SearchParams, _ appt: Appointment) {
    if let v = appt.status.value?.rawValue {
        p.tokens.append(.init(paramName: "status", system: nil, code: v))
    }
}

// TODO: unhandled — supporting-info [reference] Appointment.supportingInformation
private func extract_Appointment_supporting_info(_ p: inout SearchParams, _ appt: Appointment) {}