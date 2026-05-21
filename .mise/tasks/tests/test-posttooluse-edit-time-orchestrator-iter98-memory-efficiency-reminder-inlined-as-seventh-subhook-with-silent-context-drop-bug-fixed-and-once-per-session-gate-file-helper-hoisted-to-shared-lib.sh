#!/usr/bin/env bash
#MISE description="Iter-98 regression test for the PostToolUse orchestrator 7-subhook state. Verifies (1) memory-efficiency-reminder inlined as 7th subhook with dual-export naming; (2) registry has ≥7 entries; (3) silent context-drop bug FIXED — classifier returns additional_context decision (not raw console.log); standalone CLI emits {decision:block} JSON (not plain text); (4) iter-98 shared lib helper exists in lib/ + both ssot-principles and memory-efficiency-reminder import it; (5) iter-97 ssot-principles local gate helper REMOVED (uplift verified); (6) iter-94 static audit STILL passes after iter-98 migration (now scans 7 classifiers cleanly); (7) hooks.json no longer wires standalone memory-efficiency-reminder; (8) orchestrator description bumped to ≥7/15; (9) standalone import.meta.main guard retained; (10) end-to-end orchestrator fires BOTH memory-efficiency-reminder AND ssot-principles on a .py edit + emits aggregated {decision:block} JSON with iter-95 conditional [orchestrator-subhook:<name>] provenance prefix (because ≥2 sections contributed)."

set -euo pipefail
shopt -u patsub_replacement 2>/dev/null || true

SCRIPT_DIR_ABSOLUTE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR_ABSOLUTE/../../.." && pwd)"
POSTTOOLUSE_ORCHESTRATOR_HOOK_ABSOLUTE_PATH="$REPO_ROOT/plugins/itp-hooks/hooks/posttooluse-edit-time-orchestrator-aggregating-context-injecting-subhooks-into-single-bun-process-iter93-corrects-iter89-async-true-strict-dominance-claim.ts"
MEMORY_EFFICIENCY_REMINDER_CLASSIFIER_ABSOLUTE_PATH="$REPO_ROOT/plugins/itp-hooks/hooks/posttooluse-memory-efficiency-reminder.ts"
SSOT_PRINCIPLES_CLASSIFIER_ABSOLUTE_PATH="$REPO_ROOT/plugins/itp-hooks/hooks/posttooluse-ssot-principles.ts"
SHARED_LIB_HELPERS_ABSOLUTE_PATH="$REPO_ROOT/plugins/itp-hooks/hooks/lib/posttooluse-subhook-async-subprocess-execution-and-once-per-session-reminder-gate-file-helpers-iter95.ts"
STATIC_AUDIT_TASK_ABSOLUTE_PATH="$REPO_ROOT/.mise/tasks/audit-no-bun-spawnsync-in-posttooluse-orchestrator-subhooks-because-it-defeats-promise-all-parallelism-per-bun-docs-and-2026-community-guidance.sh"
HOOKS_JSON_ABSOLUTE_PATH="$REPO_ROOT/plugins/itp-hooks/hooks/hooks.json"

for required_file_absolute_path in \
    "$POSTTOOLUSE_ORCHESTRATOR_HOOK_ABSOLUTE_PATH" \
    "$MEMORY_EFFICIENCY_REMINDER_CLASSIFIER_ABSOLUTE_PATH" \
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
echo "  Iter-98 PostToolUse orchestrator regression test (memory-efficiency 7th)"
echo "═══════════════════════════════════════════════════════════════════════════════"
echo ""

# ─── Case 1: dual-export naming pattern ───────────────────────────────────────
if grep -q "classifyMemoryEfficiencyBestPracticesReminderOncePerSessionForPostToolUseOrchestrator" "$MEMORY_EFFICIENCY_REMINDER_CLASSIFIER_ABSOLUTE_PATH" && \
   grep -q "classifyMemoryEfficiencyReminderForPostToolUseOrchestrator" "$MEMORY_EFFICIENCY_REMINDER_CLASSIFIER_ABSOLUTE_PATH"; then
    assert_passes "Case 1: memory-efficiency-reminder exports BOTH precise algorithm name + symmetric-naming alias"
else
    assert_fails "Case 1: memory-efficiency-reminder dual-export naming pattern missing"
fi
if grep -q "classifyMemoryEfficiencyReminderForPostToolUseOrchestrator" "$POSTTOOLUSE_ORCHESTRATOR_HOOK_ABSOLUTE_PATH"; then
    assert_passes "Case 1b: orchestrator imports memory-efficiency-reminder classifier"
