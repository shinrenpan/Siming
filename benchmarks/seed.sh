#!/usr/bin/env bash
# seed.sh <base_url> <n_patients> [id_file]
# Seeds N patients into a FHIR server, outputs newline-separated IDs.
# Usage:
#   ./benchmarks/seed.sh http://127.0.0.1:8080 1000 /tmp/siming-ids.txt
#   ./benchmarks/seed.sh http://127.0.0.1:8081/fhir 1000 /tmp/hapi-ids.txt

set -euo pipefail

BASE_URL="${1:?Usage: seed.sh <base_url> <n_patients> [id_file]}"
N="${2:?Usage: seed.sh <base_url> <n_patients> [id_file]}"
ID_FILE="${3:-/tmp/fhir-seed-ids.txt}"

FAMILIES=(Wang Chen Lin Wu Zhang Liu Yang Huang Zhao Chen)
GIVEN=(Wei Li Fang Hong Ming Jing Xia Yang Lei Hui)
GENDERS=(male female)
YEARS=(1975 1978 1980 1982 1985 1987 1990 1992 1995 1998)
MONTHS=(01 02 03 04 05 06 07 08 09 10 11 12)
DAYS=(01 05 10 15 20 25 28)

> "$ID_FILE"
ok=0
fail=0

for i in $(seq 1 "$N"); do
    FAMILY=${FAMILIES[$((RANDOM % ${#FAMILIES[@]}))]}
    GIVEN_=${GIVEN[$((RANDOM % ${#GIVEN[@]}))]}
    GENDER=${GENDERS[$((RANDOM % ${#GENDERS[@]}))]}
    BD="${YEARS[$((RANDOM % ${#YEARS[@]}))]}-${MONTHS[$((RANDOM % ${#MONTHS[@]}))]}-${DAYS[$((RANDOM % ${#DAYS[@]}))]}"
    MRN="MRN-$(printf '%06d' "$i")"

    BODY=$(cat <<JSON
{
  "resourceType": "Patient",
  "identifier": [{"system": "http://bench.example/mrn", "value": "$MRN"}],
  "name": [{"family": "$FAMILY", "given": ["$GIVEN_"]}],
  "gender": "$GENDER",
  "birthDate": "$BD"
}
JSON
)

    HTTP_CODE=$(curl -sf -o /tmp/_seed_body.json -w '%{http_code}' -X POST "$BASE_URL/Patient" \
        -H 'Content-Type: application/fhir+json' \
        -d "$BODY" 2>/dev/null) || { fail=$((fail+1)); continue; }

    if [[ "$HTTP_CODE" == "201" ]]; then
        ID=$(python3 -c "import json,sys; print(json.load(open('/tmp/_seed_body.json'))['id'])" 2>/dev/null) || true
        if [[ -n "${ID:-}" ]]; then
            echo "$ID" >> "$ID_FILE"
            ok=$((ok+1))
        else
            fail=$((fail+1))
        fi
    else
        fail=$((fail+1))
    fi

    if (( i % 100 == 0 )); then
        echo "  seeded $i / $N (ok=$ok fail=$fail)" >&2
    fi
done

echo "Done: ok=$ok fail=$fail  IDs → $ID_FILE" >&2
