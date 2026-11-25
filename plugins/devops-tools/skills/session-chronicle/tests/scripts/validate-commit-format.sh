#!/usr/bin/env bash
# validate-commit-format.sh - Git commit message format check for generate_commit_message.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "=== Git Commit Message Format Validation ==="

GEN_SCRIPT="$SCRIPT_DIR/../../scripts/generate_commit_message.sh"
if [[ ! -f "$GEN_SCRIPT" ]]; then
  echo "✗ generate_commit_message.sh: NOT FOUND"
  exit 1
fi
echo "✓ generate_commit_message.sh: Found"

TEMP_DIR=$(mktemp -d)
# iter-38 SC2064: single quotes so $TEMP_DIR expands at signal time
trap 'rm -rf "$TEMP_DIR"' EXIT

# The fields extract_session_chain.sh writes.
cat > "$TEMP_DIR/manifest.json" << 'MANIFEST'
{
  "total_sessions": 2,
  "total_lines": 1500,
  "total_bytes_compressed": 50000,
  "chain_depth": 12,
  "first_timestamp": "2026-01-01T00:00:00Z",
  "last_timestamp": "2026-01-02T00:00:00Z",
  "project_path": "/test/project",
  "created_at": "2026-01-02T12:00:00Z",
  "compression": "brotli-9"
}
MANIFEST
touch "$TEMP_DIR/session-a.jsonl.br"

PASSED=0
FAILED=0
pass() { echo "✓ $1"; ((PASSED++)) || true; }
fail() { echo "✗ $1"; ((FAILED++)) || true; }

rc=0
COMMIT_MSG=$(bash "$GEN_SCRIPT" "$TEMP_DIR" "Test provenance finding" "2026-01-01-example-adr" 2>&1) || rc=$?
if [[ $rc -eq 0 ]]; then pass "generator exits 0"; else fail "generator exited $rc: $COMMIT_MSG"; fi

for pattern in \
  "feat(provenance): Test provenance finding" \
  "Session-Chronicle Provenance:" \
  "  sessions_traced: 2" \
  "  chain_depth: 12" \
  "  compression: brotli-9" \
  "  - session-a.jsonl.br" \
  "Related ADR: 2026-01-01-example-adr"; do
  if grep -qF -- "$pattern" <<<"$COMMIT_MSG"; then pass "Contains: $pattern"; else fail "Missing: $pattern"; fi
done

# No cloud upload or credential lookup is described any more.
for pattern in "s3://" "aws s3" "op read" "op://" "presigned"; do
  if grep -qiF -- "$pattern" <<<"$COMMIT_MSG"; then fail "Contains retired pattern: $pattern"; else pass "No: $pattern"; fi
done

# A field the manifest lacks is left out, never filled with a placeholder.
echo '{"total_sessions": 1}' > "$TEMP_DIR/manifest.json"
rm -f "$TEMP_DIR"/*.br
rc=0
PARTIAL=$(bash "$GEN_SCRIPT" "$TEMP_DIR" "Partial" 2>&1) || rc=$?
if [[ $rc -eq 0 ]] && grep -qF "  sessions_traced: 1" <<<"$PARTIAL" && ! grep -qE "N/A|total_lines|chain_depth|Archived sessions" <<<"$PARTIAL"; then
  pass "Partial manifest: only present fields, no placeholders"
else
  fail "Partial manifest (rc=$rc): $PARTIAL"
fi

echo ""
if [[ $FAILED -eq 0 ]]; then
  echo "Git commit message format validation PASSED ($PASSED checks)"
else
  echo "Git commit message format validation FAILED ($FAILED failures, $PASSED passed)"
  exit 1
fi
