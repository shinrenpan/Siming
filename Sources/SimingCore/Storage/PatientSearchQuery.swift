import Foundation

public struct PatientSearchQuery: Sendable {
    public var name: String?
    public var identifier: IdentifierParam?
    public var birthdate: [BirthdateParam]
    public var sort: SortOrder
    public var count: Int
    public var cursor: SearchCursor?

    public init(
        name: String? = nil,
        identifier: IdentifierParam? = nil,
        birthdate: [BirthdateParam] = [],
        sort: SortOrder = .lastUpdatedDescending,
        count: Int = 20,
        cursor: SearchCursor? = nil
    ) {
        self.name = name
        self.identifier = identifier
        self.birthdate = birthdate
        self.sort = sort
        self.count = count
        self.cursor = cursor
    }

    // ── Sort order ────────────────────────────────────────────────────────────

    public enum SortOrder: Sendable {
        case lastUpdatedDescending  // -_lastUpdated (default)
        case lastUpdatedAscending   // _lastUpdated

        public static func parse(_ raw: String) -> SortOrder {
            switch raw.trimmingCharacters(in: .whitespaces) {
            case "_lastUpdated":  return .lastUpdatedAscending
            case "-_lastUpdated": return .lastUpdatedDescending
            default:              return .lastUpdatedDescending
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
    }

    // ── Birthdate range search ─────────────────────────────────────────────────

    public struct BirthdateParam: Sendable {
        public enum Prefix: String, Sendable {
            case eq, ne, lt, gt, le, ge
        }
        public let prefix: Prefix
        public let date: Date

        // Parses "ge1990-01-01", "lt2000", "1985-06" (eq default), etc.
        public static func parse(_ raw: String) -> BirthdateParam? {
            let knownPrefixes = ["eq", "ne", "lt", "gt", "le", "ge"]
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
                  let date = parseFHIRDate(dateStr) else { return nil }
            return BirthdateParam(prefix: pfx, date: date)
        }

        // FHIR partial dates: YYYY → 00:00 Jan 1; YYYY-MM → 00:00 1st; YYYY-MM-DD → 12:00 UTC
        private static func parseFHIRDate(_ s: String) -> Date? {
            let parts = s.split(separator: "-")
            var dc = DateComponents()
            dc.calendar = Calendar(identifier: .gregorian)
            dc.timeZone = TimeZone(secondsFromGMT: 0)
            switch parts.count {
            case 1:
                guard let y = Int(parts[0]) else { return nil }
                dc.year = y; dc.month = 1; dc.day = 1; dc.hour = 0; dc.minute = 0; dc.second = 0
            case 2:
                guard let y = Int(parts[0]), let m = Int(parts[1]) else { return nil }
                dc.year = y; dc.month = m; dc.day = 1; dc.hour = 0; dc.minute = 0; dc.second = 0
            case 3:
                guard let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2]) else { return nil }
                dc.year = y; dc.month = m; dc.day = d; dc.hour = 12; dc.minute = 0; dc.second = 0
            default:
                return nil
            }
            return dc.date
        }
    }

    // ── Pagination cursor ──────────────────────────────────────────────────────

    public struct SearchCursor: Sendable {
        public let lastUpdated: Date
        public let id: String
        public let descending: Bool  // true = -_lastUpdated ordering

        // URL-safe base64: "<timestamp>|<id>|<1|0>"
        public func encode() -> String {
            let s = "\(lastUpdated.timeIntervalSince1970)|\(id)|\(descending ? 1 : 0)"
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
            guard parts.count == 3,
                  let ts = Double(parts[0]) else { return nil }
            return SearchCursor(
                lastUpdated: Date(timeIntervalSince1970: ts),
                id: String(parts[1]),
                descending: parts[2] == "1"
            )
        }
    }
}
