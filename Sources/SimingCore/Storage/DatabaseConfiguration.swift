import Foundation
import PostgresNIO

public struct DatabaseConfiguration {
    public var host: String
    public var port: Int
    public var username: String
    public var password: String
    public var database: String
    public var poolMin: Int
    public var poolMax: Int

    public init(
        host: String, port: Int,
        username: String, password: String, database: String,
        poolMin: Int = 4, poolMax: Int = 40
    ) {
        self.host     = host
        self.port     = port
        self.username = username
        self.password = password
        self.database = database
        self.poolMin  = poolMin
        self.poolMax  = poolMax
    }

    public var postgresClientConfiguration: PostgresClient.Configuration {
        var config = PostgresClient.Configuration(
            host: host,
            port: port,
            username: username,
            password: password,
            database: database,
            tls: .disable
        )
        config.options.minimumConnections = poolMin
        config.options.maximumConnections = poolMax
        return config
    }

    public static func fromEnvironment() throws -> DatabaseConfiguration {
        // Empty counts as unset, as for every other variable: `PGHOST=` in an env file
        // must not mean "connect to host ''".
        func env(_ key: String) -> String? {
            ProcessInfo.processInfo.environment[key].flatMap { $0.isEmpty ? nil : $0 }
        }
        if let urlString = env("DATABASE_URL") {
            return try parseURL(urlString)
        }
        return DatabaseConfiguration(
            host: env("PGHOST") ?? "localhost",
            port: env("PGPORT").flatMap(Int.init) ?? 5432,
            username: env("PGUSER") ?? "siming",
            password: env("PGPASSWORD") ?? "siming",
            database: env("PGDATABASE") ?? "siming"
        )
    }

    public static func fromURL(_ urlString: String) throws -> DatabaseConfiguration {
        try parseURL(urlString)
    }

    private static func parseURL(_ urlString: String) throws -> DatabaseConfiguration {
        guard let components = URLComponents(string: urlString),
              let host = components.host,
              let user = components.user
        else {
            throw DatabaseConfigurationError.invalidURL(urlString)
        }
        let rawPath = components.path
        let database = rawPath.hasPrefix("/") ? String(rawPath.dropFirst()) : rawPath
        return DatabaseConfiguration(
            host: host,
            port: components.port ?? 5432,
            username: user,
            password: components.password ?? "",
            database: database.isEmpty ? "siming" : database
        )
    }
}

public enum DatabaseConfigurationError: Error, CustomStringConvertible {
    case invalidURL(String)

    public var description: String {
        switch self {
        case .invalidURL(let url): "Invalid DATABASE_URL: \(url)"
        }
    }
}
