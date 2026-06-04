import Foundation

/// Aggregates all index rows extracted from a single resource write.
/// Passed to the storage layer to bulk-insert into the five idx_* tables.
public struct SearchParams {
    public var tokens:     [TokenIndexRow]     = []
    public var strings:    [StringIndexRow]    = []
    public var dates:      [DateIndexRow]      = []
    public var references: [ReferenceIndexRow] = []
    public var quantities: [QuantityIndexRow]  = []

    public init() {}
}
