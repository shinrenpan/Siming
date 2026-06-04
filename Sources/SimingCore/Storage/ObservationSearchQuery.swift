import Foundation

public struct ObservationSearchQuery: Sendable {

    // ── Filters ───────────────────────────────────────────────────────────────

    /// subject or patient: "Patient/abc-123" or plain "abc-123"
    public var subject: String?

    /// code token: optional system + code  ("http://loinc.org|8867-4" or "8867-4")
    public var code: TokenParam?

    /// date range on Observation.effective (same prefix semantics as Patient.birthdate)
    public var date: [DateParam]

    /// status token ("final", "preliminary", etc.)
    public var status: String?

    /// category token (system|code or plain code)
    public var category: TokenParam?

    // ── Pagination / sort ─────────────────────────────────────────────────────

    public var count: Int
    public var sort: SortOrder
    public var cursor: SearchCursor?

    public init(
        subject: String? = nil,
        code: TokenParam? = nil,
        date: [DateParam] = [],
        status: String? = nil,
        category: TokenParam? = nil,
        count: Int = 20,
        sort: SortOrder = .lastUpdatedDescending,
        cursor: SearchCursor? = nil
    ) {
        self.subject  = subject
        self.code     = code
        self.date     = date
        self.status   = status
        self.category = category
        self.count    = count
        self.sort     = sort
        self.cursor   = cursor
    }

    // ── Nested types (shared with PatientSearchQuery where possible) ──────────

    public struct TokenParam: Sendable {
        public let system: String?
        public let code: String

        /// Parse "system|code", "|code" (null system), or bare "code"
        public static func parse(_ raw: String) -> TokenParam {
            if let pipe = raw.firstIndex(of: "|") {
                let sys  = String(raw[raw.startIndex..<pipe])
                let code = String(raw[raw.index(after: pipe)...])
                return TokenParam(system: sys.isEmpty ? nil : sys, code: code)
            }
            return TokenParam(system: nil, code: raw)
        }
    }

    // Reuse PatientSearchQuery types
    public typealias DateParam  = PatientSearchQuery.BirthdateParam
    public typealias SortOrder  = PatientSearchQuery.SortOrder
    public typealias SearchCursor = PatientSearchQuery.SearchCursor
}
