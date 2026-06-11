#!/usr/bin/env bash
# Local macOS development: start Postgres in Docker, then run SimingServer natively via swift run.
# Use this during active development for fast iteration (no image rebuild needed).
set -euo pipefail

cd "$(dirname "$0")/.."

echo "Starting Postgres..."
docker compose up -d db

echo "Waiting for Postgres to be healthy..."
until docker compose exec db pg_isready -U siming -q 2>/dev/null; do
  sleep 1
done

echo "Starting SimingServer (swift run)..."
DATABASE_URL=postgres://siming:siming@localhost:5432/siming swift run SimingServer
