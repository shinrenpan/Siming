import Foundation

public struct PatientSearchQuery: Sendable {
    public var name: StringParam?
    public var family: StringParam?
    public var given: StringParam?
    public var gender: [String]           // token OR: ["male","female","other","unknown"]
    public var active: Bool?              // nil = unfiltered
    public var address: StringParam?
    public var addressCity: StringParam?
    public var addressState: StringParam?
    public var addressPostalCode: StringParam?
    public var addressCountry: StringParam?
    public var phone: String?             // telecom.system=phone, exact match
    public var email: String?             // telecom.system=email, exact match
    public var organization: String?             // managingOrganization reference
    public var generalPractitioner: String?      // generalPractitioner[] reference
    public var link: String?                     // link[].other reference
    public var language: [TokenParam]            // communication.language token OR
    public var languageNot: [TokenParam]         // language:not modifier
    public var identifierNot: [IdentifierParam]  // identifier:not modifier
    public var genderNot: [String]               // gender:not modifier
    public var identifier: [IdentifierParam]
    public var meta: MetaSearchParams = MetaSearchParams()  // _tag / _security / _profile
    public var id: [String]               // _id: filter by resource id (OR)
    public var birthdate: [BirthdateParam]
    public var deceased: Bool?            // deceased token: true=deceased, false=not deceased
    public var deathDate: [BirthdateParam]   // death-date: deceasedDateTime range
    public var lastUpdated: [BirthdateParam]  // _lastUpdated: filter on last write time
    public var tokenTexts: [TokenTextParam]  // param:text=value modifier
    public var missing: [String: Bool]    // param:missing=true/false
    public var chains: [ChainedParam]    // chained search: refParam.childParam=value
    public var has: [HasParam]            // _has modifier: reverse chaining
    public var totalMode: TotalMode
    public var sortKeys: [SortKey]
    public var count: Int
    public var cursor: SearchCursor?

    public init(
        name: StringParam? = nil,
        family: StringParam? = nil,
        given: StringParam? = nil,
        gender: [String] = [],
        active: Bool? = nil,
        address: StringParam? = nil,
        addressCity: StringParam? = nil,
        addressState: StringParam? = nil,
        addressPostalCode: StringParam? = nil,
        addressCountry: StringParam? = nil,
        phone: String? = nil,
        email: String? = nil,
        organization: String? = nil,
        generalPractitioner: String? = nil,
        link: String? = nil,
        language: [TokenParam] = [],
        languageNot: [TokenParam] = [],
        identifierNot: [IdentifierParam] = [],
        genderNot: [String] = [],
        identifier: [IdentifierParam] = [],
        id: [String] = [],
        birthdate: [BirthdateParam] = [],
        deceased: Bool? = nil,
        deathDate: [BirthdateParam] = [],
        lastUpdated: [BirthdateParam] = [],
        tokenTexts: [TokenTextParam] = [],
        missing: [String: Bool] = [:],
        chains: [ChainedParam] = [],
        has: [HasParam] = [],
        totalMode: TotalMode = .accurate,
        sortKeys: [SortKey] = [.default],
        count: Int = 20,
        cursor: SearchCursor? = nil
    ) {
        self.name              = name
        self.family            = family
        self.given             = given
        self.gender            = gender
        self.active            = active
        self.address           = address
        self.addressCity       = addressCity
        self.addressState      = addressState
        self.addressPostalCode = addressPostalCode
        self.addressCountry    = addressCountry
        self.phone                = phone
        self.email                = email
        self.organization         = organization
        self.generalPractitioner  = generalPractitioner
        self.link                 = link
        self.language             = language
        self.languageNot          = languageNot
        self.identifierNot        = identifierNot
        self.genderNot         = genderNot
        self.identifier        = identifier
        self.id                = id
        self.birthdate         = birthdate
        self.deceased          = deceased
        self.deathDate         = deathDate
        self.lastUpdated       = lastUpdated
        self.tokenTexts        = tokenTexts
        self.missing           = missing
        self.chains            = chains
        self.has               = has
        self.totalMode         = totalMode
        self.sortKeys          = sortKeys
        self.count             = count
        self.cursor            = cursor
    }

