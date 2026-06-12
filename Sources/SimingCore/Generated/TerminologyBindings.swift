// GENERATED — do not edit directly.
// Source: packages/*.tgz (hl7.fhir.r4.core + tw.gov.mohw.twcore)
// Regenerate: swift run SimingGenerator

public let fhirRequiredBindings: [String: [BindingRule]] = [
    "AllergyIntolerance": [
        BindingRule(path: "AllergyIntolerance.clinicalStatus", valueSet: "http://hl7.org/fhir/ValueSet/allergyintolerance-clinical", kind: .codeableConcept, isArray: false),
        BindingRule(path: "AllergyIntolerance.verificationStatus", valueSet: "http://hl7.org/fhir/ValueSet/allergyintolerance-verification", kind: .codeableConcept, isArray: false),
        BindingRule(path: "AllergyIntolerance.type", valueSet: "http://hl7.org/fhir/ValueSet/allergy-intolerance-type", kind: .code, isArray: false),
        BindingRule(path: "AllergyIntolerance.category", valueSet: "http://hl7.org/fhir/ValueSet/allergy-intolerance-category", kind: .code, isArray: true),
        BindingRule(path: "AllergyIntolerance.criticality", valueSet: "http://hl7.org/fhir/ValueSet/allergy-intolerance-criticality", kind: .code, isArray: false),
        BindingRule(path: "AllergyIntolerance.reaction.severity", valueSet: "http://hl7.org/fhir/ValueSet/reaction-event-severity", kind: .code, isArray: false)
    ],
    "Appointment": [
        BindingRule(path: "Appointment.status", valueSet: "http://hl7.org/fhir/ValueSet/appointmentstatus", kind: .code, isArray: false),
        BindingRule(path: "Appointment.participant.required", valueSet: "http://hl7.org/fhir/ValueSet/participantrequired", kind: .code, isArray: false),
        BindingRule(path: "Appointment.participant.status", valueSet: "http://hl7.org/fhir/ValueSet/participationstatus", kind: .code, isArray: false)
    ],
    "CarePlan": [
        BindingRule(path: "CarePlan.text.status", valueSet: "https://twcore.mohw.gov.tw/ig/twcore/ValueSet/narrative-status", kind: .code, isArray: false),
        BindingRule(path: "CarePlan.status", valueSet: "http://hl7.org/fhir/ValueSet/request-status", kind: .code, isArray: false),
        BindingRule(path: "CarePlan.intent", valueSet: "http://hl7.org/fhir/ValueSet/care-plan-intent", kind: .code, isArray: false),
        BindingRule(path: "CarePlan.activity.detail.kind", valueSet: "http://hl7.org/fhir/ValueSet/care-plan-activity-kind", kind: .code, isArray: false),
        BindingRule(path: "CarePlan.activity.detail.status", valueSet: "http://hl7.org/fhir/ValueSet/care-plan-activity-status", kind: .code, isArray: false)
    ],
    "Condition": [
        BindingRule(path: "Condition.clinicalStatus", valueSet: "http://hl7.org/fhir/ValueSet/condition-clinical", kind: .codeableConcept, isArray: false),
        BindingRule(path: "Condition.verificationStatus", valueSet: "http://hl7.org/fhir/ValueSet/condition-ver-status", kind: .codeableConcept, isArray: false),
        BindingRule(path: "Condition.code.coding", valueSet: "https://twcore.mohw.gov.tw/ig/twcore/ValueSet/icd-10-cm-2023-tw", kind: .code, isArray: false),
        BindingRule(path: "Condition.code.coding", valueSet: "https://twcore.mohw.gov.tw/ig/twcore/ValueSet/icd-10-cm-2021-tw", kind: .code, isArray: false),
        BindingRule(path: "Condition.code.coding", valueSet: "https://twcore.mohw.gov.tw/ig/twcore/ValueSet/icd-10-cm-2014-tw", kind: .code, isArray: false),
        BindingRule(path: "Condition.code.coding", valueSet: "https://twcore.mohw.gov.tw/ig/twcore/ValueSet/icd-9-cm-2001-tw", kind: .code, isArray: false),
        BindingRule(path: "Condition.code.coding", valueSet: "http://hl7.org/fhir/uv/ips/ValueSet/absent-or-unknown-problems-uv-ips", kind: .code, isArray: false),
        BindingRule(path: "Condition.code.coding", valueSet: "https://twcore.mohw.gov.tw/ig/twcore/ValueSet/condition-code-sct-tw", kind: .code, isArray: false)
    ],
    "DiagnosticReport": [
        BindingRule(path: "DiagnosticReport.status", valueSet: "http://hl7.org/fhir/ValueSet/diagnostic-report-status", kind: .code, isArray: false),
        BindingRule(path: "DiagnosticReport.code.coding", valueSet: "https://twcore.mohw.gov.tw/ig/twcore/ValueSet/loinc-observation-code", kind: .code, isArray: false),
        BindingRule(path: "DiagnosticReport.code.coding", valueSet: "https://twcore.mohw.gov.tw/ig/twcore/ValueSet/laboratory-category-tw", kind: .code, isArray: false),
        BindingRule(path: "DiagnosticReport.code.coding", valueSet: "https://twcore.mohw.gov.tw/ig/twcore/ValueSet/icd-10-pcs-2021-tw", kind: .code, isArray: false),
        BindingRule(path: "DiagnosticReport.code.coding", valueSet: "https://twcore.mohw.gov.tw/ig/twcore/ValueSet/icd-10-pcs-2023-tw", kind: .code, isArray: false)
    ],
    "DocumentReference": [
        BindingRule(path: "DocumentReference.status", valueSet: "http://hl7.org/fhir/ValueSet/document-reference-status", kind: .code, isArray: false),
        BindingRule(path: "DocumentReference.docStatus", valueSet: "http://hl7.org/fhir/ValueSet/composition-status", kind: .code, isArray: false),
        BindingRule(path: "DocumentReference.relatesTo.code", valueSet: "http://hl7.org/fhir/ValueSet/document-relationship-type", kind: .code, isArray: false)
    ],
    "Encounter": [
        BindingRule(path: "Encounter.identifier.use", valueSet: "http://hl7.org/fhir/ValueSet/identifier-use", kind: .code, isArray: false),
        BindingRule(path: "Encounter.status", valueSet: "http://hl7.org/fhir/ValueSet/encounter-status", kind: .code, isArray: false),
        BindingRule(path: "Encounter.statusHistory.status", valueSet: "http://hl7.org/fhir/ValueSet/encounter-status", kind: .code, isArray: false),
        BindingRule(path: "Encounter.serviceType.coding", valueSet: "https://twcore.mohw.gov.tw/ig/twcore/ValueSet/medical-department-sct-tw", kind: .code, isArray: false),
        BindingRule(path: "Encounter.serviceType.coding", valueSet: "https://twcore.mohw.gov.tw/ig/twcore/ValueSet/medical-consultation-department-tw", kind: .code, isArray: false),
        BindingRule(path: "Encounter.serviceType.coding", valueSet: "https://twcore.mohw.gov.tw/ig/twcore/ValueSet/medical-treatment-department-tw", kind: .code, isArray: false),
        BindingRule(path: "Encounter.location.status", valueSet: "http://hl7.org/fhir/ValueSet/encounter-location-status", kind: .code, isArray: false)
    ],
    "FamilyMemberHistory": [
        BindingRule(path: "FamilyMemberHistory.status", valueSet: "http://hl7.org/fhir/ValueSet/history-status", kind: .code, isArray: false)
    ],
    "Goal": [
        BindingRule(path: "Goal.lifecycleStatus", valueSet: "http://hl7.org/fhir/ValueSet/goal-status", kind: .code, isArray: false)
    ],
    "Immunization": [
        BindingRule(path: "Immunization.status", valueSet: "http://hl7.org/fhir/ValueSet/immunization-status", kind: .code, isArray: false)
    ],
    "Location": [
        BindingRule(path: "Location.status", valueSet: "http://hl7.org/fhir/ValueSet/location-status", kind: .code, isArray: false),
        BindingRule(path: "Location.mode", valueSet: "http://hl7.org/fhir/ValueSet/location-mode", kind: .code, isArray: false),
        BindingRule(path: "Location.telecom.system", valueSet: "http://hl7.org/fhir/ValueSet/contact-point-system", kind: .code, isArray: false),
        BindingRule(path: "Location.telecom.use", valueSet: "http://hl7.org/fhir/ValueSet/contact-point-use", kind: .code, isArray: false),
        BindingRule(path: "Location.hoursOfOperation.daysOfWeek", valueSet: "http://hl7.org/fhir/ValueSet/days-of-week", kind: .code, isArray: true)
    ],
    "Medication": [
        BindingRule(path: "Medication.code.coding", valueSet: "https://twcore.mohw.gov.tw/ig/twcore/ValueSet/medication-fda-tw", kind: .code, isArray: false),
        BindingRule(path: "Medication.code.coding", valueSet: "https://twcore.mohw.gov.tw/ig/twcore/ValueSet/medication-nhi-tw", kind: .code, isArray: false),
        BindingRule(path: "Medication.code.coding", valueSet: "https://twcore.mohw.gov.tw/ig/twcore/ValueSet/nhi-medication-ch-herb-tw", kind: .code, isArray: false),
        BindingRule(path: "Medication.code.coding", valueSet: "https://twcore.mohw.gov.tw/ig/twcore/ValueSet/medication-rxnorm-tw", kind: .code, isArray: false),
        BindingRule(path: "Medication.code.coding", valueSet: "https://twcore.mohw.gov.tw/ig/twcore/ValueSet/medcation-atc-tw", kind: .code, isArray: false),
        BindingRule(path: "Medication.code.coding", valueSet: "http://hl7.org/fhir/ValueSet/medication-codes", kind: .code, isArray: false),
        BindingRule(path: "Medication.status", valueSet: "http://hl7.org/fhir/ValueSet/medication-status", kind: .code, isArray: false),
        BindingRule(path: "Medication.form.coding", valueSet: "https://twcore.mohw.gov.tw/ig/twcore/ValueSet/v3-orderableDrugForm", kind: .code, isArray: false),
        BindingRule(path: "Medication.form.coding", valueSet: "http://hl7.org/fhir/ValueSet/medication-form-codes", kind: .code, isArray: false)
    ],
    "MedicationAdministration": [
        BindingRule(path: "MedicationAdministration.status", valueSet: "http://hl7.org/fhir/ValueSet/medication-admin-status", kind: .code, isArray: false)
    ],
    "MedicationRequest": [
        BindingRule(path: "MedicationRequest.status", valueSet: "http://hl7.org/fhir/ValueSet/medicationrequest-status", kind: .code, isArray: false),
        BindingRule(path: "MedicationRequest.intent", valueSet: "http://hl7.org/fhir/ValueSet/medicationrequest-intent", kind: .code, isArray: false),
        BindingRule(path: "MedicationRequest.priority", valueSet: "http://hl7.org/fhir/ValueSet/request-priority", kind: .code, isArray: false),
        BindingRule(path: "MedicationRequest.dosageInstruction.timing.repeat.durationUnit", valueSet: "http://hl7.org/fhir/ValueSet/units-of-time", kind: .code, isArray: false),
        BindingRule(path: "MedicationRequest.dosageInstruction.timing.repeat.periodUnit", valueSet: "http://hl7.org/fhir/ValueSet/units-of-time", kind: .code, isArray: false),
        BindingRule(path: "MedicationRequest.dosageInstruction.timing.repeat.dayOfWeek", valueSet: "http://hl7.org/fhir/ValueSet/days-of-week", kind: .code, isArray: true),
        BindingRule(path: "MedicationRequest.dosageInstruction.timing.repeat.when", valueSet: "http://hl7.org/fhir/ValueSet/event-timing", kind: .code, isArray: true)
    ],
    "MedicationStatement": [
        BindingRule(path: "MedicationStatement.status", valueSet: "http://hl7.org/fhir/ValueSet/medication-statement-status", kind: .code, isArray: false),
        BindingRule(path: "MedicationStatement.dosage.timing.repeat.durationUnit", valueSet: "http://hl7.org/fhir/ValueSet/units-of-time", kind: .code, isArray: false),
        BindingRule(path: "MedicationStatement.dosage.timing.repeat.periodUnit", valueSet: "http://hl7.org/fhir/ValueSet/units-of-time", kind: .code, isArray: false),
        BindingRule(path: "MedicationStatement.dosage.timing.repeat.dayOfWeek", valueSet: "http://hl7.org/fhir/ValueSet/days-of-week", kind: .code, isArray: true),
        BindingRule(path: "MedicationStatement.dosage.timing.repeat.when", valueSet: "http://hl7.org/fhir/ValueSet/event-timing", kind: .code, isArray: true)
    ],
    "Observation": [
        BindingRule(path: "Observation.status", valueSet: "http://hl7.org/fhir/ValueSet/observation-status", kind: .code, isArray: false)
    ],
    "Organization": [
        BindingRule(path: "Organization.identifier.use", valueSet: "http://hl7.org/fhir/ValueSet/identifier-use", kind: .code, isArray: false),
        BindingRule(path: "Organization.telecom.system", valueSet: "http://hl7.org/fhir/ValueSet/contact-point-system", kind: .code, isArray: false),
        BindingRule(path: "Organization.telecom.use", valueSet: "http://hl7.org/fhir/ValueSet/contact-point-use", kind: .code, isArray: false)
    ],
    "Patient": [
        BindingRule(path: "Patient.identifier.use", valueSet: "http://hl7.org/fhir/ValueSet/identifier-use", kind: .code, isArray: false),
        BindingRule(path: "Patient.name.use", valueSet: "http://hl7.org/fhir/ValueSet/name-use", kind: .code, isArray: false),
        BindingRule(path: "Patient.telecom.system", valueSet: "http://hl7.org/fhir/ValueSet/contact-point-system", kind: .code, isArray: false),
        BindingRule(path: "Patient.telecom.use", valueSet: "http://hl7.org/fhir/ValueSet/contact-point-use", kind: .code, isArray: false),
        BindingRule(path: "Patient.gender", valueSet: "http://hl7.org/fhir/ValueSet/administrative-gender", kind: .code, isArray: false),
        BindingRule(path: "Patient.contact.relationship", valueSet: "http://hl7.org/fhir/ValueSet/relatedperson-relationshiptype", kind: .codeableConcept, isArray: true),
        BindingRule(path: "Patient.contact.name.use", valueSet: "http://hl7.org/fhir/ValueSet/name-use", kind: .code, isArray: false),
        BindingRule(path: "Patient.contact.telecom.system", valueSet: "http://hl7.org/fhir/ValueSet/contact-point-system", kind: .code, isArray: false),
        BindingRule(path: "Patient.contact.telecom.use", valueSet: "http://hl7.org/fhir/ValueSet/contact-point-use", kind: .code, isArray: false),
        BindingRule(path: "Patient.contact.gender", valueSet: "http://hl7.org/fhir/ValueSet/administrative-gender", kind: .code, isArray: false),
        BindingRule(path: "Patient.link.type", valueSet: "http://hl7.org/fhir/ValueSet/link-type", kind: .code, isArray: false)
    ],
    "Practitioner": [
        BindingRule(path: "Practitioner.identifier.use", valueSet: "http://hl7.org/fhir/ValueSet/identifier-use", kind: .code, isArray: false),
        BindingRule(path: "Practitioner.name.use", valueSet: "http://hl7.org/fhir/ValueSet/name-use", kind: .code, isArray: false),
        BindingRule(path: "Practitioner.telecom.system", valueSet: "http://hl7.org/fhir/ValueSet/contact-point-system", kind: .code, isArray: false),
        BindingRule(path: "Practitioner.telecom.use", valueSet: "http://hl7.org/fhir/ValueSet/contact-point-use", kind: .code, isArray: false),
        BindingRule(path: "Practitioner.gender", valueSet: "http://hl7.org/fhir/ValueSet/administrative-gender", kind: .code, isArray: false)
    ],
    "Procedure": [
        BindingRule(path: "Procedure.status", valueSet: "http://hl7.org/fhir/ValueSet/event-status", kind: .code, isArray: false),
        BindingRule(path: "Procedure.code.coding", valueSet: "https://twcore.mohw.gov.tw/ig/twcore/ValueSet/icd-10-pcs-2023-tw", kind: .code, isArray: false),
        BindingRule(path: "Procedure.code.coding", valueSet: "https://twcore.mohw.gov.tw/ig/twcore/ValueSet/icd-10-pcs-2021-tw", kind: .code, isArray: false),
        BindingRule(path: "Procedure.code.coding", valueSet: "https://twcore.mohw.gov.tw/ig/twcore/ValueSet/icd-10-pcs-2014-tw", kind: .code, isArray: false),
        BindingRule(path: "Procedure.code.coding", valueSet: "https://twcore.mohw.gov.tw/ig/twcore/ValueSet/procedure-tw", kind: .code, isArray: false),
        BindingRule(path: "Procedure.code.coding", valueSet: "http://hl7.org/fhir/ValueSet/procedure-code", kind: .code, isArray: false),
        BindingRule(path: "Procedure.code.coding", valueSet: "http://hl7.org/fhir/ValueSet/observation-codes", kind: .code, isArray: false)
    ],
    "RelatedPerson": [
        BindingRule(path: "RelatedPerson.gender", valueSet: "http://hl7.org/fhir/ValueSet/administrative-gender", kind: .code, isArray: false)
    ],
    "ServiceRequest": [
        BindingRule(path: "ServiceRequest.status", valueSet: "http://hl7.org/fhir/ValueSet/request-status", kind: .code, isArray: false),
        BindingRule(path: "ServiceRequest.intent", valueSet: "http://hl7.org/fhir/ValueSet/request-intent", kind: .code, isArray: false),
        BindingRule(path: "ServiceRequest.category", valueSet: "https://twcore.mohw.gov.tw/ig/twcore/ValueSet/serviceRequest-category", kind: .codeableConcept, isArray: true),
        BindingRule(path: "ServiceRequest.priority", valueSet: "http://hl7.org/fhir/ValueSet/request-priority", kind: .code, isArray: false),
        BindingRule(path: "ServiceRequest.code.coding", valueSet: "https://twcore.mohw.gov.tw/ig/twcore/ValueSet/icd-10-pcs-2023-tw", kind: .code, isArray: false),
        BindingRule(path: "ServiceRequest.code.coding", valueSet: "https://twcore.mohw.gov.tw/ig/twcore/ValueSet/icd-10-pcs-2021-tw", kind: .code, isArray: false),
        BindingRule(path: "ServiceRequest.code.coding", valueSet: "https://twcore.mohw.gov.tw/ig/twcore/ValueSet/icd-10-pcs-2014-tw", kind: .code, isArray: false),
        BindingRule(path: "ServiceRequest.code.coding", valueSet: "https://twcore.mohw.gov.tw/ig/twcore/ValueSet/procedure-tw", kind: .code, isArray: false),
        BindingRule(path: "ServiceRequest.code.coding", valueSet: "http://hl7.org/fhir/ValueSet/procedure-code", kind: .code, isArray: false),
        BindingRule(path: "ServiceRequest.code.coding", valueSet: "http://hl7.org/fhir/ValueSet/observation-codes", kind: .code, isArray: false)
    ],
    "Specimen": [
        BindingRule(path: "Specimen.status", valueSet: "http://hl7.org/fhir/ValueSet/specimen-status", kind: .code, isArray: false)
    ]
]