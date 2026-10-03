// GENERATED — do not edit directly.
// Source: packages/*.tgz (hl7.fhir.r4.core + tw.gov.mohw.twcore)
// Regenerate: swift run SimingGenerator

import Foundation
import ModelsR4

/// Extracts all supported search parameters from a QuestionnaireResponse for insertion
/// into the five idx_* index tables.
///
/// Params marked TODO are recognised by the FHIR R4 spec but not yet implemented.
public func extractQuestionnaireResponseSearchParams(_ q: QuestionnaireResponse) -> SearchParams {
    var p = SearchParams()
    extract_QuestionnaireResponse_author(&p, q)
    extract_QuestionnaireResponse_authored(&p, q)
    extract_QuestionnaireResponse_based_on(&p, q)
    extract_QuestionnaireResponse_encounter(&p, q)
    extract_QuestionnaireResponse_identifier(&p, q)
    extract_QuestionnaireResponse_item_subject(&p, q)
    extract_QuestionnaireResponse_part_of(&p, q)
    extract_QuestionnaireResponse_patient(&p, q)
    extract_QuestionnaireResponse_questionnaire(&p, q)
    extract_QuestionnaireResponse_source(&p, q)
    extract_QuestionnaireResponse_status(&p, q)
    extract_QuestionnaireResponse_subject(&p, q)
    return p
}

// author [reference] — QuestionnaireResponse.author
private func extract_QuestionnaireResponse_author(_ p: inout SearchParams, _ q: QuestionnaireResponse) {
    guard let refStr = q.author?.reference?.value?.string else { return }
    let parts = refStr.split(separator: "/")
    let (refType, refId): (String?, String) = parts.count == 2
        ? (String(parts[0]), String(parts[1]))
        : (nil, refStr)
    p.references.append(.init(paramName: "author", refType: refType, refId: refId))
}

// authored [date] — QuestionnaireResponse.authored
private func extract_QuestionnaireResponse_authored(_ p: inout SearchParams, _ q: QuestionnaireResponse) {
    guard let prim = q.authored, let dt = prim.value else { return }
    let cal = Calendar(identifier: .gregorian)
    var dc = DateComponents()
    dc.year = dt.date.year; dc.month = dt.date.month.map(Int.init)
    dc.day  = dt.date.day.map(Int.init)
    // A dateTime carrying a time keeps it; a date-only value stays anchored at
    // midday so it sits well inside the day whatever offset it is compared against.
    // The zone must be explicit — falling through to the host's zone makes the
    // stored value depend on where the server happens to run.
    dc.hour   = dt.time.map { Int($0.hour) } ?? 12
    dc.minute = dt.time.map { Int($0.minute) } ?? 0
    dc.second = dt.time.map { min(Int(truncating: $0.second as NSDecimalNumber), 59) } ?? 0
    dc.timeZone = dt.timeZone ?? TimeZone(secondsFromGMT: 0)
    let d = cal.date(from: dc) ?? Date()
    p.dates.append(.init(paramName: "authored", dateStart: d, dateEnd: d))
}

// based-on [reference] — QuestionnaireResponse.basedOn
private func extract_QuestionnaireResponse_based_on(_ p: inout SearchParams, _ q: QuestionnaireResponse) {
    for ref in q.basedOn ?? [] {
        guard let refStr = ref.reference?.value?.string else { continue }
        let parts = refStr.split(separator: "/")
        let (refType, refId): (String?, String) = parts.count == 2
            ? (String(parts[0]), String(parts[1]))
            : (nil, refStr)
        p.references.append(.init(paramName: "based-on", refType: refType, refId: refId))
    }
}

// encounter [reference] — QuestionnaireResponse.encounter
private func extract_QuestionnaireResponse_encounter(_ p: inout SearchParams, _ q: QuestionnaireResponse) {
    guard let refStr = q.encounter?.reference?.value?.string else { return }
    let parts = refStr.split(separator: "/")
    let (refType, refId): (String?, String) = parts.count == 2
        ? (String(parts[0]), String(parts[1]))
        : (nil, refStr)
    p.references.append(.init(paramName: "encounter", refType: refType, refId: refId))
}

