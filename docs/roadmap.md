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

### `_summary=count` ignores filters the same query applies without it

`buildCountSQL` is a hand-maintained duplicate of `buildSearchSQL`, taken only when
`count == 0` (which is what `_summary=count` forces). The two have drifted, so the
same query string answers differently depending on whether `_summary=count` is present:

```
GET /MedicationRequest?identifier=urn:x|mr1               -> 1 entry,  total 1   (correct)
GET /MedicationRequest?identifier=urn:x|mr1&_summary=count -> total 2            (wrong)
```

Comparing `query.*` references between the two builders, 20 of the 24 stores drift:

- **all 20** drop `_lastUpdated` and every `:missing`
- nearly all drop every `:not` modifier
- `identifier` is dropped by AllergyIntolerance, DiagnosticReport, Immunization,
  MedicationRequest, Procedure
- MedicationRequest additionally drops `encounter` and `requester`

Clean (no drift): Patient, Observation, Encounter, Condition.

Searches that return entries are unaffected — with `_total=accurate` the count comes
from the same SQL as the page. Only the count-only path is wrong.

Patching the 20 stores would re-create the drift on the next parameter added. The fix
is structural: have the count path reuse `buildSearchSQL`'s filter assembly instead of
duplicating it. Scoped as its own change because it touches every store.

The deleted-row half of this path is already fixed — both builders now go through
`buildIdsInner` / `buildCountIdsInner` in `MultiSort.swift`.

---

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

- **A reindex command.** Index rows are only rewritten when a resource is written, so
  a change to an extractor leaves every existing row stale until someone touches it.
  That already bit once: the `period` extractors were building `DateComponents` without
  a `timeZone`, so every indexed period was stored shifted by the host's UTC offset, and
  fixing the generator did not fix the rows already written. Today the only remedy is to
  reload the data. `SimingServer --reindex <ResourceType>` — read current versions, re-run
  the extractor, `replaceIndexRows` — would be small and is needed by any future extractor
  correction.

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

### Interpreting a timezone-less date search value as the server's local timezone

Raised from downstream: on a `TZ=Asia/Taipei` host, `Encounter?date=ge2026-09-05`
misses visits that started at 00:03 local, because Siming reads a bare date as UTC.
The claim was that R4 requires the server's local timezone instead.

The spec text (R4 §3.1.1.4.7) is narrower than that:

> Where possible, the system should correct for time zones when performing queries.
> Dates do not have time zones, and time zones should not be considered. Where
> **both** search parameters **and** resource element date times do not have time
> zones, the servers local time zone should be assumed.

The "server's local time zone" sentence is conditioned on *both* sides lacking a
timezone. The reported case is a bare search value against `Encounter.period.start`,
which carries `+08:00` — so the clause does not reach it. And in the case the clause
does cover (date-only on both sides, e.g. `Patient?birthdate=1990-06-15` against
`Patient.birthDate`), Siming applies UTC to both sides, so the offset cancels and the
answer is identical to what a local-timezone server would return. That is the same
sentence's leading instruction: time zones should not be considered.

The spec also flags the whole area as unresolved — "the FHIR implementation community
is still investigating and debating the best way to handle time zones… future versions
of this specification may impose rules".

**Decision: keep UTC, on both the index and the query side.** Adopting a local
timezone would have to apply to both — a query-side-only change breaks the date-only
case above — and a timezone-dependent *index* is precisely the defect just removed
from the `period` extractors, with the added cost that changing the setting would
require a reindex. A client that means a local day should say so: sending
`ge2026-09-05T00:00:00+08:00` is unambiguous under every reading, and is what the
downstream client settled on.

Reopen if a deployment needs `TZ`-relative semantics for date-only values against
timed elements. The shape would be a configured (never inherited) server timezone
applied symmetrically to extraction and parsing, plus a reindex.

---

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
