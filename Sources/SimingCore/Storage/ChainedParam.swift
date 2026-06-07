import Foundation

/// A parsed FHIR chained search parameter.
///
/// Format: `refParam.childParam=value` or `refParam:TargetType.childParam=value`
/// Examples:
///   subject.name=Wang
///   subject:Patient.birthdate=ge1990
///   patient.gender=female
public struct ChainedParam: Sendable {
    public enum ChildType: Sendable {
        case string     // resolved via idx_string
        case token      // resolved via idx_token
        case date       // resolved via idx_date
    }

    public let refParam: String     // "subject"
    public let targetType: String?  // "Patient" (from ":Patient.name"), nil = any type
    public let childParam: String   // "name"
    public let value: String        // "Wang"
    public let modifier: String?    // "contains", "exact", nil = startsWith
    public let childType: ChildType

    public init(refParam: String, targetType: String? = nil, childParam: String,
                value: String, modifier: String? = nil, childType: ChildType) {
        self.refParam   = refParam
        self.targetType = targetType
        self.childParam = childParam
        self.value      = value
        self.modifier   = modifier
        self.childType  = childType
    }
}

/// Maps well-known FHIR search param names to the index table they live in.
public let chainChildParamType: [String: ChainedParam.ChildType] = [
    // String params (idx_string)
    "name": .string, "family": .string, "given": .string,
    "address": .string, "address-city": .string, "address-state": .string,
    "address-postalcode": .string, "address-country": .string,
    // Token params (idx_token)
    "gender": .token, "identifier": .token, "code": .token, "status": .token,
    "clinical-status": .token, "verification-status": .token,
    "category": .token, "type": .token, "class": .token,
    "criticality": .token, "intent": .token, "priority": .token,
    // Date params (idx_date)
    "birthdate": .date, "date": .date, "onset-date": .date,
    "authoredon": .date, "recorded-date": .date,
    "issued": .date,
    // Additional token and string params for new resources
    "vaccine-code": .token, "lot-number": .string,
    // Date params for additional resources
    "effective-time": .date,
    // Token params for additional resources
    "reason-given": .token, "reason-not-given": .token,
]

/// Parses a chained search param key+value.
///
/// Key format: `refParam.childParam` or `refParam:TargetType.childParam` or
///             `refParam.childParam:modifier`
/// Returns nil if key does not contain ".", starts with "_", or if
/// the child param type is not in the lookup table.
public func parseChainKey(_ key: String, value: String) -> ChainedParam? {
    guard let dotIdx = key.firstIndex(of: "."), !key.hasPrefix("_") else { return nil }

    let refPart   = String(key[key.startIndex..<dotIdx])
    var childPart = String(key[key.index(after: dotIdx)...])

    // Extract optional modifier suffix from child part: "name:contains"
    var modifier: String? = nil
    if let colonIdx = childPart.lastIndex(of: ":") {
        let mod = String(childPart[childPart.index(after: colonIdx)...])
        if ["contains", "exact", "text"].contains(mod) {
            modifier = mod
            childPart = String(childPart[childPart.startIndex..<colonIdx])
        }
    }

    // Extract optional TargetType from ref part: "subject:Patient"
    var refParam = refPart
    var targetType: String? = nil
    if let colonIdx = refPart.firstIndex(of: ":") {
        targetType = String(refPart[refPart.index(after: colonIdx)...])
        refParam   = String(refPart[refPart.startIndex..<colonIdx])
    }

    guard let childType = chainChildParamType[childPart] else { return nil }

    return ChainedParam(refParam: refParam, targetType: targetType,
                        childParam: childPart, value: value,
                        modifier: modifier, childType: childType)
}

/// Generates a filter CTE for one chained search param.
///
/// The caller supplies two specialised bind closures so that the generated
/// placeholders slot into the caller's existing PostgresBindings counter:
///   `bindStr` — appends a String value and returns "$n"
///   `bindDate` — appends a Date value and returns "$n"
///
/// Returns nil if the chain value cannot be parsed (e.g. bad date string).
public func chainFilterCTE(
    index: Int,
    sourceType: String,
    chain: ChainedParam,
    bindStr: (String) -> String,
    bindDate: (Date) -> String
) -> (name: String, sql: String)? {
    let cteName = "f_chain\(index)"

    // Bind in the order they appear in SQL (JOIN ON ... before WHERE ...)
    let cpBind = bindStr(chain.childParam)

    let joinSQL: String
    switch chain.childType {
    case .string:
        let pBind: String
        let stringCond: String
        switch chain.modifier {
        case "exact":
            pBind = bindStr(chain.value)
            stringCond = "s.value = \(pBind)"
        case "contains", "text":
            pBind = bindStr("%\(chain.value)%")
            stringCond = "s.value ILIKE \(pBind)"
        default:
            pBind = bindStr("\(chain.value)%")
            stringCond = "lower(s.value) LIKE lower(\(pBind))"
        }
        joinSQL = """
        JOIN idx_string s ON s.resource_type = ref.ref_type AND s.resource_id = ref.ref_id \
        AND s.param_name = \(cpBind) AND \(stringCond)
        """

    case .token:
        let parts = chain.value.split(separator: "|", maxSplits: 1)
        if parts.count == 2 {
            let sBind = bindStr(String(parts[0]))
            let cBind = bindStr(String(parts[1]))
            joinSQL = """
            JOIN idx_token t ON t.resource_type = ref.ref_type AND t.resource_id = ref.ref_id \
            AND t.param_name = \(cpBind) AND t.system = \(sBind) AND t.code = \(cBind)
            """
        } else {
            let cBind = bindStr(chain.value)
            joinSQL = """
            JOIN idx_token t ON t.resource_type = ref.ref_type AND t.resource_id = ref.ref_id \
            AND t.param_name = \(cpBind) AND t.code = \(cBind)
            """
        }

    case .date:
        guard let dp = PatientSearchQuery.BirthdateParam.parse(chain.value) else { return nil }
        let dateClause = chainDateClause(dp: dp, bindDate: bindDate)
        joinSQL = """
        JOIN idx_date d ON d.resource_type = ref.ref_type AND d.resource_id = ref.ref_id \
        AND d.param_name = \(cpBind) AND \(dateClause)
        """
    }

    let srcBind = bindStr(sourceType)
    let refBind = bindStr(chain.refParam)
    var targetClause = ""
    if let tt = chain.targetType { targetClause = " AND ref.ref_type = \(bindStr(tt))" }

    return (cteName, """
    SELECT DISTINCT ref.resource_id FROM idx_reference ref
    \(joinSQL)
    WHERE ref.resource_type = \(srcBind) AND ref.param_name = \(refBind)\(targetClause)
    """)
}

private func chainDateClause(
    dp: PatientSearchQuery.BirthdateParam,
    bindDate: (Date) -> String
) -> String {
    switch dp.prefix {
    case .eq:  return "d.date_start <= \(bindDate(dp.dateEnd)) AND d.date_end >= \(bindDate(dp.dateStart))"
    case .ne:  return "NOT (d.date_start <= \(bindDate(dp.dateEnd)) AND d.date_end >= \(bindDate(dp.dateStart)))"
    case .lt:  return "d.date_end < \(bindDate(dp.dateStart))"
    case .le:  return "d.date_start <= \(bindDate(dp.dateEnd))"
    case .gt:  return "d.date_start > \(bindDate(dp.dateEnd))"
    case .ge:  return "d.date_end >= \(bindDate(dp.dateStart))"
    case .sa:  return "d.date_start > \(bindDate(dp.dateEnd))"
    case .eb:  return "d.date_end < \(bindDate(dp.dateStart))"
    }
}