    // ── Token parameter (for language, etc.) ─────────────────────────────────
    public typealias TokenParam = ObservationSearchQuery.TokenParam

    // ── String parameter ──────────────────────────────────────────────────────
    // FHIR R4 default: starts-with, case+accent insensitive.
    // :contains → substring match; :exact → case-sensitive exact match.

    public struct StringParam: Sendable {
        public enum Modifier: Sendable { case startsWith, contains, exact, text }
        public let value: String
        public let modifier: Modifier

        public init(value: String, modifier: Modifier) {
            self.value    = value
            self.modifier = modifier
        }

        // Tries key:text, key:contains, key:exact, then bare key (starts-with).
        public static func parse(key: String, from qp: some Collection<(key: Substring, value: Substring)>) -> StringParam? {
            if let v = qp.first(where: { $0.key == "\(key):text" })?.value {
                return StringParam(value: String(v), modifier: .text)
            }
            if let v = qp.first(where: { $0.key == "\(key):contains" })?.value {
                return StringParam(value: String(v), modifier: .contains)
            }
            if let v = qp.first(where: { $0.key == "\(key):exact" })?.value {
                return StringParam(value: String(v), modifier: .exact)
            }
            if let v = qp.first(where: { $0.key == Substring(key) })?.value {
                return StringParam(value: String(v), modifier: .startsWith)
            }
            return nil
        }
    }

    // ── Total mode ───────────────────────────────────────────────────────────

    public enum TotalMode: Sendable {
        case accurate   // COUNT(*) from ids — exact, default
        case estimate   // skip COUNT(*); return exact only when page is incomplete
        case none       // skip count entirely, omit Bundle.total

        public static func parse(_ raw: String?) -> TotalMode {
            switch raw?.lowercased() {
            case "none":     return .none
            case "estimate": return .estimate
            default:         return .accurate
            }
        }
    }

    // ── Sort order ────────────────────────────────────────────────────────────

    /// Parses a comma-separated `_sort` value into sort keys.
    /// Unrecognised tokens are ignored; empty result falls back to `[.default]`.
    public static func parseSortKeys(_ raw: String) -> [SortKey] {
        let keys = raw.split(separator: ",").compactMap { token -> SortKey? in
            let s = String(token).trimmingCharacters(in: .whitespaces)
            let desc = s.hasPrefix("-")
            let name = desc ? String(s.dropFirst()) : s
            let src: SortKeySource? = switch name {
            case "_lastUpdated":    .lastUpdated
            case "_id":             .resourceId
            case "name", "family":  .string(paramName: "family")
            case "birthdate":       .date(paramName: "birthdate")
            default:                nil
            }
            guard let src else { return nil }
            return SortKey(source: src, descending: desc)
        }
        return keys.isEmpty ? [.default] : keys
    }

    // ── Identifier token search ────────────────────────────────────────────────

    public struct IdentifierParam: Sendable {
        public enum SystemFilter: Sendable {
            case any                // no "|" — match any system
            case specific(String?)  // nil = NULL system; non-nil = system value
        }
        public let systemFilter: SystemFilter
        public let code: String

        // Parses "system|code", "|code" (null system), or "code" (any system)
        public static func parse(_ raw: String) -> IdentifierParam {
            guard let pipe = raw.firstIndex(of: "|") else {
                return IdentifierParam(systemFilter: .any, code: raw)
            }
            let sys = String(raw[raw.startIndex..<pipe])
            let code = String(raw[raw.index(after: pipe)...])
            return IdentifierParam(systemFilter: .specific(sys.isEmpty ? nil : sys), code: code)
        }

        // Parses comma-separated OR list: "sys|code1,sys|code2"
        public static func parseList(_ raw: String) -> [IdentifierParam] {
            raw.split(separator: ",").map { parse(String($0).trimmingCharacters(in: .whitespaces)) }
        }
    }

    // ── Birthdate / date range search ─────────────────────────────────────────

