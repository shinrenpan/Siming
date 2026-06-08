# FHIR R4 Implementation Notes

Per-resource search parameter implementation details and known gaps.
**Do not hand-edit this during a round — update after implementation is complete.**

---

## Cross-resource features

### `_sort` support

| Resource | Supported sort params |
|---|---|
| Patient | `_lastUpdated`, `name`, `family`, `birthdate`, `_id` |
| Observation | `date`, `status`, `code`, `_id` |
| Encounter | `date`, `status`, `code`, `_id` |
| Procedure | `date`, `status`, `code`, `_id` |
| DiagnosticReport | `date`, `status`, `code`, `_id` |
| Immunization | `date`, `status`, `code` (`vaccine-code` param), `_id` |
| Condition | `date` (onset), `clinical-status`, `code`, `_id` |
| MedicationRequest | `date` (authoredOn), `status`, `code`, `_id` |
| AllergyIntolerance | `date` (recordedDate), `clinical-status`, `code`, `_id` |
| Practitioner | `_lastUpdated`, `name`, `_id` |
| Organization | `_lastUpdated`, `name`, `_id` |
| Location | `_lastUpdated`, `name`, `status`, `_id` |
| RelatedPerson | `_lastUpdated`, `birthdate`, `_id` |
| ServiceRequest | `date` (authored), `status`, `code`, `_lastUpdated`, `_id` |
| Specimen | `date` (collected), `status`, `_lastUpdated`, `_id` |
| DocumentReference | `date`, `status`, `_lastUpdated`, `_id` |
| CarePlan | `date` (period), `status`, `_lastUpdated`, `_id` |
| Goal | `date` (start-date), `status` (lifecycle-status), `_lastUpdated`, `_id` |
| MedicationStatement | `date` (effective), `status`, `code`, `_lastUpdated`, `_id` |
| FamilyMemberHistory | `date`, `status`, `code`, `_lastUpdated`, `_id` |
| Medication | `status`, `code`, `_lastUpdated`, `_id` |
| Appointment | `date` (start), `status`, `_lastUpdated`, `_id` |
| MedicationAdministration | `date` (effective-time), `status`, `code`, `_lastUpdated`, `_id` |
| All resources | `_lastUpdated`, `_id` |

### Meta search parameters (`_tag`, `_security`, `_profile`)

Supported on **all 23 resources** (FHIR R4 §3.2.2). Implemented via shared infrastructure in `MetaSearchParams.swift`.

| Param | FHIR field | Index | `:not` |
|---|---|---|---|
| `_tag` | `meta.tag[]: Coding` | idx_token (`param_name='_tag'`) | ✓ `_tag:not` |
| `_security` | `meta.security[]: Coding` | idx_token (`param_name='_security'`) | ✓ `_security:not` |
| `_profile` | `meta.profile[]: canonical` | idx_string (`param_name='_profile'`, exact URI) | — |

- **Write path**: `appendMetaParams(&params, meta: resource.meta)` called in each store's `write()` after the resource-specific extractor. Note: stores that strip `resource.meta` before extraction must capture `originalMeta` first.
- **Search path**: `metaFilterCTEs(resourceType:, meta:, bind:)` appends filter CTEs and NOT IN conditions into the standard SQL builder.
- **Strict mode**: `unknownParams()` globally accepts `_tag`, `_security`, `_profile` — no per-route change needed.
- `_tag` / `_security` token format: `system|code`, `|code`, `code` (same as standard token params).

### `identifier:not` across all resources

Supported on **all 23 resources** (FHIR R4 §3.2.1). Each `XxxSearchQuery` has `identifierNot: [IdentifierParam]`. Implemented as a `NOT IN` subquery against `idx_token` with `param_name='identifier'`. Three formats: `system|code`, `|code` (null system), `code` (any system).

### Chained search and `_has`

Fully implemented for all 23 resources. Child param types mapped in `chainChildParamType` in `ChainedParam.swift`. Includes: `effective-time`, `reason-given`, `reason-not-given`, `reason-code`.

### `_include` / `_revinclude`

Fully implemented for all 23 resources via `IncludeResolver` (queries `idx_reference` directly).

