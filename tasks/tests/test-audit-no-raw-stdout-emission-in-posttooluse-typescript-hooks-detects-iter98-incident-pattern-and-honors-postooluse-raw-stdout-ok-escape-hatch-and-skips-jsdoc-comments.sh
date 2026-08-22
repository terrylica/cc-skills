#!/usr/bin/env bash
#MISE description="Iter-99 regression test for the marketplace-wide silent-context-drop audit. Verifies audit-task existence, live marketplace passes clean, detection regex catches iter-98 incident shape + plain-string variants, JSDoc and line-comment prose mentions correctly skipped, POSTTOOLUSE-RAW-STDOUT-OK escape hatch honored same-line and within 3 preceding lines, JSON.stringify-wrapped emissions allowed, and end-to-end fixture-injection inside plugins tree triggers audit failure."

set -euo pipefail
shopt -u patsub_replacement 2>/dev/null || true

SCRIPT_DIR_ABSOLUTE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR_ABSOLUTE/../../.." && pwd)"
AUDIT_TASK_ABSOLUTE_PATH="$REPO_ROOT/.mise/tasks/audit-no-raw-stdout-emission-in-posttooluse-typescript-hooks-because-anthropic-schema-routes-non-json-stdout-to-operator-transcript-only-and-silently-drops-it-from-claude-context.sh"

if [[ ! -f "$AUDIT_TASK_ABSOLUTE_PATH" ]]; then
    echo "FAIL: audit task not found at $AUDIT_TASK_ABSOLUTE_PATH"
    exit 1
fi

ASSERTION_PASSED_COUNT=0
ASSERTION_FAILED_COUNT=0
assert_passes() { ASSERTION_PASSED_COUNT=$((ASSERTION_PASSED_COUNT + 1)); echo "  ✓ PASS: $1"; }
assert_fails()  { ASSERTION_FAILED_COUNT=$((ASSERTION_FAILED_COUNT + 1)); echo "  ✗ FAIL: $1"; }

echo "═══════════════════════════════════════════════════════════════════════════════"
echo "  Iter-99 silent-context-drop audit regression test"
echo "═══════════════════════════════════════════════════════════════════════════════"
echo ""

# ─── Case 1: audit task exists + executable ──────────────────────────────────
if [[ -x "$AUDIT_TASK_ABSOLUTE_PATH" ]]; then
    assert_passes "Case 1: audit task exists + is executable"
else
    assert_fails "Case 1: audit task not executable"
fi

# ─── Case 2: live marketplace passes clean (0 violations) ────────────────────
set +e
live_audit_output=$(bash "$AUDIT_TASK_ABSOLUTE_PATH" 2>&1)
live_audit_exit_code=$?
set -e
if [[ "$live_audit_exit_code" == "0" ]] && [[ "$live_audit_output" == *'AUDIT PASSED'* ]]; then
    discovered_count=$(echo "$live_audit_output" | grep -oE 'PostToolUse TypeScript hooks discovered across marketplace:[[:space:]]+[0-9]+' | grep -oE '[0-9]+$' | head -1 || echo 0)
    if [[ "${discovered_count:-0}" -ge 8 ]]; then
        assert_passes "Case 2: live marketplace passes clean ($discovered_count PostToolUse TS hooks scanned, 0 violations)"
    else
        assert_fails "Case 2: audit passed but discovered only $discovered_count hooks (expected ≥8 — the 7 inlined classifiers + orchestrator + others)"
    fi
else
    assert_fails "Case 2: live marketplace audit failed (exit=$live_audit_exit_code)"
fi

# ─── Synthesize fixture hooks for pattern-detection tests ────────────────────
# Detection regex used by the audit (extracted from the audit script):
#   grep -nE 'console\.log\((`|"|'"'"')'
#
# Combined with these filters:
#   - skip lines whose first non-whitespace char is `*` (JSDoc continuation)
#   - skip lines whose first non-whitespace char is `//` (line comment)
#   - skip lines containing `POSTTOOLUSE-RAW-STDOUT-OK:` (same-line escape)
#   - skip lines whose 3-preceding-window contains `POSTTOOLUSE-RAW-STDOUT-OK:`

