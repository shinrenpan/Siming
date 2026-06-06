import Foundation
import Logging
import PostgresNIO

/// A parsed _include or _revinclude parameter.
/// Format: `ResourceType:paramName` or `ResourceType:paramName:TargetType`
public struct IncludeParam: Sendable {
    public let sourceType: String
    public let paramName: String
    public let targetType: String?

    public init(sourceType: String, paramName: String, targetType: String? = nil) {
        self.sourceType = sourceType
        self.paramName = paramName
        self.targetType = targetType
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
    /// - sourceIds: IDs of the main search results (e.g. Observation IDs).
    /// - includes: each param describes which reference field to follow (e.g. Observation:subject).
    public func resolve(includes: [IncludeParam], sourceIds: [String]) async throws -> [IncludedResource] {
        guard !includes.isEmpty, !sourceIds.isEmpty else { return [] }
        var seen: [String: IncludedResource] = [:]
        for param in includes {
            try await fetchInclude(param: param, sourceIds: sourceIds, into: &seen)
        }
        return Array(seen.values)
    }

    /// _revinclude: find resources that REFERENCE the main result set.
    /// - mainIds: IDs of the main search results (e.g. Patient IDs).
    /// - revIncludes: each param describes which resource type+param to scan (e.g. Observation:subject).
    public func resolveRev(revIncludes: [IncludeParam], mainIds: [String]) async throws -> [IncludedResource] {
        guard !revIncludes.isEmpty, !mainIds.isEmpty else { return [] }
        var seen: [String: IncludedResource] = [:]
        for param in revIncludes {
            try await fetchRevInclude(param: param, mainIds: mainIds, into: &seen)
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
        let p2 = bind(param.paramName)
        let idList = sourceIds.map { bind($0) }.joined(separator: ",")

        var extra = ""
        if let tt = param.targetType { extra = " AND ref.ref_type = \(bind(tt))" }

        let sql = """
        SELECT DISTINCT ON (r.resource_type, r.id)
            r.resource_type, r.id, r.version_id, r.last_updated, r.content
        FROM idx_reference ref
        JOIN resources r
            ON r.resource_type = ref.ref_type
            AND r.id = ref.ref_id
            AND r.deleted = false
        WHERE ref.resource_type = \(p1)
          AND ref.param_name = \(p2)
          AND ref.resource_id IN (\(idList))
          \(extra)
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
        let p2 = bind(param.paramName)
        let idList = mainIds.map { bind($0) }.joined(separator: ",")

        let sql = """
        SELECT DISTINCT ON (r.resource_type, r.id)
            r.resource_type, r.id, r.version_id, r.last_updated, r.content
        FROM idx_reference ref
        JOIN resources r
            ON r.resource_type = ref.resource_type
            AND r.id = ref.resource_id
            AND r.deleted = false
        WHERE ref.resource_type = \(p1)
          AND ref.param_name = \(p2)
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