else
    assert_fails "Case 1b: memory-efficiency-reminder not imported by orchestrator"
fi

# ─── Case 2: orchestrator registry has ≥7 entries ─────────────────────────────
case2_registry_subhook_count=$(grep -cE '^[[:space:]]+name:[[:space:]]*"' "$POSTTOOLUSE_ORCHESTRATOR_HOOK_ABSOLUTE_PATH" || true)
case2_registry_subhook_count=${case2_registry_subhook_count:-0}
if [[ "${case2_registry_subhook_count}" -ge 7 ]]; then
    assert_passes "Case 2: orchestrator registry has ≥7 subhooks (iter-98 state; found ${case2_registry_subhook_count})"
else
    assert_fails "Case 2: only ${case2_registry_subhook_count} subhooks registered (expected ≥7 after iter-98)"
fi

# ─── Case 3: silent context-drop bug FIXED — additional_context + JSON ────────
# (a) classifier returns buildPostToolUseAdditionalContextDecision (not raw text)
if grep -q "buildPostToolUseAdditionalContextDecision" "$MEMORY_EFFICIENCY_REMINDER_CLASSIFIER_ABSOLUTE_PATH"; then
    assert_passes "Case 3a: memory-efficiency classifier returns additional_context decision (not raw console.log) — silent-drop bug fixed in orchestrator path"
else
    assert_fails "Case 3a: classifier still uses raw text path — silent context-drop bug NOT fixed"
fi
# (b) standalone CLI emits JSON, not raw text — check for the JSON.stringify pattern
if grep -q 'JSON.stringify.*decision.*block.*reason' "$MEMORY_EFFICIENCY_REMINDER_CLASSIFIER_ABSOLUTE_PATH"; then
    assert_passes "Case 3b: standalone CLI emits {decision:block, reason} JSON (not raw console.log) — silent-drop bug fixed in standalone path"
else
    assert_fails "Case 3b: standalone CLI still uses raw console.log — silent context-drop bug NOT fixed for direct-CLI invocation"
fi
# (c) Verify the pre-iter-98 raw-text emission pattern (`console.log(\``) is absent
# from the standalone CLI body. We tolerate any console.log inside comments/JSDoc
# (those are prose mentions, not emissions).
raw_text_console_log_emissions=$(grep -nE 'console\.log\(`' "$MEMORY_EFFICIENCY_REMINDER_CLASSIFIER_ABSOLUTE_PATH" 2>/dev/null \
    | grep -vE ':[[:space:]]*\*' \
    | grep -vE ':[[:space:]]*//' \
    || true)
if [[ -z "$raw_text_console_log_emissions" ]]; then
    assert_passes "Case 3c: pre-iter-98 raw 'console.log(\`...\`)' template-literal emission removed from classifier source"
else
    assert_fails "Case 3c: raw console.log template-literal emission still present: $raw_text_console_log_emissions"
fi

# ─── Case 4: iter-98 shared gate-file helper exists + consumed by both ────────
if grep -q "tryAtomicallyClaimOncePerSessionGenericReminderGateFileForReminderByName" "$SHARED_LIB_HELPERS_ABSOLUTE_PATH"; then
    assert_passes "Case 4a: iter-98 shared lib helper 'tryAtomicallyClaim...GenericReminderGateFile...' exists in lib/"
else
    assert_fails "Case 4a: iter-98 shared lib helper missing from lib/"
fi
if grep -q "tryAtomicallyClaimOncePerSessionGenericReminderGateFileForReminderByName" "$MEMORY_EFFICIENCY_REMINDER_CLASSIFIER_ABSOLUTE_PATH"; then
    assert_passes "Case 4b: memory-efficiency-reminder imports the iter-98 shared gate-file helper"
else
    assert_fails "Case 4b: memory-efficiency-reminder does NOT import the iter-98 shared gate-file helper"
fi
if grep -q "tryAtomicallyClaimOncePerSessionGenericReminderGateFileForReminderByName" "$SSOT_PRINCIPLES_CLASSIFIER_ABSOLUTE_PATH"; then
    assert_passes "Case 4c: ssot-principles refactored to import the iter-98 shared gate-file helper (uplift verified)"
else
    assert_fails "Case 4c: ssot-principles still using iter-97 local gate helper — uplift incomplete"
fi

