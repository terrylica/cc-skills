#!/usr/bin/env bash
# validate-extract-chain.sh - Script modification check

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# iter-38 SC2034: removed unused FIXTURE_DIR declaration (dead since script
# inception — SCRIPT_DIR is used on line 16, FIXTURE_DIR never referenced)
TEMP_DIR=$(mktemp -d)
# iter-38 SC2064: single quotes so $TEMP_DIR expands at signal time
trap 'rm -rf "$TEMP_DIR"' EXIT

echo "=== Extract Session Chain Validation ==="

# Check if extract script exists
EXTRACT_SCRIPT="$SCRIPT_DIR/../../scripts/extract_session_chain.sh"
if [[ ! -f "$EXTRACT_SCRIPT" ]]; then
  echo "✗ extract_session_chain.sh: NOT FOUND at $EXTRACT_SCRIPT"
  exit 1
fi
echo "✓ extract_session_chain.sh: Found"

# Check if script uses brotli (not gzip)
if grep -q "brotli" "$EXTRACT_SCRIPT"; then
  echo "✓ Compression: Uses brotli"
else
  if grep -q "gzip" "$EXTRACT_SCRIPT"; then
    echo "✗ Compression: Still uses gzip (should be brotli)"
    exit 1
  else
    echo "? Compression: Could not detect compression tool"
  fi
fi

# Check file extension in script
if grep -q "\.jsonl\.br" "$EXTRACT_SCRIPT"; then
  echo "✓ File extension: .jsonl.br"
else
  if grep -q "\.jsonl\.gz" "$EXTRACT_SCRIPT"; then
    echo "✗ File extension: Still .jsonl.gz (should be .jsonl.br)"
    exit 1
  else
    echo "? File extension: Could not detect extension"
  fi
fi

echo ""
echo "Extract session chain validation PASSED"
