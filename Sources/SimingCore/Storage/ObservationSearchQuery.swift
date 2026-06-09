import Foundation

public struct ObservationSearchQuery: Sendable {

    // ── Filters ───────────────────────────────────────────────────────────────

    public var subject: String?  // forced to "Patient/:id" in compartment search
    public var code: [TokenParam]         // OR: "http://loinc.org|29463-7,http://loinc.org|8867-4"
    public var codeNot: [TokenParam]      // :not modifier — exclude matching
    public var date: [DateParam]
    public var status: [String]           // OR: "final,amended"
    public var statusNot: [String]        // :not modifier — exclude matching
    public var category: [TokenParam]     // OR: "vital-signs,laboratory"
    public var categoryNot: [TokenParam]  // :not modifier — exclude matching
    public var identifier: [IdentifierParam]  // token OR, system|code format
    public var identifierNot: [IdentifierParam]  // identifier:not modifier
    public var encounter: String?             // reference: "Encounter/id" or bare id
    public var performer: String?             // reference: single performer
    public var basedOn: String?
    public var derivedFrom: String?
    public var device: String?
    public var focus: String?
    public var hasMember: String?
    public var partOf: String?
    public var specimen: String?
    public var componentCode: [TokenParam]    // component-code token OR
    public var componentCodeNot: [TokenParam]  // component-code:not modifier
    public var comboCode: [TokenParam]
    public var comboCodeNot: [TokenParam]
    public var method: [TokenParam]
    public var methodNot: [TokenParam]
    public var valueConcept: [TokenParam]
    public var valueConceptNot: [TokenParam]
    public var comboValueConcept: [TokenParam]
    public var comboValueConceptNot: [TokenParam]
    public var dataAbsentReason: [TokenParam]              // data-absent-reason token OR
    public var dataAbsentReasonNot: [TokenParam]           // data-absent-reason:not modifier
    public var comboDataAbsentReason: [TokenParam]         // combo-data-absent-reason token OR
    public var comboDataAbsentReasonNot: [TokenParam]      // combo-data-absent-reason:not modifier
    public var componentDataAbsentReason: [TokenParam]     // component-data-absent-reason token OR
    public var componentDataAbsentReasonNot: [TokenParam]  // component-data-absent-reason:not modifier
    public var componentValueConcept: [TokenParam]         // component-value-concept token OR
    public var componentValueConceptNot: [TokenParam]      // component-value-concept:not modifier
    public var componentValueQuantity: [QuantityParam] // component-value-quantity quantity OR
    public var comboValueQuantity: [QuantityParam]     // combo-value-quantity quantity OR (obs.value only; component part not yet indexed)
    public var valueQuantity: [QuantityParam] // value-quantity OR list
    // ── Root-level composite params ───────────────────────────────────────────
    public var codeValueQuantity: [CompositeCodeQuantity]   // code-value-quantity: code$value-quantity
    public var codeValueString: [CompositeCodeString]       // code-value-string: code$value-string
    public var codeValueConcept: [CompositeCodeConcept]     // code-value-concept: code$value-concept
    public var codeValueDate: [CompositeCodeDate]           // code-value-date: code$value-date
    // ── idx_composite-backed params (tuple match) ─────────────────────────────
    public var componentCodeValueQuantity: [CompositeCodeQuantity]  // component-code-value-quantity
    public var componentCodeValueConcept: [CompositeCodeConcept]    // component-code-value-concept
    public var comboCodeValueQuantity: [CompositeCodeQuantity]      // combo-code-value-quantity
    public var comboCodeValueConcept: [CompositeCodeConcept]        // combo-code-value-concept
    public var valueDate: [DateParam]
    public var valueString: [StringParam]
    public var id: [String]               // _id filter (OR)
    public var meta: MetaSearchParams = MetaSearchParams()  // _tag / _security / _profile
    public var lastUpdated: [DateParam]   // _lastUpdated range filter
    public var missing: [String: Bool]    // param:missing=true/false
    public var chains: [ChainedParam]    // chained search: subject.name=Wang, etc.
    public var has: [HasParam]           // _has modifier: reverse chaining

    // ── Pagination / sort ─────────────────────────────────────────────────────

    public var totalMode: TotalMode
    public var count: Int
    public var sort: SortOrder
    public var cursor: SearchCursor?