# ─── Case 5: iter-97 ssot-principles local gate helper REMOVED ────────────────
# Iter-98 uplift invariant: the iter-97-era function name should no longer be
# defined in the ssot-principles file body. Tolerate prose mentions in JSDoc.
if grep -nE "^function tryAtomicallyClaimOncePerSessionSsotPrinciplesReminderGateFile" "$SSOT_PRINCIPLES_CLASSIFIER_ABSOLUTE_PATH" >/dev/null 2>&1; then
    assert_fails "Case 5: iter-97 local helper 'tryAtomicallyClaimOncePerSessionSsotPrinciplesReminderGateFile' still defined — uplift incomplete"
else
    assert_passes "Case 5: iter-97 local ssot-principles gate helper REMOVED — uplift to shared lib complete"
fi

# ─── Case 6: iter-94 static audit STILL passes (now scans 7 classifiers) ──────
set +e
static_audit_output=$(bash "$STATIC_AUDIT_TASK_ABSOLUTE_PATH" 2>&1)
static_audit_exit_code=$?
set -e
if [[ "$static_audit_exit_code" == "0" ]] && [[ "$static_audit_output" == *'AUDIT PASSED'* ]]; then
    static_audit_scanned_count=$(echo "$static_audit_output" | grep -oE 'Classifier source files imported by orchestrator:[[:space:]]+[0-9]+' | grep -oE '[0-9]+$' | head -1 || echo 0)
    if [[ "${static_audit_scanned_count:-0}" -ge 7 ]]; then
        assert_passes "Case 6: iter-94 static audit STILL passes (scanned ${static_audit_scanned_count} classifiers cleanly — no spawnSync regression in 7/15 state)"
    else
        assert_fails "Case 6: static audit passed but only ${static_audit_scanned_count} classifiers discovered (expected ≥7)"
    fi
else
    assert_fails "Case 6: static audit failed (exit=$static_audit_exit_code)"
fi

# ─── Case 7: hooks.json no longer wires standalone memory-efficiency ──────────
case7_memeff_standalone_count=$(jq -r '[.hooks.PostToolUse[].hooks[] | select(.command | test("posttooluse-memory-efficiency-reminder.ts"))] | length' "$HOOKS_JSON_ABSOLUTE_PATH")
if [[ "$case7_memeff_standalone_count" == "0" ]]; then
    assert_passes "Case 7: hooks.json no longer wires standalone memory-efficiency-reminder (iter-98 removal — only via orchestrator import)"
else
    assert_fails "Case 7: standalone memory-efficiency-reminder still wired ${case7_memeff_standalone_count} time(s)"
fi

# ─── Case 8: orchestrator description records iter-98 milestone or later ──────
case8_inlined_count=$(jq -r '.hooks.PostToolUse[].hooks[] | select(.command | test("posttooluse-edit-time-orchestrator-aggregating")) | .description' "$HOOKS_JSON_ABSOLUTE_PATH" 2>/dev/null | grep -oE '[0-9]+/15 subhooks inlined' | head -1 | grep -oE '^[0-9]+' || echo 0)
case8_inlined_count=${case8_inlined_count:-0}
if [[ "${case8_inlined_count}" -ge 7 ]]; then
    assert_passes "Case 8: hooks.json orchestrator description records iter-98 milestone or later (7/15 baseline reached; current ${case8_inlined_count}/15)"
else
    assert_fails "Case 8: orchestrator description progress regressed below iter-98 baseline (7/15); found ${case8_inlined_count}/15"
fi

# ─── Case 9: import.meta.main standalone guard retained ──────────────────────
if grep -q "import.meta.main" "$MEMORY_EFFICIENCY_REMINDER_CLASSIFIER_ABSOLUTE_PATH"; then
    assert_passes "Case 9: memory-efficiency-reminder retains import.meta.main standalone-CLI guard"
else
    assert_fails "Case 9: memory-efficiency-reminder missing import.meta.main guard — standalone CLI mode broken"
fi

# ─── Case 10: end-to-end orchestrator fires BOTH subhooks + conditional prefix ─
# .py edit overlaps with multiple subhooks (memory-efficiency, ssot-principles,
# possibly ty). With ≥2 contributing sections, the iter-95 conditional
# provenance prefix `[orchestrator-subhook: <name>]` MUST activate.
TEMP_E2E_DIR=$(mktemp -d -t iter98-e2e.XXXXXX)
TEMP_PY_FILE="$TEMP_E2E_DIR/sample.py"
TEMP_PAYLOAD_FILE="$TEMP_E2E_DIR/payload.json"
trap 'rm -rf "$TEMP_E2E_DIR"' EXIT
cat > "$TEMP_PY_FILE" <<'PY'
import os
def get_mode():
    return os.environ.get("MODE", "default")
