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
    public var identifierNot: [IdentifierParam]  // identifier:not modifier
    public var genderNot: [String]               // gender:not modifier
    public var identifier: [IdentifierParam]
    public var id: [String]               // _id: filter by resource id (OR)
    public var birthdate: [BirthdateParam]
    public var lastUpdated: [BirthdateParam]  // _lastUpdated: filter on last write time
    public var missing: [String: Bool]    // param:missing=true/false
    public var chains: [ChainedParam]    // chained search: refParam.childParam=value
    public var has: [HasParam]            // _has modifier: reverse chaining
    public var totalMode: TotalMode
    public var sort: SortOrder
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
        identifierNot: [IdentifierParam] = [],
        genderNot: [String] = [],
        identifier: [IdentifierParam] = [],
        id: [String] = [],
        birthdate: [BirthdateParam] = [],
        lastUpdated: [BirthdateParam] = [],
        missing: [String: Bool] = [:],
        chains: [ChainedParam] = [],
        has: [HasParam] = [],
        totalMode: TotalMode = .accurate,
        sort: SortOrder = .lastUpdatedDescending,
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
        self.phone             = phone
        self.email             = email
        self.identifierNot     = identifierNot
        self.genderNot         = genderNot
        self.identifier        = identifier
        self.id                = id
        self.birthdate         = birthdate
        self.lastUpdated       = lastUpdated
        self.missing           = missing
        self.chains            = chains
        self.has               = has
        self.totalMode         = totalMode
        self.sort              = sort
        self.count             = count
        self.cursor            = cursor
    }

    // ── String parameter ──────────────────────────────────────────────────────
    // FHIR R4 default: starts-with, case+accent insensitive.
    // :contains → substring match; :exact → case-sensitive exact match.

    public struct StringParam: Sendable {
        public enum Modifier: Sendable { case startsWith, contains, exact, text }
        public let value: String
        public let modifier: Modifier

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

    public enum SortOrder: Sendable {
        case lastUpdatedDescending   // -_lastUpdated (default)
        case lastUpdatedAscending    // _lastUpdated
        case nameAscending           // name / family → first family name from idx_string
        case nameDescending          // -name / -family
        case birthdateAscending      // birthdate → date_start from idx_date
        case birthdateDescending     // -birthdate
        case dateAscending           // date (Observation effective date)
        case dateDescending          // -date
        case statusAscending         // status / lifecycle-status → code from idx_token
        case statusDescending        // -status
        case clinicalStatusAscending // clinical-status → code from idx_token
        case clinicalStatusDescending// -clinical-status
        case codeAscending           // code / vaccine-code → code from idx_token
        case codeDescending          // -code
        case _idAscending            // _id
        case _idDescending           // -_id

        public static func parse(_ raw: String) -> SortOrder {
            switch raw.trimmingCharacters(in: .whitespaces) {
            case "_lastUpdated":          return .lastUpdatedAscending
            case "-_lastUpdated":         return .lastUpdatedDescending
            case "name", "family":        return .nameAscending
            case "-name", "-family":      return .nameDescending
            case "birthdate":             return .birthdateAscending
            case "-birthdate":            return .birthdateDescending
            case "date":                  return .dateAscending
            case "-date":                 return .dateDescending
            case "status":                return .statusAscending
            case "-status":               return .statusDescending
            case "clinical-status":       return .clinicalStatusAscending
            case "-clinical-status":      return .clinicalStatusDescending
            case "code":                  return .codeAscending
            case "-code":                 return .codeDescending
            case "_id":                   return ._idAscending
            case "-_id":                  return ._idDescending
            default:                      return .lastUpdatedDescending
            }
        }

        public var isDescending: Bool {
            switch self {
            case .lastUpdatedDescending, .nameDescending, .birthdateDescending, .dateDescending,
                 .statusDescending, .clinicalStatusDescending, .codeDescending, ._idDescending:
                return true
            default:
                return false
            }
        }
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
        }
        public let prefix: Prefix
        /// Inclusive start of the search precision range (UTC).
        public let dateStart: Date
        /// Inclusive end of the search precision range (UTC).
        public let dateEnd: Date

        // Parses "ge1990-01-01", "lt2000", "1985-06" (eq default), "sa2024-01-01", etc.
        // Partial dates expand to a full precision range per FHIR R4 §2.4.0.1:
        //   YYYY      → [Jan 1 00:00:00, Dec 31 23:59:59]
        //   YYYY-MM   → [1st 00:00:00, last-day 23:59:59]
        //   YYYY-MM-DD → [00:00:00, 23:59:59]
        public static func parse(_ raw: String) -> BirthdateParam? {
            let knownPrefixes = ["eq", "ne", "lt", "gt", "le", "ge", "sa", "eb"]
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

    // ── Pagination cursor ──────────────────────────────────────────────────────

    public struct SearchCursor: Sendable {
        /// Sort key value: epoch timestamp string for date sorts, raw string for string sorts.
        public let sortValue: String
        public let id: String
        public let descending: Bool

        // URL-safe base64: "<sortValue>|<id>|<1|0>"
        public func encode() -> String {
            let s = "\(sortValue)|\(id)|\(descending ? 1 : 0)"
            return Data(s.utf8).base64EncodedString()
                .replacingOccurrences(of: "+", with: "-")
                .replacingOccurrences(of: "/", with: "_")
                .replacingOccurrences(of: "=", with: "")
        }

        public static func decode(_ raw: String) -> SearchCursor? {
            var b64 = raw
                .replacingOccurrences(of: "-", with: "+")
                .replacingOccurrences(of: "_", with: "/")
            while b64.count % 4 != 0 { b64 += "=" }
            guard let data = Data(base64Encoded: b64),
                  let s = String(data: data, encoding: .utf8) else { return nil }
            let parts = s.split(separator: "|", maxSplits: 2)
            guard parts.count == 3 else { return nil }
            return SearchCursor(
                sortValue: String(parts[0]),
                id: String(parts[1]),
                descending: parts[2] == "1"
            )
        }
    }
}
