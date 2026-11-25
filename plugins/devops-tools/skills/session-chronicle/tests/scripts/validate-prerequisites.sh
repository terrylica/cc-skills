#!/usr/bin/env bash
# validate-prerequisites.sh - Check required tool installation

set -euo pipefail

echo "=== Prerequisites Validation ==="

# Check brotli
if command -v brotli &>/dev/null; then
  BROTLI_VERSION=$(brotli --version 2>&1 | head -1)
  echo "✓ brotli: $BROTLI_VERSION"
else
  echo "✗ brotli: NOT INSTALLED"
  exit 1
fi

# Check jq
if command -v jq &>/dev/null; then
  JQ_VERSION=$(jq --version 2>&1)
  echo "✓ jq: $JQ_VERSION"
else
  echo "✗ jq: NOT INSTALLED"
  exit 1
fi

echo ""
echo "All prerequisites satisfied"
