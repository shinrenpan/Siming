import Foundation
import Logging
import SimingCore

/// Loads CodeSystem and ValueSet resources from all .tgz packages in `packagesDir`.
///
/// Two-pass strategy:
///   Pass 1 — index all CodeSystems (url → set of codes, flattened recursively).
///   Pass 2 — build ValueSet index; for "include all codes from system" entries,
///             resolve against the CodeSystem index from pass 1.
///
/// Intensional ValueSets (compose.include[].filter present) are recorded but not expanded —
/// validation for those is skipped (conservative pass-through).
///
/// Never throws. Returns `TerminologyIndex.empty` when the directory is absent or empty.
public func loadTerminology(packagesDir: String, logger: Logger) -> TerminologyIndex {
    let fm = FileManager.default
    guard let contents = try? fm.contentsOfDirectory(atPath: packagesDir) else {
        return .empty
    }
    let tgzFiles = contents.filter { $0.hasSuffix(".tgz") }.sorted()
        .map { "\(packagesDir)/\($0)" }
    guard !tgzFiles.isEmpty else { return .empty }

    // Collect all JSON objects from every package (one pass over the filesystem)
    var allObjects: [[String: Any]] = []
    for tgzPath in tgzFiles {
        guard let tempDir = extractTGZTerm(tgzPath) else { continue }
        defer { try? fm.removeItem(at: tempDir) }
        let pkgDir = tempDir.appendingPathComponent("package")
        guard let files = try? fm.contentsOfDirectory(atPath: pkgDir.path) else { continue }
        for filename in files where filename.hasSuffix(".json") {
            guard
                let data = try? Data(contentsOf: pkgDir.appendingPathComponent(filename)),
                let obj  = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { continue }
            allObjects.append(obj)
        }
    }

    // ── Pass 1: CodeSystems ───────────────────────────────────────────────────

    var codeSystems: [String: Set<String>] = [:]
    for obj in allObjects where obj["resourceType"] as? String == "CodeSystem" {
        guard let url      = obj["url"] as? String,
              let concepts = obj["concept"] as? [[String: Any]]
        else { continue }
        var codes = Set<String>()
        collectCodes(from: concepts, into: &codes)
        codeSystems[url] = codes
    }

    // ── Pass 2: ValueSets ─────────────────────────────────────────────────────

    var valueSets:   [String: Set<TermCode>] = [:]
    var intensional: Set<String>             = []

    for obj in allObjects where obj["resourceType"] as? String == "ValueSet" {
        guard let url      = obj["url"] as? String,
              let compose  = obj["compose"] as? [String: Any],
              let includes = compose["include"] as? [[String: Any]]
        else { continue }

        var termCodes = Set<TermCode>()
        var skip      = false

        for include in includes {
            guard let system = include["system"] as? String else { continue }

            if include["filter"] != nil {
                skip = true
                break
            }

            if let concepts = include["concept"] as? [[String: Any]] {
                // Explicit code list
                for concept in concepts {
                    if let code = concept["code"] as? String {
                        termCodes.insert(TermCode(system: system, code: code))
                    }
                }
            } else {
                // No filter, no concept list → include all codes from the CodeSystem
                if let allCodes = codeSystems[system] {
                    for code in allCodes {
                        termCodes.insert(TermCode(system: system, code: code))
                    }
                }
                // CodeSystem not in index → conservative: add no codes from this include
            }
        }

        if skip {
            intensional.insert(url)
        } else {
            valueSets[url] = termCodes
        }
    }

    let index = TerminologyIndex(
        codeSystems: codeSystems,
        valueSets: valueSets,
        intensionalValueSets: intensional
    )
    let msg = "[Terminology] Loaded \(index.codeSystemCount) CodeSystems, \(index.valueSetCount) extensional ValueSets, \(index.intensionalCount) intensional (skipped)"
    logger.info("\(msg)")
    return index
}

// ── Helpers ───────────────────────────────────────────────────────────────────

private func collectCodes(from concepts: [[String: Any]], into codes: inout Set<String>) {
    for concept in concepts {
        if let code = concept["code"] as? String { codes.insert(code) }
        if let children = concept["concept"] as? [[String: Any]] {
            collectCodes(from: children, into: &codes)
        }
    }
}

private func extractTGZTerm(_ tgzPath: String) -> URL? {
    let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("siming-term-\(UUID().uuidString)")
    guard (try? FileManager.default.createDirectory(
        at: tempDir, withIntermediateDirectories: true)) != nil
    else { return nil }
    let tar = Process()
    tar.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
    tar.arguments    = ["xzf", tgzPath, "-C", tempDir.path]
    try? tar.run()
    tar.waitUntilExit()
    return tar.terminationStatus == 0 ? tempDir : nil
}
