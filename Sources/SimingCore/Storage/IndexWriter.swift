import Foundation
import Logging
import PostgresNIO

/// Replaces all index rows for one resource inside an open transaction.
///
/// Deletes the existing index rows (5 statements, each hitting an indexed column),
/// then bulk-inserts the new rows using a single multi-row VALUES clause per
/// non-empty table type — reducing N individual round trips to at most 10.
public func replaceIndexRows(
    conn: PostgresConnection,
    resourceType: String,
    id: String,
    params: SearchParams,
    logger: Logger
) async throws {
    _ = try await conn.query("SELECT clear_index_rows(\(resourceType), \(id))", logger: logger)

    if !params.tokens.isEmpty {
        var binds = PostgresBindings()
        var n = 0
        func b(_ v: some PostgresDynamicTypeEncodable) -> String { n += 1; binds.append(v); return "$\(n)" }
        func bNull() -> String { n += 1; binds.appendNull(); return "$\(n)" }
        let rt = b(resourceType); let rid = b(id)
        let rows = params.tokens.map { row -> String in
            let pn = b(row.paramName)
            let sys = row.system != nil ? b(row.system!) : bNull()
            let code = b(row.code)
            return "(\(rt), \(rid), \(pn), \(sys), \(code))"
        }
        _ = try await conn.query(
            PostgresQuery(unsafeSQL: "INSERT INTO idx_token (resource_type, resource_id, param_name, system, code) VALUES \(rows.joined(separator: ","))", binds: binds),
            logger: logger)
    }

    if !params.strings.isEmpty {
        var binds = PostgresBindings()
        var n = 0
        func b(_ v: some PostgresDynamicTypeEncodable) -> String { n += 1; binds.append(v); return "$\(n)" }
        let rt = b(resourceType); let rid = b(id)
        let rows = params.strings.map { row -> String in
            let pn = b(row.paramName); let val = b(row.value)
            return "(\(rt), \(rid), \(pn), \(val))"
        }
        _ = try await conn.query(
            PostgresQuery(unsafeSQL: "INSERT INTO idx_string (resource_type, resource_id, param_name, value) VALUES \(rows.joined(separator: ","))", binds: binds),
            logger: logger)
    }

    if !params.dates.isEmpty {
        var binds = PostgresBindings()
        var n = 0
        func b(_ v: some PostgresDynamicTypeEncodable) -> String { n += 1; binds.append(v); return "$\(n)" }
        let rt = b(resourceType); let rid = b(id)
        let rows = params.dates.map { row -> String in
            let pn = b(row.paramName); let ds = b(row.dateStart); let de = b(row.dateEnd)
            return "(\(rt), \(rid), \(pn), \(ds), \(de))"
        }
        _ = try await conn.query(
            PostgresQuery(unsafeSQL: "INSERT INTO idx_date (resource_type, resource_id, param_name, date_start, date_end) VALUES \(rows.joined(separator: ","))", binds: binds),
            logger: logger)
    }

    if !params.references.isEmpty {
        var binds = PostgresBindings()
        var n = 0
        func b(_ v: some PostgresDynamicTypeEncodable) -> String { n += 1; binds.append(v); return "$\(n)" }
        func bNull() -> String { n += 1; binds.appendNull(); return "$\(n)" }
        let rt = b(resourceType); let rid = b(id)
        let rows = params.references.map { row -> String in
            let pn = b(row.paramName)
            let rft = row.refType != nil ? b(row.refType!) : bNull()
            let rfid = b(row.refId)
            return "(\(rt), \(rid), \(pn), \(rft), \(rfid))"
        }
        _ = try await conn.query(
            PostgresQuery(unsafeSQL: "INSERT INTO idx_reference (resource_type, resource_id, param_name, ref_type, ref_id) VALUES \(rows.joined(separator: ","))", binds: binds),
            logger: logger)
    }

    if !params.quantities.isEmpty {
        var binds = PostgresBindings()
        var n = 0
        func b(_ v: some PostgresDynamicTypeEncodable) -> String { n += 1; binds.append(v); return "$\(n)" }
        func bNull() -> String { n += 1; binds.appendNull(); return "$\(n)" }
        let rt = b(resourceType); let rid = b(id)
        let rows = params.quantities.map { row -> String in
            let pn = b(row.paramName)
            let sys = row.system != nil ? b(row.system!) : bNull()
            let code = row.code != nil ? b(row.code!) : bNull()
            let val = b(NSDecimalNumber(decimal: row.value).doubleValue)
            return "(\(rt), \(rid), \(pn), \(sys), \(code), \(val))"
        }
        _ = try await conn.query(
            PostgresQuery(unsafeSQL: "INSERT INTO idx_quantity (resource_type, resource_id, param_name, system, code, value) VALUES \(rows.joined(separator: ","))", binds: binds),
            logger: logger)
    }
}
