import Foundation
import Logging
import PostgresNIO

/// Shared write transaction.
///
/// Combines If-Match validation, version increment, and resource INSERT into a
/// single CTE (one DB round trip instead of three), then refreshes index rows
/// via replaceIndexRows.
///
/// Throws FHIRServerError.versionConflict when If-Match is set and does not
/// match the current version.
public func writeResource(
    conn: PostgresConnection,
    resourceType: String,
    id: String,
    jsonString: String,
    ifMatch: Int64?,
    params: SearchParams,
    logger: Logger
) async throws -> (versionId: Int64, lastUpdated: Date) {
    _ = try await conn.query("BEGIN", logger: logger)
    do {
        var binds = PostgresBindings()
        binds.append(resourceType)  // $1
        binds.append(id)            // $2
        if let m = ifMatch { binds.append(m) } else { binds.appendNull() }  // $3
        binds.append(jsonString)    // $4

        // Single round trip: compute current version, validate If-Match,
        // compute next version, insert the new resource row.
        let sql = """
        WITH
        cur AS (
            SELECT COALESCE(MAX(version_id), 0) AS v
            FROM resources WHERE resource_type = $1 AND id = $2
        ),
        chk AS (
            SELECT v, v + 1 AS nv FROM cur
            WHERE $3::bigint IS NULL OR v = $3
        )
        INSERT INTO resources (resource_type, id, version_id, last_updated, content, deleted)
        SELECT $1, $2, nv, now(), $4::jsonb, false FROM chk
        RETURNING version_id, last_updated
        """
        let rows = try await conn.query(PostgresQuery(unsafeSQL: sql, binds: binds), logger: logger)
        var versionId: Int64? = nil
        var lastUpdated: Date? = nil
        for try await (vid, lu) in rows.decode((Int64, Date).self, context: .default) {
            versionId = vid; lastUpdated = lu
        }
        guard let vid = versionId, let lu = lastUpdated else {
            _ = try? await conn.query("ROLLBACK", logger: logger)
            throw FHIRServerError.versionConflict(id: id, expected: ifMatch ?? -1, actual: nil)
        }

        try await replaceIndexRows(conn: conn, resourceType: resourceType, id: id, params: params, logger: logger)
        _ = try await conn.query("COMMIT", logger: logger)
        return (vid, lu)
    } catch {
        _ = try? await conn.query("ROLLBACK", logger: logger)
        throw error
    }
}

/// Shared delete transaction.
///
/// Reads the current state, validates If-Match, inserts a tombstone, then
/// clears all index rows via the clear_index_rows SQL function.
///
/// Returns (versionId, lastUpdated, alreadyDeleted).
/// alreadyDeleted == true means the resource was already in a deleted state;
/// callers should treat this as idempotent (return 204 with existing version).
///
/// Throws FHIRServerError.notFound when the resource has never existed.
/// Throws FHIRServerError.versionConflict when If-Match is set and mismatches.
public func deleteResource(
    conn: PostgresConnection,
    resourceType: String,
    id: String,
    ifMatch: Int64?,
    logger: Logger
) async throws -> (versionId: Int64, lastUpdated: Date, alreadyDeleted: Bool) {
    _ = try await conn.query("BEGIN", logger: logger)
    do {
        let rows = try await conn.query(
            """
            SELECT version_id, deleted FROM resources
            WHERE resource_type = \(resourceType) AND id = \(id)
            ORDER BY version_id DESC LIMIT 1
            """, logger: logger)
        var currentVersion: Int64? = nil
        var isDeleted = false
        for try await (v, d) in rows.decode((Int64, Bool).self, context: .default) {
            currentVersion = v; isDeleted = d
        }
        guard let current = currentVersion else {
            _ = try? await conn.query("ROLLBACK", logger: logger)
            throw FHIRServerError.notFound(resourceType: resourceType, id: id)
        }
        if isDeleted {
            _ = try? await conn.query("ROLLBACK", logger: logger)
            return (current, Date(), true)
        }
        if let expected = ifMatch, current != expected {
            _ = try? await conn.query("ROLLBACK", logger: logger)
            throw FHIRServerError.versionConflict(id: id, expected: expected, actual: current)
        }

        let nextVersion = current + 1
        let insRows = try await conn.query(
            """
            INSERT INTO resources (resource_type, id, version_id, last_updated, content, deleted)
            VALUES (\(resourceType), \(id), \(nextVersion), now(), '{}'::jsonb, true)
            RETURNING last_updated
            """, logger: logger)
        var lastUpdated = Date()
        for try await (d) in insRows.decode(Date.self, context: .default) { lastUpdated = d }

        _ = try await conn.query("SELECT clear_index_rows(\(resourceType), \(id))", logger: logger)
        _ = try await conn.query("COMMIT", logger: logger)
        return (nextVersion, lastUpdated, false)
    } catch {
        _ = try? await conn.query("ROLLBACK", logger: logger)
        throw error
    }
}
