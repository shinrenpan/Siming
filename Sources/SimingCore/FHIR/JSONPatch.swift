import Foundation

/// RFC 6901 JSON Pointer errors.
public enum JSONPointerError: Error {
    case invalidPointer(String)
}

/// Parses an RFC 6901 JSON Pointer string into a token array.
/// Empty string → root. "/a/b/0" → ["a", "b", "0"].
public func parseJSONPointer(_ pointer: String) throws -> [String] {
    guard pointer.isEmpty || pointer.hasPrefix("/") else {
        throw JSONPointerError.invalidPointer(
            "JSON Pointer must be empty or start with '/': \(pointer)"
        )
    }
    if pointer.isEmpty { return [] }
    return pointer.dropFirst()
        .split(separator: "/", omittingEmptySubsequences: false)
        .map {
            $0.replacingOccurrences(of: "~1", with: "/")
              .replacingOccurrences(of: "~0", with: "~")
        }
}

// ── RFC 6902 JSON Patch ───────────────────────────────────────────────────────

/// Errors thrown by the JSON Patch engine.
public enum JSONPatchError: Error {
    case invalidPatch(String)   // Malformed patch document or operation → 400
    case pathNotFound(String)   // Pointer path does not exist → 400
    case testFailed(String)     // `test` operation value mismatch → 422
}

/// RFC 6902 JSON Patch engine.
/// Operates on raw JSON `Data`; no FHIR-specific logic.
public enum JSONPatch {

    /// Apply a JSON Patch document to a JSON document.
    /// - Parameters:
    ///   - patchData: RFC 6902 patch array, UTF-8 encoded.
    ///   - documentData: Target JSON document, UTF-8 encoded.
    /// - Returns: Patched JSON document bytes.
    public static func apply(_ patchData: Data, to documentData: Data) throws -> Data {
        guard let raw = try? JSONSerialization.jsonObject(with: patchData),
              let ops = raw as? [[String: Any]] else {
            throw JSONPatchError.invalidPatch(
                "Patch body must be a JSON array of operation objects"
            )
        }
        var doc: Any = (try? JSONSerialization.jsonObject(with: documentData)) ?? NSNull()
        for op in ops {
            doc = try applyOne(op, to: doc)
        }
        return try JSONSerialization.data(withJSONObject: doc)
    }

    // ── Operation dispatch ────────────────────────────────────────────────────

    private static func applyOne(_ op: [String: Any], to doc: Any) throws -> Any {
        guard let opType = op["op"] as? String else {
            throw JSONPatchError.invalidPatch("Operation missing required 'op' field")
        }
        guard let pathStr = op["path"] as? String else {
            throw JSONPatchError.invalidPatch("Operation missing required 'path' field")
        }
        let path = try parseJSONPointer(pathStr)

        switch opType {
        case "add":
            guard let value = op["value"] else {
                throw JSONPatchError.invalidPatch("'add' operation missing required 'value' field")
            }
            return try jpAdd(value: value, at: path, in: doc)

        case "remove":
            return try jpRemove(at: path, from: doc)

        case "replace":
            guard let value = op["value"] else {
                throw JSONPatchError.invalidPatch("'replace' operation missing required 'value' field")
            }
            return try jpReplace(value: value, at: path, in: doc)

        case "move":
            guard let fromStr = op["from"] as? String else {
                throw JSONPatchError.invalidPatch("'move' operation missing required 'from' field")
            }
            let from = try parseJSONPointer(fromStr)
            let value = try jpGet(at: from, from: doc)
            let removed = try jpRemove(at: from, from: doc)
            return try jpAdd(value: value, at: path, in: removed)

        case "copy":
            guard let fromStr = op["from"] as? String else {
                throw JSONPatchError.invalidPatch("'copy' operation missing required 'from' field")
            }
            let from = try parseJSONPointer(fromStr)
            let value = try jpGet(at: from, from: doc)
            return try jpAdd(value: value, at: path, in: doc)

        case "test":
            guard let value = op["value"] else {
                throw JSONPatchError.invalidPatch("'test' operation missing required 'value' field")
            }
            let current = try jpGet(at: path, from: doc)
            guard jpEqual(current, value) else {
                throw JSONPatchError.testFailed("test operation failed at '\(pathStr)'")
            }
            return doc

        default:
            throw JSONPatchError.invalidPatch("Unknown operation type '\(opType)'")
        }
    }

    // ── Navigation ────────────────────────────────────────────────────────────

    private static func jpGet(at tokens: [String], from doc: Any) throws -> Any {
        var current = doc
        for (i, token) in tokens.enumerated() {
            if let dict = current as? [String: Any] {
                guard let next = dict[token] else {
                    let at = "/" + tokens[...i].joined(separator: "/")
                    throw JSONPatchError.pathNotFound("Key '\(token)' not found at \(at)")
                }
                current = next
            } else if let arr = current as? [Any] {
                guard let idx = Int(token), idx >= 0, idx < arr.count else {
                    let at = "/" + tokens[...i].joined(separator: "/")
                    throw JSONPatchError.pathNotFound("Array index '\(token)' out of bounds at \(at)")
                }
                current = arr[idx]
            } else {
                let at = "/" + tokens[..<i].joined(separator: "/")
                throw JSONPatchError.pathNotFound("Cannot navigate into scalar at \(at)")
            }
        }
        return current
    }

