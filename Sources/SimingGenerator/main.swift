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

let patientParams = try loadParams(resourceType: "Patient", bundlePath: bundlePath)
    .sorted { $0.code < $1.code }

let patientCode = generatePatientExtractor(params: patientParams)
let patientOut  = "\(outputDir)/Patient+SearchExtractor.swift"
try patientCode.write(toFile: patientOut, atomically: true, encoding: .utf8)

print("Generated \(patientOut) — \(patientParams.count) Patient params")
