# Roadmap

The single place recording **what is not done, and why**. Everything Siming
already does belongs in [`README.md`](../README.md) and the
[wiki](https://github.com/shinrenpan/Siming/wiki) — not here.

No dates and no priority ordering: an unmaintained schedule is worse than none.
Entries move out of this file when they ship, or when the decision changes.

---

## Known defects

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

### A `Period` with neither bound matches every date search

`{"effectivePeriod": {}}` — a Period carrying neither `start` nor `end` — is
indexed as `distantPast .. distantFuture`, so the resource is returned by every
`date=` query, including ones it has no business matching
(`?effective=eq1900-01-01` finds it). Every period extractor behaves this way
(11 generated files); it is consistent, not a two-resource anomaly.

The fix is a guard before the append: emit no row when both bounds are absent —
a resource with no date should be absent from date searches, which is also what
`:missing=true` already means.

Not done yet, deliberately. It needs the same edit at every period site in
`Sources/SimingGenerator/`, each with different surrounding control flow
(`return` / `continue` / `switch` case), and that shape of per-site hand-editing
is where two regressions were introduced during the search-correctness round —
including one in a block that had just been edited. Weighed against an input that
does not occur in real data, the change is not worth making unforced. Do it when
a period extractor is being touched for another reason.

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

### Composite search params beyond `code-value-*`

`component-code-value-quantity`, `component-code-value-concept`,
`combo-code-value-quantity`, `combo-code-value-concept` (Observation) and `relationship`
(DocumentReference) are unsupported: an unknown param like any other — ignored under
lenient handling, 400 under `Prefer: handling=strict`. The four root-level
`code-value-*` params do work (they intersect existing index tables).

Until 1.4.2 the router accepted them and returned an empty result, because the
generator drops every `composite` SearchParameter (`BundleTypes.swift`) and nothing ever
wrote `idx_composite`. ServiceRequest `order-detail` was removed at the same time: it is
not an R4 search param at all.

Reopen when a client needs them. The shape: stop filtering `composite` in the generator,
emit the composite handlers already in `ObservationHandlers.swift` /
`DocumentReferenceHandlers.swift` (they write `SearchParams.composites`, which
`replaceIndexRows` sends to `idx_composite`), and restore the query side from git
history (before 1.4.2). The table, its index and `clear_index_rows` support remain.

