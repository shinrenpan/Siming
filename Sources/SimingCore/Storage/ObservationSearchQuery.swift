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
    public var comboCode: [TokenParam]
    public var comboCodeNot: [TokenParam]
    public var method: [TokenParam]
    public var methodNot: [TokenParam]
    public var valueConcept: [TokenParam]
    public var valueConceptNot: [TokenParam]
    public var dataAbsentReason: [TokenParam]         // data-absent-reason token OR
    public var comboDataAbsentReason: [TokenParam]    // combo-data-absent-reason token OR
    public var componentDataAbsentReason: [TokenParam] // component-data-absent-reason token OR
    public var componentValueConcept: [TokenParam]    // component-value-concept token OR
    public var valueQuantity: [QuantityParam] // value-quantity OR list
    public var valueDate: [DateParam]
    public var valueString: [String]
    public var id: [String]               // _id filter (OR)
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
        comboCode: [TokenParam] = [],
        comboCodeNot: [TokenParam] = [],
        method: [TokenParam] = [],
        methodNot: [TokenParam] = [],
        valueConcept: [TokenParam] = [],
        valueConceptNot: [TokenParam] = [],
        dataAbsentReason: [TokenParam] = [],
        comboDataAbsentReason: [TokenParam] = [],
        componentDataAbsentReason: [TokenParam] = [],
        componentValueConcept: [TokenParam] = [],
        valueQuantity: [QuantityParam] = [],
        valueDate: [DateParam] = [],
        valueString: [String] = [],
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
        self.encounter      = encounter
        self.performer      = performer
        self.basedOn        = basedOn
        self.derivedFrom    = derivedFrom
        self.device         = device
        self.focus          = focus
        self.hasMember      = hasMember
        self.partOf         = partOf
        self.specimen       = specimen
        self.componentCode  = componentCode
        self.comboCode      = comboCode
        self.comboCodeNot   = comboCodeNot
        self.method         = method
        self.methodNot      = methodNot
        self.valueConcept   = valueConcept
        self.valueConceptNot = valueConceptNot
        self.dataAbsentReason          = dataAbsentReason
        self.comboDataAbsentReason     = comboDataAbsentReason
        self.componentDataAbsentReason = componentDataAbsentReason
        self.componentValueConcept     = componentValueConcept
        self.valueQuantity  = valueQuantity
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
}
