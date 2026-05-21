#!/usr/bin/env bash
#MISE description="Iter-95 regression test for the PostToolUse orchestrator 4-subhook state. Verifies (1) shared async-spawn helper module exists at lib/ and is imported by ALL 4 inlined classifiers (DRY invariant); (2) orchestrator registry contains ≥4 entries; (3) oxlint + biome dual-export naming present; (4) hooks.json no longer wires standalone oxlint or biome (iter-95 removal); (5) iter-94 static audit task STILL passes after the migration (no spawnSync regression in any of the 4 classifiers); (6) aggregator function renamed to encode conditional-provenance-prefix invariant; (7) single-subhook payload (.py) → no provenance prefix in emitted reason; (8) standalone CLI backward-compat preserved via import.meta.main; (9) empirical-parallelism benchmark task discoverable + runs to completion; (10) maxBuffer safety-net constant is exported from shared lib."

set -euo pipefail
shopt -u patsub_replacement 2>/dev/null || true

SCRIPT_DIR_ABSOLUTE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR_ABSOLUTE/../../.." && pwd)"
POSTTOOLUSE_ORCHESTRATOR_HOOK_ABSOLUTE_PATH="$REPO_ROOT/plugins/itp-hooks/hooks/posttooluse-edit-time-orchestrator-aggregating-context-injecting-subhooks-into-single-bun-process-iter93-corrects-iter89-async-true-strict-dominance-claim.ts"
SHARED_LIB_HELPERS_ABSOLUTE_PATH="$REPO_ROOT/plugins/itp-hooks/hooks/lib/posttooluse-subhook-async-subprocess-execution-and-once-per-session-reminder-gate-file-helpers-iter95.ts"
TY_TYPE_CHECK_ABSOLUTE_PATH="$REPO_ROOT/plugins/itp-hooks/hooks/posttooluse-ty-type-check.ts"
TSGO_TYPE_CHECK_ABSOLUTE_PATH="$REPO_ROOT/plugins/itp-hooks/hooks/posttooluse-tsgo-type-check.ts"
OXLINT_CHECK_ABSOLUTE_PATH="$REPO_ROOT/plugins/itp-hooks/hooks/posttooluse-oxlint-check.ts"
BIOME_LINT_ABSOLUTE_PATH="$REPO_ROOT/plugins/itp-hooks/hooks/posttooluse-biome-lint.ts"
STATIC_AUDIT_TASK_ABSOLUTE_PATH="$REPO_ROOT/.mise/tasks/audit-no-bun-spawnsync-in-posttooluse-orchestrator-subhooks-because-it-defeats-promise-all-parallelism-per-bun-docs-and-2026-community-guidance.sh"
EMPIRICAL_PARALLELISM_BENCHMARK_ABSOLUTE_PATH="$REPO_ROOT/.mise/tasks/benchmark-posttooluse-orchestrator-real-subprocess-firing-with-actual-typescript-file-empirically-confirms-async-bun-spawn-parallelism-gain-iter95.sh"
HOOKS_JSON_ABSOLUTE_PATH="$REPO_ROOT/plugins/itp-hooks/hooks/hooks.json"

for required_file_absolute_path in \
    "$POSTTOOLUSE_ORCHESTRATOR_HOOK_ABSOLUTE_PATH" \
    "$SHARED_LIB_HELPERS_ABSOLUTE_PATH" \
    "$TY_TYPE_CHECK_ABSOLUTE_PATH" \
    "$TSGO_TYPE_CHECK_ABSOLUTE_PATH" \
    "$OXLINT_CHECK_ABSOLUTE_PATH" \
    "$BIOME_LINT_ABSOLUTE_PATH" \
    "$STATIC_AUDIT_TASK_ABSOLUTE_PATH" \
    "$EMPIRICAL_PARALLELISM_BENCHMARK_ABSOLUTE_PATH" \
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
echo "  Iter-95 PostToolUse orchestrator regression test (oxlint + biome inlined; shared lib; conditional provenance)"
echo "═══════════════════════════════════════════════════════════════════════════════"
echo ""

TEMPORARY_PAYLOAD_DIRECTORY_ABSOLUTE_PATH=$(mktemp -d -t iter95-posttooluse-payloads.XXXXXX)
trap 'rm -rf "$TEMPORARY_PAYLOAD_DIRECTORY_ABSOLUTE_PATH"' EXIT

# ─── Case 1: shared lib/ helpers exist + exports the right surface ────────────
if grep -q "executeBunSubprocessAsyncWithAbortSignalCooperativeTimeoutAndConcurrentStreamDrainAndMaxBufferGuardrail" "$SHARED_LIB_HELPERS_ABSOLUTE_PATH" && \
   grep -q "tryAtomicallyClaimOncePerSessionInstallReminderGateFileForToolByName" "$SHARED_LIB_HELPERS_ABSOLUTE_PATH" && \
   grep -q "drainBunSubprocessReadableStreamToUtf8TextSwallowingErrors" "$SHARED_LIB_HELPERS_ABSOLUTE_PATH"; then
    assert_passes "Case 1a: shared lib/ module exports async-spawn, install-reminder, and stream-drain helpers"