    public init(
        subject: String? = nil,
        code: [TokenParam] = [],
        codeNot: [TokenParam] = [],
        date: [DateParam] = [],
        status: [String] = [],
        statusNot: [String] = [],
        category: [TokenParam] = [],
        categoryNot: [TokenParam] = [],
        identifier: [IdentifierParam] = [],
        identifierNot: [IdentifierParam] = [],
        encounter: String? = nil,
        performer: String? = nil,
        basedOn: String? = nil,
        derivedFrom: String? = nil,
        device: String? = nil,
        focus: String? = nil,
        hasMember: String? = nil,
        partOf: String? = nil,
        specimen: String? = nil,
        componentCode: [TokenParam] = [],
        componentCodeNot: [TokenParam] = [],
        comboCode: [TokenParam] = [],
        comboCodeNot: [TokenParam] = [],
        method: [TokenParam] = [],
        methodNot: [TokenParam] = [],
        valueConcept: [TokenParam] = [],
        valueConceptNot: [TokenParam] = [],
        comboValueConcept: [TokenParam] = [],
        comboValueConceptNot: [TokenParam] = [],
        dataAbsentReason: [TokenParam] = [],
        dataAbsentReasonNot: [TokenParam] = [],
        comboDataAbsentReason: [TokenParam] = [],
        comboDataAbsentReasonNot: [TokenParam] = [],
        componentDataAbsentReason: [TokenParam] = [],
        componentDataAbsentReasonNot: [TokenParam] = [],
        componentValueConcept: [TokenParam] = [],
        componentValueConceptNot: [TokenParam] = [],
        componentValueQuantity: [QuantityParam] = [],
        comboValueQuantity: [QuantityParam] = [],
        valueQuantity: [QuantityParam] = [],
        codeValueQuantity: [CompositeCodeQuantity] = [],
        codeValueString: [CompositeCodeString] = [],
        codeValueConcept: [CompositeCodeConcept] = [],
        codeValueDate: [CompositeCodeDate] = [],
        componentCodeValueQuantity: [CompositeCodeQuantity] = [],
        componentCodeValueConcept: [CompositeCodeConcept] = [],
        comboCodeValueQuantity: [CompositeCodeQuantity] = [],
        comboCodeValueConcept: [CompositeCodeConcept] = [],
        valueDate: [DateParam] = [],
        valueString: [StringParam] = [],
        id: [String] = [],
        lastUpdated: [DateParam] = [],
        missing: [String: Bool] = [:],
        chains: [ChainedParam] = [],
        has: [HasParam] = [],
        totalMode: TotalMode = .accurate,
        count: Int = 20,
        sort: SortOrder = .lastUpdatedDescending,
        cursor: SearchCursor? = nil
    ) {
        self.subject        = subject
        self.code           = code
        self.codeNot        = codeNot
        self.date           = date
        self.status         = status
        self.statusNot      = statusNot
        self.category       = category
        self.categoryNot    = categoryNot
        self.identifier     = identifier
        self.identifierNot  = identifierNot
        self.encounter      = encounter
        self.performer      = performer
        self.basedOn        = basedOn
        self.derivedFrom    = derivedFrom
        self.device         = device
        self.focus          = focus
        self.hasMember      = hasMember
        self.partOf         = partOf
        self.specimen       = specimen
        self.componentCode    = componentCode
        self.componentCodeNot = componentCodeNot
        self.comboCode        = comboCode
        self.comboCodeNot     = comboCodeNot
        self.method         = method
        self.methodNot      = methodNot
        self.valueConcept   = valueConcept
        self.valueConceptNot = valueConceptNot
        self.comboValueConcept    = comboValueConcept
        self.comboValueConceptNot = comboValueConceptNot
        self.dataAbsentReason               = dataAbsentReason
        self.dataAbsentReasonNot            = dataAbsentReasonNot
        self.comboDataAbsentReason          = comboDataAbsentReason
        self.comboDataAbsentReasonNot       = comboDataAbsentReasonNot
        self.componentDataAbsentReason      = componentDataAbsentReason
        self.componentDataAbsentReasonNot   = componentDataAbsentReasonNot
        self.componentValueConcept          = componentValueConcept
        self.componentValueConceptNot       = componentValueConceptNot
        self.componentValueQuantity    = componentValueQuantity
        self.comboValueQuantity        = comboValueQuantity
        self.valueQuantity  = valueQuantity
        self.codeValueQuantity = codeValueQuantity
        self.codeValueString   = codeValueString
        self.codeValueConcept  = codeValueConcept
        self.codeValueDate     = codeValueDate
        self.componentCodeValueQuantity = componentCodeValueQuantity
        self.componentCodeValueConcept  = componentCodeValueConcept
        self.comboCodeValueQuantity     = comboCodeValueQuantity
        self.comboCodeValueConcept      = comboCodeValueConcept
        self.valueDate      = valueDate
        self.valueString    = valueString
        self.id             = id
        self.lastUpdated    = lastUpdated
        self.missing        = missing
        self.chains         = chains
        self.has            = has
        self.totalMode      = totalMode
        self.count          = count
        self.sort           = sort
        self.cursor         = cursor
    }

    // ── Nested types ──────────────────────────────────────────────────────────

    public typealias StringParam = PatientSearchQuery.StringParam

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

    // ── Quantity parameter ────────────────────────────────────────────────────
    // Format: [prefix][value][|system][|code]
    // Examples: "5.4", "ge5.4", "5.4||mg", "ge5.4|http://unitsofmeasure.org|mg"

    public struct QuantityParam: Sendable {
        public enum Prefix: String, Sendable {
            case eq, ne, lt, gt, le, ge, sa, eb, ap
        }
        public let prefix: Prefix
        public let value: Double
        public let system: String?   // nil = match any system
        public let code: String?     // nil = match any unit code

