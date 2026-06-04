import Foundation
import Hummingbird
import Logging
import PostgresNIO
import SimingCore

@main
struct SimingApp {
    static func main() async throws {
        var logger = Logger(label: "siming")
        logger.logLevel = .info

        let dbConfig = try DatabaseConfiguration.fromEnvironment()
        let postgresClient = PostgresClient(
            configuration: dbConfig.postgresClientConfiguration,
            backgroundLogger: logger
        )

        let migrationsPath = ProcessInfo.processInfo.environment["MIGRATIONS_PATH"] ?? "migrations"
        let migrationRunner = MigrationRunner(
            client: postgresClient,
            logger: logger,
            migrationsPath: migrationsPath
        )

        let patientStore = PatientStore(client: postgresClient, logger: logger)

        let router = Router()
        router.get("health") { _, _ in HTTPResponse.Status.ok }
        addMetadataRoutes(to: router)
        addPatientRoutes(to: router, store: patientStore, logger: logger)

        let app = Application(
            router: router,
            configuration: .init(address: .hostname("0.0.0.0", port: 8080)),
            logger: logger
        )

        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask { await postgresClient.run() }

            // Migrations run after the pool is up; connections are made on demand.
            try await migrationRunner.run()

            group.addTask { try await app.runService() }

            // First completion (normal shutdown or error) ends the group.
            do {
                try await group.next()
            } catch {
                group.cancelAll()
                throw error
            }
            group.cancelAll()
        }
    }
}