FIXTURE_DIR=$(mktemp -d -t iter99-fixtures.XXXXXX)
trap 'rm -rf "$FIXTURE_DIR"' EXIT

# Replicate the audit's emission-detection logic for fixture-based testing.
# Returns the number of fixture-detected violations (after applying skip
# filters identical to the audit script).
detect_silent_context_drop_violations_in_fixture_file() {
    local fixture_path="$1"
    local violation_count=0
    while IFS= read -r matched_line_with_lineno; do
        line_body_only="${matched_line_with_lineno#*:}"
        leading_stripped="${line_body_only#"${line_body_only%%[![:space:]]*}"}"
        # Skip JSDoc continuation
        [[ "$leading_stripped" == \** ]] && continue
        # Skip line-comments
        [[ "$leading_stripped" == //* ]] && continue
        # Same-line escape hatch
        [[ "$line_body_only" == *"POSTTOOLUSE-RAW-STDOUT-OK:"* ]] && continue
        # 3-line preceding window escape hatch
        line_number="${matched_line_with_lineno%%:*}"
        window_start=$((line_number - 3))
        [[ "$window_start" -lt 1 ]] && window_start=1
        window_end=$((line_number - 1))
        if [[ "$window_end" -ge "$window_start" ]]; then
            preceding_window=$(awk -v start="$window_start" -v end="$window_end" 'NR>=start && NR<=end' "$fixture_path")
            [[ "$preceding_window" == *"POSTTOOLUSE-RAW-STDOUT-OK:"* ]] && continue
        fi
        violation_count=$((violation_count + 1))
    done < <(grep -nE 'console\.log\((`|"|'"'"')' "$fixture_path" 2>/dev/null || true)
    echo "$violation_count"
}

# ─── Case 3: detects the iter-98 incident shape (template-literal) ───────────
cat > "$FIXTURE_DIR/iter98_incident_shape.ts" <<'TS_FIXTURE'
async function main(): Promise<void> {
  console.log(`[MEMORY-EFFICIENCY] zero-copy reminder text here`);
}
void main();
TS_FIXTURE
case3_violation_count=$(detect_silent_context_drop_violations_in_fixture_file "$FIXTURE_DIR/iter98_incident_shape.ts")
if [[ "$case3_violation_count" == "1" ]]; then
    assert_passes "Case 3: detection regex catches the iter-98 incident shape (template-literal console.log) — exactly 1 violation flagged"
else
    assert_fails "Case 3: expected 1 violation on iter-98 incident shape, got $case3_violation_count"
fi

# ─── Case 4: detects double-quoted string-literal console.log ────────────────
cat > "$FIXTURE_DIR/double_quoted_string_literal.ts" <<'TS_FIXTURE'
console.log("This is raw text that bypasses both valid Claude-visible schemas");
TS_FIXTURE
case4_violation_count=$(detect_silent_context_drop_violations_in_fixture_file "$FIXTURE_DIR/double_quoted_string_literal.ts")
if [[ "$case4_violation_count" == "1" ]]; then
    assert_passes "Case 4: detection regex catches double-quoted string-literal console.log"
else
    assert_fails "Case 4: expected 1 violation on double-quoted string-literal, got $case4_violation_count"
fi

# ─── Case 5: detects single-quoted string-literal console.log ────────────────
cat > "$FIXTURE_DIR/single_quoted_string_literal.ts" <<'TS_FIXTURE'
console.log('Also raw text — single-quoted variant of the same anti-pattern');
TS_FIXTURE
case5_violation_count=$(detect_silent_context_drop_violations_in_fixture_file "$FIXTURE_DIR/single_quoted_string_literal.ts")
if [[ "$case5_violation_count" == "1" ]]; then
    assert_passes "Case 5: detection regex catches single-quoted string-literal console.log"
else
    assert_fails "Case 5: expected 1 violation on single-quoted string-literal, got $case5_violation_count"
fi

# ─── Case 6: skips JSDoc continuation prose mentions ────────────────────────
cat > "$FIXTURE_DIR/jsdoc_prose_mention.ts" <<'TS_FIXTURE'
/**
 * Example: a buggy hook would emit
 *   console.log(`text`);
 * but this is just JSDoc prose — should NOT be flagged.
 */
function classifier(): void {}
TS_FIXTURE
case6_violation_count=$(detect_silent_context_drop_violations_in_fixture_file "$FIXTURE_DIR/jsdoc_prose_mention.ts")
if [[ "$case6_violation_count" == "0" ]]; then
    assert_passes "Case 6: JSDoc continuation prose mentions correctly skipped (0 violations on a documentation-only file)"
else
    assert_fails "Case 6: JSDoc prose mention false-positive: got $case6_violation_count violations on documentation-only file"
fi

# ─── Case 7: skips // line-comment prose mentions ───────────────────────────
cat > "$FIXTURE_DIR/line_comment_prose_mention.ts" <<'TS_FIXTURE'
// Old code shape was: console.log(`raw text`)
// We've since migrated to console.log(JSON.stringify(...))
function classifier(): void {}
TS_FIXTURE
case7_violation_count=$(detect_silent_context_drop_violations_in_fixture_file "$FIXTURE_DIR/line_comment_prose_mention.ts")
if [[ "$case7_violation_count" == "0" ]]; then
    assert_passes "Case 7: // line-comment prose mentions correctly skipped (0 violations on commentary-only file)"
else
    assert_fails "Case 7: line-comment prose mention false-positive: got $case7_violation_count violations"
fi

# ─── Case 8: same-line escape hatch honored ─────────────────────────────────
cat > "$FIXTURE_DIR/same_line_escape_hatch.ts" <<'TS_FIXTURE'
console.log(`Intentional operator-only diagnostic`); // POSTTOOLUSE-RAW-STDOUT-OK: stderr fallback hardened
TS_FIXTURE
case8_violation_count=$(detect_silent_context_drop_violations_in_fixture_file "$FIXTURE_DIR/same_line_escape_hatch.ts")
if [[ "$case8_violation_count" == "0" ]]; then
    assert_passes "Case 8: same-line POSTTOOLUSE-RAW-STDOUT-OK escape hatch honored (0 violations)"
else
    assert_fails "Case 8: same-line escape hatch NOT honored: got $case8_violation_count violations"
fi

# ─── Case 9: 3-line preceding-window escape hatch honored ──────────────────
cat > "$FIXTURE_DIR/preceding_window_escape_hatch.ts" <<'TS_FIXTURE'
// POSTTOOLUSE-RAW-STDOUT-OK: legacy hook deliberately operator-only per ADR
// (escape hatch placed 2 lines above the emission below)

console.log(`Operator-only banner — intentionally bypasses Claude context`);
TS_FIXTURE
case9_violation_count=$(detect_silent_context_drop_violations_in_fixture_file "$FIXTURE_DIR/preceding_window_escape_hatch.ts")
if [[ "$case9_violation_count" == "0" ]]; then
    assert_passes "Case 9: 3-line preceding-window POSTTOOLUSE-RAW-STDOUT-OK escape hatch honored (0 violations)"
else
    assert_fails "Case 9: preceding-window escape hatch NOT honored: got $case9_violation_count violations"
fi

# ─── Case 10: JSON.stringify-wrapped emissions are NOT flagged ──────────────
# Note: the audit's detection regex `console\.log\((`|"|'`)` does NOT match
# `console.log(JSON.stringify(...))` because the first char after `(` is `J`,
# not a string-literal quote or template-literal backtick. Verify.
cat > "$FIXTURE_DIR/correct_json_wrapped.ts" <<'TS_FIXTURE'
console.log(JSON.stringify({ decision: "block", reason: "Claude-visible context" }));
console.log(JSON.stringify({ hookSpecificOutput: { hookEventName: "PostToolUse", additionalContext: "also valid" } }));
TS_FIXTURE
case10_violation_count=$(detect_silent_context_drop_violations_in_fixture_file "$FIXTURE_DIR/correct_json_wrapped.ts")
if [[ "$case10_violation_count" == "0" ]]; then
    assert_passes "Case 10: console.log(JSON.stringify(...)) — correct Claude-visible pattern — NOT flagged (0 violations)"
else
    assert_fails "Case 10: false-positive on JSON.stringify-wrapped emission: got $case10_violation_count violations"
fi

# ─── Case 11: end-to-end fixture-injection — audit FAILS on real bad hook ──
# Place a synthesized bad-pattern hook inside plugins/ so the audit's find
# loop picks it up, then verify the audit exits non-zero and reports the
# violation. Restore clean state on exit.
case11_injected_hook="$REPO_ROOT/plugins/itp-hooks/hooks/posttooluse-iter99-fixture-injected-silent-drop-bug.ts"
trap 'rm -f "$case11_injected_hook"; rm -rf "$FIXTURE_DIR"' EXIT
cat > "$case11_injected_hook" <<'TS_FIXTURE'
#!/usr/bin/env bun
// Synthesized iter-99 regression-test fixture (removed by trap).
async function main(): Promise<void> {
  console.log(`[ITER99-FIXTURE] this should be flagged by the audit`);
}
void main();
TS_FIXTURE
set +e
injected_audit_output=$(bash "$AUDIT_TASK_ABSOLUTE_PATH" 2>&1)
injected_audit_exit_code=$?
set -e
rm -f "$case11_injected_hook"
if [[ "$injected_audit_exit_code" != "0" ]] && \
   [[ "$injected_audit_output" == *'AUDIT FAILED'* ]] && \
   [[ "$injected_audit_output" == *'posttooluse-iter99-fixture-injected-silent-drop-bug.ts'* ]]; then
    assert_passes "Case 11: e2e fixture-injection — audit correctly FAILS + reports the injected silent-drop bug"
else
    assert_fails "Case 11: e2e fixture-injection did NOT trigger audit failure (exit=$injected_audit_exit_code) — audit may be missing real-world violations"
fi

# ─── Summary ─────────────────────────────────────────────────────────────────
echo ""
echo "═══════════════════════════════════════════════════════════════════════════════"
echo "  Iter-99 silent-context-drop audit regression — Summary"
echo "═══════════════════════════════════════════════════════════════════════════════"
echo "  Assertions passed: $ASSERTION_PASSED_COUNT"
echo "  Assertions failed: $ASSERTION_FAILED_COUNT"
echo "═══════════════════════════════════════════════════════════════════════════════"
if [[ "$ASSERTION_FAILED_COUNT" -gt 0 ]]; then
    echo "  ✗ FAIL — $ASSERTION_FAILED_COUNT assertion(s) failed"
    exit 1
fi
echo "  ✓ PASS — all $ASSERTION_PASSED_COUNT assertions passed"
echo ""
echo "  🚀 Iter-99 marketplace-wide silent-context-drop audit verified."
echo "  🚀 Iter-99 detection regex catches iter-98 incident shape + plain-string variants."
echo "  🚀 Iter-99 JSDoc + // line-comment prose mentions correctly skipped (no false-positives)."
echo "  🚀 Iter-99 POSTTOOLUSE-RAW-STDOUT-OK escape hatch honored (same-line + 3-line preceding window)."
echo "  🚀 Iter-99 e2e fixture-injection sanity check confirms audit catches real-world violations."
