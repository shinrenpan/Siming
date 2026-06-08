import Foundation
import ModelsR4

// ── Shared meta search params (FHIR R4 §3.2.2 global params) ─────────────────
// Applies to all 23 resources. Embedded in each XxxSearchQuery as a default-
// initialised property (no init signature change required).

public struct MetaSearchParams: Sendable {
    public typealias TokenParam = ObservationSearchQuery.TokenParam
    public var tag:         [TokenParam] = []   // _tag token OR
    public var tagNot:      [TokenParam] = []   // _tag:not
    public var security:    [TokenParam] = []   // _security token OR
    public var securityNot: [TokenParam] = []   // _security:not
    public var profile:     [String]     = []   // _profile URI exact match

    public init() {}
}

// ── Write path ────────────────────────────────────────────────────────────────
// Call immediately after the resource-specific extractor to append meta rows.

public func appendMetaParams(_ params: inout SearchParams, meta: Meta?) {
    guard let meta else { return }
    for coding in meta.tag ?? [] {
        guard let code = coding.code?.value?.string, !code.isEmpty else { continue }
        params.tokens.append(TokenIndexRow(paramName: "_tag",
                                           system: coding.system?.value?.url.absoluteString,
                                           code: code))
    }
    for coding in meta.security ?? [] {
        guard let code = coding.code?.value?.string, !code.isEmpty else { continue }
        params.tokens.append(TokenIndexRow(paramName: "_security",
                                           system: coding.system?.value?.url.absoluteString,
                                           code: code))
    }
    for profile in meta.profile ?? [] {
        if let uri = profile.value?.url.absoluteString {
            params.strings.append(StringIndexRow(paramName: "_profile", value: uri))
        }
    }
}

// ── Search path ───────────────────────────────────────────────────────────────
// Returns filter CTEs (JOIN into `ids`) and WHERE conditions (NOT IN) for meta params.
// `bind` is the store-local String→$n binder (only String values needed for meta).
// resourceType is used as a SQL string literal — caller must pass a trusted constant.

public func metaFilterCTEs(
    resourceType: String,
    meta: MetaSearchParams,
    bind: (String) -> String
) -> (filterCTEs: [(String, String)], whereConditions: [String]) {
    var filterCTEs: [(String, String)] = []
    var whereConditions: [String] = []

    func orClause(_ tok: MetaSearchParams.TokenParam) -> String {
        var parts = ["code = \(bind(tok.code))"]
        if let sys = tok.system { parts.append("system = \(bind(sys))") }
        return "(\(parts.joined(separator: " AND ")))"
    }
    func notClause(_ tok: MetaSearchParams.TokenParam) -> String { orClause(tok) }

    // _tag
    if !meta.tag.isEmpty {
        let or = meta.tag.map { orClause($0) }.joined(separator: " OR ")
        filterCTEs.append(("f__tag",
            "SELECT DISTINCT resource_id FROM idx_token WHERE resource_type = '\(resourceType)' AND param_name = '_tag' AND (\(or))"))
    }
    if !meta.tagNot.isEmpty {
        let or = meta.tagNot.map { notClause($0) }.joined(separator: " OR ")
        whereConditions.append(
            "r.id NOT IN (SELECT resource_id FROM idx_token WHERE resource_type = '\(resourceType)' AND param_name = '_tag' AND (\(or)))")
    }

    // _security
    if !meta.security.isEmpty {
        let or = meta.security.map { orClause($0) }.joined(separator: " OR ")
        filterCTEs.append(("f__security",
            "SELECT DISTINCT resource_id FROM idx_token WHERE resource_type = '\(resourceType)' AND param_name = '_security' AND (\(or))"))
    }
    if !meta.securityNot.isEmpty {
        let or = meta.securityNot.map { notClause($0) }.joined(separator: " OR ")
        whereConditions.append(
            "r.id NOT IN (SELECT resource_id FROM idx_token WHERE resource_type = '\(resourceType)' AND param_name = '_security' AND (\(or)))")
    }

    // _profile (idx_string, exact URI match)
    if !meta.profile.isEmpty {
        let or = meta.profile.map { "value = \(bind($0))" }.joined(separator: " OR ")
        filterCTEs.append(("f__profile",
            "SELECT DISTINCT resource_id FROM idx_string WHERE resource_type = '\(resourceType)' AND param_name = '_profile' AND (\(or))"))
    }

    return (filterCTEs, whereConditions)
}
