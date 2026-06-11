import Foundation

struct ParamSpec {
    let code: String
    let type: String
    let expression: String
}

/// Loads SearchParameter specs from all .tgz packages in packagesDir.
/// Packages are processed in alphabetical order so IG packages (e.g. tw.gov.mohw.twcore)
/// override base packages (e.g. hl7.fhir.r4.core) for the same code + base combination.
func loadParams(resourceType: String, packagesDir: String) throws -> [ParamSpec] {
    let fm = FileManager.default

    let contents = try fm.contentsOfDirectory(atPath: packagesDir)
    let tgzFiles = contents
        .filter { $0.hasSuffix(".tgz") }
        .sorted()
        .map { "\(packagesDir)/\($0)" }

    guard !tgzFiles.isEmpty else {
        throw NSError(
            domain: "SimingGenerator", code: 1,
            userInfo: [NSLocalizedDescriptionKey:
                "No .tgz packages found in '\(packagesDir)'. " +
                "Run scripts/fetch-packages.sh to download required packages."]
        )
    }

    var merged: [String: ParamSpec] = [:]  // code → spec

    for tgzPath in tgzFiles {
        let params = try loadParamsFromTGZ(resourceType: resourceType, tgzPath: tgzPath)
        for spec in params {
            // Skip geospatial, composite (multi-component, not yet indexable), extension-based,
            // and meta (_-prefixed) params handled globally at query layer, not via extractors.
            guard spec.type != "special",
                  spec.type != "composite",
                  !spec.code.hasPrefix("_"),
                  !spec.expression.contains(".extension(") else { continue }
            // Don't replace a more-specific reference path with a shorter one.
            // e.g. keep r4.core "Encounter.location.location" over TW Core "Encounter.location"
            if let existing = merged[spec.code],
               spec.type == "reference",
               existing.expression.hasPrefix(spec.expression + ".") { continue }
            merged[spec.code] = spec
        }
    }

    return Array(merged.values)
}

private func loadParamsFromTGZ(resourceType: String, tgzPath: String) throws -> [ParamSpec] {
    let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("siming-pkg-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let tar = Process()
    tar.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
    tar.arguments = ["xzf", tgzPath, "-C", tempDir.path]
    try tar.run()
    tar.waitUntilExit()
    guard tar.terminationStatus == 0 else {
        throw NSError(
            domain: "SimingGenerator", code: 2,
            userInfo: [NSLocalizedDescriptionKey: "tar failed for \(tgzPath)"]
        )
    }

    let packageDir = tempDir.appendingPathComponent("package")
    guard FileManager.default.fileExists(atPath: packageDir.path) else { return [] }

    var results: [ParamSpec] = []
    let jsonFiles = (try? FileManager.default.contentsOfDirectory(atPath: packageDir.path)) ?? []

    for filename in jsonFiles where filename.hasSuffix(".json") {
        let filePath = packageDir.appendingPathComponent(filename)
        guard let data = try? Data(contentsOf: filePath),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              obj["resourceType"] as? String == "SearchParameter",
              let code = obj["code"] as? String,
              let type_ = obj["type"] as? String,
              let bases = obj["base"] as? [String], bases.contains(resourceType),
              let expression = obj["expression"] as? String
        else { continue }
        results.append(ParamSpec(code: code, type: type_, expression: expression))
    }

    return results
}
