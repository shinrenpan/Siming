# Siming

A high-performance FHIR R4 server written in Swift.

**Stack:** [Hummingbird 2](https://github.com/hummingbird-project/hummingbird) (SwiftNIO) · [PostgresNIO](https://github.com/vapor/postgres-nio) (no ORM) · [FHIRModels](https://github.com/apple/FHIRModels)

## Quick start

### macOS (recommended)

Swift is a first-class citizen on macOS — no VM overhead, faster builds, and the full Foundation stack. If you're on macOS, run natively.

Requires Swift 6.2+ and Docker (for Postgres only).

```bash
# Download FHIR packages (one-time setup)
bash scripts/fetch-packages.sh

# Start Postgres in Docker, then run server natively in release mode
bash scripts/run-macOS.sh
```

Server listens on `http://localhost:8080`.

### Docker (Linux / staging)

For Linux developers or integration/staging validation.

```bash
bash scripts/fetch-packages.sh   # one-time
bash scripts/run-docker.sh       # builds release image + starts full stack
```

## FHIR R4 capabilities

### Supported resources

| Resource | CRUD | Search | Compartment |
|---|---|---|---|
| Patient | ✓ | ✓ | — |
| Observation | ✓ | ✓ | `GET /Patient/:id/Observation` |
| Encounter | ✓ | ✓ | `GET /Patient/:id/Encounter` |
| Condition | ✓ | ✓ | `GET /Patient/:id/Condition` |
| Medication | ✓ | ✓ | — |
| MedicationRequest | ✓ | ✓ | `GET /Patient/:id/MedicationRequest` |
| AllergyIntolerance | ✓ | ✓ | `GET /Patient/:id/AllergyIntolerance` |
| Procedure | ✓ | ✓ | `GET /Patient/:id/Procedure` |
| DiagnosticReport | ✓ | ✓ | `GET /Patient/:id/DiagnosticReport` |
| Immunization | ✓ | ✓ | `GET /Patient/:id/Immunization` |
| Practitioner | ✓ | ✓ | — |
| Organization | ✓ | ✓ | — |
| Location | ✓ | ✓ | — |
| RelatedPerson | ✓ | ✓ | `GET /Patient/:id/RelatedPerson` |
| ServiceRequest | ✓ | ✓ | `GET /Patient/:id/ServiceRequest` |
| Specimen | ✓ | ✓ | `GET /Patient/:id/Specimen` |
| DocumentReference | ✓ | ✓ | `GET /Patient/:id/DocumentReference` |
| CarePlan | ✓ | ✓ | `GET /Patient/:id/CarePlan` |
| Goal | ✓ | ✓ | `GET /Patient/:id/Goal` |
| MedicationStatement | ✓ | ✓ | `GET /Patient/:id/MedicationStatement` |
| FamilyMemberHistory | ✓ | ✓ | `GET /Patient/:id/FamilyMemberHistory` |
| Appointment | ✓ | ✓ | `GET /Patient/:id/Appointment` |
| MedicationAdministration | ✓ | ✓ | `GET /Patient/:id/MedicationAdministration` |

### Interactions

| Feature | Status |
|---|---|
| read, vread, create, update, patch, delete | ✓ |
| Transaction Bundle (`POST /`, type=transaction) — atomic multi-resource, urn:uuid resolution | ✓ |
| history — instance, type, system | ✓ |
| `/_history?_type=Patient,Observation,...` | ✓ |
| Conditional create (`If-None-Exist`) | ✓ |
| Conditional update (`PUT /[type]?<search>`) | ✓ |
| Conditional delete (`DELETE /[type]?<search>`) | ✓ |
| JSON Patch (`PATCH /[type]/:id`, RFC 6902) — all 23 resource types | ✓ |
| Conditional read (`If-None-Match` / `If-Modified-Since`) | ✓ |
| `ETag` / `If-Match` optimistic locking | ✓ |
| `410 Gone` on deleted resource GET | ✓ |
| `Prefer: return=representation` / `return=minimal` / `return=OperationOutcome` on write | ✓ |
| CORS — preflight (`OPTIONS`) + response headers for browser-based Inferno / Touchstone | ✓ |
| `Content-Type: application/fhir+json; fhirVersion=4.0` on all FHIR responses | ✓ |
| `Bundle.id` + `Bundle.meta.lastUpdated` on all Bundle types (searchset / history / transaction-response) | ✓ |
| `resourceType` mismatch on write → 422 Unprocessable Entity | ✓ |
| CapabilityStatement `instantiates` + `patchFormat` | ✓ |
| `link.self` on history bundles (instance / type / system) | ✓ |
| `Content-Location` on read + vread — versioned URL per FHIR R4 §2.21.0.6 | ✓ |

### Search

| Feature | Status |
|---|---|
| Date prefixes: `eq` `lt` `gt` `le` `ge` `sa` `eb` | ✓ |
| String modifiers: `:contains` `:exact` `:text` | ✓ |
| Token modifier: `:not` | ✓ |
| `:missing` modifier | ✓ |
| Multiple values — OR (comma) / AND (repeated param) | ✓ |
| `_sort` (multi-key: `_sort=family,-birthdate`), `_count`, cursor pagination | ✓ |
| `_total` (`accurate` \| `estimate` \| `none`) | ✓ |
| `_elements` (field projection) | ✓ |
| `_summary` (`true` \| `text` \| `data` \| `count` \| `false`) | ✓ |
| `_format` negotiation; 406 for non-JSON | ✓ |
| POST `/_search` (form-encoded) | ✓ |
| `_include` / `_revinclude` (1-level, all 23 resources) | ✓ |
| Chained search (`subject.name=Wang`, `patient.birthdate=ge1990`, etc.) | ✓ |
| `_has` reverse chaining (`_has:Observation:subject:code=85354-9`) | ✓ |

For the full per-resource search parameter list, query `GET /metadata` — the CapabilityStatement is the authoritative source, built at runtime from loaded FHIR packages.

### Security

| Feature | Status |
|---|---|
| SMART on FHIR JWT Bearer (resource server) — `SMART_ISSUER` + JWKS or PEM | ✓ |
| `GET /.well-known/smart-configuration` | ✓ |
| Per-IP token-bucket rate limiting — `RATE_LIMIT_RPS` | ✓ |

Auth is opt-in: set `SMART_ISSUER` to enable. Rate limiting is opt-in: set `RATE_LIMIT_RPS` to enable. `/health` and `/metrics` are always exempt from rate limiting.

### Other

| Feature | Status |
|---|---|
| CapabilityStatement (`GET /metadata`) — built at runtime from FHIR packages; reflects SearchParameters and profiles from any loaded FHIR R4 IG | ✓ |
| Prometheus metrics (`GET /metrics`) | ✓ |
| `X-Request-ID` trace header | ✓ |

All error responses are `OperationOutcome`.

### IG packages

`GET /metadata` is built at server startup from FHIR R4 packages in `packages/`. Place any FHIR R4 IG `.tgz` in that directory and the CapabilityStatement will reflect its SearchParameters and StructureDefinition profiles automatically — no rebuild required.

`scripts/fetch-packages.sh` downloads the base R4 package (required) and an example IG package. Override the directory with `PACKAGES_DIR`.

## Configuration

Non-secret settings live in `config.yml` at the project root. Edit it to change ports, pool sizes, log level, and so on. The file ships with defaults that work out of the box.

Secrets and deployment overrides always use environment variables. **Environment variables take precedence over `config.yml`.**

### config.yml keys

| Key | Default | Description |
|---|---|---|
| `server.port` | `8080` | TCP port the server listens on |
| `server.baseUrl` | `http://localhost:8080` | Public base URL — must be set correctly behind a reverse proxy |
| `fhir.packagesDir` | `./packages` | Directory of FHIR IG `.tgz` packages |
| `capability.publisher` | `Siming` | `CapabilityStatement.publisher` |
| `capability.description` | `Siming FHIR R4 Server` | `CapabilityStatement.implementation.description` |
| `database.migrationsPath` | `./migrations` | Path to SQL migration files |
| `database.pool.min` | `4` | Minimum idle Postgres connections |
| `database.pool.max` | `40` | Maximum concurrent Postgres connections |
| `security.rateLimit.rps` | — | Requests/second per IP; enables rate limiting when set |
| `security.rateLimit.burst` | `2×rps` | Token bucket burst size |
| `logging.level` | `info` | Log level: `trace` `debug` `info` `warn` `error` |

### Environment variables

Environment variables override the corresponding `config.yml` field.

| Variable | Overrides | Description |
|---|---|---|
| `SERVER_PORT` | `server.port` | TCP port |
| `SERVER_BASE_URL` | `server.baseUrl` | Public base URL |
| `PACKAGES_DIR` | `fhir.packagesDir` | FHIR package directory |
| `MIGRATIONS_PATH` | `database.migrationsPath` | Migration files path |
| `DB_POOL_MIN` | `database.pool.min` | Min pool size |
| `DB_POOL_MAX` | `database.pool.max` | Max pool size |
| `LOG_LEVEL` | `logging.level` | Log level |
| `RATE_LIMIT_RPS` | `security.rateLimit.rps` | Rate limit RPS |
| `RATE_LIMIT_BURST` | `security.rateLimit.burst` | Rate limit burst |
| `DATABASE_URL` | — | Full Postgres URL (takes priority over PG* vars) |
| `PGHOST` | — | Postgres host (default: `localhost`) |
| `PGPORT` | — | Postgres port (default: `5432`) |
| `PGUSER` | — | Postgres user |
| `PGPASSWORD` | — | Postgres password |
| `PGDATABASE` | — | Postgres database name |
| `SMART_ISSUER` | — | Expected JWT `iss`; enables SMART bearer auth when set |
| `SMART_JWKS_URL` | — | JWKS endpoint URL — fetched at startup |
| `SMART_PUBLIC_KEY_PEM` | — | RSA public key PEM (alternative to `SMART_JWKS_URL`) |
| `SMART_AUDIENCE` | — | Expected JWT `aud` value (optional) |

## Building from source

**macOS (native):** Requires Swift 6.2+ and a running PostgreSQL instance.

```bash
DATABASE_URL=postgres://siming:siming@localhost:5432/siming swift run -c release SimingServer
```

**Docker (Linux release image):**

```bash
docker build -t siming .
docker run -e DATABASE_URL=postgres://... -p 8080:8080 siming
```

## Benchmarks

See [`benchmarks/README.md`](benchmarks/README.md) for setup and results.

Sample figures (release build, 5000 patients, both servers on PostgreSQL):

| Scenario | Siming | HAPI FHIR | Ratio |
|---|---|---|---|
| GET /Patient/:id | 15 515 RPS | 6 883 RPS | **2.25x** |
| GET /Patient?name=Wang | 2 512 RPS | 1 627 RPS | **1.54x** |

## License

MIT — see [LICENSE](LICENSE).