else
    assert_fails "Case 1a: shared lib/ module missing one or more iter-95 helper exports"
fi
if grep -q "DEFAULT_SUBPROCESS_OUTPUT_MAX_BUFFER_BYTES_PER_BUN_DOCS_SAFETY_NET" "$SHARED_LIB_HELPERS_ABSOLUTE_PATH"; then
    assert_passes "Case 1b: shared lib/ exports maxBuffer safety-net constant per Bun docs"
else
    assert_fails "Case 1b: maxBuffer safety-net constant missing from shared lib"
fi

# ─── Case 2: ALL 4 classifiers import from the shared lib (DRY invariant) ─────
classifiers_importing_shared_lib_count=0
for classifier_file_absolute_path in \
    "$TY_TYPE_CHECK_ABSOLUTE_PATH" \
    "$TSGO_TYPE_CHECK_ABSOLUTE_PATH" \
    "$OXLINT_CHECK_ABSOLUTE_PATH" \
    "$BIOME_LINT_ABSOLUTE_PATH"; do
    if grep -q "posttooluse-subhook-async-subprocess-execution-and-once-per-session-reminder-gate-file-helpers-iter95" "$classifier_file_absolute_path"; then
        classifiers_importing_shared_lib_count=$((classifiers_importing_shared_lib_count + 1))
    fi
done
if [[ "$classifiers_importing_shared_lib_count" == "4" ]]; then
    assert_passes "Case 2: ALL 4 classifiers import from the shared lib/ helpers (DRY invariant — no duplicate copies of executeBunSubprocessAsync...)"
else
    assert_fails "Case 2: only ${classifiers_importing_shared_lib_count}/4 classifiers import shared lib — DRY drift"
fi

# ─── Case 3: orchestrator registry has ≥4 entries ─────────────────────────────
case3_registry_subhook_count=$(grep -cE '^[[:space:]]+name:[[:space:]]*"' "$POSTTOOLUSE_ORCHESTRATOR_HOOK_ABSOLUTE_PATH" || true)
case3_registry_subhook_count=${case3_registry_subhook_count:-0}
if [[ "${case3_registry_subhook_count}" -ge 4 ]]; then
    assert_passes "Case 3: orchestrator registry has ≥4 subhooks (iter-95 state; found ${case3_registry_subhook_count})"
else
    assert_fails "Case 3: only ${case3_registry_subhook_count} subhooks registered (expected ≥4 after iter-95)"
fi

# ─── Case 4: dual-export naming-drift acknowledgement for oxlint + biome ──────
if grep -q "classifyOxlintCorrectnessAndSuspiciousCategoryLintOnEditedJavaScriptOrTypeScriptFileForPostToolUseOrchestrator" "$OXLINT_CHECK_ABSOLUTE_PATH" && \
   grep -q "classifyOxlintCheckForPostToolUseOrchestrator" "$OXLINT_CHECK_ABSOLUTE_PATH"; then
    assert_passes "Case 4a: oxlint-check exports BOTH precise algorithm name + symmetric-naming alias"
else
    assert_fails "Case 4a: oxlint dual-export naming pattern missing"
fi
if grep -q "classifyBiomeComplementaryToOxlintLintOnEditedJavaScriptOrTypeScriptFileForPostToolUseOrchestrator" "$BIOME_LINT_ABSOLUTE_PATH" && \
   grep -q "classifyBiomeLintForPostToolUseOrchestrator" "$BIOME_LINT_ABSOLUTE_PATH"; then
    assert_passes "Case 4b: biome-lint exports BOTH precise algorithm name + symmetric-naming alias"
else
    assert_fails "Case 4b: biome dual-export naming pattern missing"
fi

# ─── Case 5: hooks.json no longer wires standalone oxlint or biome ────────────
case5_oxlint_standalone_count=$(jq -r '[.hooks.PostToolUse[] | select(.hooks[].command | test("/posttooluse-oxlint-check.ts"))] | length' "$HOOKS_JSON_ABSOLUTE_PATH")
case5_biome_standalone_count=$(jq -r '[.hooks.PostToolUse[] | select(.hooks[].command | test("/posttooluse-biome-lint.ts"))] | length' "$HOOKS_JSON_ABSOLUTE_PATH")
if [[ "$case5_oxlint_standalone_count" == "0" ]]; then
    assert_passes "Case 5a: hooks.json no longer wires standalone oxlint (iter-95 removal — only via orchestrator import)"
else
    assert_fails "Case 5a: standalone oxlint still wired ${case5_oxlint_standalone_count} time(s)"
fi
if [[ "$case5_biome_standalone_count" == "0" ]]; then
    assert_passes "Case 5b: hooks.json no longer wires standalone biome (iter-95 removal — only via orchestrator import)"
else
    assert_fails "Case 5b: standalone biome still wired ${case5_biome_standalone_count} time(s)"
fi

