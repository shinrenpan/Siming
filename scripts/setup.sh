#!/usr/bin/env bash
# One-command setup for Siming FHIR R4 Server.
# Downloads FHIR packages (once) and starts the full stack.
set -euo pipefail

cd "$(dirname "$0")/.."

# ── Preflight ─────────────────────────────────────────────────────────────────

if ! command -v docker &>/dev/null; then
  echo "Error: Docker is not installed. Install Docker Desktop from https://www.docker.com/products/docker-desktop/"
  exit 1
fi

if ! docker info &>/dev/null; then
  echo "Error: Docker is not running. Please start Docker Desktop and try again."
  exit 1
fi

# ── FHIR packages ─────────────────────────────────────────────────────────────

if [ -z "$(ls packages/*.tgz 2>/dev/null)" ]; then
  echo "Downloading FHIR packages..."
  bash scripts/fetch-packages.sh
else
  echo "FHIR packages already present — skipping download."
fi

# ── Environment ───────────────────────────────────────────────────────────────

if [ ! -f .env ]; then
  echo "Creating .env from .env.example (edit it to customise settings)..."
  cp .env.example .env
fi

# ── Start ─────────────────────────────────────────────────────────────────────

echo "Building and starting Siming..."
docker compose up --build -d

echo ""
echo "Waiting for server to be ready..."
for i in $(seq 1 30); do
  if curl -sf http://localhost:8080/health &>/dev/null; then
    echo ""
    echo "Siming is running at http://localhost:8080"
    echo "  CapabilityStatement: http://localhost:8080/metadata"
    echo "  Metrics:             http://localhost:8080/metrics"
    echo ""
    echo "To stop:    docker compose down"
    echo "To logs:    docker compose logs -f app"
    exit 0
  fi
  printf "."
  sleep 2
done

echo ""
echo "Server did not respond in time. Check logs: docker compose logs app"
exit 1
