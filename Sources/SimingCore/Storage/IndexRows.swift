import Foundation

public struct TokenIndexRow {
    public let paramName: String
    public let system: String?
    public let code: String

    public init(paramName: String, system: String?, code: String) {
        self.paramName = paramName; self.system = system; self.code = code
    }
}

public struct StringIndexRow {
    public let paramName: String
    public let value: String

    public init(paramName: String, value: String) {
        self.paramName = paramName; self.value = value
    }
}

public struct DateIndexRow {
    public let paramName: String
    public let dateStart: Date
    public let dateEnd: Date

    public init(paramName: String, dateStart: Date, dateEnd: Date) {
        self.paramName = paramName; self.dateStart = dateStart; self.dateEnd = dateEnd
    }
}

public struct ReferenceIndexRow {
    public let paramName: String
    public let refType: String?
    public let refId: String

    public init(paramName: String, refType: String?, refId: String) {
        self.paramName = paramName; self.refType = refType; self.refId = refId
    }
}

public struct QuantityIndexRow {
    public let paramName: String
    public let system: String?
    public let code: String?
    public let value: Decimal

    public init(paramName: String, system: String?, code: String?, value: Decimal) {
        self.paramName = paramName; self.system = system; self.code = code; self.value = value
    }
}
