#!/usr/bin/env bash
# Download MIWG (Model Interchange Working Group) BPMN conformance test files.
#
# These files are reference BPMN 2.0 diagrams used to verify parser conformance.
# Source: https://github.com/bpmn-miwg/bpmn-miwg-test-suite
#
# Usage: ./scripts/download_miwg.sh

set -euo pipefail

DEST="test/fixtures/conformance/miwg"
BASE_URL="https://raw.githubusercontent.com/bpmn-miwg/bpmn-miwg-test-suite/master/Reference"

mkdir -p "$DEST"

echo "Downloading MIWG reference BPMN files..."

for file in A.1.0 A.2.0 A.3.0 B.1.0 B.2.0; do
  echo "  ${file}.bpmn"
  curl -sSfL "${BASE_URL}/${file}.bpmn" -o "${DEST}/${file}.bpmn" 2>/dev/null || \
    echo "  WARNING: Failed to download ${file}.bpmn (using local copy)"
done

echo "Done. Files saved to ${DEST}/"
