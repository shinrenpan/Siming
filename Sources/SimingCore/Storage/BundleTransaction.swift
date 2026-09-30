import Foundation
import ModelsR4

// ── Bundle entry prepare dispatch ─────────────────────────────────────────────
//
// Decodes the resource JSON into the concrete FHIR type, sets the
// server-assigned id, strips meta (reconstructed on every read via injectMeta),
// re-encodes for storage, and extracts search index params.
//
// Called by the transaction bundle handler for each POST/PUT entry. Transaction
// writes bypass the stores, so every check a store's write() runs before storing
// must run here too — otherwise a Bundle is a way around it. Terminology binding
// validation runs in prepareResource. The per-store validate() hook is a no-op;
// when profile validation is implemented, add it to prepareResource as well.
//
// Parameters:
//   resourceType — "Patient", "Observation", etc. Must be one of the 24 supported types.
//   id           — server-assigned (POST) or client-provided (PUT) resource id.
//   data         — raw JSON of the resource (post urn:uuid replacement).

public func prepareEntryForWrite(
    resourceType: String,
    id: String,
    data: Data,
    terminology: TerminologyIndex
) throws -> (json: String, params: SearchParams) {
    switch resourceType {
    case "Patient":
        return try prepareResource(Patient.self, data: data, id: id, terminology: terminology, extractor: extractPatientSearchParams)
    case "Observation":
        return try prepareResource(Observation.self, data: data, id: id, terminology: terminology, extractor: extractObservationSearchParams)
    case "Encounter":
        return try prepareResource(Encounter.self, data: data, id: id, terminology: terminology, extractor: extractEncounterSearchParams)
    case "Condition":
        return try prepareResource(Condition.self, data: data, id: id, terminology: terminology, extractor: extractConditionSearchParams)
    case "Medication":
        return try prepareResource(Medication.self, data: data, id: id, terminology: terminology, extractor: extractMedicationSearchParams)
    case "MedicationRequest":
        return try prepareResource(MedicationRequest.self, data: data, id: id, terminology: terminology, extractor: extractMedicationRequestSearchParams)
    case "AllergyIntolerance":
        return try prepareResource(AllergyIntolerance.self, data: data, id: id, terminology: terminology, extractor: extractAllergyIntoleranceSearchParams)
    case "Procedure":
        return try prepareResource(Procedure.self, data: data, id: id, terminology: terminology, extractor: extractProcedureSearchParams)
    case "DiagnosticReport":
        return try prepareResource(DiagnosticReport.self, data: data, id: id, terminology: terminology, extractor: extractDiagnosticReportSearchParams)
    case "Immunization":
        return try prepareResource(Immunization.self, data: data, id: id, terminology: terminology, extractor: extractImmunizationSearchParams)
    case "Practitioner":
        return try prepareResource(Practitioner.self, data: data, id: id, terminology: terminology, extractor: extractPractitionerSearchParams)
    case "PractitionerRole":
        return try prepareResource(PractitionerRole.self, data: data, id: id, terminology: terminology, extractor: extractPractitionerRoleSearchParams)
    case "Organization":
        return try prepareResource(Organization.self, data: data, id: id, terminology: terminology, extractor: extractOrganizationSearchParams)
    case "Location":
        return try prepareResource(Location.self, data: data, id: id, terminology: terminology, extractor: extractLocationSearchParams)
    case "RelatedPerson":
        return try prepareResource(RelatedPerson.self, data: data, id: id, terminology: terminology, extractor: extractRelatedPersonSearchParams)
    case "ServiceRequest":
        return try prepareResource(ServiceRequest.self, data: data, id: id, terminology: terminology, extractor: extractServiceRequestSearchParams)
    case "Specimen":
        return try prepareResource(Specimen.self, data: data, id: id, terminology: terminology, extractor: extractSpecimenSearchParams)
    case "DocumentReference":
        return try prepareResource(DocumentReference.self, data: data, id: id, terminology: terminology, extractor: extractDocumentReferenceSearchParams)
    case "CarePlan":
        return try prepareResource(CarePlan.self, data: data, id: id, terminology: terminology, extractor: extractCarePlanSearchParams)
    case "Goal":
        return try prepareResource(Goal.self, data: data, id: id, terminology: terminology, extractor: extractGoalSearchParams)
    case "MedicationStatement":
        return try prepareResource(MedicationStatement.self, data: data, id: id, terminology: terminology, extractor: extractMedicationStatementSearchParams)
    case "FamilyMemberHistory":
        return try prepareResource(FamilyMemberHistory.self, data: data, id: id, terminology: terminology, extractor: extractFamilyMemberHistorySearchParams)
    case "Appointment":
        return try prepareResource(Appointment.self, data: data, id: id, terminology: terminology, extractor: extractAppointmentSearchParams)
    case "MedicationAdministration":
        return try prepareResource(MedicationAdministration.self, data: data, id: id, terminology: terminology, extractor: extractMedicationAdministrationSearchParams)
    default:
        throw BundleTransactionError.unsupportedResourceType(resourceType)
    }
}

private func prepareResource<R: Resource>(
    _ type: R.Type,
    data: Data,
    id: String,
    terminology: TerminologyIndex,
    extractor: (R) -> SearchParams
) throws -> (String, SearchParams) {
    var r = try JSONDecoder().decode(type, from: data)
    let originalMeta = r.meta
    r.id = FHIRPrimitive(FHIRString(id))
    r.meta = nil
    let encoded = try JSONEncoder().encode(r)
    try validate(r)
    // Same check, on the same encoded form, as every store's write().
    if let obj = try? JSONSerialization.jsonObject(with: encoded) as? [String: Any] {
        try validateCodes(resourceType: R.resourceType.rawValue, json: obj, terminology: terminology)
    }
    let json = String(data: encoded, encoding: .utf8)!
    var p = extractor(r)
    appendMetaParams(&p, meta: originalMeta)
    return (json, p)
}

/// Transaction-path counterpart of each store's private `validate(_:)` hook — no-op until
/// profile validation lands, and then it must be implemented here as well as in the stores.
/// Never remove the call in `prepareResource`.
private func validate<R: Resource>(_ resource: R) throws {}

public enum BundleTransactionError: Error {
    case unsupportedResourceType(String)
    case invalidEntry(String)
    case notTransaction
}
