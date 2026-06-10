import Foundation

public struct TokenIndexRow: Sendable {
    public let paramName: String
    public let system: String?
    public let code: String

    public init(paramName: String, system: String?, code: String) {
        self.paramName = paramName; self.system = system; self.code = code
    }
}

public struct StringIndexRow: Sendable {
    public let paramName: String
    public let value: String

    public init(paramName: String, value: String) {
        self.paramName = paramName; self.value = value
    }
}

public struct DateIndexRow: Sendable {
    public let paramName: String
    public let dateStart: Date
    public let dateEnd: Date

    public init(paramName: String, dateStart: Date, dateEnd: Date) {
        self.paramName = paramName; self.dateStart = dateStart; self.dateEnd = dateEnd
    }
}

public struct ReferenceIndexRow: Sendable {
    public let paramName: String
    public let refType: String?
    public let refId: String

    public init(paramName: String, refType: String?, refId: String) {
        self.paramName = paramName; self.refType = refType; self.refId = refId
    }
}

public struct QuantityIndexRow: Sendable {
    public let paramName: String
    public let system: String?
    public let code: String?
    public let value: Decimal

    public init(paramName: String, system: String?, code: String?, value: Decimal) {
        self.paramName = paramName; self.system = system; self.code = code; self.value = value
    }
}

/// Carry a single token :text filter from the route layer to the store.
/// The store queries idx_string WHERE param_name = '\(paramName):text' AND value ILIKE '%value%'.
public struct TokenTextParam: Sendable {
    public let paramName: String
    public let value: String
    public init(paramName: String, value: String) {
        self.paramName = paramName; self.value = value
    }
}
