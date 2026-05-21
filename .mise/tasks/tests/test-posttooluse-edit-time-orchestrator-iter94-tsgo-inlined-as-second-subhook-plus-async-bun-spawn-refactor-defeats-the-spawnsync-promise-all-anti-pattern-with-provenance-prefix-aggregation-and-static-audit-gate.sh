#!/usr/bin/env bash
#MISE description="Iter-94 regression test for the PostToolUse orchestrator second-subhook migration plus async-Bun.spawn perf correction. Verifies (1) tsgo-type-check inlined as 2nd subhook with dual-export precise+alias names; (2) orchestrator registry now has ≥2 entries; (3) NEITHER inlined classifier uses Bun.spawnSync (parallelism-defeat anti-pattern per Bun docs + 2026 community guidance); (4) the iter-94 static audit task passes cleanly; (5) hooks.json no longer wires standalone tsgo; (6) aggregator now emits [orchestrator-subhook: <name>] provenance prefix per section (iter-94 usability enhancement); (7) ty-type-check and tsgo-type-check both expose the executeBunSubprocessAsyncWithAbortSignalCooperativeTimeoutAndStreamDrain helper pattern; (8) standalone backward-compat preserved via import.meta.main; (9) microbenchmark task discoverable + runs to completion."

set -euo pipefail
shopt -u patsub_replacement 2>/dev/null || true

SCRIPT_DIR_ABSOLUTE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR_ABSOLUTE/../../.." && pwd)"
POSTTOOLUSE_ORCHESTRATOR_HOOK_ABSOLUTE_PATH="$REPO_ROOT/plugins/itp-hooks/hooks/posttooluse-edit-time-orchestrator-aggregating-context-injecting-subhooks-into-single-bun-process-iter93-corrects-iter89-async-true-strict-dominance-claim.ts"
TY_TYPE_CHECK_ABSOLUTE_PATH="$REPO_ROOT/plugins/itp-hooks/hooks/posttooluse-ty-type-check.ts"
TSGO_TYPE_CHECK_ABSOLUTE_PATH="$REPO_ROOT/plugins/itp-hooks/hooks/posttooluse-tsgo-type-check.ts"
STATIC_AUDIT_TASK_ABSOLUTE_PATH="$REPO_ROOT/.mise/tasks/audit-no-bun-spawnsync-in-posttooluse-orchestrator-subhooks-because-it-defeats-promise-all-parallelism-per-bun-docs-and-2026-community-guidance.sh"
MICROBENCHMARK_TASK_ABSOLUTE_PATH="$REPO_ROOT/.mise/tasks/benchmark-posttooluse-orchestrator-async-bun-spawn-parallelism-gain-versus-hypothetical-spawnsync-serialization-iter94-empirical-confirmation.sh"
HOOKS_JSON_ABSOLUTE_PATH="$REPO_ROOT/plugins/itp-hooks/hooks/hooks.json"

for required_file_absolute_path in \
    "$POSTTOOLUSE_ORCHESTRATOR_HOOK_ABSOLUTE_PATH" \
    "$TY_TYPE_CHECK_ABSOLUTE_PATH" \
    "$TSGO_TYPE_CHECK_ABSOLUTE_PATH" \
    "$STATIC_AUDIT_TASK_ABSOLUTE_PATH" \
    "$MICROBENCHMARK_TASK_ABSOLUTE_PATH" \
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
echo "  Iter-94 PostToolUse orchestrator regression test (tsgo inlined + async refactor)"
echo "═══════════════════════════════════════════════════════════════════════════════"
echo ""

TEMPORARY_PAYLOAD_DIRECTORY_ABSOLUTE_PATH=$(mktemp -d -t iter94-posttooluse-payloads.XXXXXX)
trap 'rm -rf "$TEMPORARY_PAYLOAD_DIRECTORY_ABSOLUTE_PATH"' EXIT

# ─── Case 1: orchestrator imports BOTH ty + tsgo classifiers ──────────────────
if grep -q "classifyTyTypeCheckForPostToolUseOrchestrator" "$POSTTOOLUSE_ORCHESTRATOR_HOOK_ABSOLUTE_PATH" && \
   grep -q "classifyTsgoTypeCheckForPostToolUseOrchestrator" "$POSTTOOLUSE_ORCHESTRATOR_HOOK_ABSOLUTE_PATH"; then
    assert_passes "Case 1: orchestrator imports BOTH ty + tsgo classifiers"
else
    assert_fails "Case 1: orchestrator missing one of the iter-94 classifier imports"
fi

# ─── Case 2: orchestrator registry has ≥ 2 entries ────────────────────────────
case2_registry_subhook_count=$(grep -cE '^[[:space:]]+name:[[:space:]]*"' "$POSTTOOLUSE_ORCHESTRATOR_HOOK_ABSOLUTE_PATH" || echo 0)
if [[ "${case2_registry_subhook_count:-0}" -ge 2 ]]; then
    assert_passes "Case 2: orchestrator registry has ≥2 subhooks (iter-94 state; found ${case2_registry_subhook_count})"
