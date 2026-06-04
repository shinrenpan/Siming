import Testing
import Foundation
@testable import SimingCore

// ── DatabaseConfiguration ─────────────────────────────────────────────────────

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

// ── JSONPassthrough ───────────────────────────────────────────────────────────

@Suite("JSONPassthrough")
struct JSONPassthroughTests {

    // injectMeta

    @Test("injectMeta produces valid JSON with meta fields")
    func injectMetaValid() throws {
        let content = #"{"resourceType":"Patient","id":"abc-123"}"#
        let date = Date(timeIntervalSince1970: 0)
        let result = injectMeta(into: content, versionId: 5, lastUpdated: date)
        let json = try #require(try JSONSerialization.jsonObject(with: result) as? [String: Any])
        #expect(json["resourceType"] as? String == "Patient")
        #expect(json["id"] as? String == "abc-123")
        let meta = try #require(json["meta"] as? [String: Any])
        #expect(meta["versionId"] as? String == "5")
        #expect((meta["lastUpdated"] as? String)?.hasPrefix("1970") == true)
    }

    @Test("injectMeta result is valid UTF-8 terminated with }")
    func injectMetaTermination() {
        let content = #"{"id":"x"}"#
        let result = injectMeta(into: content, versionId: 1, lastUpdated: Date())
        #expect(result.last == UInt8(ascii: "}"))
        #expect(String(data: result, encoding: .utf8) != nil)
    }

    // buildBundleJSON

    @Test("buildBundleJSON empty entries")
    func bundleEmpty() throws {
        let data = buildBundleJSON(entries: [], total: 0, selfURL: "http://localhost/Patient", nextURL: nil)
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(json["resourceType"] as? String == "Bundle")
        #expect(json["type"] as? String == "searchset")
        #expect(json["total"] as? Int == 0)
        #expect(json["entry"] == nil)
    }

    @Test("buildBundleJSON single entry")
    func bundleSingleEntry() throws {
        let resource = Data(#"{"resourceType":"Patient","id":"p1"}"#.utf8)
        let data = buildBundleJSON(
            entries: [(fullUrl: "/Patient/p1", json: resource)],
            total: 1, selfURL: "http://localhost/Patient", nextURL: nil)
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(json["total"] as? Int == 1)
        let entries = try #require(json["entry"] as? [[String: Any]])
        #expect(entries.count == 1)
        #expect(entries[0]["fullUrl"] as? String == "/Patient/p1")
        let res = try #require(entries[0]["resource"] as? [String: Any])
        #expect(res["resourceType"] as? String == "Patient")
    }

    @Test("buildBundleJSON includes next link when nextURL provided")
    func bundleNextLink() throws {
        let data = buildBundleJSON(entries: [], total: 100, selfURL: "http://localhost/Patient",
                                   nextURL: "http://localhost/Patient?_cursor=abc")
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let links = try #require(json["link"] as? [[String: Any]])
        let relations = links.compactMap { $0["relation"] as? String }
        #expect(relations.contains("self"))
        #expect(relations.contains("next"))
    }

    @Test("buildBundleJSON escapes special characters in URLs")
    func bundleURLEscaping() throws {
        let data = buildBundleJSON(entries: [], total: 0,
                                   selfURL: #"http://example.com/Patient?name=O\"Brien"#,
                                   nextURL: nil)
        // Must parse as valid JSON
        #expect(throws: Never.self) {
            _ = try JSONSerialization.jsonObject(with: data)
        }
    }

    // buildHistoryBundleJSON

