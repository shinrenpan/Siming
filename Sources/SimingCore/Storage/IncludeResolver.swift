import Foundation
import Logging
import PostgresNIO

/// A parsed _include or _revinclude parameter.
/// Format: `ResourceType:paramName` or `ResourceType:paramName:TargetType`
/// `isIterate` is true when parsed from `_include:iterate` / `_revinclude:iterate`.
/// `paramName == "*"` means wildcard — follow all reference params of the source type.
public struct IncludeParam: Sendable {
    public let sourceType: String
    public let paramName: String
    public let targetType: String?
    public let isIterate: Bool

    public init(sourceType: String, paramName: String, targetType: String? = nil, isIterate: Bool = false) {
        self.sourceType = sourceType
        self.paramName  = paramName
        self.targetType = targetType
        self.isIterate  = isIterate
    }
}

/// A resource fetched as a search include result, with meta already injected.
public struct IncludedResource: Sendable {
    public let resourceType: String
    public let id: String
    public let jsonWithMeta: Data
}

/// Resolves _include and _revinclude parameters against idx_reference.
public struct IncludeResolver: Sendable {
    let client: PostgresClient
    let logger: Logger

    public init(client: PostgresClient, logger: Logger) {
        self.client = client
        self.logger = logger
    }

    /// _include: follow references FROM the main result set to other resources.
    /// Handles `:iterate` (recursive until stable, max 5 levels) and `*` wildcard paramName.
    public func resolve(includes: [IncludeParam], sourceIds: [String]) async throws -> [IncludedResource] {
        guard !includes.isEmpty, !sourceIds.isEmpty else { return [] }

        var seen: [String: IncludedResource] = [:]

        // First pass: all include params (both regular and iterate) against main source IDs.
        for param in includes {
            try await fetchInclude(param: param, sourceIds: sourceIds, into: &seen)
        }

        let iterateParams = includes.filter { $0.isIterate }
        guard !iterateParams.isEmpty else { return Array(seen.values) }

        // Iterative passes: follow iterate params on newly-discovered resources until stable.
        // `usedAsSource` tracks "ResourceType/id" keys already used as a frontier source.
        var usedAsSource: Set<String> = []

        for _ in 0..<5 {
            // Frontier = seen resources matching an iterate param's sourceType and not yet used.
            var frontier: [String: [String]] = [:]   // resourceType → [id]
            for r in seen.values {
                let key = "\(r.resourceType)/\(r.id)"
                guard !usedAsSource.contains(key) else { continue }
                guard iterateParams.contains(where: { $0.sourceType == r.resourceType }) else { continue }
                frontier[r.resourceType, default: []].append(r.id)
            }
            guard !frontier.isEmpty else { break }

            // Mark current frontier as used so we don't re-process it.
            for (type, ids) in frontier {
                for id in ids { usedAsSource.insert("\(type)/\(id)") }
            }

            var iterSeen: [String: IncludedResource] = [:]
            for param in iterateParams {
                if let ids = frontier[param.sourceType], !ids.isEmpty {
                    try await fetchInclude(param: param, sourceIds: ids, into: &iterSeen)
                }
            }

            let newResources = iterSeen.filter { seen[$0.key] == nil }
            guard !newResources.isEmpty else { break }
            seen.merge(newResources) { existing, _ in existing }
        }

        return Array(seen.values)
    }

    /// _revinclude: find resources that REFERENCE the main result set.
    /// Handles `:iterate` and `*` wildcard paramName.
    public func resolveRev(revIncludes: [IncludeParam], mainIds: [String]) async throws -> [IncludedResource] {
        guard !revIncludes.isEmpty, !mainIds.isEmpty else { return [] }

        var seen: [String: IncludedResource] = [:]

        // First pass: all revinclude params against main IDs.
        for param in revIncludes {
            try await fetchRevInclude(param: param, mainIds: mainIds, into: &seen)
        }

        let iterateParams = revIncludes.filter { $0.isIterate }
        guard !iterateParams.isEmpty else { return Array(seen.values) }

        // Iterative passes: also revinclude on newly-discovered resources until stable.
        var usedAsSource: Set<String> = Set(mainIds.map { "__main/\($0)" })

        for _ in 0..<5 {
            // Frontier = all IDs of revincluded resources not yet processed as revinclude targets.
            let frontierIds = seen.values
                .map { $0.id }
                .filter { !usedAsSource.contains("__rev/\($0)") }
            guard !frontierIds.isEmpty else { break }

            for id in frontierIds { usedAsSource.insert("__rev/\(id)") }

            var iterSeen: [String: IncludedResource] = [:]
            for param in iterateParams {
                try await fetchRevInclude(param: param, mainIds: frontierIds, into: &iterSeen)
            }

            let newResources = iterSeen.filter { seen[$0.key] == nil }
            guard !newResources.isEmpty else { break }
            seen.merge(newResources) { existing, _ in existing }
        }

        return Array(seen.values)
    }

