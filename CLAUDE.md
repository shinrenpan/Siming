# CLAUDE.md

## Scope of this file

Working rules, constraints, and code patterns only.
**Do not add:** feature lists, capability counts, project structure trees, test counts, or round summaries — those belong in README.md.
Only include information that prevents mistakes.

## Project

Server-side Swift FHIR R4 server. Goal priority: **A first, everything else later**.
- **A (now):** Technically excellent, high-performance FHIR R4 server — clean architecture, honest benchmarks.
- **Later:** Production readiness, deeper FHIR features, Core IG, OAuth — when A is solid. Do not pull later-stage work into A.

Rule: **don't build future features early, but don't weld future doors shut.**

## Stack

- **Framework:** Hummingbird 2 (SwiftNIO based). No Fluent, no Leaf.
- **DB:** PostgreSQL via PostgresNIO directly. Hand-tuned SQL — no ORM. Connection pooling via `PostgresClient` (call `.run()` as a background task). Pool: min=4 / max=40 (set in `DatabaseConfiguration.postgresClientConfiguration`).
- **FHIR models:** apple/FHIRModels, `ModelsR4` target. Pinned at `0.9.2`.
- **FHIR version:** R4 only. R5 door stays open via the generator.

### FHIRModels API cheatsheet

Primitive access patterns (all non-obvious without reading source):

```swift
// FHIRPrimitive<FHIRString> → String
humanName.family?.value?.string          // → String?
fhirPrimitive.value?.string              // general pattern

// FHIRPrimitive<FHIRURI> → String
identifier.system?.value?.url.absoluteString   // → String?

// FHIRPrimitive<FHIRBool> → Bool
patient.active?.value?.bool              // → Bool?

// FHIRPrimitive<FHIRDate> — year/month/day
patient.birthDate?.value?.year           // → Int?
patient.birthDate?.value?.month          // → UInt8?
patient.birthDate?.value?.day            // → UInt8?

// FHIRPrimitive<SomeEnum> → raw String
patient.gender?.value?.rawValue          // → String? ("male", "female", …)
```

Encoding / decoding (standard Codable — nothing FHIR-specific needed):
```swift
let patient = try JSONDecoder().decode(Patient.self, from: requestBodyData)
let jsonData = try JSONEncoder().encode(patient)
```

## Build / run / test

- Build: `swift build`
- Run server: `swift run SimingServer` — listens on `0.0.0.0:8080`
- Unit tests: `swift test --filter SimingCoreTests` — no DB required
- Integration tests: `PGHOST=localhost PGUSER=siming PGPASSWORD=siming PGDATABASE=siming swift test --filter SimingIntegrationTests` — requires Postgres
- Run all tests: `swift test` — integration tests auto-skip if no DB configured
- Regenerate search extractors: `swift run SimingGenerator`
- Local Postgres only: `docker compose up -d db`
- DB connection env vars (defaults match docker-compose):
  - `DATABASE_URL=postgres://siming:siming@localhost:5432/siming` (takes priority)
  - or discrete: `PGHOST`, `PGPORT`, `PGUSER`, `PGPASSWORD`, `PGDATABASE`
  - `MIGRATIONS_PATH` — path to `migrations/` dir (default: `"migrations"`, relative to CWD)
- Full local run: `PGHOST=localhost PGUSER=siming PGPASSWORD=siming PGDATABASE=siming swift run SimingServer`
- After any series of changes: build + run tests before considering work done

## Database migrations

- Hand-written, ordered SQL files (`migrations/0001_init.sql`, `0002_...`). No ORM-driven auto-migration.
- Files are **immutable once committed** — new changes get a new numbered file.
- `MigrationRunner` applies pending files in filename order at server startup.

## Storage design

Hybrid schema — source of truth in jsonb, search params extracted to typed index tables on write:

- `resources` table: `(resource_type, id, version_id, last_updated, content jsonb, deleted bool)`
- **History-preserving:** update writes a NEW row (incremented `version_id`), never overwrites. Current version = highest `version_id` for `(resource_type, id)`.
- Five typed index tables (one per search-param TYPE, not per param):
  - `idx_token` (system, code) — identifier, code, status
  - `idx_string` — name, address (functional btree on `lower(value)` for prefix; trigram GIN for `:contains`)
  - `idx_reference` — subject, patient
  - `idx_date` — date, period (b-tree range)
  - `idx_quantity` — value-quantity
