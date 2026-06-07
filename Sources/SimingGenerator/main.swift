import Foundation

let bundlePath = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "Resources/fhir/search-parameters-r4.json"

let outputDir = CommandLine.arguments.count > 2
    ? CommandLine.arguments[2]
    : "Sources/SimingCore/Generated"

try FileManager.default.createDirectory(
    atPath: outputDir,
    withIntermediateDirectories: true
)

let medicationAdministrationParams = try loadParams(resourceType: "MedicationAdministration", bundlePath: bundlePath)
    .sorted { $0.code < $1.code }

let medicationAdministrationCode = generateMedicationAdministrationExtractor(params: medicationAdministrationParams)
let medicationAdministrationOut  = "\(outputDir)/MedicationAdministration+SearchExtractor.swift"
try medicationAdministrationCode.write(toFile: medicationAdministrationOut, atomically: true, encoding: .utf8)
print("Generated \(medicationAdministrationOut) — \(medicationAdministrationParams.count) MedicationAdministration params")

let appointmentParams = try loadParams(resourceType: "Appointment", bundlePath: bundlePath)
    .sorted { $0.code < $1.code }

let appointmentCode = generateAppointmentExtractor(params: appointmentParams)
let appointmentOut  = "\(outputDir)/Appointment+SearchExtractor.swift"
try appointmentCode.write(toFile: appointmentOut, atomically: true, encoding: .utf8)
print("Generated \(appointmentOut) — \(appointmentParams.count) Appointment params")

let familyMemberHistoryParams = try loadParams(resourceType: "FamilyMemberHistory", bundlePath: bundlePath)
    .sorted { $0.code < $1.code }

let familyMemberHistoryCode = generateFamilyMemberHistoryExtractor(params: familyMemberHistoryParams)
let familyMemberHistoryOut  = "\(outputDir)/FamilyMemberHistory+SearchExtractor.swift"
try familyMemberHistoryCode.write(toFile: familyMemberHistoryOut, atomically: true, encoding: .utf8)
print("Generated \(familyMemberHistoryOut) — \(familyMemberHistoryParams.count) FamilyMemberHistory params")

let medicationStatementParams = try loadParams(resourceType: "MedicationStatement", bundlePath: bundlePath)
    .sorted { $0.code < $1.code }

let medicationStatementCode = generateMedicationStatementExtractor(params: medicationStatementParams)
let medicationStatementOut  = "\(outputDir)/MedicationStatement+SearchExtractor.swift"
try medicationStatementCode.write(toFile: medicationStatementOut, atomically: true, encoding: .utf8)
print("Generated \(medicationStatementOut) — \(medicationStatementParams.count) MedicationStatement params")

let goalParams = try loadParams(resourceType: "Goal", bundlePath: bundlePath)
    .sorted { $0.code < $1.code }

let goalCode = generateGoalExtractor(params: goalParams)
let goalOut  = "\(outputDir)/Goal+SearchExtractor.swift"
try goalCode.write(toFile: goalOut, atomically: true, encoding: .utf8)
print("Generated \(goalOut) — \(goalParams.count) Goal params")

let carePlanParams = try loadParams(resourceType: "CarePlan", bundlePath: bundlePath)
    .sorted { $0.code < $1.code }

let carePlanCode = generateCarePlanExtractor(params: carePlanParams)
let carePlanOut  = "\(outputDir)/CarePlan+SearchExtractor.swift"
try carePlanCode.write(toFile: carePlanOut, atomically: true, encoding: .utf8)
print("Generated \(carePlanOut) — \(carePlanParams.count) CarePlan params")

let documentReferenceParams = try loadParams(resourceType: "DocumentReference", bundlePath: bundlePath)
    .sorted { $0.code < $1.code }

let documentReferenceCode = generateDocumentReferenceExtractor(params: documentReferenceParams)
let documentReferenceOut  = "\(outputDir)/DocumentReference+SearchExtractor.swift"
try documentReferenceCode.write(toFile: documentReferenceOut, atomically: true, encoding: .utf8)
print("Generated \(documentReferenceOut) — \(documentReferenceParams.count) DocumentReference params")

