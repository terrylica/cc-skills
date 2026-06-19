#!/usr/bin/env bash
#MISE description="Iter-97 regression test for the PostToolUse orchestrator 6-subhook state. Verifies (1) ssot-principles inlined as 6th subhook with dual-export naming; (2) orchestrator registry has ≥6 entries; (3) classifier uses iter-95 shared async-spawn helper (not the legacy bun $ template literal); (4) classifier scans filePath directly per PostToolUse invariant — no /tmp/.claude-ssot-scan${ext} fixed-path scratch (latent race eliminated); (5) iter-94 static audit STILL passes after iter-97 migration (now scans 6 classifiers cleanly); (6) hooks.json no longer wires standalone ssot-principles; (7) orchestrator description bumped to 6/15; (8) standalone import.meta.main guard retained for backward-compat CLI; (9) iter-96 Bun.stdin.text() idiom retained across all 7 entry points (orchestrator + 6 classifier mains); (10) end-to-end: orchestrator fires ssot-principles on a .py edit and emits {decision:block} JSON with the SSoT reminder."

set -euo pipefail
shopt -u patsub_replacement 2>/dev/null || true

SCRIPT_DIR_ABSOLUTE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR_ABSOLUTE/../../.." && pwd)"
POSTTOOLUSE_ORCHESTRATOR_HOOK_ABSOLUTE_PATH="$REPO_ROOT/plugins/itp-hooks/hooks/posttooluse-edit-time-orchestrator-aggregating-context-injecting-subhooks-into-single-bun-process-iter93-corrects-iter89-async-true-strict-dominance-claim.ts"
SSOT_PRINCIPLES_CLASSIFIER_ABSOLUTE_PATH="$REPO_ROOT/plugins/itp-hooks/hooks/posttooluse-ssot-principles.ts"
SHARED_LIB_HELPERS_ABSOLUTE_PATH="$REPO_ROOT/plugins/itp-hooks/hooks/lib/posttooluse-subhook-async-subprocess-execution-and-once-per-session-reminder-gate-file-helpers-iter95.ts"
STATIC_AUDIT_TASK_ABSOLUTE_PATH="$REPO_ROOT/.mise/tasks/audit-no-bun-spawnsync-in-posttooluse-orchestrator-subhooks-because-it-defeats-promise-all-parallelism-per-bun-docs-and-2026-community-guidance.sh"
HOOKS_JSON_ABSOLUTE_PATH="$REPO_ROOT/plugins/itp-hooks/hooks/hooks.json"

for required_file_absolute_path in \
    "$POSTTOOLUSE_ORCHESTRATOR_HOOK_ABSOLUTE_PATH" \
    "$SSOT_PRINCIPLES_CLASSIFIER_ABSOLUTE_PATH" \
    "$SHARED_LIB_HELPERS_ABSOLUTE_PATH" \
    "$STATIC_AUDIT_TASK_ABSOLUTE_PATH" \
    "$HOOKS_JSON_ABSOLUTE_PATH"; do
    if [[ ! -f "$required_file_absolute_path" ]]; then
        echo "FAIL: required file not found: $required_file_absolute_path"
        exit 1
    fi
done

ASSERTION_PASSED_COUNT=0
ASSERTION_FAILED_COUNT=0
assert_passes() { ASSERTION_PASSED_COUNT=$((ASSERTION_PASSED_COUNT + 1)); echo "  ✓ PASS: $1"; }
assert_fails()  { ASSERTION_FAILED_COUNT=$((ASSERTION_FAILED_COUNT + 1)); echo "  ✗ FAIL: $1"; }

echo "═══════════════════════════════════════════════════════════════════════════════"
echo "  Iter-97 PostToolUse orchestrator regression test (ssot-principles inlined)"
echo "═══════════════════════════════════════════════════════════════════════════════"
echo ""

