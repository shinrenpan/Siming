# CLAUDE.md

## Project

Server-side Swift FHIR R4 server. Goal priority: **A > B > C**, in that order.
- **A (now):** Technically excellent, high-performance FHIR R4 server — clean architecture, honest benchmarks.
- **C (door open, not built):** Market adoption, compliance depth, OAuth. Do not pull C-stage work into A.

Rule: **don't build future features early, but don't weld future doors shut.**

## Stack

- **Framework:** Hummingbird 2 (SwiftNIO based). No Fluent, no Leaf.
- **DB:** PostgreSQL via PostgresNIO directly. Hand-tuned SQL — no ORM. Connection pooling via `PostgresClient` (call `.run()` as a background task).
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
- Test: `swift test` — prefer running single tests during iteration
- Regenerate search extractors: `swift run SimingGenerator`
- Local Postgres: `docker compose up -d db`
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
  - `idx_string` — name, address (trigram/GIN index)
  - `idx_reference` — subject, patient
  - `idx_date` — date, period (b-tree range)
  - `idx_quantity` — value-quantity
- Each index row: `(resource_type, resource_id, param_name, value...)`.
- **Write extracts to index tables. Read/search queries index tables, never scans jsonb.**
- Covering indexes on all idx_* tables enable index-only scans. `resources_live_idx` partial index covers non-deleted rows only.
- Read path uses raw JSON passthrough (`injectMeta` / `buildBundleJSON`) — zero FHIRModels decode on reads. Do not decode/re-encode on the read path.

### Write path

Every create / update runs in a single PostgresNIO transaction:
1. Assign `id` — UUID on create; client-provided on PUT (validate `[A-Za-z0-9\-\.]{1,64}`).
2. Compute `version_id`: `COALESCE(MAX(version_id), 0) + 1` in the same transaction.
3. Insert resource row.
4. Replace index rows: DELETE existing for `(resource_type, id)`, bulk-insert from extractor.
5. Call `validate(resource)` — no-op hook for future profile validation. **Never remove this call.**

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

```sql
WITH
f_name AS (
  SELECT DISTINCT resource_id FROM idx_string
  WHERE resource_type = 'Patient' AND param_name = 'name' AND value ILIKE $1
),
f_date0 AS (
  SELECT DISTINCT resource_id FROM idx_date
  WHERE resource_type = 'Patient' AND param_name = 'birthdate' AND date_end >= $2
),
current AS (
  SELECT DISTINCT ON (r.id) r.id, r.version_id, r.last_updated, r.content
  FROM resources r
  JOIN f_name  ON f_name.resource_id  = r.id
  JOIN f_date0 ON f_date0.resource_id = r.id
  WHERE r.resource_type = 'Patient' AND r.deleted = false
  ORDER BY r.id, r.version_id DESC
)
SELECT c.id, c.version_id, c.last_updated, c.content, COUNT(*) OVER () AS total
FROM current c
ORDER BY c.last_updated DESC, c.id ASC
LIMIT $3
```

Filter CTEs hit GIN/b-tree indexes directly; `current` materialises only the matching subset; planner can hash-join the filter CTEs.

## FHIR wire-format rules

- **Content-Type:** `application/fhir+json` on all requests and responses.
- **Errors:** always `OperationOutcome` — never ad-hoc JSON.
- **Concurrency:** `ETag` (from `version_id`) on reads; `If-Match` on updates for optimistic locking.
- **Status codes:** 201 + `Location` on create; 410 Gone on deleted-resource GET; 412 on `If-Match` failure.
- **`id` semantics:** server-assigned UUID on create; client-provided on PUT; reject malformed ids.

## FHIR R4 interaction compliance

All Layer 1 baseline interactions are complete: create, read, update, delete, search, vread, history-instance, history-type, `Last-Modified`, conditional read (`If-None-Match` / `If-Modified-Since`), conditional create (`If-None-Exist`), conditional update (`PUT /[type]?<search>`).

**Layer 2 — deferred (do not build now):** Inferno/Touchstone, SMART on FHIR, terminology, `$operations`, `_include`/`_revinclude`, transaction bundles, conditional delete, `Prefer` header, type/system-level history.

## Pagination

Cursor / keyset based: `WHERE (sort_val, id) > (?, ?)`. **Never offset-based.**

## Current capabilities

