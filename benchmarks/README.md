# Benchmarks

## Running

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
```

Results saved to `benchmarks/results/bench-<timestamp>.md`.

### Environment variables

| Variable | Default | Description |
|---|---|---|
| `SEED_N` | 1000 | Patients to create before benchmarking (use 5000+ for meaningful results) |
| `BENCH_DURATION` | 30s | oha `-z` value per scenario |
| `BENCH_CONNS` | 20 | oha `-c` value |
| `SKIP_SEED` | — | Set to `1` to reuse IDs from previous run |
| `SIMING_URL` | `http://localhost:8080` | Override Siming base URL |
| `HAPI_URL` | `http://localhost:8081/fhir` | Override HAPI base URL |

### Resetting databases

Always reset before a comparison run to avoid data pollution from the POST scenario.
The POST body uses `birthDate: 1950-06-15` intentionally — does not match the `ge1990-01-01` search scenario.

```bash
# Reset Siming
docker exec siming-db-1 psql -U siming -d siming \
  -c "TRUNCATE resources, idx_token, idx_string, idx_date, idx_reference, idx_quantity;"

# Reset HAPI (hapi-db has no volume; restart clears it)
docker-compose -f docker-compose.yml -f docker-compose.benchmark.yml restart hapi-db hapi
```

## Honesty rule

Compare under the **same feature set only**. HAPI is often slow because it does more (profile validation, `_revinclude`, terminology). Claiming speed advantage while supporting less is dishonest. State what's supported alongside any number.

Storage backend matters: always use the PostgreSQL-backed HAPI from `docker-compose.benchmark.yml`, not the default H2 backend.

HAPI POST at ≥20 connections has ~50% failure rate — treat POST comparison as informational only.

## Results history

### 2026-06-05 — v3 (release build, 5000 patients, both PostgreSQL)

| Scenario | Siming v1 | Siming v2 | Siming v3 | HAPI | Ratio (v3) |
|---|---|---|---|---|---|
| POST /Patient (create) | 547 RPS | — | — | ~2300 RPS (51% ok — unreliable) | — |
| GET /Patient/:id (read) | 9353 RPS | 9309 RPS | **16577 RPS** | 7055 RPS | **2.35x faster** |
| GET /Patient?name=Wang | 630 RPS | 677 RPS | **2420 RPS** | 1560 RPS | **1.55x faster** |
| GET /Patient?birthdate=ge1990-01-01 | 562 RPS | 680 RPS | **1623 RPS** | 1894 RPS | 0.86x |

**v2 optimisations** (migration `0002` + deferred-content SQL):
- `resources_live_idx` partial covering index → index-only scan for the `ids` CTE.
- Covering indexes on all `idx_*` tables (resource_id included) → index-only DISTINCT scans.
- Deferred-content SQL: `ids` CTE (no content) → `paged` CTE (cursor + LIMIT) → final JOIN for content only.

**v3 optimisations** (raw JSON passthrough):
- `injectMeta()`: appends `,"meta":{...}` before the final `}` using byte manipulation — zero parse on reads.
- `buildBundleJSON()`: builds searchset Bundle as raw bytes — eliminates FHIRModels Bundle Codable overhead.
- Write path: stored JSON reused as response — eliminates second `JSONEncoder.encode()`.
- FHIRModels role preserved: write-path parse/validate + search extraction. Generator moat untouched.