else
    assert_fails "Case 2: only ${case2_registry_subhook_count} subhook(s) registered (expected ≥2 after iter-94)"
fi

# ─── Case 3: dual-export naming-drift acknowledgement for tsgo ────────────────
if grep -q "classifyTsgoNativeGoTypeScriptCompilerProjectScopedTypeCheckForPostToolUseOrchestrator" "$TSGO_TYPE_CHECK_ABSOLUTE_PATH" && \
   grep -q "classifyTsgoTypeCheckForPostToolUseOrchestrator" "$TSGO_TYPE_CHECK_ABSOLUTE_PATH"; then
    assert_passes "Case 3: tsgo-type-check exports BOTH precise algorithm name + symmetric-naming alias"
else
    assert_fails "Case 3: tsgo dual-export naming pattern missing"
fi

# ─── Case 4: NEITHER inlined classifier uses Bun.spawnSync (parallelism invariant) ──
# grep -c outputs "0" AND exits non-zero when there are 0 matches, so `|| echo 0`
# would PREPEND a second "0" line to the captured output. Use `|| true` so the
# fallback adds nothing (we want grep's own "0" stdout when there are no matches).
ty_spawnsync_violations=$(grep -cE '^[[:space:]]*Bun\.spawnSync\(|^[[:space:]]*(const|let|var)[[:space:]]+[A-Za-z]+[[:space:]]*=[[:space:]]*Bun\.spawnSync\(' "$TY_TYPE_CHECK_ABSOLUTE_PATH" 2>/dev/null || true)
tsgo_spawnsync_violations=$(grep -cE '^[[:space:]]*Bun\.spawnSync\(|^[[:space:]]*(const|let|var)[[:space:]]+[A-Za-z]+[[:space:]]*=[[:space:]]*Bun\.spawnSync\(' "$TSGO_TYPE_CHECK_ABSOLUTE_PATH" 2>/dev/null || true)
ty_spawnsync_violations=${ty_spawnsync_violations:-0}
tsgo_spawnsync_violations=${tsgo_spawnsync_violations:-0}
if [[ "${ty_spawnsync_violations:-0}" -eq 0 ]]; then
    assert_passes "Case 4a: posttooluse-ty-type-check.ts has NO Bun.spawnSync invocations (iter-94 async refactor)"
else
    assert_fails "Case 4a: ${ty_spawnsync_violations} Bun.spawnSync invocation(s) in ty-type-check (defeats Promise.all parallelism)"
fi
if [[ "${tsgo_spawnsync_violations:-0}" -eq 0 ]]; then
    assert_passes "Case 4b: posttooluse-tsgo-type-check.ts has NO Bun.spawnSync invocations (async-from-day-one)"
else
    assert_fails "Case 4b: ${tsgo_spawnsync_violations} Bun.spawnSync invocation(s) in tsgo-type-check"
fi

# ─── Case 5: static audit task passes cleanly ─────────────────────────────────
set +e
static_audit_output=$(bash "$STATIC_AUDIT_TASK_ABSOLUTE_PATH" 2>&1)
static_audit_exit_code=$?
set -e
if [[ "$static_audit_exit_code" == "0" ]] && [[ "$static_audit_output" == *'AUDIT PASSED'* ]]; then
    assert_passes "Case 5: iter-94 static audit task passes cleanly (exit 0 + 'AUDIT PASSED' banner)"
else
    assert_fails "Case 5: static audit failed (exit=$static_audit_exit_code) — output tail: ${static_audit_output: -300}"
fi

# ─── Case 6: hooks.json no longer wires standalone tsgo ───────────────────────
case6_tsgo_standalone_count=$(jq -r '[.hooks.PostToolUse[] | select(.hooks[].command | test("/posttooluse-tsgo-type-check.ts"))] | length' "$HOOKS_JSON_ABSOLUTE_PATH")
case6_orchestrator_count=$(jq -r '[.hooks.PostToolUse[] | select(.hooks[].command | test("posttooluse-edit-time-orchestrator-aggregating"))] | length' "$HOOKS_JSON_ABSOLUTE_PATH")
if [[ "$case6_tsgo_standalone_count" == "0" ]]; then
    assert_passes "Case 6a: hooks.json no longer wires standalone tsgo (iter-94 removal — only via orchestrator import)"
else
    assert_fails "Case 6a: standalone tsgo still wired ${case6_tsgo_standalone_count} time(s)"
fi
if [[ "$case6_orchestrator_count" == "1" ]]; then
    assert_passes "Case 6b: hooks.json wires exactly 1 orchestrator entry under PostToolUse"
else
    assert_fails "Case 6b: orchestrator wired ${case6_orchestrator_count} time(s) (expected 1)"
fi

# ─── Case 7: aggregator emits provenance prefix per section ───────────────────
if grep -q "orchestrator-subhook:" "$POSTTOOLUSE_ORCHESTRATOR_HOOK_ABSOLUTE_PATH"; then
    assert_passes "Case 7: aggregator emits [orchestrator-subhook: <name>] provenance prefix per section (iter-94 usability)"
