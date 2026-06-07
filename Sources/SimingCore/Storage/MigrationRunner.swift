import Foundation
import Logging
import PostgresNIO

public struct MigrationRunner: Sendable {
    public let client: PostgresClient
    public let logger: Logger
    public let migrationsPath: String

    public init(client: PostgresClient, logger: Logger, migrationsPath: String = "migrations") {
        self.client = client
        self.logger = logger
        self.migrationsPath = migrationsPath
    }

    public func run() async throws {
        try await ensureMigrationsTable()
        let applied = try await fetchApplied()
        let files = try pendingFiles(applied: applied)

        for file in files {
            let version = String(file.dropLast(4)) // strip .sql
            try await apply(version: version, file: file)
        }

        if files.isEmpty {
            logger.info("No pending migrations.")
        }
    }

    // MARK: - Private

    private func ensureMigrationsTable() async throws {
        try await client.withConnection { conn in
            _ = try await conn.query(
                """
                CREATE TABLE IF NOT EXISTS schema_migrations (
                    version     TEXT        PRIMARY KEY,
                    applied_at  TIMESTAMPTZ NOT NULL DEFAULT now()
                )
                """,
                logger: logger
            )
        }
    }

    private func fetchApplied() async throws -> Set<String> {
        try await client.withConnection { conn in
            let rows = try await conn.query(
                "SELECT version FROM schema_migrations ORDER BY version",
                logger: logger
            )
            var versions = Set<String>()
            for try await (version) in rows.decode(String.self, context: .default) {
                versions.insert(version)
            }
            return versions
        }
    }

    private func pendingFiles(applied: Set<String>) throws -> [String] {
        let all = try FileManager.default
            .contentsOfDirectory(atPath: migrationsPath)
            .filter { $0.hasSuffix(".sql") }
            .sorted()
        return all.filter { !applied.contains(String($0.dropLast(4))) }
    }

    private func apply(version: String, file: String) async throws {
        let filePath = "\(migrationsPath)/\(file)"
        let sql = try String(contentsOfFile: filePath, encoding: .utf8)
        logger.info("Applying migration: \(version)")

        try await client.withConnection { conn in
            for statement in splitSQL(sql) {
                _ = try await conn.query(PostgresQuery(unsafeSQL: statement), logger: logger)
            }
            _ = try await conn.query(
                "INSERT INTO schema_migrations (version) VALUES (\(version))",
                logger: logger
            )
        }
        logger.info("Applied migration: \(version)")
    }

    /// Splits a SQL file into executable statements on `;`, respecting dollar-quoted
    /// strings (`$$...$$` and `$tag$...$tag$`) so that semicolons inside PL/pgSQL
    /// function bodies are not treated as statement terminators.
    private func splitSQL(_ sql: String) -> [String] {
        var statements: [String] = []
        var current = ""
        var dollarTag: String? = nil  // non-nil while inside a dollar-quoted string
        let chars = Array(sql)
        var i = 0

        while i < chars.count {
            if let tag = dollarTag {
                // Inside a dollar-quoted string: scan for the closing tag.
                if sql[sql.index(sql.startIndex, offsetBy: i)...].hasPrefix(tag) {
                    current.append(contentsOf: tag)
                    i += tag.count
                    dollarTag = nil
                } else {
                    current.append(chars[i])
                    i += 1
                }
            } else if chars[i] == "$" {
                // Scan forward for the closing $ to detect a dollar-quote tag.
                var j = i + 1
                while j < chars.count && chars[j] != "$" && chars[j] != "\n" { j += 1 }
                if j < chars.count && chars[j] == "$" {
                    let tag = String(chars[i...j])  // e.g. "$$" or "$func$"
                    dollarTag = tag
                    current.append(contentsOf: tag)
                    i = j + 1
                } else {
                    current.append(chars[i])
                    i += 1
                }
            } else if chars[i] == ";" {
                let stmt = cleanStatement(current)
                if !stmt.isEmpty { statements.append(stmt) }
                current = ""
                i += 1
            } else {
                current.append(chars[i])
                i += 1
            }
        }
        let stmt = cleanStatement(current)
        if !stmt.isEmpty { statements.append(stmt) }
        return statements
    }

    private func cleanStatement(_ s: String) -> String {
        s.split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("--") }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