- Each index row: `(resource_type, resource_id, param_name, value...)`.
- **Write extracts to index tables. Read/search queries index tables, never scans jsonb.**
- Covering indexes on all idx_* tables enable index-only scans. `resources_live_idx` partial index covers non-deleted rows only.
- Read path uses raw JSON passthrough (`injectMeta` / `buildBundleJSON`) — zero FHIRModels decode on reads. Do not decode/re-encode on the read path.

### Write path

Every create / update runs in a single PostgresNIO transaction via **`writeResource`** (`ResourceWriter.swift`):
1. Assign `id` — UUID on create; client-provided on PUT (validate `[A-Za-z0-9\-\.]{1,64}`).
2. Single CTE: validate If-Match + compute `version_id` (`COALESCE(MAX, 0) + 1`) + insert resource row.
3. Call `clear_index_rows($resourceType, $id)` — PostgreSQL function in `0003_functions.sql` that deletes all five index tables in one server-side call.
4. Bulk-insert new index rows via **`replaceIndexRows`** (`IndexWriter.swift`) — one batch INSERT per non-empty index table.
5. Call `validate(resource)` in the store before entering the transaction — no-op hook for future profile validation. **Never remove this call.**

Delete follows the same pattern via **`deleteResource`** (`ResourceWriter.swift`): version check → tombstone INSERT → `clear_index_rows`.

**Do NOT write your own BEGIN/COMMIT transaction for resource writes.** Use `writeResource` / `deleteResource`.
**Do NOT issue 5 individual DELETEs against index tables.** Use `clear_index_rows` or `replaceIndexRows`.

### Adding a new resource

Checklist (in addition to generator + extractor + SQL migration):
1. Add store property to **`StoreContainer`** (`StoreContainer.swift`) — single init param for all wiring.
2. The new store's `write()` calls `writeResource`; `delete()` calls `deleteResource` — copy the pattern from any existing store.
3. Register in **`RouterBuilder`** (`RouterBuilder.swift`) via `addXxxRoutes(to: router, store: stores.xxx, logger: logger)`.

## Search parameters

**Do NOT hand-write search-param definitions.** `SimingGenerator` consumes `Resources/fhir/search-parameters-r4.json` and emits extractors into `Sources/SimingCore/Generated/`. This generator is the architectural moat and the R5 door. Regenerate: `swift run SimingGenerator`.

## Hummingbird 2 handler patterns

```swift
// Content-Type check (required on every write handler)
let ct = request.headers[.contentType] ?? ""
guard ct.contains("application/fhir+json") || ct.contains("application/json") else {
    throw FHIRRouteError.unsupportedMediaType
}

// Collect body — Request is a struct so collectBody is mutating:
var req = request
let bodyBuffer = try await req.collectBody(upTo: 4 * 1024 * 1024)  // ByteBuffer
let patient = try JSONDecoder().decode(Patient.self, from: Data(bodyBuffer.readableBytesView))

// Query params — FlatDictionary<Substring, Substring>
let name  = request.uri.queryParameters["name"].map(String.init)      // single value
let dates = request.uri.queryParameters[values: "birthdate"]           // multi-value → [Substring]

// Host/authority (request.headers[.host] is unavailable in swift-http-types)
let authority = request.head.authority ?? "localhost"
```

OperationOutcome for errors (never return ad-hoc JSON):
```swift
let outcome = OperationOutcome(issue: [
    OperationOutcomeIssue(
        code: FHIRPrimitive(.invalid),
        diagnostics: FHIRPrimitive(FHIRString("…")),
        severity: FHIRPrimitive(.error)
    )
])
```

Passing `PostgresClient` to handlers: capture in closure at router-build time.

## PostgresNIO dynamic query pattern

```swift
var binds = PostgresBindings()
var n = 0
func bind(_ val: some PostgresDynamicTypeEncodable) -> String {
    n += 1; binds.append(val); return "$\(n)"
}
```

`String`, `Int64`, `Date`, `Bool` conform to `PostgresDynamicTypeEncodable` (non-throwing). `binds.appendNull()` for NULL.

### Search SQL pattern — filter CTEs, not correlated EXISTS

