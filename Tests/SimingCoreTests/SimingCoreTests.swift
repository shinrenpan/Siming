import Testing
@testable import SimingCore

@Suite("DatabaseConfiguration")
struct DatabaseConfigurationTests {
    @Test("parses DATABASE_URL correctly")
    func parsesURL() throws {
        let config = try DatabaseConfiguration.fromURL("postgres://user:pass@localhost:5432/mydb")
        #expect(config.host == "localhost")
        #expect(config.port == 5432)
        #expect(config.username == "user")
        #expect(config.password == "pass")
        #expect(config.database == "mydb")
    }
}
