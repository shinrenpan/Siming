# CLAUDE.md

## Name

**Siming 司命** — package name `Siming`, repo `siming`.

司命 is the Daoist deity who governs life and lifespan, keeper of the record of every mortal's days. A fitting name for a server that keeps the record of every patient's health — and one whose history-preserving design literally keeps every version of that record.

README convention (pinyin + hanzi + gloss, so the meaning is anchored and any tonal ambiguity is dispelled):

> # Siming 司命
> *Siming (司命) — the Daoist deity who keeps the record of every mortal's lifespan. A high-performance, history-preserving FHIR R4 server in Swift.*

Name chosen deliberately for being uncommon: low collision risk now and long-term, unlike first-instinct mythology names (Kunlun, Shennong, Queqiao). **Claim the position early** — register repo / package name / domain while clean; ownership is first-come, not auto-reserved by obscurity.

## Project

Server-side Swift FHIR server. Goal priority: **A > B > C**, pursued in that order (not simultaneously).

- **A (now):** A technically excellent, high-performance FHIR R4 server as a flagship work — clean architecture, honest benchmarks. This is the real current target.
- **B (free byproduct):** Self-hostable / usable for a real backend once A is solid.
- **C (door kept open, not built):** Market adoption. Requires compliance depth — deferred, but architecture must not foreclose it.

Do not pull C-stage work (full compliance, OAuth, terminology, R5) into A. The rule is: **don't build future features early, but don't weld future doors shut.**

## Stack

