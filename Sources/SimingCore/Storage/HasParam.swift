import Foundation

/// A parsed FHIR `_has` search modifier.
///
/// Format: `_has:[ReferencedType]:[refParam]:[childParam]=value`
/// Examples:
///   _has:Observation:subject:code=85354-9
///   _has:Condition:subject:clinical-status=active
///   _has:MedicationRequest:patient:status=active
///   _has:Observation:encounter:code=85354-9       (on Encounter)
public struct HasParam: Sendable {
    public let referencedType: String   // "Observation" — the resource doing the referencing
    public let refParam: String         // "subject" — the reference param on that type
    public let childParam: String       // "code" — the search param to filter on
    public let value: String            // "85354-9"
    public let modifier: String?        // "contains", "exact", nil = startsWith (string only)
    public let childType: ChainedParam.ChildType

    public init(referencedType: String, refParam: String, childParam: String,
                value: String, modifier: String? = nil, childType: ChainedParam.ChildType) {
        self.referencedType = referencedType
        self.refParam       = refParam
        self.childParam     = childParam
        self.value          = value
        self.modifier       = modifier
        self.childType      = childType
    }
}

/// Parses a `_has` modifier key+value pair.
///
/// Key format: `_has:[ReferencedType]:[refParam]:[childParam]`
/// or          `_has:[ReferencedType]:[refParam]:[childParam]:modifier`
/// Returns nil if key is malformed or childParam type is unknown.
public func parseHasKey(_ key: String, value: String) -> HasParam? {
    guard key.hasPrefix("_has:") else { return nil }
    let rest = String(key.dropFirst(5))  // drop "_has:"

    // Split on ":" — expect exactly 3 components (or 4 with modifier)
    let parts = rest.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
    guard parts.count >= 3 else { return nil }

    let referencedType = parts[0]
    let refParam       = parts[1]
    let childPart      = parts[2]
    var modifier: String? = nil

    // Optional string modifier as 4th segment: _has:Type:ref:name:contains
    if parts.count >= 4 {
        let mod = parts[3]
        if ["contains", "exact", "text"].contains(mod) {
            modifier  = mod
        } else {
            // unknown 4th segment — ignore gracefully
        }
    }

    guard !referencedType.isEmpty, !refParam.isEmpty, !childPart.isEmpty else { return nil }
    guard let childType = chainChildParamType[childPart] else { return nil }

    return HasParam(referencedType: referencedType, refParam: refParam,
                    childParam: childPart, value: value,
                    modifier: modifier, childType: childType)
}

/// Generates a filter CTE for one `_has` search modifier.
///
/// Finds IDs of `mainType` resources that are referenced by at least one
/// `param.referencedType` resource via `param.refParam`, where that referencing
/// resource also matches `param.childParam=value`.
///
/// The caller supplies specialised bind closures that share the caller's bind counter:
///   `bindStr` — appends a String value and returns "$n"
///   `bindDate` — appends a Date value and returns "$n"
///
/// Returns nil if the value cannot be parsed (e.g. bad date string).
public func hasFilterCTE(
    index: Int,
    mainType: String,
    param: HasParam,
    bindStr: (String) -> String,
    bindDate: (Date) -> String
) -> (name: String, sql: String)? {
    let cteName = "f_has\(index)"

    // Bind in SQL appearance order — child param name first, then value(s)
    let cpBind = bindStr(param.childParam)

    let joinSQL: String
    switch param.childType {
    case .string:
        let pBind: String
        let stringCond: String
        switch param.modifier {
        case "exact":
            pBind = bindStr(param.value)
            stringCond = "s.value = \(pBind)"
        case "contains", "text":
            pBind = bindStr("%\(param.value)%")
            stringCond = "s.value ILIKE \(pBind)"
        default:
            pBind = bindStr("\(param.value)%")
            stringCond = "lower(s.value) LIKE lower(\(pBind))"
        }
        joinSQL = """
        JOIN idx_string s ON s.resource_type = ref.resource_type AND s.resource_id = ref.resource_id \
        AND s.param_name = \(cpBind) AND \(stringCond)
        """

    case .token:
        let parts = param.value.split(separator: "|", maxSplits: 1)
        if parts.count == 2 {
            let sBind = bindStr(String(parts[0]))
            let cBind = bindStr(String(parts[1]))
            joinSQL = """
            JOIN idx_token t ON t.resource_type = ref.resource_type AND t.resource_id = ref.resource_id \
            AND t.param_name = \(cpBind) AND t.system = \(sBind) AND t.code = \(cBind)
            """
        } else {
            let cBind = bindStr(param.value)
            joinSQL = """
            JOIN idx_token t ON t.resource_type = ref.resource_type AND t.resource_id = ref.resource_id \
            AND t.param_name = \(cpBind) AND t.code = \(cBind)
            """
        }

    case .date:
        guard let dp = PatientSearchQuery.BirthdateParam.parse(param.value) else { return nil }
        let dateClause = hasDateClause(dp: dp, bindDate: bindDate)
        joinSQL = """
        JOIN idx_date d ON d.resource_type = ref.resource_type AND d.resource_id = ref.resource_id \
        AND d.param_name = \(cpBind) AND \(dateClause)
        """
    }

    let rtBind  = bindStr(param.referencedType)
    let rpBind  = bindStr(param.refParam)
    let mtBind  = bindStr(mainType)

    return (cteName, """
    \(cteName) AS (
      SELECT DISTINCT ref.ref_id AS resource_id FROM idx_reference ref
      \(joinSQL)
      WHERE ref.resource_type = \(rtBind) AND ref.param_name = \(rpBind) AND ref.ref_type = \(mtBind)
    )
    """)
}

private func hasDateClause(
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