else
    assert_fails "Case 7: provenance prefix missing — Claude cannot distinguish which subhook contributed which section"
fi
# Iter-95 update: aggregator function renamed from PerSection to
# OnlyWhenMultipleSectionsContribute (conditional provenance prefix is now
# the encoded invariant). Accept EITHER name as satisfying the
# "function name encodes the provenance-prefix algorithm" invariant.
if grep -qE "aggregatePostToolUseSubhookAdditionalContextMessagesIntoSingleReasonStringWith(ProvenancePrefixPerSection|ProvenancePrefixOnlyWhenMultipleSectionsContribute)" "$POSTTOOLUSE_ORCHESTRATOR_HOOK_ABSOLUTE_PATH"; then
    assert_passes "Case 7b: aggregator function renamed to encode provenance-prefix invariant (iter-94 PerSection OR iter-95 OnlyWhenMultipleSectionsContribute)"
else
    assert_fails "Case 7b: aggregator function name doesn't encode the provenance-prefix algorithm"
fi

# ─── Case 8: both classifiers use the async-spawn helper ──────────────────────
# Iter-95 update: helper renamed from
#   executeBunSubprocessAsyncWithAbortSignalCooperativeTimeoutAndStreamDrain
# to
#   executeBunSubprocessAsyncWithAbortSignalCooperativeTimeoutAndConcurrentStreamDrainAndMaxBufferGuardrail
# (encoded maxBuffer safety-net addition + made the concurrent drain
# invariant explicit in the name). Accept EITHER name.
if grep -qE "executeBunSubprocessAsyncWithAbortSignalCooperativeTimeoutAnd(StreamDrain|ConcurrentStreamDrainAndMaxBufferGuardrail)" "$TY_TYPE_CHECK_ABSOLUTE_PATH" && \
   grep -qE "executeBunSubprocessAsyncWithAbortSignalCooperativeTimeoutAnd(StreamDrain|ConcurrentStreamDrainAndMaxBufferGuardrail)" "$TSGO_TYPE_CHECK_ABSOLUTE_PATH"; then
    assert_passes "Case 8: both ty + tsgo use the executeBunSubprocessAsync... helper (iter-94 inline or iter-95 shared-lib)"
else
    assert_fails "Case 8: async-spawn helper pattern not consistent across both subhooks"
fi

# ─── Case 9: standalone backward-compat (import.meta.main guard) ──────────────
if grep -q "import.meta.main" "$TY_TYPE_CHECK_ABSOLUTE_PATH" && \
   grep -q "import.meta.main" "$TSGO_TYPE_CHECK_ABSOLUTE_PATH"; then
    assert_passes "Case 9: both ty-type-check + tsgo-type-check retain import.meta.main guard for standalone CLI"
else
    assert_fails "Case 9: import.meta.main guard missing from one of the subhooks"
fi

# ─── Case 10: orchestrator silent-noop on non-applicable payload ──────────────
case10_payload="$TEMPORARY_PAYLOAD_DIRECTORY_ABSOLUTE_PATH/case10.json"
cat > "$case10_payload" <<'PAYLOAD'
{"tool_name":"Write","tool_input":{"file_path":"/tmp/iter94/foo.txt","content":"plain text\n"}}
PAYLOAD
set +e
case10_stdout=$(bun "$POSTTOOLUSE_ORCHESTRATOR_HOOK_ABSOLUTE_PATH" < "$case10_payload" 2>/dev/null)
case10_exit=$?
set -e
if [[ -z "$case10_stdout" ]] && [[ "$case10_exit" == "0" ]]; then
    assert_passes "Case 10: orchestrator silent-noop + exit 0 on non-applicable .txt payload (both subhooks return noop via O(1) filter)"
else
    assert_fails "Case 10: orchestrator misbehaved on .txt; exit=$case10_exit stdout='${case10_stdout:0:200}'"
fi

# ─── Case 11: microbenchmark task discoverable + runs to completion ───────────
set +e
microbenchmark_output=$(bash "$MICROBENCHMARK_TASK_ABSOLUTE_PATH" 2>&1)
microbenchmark_exit=$?
set -e
if [[ "$microbenchmark_exit" == "0" ]] && [[ "$microbenchmark_output" == *'median:'* ]]; then
    assert_passes "Case 11: iter-94 microbenchmark task runs to completion (3 payloads × 5 replicates)"
else
    assert_fails "Case 11: microbenchmark failed; exit=$microbenchmark_exit"
fi

# ─── Summary ─────────────────────────────────────────────────────────────────
echo ""
echo "═══════════════════════════════════════════════════════════════════════════════"
echo "  Iter-94 PostToolUse orchestrator regression — Summary"
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
echo "  🚀 Iter-94 PostToolUse Write|Edit migration arc progress: 2/15 subhooks inlined."
echo "  🚀 Iter-94 perf correction: every classifier now uses async Bun.spawn —"
echo "     orchestrator wall-clock now approaches MAX(subhook_i), not SUM."
