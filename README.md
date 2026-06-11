# Siming

A high-performance FHIR R4 server written in Swift.

**Stack:** [Hummingbird 2](https://github.com/hummingbird-project/hummingbird) (SwiftNIO) · [PostgresNIO](https://github.com/vapor/postgres-nio) (no ORM) · [FHIRModels](https://github.com/apple/FHIRModels)

## Quick start

Requires macOS and a running PostgreSQL instance.

```bash
# Start PostgreSQL only (Docker)
docker compose up -d db

# Run server
PGHOST=localhost PGUSER=siming PGPASSWORD=siming PGDATABASE=siming swift run SimingServer
```

Server listens on `http://localhost:8080`.

> **Note:** Linux builds require Swift 6.2+. macOS and Linux (Docker) are both supported as of FHIRModels 0.9.3.

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

For the full per-resource search parameter list, see [`docs/search-params.md`](docs/search-params.md).

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
| CapabilityStatement (`GET /metadata`) | ✓ |
| Prometheus metrics (`GET /metrics`) | ✓ |
| `X-Request-ID` trace header | ✓ |

All error responses are `OperationOutcome`.

## Configuration

| Variable | Default | Description |
|---|---|---|
| `DATABASE_URL` | — | Full Postgres URL (takes priority over PG* vars) |
| `PGHOST` | `localhost` | Postgres host |
| `PGPORT` | `5432` | Postgres port |
| `PGUSER` | — | Postgres user |
| `PGPASSWORD` | — | Postgres password |
| `PGDATABASE` | — | Postgres database name |
| `MIGRATIONS_PATH` | `migrations` | Path to SQL migration files (relative to CWD) |
| `SMART_ISSUER` | — | Expected JWT `iss` value; enables SMART bearer auth when set |
| `SMART_JWKS_URL` | — | JWKS endpoint URL — fetched at startup to load public keys |
| `SMART_PUBLIC_KEY_PEM` | — | RSA public key PEM — alternative to `SMART_JWKS_URL` |
| `SMART_AUDIENCE` | — | Expected JWT `aud` value (optional) |
| `RATE_LIMIT_RPS` | — | Requests per second per IP; enables rate limiting when set |
| `RATE_LIMIT_BURST` | `2×RPS` | Token bucket burst size |

## Building from source

Requires Swift 6.2+ and a running PostgreSQL instance (macOS only).

```bash
swift build -c release
PGHOST=localhost PGUSER=siming PGPASSWORD=siming PGDATABASE=siming \
  .build/release/SimingServer
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
