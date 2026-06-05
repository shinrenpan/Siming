import Foundation

public struct ObservationSearchQuery: Sendable {

    // ── Filters ───────────────────────────────────────────────────────────────

    public var subject: String?
    public var code: [TokenParam]       // OR: "http://loinc.org|29463-7,http://loinc.org|8867-4"
    public var date: [DateParam]
    public var status: [String]         // OR: "final,amended"
    public var category: [TokenParam]   // OR: "vital-signs,laboratory"
    public var id: [String]             // _id filter (OR)
    public var lastUpdated: [DateParam] // _lastUpdated range filter

    // ── Pagination / sort ─────────────────────────────────────────────────────

    public var count: Int
    public var sort: SortOrder
    public var cursor: SearchCursor?

    public init(
        subject: String? = nil,
        code: [TokenParam] = [],
        date: [DateParam] = [],
        status: [String] = [],
        category: [TokenParam] = [],
        id: [String] = [],
        lastUpdated: [DateParam] = [],
        count: Int = 20,
        sort: SortOrder = .lastUpdatedDescending,
        cursor: SearchCursor? = nil
    ) {
        self.subject     = subject
        self.code        = code
        self.date        = date
        self.status      = status
        self.category    = category
        self.id          = id
        self.lastUpdated = lastUpdated
        self.count       = count
        self.sort        = sort
        self.cursor      = cursor
    }

    // ── Nested types ──────────────────────────────────────────────────────────

    public struct TokenParam: Sendable {
        public let system: String?
        public let code: String

        public static func parse(_ raw: String) -> TokenParam {
            if let pipe = raw.firstIndex(of: "|") {
                let sys  = String(raw[raw.startIndex..<pipe])
                let code = String(raw[raw.index(after: pipe)...])
                return TokenParam(system: sys.isEmpty ? nil : sys, code: code)
            }
            return TokenParam(system: nil, code: raw)
        }

        // Parses comma-separated OR list: "system|code1,system|code2"
        public static func parseList(_ raw: String) -> [TokenParam] {
            raw.split(separator: ",").map { parse(String($0).trimmingCharacters(in: .whitespaces)) }
        }
    }

    // Reuse PatientSearchQuery types (includes sa/eb prefixes)
    public typealias DateParam    = PatientSearchQuery.BirthdateParam
    public typealias SortOrder    = PatientSearchQuery.SortOrder
    public typealias SearchCursor = PatientSearchQuery.SearchCursor
}
