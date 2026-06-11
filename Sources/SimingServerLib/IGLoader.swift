import Foundation

// ── Data types ────────────────────────────────────────────────────────────────

struct IGSearchParam {
    let code: String
    let type: String        // "string" | "token" | "reference" | "date" | "quantity" | "uri" | …
    let url: String?        // canonical URL for the SearchParameter definition
    let targets: [String]   // resource types this reference param can point to (from r4.core)
}

struct IGData {
    /// SearchParameters per resource type, merged from all packages (IG overrides base).
    let searchParams: [String: [IGSearchParam]]
    /// IG-specific profile canonical URLs per resource type (excludes base R4 SDs).
    /// Multiple profiles per resource are possible (e.g. Observation has 26 TW Core profiles).
    let profiles: [String: [String]]
    /// ImplementationGuide canonical URLs declared by loaded IG packages.
    let implementationGuides: [String]
}

// ── Loader ────────────────────────────────────────────────────────────────────

/// Loads SearchParameters, StructureDefinition profiles, and ImplementationGuide URLs
/// from all .tgz packages in `packagesDir`. Packages are processed alphabetically so IG
/// packages override base packages for the same param code.
/// Never throws — returns empty IGData if packages directory is missing or empty.
func loadIG(packagesDir: String, resourceTypes: [String]) -> IGData {
    let fm = FileManager.default
    guard let contents = try? fm.contentsOfDirectory(atPath: packagesDir) else {
        return IGData(searchParams: [:], profiles: [:], implementationGuides: [])
    }
    let tgzFiles = contents.filter { $0.hasSuffix(".tgz") }.sorted()
        .map { "\(packagesDir)/\($0)" }
    guard !tgzFiles.isEmpty else {
        return IGData(searchParams: [:], profiles: [:], implementationGuides: [])
    }

    let targetSet = Set(resourceTypes)
    // code-keyed dict per resource type so later package overrides earlier
    var mergedParams: [String: [String: IGSearchParam]] = [:]
    // set-keyed profiles per resource type — accumulated across all packages
    var profileSets: [String: Set<String>] = [:]
    var igURLs: Set<String> = []

    for tgzPath in tgzFiles {
        guard let tempDir = extractTGZ(tgzPath) else { continue }
        defer { try? fm.removeItem(at: tempDir) }
        let pkgDir = tempDir.appendingPathComponent("package")
        guard let files = try? fm.contentsOfDirectory(atPath: pkgDir.path) else { continue }

        for filename in files where filename.hasSuffix(".json") {
            guard let data = try? Data(contentsOf: pkgDir.appendingPathComponent(filename)),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { continue }

            switch obj["resourceType"] as? String {

            case "SearchParameter":
                guard let code = obj["code"] as? String,
                      let type_ = obj["type"] as? String,
                      let bases = obj["base"] as? [String],
                      let expression = obj["expression"] as? String, !expression.isEmpty
                else { continue }
                let url = obj["url"] as? String
                let newTargets = obj["target"] as? [String] ?? []
                for base in bases where targetSet.contains(base) {
                    let existing = mergedParams[base]?[code]
                    // Preserve targets from earlier package (e.g. r4.core) if new package has none
                    let targets = newTargets.isEmpty ? (existing?.targets ?? []) : newTargets
                    let param = IGSearchParam(code: code, type: type_, url: url, targets: targets)
                    if mergedParams[base] == nil { mergedParams[base] = [:] }
                    mergedParams[base]![code] = param
                }

            case "StructureDefinition":
                guard let type_ = obj["type"] as? String,
                      targetSet.contains(type_),
                      let url = obj["url"] as? String,
                      obj["kind"] as? String == "resource",
                      obj["abstract"] as? Bool != true,
                      // Skip base R4 definitions — only collect IG-specific profiles
                      !url.hasPrefix("http://hl7.org/fhir/StructureDefinition/")
                else { continue }
                profileSets[type_, default: []].insert(url)

            case "ImplementationGuide":
                guard let url = obj["url"] as? String,
                      // Skip base R4 IG — only collect external IG canonical URLs
                      !url.hasPrefix("http://hl7.org/fhir/")
                else { continue }
                igURLs.insert(url)

            default: break
            }
        }
    }

    let searchParams = mergedParams.mapValues { byCode in
        Array(byCode.values).sorted { $0.code < $1.code }
    }
    let profiles = profileSets.mapValues { Array($0).sorted() }
    return IGData(
        searchParams: searchParams,
        profiles: profiles,
        implementationGuides: igURLs.sorted()
    )
}

// ── Helpers ───────────────────────────────────────────────────────────────────

private func extractTGZ(_ tgzPath: String) -> URL? {
    let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("siming-ig-\(UUID().uuidString)")
    guard (try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)) != nil
    else { return nil }
    let tar = Process()
    tar.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
    tar.arguments = ["xzf", tgzPath, "-C", tempDir.path]
    try? tar.run()
    tar.waitUntilExit()
    return tar.terminationStatus == 0 ? tempDir : nil
}