let specimenParams = try loadParams(resourceType: "Specimen", bundlePath: bundlePath)
    .sorted { $0.code < $1.code }

let specimenCode = generateSpecimenExtractor(params: specimenParams)
let specimenOut  = "\(outputDir)/Specimen+SearchExtractor.swift"
try specimenCode.write(toFile: specimenOut, atomically: true, encoding: .utf8)
print("Generated \(specimenOut) — \(specimenParams.count) Specimen params")

let serviceRequestParams = try loadParams(resourceType: "ServiceRequest", bundlePath: bundlePath)
    .sorted { $0.code < $1.code }

let serviceRequestCode = generateServiceRequestExtractor(params: serviceRequestParams)
let serviceRequestOut  = "\(outputDir)/ServiceRequest+SearchExtractor.swift"
try serviceRequestCode.write(toFile: serviceRequestOut, atomically: true, encoding: .utf8)
print("Generated \(serviceRequestOut) — \(serviceRequestParams.count) ServiceRequest params")

let relatedPersonParams = try loadParams(resourceType: "RelatedPerson", bundlePath: bundlePath)
    .sorted { $0.code < $1.code }

let relatedPersonCode = generateRelatedPersonExtractor(params: relatedPersonParams)
let relatedPersonOut  = "\(outputDir)/RelatedPerson+SearchExtractor.swift"
try relatedPersonCode.write(toFile: relatedPersonOut, atomically: true, encoding: .utf8)
print("Generated \(relatedPersonOut) — \(relatedPersonParams.count) RelatedPerson params")

let medicationParams = try loadParams(resourceType: "Medication", bundlePath: bundlePath)
    .sorted { $0.code < $1.code }

let medicationCode = generateMedicationExtractor(params: medicationParams)
let medicationOut  = "\(outputDir)/Medication+SearchExtractor.swift"
try medicationCode.write(toFile: medicationOut, atomically: true, encoding: .utf8)
print("Generated \(medicationOut) — \(medicationParams.count) Medication params")

let locationParams = try loadParams(resourceType: "Location", bundlePath: bundlePath)
    .sorted { $0.code < $1.code }

let locationCode = generateLocationExtractor(params: locationParams)
let locationOut  = "\(outputDir)/Location+SearchExtractor.swift"
try locationCode.write(toFile: locationOut, atomically: true, encoding: .utf8)
print("Generated \(locationOut) — \(locationParams.count) Location params")

let practitionerParams = try loadParams(resourceType: "Practitioner", bundlePath: bundlePath)
    .sorted { $0.code < $1.code }

let practitionerCode = generatePractitionerExtractor(params: practitionerParams)
let practitionerOut  = "\(outputDir)/Practitioner+SearchExtractor.swift"
try practitionerCode.write(toFile: practitionerOut, atomically: true, encoding: .utf8)
print("Generated \(practitionerOut) — \(practitionerParams.count) Practitioner params")

let organizationParams = try loadParams(resourceType: "Organization", bundlePath: bundlePath)
    .sorted { $0.code < $1.code }

let organizationCode = generateOrganizationExtractor(params: organizationParams)
let organizationOut  = "\(outputDir)/Organization+SearchExtractor.swift"
try organizationCode.write(toFile: organizationOut, atomically: true, encoding: .utf8)
print("Generated \(organizationOut) — \(organizationParams.count) Organization params")

let procedureParams = try loadParams(resourceType: "Procedure", bundlePath: bundlePath)
    .sorted { $0.code < $1.code }

let procedureCode = generateProcedureExtractor(params: procedureParams)
let procedureOut  = "\(outputDir)/Procedure+SearchExtractor.swift"
try procedureCode.write(toFile: procedureOut, atomically: true, encoding: .utf8)
print("Generated \(procedureOut) — \(procedureParams.count) Procedure params")

