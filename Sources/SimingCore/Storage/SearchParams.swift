import Foundation

/// Aggregates all index rows extracted from a single resource write.
/// Passed to the storage layer to bulk-insert into the five idx_* tables.
public struct SearchParams: Sendable {
    public var tokens:     [TokenIndexRow]     = []
    public var strings:    [StringIndexRow]    = []
    public var dates:      [DateIndexRow]      = []
    public var references: [ReferenceIndexRow] = []
    public var quantities: [QuantityIndexRow]  = []
    public var composites: [CompositeIndexRow] = []

    public init() {}
}

/// One row in idx_composite: a (code1, value2/code2) tuple from a single
/// resource element (component, root-level value, etc.).
public struct CompositeIndexRow: Sendable {
    public let paramName:   String
    public let code1System: String?
    public let code1Code:   String
    public let code2System: String?
    public let code2Code:   String?
    public let value2:      Double?
    public let date2Start:  Date?
    public let date2End:    Date?
    public let string2:     String?

    public init(paramName: String, code1System: String?, code1Code: String,
                code2System: String? = nil, code2Code: String? = nil,
                value2: Double? = nil, date2Start: Date? = nil, date2End: Date? = nil,
                string2: String? = nil) {
        self.paramName   = paramName
        self.code1System = code1System
        self.code1Code   = code1Code
        self.code2System = code2System
        self.code2Code   = code2Code
        self.value2      = value2
        self.date2Start  = date2Start
        self.date2End    = date2End
        self.string2     = string2
    }
}