        public static func parse(_ raw: String) -> QuantityParam? {
            let knownPrefixes = ["eq", "ne", "lt", "gt", "le", "ge", "sa", "eb", "ap"]
            let (pfxStr, rest): (String, String)
            let candidate = String(raw.prefix(2))
            if knownPrefixes.contains(candidate) {
                pfxStr = candidate; rest = String(raw.dropFirst(2))
            } else {
                pfxStr = "eq"; rest = raw
            }
            guard let pfx = Prefix(rawValue: pfxStr) else { return nil }
            // Split rest on '|' without dropping empty subsequences
            let parts = rest.split(separator: "|", maxSplits: 2, omittingEmptySubsequences: false)
            guard let valueStr = parts.first, let val = Double(String(valueStr)) else { return nil }
            let system: String? = parts.count >= 2 ? (parts[1].isEmpty ? nil : String(parts[1])) : nil
            let code: String?   = parts.count >= 3 ? (parts[2].isEmpty ? nil : String(parts[2])) : nil
            return QuantityParam(prefix: pfx, value: val, system: system, code: code)
        }

        public static func parseList(_ raw: String) -> [QuantityParam] {
            raw.split(separator: ",").compactMap { parse(String($0).trimmingCharacters(in: .whitespaces)) }
        }
    }

    // Reuse PatientSearchQuery types (includes sa/eb prefixes)
    public typealias DateParam       = PatientSearchQuery.BirthdateParam
    public typealias SortOrder       = PatientSearchQuery.SortOrder
    public typealias SearchCursor    = PatientSearchQuery.SearchCursor
    public typealias IdentifierParam = PatientSearchQuery.IdentifierParam
    public typealias TotalMode       = PatientSearchQuery.TotalMode

    // ── Composite param types — code$value ────────────────────────────────────

    public struct CompositeCodeQuantity: Sendable {
        public let codeToken: TokenParam
        public let valueQuantity: QuantityParam
        public static func parse(_ raw: String) -> CompositeCodeQuantity? {
            guard let dollarIdx = raw.firstIndex(of: "$") else { return nil }
            let codePart  = String(raw[raw.startIndex..<dollarIdx])
            let valuePart = String(raw[raw.index(after: dollarIdx)...])
            guard let qty = QuantityParam.parse(valuePart) else { return nil }
            return CompositeCodeQuantity(codeToken: TokenParam.parse(codePart), valueQuantity: qty)
        }
        public static func parseList(_ raw: String) -> [CompositeCodeQuantity] {
            raw.split(separator: ",").compactMap { parse(String($0).trimmingCharacters(in: .whitespaces)) }
        }
    }

    public struct CompositeCodeString: Sendable {
        public let codeToken: TokenParam
        public let valueString: String
        public static func parse(_ raw: String) -> CompositeCodeString? {
            guard let dollarIdx = raw.firstIndex(of: "$") else { return nil }
            let codePart  = String(raw[raw.startIndex..<dollarIdx])
            let valuePart = String(raw[raw.index(after: dollarIdx)...])
            guard !valuePart.isEmpty else { return nil }
            return CompositeCodeString(codeToken: TokenParam.parse(codePart), valueString: valuePart)
        }
        public static func parseList(_ raw: String) -> [CompositeCodeString] {
            raw.split(separator: ",").compactMap { parse(String($0).trimmingCharacters(in: .whitespaces)) }
        }
    }

    public struct CompositeCodeConcept: Sendable {
        public let codeToken: TokenParam
        public let valueConcept: TokenParam
        public static func parse(_ raw: String) -> CompositeCodeConcept? {
            guard let dollarIdx = raw.firstIndex(of: "$") else { return nil }
            let codePart    = String(raw[raw.startIndex..<dollarIdx])
            let conceptPart = String(raw[raw.index(after: dollarIdx)...])
            return CompositeCodeConcept(codeToken: TokenParam.parse(codePart),
                                        valueConcept: TokenParam.parse(conceptPart))
        }
        public static func parseList(_ raw: String) -> [CompositeCodeConcept] {
            raw.split(separator: ",").compactMap { parse(String($0).trimmingCharacters(in: .whitespaces)) }
        }
    }

    public struct CompositeCodeDate: Sendable {
        public let codeToken: TokenParam
        public let valueDate: DateParam
        public static func parse(_ raw: String) -> CompositeCodeDate? {
            guard let dollarIdx = raw.firstIndex(of: "$") else { return nil }
            let codePart  = String(raw[raw.startIndex..<dollarIdx])
            let datePart  = String(raw[raw.index(after: dollarIdx)...])
            guard let dp = DateParam.parse(datePart) else { return nil }
            return CompositeCodeDate(codeToken: TokenParam.parse(codePart), valueDate: dp)
        }
        public static func parseList(_ raw: String) -> [CompositeCodeDate] {
            raw.split(separator: ",").compactMap { parse(String($0).trimmingCharacters(in: .whitespaces)) }
        }
    }
}
