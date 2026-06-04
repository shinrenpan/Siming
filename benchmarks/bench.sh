#!/usr/bin/env bash
# bench.sh — Siming vs HAPI same-feature-set benchmark
#
# Prerequisites:
#   - oha installed (brew install oha)
#   - Siming running on SIMING_URL (default http://127.0.0.1:8080)
#   - HAPI running on HAPI_URL    (default http://127.0.0.1:8081/fhir)
#     Start HAPI: docker-compose -f docker-compose.yml -f docker-compose.benchmark.yml up -d hapi
#
# Environment variables:
#   SIMING_URL      — Siming base URL  (default: http://127.0.0.1:8080)
#   HAPI_URL        — HAPI base URL    (default: http://127.0.0.1:8081/fhir)
#   SEED_N          — patients to seed (default: 1000)
#   BENCH_DURATION  — oha duration     (default: 30s)
#   BENCH_CONNS     — oha connections  (default: 20)
#   SKIP_SEED       — set to 1 to skip seeding (reuse previous run)
#   SIMING_IDS_FILE — pre-seeded IDs file for Siming (default: /tmp/siming-ids.txt)
#   HAPI_IDS_FILE   — pre-seeded IDs file for HAPI   (default: /tmp/hapi-ids.txt)
#
# Feature set compared (CLAUDE.md honesty rule):
#   - POST /Patient (create)
#   - GET /Patient/:id (read by server-assigned id)
#   - GET /Patient?name=<string> (string search)
#   - GET /Patient?birthdate=ge<date> (date range search)
#
# Storage note:
#   Siming: PostgreSQL 16 (docker, same host)
#   HAPI:   PostgreSQL 16 (docker, same host) — same storage backend for fair comparison

set -euo pipefail

SIMING_URL="${SIMING_URL:-http://127.0.0.1:8080}"
HAPI_URL="${HAPI_URL:-http://127.0.0.1:8081/fhir}"
SEED_N="${SEED_N:-1000}"
BENCH_DURATION="${BENCH_DURATION:-30s}"
BENCH_CONNS="${BENCH_CONNS:-20}"
SKIP_SEED="${SKIP_SEED:-0}"
SIMING_IDS="${SIMING_IDS_FILE:-/tmp/siming-ids.txt}"
HAPI_IDS="${HAPI_IDS_FILE:-/tmp/hapi-ids.txt}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
RESULTS_DIR="$SCRIPT_DIR/results"
mkdir -p "$RESULTS_DIR"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
RESULT_FILE="$RESULTS_DIR/bench-$TIMESTAMP.md"

# ── Helpers ───────────────────────────────────────────────────────────────────

check_tool() {
    command -v "$1" >/dev/null 2>&1 || { echo "ERROR: $1 not found. Install with: brew install $1" >&2; exit 1; }
}

wait_for_server() {
    local url="$1"
    local name="$2"
    local max=30
    echo -n "Waiting for $name ... " >&2
    for i in $(seq 1 $max); do
        if curl -sf "$url" >/dev/null 2>&1; then
            echo "up" >&2; return 0
        fi
        sleep 2
    done
    echo "TIMEOUT" >&2; exit 1
}

random_id() {
    local file="$1"
    local total
    total=$(wc -l < "$file" | tr -d ' ')
    if [[ $total -eq 0 ]]; then echo ""; return; fi
    sed -n "$((RANDOM % total + 1))p" "$file"
}

# Runs oha for one scenario and extracts key metrics.
# Output: "RPS P50_MS P99_MS SUCCESS_PCT"
run_oha() {
    local label="$1"; shift
    local result
    result=$(oha --no-tui --output-format json "$@" 2>/dev/null) || { echo "0 0 0 0"; return; }
    echo "$result" | python3 -c "
import json, sys
d = json.load(sys.stdin)
s = d['summary']
p = d['latencyPercentiles']
rps  = s['requestsPerSec']
pct  = s['successRate'] * 100
p50  = (p.get('p50') or 0) * 1000
p99  = (p.get('p99') or 0) * 1000
print(f'{rps:.1f} {p50:.1f} {p99:.1f} {pct:.0f}')
"
}

# ── Preflight ─────────────────────────────────────────────────────────────────

check_tool oha
check_tool python3
check_tool curl

echo "=== Siming vs HAPI Benchmark ===" >&2
echo "Duration: $BENCH_DURATION  Connections: $BENCH_CONNS" >&2
echo "Siming: $SIMING_URL" >&2
echo "HAPI:   $HAPI_URL" >&2
echo "" >&2

wait_for_server "$SIMING_URL/health" "Siming"
wait_for_server "$HAPI_URL/metadata" "HAPI"

# ── Seed ─────────────────────────────────────────────────────────────────────

if [[ "$SKIP_SEED" == "0" ]]; then
    echo "Seeding $SEED_N patients → Siming ..." >&2
    bash "$SCRIPT_DIR/seed.sh" "$SIMING_URL" "$SEED_N" "$SIMING_IDS"
    echo "Seeding $SEED_N patients → HAPI ..." >&2
    bash "$SCRIPT_DIR/seed.sh" "$HAPI_URL" "$SEED_N" "$HAPI_IDS"
else
    echo "Skipping seed (SKIP_SEED=1)" >&2
fi

