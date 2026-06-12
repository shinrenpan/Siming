public struct BindingRule: Sendable {
    public let path: String
    public let valueSet: String
    public let kind: BindingKind
    public let isArray: Bool

    public init(path: String, valueSet: String, kind: BindingKind, isArray: Bool) {
        self.path = path; self.valueSet = valueSet; self.kind = kind; self.isArray = isArray
    }
}

public enum BindingKind: Sendable {
    case code
    case codeableConcept
}
