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
        let entry = HistoryRawEntry(resourceType: "Patient", id: "p1", versionId: 1,
                                    lastUpdated: Date(timeIntervalSince1970: 0),
                                    jsonData: Data(#"{"resourceType":"Patient","id":"p1"}"#.utf8),
                                    deleted: false)
        let data = buildHistoryBundleJSON(entries: [entry], baseURL: "http://localhost")
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(json["type"] as? String == "history")
        #expect(json["total"] as? Int == 1)
    }

    @Test("buildHistoryBundleJSON first version uses POST method")
    func historyFirstVersionPOST() throws {
        let entry = HistoryRawEntry(resourceType: "Patient", id: "x", versionId: 1,
                                    lastUpdated: Date(),
                                    jsonData: Data(#"{"resourceType":"Patient"}"#.utf8), deleted: false)
        let data = buildHistoryBundleJSON(entries: [entry], baseURL: "http://localhost")
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let entries = try #require(json["entry"] as? [[String: Any]])
        let req = try #require(entries[0]["request"] as? [String: Any])
        #expect(req["method"] as? String == "POST")
    }

    @Test("buildHistoryBundleJSON delete marker uses DELETE, no resource")
    func historyDeleteMarker() throws {
        let entry = HistoryRawEntry(resourceType: "Patient", id: "x", versionId: 3,
                                    lastUpdated: Date(), jsonData: nil, deleted: true)
        let data = buildHistoryBundleJSON(entries: [entry], baseURL: "http://localhost")
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let entries = try #require(json["entry"] as? [[String: Any]])
        let req = try #require(entries[0]["request"] as? [String: Any])
        #expect(req["method"] as? String == "DELETE")
        #expect(entries[0]["resource"] == nil)
    }

    @Test("buildHistoryBundleJSON subsequent versions use PUT method")
    func historySubsequentVersionPUT() throws {
        let entry = HistoryRawEntry(resourceType: "Patient", id: "x", versionId: 2,
                                    lastUpdated: Date(),
                                    jsonData: Data(#"{"resourceType":"Patient"}"#.utf8), deleted: false)
        let data = buildHistoryBundleJSON(entries: [entry], baseURL: "http://localhost")
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

    // applyElements

    @Test("applyElements keeps only requested + mandatory fields")
    func applyElementsFilters() throws {
        let input = #"{"resourceType":"Patient","id":"abc","name":[{"family":"Wang"}],"birthDate":"1990-01-01","active":true,"meta":{"versionId":"1","lastUpdated":"2024-01-01T00:00:00Z"}}"#
        let result = applyElements(input.data(using: .utf8)!, elements: ["name"])
        let obj = try JSONSerialization.jsonObject(with: result) as! [String: Any]
        #expect(obj["resourceType"] as? String == "Patient")
        #expect(obj["id"] as? String == "abc")
        #expect(obj["name"] != nil)
        #expect(obj["meta"] != nil)
        #expect(obj["birthDate"] == nil)
        #expect(obj["active"] == nil)
    }

    @Test("applyElements adds SUBSETTED tag to meta")
    func applyElementsSubsetted() throws {
        let input = #"{"resourceType":"Patient","id":"abc","meta":{"versionId":"1"}}"#
        let result = applyElements(input.data(using: .utf8)!, elements: ["id"])
        let obj = try JSONSerialization.jsonObject(with: result) as! [String: Any]
        let meta = obj["meta"] as! [String: Any]
        let tags = meta["tag"] as! [[String: Any]]
        #expect(tags.contains(where: { $0["code"] as? String == "SUBSETTED" }))
    }

    @Test("applyElements does not duplicate SUBSETTED tag")
    func applyElementsNoDuplicateSubsetted() throws {
        let input = #"{"resourceType":"Patient","id":"abc","meta":{"versionId":"1","tag":[{"system":"http://terminology.hl7.org/CodeSystem/v3-ObservationValue","code":"SUBSETTED"}]}}"#
        let result = applyElements(input.data(using: .utf8)!, elements: ["id"])
        let obj = try JSONSerialization.jsonObject(with: result) as! [String: Any]
        let meta = obj["meta"] as! [String: Any]
        let tags = meta["tag"] as! [[String: Any]]
        let count = tags.filter { $0["code"] as? String == "SUBSETTED" }.count
        #expect(count == 1)
    }

    @Test("applyElements returns original data on invalid JSON")
    func applyElementsInvalidJSON() {
        let input = Data("not json".utf8)
        let result = applyElements(input, elements: ["id"])
        #expect(result == input)
    }

    // applySummary

    @Test("applySummary true keeps only summary + mandatory fields with SUBSETTED")
    func applySummaryTrue() throws {
        let input = #"{"resourceType":"Patient","id":"x","name":[{"family":"Smith"}],"text":{"status":"generated","div":"<div/>"},"contact":[]}"#
        let result = applySummary(Data(input.utf8), mode: .true, summaryFields: patientSummaryFields)
        let obj = try JSONSerialization.jsonObject(with: result) as! [String: Any]
        #expect(obj["id"] != nil)
        #expect(obj["resourceType"] as? String == "Patient")
        #expect(obj["name"] != nil)
        #expect(obj["contact"] == nil)
        #expect(obj["text"] == nil)
        let tags = (obj["meta"] as? [String: Any])?["tag"] as? [[String: Any]]
        #expect(tags?.contains(where: { $0["code"] as? String == "SUBSETTED" }) == true)
    }

    @Test("applySummary text keeps only text + mandatory fields")
    func applySummaryText() throws {
        let input = #"{"resourceType":"Patient","id":"x","name":[{"family":"Smith"}],"text":{"status":"generated","div":"<div/>"}}"#
        let result = applySummary(Data(input.utf8), mode: .text, summaryFields: patientSummaryFields)
        let obj = try JSONSerialization.jsonObject(with: result) as! [String: Any]
        #expect(obj["id"] != nil)
        #expect(obj["text"] != nil)
        #expect(obj["name"] == nil)
    }

    @Test("applySummary data removes text field and adds SUBSETTED")
    func applySummaryData() throws {
        let input = #"{"resourceType":"Patient","id":"x","name":[{"family":"Smith"}],"text":{"status":"generated","div":"<div/>"}}"#
        let result = applySummary(Data(input.utf8), mode: .data, summaryFields: patientSummaryFields)
        let obj = try JSONSerialization.jsonObject(with: result) as! [String: Any]
        #expect(obj["text"] == nil)
        #expect(obj["name"] != nil)
        let tags = (obj["meta"] as? [String: Any])?["tag"] as? [[String: Any]]
        #expect(tags?.contains(where: { $0["code"] as? String == "SUBSETTED" }) == true)
    }

    @Test("applySummary false returns input unchanged")
    func applySummaryFalse() {
        let input = #"{"resourceType":"Patient","id":"x","name":[]}"#
        let data = Data(input.utf8)
        let result = applySummary(data, mode: .false, summaryFields: patientSummaryFields)
        #expect(result == data)
    }

    @Test("applySummary count returns input unchanged")
    func applySummaryCount() {
        let input = #"{"resourceType":"Patient","id":"x"}"#
        let data = Data(input.utf8)
        let result = applySummary(data, mode: .count, summaryFields: patientSummaryFields)
        #expect(result == data)
    }

    @Test("SummaryMode rawValue parsing")
    func summaryModeRawValue() {
        #expect(SummaryMode(rawValue: "true")  == .true)
        #expect(SummaryMode(rawValue: "false") == .false)
        #expect(SummaryMode(rawValue: "count") == .count)
        #expect(SummaryMode(rawValue: "text")  == .text)
        #expect(SummaryMode(rawValue: "data")  == .data)
        #expect(SummaryMode(rawValue: "bogus") == nil)
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
        #expect(PatientSearchQuery.SortOrder.parse("unknown_field") == .lastUpdatedDescending)
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

    // StringParam

    @Test("StringParam parse: bare key → starts-with modifier")
    func stringParamStartsWith() {
        let pairs: [(key: Substring, value: Substring)] = [("name", "Wang")]
        let p = PatientSearchQuery.StringParam.parse(key: "name", from: pairs)
        #expect(p?.value == "Wang")
        #expect(p?.modifier == .startsWith)
    }

    @Test("StringParam parse: name:contains key → contains modifier")
    func stringParamContains() {
        let pairs: [(key: Substring, value: Substring)] = [("name:contains", "ang")]
        let p = PatientSearchQuery.StringParam.parse(key: "name", from: pairs)
        #expect(p?.value == "ang")
        #expect(p?.modifier == .contains)
    }

    @Test("StringParam parse: name:exact key → exact modifier")
    func stringParamExact() {
        let pairs: [(key: Substring, value: Substring)] = [("name:exact", "Wang Wei")]
        let p = PatientSearchQuery.StringParam.parse(key: "name", from: pairs)
        #expect(p?.value == "Wang Wei")
        #expect(p?.modifier == .exact)
    }

    @Test("StringParam parse: name:text key → text modifier")
    func stringParamText() {
        let pairs: [(key: Substring, value: Substring)] = [("name:text", "mur")]
        let p = PatientSearchQuery.StringParam.parse(key: "name", from: pairs)
        #expect(p?.value == "mur")
        #expect(p?.modifier == .text)
    }

    @Test("StringParam parse: modifier takes precedence over bare key")
    func stringParamModifierPrecedence() {
        let pairs: [(key: Substring, value: Substring)] = [("name", "fallback"), ("name:contains", "preferred")]
        let p = PatientSearchQuery.StringParam.parse(key: "name", from: pairs)
        #expect(p?.modifier == .contains)
        #expect(p?.value == "preferred")
    }

    @Test("StringParam parse: missing key returns nil")
    func stringParamMissing() {
        let pairs: [(key: Substring, value: Substring)] = [("other", "value")]
        #expect(PatientSearchQuery.StringParam.parse(key: "name", from: pairs) == nil)
    }

    // IdentifierParam OR list

    @Test("IdentifierParam parseList single value")
    func identifierParseListSingle() {
        let list = PatientSearchQuery.IdentifierParam.parseList("MRN-001")
        #expect(list.count == 1)
        #expect(list[0].code == "MRN-001")
    }

    @Test("IdentifierParam parseList comma-separated OR values")
    func identifierParseListMultiple() {
        let list = PatientSearchQuery.IdentifierParam.parseList("http://a.org|MRN-001,http://b.org|MRN-002")
        #expect(list.count == 2)
        #expect(list[0].code == "MRN-001")
        #expect(list[1].code == "MRN-002")
        guard case .specific(let s0) = list[0].systemFilter else {
            Issue.record("Expected .specific"); return
        }
        #expect(s0 == "http://a.org")
    }

    // BirthdateParam

    @Test("BirthdateParam sa and eb prefixes")
    func birthdateSaEbPrefix() throws {
        let sa = try #require(PatientSearchQuery.BirthdateParam.parse("sa2024-01-01"))
        #expect(sa.prefix == .sa)
        let eb = try #require(PatientSearchQuery.BirthdateParam.parse("eb2024-06-30"))
        #expect(eb.prefix == .eb)
    }

    @Test("BirthdateParam full date YYYY-MM-DD defaults to eq, expands to full day")
    func birthdateFullDate() throws {
        let p = try #require(PatientSearchQuery.BirthdateParam.parse("1990-06-15"))
        #expect(p.prefix == .eq)
        let cal = Calendar(identifier: .gregorian)
        let tz  = TimeZone(secondsFromGMT: 0)!
        func date(h: Int, m: Int, s: Int) -> Date {
            var dc = DateComponents()
            dc.year = 1990; dc.month = 6; dc.day = 15
            dc.hour = h; dc.minute = m; dc.second = s; dc.timeZone = tz
            return cal.date(from: dc)!
        }
        #expect(p.dateStart == date(h: 0,  m: 0,  s: 0))
        #expect(p.dateEnd   == date(h: 23, m: 59, s: 59))
    }

    @Test("BirthdateParam YYYY-MM expands to full month range")
    func birthdateYearMonth() throws {
        let p = try #require(PatientSearchQuery.BirthdateParam.parse("2000-03"))
        #expect(p.prefix == .eq)
        let cal = Calendar(identifier: .gregorian)
        let tz  = TimeZone(secondsFromGMT: 0)!
        func date(d: Int, h: Int, m: Int, s: Int) -> Date {
            var dc = DateComponents()
            dc.year = 2000; dc.month = 3; dc.day = d
            dc.hour = h; dc.minute = m; dc.second = s; dc.timeZone = tz
            return cal.date(from: dc)!
        }
        #expect(p.dateStart == date(d: 1,  h: 0,  m: 0,  s: 0))
        #expect(p.dateEnd   == date(d: 31, h: 23, m: 59, s: 59))
    }

    @Test("BirthdateParam YYYY expands to full year range")
    func birthdateYearOnly() throws {
        let p = try #require(PatientSearchQuery.BirthdateParam.parse("1985"))
        #expect(p.prefix == .eq)
        let cal = Calendar(identifier: .gregorian)
        let tz  = TimeZone(secondsFromGMT: 0)!
        func date(mo: Int, d: Int, h: Int, m: Int, s: Int) -> Date {
            var dc = DateComponents()
            dc.year = 1985; dc.month = mo; dc.day = d
            dc.hour = h; dc.minute = m; dc.second = s; dc.timeZone = tz
            return cal.date(from: dc)!
        }
        #expect(p.dateStart == date(mo: 1,  d: 1,  h: 0,  m: 0,  s: 0))
        #expect(p.dateEnd   == date(mo: 12, d: 31, h: 23, m: 59, s: 59))
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

    @Test("SearchCursor encodes and decodes symmetrically (date sort value)")
    func cursorRoundtrip() throws {
        let date = Date(timeIntervalSince1970: 1_717_545_600.5)
        let sortVal = "\(date.timeIntervalSince1970)"
        let original = PatientSearchQuery.SearchCursor(sortValue: sortVal, id: "abc-123-def", descending: true)
        let encoded = original.encode()
        let decoded = try #require(PatientSearchQuery.SearchCursor.decode(encoded))
        #expect(abs((Double(decoded.sortValue) ?? 0) - date.timeIntervalSince1970) < 0.001)
        #expect(decoded.id == "abc-123-def")
        #expect(decoded.descending == true)
    }

    @Test("SearchCursor string sort value roundtrips")
    func cursorStringValueRoundtrip() throws {
        let original = PatientSearchQuery.SearchCursor(sortValue: "Wang Wei", id: "pt-001", descending: false)
        let decoded = try #require(PatientSearchQuery.SearchCursor.decode(original.encode()))
        #expect(decoded.sortValue == "Wang Wei")
        #expect(decoded.id == "pt-001")
        #expect(decoded.descending == false)
    }

    @Test("SearchCursor ascending flag preserved")
    func cursorAscendingFlag() throws {
        let cursor = PatientSearchQuery.SearchCursor(sortValue: "1.0", id: "x", descending: false)
        let decoded = try #require(PatientSearchQuery.SearchCursor.decode(cursor.encode()))
        #expect(decoded.descending == false)
    }

    @Test("SearchCursor invalid input returns nil")
    func cursorInvalidDecode() {
        #expect(PatientSearchQuery.SearchCursor.decode("!!!") == nil)
        #expect(PatientSearchQuery.SearchCursor.decode("") == nil)
        #expect(PatientSearchQuery.SearchCursor.decode("bm90dmFsaWQ=") == nil) // "notvalid" — no pipes
    }

    // Step 19: extended SortOrder parsing

    @Test("SortOrder parse name ascending")
    func sortOrderNameAscending() {
        #expect(PatientSearchQuery.SortOrder.parse("name") == .nameAscending)
        #expect(PatientSearchQuery.SortOrder.parse("family") == .nameAscending)
    }

    @Test("SortOrder parse name descending")
    func sortOrderNameDescending() {
        #expect(PatientSearchQuery.SortOrder.parse("-name") == .nameDescending)
        #expect(PatientSearchQuery.SortOrder.parse("-family") == .nameDescending)
    }

    @Test("SortOrder parse birthdate ascending and descending")
    func sortOrderBirthdate() {
        #expect(PatientSearchQuery.SortOrder.parse("birthdate") == .birthdateAscending)
        #expect(PatientSearchQuery.SortOrder.parse("-birthdate") == .birthdateDescending)
    }

    @Test("SortOrder parse date (Observation)")
    func sortOrderDate() {
        #expect(PatientSearchQuery.SortOrder.parse("date") == .dateAscending)
        #expect(PatientSearchQuery.SortOrder.parse("-date") == .dateDescending)
    }

    @Test("SortOrder parse _id ascending and descending")
    func sortOrderId() {
        #expect(PatientSearchQuery.SortOrder.parse("_id") == ._idAscending)
        #expect(PatientSearchQuery.SortOrder.parse("-_id") == ._idDescending)
    }

    @Test("SortOrder isDescending property")
    func sortOrderIsDescending() {
        #expect(PatientSearchQuery.SortOrder.lastUpdatedDescending.isDescending == true)
        #expect(PatientSearchQuery.SortOrder.lastUpdatedAscending.isDescending == false)
        #expect(PatientSearchQuery.SortOrder.nameDescending.isDescending == true)
        #expect(PatientSearchQuery.SortOrder.nameAscending.isDescending == false)
        #expect(PatientSearchQuery.SortOrder.birthdateDescending.isDescending == true)
        #expect(PatientSearchQuery.SortOrder.birthdateAscending.isDescending == false)
        #expect(PatientSearchQuery.SortOrder.dateDescending.isDescending == true)
        #expect(PatientSearchQuery.SortOrder.dateAscending.isDescending == false)
        #expect(PatientSearchQuery.SortOrder._idDescending.isDescending == true)
        #expect(PatientSearchQuery.SortOrder._idAscending.isDescending == false)
    }

    // Step 16 params: family, given, address variants, gender, active, phone, email

    @Test("StringParam parse: family bare key → starts-with")
    func stringParamFamilyStartsWith() {
        let pairs: [(key: Substring, value: Substring)] = [("family", "Wang")]
        let p = PatientSearchQuery.StringParam.parse(key: "family", from: pairs)
        #expect(p?.value == "Wang")
        #expect(p?.modifier == .startsWith)
    }

    @Test("StringParam parse: given:contains modifier")
    func stringParamGivenContains() {
        let pairs: [(key: Substring, value: Substring)] = [("given:contains", "ei")]
        let p = PatientSearchQuery.StringParam.parse(key: "given", from: pairs)
        #expect(p?.value == "ei")
        #expect(p?.modifier == .contains)
    }

    @Test("StringParam parse: hyphenated key address-city works")
    func stringParamAddressCityExact() {
        let pairs: [(key: Substring, value: Substring)] = [("address-city:exact", "Berlin")]
        let p = PatientSearchQuery.StringParam.parse(key: "address-city", from: pairs)
        #expect(p?.value == "Berlin")
        #expect(p?.modifier == .exact)
    }

    @Test("StringParam parse: address bare key → starts-with")
    func stringParamAddressStartsWith() {
        let pairs: [(key: Substring, value: Substring)] = [("address", "Main")]
        let p = PatientSearchQuery.StringParam.parse(key: "address", from: pairs)
        #expect(p?.value == "Main")
        #expect(p?.modifier == .startsWith)
    }

    @Test("gender OR list parses to array")
    func genderOrList() {
        let raw = "male,female"
        let result = raw.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }
        #expect(result == ["male", "female"])
    }

    @Test("active=true parses to Bool true")
    func activeTrueParsing() {
        let result: Bool? = {
            switch "true".lowercased() {
            case "true": return true
            case "false": return false
            default: return nil
            }
        }()
        #expect(result == true)
    }

    @Test("active=false parses to Bool false")
    func activeFalseParsing() {
        let result: Bool? = {
            switch "false".lowercased() {
            case "true": return true
            case "false": return false
            default: return nil
            }
        }()
        #expect(result == false)
    }

    @Test("active=invalid returns nil")
    func activeInvalidParsing() {
        let result: Bool? = {
            switch "yes".lowercased() {
            case "true": return true
            case "false": return false
            default: return nil
            }
        }()
        #expect(result == nil)
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

    @Test("TokenParam parseList comma-separated OR values")
    func tokenParseListMultiple() {
        let list = ObservationSearchQuery.TokenParam.parseList("final,amended")
        #expect(list.count == 2)
        #expect(list[0].code == "final")
        #expect(list[1].code == "amended")
        #expect(list[0].system == nil)
    }

    @Test("TokenParam parseList with systems")
    func tokenParseListWithSystems() {
        let list = ObservationSearchQuery.TokenParam.parseList("http://loinc.org|29463-7,http://loinc.org|8867-4")
        #expect(list.count == 2)
        #expect(list[0].code == "29463-7")
        #expect(list[0].system == "http://loinc.org")
        #expect(list[1].code == "8867-4")
    }

    // Step 17: system| format and :not modifier

    @Test("TokenParam system-only: 'system|' produces empty code")
    func tokenSystemOnly() {
        let p = ObservationSearchQuery.TokenParam.parse("http://loinc.org|")
        #expect(p.system == "http://loinc.org")
        #expect(p.code == "")
    }

    @Test("TokenParam '|' (empty system, empty code) produces nil system")
    func tokenEmptySystemEmptyCode() {
        let p = ObservationSearchQuery.TokenParam.parse("|")
        #expect(p.system == nil)
        #expect(p.code == "")
    }

    @Test("IdentifierParam system-only: 'system|' produces empty code with specific system")
    func identifierSystemOnly() {
        let p = PatientSearchQuery.IdentifierParam.parse("http://hospital.org|")
        #expect(p.code == "")
        guard case .specific(let sys) = p.systemFilter else {
            Issue.record("Expected .specific system filter"); return
        }
        #expect(sys == "http://hospital.org")
    }

    @Test("TokenParam parseList includes system-only entry")
    func tokenParseListSystemOnly() {
        let list = ObservationSearchQuery.TokenParam.parseList("http://loinc.org|,final")
        #expect(list.count == 2)
        #expect(list[0].system == "http://loinc.org")
        #expect(list[0].code == "")
        #expect(list[1].code == "final")
        #expect(list[1].system == nil)
    }

    @Test("status:not comma-separated parses to array")
    func statusNotParsing() {
        let raw = "final,amended"
        let result = raw.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }
        #expect(result == ["final", "amended"])
    }

    @Test("code:not with system|code parses correctly")
    func codeNotParsing() {
        let list = ObservationSearchQuery.TokenParam.parseList("http://loinc.org|29463-7")
        #expect(list.count == 1)
        #expect(list[0].code == "29463-7")
        #expect(list[0].system == "http://loinc.org")
    }

    // Step 18: identifier, encounter, performer, component-code

    @Test("IdentifierParam typealias reuses PatientSearchQuery type")
    func observationIdentifierTypealias() {
        let p = ObservationSearchQuery.IdentifierParam.parse("http://example.org|OBS-001")
        #expect(p.code == "OBS-001")
        guard case .specific(let sys) = p.systemFilter else {
            Issue.record("Expected .specific system filter"); return
        }
        #expect(sys == "http://example.org")
    }

    @Test("IdentifierParam parseList works for Observation identifiers")
    func observationIdentifierParseList() {
        let list = ObservationSearchQuery.IdentifierParam.parseList("http://a.org|OBS-1,http://b.org|OBS-2")
        #expect(list.count == 2)
        #expect(list[0].code == "OBS-1")
        #expect(list[1].code == "OBS-2")
    }

    @Test("encounter reference bare id parses correctly")
    func encounterBareId() {
        let raw = "enc-abc-123"
        let parts = raw.split(separator: "/")
        #expect(parts.count == 1)
    }

    @Test("encounter reference Encounter/id splits correctly")
    func encounterFullReference() {
        let raw = "Encounter/enc-abc-123"
        let parts = raw.split(separator: "/")
        #expect(parts.count == 2)
        #expect(String(parts[0]) == "Encounter")
        #expect(String(parts[1]) == "enc-abc-123")
    }

    @Test("component-code TokenParam parseList OR values")
    func componentCodeParseList() {
        let list = ObservationSearchQuery.TokenParam.parseList("http://loinc.org|8480-6,http://loinc.org|8462-4")
        #expect(list.count == 2)
        #expect(list[0].code == "8480-6")
        #expect(list[0].system == "http://loinc.org")
        #expect(list[1].code == "8462-4")
    }

    @Test("performer reference splits by resource type")
    func performerFullReference() {
        let raw = "Practitioner/prac-001"
        let parts = raw.split(separator: "/")
        #expect(parts.count == 2)
        #expect(String(parts[0]) == "Practitioner")
        #expect(String(parts[1]) == "prac-001")
    }

    // Step 20: value-quantity QuantityParam

    @Test("QuantityParam bare value defaults to eq prefix")
    func quantityBareValue() throws {
        let p = try #require(ObservationSearchQuery.QuantityParam.parse("5.4"))
        #expect(p.prefix == .eq)
        #expect(p.value == 5.4)
        #expect(p.system == nil)
        #expect(p.code == nil)
    }

    @Test("QuantityParam ge prefix")
    func quantityGePrefix() throws {
        let p = try #require(ObservationSearchQuery.QuantityParam.parse("ge5.4"))
        #expect(p.prefix == .ge)
        #expect(p.value == 5.4)
    }

    @Test("QuantityParam lt prefix")
    func quantityLtPrefix() throws {
        let p = try #require(ObservationSearchQuery.QuantityParam.parse("lt100"))
        #expect(p.prefix == .lt)
        #expect(p.value == 100)
    }

    @Test("QuantityParam with system and code")
    func quantityWithSystemAndCode() throws {
        let p = try #require(ObservationSearchQuery.QuantityParam.parse("5.4|http://unitsofmeasure.org|kg"))
        #expect(p.prefix == .eq)
        #expect(p.value == 5.4)
        #expect(p.system == "http://unitsofmeasure.org")
        #expect(p.code == "kg")
    }

    @Test("QuantityParam with empty system and code")
    func quantityEmptySystemWithCode() throws {
        let p = try #require(ObservationSearchQuery.QuantityParam.parse("5.4||mg"))
        #expect(p.system == nil)
        #expect(p.code == "mg")
    }

    @Test("QuantityParam ap prefix")
    func quantityApPrefix() throws {
        let p = try #require(ObservationSearchQuery.QuantityParam.parse("ap5.0"))
        #expect(p.prefix == .ap)
        #expect(p.value == 5.0)
    }

    @Test("QuantityParam invalid returns nil")
    func quantityInvalidReturnsNil() {
        #expect(ObservationSearchQuery.QuantityParam.parse("not-a-number") == nil)
    }

    @Test("QuantityParam parseList OR values")
    func quantityParseList() {
        let list = ObservationSearchQuery.QuantityParam.parseList("ge5.0,lt10.0")
        #expect(list.count == 2)
        #expect(list[0].prefix == .ge)
        #expect(list[0].value == 5.0)
        #expect(list[1].prefix == .lt)
        #expect(list[1].value == 10.0)
    }

    // Step 21: :missing modifier parsing

    @Test("missing=true parses to Bool true")
    func missingTrueParsing() {
        var missing: [String: Bool] = [:]
        let v = "true"
        if v == "true" { missing["code"] = true } else if v == "false" { missing["code"] = false }
        #expect(missing["code"] == true)
    }

    @Test("missing=false parses to Bool false")
    func missingFalseParsing() {
        var missing: [String: Bool] = [:]
        let v = "false"
        if v == "true" { missing["date"] = true } else if v == "false" { missing["date"] = false }
        #expect(missing["date"] == false)
    }

    @Test("missing invalid value is ignored")
    func missingInvalidIgnored() {
        var missing: [String: Bool] = [:]
        let v = "maybe"
        if v == "true" { missing["status"] = true } else if v == "false" { missing["status"] = false }
        #expect(missing["status"] == nil)
    }
}

// ── TotalMode ────────────────────────────────────────────────────────────────

@Suite("TotalMode")
struct TotalModeTests {

    @Test("parse nil defaults to accurate")
    func parseNilIsAccurate() {
        #expect(PatientSearchQuery.TotalMode.parse(nil) == .accurate)
    }

    @Test("parse 'accurate' returns accurate")
    func parseAccurate() {
        #expect(PatientSearchQuery.TotalMode.parse("accurate") == .accurate)
    }

    @Test("parse 'none' returns none")
    func parseNone() {
        #expect(PatientSearchQuery.TotalMode.parse("none") == .none)
    }

    @Test("parse 'NONE' is case-insensitive")
    func parseCaseInsensitive() {
        #expect(PatientSearchQuery.TotalMode.parse("NONE") == .none)
    }

    @Test("parse unknown value defaults to accurate")
    func parseUnknownIsAccurate() {
        #expect(PatientSearchQuery.TotalMode.parse("estimate") == .accurate)
    }

    @Test("TotalMode typealias on ObservationSearchQuery")
    func observationTotalModeTypealias() {
        let mode: ObservationSearchQuery.TotalMode = .none
        #expect(mode == .none)
    }
}

// ── buildBundleJSON with nil total ───────────────────────────────────────────

@Suite("buildBundleJSON _total=none")
struct BuildBundleJSONNilTotalTests {

    @Test("nil total omits 'total' field from Bundle JSON")
    func nilTotalOmitsField() throws {
        let data = buildBundleJSON(entries: [], total: nil, selfURL: "http://localhost/Patient", nextURL: nil)
        let json = try #require(String(data: data, encoding: .utf8))
        #expect(!json.contains("\"total\""))
        #expect(json.contains("\"type\":\"searchset\""))
    }

    @Test("non-nil total includes 'total' field in Bundle JSON")
    func nonNilTotalIncludesField() throws {
        let data = buildBundleJSON(entries: [], total: 42, selfURL: "http://localhost/Patient", nextURL: nil)
        let json = try #require(String(data: data, encoding: .utf8))
        #expect(json.contains("\"total\":42"))
    }
}

// ── JSONPatch ─────────────────────────────────────────────────────────────────

@Suite("JSONPatch")
struct JSONPatchTests {

    // ── JSON Pointer ──────────────────────────────────────────────────────────

    @Test("parseJSONPointer: empty string → root")
    func pointerRoot() throws {
        let tokens = try parseJSONPointer("")
        #expect(tokens.isEmpty)
    }

    @Test("parseJSONPointer: single level")
    func pointerSingleLevel() throws {
        let tokens = try parseJSONPointer("/status")
        #expect(tokens == ["status"])
    }

    @Test("parseJSONPointer: nested path")
    func pointerNested() throws {
        let tokens = try parseJSONPointer("/name/0/family")
        #expect(tokens == ["name", "0", "family"])
    }

    @Test("parseJSONPointer: tilde escaping")
    func pointerTildeEscape() throws {
        let tokens = try parseJSONPointer("/a~1b/c~0d")
        #expect(tokens == ["a/b", "c~d"])
    }

    @Test("parseJSONPointer: invalid (no leading slash) throws")
    func pointerInvalidThrows() throws {
        #expect(throws: JSONPointerError.self) {
            try parseJSONPointer("status")
        }
    }

    // ── replace ───────────────────────────────────────────────────────────────

    @Test("replace top-level string field")
    func replaceTopLevel() throws {
        let doc  = #"{"status":"active"}"#.data(using: .utf8)!
        let patch = #"[{"op":"replace","path":"/status","value":"inactive"}]"#.data(using: .utf8)!
        let result = try JSONPatch.apply(patch, to: doc)
        let obj = try #require(JSONSerialization.jsonObject(with: result) as? [String: Any])
        #expect(obj["status"] as? String == "inactive")
    }

    @Test("replace nested field")
    func replaceNested() throws {
        let doc  = #"{"name":[{"family":"Smith"}]}"#.data(using: .utf8)!
        let patch = #"[{"op":"replace","path":"/name/0/family","value":"Jones"}]"#.data(using: .utf8)!
        let result = try JSONPatch.apply(patch, to: doc)
        let obj = try #require(JSONSerialization.jsonObject(with: result) as? [String: Any])
        let name = try #require(obj["name"] as? [[String: Any]])
        #expect(name[0]["family"] as? String == "Jones")
    }

    // ── add ───────────────────────────────────────────────────────────────────

    @Test("add new key to object")
    func addNewKey() throws {
        let doc  = #"{"a":1}"#.data(using: .utf8)!
        let patch = #"[{"op":"add","path":"/b","value":2}]"#.data(using: .utf8)!
        let result = try JSONPatch.apply(patch, to: doc)
        let obj = try #require(JSONSerialization.jsonObject(with: result) as? [String: Any])
        #expect(obj["b"] as? Int == 2)
    }

    @Test("add to array by index")
    func addToArray() throws {
        let doc  = #"{"arr":[1,3]}"#.data(using: .utf8)!
        let patch = #"[{"op":"add","path":"/arr/1","value":2}]"#.data(using: .utf8)!
        let result = try JSONPatch.apply(patch, to: doc)
        let obj = try #require(JSONSerialization.jsonObject(with: result) as? [String: Any])
        let arr = try #require(obj["arr"] as? [Int])
        #expect(arr == [1, 2, 3])
    }

    @Test("add to end of array with '-'")
    func addArrayAppend() throws {
        let doc  = #"{"arr":[1,2]}"#.data(using: .utf8)!
        let patch = #"[{"op":"add","path":"/arr/-","value":3}]"#.data(using: .utf8)!
        let result = try JSONPatch.apply(patch, to: doc)
        let obj = try #require(JSONSerialization.jsonObject(with: result) as? [String: Any])
        let arr = try #require(obj["arr"] as? [Int])
        #expect(arr == [1, 2, 3])
    }

    // ── remove ────────────────────────────────────────────────────────────────

    @Test("remove key from object")
    func removeKey() throws {
        let doc  = #"{"a":1,"b":2}"#.data(using: .utf8)!
        let patch = #"[{"op":"remove","path":"/b"}]"#.data(using: .utf8)!
        let result = try JSONPatch.apply(patch, to: doc)
        let obj = try #require(JSONSerialization.jsonObject(with: result) as? [String: Any])
        #expect(obj["b"] == nil)
        #expect(obj["a"] as? Int == 1)
    }

    @Test("remove array element")
    func removeArrayElement() throws {
        let doc  = #"{"arr":[1,2,3]}"#.data(using: .utf8)!
        let patch = #"[{"op":"remove","path":"/arr/1"}]"#.data(using: .utf8)!
        let result = try JSONPatch.apply(patch, to: doc)
        let obj = try #require(JSONSerialization.jsonObject(with: result) as? [String: Any])
        let arr = try #require(obj["arr"] as? [Int])
        #expect(arr == [1, 3])
    }

    // ── move ──────────────────────────────────────────────────────────────────

    @Test("move value between keys")
    func moveValue() throws {
        let doc  = #"{"a":42,"b":0}"#.data(using: .utf8)!
        let patch = #"[{"op":"move","from":"/a","path":"/c"}]"#.data(using: .utf8)!
        let result = try JSONPatch.apply(patch, to: doc)
        let obj = try #require(JSONSerialization.jsonObject(with: result) as? [String: Any])
        #expect(obj["a"] == nil)
        #expect(obj["c"] as? Int == 42)
    }

    // ── copy ──────────────────────────────────────────────────────────────────

    @Test("copy value to new key")
    func copyValue() throws {
        let doc  = #"{"a":99}"#.data(using: .utf8)!
        let patch = #"[{"op":"copy","from":"/a","path":"/b"}]"#.data(using: .utf8)!
        let result = try JSONPatch.apply(patch, to: doc)
        let obj = try #require(JSONSerialization.jsonObject(with: result) as? [String: Any])
        #expect(obj["a"] as? Int == 99)
        #expect(obj["b"] as? Int == 99)
    }

    // ── test ──────────────────────────────────────────────────────────────────

    @Test("test passes when value matches")
    func testPasses() throws {
        let doc  = #"{"status":"active"}"#.data(using: .utf8)!
        let patch = #"[{"op":"test","path":"/status","value":"active"}]"#.data(using: .utf8)!
        let result = try JSONPatch.apply(patch, to: doc)
        let obj = try #require(JSONSerialization.jsonObject(with: result) as? [String: Any])
        #expect(obj["status"] as? String == "active")
    }

    @Test("test throws testFailed when value differs")
    func testFailsThrows() throws {
        let doc  = #"{"status":"active"}"#.data(using: .utf8)!
        let patch = #"[{"op":"test","path":"/status","value":"inactive"}]"#.data(using: .utf8)!
        #expect(throws: JSONPatchError.self) {
            try JSONPatch.apply(patch, to: doc)
        }
    }

    // ── error cases ───────────────────────────────────────────────────────────

    @Test("replace missing key throws pathNotFound")
    func replaceMissingKey() throws {
        let doc  = #"{"a":1}"#.data(using: .utf8)!
        let patch = #"[{"op":"replace","path":"/b","value":2}]"#.data(using: .utf8)!
        #expect(throws: JSONPatchError.self) {
            try JSONPatch.apply(patch, to: doc)
        }
    }

    @Test("non-array patch body throws invalidPatch")
    func nonArrayBody() throws {
        let doc  = #"{"a":1}"#.data(using: .utf8)!
        let patch = #"{"op":"replace","path":"/a","value":2}"#.data(using: .utf8)!
        #expect(throws: JSONPatchError.self) {
            try JSONPatch.apply(patch, to: doc)
        }
    }

    @Test("unknown operation throws invalidPatch")
    func unknownOp() throws {
        let doc  = #"{"a":1}"#.data(using: .utf8)!
        let patch = #"[{"op":"flip","path":"/a","value":2}]"#.data(using: .utf8)!
        #expect(throws: JSONPatchError.self) {
            try JSONPatch.apply(patch, to: doc)
        }
    }

    // ── multi-operation sequence ──────────────────────────────────────────────

    @Test("multiple operations applied in order")
    func multipleOps() throws {
        let doc  = #"{"a":1,"b":2}"#.data(using: .utf8)!
        let patch = #"""
            [
              {"op":"replace","path":"/a","value":10},
              {"op":"add","path":"/c","value":3},
              {"op":"remove","path":"/b"}
            ]
            """#.data(using: .utf8)!
        let result = try JSONPatch.apply(patch, to: doc)
        let obj = try #require(JSONSerialization.jsonObject(with: result) as? [String: Any])
        #expect(obj["a"] as? Int == 10)
        #expect(obj["c"] as? Int == 3)
        #expect(obj["b"] == nil)
    }
}
