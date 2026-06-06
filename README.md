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

> **Note:** Linux / Docker builds are currently unsupported. FHIRModels 0.9.2 depends on
> Apple's `os` framework (`import os`), which is unavailable on Linux. This will be
> restored once FHIRModels ships a Linux-compatible release.

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

### Interactions

| Feature | Status |
|---|---|
| read, vread, create, update, patch, delete | ✓ |
| history — instance, type, system | ✓ |
| `/_history?_type=Patient,Observation,...` | ✓ |
| Conditional create (`If-None-Exist`) | ✓ |
| Conditional update (`PUT /[type]?<search>`) | ✓ |
| Conditional delete (`DELETE /[type]?<search>`) | ✓ |
| JSON Patch (`PATCH /[type]/:id`, RFC 6902) — all 21 resource types | ✓ |
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
| `_sort`, `_count`, cursor pagination | ✓ |
| `_total` (`accurate` \| `none`) | ✓ |
| `_elements` (field projection) | ✓ |
| `_summary` (`true` \| `text` \| `data` \| `count` \| `false`) | ✓ |
| `_format` negotiation; 406 for non-JSON | ✓ |
| POST `/_search` (form-encoded) | ✓ |
| `_include` / `_revinclude` (1-level, all 21 resources) | ✓ |
| Chained search (`subject.name=Wang`, `patient.birthdate=ge1990`, etc.) | ✓ |
| `_has` reverse chaining (`_has:Observation:subject:code=85354-9`) | ✓ |

**Patient** — `name`, `family`, `given`, `identifier`, `gender`, `birthdate`, `address`, `address-city`, `address-state`, `address-country`, `address-postalcode`, `phone`, `email`, `active`, `deceased`, `_id`, `_lastUpdated`

**Observation** — `subject`, `patient`, `code`, `status`, `category`, `date`, `value-quantity`, `identifier`, `_id`, `_lastUpdated`

**Encounter** — `subject`, `patient`, `status`, `class`, `type`, `date`, `identifier`, `_id`, `_lastUpdated`

**Condition** — `subject`, `patient`, `clinical-status`, `verification-status`, `category`, `severity`, `code`, `body-site`, `encounter`, `onset-date`, `abatement-date`, `recorded-date`, `identifier`, `_id`, `_lastUpdated`

**MedicationRequest** — `subject`, `patient`, `status`, `intent`, `medication`, `code`, `priority`, `authored-on`, `identifier`, `_id`, `_lastUpdated`

**AllergyIntolerance** — `patient`, `clinical-status`, `verification-status`, `type`, `category`, `criticality`, `code`, `identifier`, `date`, `manifestation`, `severity`, `route`, `last-date`, `onset`, `_id`, `_lastUpdated`

**Procedure** — `subject`, `patient`, `status`, `code`, `category`, `identifier`, `encounter`, `performer`, `date`, `_id`, `_lastUpdated`

**DiagnosticReport** — `subject`, `patient`, `status`, `code`, `category`, `identifier`, `encounter`, `performer`, `date`, `issued`, `_id`, `_lastUpdated`

**Immunization** — `patient`, `status`, `vaccine-code`, `identifier`, `date`, `performer`, `lot-number`, `_id`, `_lastUpdated`

**Practitioner** — `name`, `family`, `given`, `identifier`, `active`, `gender`, `address`, `address-city`, `address-state`, `address-country`, `address-postalcode`, `phone`, `email`, `communication`, `_id`, `_lastUpdated`

**Organization** — `name`, `identifier`, `active`, `type`, `address`, `address-city`, `address-state`, `address-country`, `address-postalcode`, `partof`, `_id`, `_lastUpdated`

**Medication** — `code`, `status`, `form`, `identifier`, `lot-number`, `ingredient-code`, `manufacturer`, `ingredient`, `expiration-date`, `_id`, `_lastUpdated`

**Location** — `name`, `identifier`, `status`, `type`, `operational-status`, `address`, `address-city`, `address-state`, `address-country`, `address-postalcode`, `organization`, `partof`, `_id`, `_lastUpdated` (`near` geospatial not supported)

**RelatedPerson** — `name`, `phonetic` (alias for `name`), `identifier`, `active`, `gender`, `relationship`, `birthdate`, `address`, `address-city`, `address-state`, `address-country`, `address-postalcode`, `address-use`, `phone`, `email`, `telecom`, `patient`, `_id`, `_lastUpdated`

**ServiceRequest** — `status`, `intent`, `priority`, `code`, `category`, `body-site`, `performer-type`, `requisition`, `identifier`, `authored`, `occurrence`, `subject`, `patient`, `encounter`, `requester`, `performer`, `based-on`, `replaces`, `specimen`, `_id`, `_lastUpdated`

**Specimen** — `status`, `type`, `accession`, `identifier`, `bodysite`, `container`, `container-id`, `collected`, `subject`, `patient`, `collector`, `parent`, `_id`, `_lastUpdated`

**DocumentReference** — `status`, `type`, `category`, `identifier`, `security-label`, `facility`, `event`, `description`, `date`, `period`, `subject`, `patient`, `author`, `encounter`, `_id`, `_lastUpdated`

**CarePlan** — `status`, `intent`, `category`, `identifier`, `activity-code`, `date` (period), `subject`, `patient`, `encounter`, `care-team`, `condition`, `goal`, `based-on`, `part-of`, `replaces`, `performer`, `activity-reference`, `_id`, `_lastUpdated`

**Goal** — `lifecycle-status`, `achievement-status`, `category`, `identifier`, `start-date`, `target-date`, `subject`, `patient`, `_id`, `_lastUpdated`

**MedicationStatement** — `status`, `category`, `code`, `identifier`, `effective`, `subject`, `patient`, `context`, `source`, `medication`, `part-of`, `_id`, `_lastUpdated`

**FamilyMemberHistory** — `status`, `relationship`, `sex`, `code`, `identifier`, `date`, `patient`, `_id`, `_lastUpdated`

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

| Scenario | Siming | HAPI FHIR |
|---|---|---|
| GET /Patient/:id | 16 577 RPS | 7 055 RPS |
| GET /Patient?name=Wang | 2 420 RPS | 1 560 RPS |

## License

MIT — see [LICENSE](LICENSE).
