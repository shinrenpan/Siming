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
