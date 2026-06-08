import Foundation

public struct ConditionSearchQuery: Sendable {

    // ── Filters ───────────────────────────────────────────────────────────────

    public var subject: String?                      // patient/subject reference
    public var encounter: String?                    // encounter reference
    public var clinicalStatus: [TokenParam]          // token OR: "active,recurrence,relapse,..."
    public var clinicalStatusNot: [TokenParam]       // clinical-status:not modifier
    public var verificationStatus: [TokenParam]      // token OR: "unconfirmed,confirmed,refuted,..."
    public var verificationStatusNot: [TokenParam]   // verification-status:not modifier
    public var category: [TokenParam]                // CodeableConcept token OR
    public var categoryNot: [TokenParam]             // category:not modifier
    public var code: [TokenParam]                    // CodeableConcept token OR
    public var codeNot: [TokenParam]                 // code:not modifier
    public var identifier: [IdentifierParam]
    public var onsetDate: [DateParam]                // onset-date range filter
    public var abatementDate: [DateParam]            // abatement-date range filter
    public var recordedDate: [DateParam]             // recorded-date range filter
    public var asserter: String?                     // Condition.asserter reference
    public var evidenceDetail: String?               // Condition.evidence.detail reference
    public var bodySite: [TokenParam]                // Condition.bodySite token OR
    public var bodySiteNot: [TokenParam]             // body-site:not modifier
    public var evidence: [TokenParam]                // Condition.evidence.code token OR
    public var evidenceNot: [TokenParam]             // evidence:not modifier
    public var severity: [TokenParam]                // Condition.severity token OR
    public var severityNot: [TokenParam]             // severity:not modifier
    public var stage: [TokenParam]                   // Condition.stage.summary token OR
    public var stageNot: [TokenParam]                // stage:not modifier
    public var onsetAge: [QuantityParam]              // Condition.onset as Age quantity filter
    public var abatementAge: [QuantityParam]          // Condition.abatement as Age quantity filter
    public var onsetInfo: String?                    // Condition.onset as string (prefix)
    public var abatementString: String?              // Condition.abatement as string (prefix)
    public var id: [String]                          // _id filter (OR)
    public var lastUpdated: [DateParam]              // _lastUpdated range filter
    public var missing: [String: Bool]               // param:missing=true/false
    public var chains: [ChainedParam]                // chained search: subject.name=Wang, etc.
    public var has: [HasParam]                       // _has modifier: reverse chaining

    // ── Pagination / sort ─────────────────────────────────────────────────────

    public var totalMode: TotalMode
    public var count: Int
    public var sort: SortOrder
    public var cursor: SearchCursor?

    public init(
        subject: String? = nil,
        encounter: String? = nil,
        clinicalStatus: [TokenParam] = [],
        clinicalStatusNot: [TokenParam] = [],
        verificationStatus: [TokenParam] = [],
        verificationStatusNot: [TokenParam] = [],
        category: [TokenParam] = [],
        categoryNot: [TokenParam] = [],
        code: [TokenParam] = [],
        codeNot: [TokenParam] = [],
        identifier: [IdentifierParam] = [],
        onsetDate: [DateParam] = [],
        abatementDate: [DateParam] = [],
        recordedDate: [DateParam] = [],
        asserter: String? = nil,
        evidenceDetail: String? = nil,
        bodySite: [TokenParam] = [],
        bodySiteNot: [TokenParam] = [],
        evidence: [TokenParam] = [],
        evidenceNot: [TokenParam] = [],
        severity: [TokenParam] = [],
        severityNot: [TokenParam] = [],
        stage: [TokenParam] = [],
        stageNot: [TokenParam] = [],
        onsetAge: [QuantityParam] = [],
        abatementAge: [QuantityParam] = [],
        onsetInfo: String? = nil,
        abatementString: String? = nil,
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
        self.subject              = subject
        self.encounter            = encounter
        self.clinicalStatus       = clinicalStatus
        self.clinicalStatusNot    = clinicalStatusNot
        self.verificationStatus   = verificationStatus
        self.verificationStatusNot = verificationStatusNot
        self.category             = category
        self.categoryNot          = categoryNot
        self.code                 = code
        self.codeNot              = codeNot
        self.identifier           = identifier
        self.onsetDate            = onsetDate
        self.abatementDate        = abatementDate
        self.recordedDate         = recordedDate
        self.asserter             = asserter
        self.evidenceDetail       = evidenceDetail
        self.bodySite             = bodySite
        self.bodySiteNot          = bodySiteNot
        self.evidence             = evidence
        self.evidenceNot          = evidenceNot
        self.severity             = severity
        self.severityNot          = severityNot
        self.stage                = stage
        self.stageNot             = stageNot
        self.onsetAge             = onsetAge
        self.abatementAge         = abatementAge
        self.onsetInfo            = onsetInfo
        self.abatementString      = abatementString
        self.id                   = id
        self.lastUpdated          = lastUpdated
        self.missing              = missing
        self.chains               = chains
        self.has                  = has
        self.totalMode            = totalMode
        self.count                = count
        self.sort                 = sort
        self.cursor               = cursor
    }

    public typealias TokenParam      = ObservationSearchQuery.TokenParam
    public typealias QuantityParam   = ObservationSearchQuery.QuantityParam
    public typealias DateParam       = PatientSearchQuery.BirthdateParam
    public typealias SortOrder       = PatientSearchQuery.SortOrder
    public typealias SearchCursor    = PatientSearchQuery.SearchCursor
    public typealias IdentifierParam = PatientSearchQuery.IdentifierParam
    public typealias TotalMode       = PatientSearchQuery.TotalMode
}