- Patient + Observation: full CRUD, vread, history-instance, logical delete (410 Gone)
- Search: 15 Patient params, 12+ Observation params
- Search modifiers: `:contains`, `:exact`, `:not`, `:missing`, `system|` format
- Date prefixes: eq/lt/gt/le/ge/sa/eb; quantity prefix `ap` (±10%)
- `_sort`: ±`_lastUpdated`, ±`name`/`family`, ±`birthdate` (Patient), ±`date` (Observation)
- Cursor pagination; `_count=0` count-only mode; correct Bundle.total across pages
- Compartment search: `GET /Patient/:id/Observation`
- Conditional read: `If-None-Match` / `If-Modified-Since` → 304
- Conditional create: `POST /[type]` + `If-None-Exist: <search>` — 0 matches creates, 1 match returns 200, >1 returns 412
- Conditional update: `PUT /[type]?<search>` — 0 matches creates (201), 1 match updates (200), >1 returns 412
- Type-level history: `GET /Patient/_history` and `GET /Observation/_history` with `_since` (ISO 8601) and `_count`
- `/metadata` CapabilityStatement reflecting all supported params
- Prometheus metrics + trace IDs (`GET /metrics`)
- 87 unit tests (no DB dependency)

## Project structure / conventions

```
Siming/
├── Package.swift
├── docker-compose.yml
├── docker-compose.benchmark.yml    # adds HAPI + hapi-db services
├── benchmarks/
│   ├── seed.sh                     # seed N patients into any FHIR server
│   ├── bench.sh                    # run 4-scenario oha benchmark, output markdown
│   ├── README.md                   # benchmark instructions + results history
│   └── results/                    # benchmark result files (gitignored)
├── migrations/
│   ├── 0001_init.sql               # resources + 5 index tables
│   └── 0002_search_indexes.sql     # covering indexes for index-only scans
├── Resources/
│   └── fhir/
│       └── search-parameters-r4.json   # FHIR R4 SearchParameter bundle (generator input)
├── Sources/
│   ├── SimingServer/
│   │   ├── App.swift
│   │   ├── Middleware/
│   │   │   └── MetricsMiddleware.swift     # trace ID + Prometheus counter/histogram
│   │   └── Routes/
│   │       ├── CompartmentRoutes.swift     # GET /Patient/:id/Observation
│   │       ├── MetadataRoutes.swift        # GET /metadata → CapabilityStatement
│   │       ├── MetricsRoutes.swift         # GET /metrics → Prometheus text format
│   │       ├── ObservationRoutes.swift
│   │       └── PatientRoutes.swift
│   ├── SimingCore/
│   │   ├── FHIR/
│   │   │   ├── FHIRErrors.swift            # FHIRServerError enum + buildOutcome helper
│   │   │   └── JSONPassthrough.swift       # injectMeta() + buildBundleJSON() + buildHistoryBundleJSON()
│   │   ├── Storage/
│   │   │   ├── DatabaseConfiguration.swift
│   │   │   ├── IndexRows.swift
│   │   │   ├── MigrationRunner.swift
│   │   │   ├── ObservationSearchQuery.swift
│   │   │   ├── ObservationStore.swift
│   │   │   ├── PatientSearchQuery.swift
│   │   │   ├── PatientStore.swift
│   │   │   └── SearchParams.swift
│   │   └── Generated/              # committed, never hand-edited
│   │       ├── Observation+SearchExtractor.swift  # 38 params
│   │       └── Patient+SearchExtractor.swift      # 23 params
│   └── SimingGenerator/
│       ├── BundleTypes.swift
│       ├── Emit.swift
│       ├── ObservationHandlers.swift
│       ├── PatientHandlers.swift
│       └── main.swift
└── Tests/
    └── SimingCoreTests/
        └── SimingCoreTests.swift
```

Pinned dependency versions (confirm against GitHub releases before changing):
- Hummingbird `2.25.0`
- PostgresNIO `1.33.0`
- FHIRModels `0.9.2`
- swift-metrics `2.11.0`
- swift-prometheus `2.3.0`

Conventions:
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
- terminology, `_revinclude`, transaction bundle, subscription → stage 3+.

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
- **Before implementing or changing any FHIR behaviour, look up the R4 spec first.** Known open gaps vs spec: `_sort` supports only `_lastUpdated`/`name`/`family`/`birthdate` (Patient) and `date` (Observation); no `:text` modifier for string searches.
- Build and run tests after a series of changes before declaring done.
- Every FHIR endpoint **must** check/set `Content-Type: application/fhir+json` and return `OperationOutcome` on error — no exceptions.
- Every write runs in a single PostgresNIO transaction (insert resource + replace index rows). Never split.
- **DELETE** returns 204 No Content; subsequent GET on deleted resource returns **410 Gone** (not 404).
- **`If-None-Match` takes precedence** over `If-Modified-Since` when both headers are present (RFC 7232 §6).
- **Compartment constraint** (`GET /Patient/:id/Observation`) is injected server-side; client cannot override the subject filter.
- Benchmarking: compare under the same feature set only — state what's supported alongside any number. See `benchmarks/README.md`.