- **`:iterate` modifier** — `_include:iterate` and `_revinclude:iterate` resolve recursively (max 5 levels). Each pass uses the newly-discovered resources of the matching `sourceType` as the next frontier; already-processed IDs are skipped to prevent cycles.
- **Wildcard `*`** — `_include=Patient:*` or `_revinclude=Observation:*` drops the `param_name` filter so all reference params of the source type are followed.
- `search.mode` is set correctly: `"match"` for main results, `"include"` for included resources.

### Date `ap` (approximate) prefix

Supported on **all** date parameters across all 23 resources, including `_lastUpdated`.

- **Semantics:** ±10% of the precision period. `delta = (dateEnd − dateStart) × 0.1`. idx_date: `date_start <= apExpandedEnd AND date_end >= apExpandedStart`. `last_updated`: `BETWEEN apExpandedStart AND apExpandedEnd`.
- Computed properties `apExpandedStart` / `apExpandedEnd` on `BirthdateParam`.

### String parameter modifiers

All string-type search params support FHIR R4 modifiers. Dispatch in both `buildSearchSQL` and `buildCountSQL`:

| Modifier | SQL pattern | Index used |
|---|---|---|
| (default / startsWith) | `lower(value) LIKE lower('foo%')` | `idx_string_lower_prefix_idx` (btree) |
| `:contains` / `:text` | `value ILIKE '%foo%'` | `idx_string_trgm_idx` (trigram GIN) |
| `:exact` | `value = 'foo'` | `idx_string_exact_idx` (btree) |

Resources and params with modifier support:
- **Patient** — `name`, `family`, `given`, `address`, `address-city`, `address-state`, `address-country`, `address-postalcode`, `phonetic`
- **Observation** — `value-string`
- **DocumentReference** — `description`
- **Immunization** — `series`, `lot-number`
- **Condition** — `onset-info`, `abatement-string`
- **Practitioner, Organization, Location, RelatedPerson** — all `name` / `address` / `phonetic` variants

`PatientSearchQuery.StringParam` is the shared type (public init, public `Modifier` enum). All other resources alias it via `typealias StringParam = PatientSearchQuery.StringParam`.

### Token `:not` modifier — `identifier:not`

`identifier:not` is supported on **all 23 resources** (FHIR R4 §3.2.1). Implemented as a `NOT IN` subquery against `idx_token`:

```sql
r.id NOT IN (
  SELECT resource_id FROM idx_token
  WHERE resource_type = 'Patient' AND param_name = 'identifier'
  AND (code = $n [AND system = $m | AND system IS NULL])
)
```

Three wire formats accepted: `system|code`, `|code` (null system), `code` (any system — no system condition). Multiple values in one param are OR'd before the NOT IN. Each SearchQuery has `identifierNot: [IdentifierParam]`; Routes accept `identifier:not` in knownParams and strict-mode whitelist.

### Patient compartment membership

**Not in compartment:** Location, Medication, Practitioner, Organization (per FHIR R4 spec — not resource-connected to a Patient).

**In compartment (19 resources):** Observation, Encounter, Condition, MedicationRequest, AllergyIntolerance, Procedure, DiagnosticReport, Immunization, RelatedPerson, ServiceRequest, Specimen, DocumentReference, CarePlan, Goal, MedicationStatement, FamilyMemberHistory, Appointment, MedicationAdministration, plus Patient itself.

Appointment uses `participant.actor`; MedicationAdministration uses `subject.where(resolve() is Patient)` — both use `patient` param_name in the index.

---

## Per-resource notes

### Patient

- `deceased` — boolean token (code `"true"`/`"false"`) stored in idx_token.
- `death-date` — date param in idx_date; only indexed when deceased is a dateTime (not boolean).
- `email` / `phone` — stored via telecom extractor with `param_name="telecom"` and the system value; store queries `system='phone'` or `system='email'`.
- `organization` — `managingOrganization` reference via idx_reference; supports both `ResourceType/id` and bare `id` forms.
- `general-practitioner` — `generalPractitioner[]` reference via idx_reference; same type-qualified matching.
- `link` — `link[].other` reference via idx_reference.
- `language` / `language:not` — `communication[].language` token OR/NOT via idx_token; supports `system|code`, `|code` (null system), and bare `code` forms.

### Observation

**Reference params** (idx_reference): `based-on`, `derived-from`, `device`, `focus`, `has-member`, `part-of`, `specimen`.