**Do NOT use correlated EXISTS subqueries for search filters.** They run once per row in the outer CTE and kill performance.

**Correct pattern:** one pre-filter CTE per active search param, then JOIN into `current`:

String filter in idx_string must be written as:
- **Prefix (FHIR default):** `lower(value) LIKE lower($n)` where `$n = 'Wang%'` — uses `idx_string_lower_prefix_idx` (functional btree, no false positives)
- **Contains (`:contains`):** `value ILIKE $n` where `$n = '%Wang%'` — uses `idx_string_trgm_idx` (trigram GIN)
- **Exact (`:exact`):** `value = $n` — uses `idx_string_exact_idx` (btree)

**Do NOT use `value ILIKE $n` for prefix search** — it silently falls back to trigram GIN with false positives.

```sql
WITH
f_name AS (
  SELECT DISTINCT resource_id FROM idx_string
  WHERE resource_type = 'Patient' AND param_name = 'name' AND lower(value) LIKE lower($1)
),
f_date0 AS (
  SELECT DISTINCT resource_id FROM idx_date
  WHERE resource_type = 'Patient' AND param_name = 'birthdate' AND date_end >= $2
),
ids AS MATERIALIZED (
  SELECT DISTINCT ON (r.id) r.id, r.version_id, r.last_updated
  FROM resources r
  JOIN f_name  ON f_name.resource_id  = r.id
  JOIN f_date0 ON f_date0.resource_id = r.id
  WHERE r.resource_type = 'Patient' AND r.deleted = false
  ORDER BY r.id, r.version_id DESC
),
total_count AS (SELECT COUNT(*) AS n FROM ids),
paged AS (SELECT id, version_id, last_updated FROM ids ORDER BY last_updated DESC, id ASC LIMIT $3)
SELECT p.id, p.version_id, p.last_updated, r.content, t.n
FROM paged p CROSS JOIN total_count t
JOIN resources r ON r.resource_type = 'Patient' AND r.id = p.id AND r.version_id = p.version_id
```

Filter CTEs hit GIN/b-tree indexes directly. `ids AS MATERIALIZED` ensures the join + DISTINCT ON is evaluated exactly once even though it is referenced by both `total_count` and `paged`. Content is fetched only for the final page (deferred-content pattern).

## FHIR wire-format rules

- **Content-Type:** `application/fhir+json` on all requests and responses.
- **Errors:** always `OperationOutcome` — never ad-hoc JSON.
- **Concurrency:** `ETag` (from `version_id`) on reads; `If-Match` on updates for optimistic locking.
- **Status codes:** 201 + `Location` on create; 410 Gone on deleted-resource GET; 412 on `If-Match` failure.
- **`id` semantics:** server-assigned UUID on create; client-provided on PUT; reject malformed ids.

## FHIR R4 interaction compliance

**Implemented:** read, vread, create, update, delete, search-type, `_history` (instance / type / system — all support `_since` and `_count`), `_include`, `_revinclude`, `_summary`, `_elements`, `Prefer: handling=strict`, `_has` reverse chaining, chained search, compartment search, `_total=none|estimate|accurate`.

**`_total` semantics:** `accurate` (default) — exact `COUNT(*)` via `total_count` CTE; `estimate` — skips `COUNT(*)`, returns exact total only when the page is the last one (result count < `_count`), `nil` otherwise; `none` — omits `Bundle.total` entirely. `_summary=count` forces `count=0 + totalMode=.accurate` at the route level for efficiency (uses `buildCountSQL` path instead of fetching page entries).

**Deferred (do not build now):** Inferno/Touchstone, SMART on FHIR, terminology, `$operations`, transaction bundles, subscriptions.

## Pagination

Cursor / keyset based: `WHERE (sort_val, id) > (?, ?)`. **Never offset-based.**

## Conventions
- **Generated code IS committed to git** — reviewable, diffable. Never hand-edit; change the generator instead.
- Generator inputs live under `Resources/fhir/search-parameters-r4.json`.
- SQL migrations under `migrations/`. Filename without `.sql` = migration version in `schema_migrations`.

## The three doors to keep open

1. **Validation hook** — `validate(resource)` no-op in write path. Never remove this call.
2. **Auth as middleware** — never hardwire auth into handlers.
3. **Search via generator** — this is also the R5 door.

