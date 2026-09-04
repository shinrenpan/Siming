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

    /// Splits a SQL file into executable statements on `;`.
    ///
    /// A `;` only terminates a statement outside of: dollar-quoted strings
    /// (`$$...$$`, `$tag$...$tag$`) for PL/pgSQL bodies, single-quoted literals
    /// (including the `''` escape), and `--` line comments. Getting any of those
    /// wrong hands PostgreSQL a fragment, and the server dies at startup with a
    /// syntax error pointing at the fragment rather than at the real cause.
    ///
    /// Known gaps, deliberately not handled because no migration uses them:
    /// `/* ... */` block comments and `E'...\'...'` escape-string literals. A
    /// migration containing either will split wrongly — add handling here before
    /// writing one, do not discover it at startup.
    ///
    /// `internal`, not `private`, so the three cases can be tested directly —
    /// a migration that fails to parse means the server does not boot.
    func splitSQL(_ sql: String) -> [String] {
        var statements: [String] = []
        var current = ""
        var dollarTag: String? = nil  // non-nil while inside a dollar-quoted string
        var inSingleQuote = false     // true while inside a '...' literal
        let chars = Array(sql)
        var i = 0

        while i < chars.count {
            if inSingleQuote {
                // Inside a literal nothing is punctuation: not ";", and not "--".
                // Without this, 'a--b' would start a comment that swallows the
                // rest of the line including the statement terminator.
                // '' is an escaped quote, so it does not close the literal.
                if chars[i] == "'" {
                    if i + 1 < chars.count && chars[i + 1] == "'" {
                        current.append("''"); i += 2
                    } else {
                        current.append("'"); i += 1; inSingleQuote = false
                    }
                } else {
                    current.append(chars[i]); i += 1
                }
            } else if chars[i] == "'", dollarTag == nil {
                current.append("'"); i += 1; inSingleQuote = true
            } else if let tag = dollarTag {
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
            } else if chars[i] == "-", i + 1 < chars.count, chars[i + 1] == "-" {
                // A "--" line comment runs to end of line. Copy it through
                // without inspecting it: a ";" inside a comment is not a
                // statement terminator, and splitting there produces a fragment
                // that fails at startup with a bare syntax error.
                // (cleanStatement still drops whole comment lines afterwards.)
                while i < chars.count && chars[i] != "\n" {
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