let diagnosticReportParams = try loadParams(resourceType: "DiagnosticReport", bundlePath: bundlePath)
    .sorted { $0.code < $1.code }

let diagnosticReportCode = generateDiagnosticReportExtractor(params: diagnosticReportParams)
let diagnosticReportOut  = "\(outputDir)/DiagnosticReport+SearchExtractor.swift"
try diagnosticReportCode.write(toFile: diagnosticReportOut, atomically: true, encoding: .utf8)
print("Generated \(diagnosticReportOut) — \(diagnosticReportParams.count) DiagnosticReport params")

let immunizationParams = try loadParams(resourceType: "Immunization", bundlePath: bundlePath)
    .sorted { $0.code < $1.code }

let immunizationCode = generateImmunizationExtractor(params: immunizationParams)
let immunizationOut  = "\(outputDir)/Immunization+SearchExtractor.swift"
try immunizationCode.write(toFile: immunizationOut, atomically: true, encoding: .utf8)
print("Generated \(immunizationOut) — \(immunizationParams.count) Immunization params")

let medicationRequestParams = try loadParams(resourceType: "MedicationRequest", bundlePath: bundlePath)
    .sorted { $0.code < $1.code }

let medicationRequestCode = generateMedicationRequestExtractor(params: medicationRequestParams)
let medicationRequestOut  = "\(outputDir)/MedicationRequest+SearchExtractor.swift"
try medicationRequestCode.write(toFile: medicationRequestOut, atomically: true, encoding: .utf8)
print("Generated \(medicationRequestOut) — \(medicationRequestParams.count) MedicationRequest params")

let allergyIntoleranceParams = try loadParams(resourceType: "AllergyIntolerance", bundlePath: bundlePath)
    .sorted { $0.code < $1.code }

let allergyIntoleranceCode = generateAllergyIntoleranceExtractor(params: allergyIntoleranceParams)
let allergyIntoleranceOut  = "\(outputDir)/AllergyIntolerance+SearchExtractor.swift"
try allergyIntoleranceCode.write(toFile: allergyIntoleranceOut, atomically: true, encoding: .utf8)
print("Generated \(allergyIntoleranceOut) — \(allergyIntoleranceParams.count) AllergyIntolerance params")

let encounterParams = try loadParams(resourceType: "Encounter", bundlePath: bundlePath)
    .sorted { $0.code < $1.code }

let encounterCode = generateEncounterExtractor(params: encounterParams)
let encounterOut  = "\(outputDir)/Encounter+SearchExtractor.swift"
try encounterCode.write(toFile: encounterOut, atomically: true, encoding: .utf8)
print("Generated \(encounterOut) — \(encounterParams.count) Encounter params")

let conditionParams = try loadParams(resourceType: "Condition", bundlePath: bundlePath)
    .sorted { $0.code < $1.code }

let conditionCode = generateConditionExtractor(params: conditionParams)
let conditionOut  = "\(outputDir)/Condition+SearchExtractor.swift"
try conditionCode.write(toFile: conditionOut, atomically: true, encoding: .utf8)
print("Generated \(conditionOut) — \(conditionParams.count) Condition params")

let patientParams = try loadParams(resourceType: "Patient", bundlePath: bundlePath)
    .sorted { $0.code < $1.code }

let patientCode = generatePatientExtractor(params: patientParams)
let patientOut  = "\(outputDir)/Patient+SearchExtractor.swift"
try patientCode.write(toFile: patientOut, atomically: true, encoding: .utf8)
print("Generated \(patientOut) — \(patientParams.count) Patient params")

let obsParams = try loadParams(resourceType: "Observation", bundlePath: bundlePath)
    .sorted { $0.code < $1.code }

let obsCode = generateObservationExtractor(params: obsParams)
let obsOut  = "\(outputDir)/Observation+SearchExtractor.swift"
try obsCode.write(toFile: obsOut, atomically: true, encoding: .utf8)
print("Generated \(obsOut) — \(obsParams.count) Observation params")