    @Test("buildHistoryBundleJSON produces type=history bundle")
    func historyBundleType() throws {
        let entry = HistoryRawEntry(versionId: 1, lastUpdated: Date(timeIntervalSince1970: 0),
                                    jsonData: Data(#"{"resourceType":"Patient","id":"p1"}"#.utf8),
                                    deleted: false)
        let data = buildHistoryBundleJSON(entries: [entry], resourceType: "Patient", id: "p1",
                                          baseURL: "http://localhost")
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(json["type"] as? String == "history")
        #expect(json["total"] as? Int == 1)
    }

    @Test("buildHistoryBundleJSON first version uses POST method")
    func historyFirstVersionPOST() throws {
        let entry = HistoryRawEntry(versionId: 1, lastUpdated: Date(),
                                    jsonData: Data(#"{"resourceType":"Patient"}"#.utf8), deleted: false)
        let data = buildHistoryBundleJSON(entries: [entry], resourceType: "Patient", id: "x",
                                          baseURL: "http://localhost")
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let entries = try #require(json["entry"] as? [[String: Any]])
        let req = try #require(entries[0]["request"] as? [String: Any])
        #expect(req["method"] as? String == "POST")
    }

    @Test("buildHistoryBundleJSON delete marker uses DELETE, no resource")
    func historyDeleteMarker() throws {
        let entry = HistoryRawEntry(versionId: 3, lastUpdated: Date(), jsonData: nil, deleted: true)
        let data = buildHistoryBundleJSON(entries: [entry], resourceType: "Patient", id: "x",
                                          baseURL: "http://localhost")
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let entries = try #require(json["entry"] as? [[String: Any]])
        let req = try #require(entries[0]["request"] as? [String: Any])
        #expect(req["method"] as? String == "DELETE")
        #expect(entries[0]["resource"] == nil)
    }

    @Test("buildHistoryBundleJSON subsequent versions use PUT method")
    func historySubsequentVersionPUT() throws {
        let entry = HistoryRawEntry(versionId: 2, lastUpdated: Date(),
                                    jsonData: Data(#"{"resourceType":"Patient"}"#.utf8), deleted: false)
        let data = buildHistoryBundleJSON(entries: [entry], resourceType: "Patient", id: "x",
                                          baseURL: "http://localhost")
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let entries = try #require(json["entry"] as? [[String: Any]])
        let req = try #require(entries[0]["request"] as? [String: Any])
        #expect(req["method"] as? String == "PUT")
    }

    // httpDate / parseHTTPDate roundtrip

    @Test("httpDate and parseHTTPDate roundtrip within one second")
    func httpDateRoundtrip() throws {
        let date = Date(timeIntervalSince1970: 1_717_545_600)
        let formatted = httpDate(date)
        let parsed = try #require(parseHTTPDate(formatted))
        #expect(abs(parsed.timeIntervalSince1970 - date.timeIntervalSince1970) < 1.0)
    }

    @Test("parseHTTPDate returns nil for invalid input")
    func parseHTTPDateInvalid() {
        #expect(parseHTTPDate("not-a-date") == nil)
        #expect(parseHTTPDate("") == nil)
    }
}

// ── PatientSearchQuery ────────────────────────────────────────────────────────

@Suite("PatientSearchQuery")
struct PatientSearchQueryTests {

    // SortOrder

    @Test("SortOrder ascending")
    func sortAscending() {
        #expect(PatientSearchQuery.SortOrder.parse("_lastUpdated") == .lastUpdatedAscending)
    }

    @Test("SortOrder descending")
    func sortDescending() {
        #expect(PatientSearchQuery.SortOrder.parse("-_lastUpdated") == .lastUpdatedDescending)
    }

    @Test("SortOrder unknown defaults to descending")
    func sortUnknown() {
        #expect(PatientSearchQuery.SortOrder.parse("name") == .lastUpdatedDescending)
        #expect(PatientSearchQuery.SortOrder.parse("") == .lastUpdatedDescending)
    }

    // IdentifierParam

    @Test("IdentifierParam bare code → any system")
    func identifierBareCode() {
        let p = PatientSearchQuery.IdentifierParam.parse("MRN-001")
        #expect(p.code == "MRN-001")
        guard case .any = p.systemFilter else {
            Issue.record("Expected .any system filter")
            return
        }
    }

    @Test("IdentifierParam system|code → specific system")
    func identifierSystemAndCode() {
        let p = PatientSearchQuery.IdentifierParam.parse("http://example.org|MRN-001")
        #expect(p.code == "MRN-001")
        guard case .specific(let sys) = p.systemFilter else {
            Issue.record("Expected .specific system filter")
            return
        }
        #expect(sys == "http://example.org")
    }

    @Test("IdentifierParam |code → null system")
    func identifierNullSystem() {
        let p = PatientSearchQuery.IdentifierParam.parse("|MRN-001")
        #expect(p.code == "MRN-001")
        guard case .specific(nil) = p.systemFilter else {
            Issue.record("Expected .specific(nil) system filter")
            return
        }
    }

    // BirthdateParam

    @Test("BirthdateParam full date YYYY-MM-DD defaults to eq")
    func birthdateFullDate() throws {
        let p = try #require(PatientSearchQuery.BirthdateParam.parse("1990-06-15"))
        #expect(p.prefix == .eq)
        var dc = DateComponents()
        dc.year = 1990; dc.month = 6; dc.day = 15; dc.hour = 12
        dc.timeZone = TimeZone(secondsFromGMT: 0)
        let expected = Calendar(identifier: .gregorian).date(from: dc)!
        #expect(p.date == expected)
    }

    @Test("BirthdateParam YYYY-MM uses midnight of 1st")
    func birthdateYearMonth() throws {
        let p = try #require(PatientSearchQuery.BirthdateParam.parse("2000-03"))
        #expect(p.prefix == .eq)
        var dc = DateComponents()
        dc.year = 2000; dc.month = 3; dc.day = 1; dc.hour = 0
        dc.timeZone = TimeZone(secondsFromGMT: 0)
        let expected = Calendar(identifier: .gregorian).date(from: dc)!
        #expect(p.date == expected)
    }

    @Test("BirthdateParam YYYY uses midnight Jan 1")
    func birthdateYearOnly() throws {
        let p = try #require(PatientSearchQuery.BirthdateParam.parse("1985"))
        #expect(p.prefix == .eq)
        var dc = DateComponents()
        dc.year = 1985; dc.month = 1; dc.day = 1; dc.hour = 0
        dc.timeZone = TimeZone(secondsFromGMT: 0)
        let expected = Calendar(identifier: .gregorian).date(from: dc)!
        #expect(p.date == expected)
    }

    @Test("BirthdateParam ge prefix")
    func birthdateGEPrefix() throws {
        let p = try #require(PatientSearchQuery.BirthdateParam.parse("ge1990-01-01"))
        #expect(p.prefix == .ge)
    }

    @Test("BirthdateParam lt prefix")
    func birthdateLTPrefix() throws {
        let p = try #require(PatientSearchQuery.BirthdateParam.parse("lt2000-12-31"))
        #expect(p.prefix == .lt)
    }

    @Test("BirthdateParam invalid returns nil")
    func birthdateInvalid() {
        #expect(PatientSearchQuery.BirthdateParam.parse("invalid") == nil)
        #expect(PatientSearchQuery.BirthdateParam.parse("ge") == nil)
        #expect(PatientSearchQuery.BirthdateParam.parse("ge99-99-99") == nil)
    }

    // SearchCursor

    @Test("SearchCursor encodes and decodes symmetrically")
    func cursorRoundtrip() throws {
        let date = Date(timeIntervalSince1970: 1_717_545_600.5)
        let original = PatientSearchQuery.SearchCursor(lastUpdated: date, id: "abc-123-def", descending: true)
        let encoded = original.encode()
        let decoded = try #require(PatientSearchQuery.SearchCursor.decode(encoded))
        #expect(abs(decoded.lastUpdated.timeIntervalSince1970 - date.timeIntervalSince1970) < 0.001)
        #expect(decoded.id == "abc-123-def")
        #expect(decoded.descending == true)
    }

    @Test("SearchCursor ascending flag preserved")
    func cursorAscendingFlag() throws {
        let cursor = PatientSearchQuery.SearchCursor(lastUpdated: Date(), id: "x", descending: false)
        let decoded = try #require(PatientSearchQuery.SearchCursor.decode(cursor.encode()))
        #expect(decoded.descending == false)
    }

    @Test("SearchCursor invalid input returns nil")
    func cursorInvalidDecode() {
        #expect(PatientSearchQuery.SearchCursor.decode("!!!") == nil)
        #expect(PatientSearchQuery.SearchCursor.decode("") == nil)
        #expect(PatientSearchQuery.SearchCursor.decode("bm90dmFsaWQ=") == nil) // "notvalid"
    }
}

// ── ObservationSearchQuery ────────────────────────────────────────────────────

@Suite("ObservationSearchQuery")
struct ObservationSearchQueryTests {

    @Test("TokenParam bare code")
    func tokenBareCode() {
        let p = ObservationSearchQuery.TokenParam.parse("final")
        #expect(p.code == "final")
        #expect(p.system == nil)
    }

    @Test("TokenParam system|code")
    func tokenSystemAndCode() {
        let p = ObservationSearchQuery.TokenParam.parse("http://loinc.org|29463-7")
        #expect(p.code == "29463-7")
        #expect(p.system == "http://loinc.org")
    }

    @Test("TokenParam |code yields nil system")
    func tokenNullSystem() {
        let p = ObservationSearchQuery.TokenParam.parse("|8867-4")
        #expect(p.code == "8867-4")
        #expect(p.system == nil)
    }

    @Test("DateParam reuses BirthdateParam logic")
    func dateParamGEPrefix() throws {
        let p = try #require(ObservationSearchQuery.DateParam.parse("ge2024-01-01"))
        #expect(p.prefix == .ge)
    }
}