// identifier [token] — QuestionnaireResponse.identifier
private func extract_QuestionnaireResponse_identifier(_ p: inout SearchParams, _ q: QuestionnaireResponse) {
    guard let ident = q.identifier else { return }
    let v = ident.value?.value?.string ?? ""
    let sys = ident.system?.value?.url.absoluteString
    p.tokens.append(.init(paramName: "identifier", system: sys, code: v))
}

// item-subject [reference] — QuestionnaireResponse.item.where(hasExtension('http://hl7.org/fhir/StructureDefinition/questionnaireresponse-isSubject')).answer.value.ofType(Reference)
private func extract_QuestionnaireResponse_item_subject(_ p: inout SearchParams, _ q: QuestionnaireResponse) {
    let isSubject = "http://hl7.org/fhir/StructureDefinition/questionnaireresponse-isSubject"
    for item in q.item ?? [] where (item.extension ?? []).contains(where: { $0.url.value?.url.absoluteString == isSubject }) {
        for answer in item.answer ?? [] {
            guard case .reference(let ref)? = answer.value,
                  let refStr = ref.reference?.value?.string else { continue }
            let parts = refStr.split(separator: "/")
            let (refType, refId): (String?, String) = parts.count == 2
                ? (String(parts[0]), String(parts[1]))
                : (nil, refStr)
            p.references.append(.init(paramName: "item-subject", refType: refType, refId: refId))
        }
    }
}

// part-of [reference] — QuestionnaireResponse.partOf
private func extract_QuestionnaireResponse_part_of(_ p: inout SearchParams, _ q: QuestionnaireResponse) {
    for ref in q.partOf ?? [] {
        guard let refStr = ref.reference?.value?.string else { continue }
        let parts = refStr.split(separator: "/")
        let (refType, refId): (String?, String) = parts.count == 2
            ? (String(parts[0]), String(parts[1]))
            : (nil, refStr)
        p.references.append(.init(paramName: "part-of", refType: refType, refId: refId))
    }
}

// patient [reference] — QuestionnaireResponse.subject
private func extract_QuestionnaireResponse_patient(_ p: inout SearchParams, _ q: QuestionnaireResponse) {
    guard let refStr = q.subject?.reference?.value?.string else { return }
    let parts = refStr.split(separator: "/")
    guard parts.count == 2, parts[0] == "Patient" else { return }
    p.references.append(.init(paramName: "patient", refType: "Patient", refId: String(parts[1])))
}

// questionnaire [reference] — QuestionnaireResponse.questionnaire
private func extract_QuestionnaireResponse_questionnaire(_ p: inout SearchParams, _ q: QuestionnaireResponse) {
    guard let canonical = q.questionnaire?.value else { return }
    let url = canonical.url.absoluteString
    p.strings.append(.init(paramName: "questionnaire", value: url))
    if let version = canonical.version {
        p.strings.append(.init(paramName: "questionnaire", value: "\(url)|\(version)"))
    }
}

// source [reference] — QuestionnaireResponse.source
private func extract_QuestionnaireResponse_source(_ p: inout SearchParams, _ q: QuestionnaireResponse) {
    guard let refStr = q.source?.reference?.value?.string else { return }
    let parts = refStr.split(separator: "/")
    let (refType, refId): (String?, String) = parts.count == 2
        ? (String(parts[0]), String(parts[1]))
        : (nil, refStr)
    p.references.append(.init(paramName: "source", refType: refType, refId: refId))
}

// status [token] — QuestionnaireResponse.status
private func extract_QuestionnaireResponse_status(_ p: inout SearchParams, _ q: QuestionnaireResponse) {
    if let v = q.status.value?.rawValue {
        p.tokens.append(.init(paramName: "status",
                              system: "http://hl7.org/fhir/questionnaire-answers-status", code: v))
    }
}

// subject [reference] — QuestionnaireResponse.subject
private func extract_QuestionnaireResponse_subject(_ p: inout SearchParams, _ q: QuestionnaireResponse) {
    guard let refStr = q.subject?.reference?.value?.string else { return }
    let parts = refStr.split(separator: "/")
    let (refType, refId): (String?, String) = parts.count == 2
        ? (String(parts[0]), String(parts[1]))
        : (nil, refStr)
    p.references.append(.init(paramName: "subject", refType: refType, refId: refId))
}