    public struct BirthdateParam: Sendable {
        public enum Prefix: String, Sendable {
            case eq, ne, lt, gt, le, ge
            case sa  // starts-after: stored period start > search range end
            case eb  // ends-before:  stored period end   < search range start
            case ap  // approximately equal: ±10% of precision period
        }
        public let prefix: Prefix
        /// Inclusive start of the search precision range (UTC).
        public let dateStart: Date
        /// Inclusive end of the search precision range (UTC).
        public let dateEnd: Date

        /// For `ap` prefix: expanded start = dateStart − 10% of precision period.
        public var apExpandedStart: Date { dateStart.addingTimeInterval(-(dateEnd.timeIntervalSince(dateStart) * 0.1)) }
        /// For `ap` prefix: expanded end = dateEnd + 10% of precision period.
        public var apExpandedEnd:   Date { dateEnd.addingTimeInterval(dateEnd.timeIntervalSince(dateStart) * 0.1) }

        // Parses "ge1990-01-01", "lt2000", "1985-06" (eq default), "sa2024-01-01", etc.
        // Partial dates expand to a full precision range per FHIR R4 §2.4.0.1:
        //   YYYY      → [Jan 1 00:00:00, Dec 31 23:59:59]
        //   YYYY-MM   → [1st 00:00:00, last-day 23:59:59]
        //   YYYY-MM-DD → [00:00:00, 23:59:59]
        public static func parse(_ raw: String) -> BirthdateParam? {
            let knownPrefixes = ["eq", "ne", "lt", "gt", "le", "ge", "sa", "eb", "ap"]
            let (pfxStr, dateStr): (String, String)
            let candidate = String(raw.prefix(2))
            if knownPrefixes.contains(candidate) {
                pfxStr = candidate
                dateStr = String(raw.dropFirst(2))
            } else {
                pfxStr = "eq"
                dateStr = raw
            }
            guard let pfx = Prefix(rawValue: pfxStr),
                  let range = parseFHIRDateRange(dateStr) else { return nil }
            return BirthdateParam(prefix: pfx, dateStart: range.start, dateEnd: range.end)
        }

        private static func parseFHIRDateRange(_ s: String) -> (start: Date, end: Date)? {
            let cal = Calendar(identifier: .gregorian)
            let tz  = TimeZone(secondsFromGMT: 0)!
            let parts = s.split(separator: "-")

            func dc(year: Int, month: Int, day: Int, hour: Int, minute: Int, second: Int) -> Date? {
                var c = DateComponents()
                c.calendar = cal; c.timeZone = tz
                c.year = year; c.month = month; c.day = day
                c.hour = hour; c.minute = minute; c.second = second
                return c.date
            }

            switch parts.count {
            case 1:
                guard let y = Int(parts[0]) else { return nil }
                guard let start = dc(year: y, month: 1,  day: 1,  hour: 0,  minute: 0, second: 0),
                      let end   = dc(year: y, month: 12, day: 31, hour: 23, minute: 59, second: 59)
                else { return nil }
                return (start, end)
            case 2:
                guard let y = Int(parts[0]), let m = Int(parts[1]),
                      (1...12).contains(m) else { return nil }
                guard let start = dc(year: y, month: m, day: 1, hour: 0, minute: 0, second: 0)
                else { return nil }
                // First of next month minus one second = last moment of this month
                let (ny, nm) = m == 12 ? (y + 1, 1) : (y, m + 1)
                guard let firstOfNext = dc(year: ny, month: nm, day: 1, hour: 0, minute: 0, second: 0)
                else { return nil }
                let end = firstOfNext.addingTimeInterval(-1)
                return (start, end)
            case 3:
                guard let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2]),
                      (1...12).contains(m), (1...31).contains(d) else { return nil }
                guard let start = dc(year: y, month: m, day: d, hour: 0, minute: 0, second: 0)
                else { return nil }
                let end = start.addingTimeInterval(86399)  // +23:59:59
                return (start, end)
            default:
                return nil
            }
        }
    }

}
// SearchCursor is the shared type defined in MultiSort.swift.