# ─── Case 1: dual-export naming pattern preserved ─────────────────────────────
if grep -q "classifySsotPrinciplesAstGrepBasedAntiPatternDetectionOncePerSessionForPostToolUseOrchestrator" "$SSOT_PRINCIPLES_CLASSIFIER_ABSOLUTE_PATH" && \
   grep -q "classifySsotPrinciplesForPostToolUseOrchestrator" "$SSOT_PRINCIPLES_CLASSIFIER_ABSOLUTE_PATH"; then
    assert_passes "Case 1: ssot-principles exports BOTH precise algorithm name + symmetric-naming alias"
else
    assert_fails "Case 1: ssot-principles dual-export naming pattern missing"
fi
if grep -q "classifySsotPrinciplesForPostToolUseOrchestrator" "$POSTTOOLUSE_ORCHESTRATOR_HOOK_ABSOLUTE_PATH"; then
    assert_passes "Case 1b: orchestrator imports ssot-principles classifier"
else
    assert_fails "Case 1b: ssot-principles not imported by orchestrator"
fi

# ─── Case 2: orchestrator registry has ≥6 entries ─────────────────────────────
case2_registry_subhook_count=$(grep -cE '^[[:space:]]+name:[[:space:]]*"' "$POSTTOOLUSE_ORCHESTRATOR_HOOK_ABSOLUTE_PATH" || true)
case2_registry_subhook_count=${case2_registry_subhook_count:-0}
if [[ "${case2_registry_subhook_count}" -ge 6 ]]; then
    assert_passes "Case 2: orchestrator registry has ≥6 subhooks (iter-97 state; found ${case2_registry_subhook_count})"
else
    assert_fails "Case 2: only ${case2_registry_subhook_count} subhooks registered (expected ≥6 after iter-97)"
fi

# ─── Case 3: shared lib async-spawn helper used (not legacy bun $ template) ──
if grep -q "executeBunSubprocessAsyncWithAbortSignalCooperativeTimeoutAndConcurrentStreamDrainAndMaxBufferGuardrail" "$SSOT_PRINCIPLES_CLASSIFIER_ABSOLUTE_PATH"; then
    assert_passes "Case 3a: ssot-principles imports the iter-95 shared async-spawn helper"
else
    assert_fails "Case 3a: ssot-principles does NOT use shared async-spawn helper — helper-drift regression"
fi
# Legacy Bun-$-template-literal emission check (skip prose mentions in JSDoc/comments).
# Match `await $` or `$\`` style emissions (not the string `bun $` in prose).
legacy_template_emissions=$(grep -nE '(await[[:space:]]+\$|^[[:space:]]*\$\`)' "$SSOT_PRINCIPLES_CLASSIFIER_ABSOLUTE_PATH" 2>/dev/null \
    | grep -vE ':[[:space:]]*\*' \
    | grep -vE ':[[:space:]]*//' \
    || true)
if [[ -z "$legacy_template_emissions" ]]; then
    assert_passes "Case 3b: ssot-principles no longer uses legacy 'await \$\`...\`' shell template literal"
else
    assert_fails "Case 3b: ssot-principles still uses 'await \$\`...\`' template literal: $legacy_template_emissions"
fi

# ─── Case 4: latent /tmp temp-file race eliminated (no fixed-path scratch) ────
# Iter-97 invariant: classifier MUST scan filePath directly per PostToolUse
# invariant (file is on disk by the time we run). The pre-iter-97 fixed-path
# scratch buffer `/tmp/.claude-ssot-scan${ext}` is a race hazard between two
# concurrent Claude sessions writing the same extension.
#
# Emission-pattern check: a literal `/tmp/.claude-ssot-scan` string in source
# code (not prose comments) indicates the race-prone scratch is still in use.
race_prone_scratch_emissions=$(grep -nE "/tmp/\.claude-ssot-scan" "$SSOT_PRINCIPLES_CLASSIFIER_ABSOLUTE_PATH" 2>/dev/null \
    | grep -vE ':[[:space:]]*\*' \
    | grep -vE ':[[:space:]]*//' \
    || true)
if [[ -z "$race_prone_scratch_emissions" ]]; then
    assert_passes "Case 4: latent /tmp temp-file race eliminated (no /tmp/.claude-ssot-scan fixed-path emissions)"
