# Roadmap

The single place recording **what is not done, and why**. Everything Siming
already does belongs in [`README.md`](../README.md) and the
[wiki](https://github.com/shinrenpan/Siming/wiki) — not here.

No dates and no priority ordering: an unmaintained schedule is worse than none.
Entries move out of this file when they ship, or when the decision changes.

---

## Known defects

### Composite-backed search returns wrong results

7 integration tests fail on `main`. All of them exercise `idx_composite`:

| Test | Expected | Actual |
|---|---|---|
| `ObservationStoreTests` — component/combo × quantity/concept (4 tests) | 1 | **0** |
| `DocumentReferenceStoreTests.testSearch_byRelationship_matchesExactTuple` | 1 | **0** |
| `ServiceRequestStoreTests.testSearch_byOrderDetail_returnsMatchOnly` | 1 | **0** |
| `ServiceRequestStoreTests.testSearch_byOrderDetailNot_excludesCorrectly` | 1 | **2** |

Six return too few, one returns too many — possibly two faces of one bug.

**Already ruled out** (do not re-investigate):

- `idx_composite` table and its indexes exist; migration `0005_composite_idx` is applied
- The write path works — the table holds rows, and the specific values the failing
  tests search for (e.g. `value2 = 120` under `component-code-value-quantity`) are present
- `clear_index_rows` **does** delete from `idx_composite` (`0005` re-creates the function),
  so stale rows are not left behind on update or delete
- `ObservationSearchQuery.QuantityParam.parse` handles `ge100` correctly
- The `param_name` string literals match between the extractor and the query builder

**Remaining suspect:** the search SQL assembly — the composite filter CTEs in
`ObservationStore.buildSearchSQL` (and the equivalents in `DocumentReferenceStore` /
`ServiceRequestStore`) and how they combine in `buildIdsInner`.

**Separate, smaller bug found while investigating:** `TestDatabase.truncate()`
(`Tests/SimingIntegrationTests/TestDatabase.swift`) omits `idx_composite`, so orphan
composite rows accumulate across tests. Worth fixing on its own, but fixing it alone
does **not** make the 7 tests pass — verified.

---

## Gaps with a decision still open

### Batch bundles

Siming implements `Bundle.type = transaction` but not `batch`. This blocks the
offline-sync design of at least one downstream client. Deliberately kept out of the
`PractitionerRole` work so that change stayed reviewable.

Open question: whether batch is worth the divergent error semantics (a batch keeps
going after a failed entry; a transaction rolls everything back).

---

## Backlog

Implemented when there is a reason to, not on spec:

- **`MedicationDispense`** — completes the medication workflow. Follows the existing
  store/route patterns, so implementation cost is low and clinical value is high.

---

## Partial by design

### `PractitionerRole`

Only the `practitioner` reference param is indexed. The other 12 R4 params
(`active`, `date`, `email`, `endpoint`, `identifier`, `location`, `organization`,
`phone`, `role`, `service`, `specialty`, `telecom`) are live `// TODO: unhandled`
markers in `Sources/SimingCore/Generated/PractitionerRole+SearchExtractor.swift`.

A visible gap is worth more than a silent stub. To close one, write its case in
`Sources/SimingGenerator/PractitionerRoleHandlers.swift` and regenerate — never
hand-edit the generated file.

Note that `GET /metadata` still advertises all 13 params: the CapabilityStatement is
built from `packages/*.tgz` at startup and is independent of extractor coverage. That
is true of every resource carrying TODO params, not just this one.

---

## Planned, but outside this repo

- **NHI terminology as external FHIR packages** — Siming needs no code changes; the
  existing package loader already handles them. That work belongs in a separate
  package project.

---

## Not planned

Resources: `Composition`, `CareTeam`, `Provenance`, `Coverage`, `ImagingStudy`,
`Device`, `Media`, `MessageHeader`, `QuestionnaireResponse`.

Capabilities: R5, multi-tenancy, Subscriptions/Notifications, and a terminology
server (CodeSystem/ValueSet CRUD plus `$expand` / `$lookup`) — Siming is a clinical
data server; terminology belongs to a separate service layer.

Ecosystem: no first-party frontend. Downstream clients connect over the standard
FHIR API.

Reopening any of these needs a reason that did not exist when it was ruled out —
not just a new opportunity to build it.