**Token params** (idx_token, `:not` modifier supported): `combo-code` (indexes both `obs.code` AND `obs.component[].code`), `method`, `value-concept`, `combo-value-concept` (both `obs.value as CodeableConcept` AND `obs.component[].value as CodeableConcept`), `data-absent-reason` (`obs.dataAbsentReason`), `combo-data-absent-reason` (both `obs.dataAbsentReason` AND `obs.component[].dataAbsentReason`), `component-data-absent-reason` (`obs.component[].dataAbsentReason`), `component-value-concept` (`obs.component[].value as CodeableConcept`).

**Quantity params** (idx_quantity): `value-quantity` (`obs.value as Quantity`), `combo-value-quantity` (both `obs.value as Quantity` AND `obs.component[].value as Quantity`), `component-value-quantity` (`obs.component[].value as Quantity`; SampledData case silently skipped).

**Root-level composite params** (INTERSECT-per-pair, UNION across OR values; no new index table required — reuses existing idx_token/idx_quantity/idx_string/idx_date): `code-value-quantity` (code token `$` value-quantity quantity), `code-value-string` (code token `$` value-string prefix), `code-value-concept` (code token `$` value-concept token), `code-value-date` (code token `$` value-date date). Wire format: `code-value-quantity=29463-7$ge60`. Multiple values OR'd.

**Component/combo composite params** (idx_composite tuple match): `component-code-value-quantity`, `component-code-value-concept`, `combo-code-value-quantity`, `combo-code-value-concept` — use `idx_composite` table (migration `0005_composite_idx.sql`). Each row stores one `(code1, value2/code2)` tuple from a single component or root element. Query: simple OR across tuple conditions — no INTERSECT needed. Wire format: `component-code-value-quantity=8480-6$ge100`. `combo-code-value-quantity` indexes both root (`obs.value as Quantity`) and each component.

**Date params** (idx_date): `value-date` (`obs.value as DateTime`).

**String params** (idx_string): `value-string` (`obs.value as string`).

### Encounter

All of the following are fully implemented:
- `participant`, `practitioner` — both index `Encounter.participant[].individual` but with different `param_name`.
- `account` — `enc.account[]` via idx_reference.
- `appointment` — `enc.appointment[]` via idx_reference.
- `episode-of-care` — `enc.episodeOfCare[]` via idx_reference.
- `reason-reference` — `enc.reasonReference[]` via idx_reference.
- `location-period` — `enc.location[].period` (start/end) via idx_date.
- `participant-type` — `enc.participant[].type[].coding[]` via idx_token with `:not`.
- `special-arrangement` — `enc.hospitalization.specialArrangement[].coding[]` via idx_token with `:not`.
- `reason-code`, `part-of`, `service-provider`, `based-on`, `location`, `diagnosis` — fully implemented.

- `length` — `enc.length` (Duration extends Quantity) via idx_quantity; supports all prefix comparisons including `ap` (±10%).

### Condition

- `asserter` — `cond.asserter` via idx_reference.
- `evidence-detail` — `cond.evidence[].detail[]` via idx_reference.
- `body-site` — `cond.bodySite[].coding[]` via idx_token with `:not`.
- `evidence` — `cond.evidence[].code[].coding[]` via idx_token with `:not`.
- `severity` — `cond.severity.coding[]` via idx_token with `:not`.
- `stage` — `cond.stage[].summary.coding[]` via idx_token with `:not`.
- `onset-info` — `cond.onset` when string via idx_string (prefix match).
- `abatement-string` — `cond.abatement` when string via idx_string (prefix match).

- `onset-age` — `cond.onset` when `.age(Age)` case via idx_quantity; `.range` and other onset cases silently skipped.
- `abatement-age` — `cond.abatement` when `.age(Age)` case via idx_quantity; other abatement cases silently skipped.

### MedicationRequest

- `intended-dispenser` — `mr.dispenseRequest.performer` via idx_reference.
- `intended-performer` — `mr.performer` via idx_reference.
- `intended-performertype` — `mr.performerType.coding[]` via idx_token with `:not`.
- `medication` (reference) — `mr.medication` when it is a Reference via idx_reference (distinct from `code` which indexes medication as CodeableConcept).

- `date` — `dosageInstruction[].timing.event[]` (DateTime array) via idx_date. Only `timing.event` is indexed; `timing.repeat.bounds` and other Timing sub-fields are not.

