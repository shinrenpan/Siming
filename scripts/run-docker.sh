#!/usr/bin/env bash
# Full Docker stack: builds the release image and starts both db and app containers.
# Use for integration testing or staging validation.
set -euo pipefail

cd "$(dirname "$0")/.."

if [ -z "$(ls packages/*.tgz 2>/dev/null)" ]; then
  echo "No FHIR packages found in packages/. Run scripts/fetch-packages.sh first."
  exit 1
fi

echo "Building image and starting stack..."
docker compose up --build "$@"
