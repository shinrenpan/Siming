import Foundation
import Hummingbird
import Logging
import Metrics
import PostgresNIO
import Prometheus
import SimingCore

@main
struct SimingApp {
    static func main() async throws {
        var logger = Logger(label: "siming")
        logger.logLevel = .info

        // Bootstrap Prometheus as the global metrics backend (must happen before any metric is created).
        let registry = PrometheusCollectorRegistry()
        MetricsSystem.bootstrap(PrometheusMetricsFactory(registry: registry))

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

        let patientStore     = PatientStore(client: postgresClient, logger: logger)
        let observationStore = ObservationStore(client: postgresClient, logger: logger)

        let router = Router()
        router.middlewares.add(MetricsMiddleware())
        router.get("health") { _, _ in HTTPResponse.Status.ok }
        addMetadataRoutes(to: router)
        addMetricsRoute(to: router, registry: registry)
        addPatientRoutes(to: router, store: patientStore, logger: logger)
        addObservationRoutes(to: router, store: observationStore, logger: logger)

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
