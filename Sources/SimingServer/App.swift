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
        let config = SimingConfig.load()

        var logger = Logger(label: "siming")
        logger.logLevel = Logger.Level(configString: config.logLevel)

        let registry = PrometheusCollectorRegistry()
        MetricsSystem.bootstrap(PrometheusMetricsFactory(registry: registry))

        // Wire configurable base URL for Location / Content-Location headers.
        configuredServerBaseURL = config.serverBaseURL

        var dbConfig = try DatabaseConfiguration.fromEnvironment()
        dbConfig.poolMin = config.dbPoolMin
        dbConfig.poolMax = config.dbPoolMax
        let postgresClient = PostgresClient(
            configuration: dbConfig.postgresClientConfiguration,
            backgroundLogger: logger
        )

        let migrationRunner = MigrationRunner(
            client: postgresClient,
            logger: logger,
            migrationsPath: config.dbMigrationsPath
        )

        let stores = StoreContainer(client: postgresClient, logger: logger)
        let smartConfig = try await SmartConfiguration.fromEnvironment(logger: logger)
        let rateLimitConfig = RateLimitConfiguration.from(config: config, logger: logger)

        let router = buildRouter(
            stores: stores,
            registry: registry,
            logger: logger,
            config: config,
            smartConfig: smartConfig,
            rateLimitConfig: rateLimitConfig
        )

        let app = Application(
            router: router,
            configuration: .init(address: .hostname("0.0.0.0", port: config.serverPort)),
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