SIMING_TOTAL=$(wc -l < "$SIMING_IDS" | tr -d ' ')
HAPI_TOTAL=$(wc -l < "$HAPI_IDS" | tr -d ' ')
echo "Siming seeded: $SIMING_TOTAL  HAPI seeded: $HAPI_TOTAL" >&2
echo "" >&2

# Pick a representative ID from each server for read benchmarks
SIMING_ID=$(sed -n "1p" "$SIMING_IDS")
HAPI_ID=$(sed -n "1p" "$HAPI_IDS")

# ── Run scenarios ─────────────────────────────────────────────────────────────

PATIENT_JSON='{"resourceType":"Patient","name":[{"family":"Bench","given":["Load"]}],"gender":"female","birthDate":"1950-06-15"}'

echo "Running scenario: POST /Patient ..." >&2
SIMING_POST=$(run_oha "siming-post" \
    -z "$BENCH_DURATION" -c "$BENCH_CONNS" \
    -m POST -d "$PATIENT_JSON" \
    -H 'Content-Type: application/fhir+json' \
    "$SIMING_URL/Patient")

HAPI_POST=$(run_oha "hapi-post" \
    -z "$BENCH_DURATION" -c "$BENCH_CONNS" \
    -m POST -d "$PATIENT_JSON" \
    -H 'Content-Type: application/fhir+json' \
    "$HAPI_URL/Patient")

echo "Running scenario: GET /Patient/:id ..." >&2
SIMING_READ=$(run_oha "siming-read" \
    -z "$BENCH_DURATION" -c "$BENCH_CONNS" \
    "$SIMING_URL/Patient/$SIMING_ID")

HAPI_READ=$(run_oha "hapi-read" \
    -z "$BENCH_DURATION" -c "$BENCH_CONNS" \
    "$HAPI_URL/Patient/$HAPI_ID")

echo "Running scenario: GET /Patient?name=... ..." >&2
SIMING_SEARCH_NAME=$(run_oha "siming-search-name" \
    -z "$BENCH_DURATION" -c "$BENCH_CONNS" \
    "$SIMING_URL/Patient?name=Wang")

HAPI_SEARCH_NAME=$(run_oha "hapi-search-name" \
    -z "$BENCH_DURATION" -c "$BENCH_CONNS" \
    "$HAPI_URL/Patient?name=Wang")

echo "Running scenario: GET /Patient?birthdate=ge1990-01-01 ..." >&2
SIMING_SEARCH_DATE=$(run_oha "siming-search-date" \
    -z "$BENCH_DURATION" -c "$BENCH_CONNS" \
    "$SIMING_URL/Patient?birthdate=ge1990-01-01")

HAPI_SEARCH_DATE=$(run_oha "hapi-search-date" \
    -z "$BENCH_DURATION" -c "$BENCH_CONNS" \
    "$HAPI_URL/Patient?birthdate=ge1990-01-01")

# ── Format results ────────────────────────────────────────────────────────────

format_row() {
    local scenario="$1"
    local siming="$2"
    local hapi="$3"
    local s_rps s_p50 s_p99 s_pct
    local h_rps h_p50 h_p99 h_pct
    read -r s_rps s_p50 s_p99 s_pct <<< "$siming"
    read -r h_rps h_p50 h_p99 h_pct <<< "$hapi"
    local ratio=""
    if python3 -c "import sys; exit(0 if float('$h_rps') > 0 else 1)" 2>/dev/null; then
        ratio=$(python3 -c "print(f'{float(\"$s_rps\")/float(\"$h_rps\"):.2f}x')" 2>/dev/null || echo "N/A")
    fi
    printf "| %-30s | %8s | %6s | %6s | %4s%% | %8s | %6s | %6s | %4s%% | %6s |\n" \
        "$scenario" \
        "$s_rps" "$s_p50" "$s_p99" "$s_pct" \
        "$h_rps" "$h_p50" "$h_p99" "$h_pct" \
        "$ratio"
}

HEADER="# Siming vs HAPI Benchmark — $TIMESTAMP

**Feature set:** POST create, GET by id, name search, birthdate search
**Duration per scenario:** $BENCH_DURATION  **Connections:** $BENCH_CONNS
**Dataset:** ~$SIMING_TOTAL patients
**Storage:** both servers using PostgreSQL 16 (Docker, same host)

| Scenario                       |  Siming RPS |  p50ms |  p99ms | ok% |  HAPI RPS  |  p50ms |  p99ms | ok% | Ratio |
|--------------------------------|-------------|--------|--------|-----|------------|--------|--------|-----|-------|"

ROWS=$(format_row "POST /Patient (create)"       "$SIMING_POST"        "$HAPI_POST")
ROWS+=$'\n'$(format_row "GET  /Patient/:id (read)"      "$SIMING_READ"        "$HAPI_READ")
ROWS+=$'\n'$(format_row "GET  /Patient?name=Wang"       "$SIMING_SEARCH_NAME" "$HAPI_SEARCH_NAME")
ROWS+=$'\n'$(format_row "GET  /Patient?birthdate=ge..." "$SIMING_SEARCH_DATE" "$HAPI_SEARCH_DATE")

OUTPUT="$HEADER
$ROWS"

echo "$OUTPUT" | tee "$RESULT_FILE"
echo "" >&2
echo "Results saved → $RESULT_FILE" >&2
