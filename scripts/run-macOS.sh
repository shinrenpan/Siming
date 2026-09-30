#!/usr/bin/env bash
# Local macOS development: start Postgres in Docker, then run SimingServer natively (release build).
# Use this for all day-to-day development and testing on macOS.
set -euo pipefail

cd "$(dirname "$0")/.."

# The db container takes its credentials from .env; read the same PG* values (not by
# sourcing .env — compose env files allow unquoted spaces that bash would execute).
env_value() { [ -f .env ] && sed -n "s/^$1=//p" .env | tail -n 1 || true; }
export PGHOST=127.0.0.1   # compose publishes db on loopback only
export PGPORT=5432
export PGUSER="${PGUSER:-$(env_value PGUSER)}";             PGUSER="${PGUSER:-siming}"
export PGPASSWORD="${PGPASSWORD:-$(env_value PGPASSWORD)}"; PGPASSWORD="${PGPASSWORD:-siming}"
export PGDATABASE="${PGDATABASE:-$(env_value PGDATABASE)}"; PGDATABASE="${PGDATABASE:-siming}"
unset DATABASE_URL

echo "Starting Postgres..."
docker compose up -d db

echo "Waiting for Postgres to be healthy..."
until docker compose exec db pg_isready -U "$PGUSER" -q 2>/dev/null; do
  sleep 1
done

echo "Starting SimingServer (release build)..."
swift run -c release SimingServer
