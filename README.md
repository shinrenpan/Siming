# Siming

A high-performance FHIR R4 server written in Swift.

**Stack:** [Hummingbird 2](https://github.com/hummingbird-project/hummingbird) (SwiftNIO) · [PostgresNIO](https://github.com/vapor/postgres-nio) (no ORM) · [FHIRModels](https://github.com/apple/FHIRModels)

## Quick start

```bash
# Requires Docker
docker compose up --build
```

Server listens on `http://localhost:8080`. PostgreSQL starts automatically and migrations run at boot.

## FHIR R4 capabilities

| Feature | Status |
|---|---|
| Patient + Observation CRUD | ✓ |
| vread (`/[type]/[id]/_history/[vid]`) | ✓ |
| History — instance, type, system | ✓ |
| Search — 15 Patient / 12+ Observation params | ✓ |
| Search modifiers: `:contains` `:exact` `:not` `:missing` | ✓ |
| Date prefixes: `eq` `lt` `gt` `le` `ge` `sa` `eb` | ✓ |
| `_sort`, `_count`, cursor pagination | ✓ |
| Compartment search (`GET /Patient/:id/Observation`) | ✓ |
| Conditional read (`If-None-Match` / `If-Modified-Since`) | ✓ |
| Conditional create (`If-None-Exist`) | ✓ |
| Conditional update (`PUT /[type]?<search>`) | ✓ |
| Conditional delete (`DELETE /[type]?<search>`) | ✓ |
| `_format` negotiation; 406 for non-JSON | ✓ |
| CapabilityStatement (`GET /metadata`) | ✓ |
| Prometheus metrics (`GET /metrics`) | ✓ |

All error responses are `OperationOutcome`. `ETag` / `If-Match` optimistic locking on updates.

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

Requires Swift 6.2+ and a running PostgreSQL instance.

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
