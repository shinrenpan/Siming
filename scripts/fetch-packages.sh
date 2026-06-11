#!/usr/bin/env bash
# Download FHIR IG packages required by SimingGenerator.
# Run once before `swift run SimingGenerator`.
set -euo pipefail

PACKAGES_DIR="$(cd "$(dirname "$0")/.." && pwd)/packages"
mkdir -p "$PACKAGES_DIR"

download() {
    local name="$1" version="$2" url="$3"
    local dest="$PACKAGES_DIR/${name}-${version}.tgz"
    if [[ -f "$dest" ]]; then
        echo "  already downloaded: ${name}-${version}.tgz"
    else
        echo "  downloading ${name} ${version}..."
        curl -fsSL "$url" -o "$dest"
        echo "  saved to $dest"
    fi
}

echo "Fetching FHIR packages into $PACKAGES_DIR ..."
download "hl7.fhir.r4.core" "4.0.1" "https://packages.fhir.org/hl7.fhir.r4.core/4.0.1"
download "tw.gov.mohw.twcore" "1.0.0" "https://packages.simplifier.net/tw.gov.mohw.twcore/1.0.0"
echo "Done. Run: swift run SimingGenerator"