    // ── Mutation (pure functional — each returns a new document) ─────────────

    private static func jpAdd(value: Any, at tokens: [String], in doc: Any) throws -> Any {
        if tokens.isEmpty { return value }
        let parent = Array(tokens.dropLast())
        let key = tokens.last!
        return try jpModify(at: parent, in: doc) { container in
            if var dict = container as? [String: Any] {
                dict[key] = value
                return dict
            } else if var arr = container as? [Any] {
                if key == "-" {
                    arr.append(value)
                } else if let idx = Int(key), idx >= 0, idx <= arr.count {
                    arr.insert(value, at: idx)
                } else {
                    throw JSONPatchError.pathNotFound(
                        "Array index '\(key)' out of bounds for add (length \(arr.count))"
                    )
                }
                return arr
            } else {
                throw JSONPatchError.invalidPatch("Cannot add into a non-container node")
            }
        }
    }

    private static func jpRemove(at tokens: [String], from doc: Any) throws -> Any {
        guard !tokens.isEmpty else {
            throw JSONPatchError.invalidPatch("Cannot remove the root document")
        }
        let parent = Array(tokens.dropLast())
        let key = tokens.last!
        return try jpModify(at: parent, in: doc) { container in
            if var dict = container as? [String: Any] {
                guard dict[key] != nil else {
                    throw JSONPatchError.pathNotFound("Key '\(key)' not found for remove")
                }
                dict.removeValue(forKey: key)
                return dict
            } else if var arr = container as? [Any] {
                guard let idx = Int(key), idx >= 0, idx < arr.count else {
                    throw JSONPatchError.pathNotFound(
                        "Array index '\(key)' out of bounds for remove (length \(arr.count))"
                    )
                }
                arr.remove(at: idx)
                return arr
            } else {
                throw JSONPatchError.invalidPatch("Cannot remove from a non-container node")
            }
        }
    }

    private static func jpReplace(value: Any, at tokens: [String], in doc: Any) throws -> Any {
        if tokens.isEmpty { return value }
        let parent = Array(tokens.dropLast())
        let key = tokens.last!
        return try jpModify(at: parent, in: doc) { container in
            if var dict = container as? [String: Any] {
                guard dict[key] != nil else {
                    throw JSONPatchError.pathNotFound("Key '\(key)' not found for replace")
                }
                dict[key] = value
                return dict
            } else if var arr = container as? [Any] {
                guard let idx = Int(key), idx >= 0, idx < arr.count else {
                    throw JSONPatchError.pathNotFound(
                        "Array index '\(key)' out of bounds for replace (length \(arr.count))"
                    )
                }
                arr[idx] = value
                return arr
            } else {
                throw JSONPatchError.invalidPatch("Cannot replace in a non-container node")
            }
        }
    }

    /// Recursively navigate to `tokens` path, apply `modify` to the node there,
    /// and rebuild the document from root to that node with the new value.
    private static func jpModify(
        at tokens: [String],
        in doc: Any,
        modify: (Any) throws -> Any
    ) throws -> Any {
        if tokens.isEmpty { return try modify(doc) }
        let head = tokens[0]
        let tail = Array(tokens.dropFirst())
        if var dict = doc as? [String: Any] {
            guard let child = dict[head] else {
                throw JSONPatchError.pathNotFound("Key '\(head)' not found")
            }
            dict[head] = try jpModify(at: tail, in: child, modify: modify)
            return dict
        } else if var arr = doc as? [Any] {
            guard let idx = Int(head), idx >= 0, idx < arr.count else {
                throw JSONPatchError.pathNotFound(
                    "Array index '\(head)' out of bounds (length \(arr.count))"
                )
            }
            arr[idx] = try jpModify(at: tail, in: arr[idx], modify: modify)
            return arr
        } else {
            throw JSONPatchError.pathNotFound("Cannot navigate into scalar at '\(head)'")
        }
    }

    // ── Deep equality for `test` ──────────────────────────────────────────────

    private static func jpEqual(_ a: Any, _ b: Any) -> Bool {
        if let da = a as? [String: Any], let db = b as? [String: Any] {
            guard da.count == db.count else { return false }
            return da.allSatisfy { k, v in db[k].map { jpEqual(v, $0) } ?? false }
        }
        if let aa = a as? [Any], let ab = b as? [Any] {
            guard aa.count == ab.count else { return false }
            return zip(aa, ab).allSatisfy { jpEqual($0, $1) }
        }
        if let na = a as? NSNumber, let nb = b as? NSNumber { return na == nb }
        if let sa = a as? String, let sb = b as? String { return sa == sb }
        if a is NSNull, b is NSNull { return true }
        return false
    }
}
