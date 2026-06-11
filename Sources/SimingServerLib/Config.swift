import Foundation
import Logging
import Yams

/// Server configuration loaded from config.yml, with environment variable overrides.
/// Loaded once at startup; never mutated after that.
public struct SimingConfig: Sendable {
    public var serverPort: Int
    public var serverBaseURL: String          // empty = derive from Host header
    public var fhirPackagesDir: String
    public var capabilityPublisher: String
    public var capabilityDescription: String
    public var dbMigrationsPath: String
    public var dbPoolMin: Int
    public var dbPoolMax: Int
    public var rateLimitRPS: Double?          // nil = disabled
    public var rateLimitBurst: Int?           // nil = 2 × rps
    public var logLevel: String

    // MARK: - Load

    /// Loads config from `path` (default: "config.yml" relative to CWD),
    /// then applies environment variable overrides.
    /// Missing file or unparseable YAML → all defaults, no error.
    public static func load(from path: String = "config.yml") -> SimingConfig {
        var c = SimingConfig()
        if let text = try? String(contentsOfFile: path, encoding: .utf8),
           let root = (try? Yams.load(yaml: text)) as? [String: Any] {
            c.apply(yaml: root)
        }
        c.applyEnvironment()
        return c
    }

    // MARK: - Defaults

    public init() {
        serverPort             = 8080
        serverBaseURL          = ""
        fhirPackagesDir        = "packages"
        capabilityPublisher    = "Siming"
        capabilityDescription  = "Siming FHIR R4 Server"
        dbMigrationsPath       = "migrations"
        dbPoolMin              = 4
        dbPoolMax              = 40
        rateLimitRPS           = nil
        rateLimitBurst         = nil
        logLevel               = "info"
    }

    // MARK: - YAML mapping

    private mutating func apply(yaml root: [String: Any]) {
        if let s = root["server"] as? [String: Any] {
            if let v = s["port"]    as? Int    { serverPort    = v }
            if let v = s["baseUrl"] as? String { serverBaseURL = v }
        }
        if let f = root["fhir"] as? [String: Any] {
            if let v = f["packagesDir"] as? String { fhirPackagesDir = v }
        }
        if let cap = root["capability"] as? [String: Any] {
            if let v = cap["publisher"]   as? String { capabilityPublisher   = v }
            if let v = cap["description"] as? String { capabilityDescription = v }
        }
        if let db = root["database"] as? [String: Any] {
            if let v = db["migrationsPath"] as? String { dbMigrationsPath = v }
            if let pool = db["pool"] as? [String: Any] {
                if let v = pool["min"] as? Int { dbPoolMin = v }
                if let v = pool["max"] as? Int { dbPoolMax = v }
            }
        }
        if let sec = root["security"] as? [String: Any],
           let rl  = sec["rateLimit"] as? [String: Any] {
            if let v = rl["rps"] as? Double   { rateLimitRPS = v }
            else if let v = rl["rps"] as? Int { rateLimitRPS = Double(v) }
            if let v = rl["burst"] as? Int    { rateLimitBurst = v }
        }
        if let log = root["logging"] as? [String: Any] {
            if let v = log["level"] as? String { logLevel = v }
        }
    }

    // MARK: - Environment variable overrides

    private mutating func applyEnvironment() {
        let env = ProcessInfo.processInfo.environment
        if let v = env["SERVER_PORT"].flatMap(Int.init)  { serverPort        = v }
        if let v = env["SERVER_BASE_URL"], !v.isEmpty    { serverBaseURL     = v }
        if let v = env["PACKAGES_DIR"],    !v.isEmpty    { fhirPackagesDir   = v }
        if let v = env["MIGRATIONS_PATH"], !v.isEmpty    { dbMigrationsPath  = v }
        if let v = env["DB_POOL_MIN"].flatMap(Int.init)  { dbPoolMin         = v }
        if let v = env["DB_POOL_MAX"].flatMap(Int.init)  { dbPoolMax         = v }
        if let v = env["LOG_LEVEL"],       !v.isEmpty    { logLevel          = v }
        if let rpsStr = env["RATE_LIMIT_RPS"],
           let rps = Double(rpsStr), rps > 0 {
            rateLimitRPS = rps
            if let burst = env["RATE_LIMIT_BURST"].flatMap(Int.init) { rateLimitBurst = burst }
        }
    }
}

// MARK: - Logger.Level helper

extension Logger.Level {
    /// Parse a config / env-var log level string.
    /// Accepts "trace", "debug", "info", "notice", "warn"/"warning", "error", "critical".
    public init(configString s: String) {
        switch s.lowercased() {
        case "trace":            self = .trace
        case "debug":            self = .debug
        case "notice":           self = .notice
        case "warn", "warning":  self = .warning
        case "error":            self = .error
        case "critical":         self = .critical
        default:                 self = .info
        }
    }
}
