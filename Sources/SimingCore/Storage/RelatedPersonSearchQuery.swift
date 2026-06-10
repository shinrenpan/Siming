import Foundation

public struct RelatedPersonSearchQuery: Sendable {

    // ── Filters ───────────────────────────────────────────────────────────────

    // token params
    public var active: [TokenParam]
    public var activeNot: [TokenParam]
    public var gender: [TokenParam]
    public var genderNot: [TokenParam]
    public var identifier: [IdentifierParam]
    public var identifierNot: [IdentifierParam]  // identifier:not modifier
    public var relationship: [TokenParam]
    public var relationshipNot: [TokenParam]
    public var phone: [TokenParam]
    public var phoneNot: [TokenParam]
    public var email: [TokenParam]
    public var emailNot: [TokenParam]
    public var telecom: [TokenParam]
    public var telecomNot: [TokenParam]
    public var addressUse: [TokenParam]
    public var addressUseNot: [TokenParam]

    // string params (single optional, supports modifiers via StringParam.parse)
    public var name: StringParam?
    public var address: StringParam?
    public var addressCity: StringParam?
    public var addressCountry: StringParam?
    public var addressPostalcode: StringParam?
    public var addressState: StringParam?

    // date params
    public var birthdate: [DateParam]

    // reference params
    public var patient: String?

    // system params
    public var id: [String]
    public var lastUpdated: [DateParam]
    public var tokenTexts: [TokenTextParam]
    public var missing: [String: Bool]
    public var chains: [ChainedParam]
    public var has: [HasParam]
    public var meta: MetaSearchParams           // _tag / _security / _profile

    // ── Pagination / sort ─────────────────────────────────────────────────────

    public var totalMode: TotalMode
    public var count: Int
    public var sortKeys: [SortKey]
    public var cursor: SearchCursor?

    public init(
        active: [TokenParam] = [],
        activeNot: [TokenParam] = [],
        gender: [TokenParam] = [],
        genderNot: [TokenParam] = [],
        identifier: [IdentifierParam] = [],
        identifierNot: [IdentifierParam] = [],
        relationship: [TokenParam] = [],
        relationshipNot: [TokenParam] = [],
        phone: [TokenParam] = [],
        phoneNot: [TokenParam] = [],
        email: [TokenParam] = [],
        emailNot: [TokenParam] = [],
        telecom: [TokenParam] = [],
        telecomNot: [TokenParam] = [],
        addressUse: [TokenParam] = [],
        addressUseNot: [TokenParam] = [],
        name: StringParam? = nil,
        address: StringParam? = nil,
        addressCity: StringParam? = nil,
        addressCountry: StringParam? = nil,
        addressPostalcode: StringParam? = nil,
        addressState: StringParam? = nil,
        birthdate: [DateParam] = [],
        patient: String? = nil,
        id: [String] = [],
        lastUpdated: [DateParam] = [],
        tokenTexts: [TokenTextParam] = [],
        missing: [String: Bool] = [:],
        chains: [ChainedParam] = [],
        has: [HasParam] = [],
        meta: MetaSearchParams = MetaSearchParams(),
        totalMode: TotalMode = .accurate,
        count: Int = 20,
        sortKeys: [SortKey] = [.default],
        cursor: SearchCursor? = nil
    ) {
        self.active             = active
        self.activeNot          = activeNot
        self.gender             = gender
        self.genderNot          = genderNot
        self.identifier         = identifier
        self.identifierNot      = identifierNot
        self.relationship       = relationship
        self.relationshipNot    = relationshipNot
        self.phone              = phone
        self.phoneNot           = phoneNot
        self.email              = email
        self.emailNot           = emailNot
        self.telecom            = telecom
        self.telecomNot         = telecomNot
        self.addressUse         = addressUse
        self.addressUseNot      = addressUseNot
        self.name               = name
        self.address            = address
        self.addressCity        = addressCity
        self.addressCountry     = addressCountry
        self.addressPostalcode  = addressPostalcode
        self.addressState       = addressState
        self.birthdate          = birthdate
        self.patient            = patient
        self.id                 = id
        self.lastUpdated        = lastUpdated
        self.tokenTexts         = tokenTexts
        self.missing            = missing
        self.chains             = chains
        self.has                = has
        self.meta               = meta
        self.totalMode          = totalMode
        self.count              = count
        self.sortKeys       = sortKeys
        self.cursor             = cursor
    }

    // ── Sort order ────────────────────────────────────────────────────────────

    /// Parses a comma-separated `_sort` value into sort keys.
    /// Unrecognised tokens are ignored; empty result falls back to `[.default]`.
    public static func parseSortKeys(_ raw: String) -> [SortKey] {
        let keys = raw.split(separator: ",").compactMap { token -> SortKey? in
            let s = String(token).trimmingCharacters(in: .whitespaces)
            let desc = s.hasPrefix("-")
            let name = desc ? String(s.dropFirst()) : s
            let src: SortKeySource? = switch name {
            case "_lastUpdated":    .lastUpdated
            case "_id":             .resourceId
            case "birthdate":  .date(paramName: "birthdate")
            case "name":  .string(paramName: "name")
            case "family":  .string(paramName: "name")
            default:                nil
            }
            guard let src else { return nil }
            return SortKey(source: src, descending: desc)
        }
        return keys.isEmpty ? [.default] : keys
    }

    public typealias TokenParam      = ObservationSearchQuery.TokenParam
    public typealias StringParam     = PatientSearchQuery.StringParam
    public typealias DateParam       = PatientSearchQuery.BirthdateParam
    public typealias IdentifierParam = PatientSearchQuery.IdentifierParam
    public typealias TotalMode       = PatientSearchQuery.TotalMode
}