else
    assert_fails "Case 4: race-prone /tmp scratch still in use: $race_prone_scratch_emissions"
fi

# ─── Case 5: iter-94 static audit STILL passes (now scans 6 classifiers) ──────
set +e
static_audit_output=$(bash "$STATIC_AUDIT_TASK_ABSOLUTE_PATH" 2>&1)
static_audit_exit_code=$?
set -e
if [[ "$static_audit_exit_code" == "0" ]] && [[ "$static_audit_output" == *'AUDIT PASSED'* ]]; then
    static_audit_scanned_count=$(echo "$static_audit_output" | grep -oE 'Classifier source files imported by orchestrator:[[:space:]]+[0-9]+' | grep -oE '[0-9]+$' | head -1 || echo 0)
    if [[ "${static_audit_scanned_count:-0}" -ge 6 ]]; then
        assert_passes "Case 5: iter-94 static audit STILL passes (scanned ${static_audit_scanned_count} classifiers cleanly — no spawnSync regression in 6/15 state)"
    else
        assert_fails "Case 5: static audit passed but only ${static_audit_scanned_count} classifiers discovered (expected ≥6)"
    fi
else
    assert_fails "Case 5: static audit failed (exit=$static_audit_exit_code)"
fi

# ─── Case 6: hooks.json no longer wires standalone ssot-principles ─────────────
case6_ssot_standalone_count=$(jq -r '[.hooks.PostToolUse[].hooks[] | select(.command | test("posttooluse-ssot-principles.ts"))] | length' "$HOOKS_JSON_ABSOLUTE_PATH")
if [[ "$case6_ssot_standalone_count" == "0" ]]; then
    assert_passes "Case 6: hooks.json no longer wires standalone ssot-principles (iter-97 removal — only via orchestrator import)"
else
    assert_fails "Case 6: standalone ssot-principles still wired ${case6_ssot_standalone_count} time(s)"
fi

# ─── Case 7: orchestrator description records iter-97 milestone or later ─────
# Forward-compat: assert progress is AT LEAST 6/15 (iter-97 milestone).
# Iter-98+ bumping to 7/15 etc. must not regress this test.
case7_inlined_count=$(jq -r '.hooks.PostToolUse[].hooks[] | select(.command | test("posttooluse-edit-time-orchestrator-aggregating")) | .description' "$HOOKS_JSON_ABSOLUTE_PATH" 2>/dev/null | grep -oE '[0-9]+/15 subhooks inlined' | head -1 | grep -oE '^[0-9]+' || echo 0)
case7_inlined_count=${case7_inlined_count:-0}
if [[ "${case7_inlined_count}" -ge 6 ]]; then
    assert_passes "Case 7: hooks.json orchestrator description records iter-97 milestone or later (6/15 baseline reached; current ${case7_inlined_count}/15)"
else
    assert_fails "Case 7: orchestrator description progress regressed below iter-97 baseline (6/15); found ${case7_inlined_count}/15"
fi

# ─── Case 8: import.meta.main standalone guard retained ──────────────────────
if grep -q "import.meta.main" "$SSOT_PRINCIPLES_CLASSIFIER_ABSOLUTE_PATH"; then
    assert_passes "Case 8: ssot-principles retains import.meta.main standalone-CLI guard"
else
    assert_fails "Case 8: ssot-principles missing import.meta.main guard — standalone CLI mode broken"
fi

# ─── Case 9: Bun.stdin.text() idiom retained across 7 entry points ──────────
files_using_modern_text_count=0
for source_file_absolute_path in \
    "$POSTTOOLUSE_ORCHESTRATOR_HOOK_ABSOLUTE_PATH" \
    "$REPO_ROOT/plugins/itp-hooks/hooks/posttooluse-ty-type-check.ts" \
    "$REPO_ROOT/plugins/itp-hooks/hooks/posttooluse-tsgo-type-check.ts" \
    "$REPO_ROOT/plugins/itp-hooks/hooks/posttooluse-oxlint-check.ts" \
    "$REPO_ROOT/plugins/itp-hooks/hooks/posttooluse-biome-lint.ts" \
    "$REPO_ROOT/plugins/itp-hooks/hooks/posttooluse-vale-claude-md.ts" \
    "$SSOT_PRINCIPLES_CLASSIFIER_ABSOLUTE_PATH"; do
    if grep -q "Bun\.stdin\.text(" "$source_file_absolute_path"; then
        files_using_modern_text_count=$((files_using_modern_text_count + 1))
    fi