    // MARK: - Private

    private func fetchInclude(
        param: IncludeParam,
        sourceIds: [String],
        into seen: inout [String: IncludedResource]
    ) async throws {
        var binds = PostgresBindings()
        var n = 0
        func bind(_ val: some PostgresDynamicTypeEncodable) -> String {
            n += 1; binds.append(val); return "$\(n)"
        }

        let p1 = bind(param.sourceType)
        let idList = sourceIds.map { bind($0) }.joined(separator: ",")

        // Wildcard: skip param_name filter; otherwise filter by param name.
        let paramFilter = param.paramName == "*" ? "" : " AND ref.param_name = \(bind(param.paramName))"
        var targetFilter = ""
        if let tt = param.targetType { targetFilter = " AND ref.ref_type = \(bind(tt))" }

        let sql = """
        SELECT DISTINCT ON (r.resource_type, r.id)
            r.resource_type, r.id, r.version_id, r.last_updated, r.content
        FROM idx_reference ref
        JOIN resources r
            ON r.resource_type = ref.ref_type
            AND r.id = ref.ref_id
            AND r.deleted = false
        WHERE ref.resource_type = \(p1)
          \(paramFilter)
          AND ref.resource_id IN (\(idList))
          \(targetFilter)
        ORDER BY r.resource_type, r.id, r.version_id DESC
        LIMIT 1000
        """

        try await client.withConnection { conn in
            let rows = try await conn.query(PostgresQuery(unsafeSQL: sql, binds: binds), logger: logger)
            for try await (rt, rid, vid, lu, content) in
                rows.decode((String, String, Int64, Date, String).self, context: .default)
            {
                let key = "\(rt)/\(rid)"
                guard seen[key] == nil else { continue }
                seen[key] = IncludedResource(
                    resourceType: rt, id: rid,
                    jsonWithMeta: injectMeta(into: content, versionId: vid, lastUpdated: lu)
                )
            }
        }
    }

    private func fetchRevInclude(
        param: IncludeParam,
        mainIds: [String],
        into seen: inout [String: IncludedResource]
    ) async throws {
        var binds = PostgresBindings()
        var n = 0
        func bind(_ val: some PostgresDynamicTypeEncodable) -> String {
            n += 1; binds.append(val); return "$\(n)"
        }

        let p1 = bind(param.sourceType)
        let idList = mainIds.map { bind($0) }.joined(separator: ",")

        // Wildcard: skip param_name filter.
        let paramFilter = param.paramName == "*" ? "" : " AND ref.param_name = \(bind(param.paramName))"

        let sql = """
        SELECT DISTINCT ON (r.resource_type, r.id)
            r.resource_type, r.id, r.version_id, r.last_updated, r.content
        FROM idx_reference ref
        JOIN resources r
            ON r.resource_type = ref.resource_type
            AND r.id = ref.resource_id
            AND r.deleted = false
        WHERE ref.resource_type = \(p1)
          \(paramFilter)
          AND ref.ref_id IN (\(idList))
        ORDER BY r.resource_type, r.id, r.version_id DESC
        LIMIT 1000
        """

        try await client.withConnection { conn in
            let rows = try await conn.query(PostgresQuery(unsafeSQL: sql, binds: binds), logger: logger)
            for try await (rt, rid, vid, lu, content) in
                rows.decode((String, String, Int64, Date, String).self, context: .default)
            {
                let key = "\(rt)/\(rid)"
                guard seen[key] == nil else { continue }
                seen[key] = IncludedResource(
                    resourceType: rt, id: rid,
                    jsonWithMeta: injectMeta(into: content, versionId: vid, lastUpdated: lu)
                )
            }
        }
    }
}