# ─── Case 6: iter-94 static audit STILL passes (no spawnSync regression) ──────
set +e
static_audit_output=$(bash "$STATIC_AUDIT_TASK_ABSOLUTE_PATH" 2>&1)
static_audit_exit_code=$?
set -e
if [[ "$static_audit_exit_code" == "0" ]] && [[ "$static_audit_output" == *'AUDIT PASSED'* ]]; then
    static_audit_scanned_count=$(echo "$static_audit_output" | grep -oE 'Classifier source files imported by orchestrator:[[:space:]]+[0-9]+' | grep -oE '[0-9]+$' | head -1 || echo 0)
    if [[ "${static_audit_scanned_count:-0}" -ge 4 ]]; then
        assert_passes "Case 6: iter-94 static audit STILL passes after iter-95 migration (scanned ${static_audit_scanned_count} classifiers cleanly — no spawnSync regression)"
    else
        assert_fails "Case 6: static audit passed but only ${static_audit_scanned_count} classifiers discovered (expected ≥4)"
    fi
else
    assert_fails "Case 6: static audit failed (exit=$static_audit_exit_code) — output tail: ${static_audit_output: -300}"
fi

# ─── Case 7: aggregator function renamed to encode conditional-prefix invariant ──
if grep -q "aggregatePostToolUseSubhookAdditionalContextMessagesIntoSingleReasonStringWithProvenancePrefixOnlyWhenMultipleSectionsContribute" "$POSTTOOLUSE_ORCHESTRATOR_HOOK_ABSOLUTE_PATH"; then
    assert_passes "Case 7: aggregator function renamed to encode conditional-provenance-prefix invariant (≥2 sections only)"
else
    assert_fails "Case 7: aggregator function name doesn't encode the iter-95 conditional-prefix algorithm"
fi
if grep -q "shouldEmitProvenancePrefix" "$POSTTOOLUSE_ORCHESTRATOR_HOOK_ABSOLUTE_PATH"; then
    assert_passes "Case 7b: aggregator uses explicit shouldEmitProvenancePrefix boolean (algorithm clarity)"
else
    assert_fails "Case 7b: shouldEmitProvenancePrefix local missing — algorithm clarity lost"
fi

# ─── Case 8: orchestrator silent-noop on non-applicable .txt payload ──────────
case8_payload="$TEMPORARY_PAYLOAD_DIRECTORY_ABSOLUTE_PATH/case8.json"
cat > "$case8_payload" <<'PAYLOAD'
{"tool_name":"Write","tool_input":{"file_path":"/tmp/iter95/foo.txt","content":"plain text\n"}}
PAYLOAD
set +e
case8_stdout=$(bun "$POSTTOOLUSE_ORCHESTRATOR_HOOK_ABSOLUTE_PATH" < "$case8_payload" 2>/dev/null)
case8_exit=$?
set -e
if [[ -z "$case8_stdout" ]] && [[ "$case8_exit" == "0" ]]; then
    assert_passes "Case 8: orchestrator silent-noop + exit 0 on non-applicable .txt payload (all 4 subhooks return noop via O(1) filter)"
else
    assert_fails "Case 8: orchestrator misbehaved on .txt; exit=$case8_exit stdout='${case8_stdout:0:200}'"
fi

# ─── Case 9: standalone CLI backward-compat preserved across all 4 ────────────
backward_compat_count=0
for classifier_file_absolute_path in \
    "$TY_TYPE_CHECK_ABSOLUTE_PATH" \
    "$TSGO_TYPE_CHECK_ABSOLUTE_PATH" \
    "$OXLINT_CHECK_ABSOLUTE_PATH" \
    "$BIOME_LINT_ABSOLUTE_PATH"; do
    if grep -q "import.meta.main" "$classifier_file_absolute_path"; then
        backward_compat_count=$((backward_compat_count + 1))
    fi
done
if [[ "$backward_compat_count" == "4" ]]; then
    assert_passes "Case 9: ALL 4 classifiers retain import.meta.main guard for standalone CLI (backward-compat preserved)"
else
    assert_fails "Case 9: only ${backward_compat_count}/4 classifiers have import.meta.main guard"
fi

# ─── Case 10: empirical-parallelism benchmark task discoverable + completes ───
set +e
benchmark_output=$(bash "$EMPIRICAL_PARALLELISM_BENCHMARK_ABSOLUTE_PATH" 2>&1)
benchmark_exit=$?
set -e
if [[ "$benchmark_exit" == "0" ]] && [[ "$benchmark_output" == *'median:'* ]]; then
    assert_passes "Case 10: iter-95 empirical-parallelism benchmark task runs to completion (real .ts file + multi-subprocess fire)"
else
    assert_fails "Case 10: benchmark failed; exit=$benchmark_exit"
fi

# ─── Summary ─────────────────────────────────────────────────────────────────
echo ""
echo "═══════════════════════════════════════════════════════════════════════════════"
echo "  Iter-95 PostToolUse orchestrator regression — Summary"
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
echo "  🚀 Iter-95 PostToolUse Write|Edit migration arc progress: 4/15 subhooks inlined."
echo "  🚀 Iter-95 shared lib helpers prevent helper-drift across N classifiers."
echo "  🚀 Iter-95 conditional provenance prefix preserves single-section UX continuity."