done
if [[ "$files_using_modern_text_count" == "7" ]]; then
    assert_passes "Case 9: ALL 7 entry points (orchestrator + 6 classifier mains) use Bun.stdin.text() idiom"
else
    assert_fails "Case 9: only ${files_using_modern_text_count}/7 entry points use Bun.stdin.text()"
fi

# ─── Case 10: end-to-end .py edit fires ssot-principles via orchestrator ─────
# macOS mktemp appends the random suffix AFTER the template, so use a
# DIRECTORY then materialize the .py file inside it (extname() relies on the
# trailing .py). NOTE: the scratch dir lives under the repo-local (gitignored)
# tmp/ — NOT mktemp's default /var/folders $TMPDIR — because iter-124's
# temp-dir lint-skip would otherwise no-op the orchestrator on this fixture.
# A repo-local path also mirrors a real project edit, which is what fires.
mkdir -p "$REPO_ROOT/tmp"
TEMP_E2E_DIR=$(mktemp -d "$REPO_ROOT/tmp/iter97-e2e.XXXXXX")
TEMP_PY_FILE="$TEMP_E2E_DIR/sample.py"
TEMP_PAYLOAD_FILE="$TEMP_E2E_DIR/payload.json"
trap 'rm -rf "$TEMP_E2E_DIR"' EXIT
# Construct a Python file that the iter-97 ast-grep rule will flag
# (direct os.environ access — anti-pattern per SSoT ast-grep-ssot rules).
cat > "$TEMP_PY_FILE" <<'PY'
import os
def get_mode():
    return os.environ.get("MODE", "default")
PY
UNIQUE_SESSION_ID="iter97-e2e-$(date +%s%N)"
cat > "$TEMP_PAYLOAD_FILE" <<JSON
{"tool_name":"Write","session_id":"$UNIQUE_SESSION_ID","tool_input":{"file_path":"$TEMP_PY_FILE","content":"import os\ndef get_mode():\n    return os.environ.get('MODE', 'default')\n"}}
JSON
set +e
case10_stdout=$(bun "$POSTTOOLUSE_ORCHESTRATOR_HOOK_ABSOLUTE_PATH" < "$TEMP_PAYLOAD_FILE" 2>/dev/null)
case10_exit=$?
set -e
if [[ "$case10_exit" == "0" ]] && [[ "$case10_stdout" == *'SSoT-PRINCIPLES'* ]] && [[ "$case10_stdout" == *'"decision":"block"'* ]]; then
    assert_passes "Case 10: end-to-end orchestrator fires ssot-principles on .py edit + emits decision:block JSON with SSoT reminder"
else
    assert_fails "Case 10: orchestrator did NOT fire ssot-principles on .py edit (exit=$case10_exit, stdout-head='${case10_stdout:0:300}')"
fi

# ─── Summary ─────────────────────────────────────────────────────────────────
echo ""
echo "═══════════════════════════════════════════════════════════════════════════════"
echo "  Iter-97 PostToolUse orchestrator regression — Summary"
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
echo "  🚀 Iter-97 PostToolUse arc progress: 6/15 subhooks inlined."
echo "  🚀 Iter-97 MILESTONE: first migration that creates real Promise.all parallel fan-out (ssot-principles overlaps .py/.ts/.tsx with ty/tsgo/oxlint/biome)."
echo "  🚀 Iter-97 latent /tmp temp-file race eliminated (fixed-path scratch removed)."
echo "  🚀 Iter-97 ssot-principles migrated from bun \$ template literal to iter-95 shared Bun.spawn helper (no shell overhead, AbortSignal-bound, 256KiB maxBuffer)."