**Weld test:** "Could profile validation / OAuth / R5 / `_history` be added without rewriting this?" If not, stop and restructure.

## Deferred — do not build now

- Inferno / Touchstone compliance → north star only, not on roadmap.
- SMART on FHIR / OAuth → much later.
- R5 → generator preserves the path, not built.
- terminology, transaction bundle, subscription → stage 3+.

## Observability

**`GET /metrics`** — Prometheus text format: `http_requests_total{method,path,status}` counter + `http_request_duration_seconds{method,path}` histogram. Path normalised (`/Patient/:id`) to prevent label cardinality explosion.

**`MetricsMiddleware`** — `X-Request-ID` trace ID on every request; structured logs on arrival and completion.

Adding new metrics anywhere in the codebase (Prometheus backend is global):
```swift
import Metrics
Counter(label: "fhir_validation_errors_total", dimensions: [("resource", "Patient")]).increment()
Timer(label: "db_query_duration_seconds", dimensions: [("query", "search")]).recordSeconds(elapsed)
```

## Working rules for Claude Code

- Verify package versions against GitHub/registry before pinning — never from memory.
- Hand-tuned SQL over ORM abstractions; this project's whole value is storage/search performance.
- Make minimal changes; don't refactor unrelated code.
- Never hand-edit generated files; change the generator instead.
- Keep the three doors unwelded in every change — apply the weld test above.
- **Before implementing or changing any FHIR behaviour, look up the R4 spec first.** Known open gaps vs spec: `_sort` supports `_lastUpdated`/`name`/`family`/`birthdate`/`_id` (Patient), `date`/`status`/`code`/`_id` (Observation, Encounter, Procedure, DiagnosticReport, Immunization — Immunization `code` maps to `vaccine-code` param), `date`(onset)/`clinical-status`/`code`/`_id` (Condition), `date`(authoredon)/`status`/`code`/`_id` (MedicationRequest), `date`(recordedDate)/`clinical-status`/`code`/`_id` (AllergyIntolerance), `_lastUpdated`/`name`/`_id` (Practitioner, Organization), `_lastUpdated`/`name`/`status`/`_id` (Location), `_lastUpdated`/`birthdate`/`_id` (RelatedPerson), `date`(authored)/`status`/`code`/`_lastUpdated`/`_id` (ServiceRequest), `date`(collected)/`status`/`_lastUpdated`/`_id` (Specimen), `date`/`status`/`_lastUpdated`/`_id` (DocumentReference), `date`(period)/`status`/`_lastUpdated`/`_id` (CarePlan), `date`(start-date)/`status`(lifecycle-status)/`_lastUpdated`/`_id` (Goal), `date`(effective)/`status`/`code`/`_lastUpdated`/`_id` (MedicationStatement), `date`/`status`/`code`/`_lastUpdated`/`_id` (FamilyMemberHistory), `status`/`code`/`_lastUpdated`/`_id` (Medication), and `_lastUpdated`/`_id` all resources. Chained search (`refParam.childParam=value`) and `_has` reverse chaining (`_has:ReferencedType:refParam:childParam=value`) are fully implemented for all 23 resources; child params mapped in `chainChildParamType` in `ChainedParam.swift`. Practitioner phone/email search indexes all telecom entries regardless of system (generator strips `.where()` — known limitation, false positives unlikely). Practitioner `phonetic` is implemented as prefix/contains match on name fields (same data as `name` param, param_name `"phonetic"` in idx_string). Organization `phonetic` and `endpoint` are fully implemented; `phonetic` indexes `org.name` and `org.alias[]` with param_name `"phonetic"`; `endpoint` indexes `org.endpoint[]` references via idx_reference. Location `endpoint` is fully implemented via idx_reference. Location `near` (geospatial) is a TODO stub (no-op extractor — requires PostGIS extension). RelatedPerson `phonetic` is an alias for `name` (indexes same HumanName fields, routes to same `name` param in idx_string). Location and Medication are not in Patient compartment per FHIR R4 spec; RelatedPerson, ServiceRequest, Specimen, DocumentReference, CarePlan, Goal, MedicationStatement, and FamilyMemberHistory ARE in Patient compartment. ServiceRequest `orderDetail` StringParam is defined in search query struct but not indexed (no extractor implementation); setting it has no filter effect. Observation `based-on`, `derived-from`, `device`, `focus`, `has-member`, `part-of`, `specimen` are reference params fully implemented via idx_reference; `combo-code` (indexes both `obs.code` AND `obs.component[].code`), `method`, `value-concept` are token params fully implemented via idx_token with `:not` modifier support; `value-date` (`obs.value as DateTime`) is fully implemented via idx_date; `value-string` (`obs.value as string`) is fully implemented via idx_string. DocumentReference `description_fhir` field (Swift name) maps to FHIR `description` search param; `contenttype`, `format`, `language`, `setting`, `custodian`, `authenticator`, `relatesto` (reference — `relatesTo[].target` via idx_reference), and `relation` (token — `relatesTo[].code` with system `http://hl7.org/fhir/document-relationship-type` via idx_token) are fully implemented (extractor + store filter); `location` (URI type), `relationship` (composite), `related` are TODO stubs (no-op extractors) in the generated extractor — `relationship` is a composite param (conjunction of relatesto + relation) that requires composite search support not yet implemented; `location` is a URI-typed attachment URL with no standard idx table. CarePlan `activity-date` indexes `activity[].detail.scheduled[x]` — `.period` (start/end) and `.timing` (event dates) cases are stored in idx_date; `.string` case is silently skipped. CarePlan `instantiates-canonical` and `instantiates-uri` are stored in idx_string (exact URL match). Goal `start-date` only indexes `start[x]` when it is a `startDate` (FHIRDate); `startCodeableConcept` case silently skipped. Goal `target-date` only indexes `target.due[x]` when it is a `dueDate` (FHIRDate); `dueDuration` case silently skipped. MedicationStatement IS in Patient compartment per FHIR R4 spec. FamilyMemberHistory `instantiates-canonical` and `instantiates-uri` are stored in idx_string (exact URL match). FamilyMemberHistory IS in Patient compartment per FHIR R4 spec. Appointment IS in Patient compartment per FHIR R4 spec (via `participant.actor`); `patient`, `practitioner`, `location`, `actor` all index the same field but with different `param_name` — search filters by `ref_type` to distinguish (e.g., `patient=Patient/123` → `ref_type='Patient' AND ref_id='123'`). Appointment `supporting-info` searches `supportingInformation[]` references via idx_reference. Appointment `_sort` supports `±_lastUpdated`, `±date` (Appointment.start), `±status`, `±_id`. MedicationAdministration IS in Patient compartment per FHIR R4 spec (via `subject.where(resolve() is Patient)` — uses `patient` param_name in index); `effective-time` maps to `effective[x]` (dateTime or Period) stored in idx_date with param_name `effective-time`; `code` searches medication as CodeableConcept only; `medication` (reference) searches when medication is a Reference; both `code` and `medication` reference the same field but are stored separately. MedicationAdministration `_sort` supports `±_lastUpdated`, `±date` (effective-time), `±status`, `±code`, `±_id`. Chained search and `_has` fully implemented for all 23 resources; `effective-time`, `reason-given`, `reason-not-given` added to `chainChildParamType` in `ChainedParam.swift`.
- Build and run tests after a series of changes before declaring done.
- Every FHIR endpoint **must** check/set `Content-Type: application/fhir+json` and return `OperationOutcome` on error — no exceptions.
- Every write runs in a single PostgresNIO transaction (insert resource + replace index rows). Never split.
- **DELETE** returns 204 No Content; subsequent GET on deleted resource returns **410 Gone** (not 404).
- **PATCH** uses `Content-Type: application/json-patch+json` (RFC 6902). Flow: read current resource → apply patch (`JSONPatch.apply`) → decode FHIR model → store.update. Patch errors → 400; `test` op failure → 422; `If-Match` mismatch → 412.
- **`If-None-Match` takes precedence** over `If-Modified-Since` when both headers are present (RFC 7232 §6).
- **Compartment constraint** (`GET /Patient/:id/[ResourceType]` — all 19 compartment resources; excludes Patient, Medication, Location, Practitioner, Organization) is injected server-side; client cannot override the subject filter.
- Benchmarking: compare under the same feature set only — state what's supported alongside any number. See `benchmarks/README.md`.