- **Framework:** Hummingbird 2 (SwiftNIO based). Chosen for minimalism, not raw speed (Vapor's NIO core is equally fast). No Fluent, no Leaf.
- **DB:** PostgreSQL, accessed via PostgresNIO directly. Hand-tuned SQL — no ORM. Connection pooling via `PostgresClient` (conforms to `Service`; call `.run()` as a background task).
- **FHIR models:** apple/FHIRModels, `ModelsR4` target. Pinned at `0.9.2`.
- **FHIR version:** R4 only for now. R5 door stays open via the generator (see below), not built.

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
- Local Postgres: `docker compose up -d db`
- DB connection env vars (defaults match docker-compose):
  - `DATABASE_URL=postgres://siming:siming@localhost:5432/siming` (takes priority)
  - or discrete: `PGHOST`, `PGPORT`, `PGUSER`, `PGPASSWORD`, `PGDATABASE`
  - `MIGRATIONS_PATH` — path to `migrations/` dir (default: `"migrations"`, relative to CWD)
- Full local run: `PGHOST=localhost PGUSER=siming PGPASSWORD=siming PGDATABASE=siming swift run SimingServer`
- After any series of changes: build + run tests before considering work done

## Database migrations

- Schema is managed by **hand-written, ordered SQL migration files** (e.g. `migrations/0001_init.sql`, `0002_...`). No ORM-driven auto-migration.
- Migrations are forward-only and committed to git. Each file is immutable once committed — new changes get a new file.
- `MigrationRunner` in `SimingCore` applies pending files in filename order, tracking applied versions in `schema_migrations`.
- Migrations run automatically at server startup (before the HTTP listener opens).
- `migrations/0001_init.sql` — **done**: `resources` table + 5 index tables + `schema_migrations`.

## Storage design (the core decision)

Hybrid schema — single source of truth in jsonb, search params extracted to typed index tables on write:

- `resources` main table: `(resource_type, id, version_id, last_updated, content jsonb, deleted bool)`
- **Versioning: keep history.** An update writes a NEW row (incremented `version_id`), it does NOT overwrite. The current version is the highest `version_id` for that `(resource_type, id)`. This preserves the path to FHIR `_history` / `vread` without a future schema migration. Reads default to current version; index tables reference the current version only.
- Five typed index tables, one per search-param TYPE (not per param):
  - `idx_token` (system, code) — identifier, code, status
  - `idx_string` — name, address (trigram/GIN index)
  - `idx_reference` — subject, patient
  - `idx_date` — date, period (b-tree range)
  - `idx_quantity` — value-quantity
- Each index row: `(resource_type, resource_id, param_name, value...)`.
- Write path extracts params into index tables. Read/search path queries index tables, never scans jsonb.

Read:write ratio in real FHIR is ~10:1+, so paying extraction cost on write to make search fast is the right trade.

### Write path detail

Every create / update runs in a single PostgresNIO transaction:

1. **Assign `id`**: server-generated UUID on create; client-provided on PUT (validate format: `[A-Za-z0-9\-\.]{1,64}`).
2. **Compute `version_id`**: `COALESCE(MAX(version_id), 0) + 1` from existing rows for that `(resource_type, id)`. Wrapped in the same transaction to avoid races.
3. **Insert resource row**: `INSERT INTO resources (resource_type, id, version_id, last_updated, content, deleted)`.
4. **Replace index rows**: `DELETE FROM idx_* WHERE resource_type=$1 AND resource_id=$2` then bulk-insert rows from `extractPatientSearchParams`.
5. **Validation hook** (currently a no-op): call `validate(resource)` before insert — hook point for future profile validation. Never remove this call.

SQL sketch for version_id:
```sql
INSERT INTO resources (resource_type, id, version_id, last_updated, content, deleted)
VALUES (
  $1, $2,
  (SELECT COALESCE(MAX(version_id), 0) + 1 FROM resources WHERE resource_type=$1 AND id=$2),
  now(), $3, false
)
RETURNING version_id, last_updated;
```

## Search parameters (the real work — do this at stage 0, not after MVP)

- **Do NOT hand-write search-param definitions.** Build a code generator that consumes the official FHIR R4 `SearchParameter` bundle (machine-readable JSON) and emits the extraction logic. This mirrors how FHIRModels generates its own models.
- This generator IS the moat: adding a new resource becomes near-zero cost. Hand-writing dies by the fifth resource.
- The same generator pattern keeps the R5 door open later (feed it the R5 bundle).

## Hummingbird 2 handler patterns

FHIR requires strict Content-Type discipline. Every handler must:

```swift
// Verify request Content-Type
let ct = request.headers[.contentType] ?? ""
guard ct.contains("application/fhir+json") || ct.contains("application/json") else {
    throw FHIRRouteError.unsupportedMediaType
}

// Collect body — Request is a struct so collectBody is mutating:
var req = request
let bodyBuffer = try await req.collectBody(upTo: 4 * 1024 * 1024)  // ByteBuffer
let patient = try JSONDecoder().decode(Patient.self, from: Data(bodyBuffer.readableBytesView))

// Build response with ETag + Location
let data = try JSONEncoder().encode(resource)
var headers = HTTPFields()
headers[.contentType] = "application/fhir+json"
headers[.eTag] = "W/\"\(versionId)\""
headers[.location] = "/Patient/\(id)/_history/\(versionId)"
return Response(status: .created, headers: headers, body: ResponseBody(byteBuffer: ByteBuffer(bytes: data)))
```

Query parameters and authority header:
```swift
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

Passing `PostgresClient` to handlers: capture in closure at router-build time (fine for MVP, refactor to typed `RequestContext` extension later if needed).

## PostgresNIO dynamic query pattern

For search endpoints that need variable WHERE clauses, use `PostgresQuery(unsafeSQL:binds:)`:

```swift
var binds = PostgresBindings()
var n = 0

func bind(_ val: some PostgresDynamicTypeEncodable) -> String {
    n += 1; binds.append(val); return "$\(n)"
}
```

Key facts: `String`, `Int64`, `Date`, `Bool` all conform to `PostgresDynamicTypeEncodable` (non-throwing). `binds.appendNull()` for NULL. `COUNT(*) OVER ()` in the SELECT gives total-before-LIMIT alongside rows, avoiding a second query.

### Search SQL pattern — filter CTEs, not correlated EXISTS

**Do NOT use correlated EXISTS subqueries for search filters.** They run once per row in the outer CTE and kill performance.

**Correct pattern:** one pre-filter CTE per active search param, then JOIN into `current`:

```sql
WITH
f_name AS (
  -- index-only scan; DISTINCT collapses multi-row patients (e.g. multiple name fields)
  SELECT DISTINCT resource_id FROM idx_string
  WHERE resource_type = 'Patient' AND param_name = 'name' AND value ILIKE $1
),
f_date0 AS (
  SELECT DISTINCT resource_id FROM idx_date
  WHERE resource_type = 'Patient' AND param_name = 'birthdate' AND date_end >= $2
),
current AS (
  -- DISTINCT ON materialises only the matching rows, not the full table
  SELECT DISTINCT ON (r.id) r.id, r.version_id, r.last_updated, r.content
  FROM resources r
  JOIN f_name  ON f_name.resource_id  = r.id
  JOIN f_date0 ON f_date0.resource_id = r.id
  WHERE r.resource_type = 'Patient' AND r.deleted = false
  ORDER BY r.id, r.version_id DESC
)
SELECT c.id, c.version_id, c.last_updated, c.content, COUNT(*) OVER () AS total
FROM current c
-- cursor condition only here
ORDER BY c.last_updated DESC, c.id ASC
LIMIT $3
```

Why this is faster:
- Filter CTEs use the GIN/b-tree indexes on `idx_string`/`idx_date` directly.
- `current` CTE only materialises the matching subset — not all rows.
- `COUNT(*) OVER ()` cost is proportional to the result set, not the full table.
- No correlated subqueries; the planner can hash-join the filter CTEs.

## FHIR wire-format rules (R4 baseline — non-negotiable, not "features")

These are basic conformance, not optional polish. Get them right from the first endpoint:

- **Content-Type:** requests and responses use `application/fhir+json`. Accept header negotiation must honor it.
- **Errors return `OperationOutcome`** resources with appropriate `issue.severity`/`code` — never ad-hoc JSON error blobs.
- **Concurrency control:** support `ETag` (from `version_id`) on reads and `If-Match` on updates for optimistic locking.
- **Standard status codes:** 201 on create (+ `Location` header), 200/204 appropriately, 404 as `OperationOutcome`, 412 on `If-Match` failure.
- **`id` semantics:** server-assigned vs client-assigned per FHIR rules; reject malformed ids.

### FHIR R4 interaction compliance — two-layer strategy

**Layer 1 — baseline interactions (implement now):** Any server claiming to be FHIR R4 must support these correctly. Schema already supports them; cost is low.

| Interaction | Method + URL | Status |
|---|---|---|
| create | `POST /[type]` | ✅ done |
| read | `GET /[type]/[id]` | ✅ done |
| update | `PUT /[type]/[id]` | ✅ done |
| search | `GET /[type]?[params]` | ✅ done |
| delete | `DELETE /[type]/[id]` | ✅ done |
| vread | `GET /[type]/[id]/_history/[vid]` | ✅ done |
| history (instance) | `GET /[type]/[id]/_history` | ✅ done |
| `Last-Modified` response header | all write + read responses | ✅ done |
| conditional read | `If-None-Match` / `If-Modified-Since` → 304 | ✅ done |

**Layer 2 — compliance depth (deferred, C-stage):** Inferno/Touchstone, SMART on FHIR, terminology, `$operations`, `_include`/`_revinclude`, transaction bundles, conditional create/update/delete, `Prefer` header, history at type/system level. Do not build now.

### Compartment search semantics (FHIR R4)

`GET /Patient/[id]/[type]?[params]` — returns resources of `[type]` that belong to the patient's compartment. Semantically equivalent to searching `[type]?subject=Patient/[id]&[params]`. The compartment constraint is injected server-side and cannot be overridden by the client.

Currently implemented: `GET /Patient/[id]/Observation` (subject compartment, all Observation search params supported).

### `_count=0` semantics

`GET /[type]?_count=0` — returns a Bundle with `Bundle.total` equal to the number of matching resources, but `entry` is absent. Used by clients to determine result set size without fetching data.

**The judgment rule:** "Is this about the server's *basic behaviour being correct*, or about *feature completeness*?" DELETE returning 204 and subsequent GET returning 410 is basic correctness. `_include` is feature completeness.

### DELETE semantics (FHIR R4 spec)

FHIR specifies **logical delete** — insert a new version row with `deleted = true`. Effects:
- `GET /[type]/[id]` → **410 Gone** (not 404)
- `GET /[type]/[id]/_history/[vid]` → still accessible for the specific version
- Deleted resource no longer appears in search results
- Can be "resurrected" via `PUT /[type]/[id]` (creates a new live version)
- Response: **204 No Content** (no body); optionally 200 with OperationOutcome

### Conditional read semantics (RFC 7232 + FHIR R4)

Applied to `GET /[type]/[id]` and `GET /[type]/[id]/_history/[vid]`:

- **`If-None-Match: W/"N"`** — if current ETag equals the client's value (or client sends `*`), return **304 Not Modified** (no body); include ETag + Last-Modified in the 304 response headers per RFC 7232.
- **`If-Modified-Since: <HTTP-date>`** — if `lastUpdated ≤ clientDate`, return **304 Not Modified**.
- If both headers are present, `If-None-Match` takes precedence (per RFC 7232 §6).
- Always perform the DB read first; 304 saves the response body, not the query.

### VRead and History semantics

- **vread** `GET /[type]/[id]/_history/[vid]`: return the exact stored version; 404 if id unknown, 410 if that version was a delete marker
- **history** `GET /[type]/[id]/_history`: return a Bundle of type `history`, one entry per version, newest first; each entry includes `request` and `response` elements per FHIR spec

## Pagination

Cursor / keyset based: `WHERE (last_updated, id) > (?, ?)`. **Never offset-based.** HAPI's pagination tokens are a known pain point; this is an architectural win available in fair comparison.

## Scope — go narrow, prove depth

First milestone: **Patient only**, but fully punched through:
- Full CRUD
- Search: `name`, `identifier`, `birthdate` + `_include` + `_sort` + `_count`
- Cursor pagination
- `/metadata` CapabilityStatement honestly reflecting what's actually supported

Three-resource CRUD is fake progress (CRUD is ~identical per resource). Real progress = search + pagination + _include working end-to-end on ONE resource. Second/third resources are then nearly free.

## Project structure / conventions

```
Siming/
├── Package.swift
├── docker-compose.yml
├── docker-compose.benchmark.yml    # adds HAPI + hapi-db services
├── benchmarks/
│   ├── seed.sh                     # seed N patients into any FHIR server
│   ├── bench.sh                    # run 4-scenario oha benchmark, output markdown
│   └── results/                    # benchmark result files (gitignored)
├── migrations/
│   ├── 0001_init.sql               # resources + 5 index tables
│   └── 0002_search_indexes.sql     # covering indexes for index-only scans (resources_live_idx + idx_* tables)
├── Resources/
│   └── fhir/
│       └── search-parameters-r4.json   # FHIR R4 SearchParameter bundle (generator input)
├── Sources/
│   ├── SimingServer/               # executable — Hummingbird app, entry point
│   │   ├── App.swift
│   │   ├── Middleware/
│   │   │   └── MetricsMiddleware.swift     # per-request trace ID + Prometheus counter/histogram
│   │   └── Routes/
│   │       ├── MetadataRoutes.swift        # GET /metadata → CapabilityStatement
│   │       ├── MetricsRoutes.swift         # GET /metrics → Prometheus text format
│   │       ├── ObservationRoutes.swift     # POST/GET /Observation + search bundle
│   │       └── PatientRoutes.swift         # POST/GET/PUT /Patient; FHIRRouteError + FHIRServerError → HTTPResponseError
│   ├── SimingCore/                 # library — storage, FHIR logic (imported by server)
│   │   ├── FHIR/
│   │   │   ├── FHIRErrors.swift            # FHIRServerError enum + buildOutcome helper
│   │   │   └── JSONPassthrough.swift       # injectMeta() + buildBundleJSON() — raw-bytes read/search path
│   │   ├── Storage/
│   │   │   ├── DatabaseConfiguration.swift
│   │   │   ├── IndexRows.swift             # row structs for idx_* tables
│   │   │   ├── MigrationRunner.swift
│   │   │   ├── ObservationSearchQuery.swift # search params + cursor + sort (reuses PatientSearchQuery types)
│   │   │   ├── ObservationStore.swift      # create / update / read / search; filter-CTE SQL
│   │   │   ├── PatientSearchQuery.swift    # search params + cursor + sort + identifier/birthdate parsers
│   │   │   ├── PatientStore.swift          # create / update / read / search; dynamic SQL builder
│   │   │   └── SearchParams.swift          # SearchParams aggregate
│   │   └── Generated/              # committed, never hand-edited
│   │       ├── Observation+SearchExtractor.swift  # 38 params; regenerate: swift run SimingGenerator
│   │       └── Patient+SearchExtractor.swift      # 23 params; regenerate: swift run SimingGenerator
│   └── SimingGenerator/            # executable — dev/build tool, NOT in server binary
│       ├── BundleTypes.swift
│       ├── Emit.swift
│       ├── ObservationHandlers.swift   # Observation-specific FHIRPath → Swift extractor logic
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
- **Generated code IS committed to git** — reviewable, diffable. Mark generated files clearly (header comment) and never hand-edit them.
- Generator inputs (the FHIR R4 `SearchParameter` bundle JSON) live under `Resources/fhir/search-parameters-r4.json`.
- SQL migrations under `migrations/`. Filename without `.sql` is the migration version recorded in `schema_migrations`.

## The three doors to keep open (architecture discipline, zero feature cost now)

1. **Validation hook** — leave an (empty) hook point in the write path for future profile validation.
2. **Auth as middleware** — never hardwire auth into handlers. Early stage: simple token or trusted-network assumption.
3. **Search via generator** — already covered; this is also the R5 door.

**How to judge if a change welds a door shut:** ask "could a future feature (profile validation / OAuth / R5 / `_history`) be added without rewriting this?" If adding it later would force a schema migration or a handler rewrite, the door is being welded — stop and restructure. Cheap-to-add-later is fine; expensive-to-add-later is the smell.

## Deferred — do not build now

- Inferno / Touchstone compliance → north star only, NOT on the roadmap. Passing it is its own large project.
- SMART on FHIR / OAuth → much later.
- R5 → not built (generator preserves the path).
- terminology, `_revinclude`, transaction bundle, subscription → stage 3+.

## Running the benchmark

```bash
# 1. Start Siming's DB
docker-compose up -d db

# 2. Start HAPI + its DB (first run pulls ~500 MB image; HAPI takes ~60 s to start)
docker-compose -f docker-compose.yml -f docker-compose.benchmark.yml up -d hapi

# 3. Build and start Siming — always use release build for benchmarking
swift build -c release
PGHOST=localhost PGUSER=siming PGPASSWORD=siming PGDATABASE=siming \
  .build/release/SimingServer &

# 4. Wait for both servers, then run
BENCH_DURATION=30s BENCH_CONNS=20 SEED_N=5000 \
  bash benchmarks/bench.sh

# Results: benchmarks/results/bench-<timestamp>.md
```

Environment variables:
- `SEED_N` — patients to create before benchmarking (default: 1000; use 5000+ for meaningful results)
- `BENCH_DURATION` — oha `-z` value per scenario (default: 30s)
- `BENCH_CONNS` — oha `-c` value (default: 20)
- `SKIP_SEED=1` — reuse IDs from previous run
- `SIMING_URL` / `HAPI_URL` — override default ports (8080 / 8081/fhir)

**Important:** always reset both databases before a comparison run to avoid data pollution from the POST scenario. The POST body uses `birthDate: 1950-06-15` intentionally — a date that does not match the `ge1990-01-01` search scenario.

```bash
# Reset Siming
docker exec siming-db-1 psql -U siming -d siming \
  -c "TRUNCATE resources, idx_token, idx_string, idx_date, idx_reference, idx_quantity;"
# Reset HAPI (hapi-db has no volume; restart clears it)
docker-compose -f docker-compose.yml -f docker-compose.benchmark.yml restart hapi-db hapi
```

## Benchmarking — honesty rule

When benchmarking against HAPI, compare **under the same feature set only**. HAPI is often slow because it does MORE (profile validation, _revinclude recursion, terminology expansion). Claiming "an order of magnitude faster" while supporting less is dishonest and the first expert will see through it. State the feature set alongside any number.

**Storage backend matters.** HAPI's default storage is H2 (JVM in-process, no TCP overhead). Always use the PostgreSQL-backed HAPI from `docker-compose.benchmark.yml` for a fair comparison.

**HAPI POST at ≥20 connections collapses (~50% failure rate).** The POST scenario numbers for HAPI at `BENCH_CONNS=20` are not trustworthy; treat the POST comparison as informational only.

### Benchmark results (2026-06-05, release build, 5000 patients, both PostgreSQL)

| Scenario | Siming v1 | Siming v2 | Siming v3 | HAPI | Ratio (v3) |
|---|---|---|---|---|---|
| POST /Patient (create) | 547 RPS | — | — | ~2300 RPS (51% ok — unreliable) | — |
| GET /Patient/:id (read) | 9353 RPS | 9309 RPS | **16577 RPS** | 7055 RPS | **2.35x faster** |
| GET /Patient?name=Wang | 630 RPS | 677 RPS | **2420 RPS** | 1560 RPS | **1.55x faster** |
| GET /Patient?birthdate=ge1990-01-01 | 562 RPS | 680 RPS | **1623 RPS** | 1894 RPS | 0.86x |

**v2 optimisations (migration 0002 + deferred-content SQL):**
- `resources_live_idx` partial covering index — enables index-only scan for the `ids` CTE.
- `idx_date_end_covering_idx` / `idx_date_start_covering_idx` — index-only scan on date filter CTEs.
- `idx_token_lookup_idx` / `idx_reference_lookup_idx` — covering indexes include `resource_id` for index-only DISTINCT scans.
- Deferred-content SQL: `ids` CTE (no content) → `paged` CTE (cursor + LIMIT) → final JOIN for content only.

**v3 optimisations (raw JSON passthrough):**
- `JSONPassthrough.swift`: `injectMeta()` appends `,"meta":{...}` before the final `}` using byte manipulation — zero parse, zero FHIRModels decode/encode on reads.
- `buildBundleJSON()`: builds searchset Bundle as raw bytes, embedding pre-formatted resource JSON directly — eliminates FHIRModels Bundle Codable overhead.
- Write path: stored JSON string reused as response via `injectMeta()` — eliminates second `JSONEncoder.encode()`.
- FHIRModels still used on the write path (parse + validate incoming JSON, extract search params) and for OperationOutcome error responses — the type-safe search extractor (generator moat) is unaffected.

## Observability (product differentiator — done, not aspirational)

HAPI's biggest user complaint is useless logs and silent lock-ups. Siming builds this in from day one.

### What's implemented

**`GET /metrics`** — Prometheus text format (content-type `text/plain; version=0.0.4`):
- `http_requests_total{method, path, status}` counter
- `http_request_duration_seconds{method, path}` histogram (13 default buckets)
- Path normalisation: `/Patient/:id` collapses all by-ID requests to prevent label cardinality explosion

**`MetricsMiddleware`** — wraps every request:
- Generates `X-Request-ID` (UUID v4) if not present; echoes it in the response header
- Structured log on request arrival (`→ METHOD /path`) and completion (`← status METHOD /path ms=N`)
- Both `requestId` and `ms` appear as structured metadata fields — grep-able and JSON-parseable
- Records metrics on both success and error paths

**Bootstrap:** `PrometheusMetricsFactory` registered as the global `MetricsSystem` backend at startup.

### Usage pattern

```bash
# Scrape metrics (Prometheus, Grafana, or curl)
curl http://localhost:8080/metrics

# Tail logs and filter by trace ID
tail -f /tmp/siming.log | grep "requestId=abc-123"
```

### Adding new metrics

Use `swift-metrics` API anywhere in the codebase — the Prometheus backend is global:
```swift
import Metrics
Counter(label: "fhir_validation_errors_total", dimensions: [("resource", "Patient")]).increment()
Timer(label: "db_query_duration_seconds", dimensions: [("query", "search")]).recordSeconds(elapsed)
```

## Roadmap — stage 0 is the heart, not a warm-up

1. ✅ Schema: `0001` migration for `resources` (history-preserving) + 5 index tables; PostgresNIO connection layer + `MigrationRunner` working.
2. ✅ Generator: `SimingGenerator` reads `Resources/fhir/search-parameters-r4.json`, emits `Sources/SimingCore/Generated/Patient+SearchExtractor.swift` (23 params; 4 complex FHIRPath expressions are TODO stubs). Run `swift run SimingGenerator` to regenerate.
3. ✅ Write path: POST/PUT/GET Patient fully wired. `PatientStore` (create/update/read + optimistic locking via `If-Match`). `FHIRServerError` mapped to `OperationOutcome` + correct HTTP status. Routes in `Sources/SimingServer/Routes/PatientRoutes.swift`.
4. ✅ Read path: `GET /Patient` search — `name` (trigram ILIKE), `identifier` (token, system optional), `birthdate` (range prefixes eq/lt/gt/le/ge); `_sort=±_lastUpdated`; `_count`; cursor keyset pagination via `_cursor` (base64 URL-safe token). Returns FHIR searchset Bundle with `total`, `link.self`, `link.next`.
5. ✅ `/metadata` CapabilityStatement — kind=instance, fhirVersion=4.0.1, Patient resource with read/create/update/search-type interactions + name/identifier/birthdate searchParam definitions.
6. ✅ Benchmark harness + search SQL optimisation: `benchmarks/bench.sh` — 4 scenarios (POST, GET/:id, name search, date search); `oha` with JSON output; seeds via `benchmarks/seed.sh`; results saved to `benchmarks/results/bench-<ts>.md`. HAPI service defined in `docker-compose.benchmark.yml` (PostgreSQL backend for fair comparison). Search SQL rewritten from correlated EXISTS to filter-CTE + JOIN pattern (5x faster for date search). Baseline: GET/:id 1.33x faster than HAPI; search at 0.3–0.4x (next optimisation target).

7. ✅ Observability: `MetricsMiddleware` (trace ID + structured logs) + `GET /metrics` (Prometheus counter + latency histogram). `swift-prometheus 2.3.0` + `swift-metrics 2.11.0`. Path normalisation prevents label cardinality explosion. "You can always tell what the server is doing" is now a fact, not a claim.

8. ✅ Observation resource: POST/GET/search fully wired. Generator produced 38 params (`ObservationHandlers.swift` → `Observation+SearchExtractor.swift`). `ObservationStore` (create/update/read/search with filter-CTE SQL). Search params: subject (idx_reference), code (idx_token), status (idx_token), category (idx_token), date/effectiveDateTime/period (idx_date). Validates the generator "near-zero cost" promise: adding a second resource required only handlers + store + routes, zero schema change.

9. ✅ Search performance optimisation (round 1): migration `0002_search_indexes` adds covering indexes on all five idx_* tables (resource_id included → index-only scans) + `resources_live_idx` partial covering index (non-deleted rows only). Deferred-content SQL pattern: `ids` CTE selects only id/version_id/last_updated; `paged` CTE applies cursor + LIMIT; final JOIN fetches content for the page only. Results: birthdate search +21%, name search +7.5%; sort memory reduced from 762 kB → 204 kB. Remaining gap vs HAPI was application-layer JSON decode/encode, not DB.

10. ✅ Raw JSON passthrough (performance round 2): `JSONPassthrough.swift` provides `injectMeta()` (byte-level meta injection, zero parse) + `buildBundleJSON()` (raw-bytes Bundle assembly). `PatientStore`/`ObservationStore` result types now carry `Data` not FHIRModels objects; read/search/write all use passthrough. Routes use `buildBundleJSON()` instead of FHIRModels Bundle Codable. Results: GET/:id **16,577 RPS** (1.77x over v2, **2.35x over HAPI**); name search **2,420 RPS** (3.57x over v2, **1.55x over HAPI**); date search **1,623 RPS** (2.39x over v2, 0.86x vs HAPI). FHIRModels role preserved: write-path parse/validate + search extraction — the generator moat is untouched.

11. ✅ FHIR R4 baseline interactions — `DELETE /[type]/[id]` (logical delete: insert deleted=true row in transaction + clear index tables; 204 response; subsequent GET → 410 Gone); `GET /[type]/[id]/_history/[vid]` (vread: exact version; 410 if delete marker); `GET /[type]/[id]/_history` (instance history: raw-bytes Bundle of type `history`, newest-first; request/response elements inferred from version metadata); `Last-Modified` RFC 7231 header on all write + read responses. `buildHistoryBundleJSON()` added to `JSONPassthrough.swift`. MetadataRoutes updated: delete/vread/history-instance declared for both Patient and Observation; Observation resource added to CapabilityStatement; `readHistory=true`.

12. ✅ Conditional read — `If-None-Match` (ETag match → 304 Not Modified) and `If-Modified-Since` (timestamp check → 304) on `GET /[type]/[id]` and vread. RFC 7232 §6 precedence: If-None-Match wins when both headers present. Sub-second DB timestamps truncated to second precision before comparing with HTTP-date. `parseHTTPDate()` added to `JSONPassthrough.swift`. Applied to both Patient and Observation.

13. ✅ Automated unit tests — 32 pure-logic tests, no DB dependency (`swift test`). Suites: `JSONPassthrough` (injectMeta, buildBundleJSON, buildHistoryBundleJSON, httpDate/parseHTTPDate); `PatientSearchQuery` (SortOrder, IdentifierParam, BirthdateParam with prefixes/partial dates, SearchCursor encode/decode); `ObservationSearchQuery` (TokenParam, DateParam); `DatabaseConfiguration`. Side-fix: `parseFHIRDate` now validates month (1–12) and day (1–31) — previously Calendar silently overflowed invalid values.

15. ✅ Search compliance round 1 — FHIR R4 search semantics corrections:
    - **String starts-with** (default) replaces previous `contains` behaviour; `name:contains` and `name:exact` modifiers now supported. `PatientSearchQuery.StringParam` struct added.
    - **Token OR**: comma-separated values parsed as OR (`status=final,amended`, `code=A,B`). `IdentifierParam.parseList()` / `TokenParam.parseList()` added; all token params in ObservationSearchQuery changed to `[TokenParam]` / `[String]` arrays.
    - **`_id` filter**: `GET /Patient?_id=abc-123` and `GET /Observation?_id=x` supported (direct `r.id IN (...)` condition in ids CTE); comma-separated for multi-id OR.
    - **`_lastUpdated` filter**: `GET /Patient?_lastUpdated=ge2024-01-01` supported; same prefix semantics as birthdate/date; applies to `r.last_updated` in the ids CTE.
    - **`sa` / `eb` date prefixes**: `sa` (starts-after → `date_start > X`) and `eb` (ends-before → `date_end < X`) added to `BirthdateParam.Prefix`; supported in birthdate and Observation date filters.
    - Tests expanded from 32 → 42 (StringParam parse, IdentifierParam/TokenParam parseList, sa/eb prefixes).

14. ✅ Compartment search + count-only query + Bundle.total fix:
    - `GET /Patient/:id/Observation[?params]` — FHIR patient compartment (`CompartmentRoutes.swift`); forces `subject=Patient/:id` server-side; returns same searchset Bundle as regular Observation search. `CapabilityStatementRest.compartment` added to `/metadata`.
    - `_count=0` — count-only mode; `ObservationStore.search()` / `PatientStore.search()` detect `count=0` early and call `buildCountSQL()` which returns `SELECT COUNT(*) FROM ids` — no content fetch, no paged CTE.
    - Fixed latent Bundle.total bug: moved count from `COUNT(*) OVER ()` in `paged` CTE to a separate `total_count AS (SELECT COUNT(*) AS n FROM ids)` CTE; final SELECT uses `CROSS JOIN total_count t` to get `t.n`. This ensures Bundle.total on page 2+ reflects the full matching set, not the cursor-filtered remainder.
    - Fixed MetricsMiddleware path normalisation: `/Patient/abc/_history/1` → `/Patient/:id/_history/:vid` (version id was previously leaking into Prometheus labels).

## Working rules for Claude Code

- Verify package versions against GitHub/registry before pinning — never from memory.
- Hand-tuned SQL over ORM abstractions; this project's whole value is storage/search performance.
- Make minimal changes; don't refactor unrelated code.
- Never hand-edit generated files; change the generator instead.
- Keep the three doors (validation hook, auth middleware, generator) unwelded in every change — apply the weld test above.
- **Before implementing or changing any FHIR behaviour, look up the R4 spec first.** This applies to: search parameter semantics (string starts-with vs contains, token OR with commas, date prefixes sa/eb/ap), HTTP interaction rules (status codes, headers, conditional logic), resource structure, and Bundle assembly. Do not guess or rely on memory — the spec is the source of truth. Known open gaps vs spec: `ap` (approximate) date prefix not implemented; `system|` token format (match any code for a given system) not implemented; `_sort` only supports `_lastUpdated`; no `:text` or `:not` modifiers.
- Build and run tests after a series of changes before declaring done.
- Every FHIR endpoint **must** check/set `Content-Type: application/fhir+json` and return `OperationOutcome` on error — no exceptions.
- Every write runs in a single PostgresNIO transaction (insert resource + replace index rows). Never split across requests or do half-writes.