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

### Chained search and `_has`

Fully implemented for all 23 resources. Child param types mapped in `chainChildParamType` in `ChainedParam.swift`. Includes: `effective-time`, `reason-given`, `reason-not-given`, `reason-code`.

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

### Observation

**Reference params** (idx_reference): `based-on`, `derived-from`, `device`, `focus`, `has-member`, `part-of`, `specimen`.

**Token params** (idx_token, `:not` modifier supported): `combo-code` (indexes both `obs.code` AND `obs.component[].code`), `method`, `value-concept`, `data-absent-reason` (`obs.dataAbsentReason`), `combo-data-absent-reason` (both `obs.dataAbsentReason` AND `obs.component[].dataAbsentReason`), `component-data-absent-reason` (`obs.component[].dataAbsentReason`), `component-value-concept` (`obs.component[].value as CodeableConcept`).

**Quantity params** (idx_quantity): `value-quantity` (`obs.value as Quantity`), `combo-value-quantity` (`obs.value as Quantity` — component part not yet indexed per FHIR spec gap; search wired and functional), `component-value-quantity` (`obs.component[].value as Quantity`; SampledData case silently skipped).

**Root-level composite params** (INTERSECT-per-pair, UNION across OR values; no new index table required — reuses existing idx_token/idx_quantity/idx_string/idx_date): `code-value-quantity` (code token `$` value-quantity quantity), `code-value-string` (code token `$` value-string prefix), `code-value-concept` (code token `$` value-concept token), `code-value-date` (code token `$` value-date date). Wire format: `code-value-quantity=29463-7$ge60`. Multiple values OR'd.

**TODO stubs (component/combo composite):** `combo-code-value-concept`, `combo-code-value-quantity`, `component-code-value-concept`, `component-code-value-quantity` — require per-component tuple matching (composite index or JSON scan); deferred.

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
- **TODO stubs:** `relationship` (composite of relatesto + relation — requires composite search support not yet implemented).

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

### MedicationAdministration

- `effective-time` — maps to `effective[x]` (dateTime or Period) stored in idx_date with `param_name="effective-time"`.
- `code` — searches medication as CodeableConcept only.
- `medication` (reference) — searches when medication is a Reference; stored separately from `code`.