### AllergyIntolerance

- `asserter`, `recorder` — reference params via idx_reference, fully implemented.

### Procedure

- `based-on`, `location`, `part-of`, `reason-reference` — reference params via idx_reference.
- `reason-code` — token param via idx_token with `:not`.
- `instantiates-canonical`, `instantiates-uri` — stored in idx_string (exact URL match).

### DiagnosticReport

- `based-on`, `media`, `result`, `results-interpreter`, `specimen` — reference params via idx_reference.
- `conclusion` — token param (indexes `conclusionCode[].coding[]`) via idx_token with `:not`.

### Immunization

- `location`, `manufacturer`, `reaction`, `reason-reference` — reference params via idx_reference.
- `reason-code`, `status-reason`, `target-disease` — token params via idx_token with `:not`.
- `series` — string param via idx_string.
- `reaction-date` — date param via idx_date.

### Practitioner

- `phone` / `email` — indexes all telecom entries regardless of system (generator strips `.where()` — known limitation, false positives unlikely in practice).
- `phonetic` — prefix/contains match on name fields; same data as `name` param but stored with `param_name="phonetic"` in idx_string.

### Organization

- `phonetic` — indexes `org.name` and `org.alias[]` with `param_name="phonetic"` in idx_string.
- `endpoint` — indexes `org.endpoint[]` references via idx_reference.

### Location

- `endpoint` — fully implemented via idx_reference.
- `near` (geospatial) — **TODO stub** (no-op extractor); requires PostGIS extension.

### RelatedPerson

- `phonetic` — alias for `name`; indexes same HumanName fields, stored with `param_name="phonetic"` in idx_string (not a separate index).

### ServiceRequest

- `order-detail` — `sr.orderDetail[].coding[]` via idx_token with `:not` modifier.
- `instantiates-canonical` — `sr.instantiatesCanonical[]` via idx_string (case-insensitive URL match via `lower(value) = lower($n)`).
- `instantiates-uri` — indexes `sr.instantiatesUri[]` via idx_string (exact URL match).

### DocumentReference

- Swift field `description_fhir` maps to FHIR search param `description`.
- Fully implemented: `contenttype`, `format`, `language`, `setting`, `custodian`, `authenticator`, `relatesto` (reference — `relatesTo[].target` via idx_reference), `relation` (token — `relatesTo[].code` with system `http://hl7.org/fhir/document-relationship-type` via idx_token), `related` (`doc.context.related[]` via idx_reference).
- `location` — `content[].attachment.url` via idx_string (URI type — exact match `value = $n`).
- `relationship` — composite of `relatesto` (reference) + `relation` (token); stores per-entry `(relation_code, target_ref)` tuple in idx_composite with `string2 = target_ref`. Wire format: `relationship=DocumentReference/targetId$appends`. Per-entry tuple matching eliminates false positives when a document has multiple relatesTo entries with different codes/targets.

### CarePlan

- `activity-date` — indexes `activity[].detail.scheduled[x]`: `.period` (start/end) and `.timing` (event dates) stored in idx_date; `.string` case silently skipped.
- `instantiates-canonical`, `instantiates-uri` — stored in idx_string (exact URL match).

### Goal

- `start-date` — indexes `start[x]` only when `startDate` (FHIRDate); `startCodeableConcept` case silently skipped.
- `target-date` — indexes `target.due[x]` only when `dueDate` (FHIRDate); `dueDuration` case silently skipped.

### FamilyMemberHistory

- `instantiates-canonical`, `instantiates-uri` — stored in idx_string (exact URL match).

### Appointment

- `patient`, `practitioner`, `location`, `actor` — all index the same `participant.actor` field but with different `param_name`; store filters by `ref_type` to distinguish (e.g., `patient=Patient/123` → `ref_type='Patient' AND ref_id='123'`).
- `supporting-info` — searches `supportingInformation[]` references via idx_reference.
- `based-on` — `basedOn` (ServiceRequest) reference via idx_reference.
- `reason-reference` — `reasonReference[]` (Condition/Procedure) references via idx_reference.

### MedicationAdministration

- `effective-time` — maps to `effective[x]` (dateTime or Period) stored in idx_date with `param_name="effective-time"`.
- `code` — searches medication as CodeableConcept only.
- `medication` (reference) — searches when medication is a Reference; stored separately from `code`.
