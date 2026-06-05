import Foundation
import Logging
import ModelsR4
import PostgresNIO
@testable import SimingCore
import XCTest

/// Shared PostgreSQL connection for the integration test process.
/// Set up once; migrations run on first setUp(). Truncate between tests.
actor TestDatabase {
    static let shared = TestDatabase()

    private(set) var isAvailable = false
    private var _client: PostgresClient?
    let logger = Logger(label: "siming.test")

    // Initialise once; subsequent calls are no-ops.
    func setUp() async throws {
        guard _client == nil else { return }
        let env = ProcessInfo.processInfo.environment
        guard env["PGHOST"] != nil || env["DATABASE_URL"] != nil else { return }

        let config = try DatabaseConfiguration.fromEnvironment()
        let c = PostgresClient(
            configuration: config.postgresClientConfiguration,
            backgroundLogger: logger
        )
        _client = c
        // run() drives the connection pool — keep it alive for the whole process.
        Swift.Task { await c.run() }

        let migrationsPath = env["MIGRATIONS_PATH"] ?? "migrations"
        let runner = MigrationRunner(client: c, logger: logger, migrationsPath: migrationsPath)
        try await runner.run()
        isAvailable = true
    }

    func makePatientStore() throws -> PatientStore {
        PatientStore(client: try requiredClient(), logger: logger)
    }

    func makeObservationStore() throws -> ObservationStore {
        ObservationStore(client: try requiredClient(), logger: logger)
    }

    func truncate() async throws {
        let c = try requiredClient()
        try await c.withConnection { conn in
            _ = try await conn.query(
                "TRUNCATE resources, idx_token, idx_string, idx_date, idx_reference, idx_quantity",
                logger: logger
            )
        }
    }

    private func requiredClient() throws -> PostgresClient {
        guard let c = _client else { throw TestDatabaseError.notInitialised }
        return c
    }
}

enum TestDatabaseError: Error { case notInitialised }

// ── Helpers used in every test class ─────────────────────────────────────────

/// Call at the start of every setUp() async throws.
/// Skips the test (not fails) when no DB is configured.
func requireDatabase() async throws {
    try await TestDatabase.shared.setUp()
    guard await TestDatabase.shared.isAvailable else {
        throw XCTSkip("Integration tests require PostgreSQL — set PGHOST or DATABASE_URL")
    }
    try await TestDatabase.shared.truncate()
}

func makePatient(family: String, given: String = "Test", birthYear: Int? = nil) throws -> Patient {
    var json = #"{"resourceType":"Patient","name":[{"family":"\#(family)","given":["\#(given)"]}]"#
    if let year = birthYear { json += #","birthDate":"\#(year)-01-01""# }
    json += "}"
    return try JSONDecoder().decode(Patient.self, from: Data(json.utf8))
}

func makeObservation(subjectId: String, code: String = "29463-7") throws -> Observation {
    let json = #"""
    {"resourceType":"Observation","status":"final",
     "code":{"coding":[{"system":"http://loinc.org","code":"\#(code)"}]},
     "subject":{"reference":"Patient/\#(subjectId)"}}
    """#
    return try JSONDecoder().decode(Observation.self, from: Data(json.utf8))
}
