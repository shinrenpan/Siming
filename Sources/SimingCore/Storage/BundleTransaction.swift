import Foundation
import ModelsR4

// ── Bundle entry prepare dispatch ─────────────────────────────────────────────
//
// Decodes the resource JSON into the concrete FHIR type, sets the
// server-assigned id, strips meta (reconstructed on every read via injectMeta),
// re-encodes for storage, and extracts search index params.
//
// Called by the transaction bundle handler for each POST/PUT entry.
// Note: the validate() hook (no-op until profile validation is added) is NOT
// called here — it lives in each store's write() path. When profile validation
// is implemented, add it to this function as well.
//
// Parameters:
//   resourceType — "Patient", "Observation", etc. Must be one of the 23 supported types.
//   id           — server-assigned (POST) or client-provided (PUT) resource id.
//   data         — raw JSON of the resource (post urn:uuid replacement).

public func prepareEntryForWrite(
    resourceType: String,
    id: String,
    data: Data
) throws -> (json: String, params: SearchParams) {
    switch resourceType {
    case "Patient":
        return try prepareResource(Patient.self, data: data, id: id, extractor: extractPatientSearchParams)
    case "Observation":
        return try prepareResource(Observation.self, data: data, id: id, extractor: extractObservationSearchParams)
    case "Encounter":
        return try prepareResource(Encounter.self, data: data, id: id, extractor: extractEncounterSearchParams)
    case "Condition":
        return try prepareResource(Condition.self, data: data, id: id, extractor: extractConditionSearchParams)
    case "Medication":
        return try prepareResource(Medication.self, data: data, id: id, extractor: extractMedicationSearchParams)
    case "MedicationRequest":
        return try prepareResource(MedicationRequest.self, data: data, id: id, extractor: extractMedicationRequestSearchParams)
    case "AllergyIntolerance":
        return try prepareResource(AllergyIntolerance.self, data: data, id: id, extractor: extractAllergyIntoleranceSearchParams)
    case "Procedure":
        return try prepareResource(Procedure.self, data: data, id: id, extractor: extractProcedureSearchParams)
    case "DiagnosticReport":
        return try prepareResource(DiagnosticReport.self, data: data, id: id, extractor: extractDiagnosticReportSearchParams)
    case "Immunization":
        return try prepareResource(Immunization.self, data: data, id: id, extractor: extractImmunizationSearchParams)
    case "Practitioner":
        return try prepareResource(Practitioner.self, data: data, id: id, extractor: extractPractitionerSearchParams)
    case "Organization":
        return try prepareResource(Organization.self, data: data, id: id, extractor: extractOrganizationSearchParams)
    case "Location":
        return try prepareResource(Location.self, data: data, id: id, extractor: extractLocationSearchParams)
    case "RelatedPerson":
        return try prepareResource(RelatedPerson.self, data: data, id: id, extractor: extractRelatedPersonSearchParams)
    case "ServiceRequest":
        return try prepareResource(ServiceRequest.self, data: data, id: id, extractor: extractServiceRequestSearchParams)
    case "Specimen":
        return try prepareResource(Specimen.self, data: data, id: id, extractor: extractSpecimenSearchParams)
    case "DocumentReference":
        return try prepareResource(DocumentReference.self, data: data, id: id, extractor: extractDocumentReferenceSearchParams)
    case "CarePlan":
        return try prepareResource(CarePlan.self, data: data, id: id, extractor: extractCarePlanSearchParams)
    case "Goal":
        return try prepareResource(Goal.self, data: data, id: id, extractor: extractGoalSearchParams)
    case "MedicationStatement":
        return try prepareResource(MedicationStatement.self, data: data, id: id, extractor: extractMedicationStatementSearchParams)
    case "FamilyMemberHistory":
        return try prepareResource(FamilyMemberHistory.self, data: data, id: id, extractor: extractFamilyMemberHistorySearchParams)
    case "Appointment":
        return try prepareResource(Appointment.self, data: data, id: id, extractor: extractAppointmentSearchParams)
    case "MedicationAdministration":
        return try prepareResource(MedicationAdministration.self, data: data, id: id, extractor: extractMedicationAdministrationSearchParams)
    default:
        throw BundleTransactionError.unsupportedResourceType(resourceType)
    }
}

private func prepareResource<R: Resource>(
    _ type: R.Type,
    data: Data,
    id: String,
    extractor: (R) -> SearchParams
) throws -> (String, SearchParams) {
    var r = try JSONDecoder().decode(type, from: data)
    let originalMeta = r.meta
    r.id = FHIRPrimitive(FHIRString(id))
    r.meta = nil
    let encoded = try JSONEncoder().encode(r)
    let json = String(data: encoded, encoding: .utf8)!
    var p = extractor(r)
    appendMetaParams(&p, meta: originalMeta)
    return (json, p)
}

public enum BundleTransactionError: Error {
    case unsupportedResourceType(String)
    case invalidEntry(String)
    case notTransaction
}
