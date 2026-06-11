import Foundation
import Hummingbird
import Logging
import Metrics
import PostgresNIO
import Prometheus
import SimingCore
import SimingServerLib

@main
struct SimingApp {
    static func main() async throws {
        var logger = Logger(label: "siming")
        logger.logLevel = .info

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

        let stores = StoreContainer(client: postgresClient, logger: logger)
        let smartConfig = try await SmartConfiguration.fromEnvironment(logger: logger)
        let rateLimitConfig = RateLimitConfiguration.fromEnvironment(logger: logger)

        let router = buildRouter(
            stores: stores,
            registry: registry,
            logger: logger,
            smartConfig: smartConfig,
            rateLimitConfig: rateLimitConfig
        )

        let app = Application(
            router: router,
            configuration: .init(address: .hostname("0.0.0.0", port: 8080)),
            logger: logger
        )

        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask { await postgresClient.run() }
            try await migrationRunner.run()
            group.addTask { try await app.runService() }
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