PY
UNIQUE_SESSION_ID="iter98-e2e-$(date +%s%N)"
cat > "$TEMP_PAYLOAD_FILE" <<JSON
{"tool_name":"Write","session_id":"$UNIQUE_SESSION_ID","tool_input":{"file_path":"$TEMP_PY_FILE","content":"import os\ndef get_mode():\n    return os.environ.get('MODE', 'default')\n"}}
JSON
set +e
case10_stdout=$(bun "$POSTTOOLUSE_ORCHESTRATOR_HOOK_ABSOLUTE_PATH" < "$TEMP_PAYLOAD_FILE" 2>/dev/null)
case10_exit=$?
set -e
case10_has_memeff_subhook=0
case10_has_ssot_subhook=0
case10_has_provenance_prefix=0
case10_has_decision_block=0
[[ "$case10_stdout" == *'MEMORY-EFFICIENCY'* ]] && case10_has_memeff_subhook=1
[[ "$case10_stdout" == *'SSoT-PRINCIPLES'* ]] && case10_has_ssot_subhook=1
[[ "$case10_stdout" == *'[orchestrator-subhook: memory-efficiency-reminder]'* ]] && case10_has_provenance_prefix=1
[[ "$case10_stdout" == *'"decision":"block"'* ]] && case10_has_decision_block=1
if [[ "$case10_exit" == "0" ]] && \
   [[ "$case10_has_memeff_subhook" == "1" ]] && \
   [[ "$case10_has_ssot_subhook" == "1" ]] && \
   [[ "$case10_has_provenance_prefix" == "1" ]] && \
   [[ "$case10_has_decision_block" == "1" ]]; then
    assert_passes "Case 10: e2e orchestrator fires BOTH memory-efficiency + ssot-principles on .py edit, emits aggregated decision:block JSON with conditional [orchestrator-subhook:<name>] provenance prefix activated (iter-95 conditional kicks in at ≥2 sections)"
else
    assert_fails "Case 10: orchestrator e2e fan-out broken (exit=$case10_exit, memeff=$case10_has_memeff_subhook, ssot=$case10_has_ssot_subhook, prefix=$case10_has_provenance_prefix, decision=$case10_has_decision_block; stdout-head='${case10_stdout:0:300}')"
fi

# ─── Case 11: gate atomic-O_EXCL race-safe (vs pre-iter-98 unguarded write) ───
# Pre-iter-98 used existsSync + writeFileSync (NOT atomic — two near-simultaneous
# Write|Edit calls could BOTH pass the existsSync check and both write the gate
# file, double-firing the reminder). Iter-98 uses O_CREAT|O_EXCL via the shared
# helper. Verify by checking that the pre-iter-98 unguarded pattern is absent.
race_unsafe_gate_pattern=$(grep -nE "existsSync\(sentinelPath\)" "$MEMORY_EFFICIENCY_REMINDER_CLASSIFIER_ABSOLUTE_PATH" 2>/dev/null \
    | grep -vE ':[[:space:]]*\*' \
    | grep -vE ':[[:space:]]*//' \
    || true)
if [[ -z "$race_unsafe_gate_pattern" ]]; then
    assert_passes "Case 11: pre-iter-98 race-unsafe 'existsSync(sentinelPath)' gate-check pattern removed — atomic O_EXCL via shared helper now"
else
    assert_fails "Case 11: race-unsafe gate-check pattern still present: $race_unsafe_gate_pattern"
fi

# ─── Summary ─────────────────────────────────────────────────────────────────
echo ""
echo "═══════════════════════════════════════════════════════════════════════════════"
echo "  Iter-98 PostToolUse orchestrator regression — Summary"
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
echo "  🚀 Iter-98 PostToolUse arc progress: 7/15 subhooks inlined."
echo "  🚀 Iter-98 BUG FIX: long-standing memory-efficiency-reminder silent context-drop closed (raw console.log was transcript-only per iter-66/93; now decision:block JSON via orchestrator)."
echo "  🚀 Iter-98 DRY: once-per-session gate-file helper hoisted to shared lib (consumed by both ssot-principles AND memory-efficiency-reminder)."
echo "  🚀 Iter-98 RACE-SAFETY: pre-iter-98 unguarded existsSync+writeFileSync pattern replaced by atomic O_CREAT|O_EXCL via shared helper."
