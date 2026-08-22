#!/usr/bin/env bash
#MISE description="Iter-141 multi-iter source-fingerprint regression test pinning the release-pipeline-instrumentation cohort (iter-137 parallelism-aware iter-130 bucket-label ranking + iter-138 chronicle-slicing test relocation into iter-50/138 marketplace-suite auto-discovery + iter-139 RELEASE_TIMING_PROFILE pipeline-level per-phase timing in release/full orchestrator + iter-140 successCmd per-step timing helpers in .releaserc.yml + iter-140 sleep-2 elimination forensic invariant). Tier 1 only (source-fingerprint assertions, no Tier 2 integration — releases have side effects). Closes the every-iter-N-gets-a-regression-test discipline gap accumulated across four iters. Auto-discovered by the iter-50 marketplace-hook-regression-suite at .mise/tasks/tests/test-*.sh path."

# Iter-141 combined regression test. Mirrors the iter-132 multi-iter pattern
# (iter-130+iter-131 bottleneck-ranking-summary as one combined source-
# fingerprint + integration test) but at a different scope: four iters
# (iter-137, iter-138, iter-139, iter-140) form a coherent feature group
# — the "release-pipeline-instrumentation cohort" — that collectively
# unlocked data-driven optimization of the post-preflight release portion.
#
# Each iter contributed a distinct invariant that must not regress:
#
#   iter-137: __preflight_timing_report_phase_elapsed_milliseconds accepts
#             an optional parallel_execution_bucket_label_for_wall_clock_
#             attribution_awareness second arg. All 17 Check 4f-4v call-
#             sites pass "iter134-audit-batch" as bucket. End-of-preflight
#             ranking renders [parallel: BUCKET] suffix on bucketed entries
#             + "wall-clock attribution NOTE" identifying the critical-path
#             member. Future "let me simplify away the bucket label" cleanup
#             would distort iter-130 ranking actionability post-iter-134.
#
#   iter-138: Chronicle-slicing 37-assertion test relocated FROM
#             .mise/tasks/release/test-chronicle-slicing TO
#             .mise/tasks/tests/test-chronicle-slicing-37-assertion-*.sh
#             so the iter-50 marketplace-suite auto-discovery glob
#             `test-*.sh` picks it up. CHRONICLE_SCRIPT path inside the
#             test patched to ../release/chronicle (chronicle producer
#             remained at its canonical home). Check 4d block in preflight
#             replaced with "ABSORBED into Check 4e by iter-138" stub
#             comment. Future "let me move it back" cleanup would
#             reintroduce the ~670ms sequential cost.
#
#   iter-139: RELEASE_TIMING_PROFILE=1 opt-in pipeline-level instrumentation
#             wrapping all 7 phases (preflight + presync + version + sync
#             + verify + chronicle + postflight) with EPOCHREALTIME capture
#             + per-phase elapsed-ms inline + end-of-pipeline top-N
#             ranking via __iter139_emit_top_n_slowest_release_phases helper.
#             Removed `depends=["release:preflight"]` from orchestrator
#             frontmatter so preflight is wrapped too. Future "let me
#             restore the depends declaration" cleanup would lose Phase 1
#             timing capture.
#
#   iter-140: Per-successCmd-step instrumentation embedded in .releaserc.yml
#             YAML literal — 3 helper functions + 6 wrapped steps + top-N
#             ranking. Step 3 `sleep 2` ELIMINATED (cache-verify Step 4
#             handles graceful degrade). Future "let me add sleep 2 back
#             for safety" cleanup would burn 2s/release unconditionally
#             without functional benefit.
#
# Each invariant is asserted by a Tier-1 source-fingerprint check below.
# No Tier-2 integration (would require running a real release with side
# effects — tag push, GitHub API, jsDelivr CDN purge). The iter-130/137
# ranking and iter-139/140 timing instrumentation are gated on env-var
# opt-in, so the source-fingerprint covers the surface area where future
# maintenance might regress them.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
PREFLIGHT_SCRIPT_ABSOLUTE_PATH="$REPO_ROOT/.mise/tasks/release/preflight"
RELEASE_FULL_ORCHESTRATOR_ABSOLUTE_PATH="$REPO_ROOT/.mise/tasks/release/full"
RELEASERC_YML_ABSOLUTE_PATH="$REPO_ROOT/.releaserc.yml"
# Iter-142: the iter-140 successCmd-internals instrumentation was EXTRACTED from
# the .releaserc.yml YAML literal heredoc into an external script to resolve the
# lodash-template-vs-bash-default-value-parameter-expansion syntax conflict
# (lodash JS-eval'd `${RELEASE_TIMING_PROFILE:-0}` and bombed v21.58.2's
# post-release verification block). The iter-140 helpers/wrappers/instrumentation
# now live in the script below; assertions that previously searched .releaserc.yml
# for these symbols now search the extracted script instead. The extraction is a
# pure code-relocation refactor that preserves behavior — invariants hold, just
# in a different file — so iter-141 source-fingerprints still bind tightly.
ITER142_EXTRACTED_POST_RELEASE_VERIFICATION_SCRIPT_ABSOLUTE_PATH_FOR_ITER140_HELPER_ASSERTIONS_AFTER_ITER142_RELOCATION="$REPO_ROOT/scripts/iter142-post-release-verification-with-iter140-per-step-timing-instrumentation-extracted-from-releaserc-yml-yaml-literal-to-avoid-lodash-template-versus-bash-parameter-expansion-syntax-conflict.sh"
CHRONICLE_TEST_ABSOLUTE_PATH="$REPO_ROOT/.mise/tasks/tests/test-chronicle-slicing-37-assertion-stress-test-against-boundary-mtimes-jsonl-vs-brotli-subagent-recursion-and-visibility-gate-parsing.sh"
LEGACY_CHRONICLE_TEST_RELEASE_DIR_PATH="$REPO_ROOT/.mise/tasks/release/test-chronicle-slicing"

ASSERTION_COUNT_PASSED_FOR_ITER141_RELEASE_PIPELINE_INSTRUMENTATION_COHORT_REGRESSION_TEST=0
ASSERTION_COUNT_FAILED_FOR_ITER141_RELEASE_PIPELINE_INSTRUMENTATION_COHORT_REGRESSION_TEST=0

__iter141_assert_substring_present() {
    local assertion_label_for_iter141="$1"
    local file_content_haystack="$2"
    local expected_substring="$3"
    if [[ "$file_content_haystack" == *"$expected_substring"* ]]; then
        ASSERTION_COUNT_PASSED_FOR_ITER141_RELEASE_PIPELINE_INSTRUMENTATION_COHORT_REGRESSION_TEST=$((ASSERTION_COUNT_PASSED_FOR_ITER141_RELEASE_PIPELINE_INSTRUMENTATION_COHORT_REGRESSION_TEST + 1))
        echo "  ✓ PASS: $assertion_label_for_iter141"
    else
        ASSERTION_COUNT_FAILED_FOR_ITER141_RELEASE_PIPELINE_INSTRUMENTATION_COHORT_REGRESSION_TEST=$((ASSERTION_COUNT_FAILED_FOR_ITER141_RELEASE_PIPELINE_INSTRUMENTATION_COHORT_REGRESSION_TEST + 1))
        echo "  ✗ FAIL: $assertion_label_for_iter141"
        echo "    expected substring: ${expected_substring:0:120}"
    fi
}

__iter141_assert_substring_absent() {
    local assertion_label_for_iter141="$1"
    local file_content_haystack="$2"
    local forbidden_substring="$3"
    if [[ "$file_content_haystack" != *"$forbidden_substring"* ]]; then
        ASSERTION_COUNT_PASSED_FOR_ITER141_RELEASE_PIPELINE_INSTRUMENTATION_COHORT_REGRESSION_TEST=$((ASSERTION_COUNT_PASSED_FOR_ITER141_RELEASE_PIPELINE_INSTRUMENTATION_COHORT_REGRESSION_TEST + 1))
        echo "  ✓ PASS: $assertion_label_for_iter141"
    else
        ASSERTION_COUNT_FAILED_FOR_ITER141_RELEASE_PIPELINE_INSTRUMENTATION_COHORT_REGRESSION_TEST=$((ASSERTION_COUNT_FAILED_FOR_ITER141_RELEASE_PIPELINE_INSTRUMENTATION_COHORT_REGRESSION_TEST + 1))
        echo "  ✗ FAIL: $assertion_label_for_iter141"
        echo "    forbidden substring (should NOT appear): ${forbidden_substring:0:120}"
    fi
}

echo "═══════════════════════════════════════════════════════════════════════════════"
echo "  Iter-141 multi-iter regression test"
echo "  (covers iter-137 + iter-138 + iter-139 + iter-140 — release-pipeline-instrumentation cohort)"
echo "═══════════════════════════════════════════════════════════════════════════════"

preflight_script_source="$(cat "$PREFLIGHT_SCRIPT_ABSOLUTE_PATH")"
release_full_orchestrator_source="$(cat "$RELEASE_FULL_ORCHESTRATOR_ABSOLUTE_PATH")"
releaserc_yml_source="$(cat "$RELEASERC_YML_ABSOLUTE_PATH")"
# Iter-142: iter-140 helpers were relocated from .releaserc.yml YAML literal
# into the extracted post-release verification script. Iter-140.D1-D8 assertions
# now read this source instead of releaserc_yml_source.
iter142_extracted_post_release_verification_script_source_for_iter140_helper_assertions="$(cat "$ITER142_EXTRACTED_POST_RELEASE_VERIFICATION_SCRIPT_ABSOLUTE_PATH_FOR_ITER140_HELPER_ASSERTIONS_AFTER_ITER142_RELOCATION")"

echo ""
echo "── ITER-137: iter-130 ranking is parallelism-aware (bucket labels + critical-path NOTE) ──"

# 1.A: timing helper accepts optional bucket-label second arg
__iter141_assert_substring_present \
    "Iter-137.A1: __preflight_timing_report_phase_elapsed_milliseconds accepts optional parallel_execution_bucket_label_for_wall_clock_attribution_awareness second arg" \
    "$preflight_script_source" \
    "parallel_execution_bucket_label_for_wall_clock_attribution_awareness"

# 1.B: per-phase inline output emits "[parallel: BUCKET]" suffix when bucket set
# shellcheck disable=SC2016
# SC2016 deliberate-suppress: the third arg is a LITERAL substring we expect to find
# in the preflight source (which uses \${var} for bash variable expansion at runtime).
# Single-quoting is REQUIRED to match the literal "[parallel: \${...}]" bytes in the
# source file — any expansion here would defeat the purpose of the assertion.
__iter141_assert_substring_present \
    "Iter-137.A2: per-phase '⧗ phase elapsed' line emits '[parallel: BUCKET]' suffix when bucket non-empty" \
    "$preflight_script_source" \
    '  [parallel: ${parallel_execution_bucket_label_for_wall_clock_attribution_awareness}]'

# 1.C: end-of-script ranking awk script handles 3-field records with bucket
__iter141_assert_substring_present \
    "Iter-137.A3: end-of-script iter-130 ranking awk script renders '[parallel: %s]' suffix on bucketed entries" \
    "$preflight_script_source" \
    '[parallel: %s]'

# 1.D: critical-path attribution NOTE emitter exists
__iter141_assert_substring_present \
    "Iter-137.A4: end-of-ranking 'wall-clock attribution NOTE' identifying slowest parallel-batch member exists" \
    "$preflight_script_source" \
    "NOTE (iter-137 wall-clock attribution)"

# 1.E: associative-array critical-path tracking exists
__iter141_assert_substring_present \
    "Iter-137.A5: per-bucket max-elapsed-ms + slowest-member-label associative arrays exist (critical-path tracking)" \
    "$preflight_script_source" \
    "iter137_max_elapsed_ms_per_parallel_execution_bucket"

# 1.F: all 17 Check 4f-4v call-sites pass "iter134-audit-batch" bucket
iter137_audit_batch_callsite_count=$(grep -cF '"iter134-audit-batch"' "$PREFLIGHT_SCRIPT_ABSOLUTE_PATH")
if [[ "$iter137_audit_batch_callsite_count" -ge 17 ]]; then
    ASSERTION_COUNT_PASSED_FOR_ITER141_RELEASE_PIPELINE_INSTRUMENTATION_COHORT_REGRESSION_TEST=$((ASSERTION_COUNT_PASSED_FOR_ITER141_RELEASE_PIPELINE_INSTRUMENTATION_COHORT_REGRESSION_TEST + 1))
    echo "  ✓ PASS: Iter-137.A6: 'iter134-audit-batch' bucket label passed from $iter137_audit_batch_callsite_count call-sites (≥17 = all Checks 4f-4v use bucket-aware ranking)"
else
    ASSERTION_COUNT_FAILED_FOR_ITER141_RELEASE_PIPELINE_INSTRUMENTATION_COHORT_REGRESSION_TEST=$((ASSERTION_COUNT_FAILED_FOR_ITER141_RELEASE_PIPELINE_INSTRUMENTATION_COHORT_REGRESSION_TEST + 1))
    echo "  ✗ FAIL: Iter-137.A6: 'iter134-audit-batch' bucket call-site count below threshold (expected ≥17, got $iter137_audit_batch_callsite_count)"
fi

echo ""
echo "── ITER-138: chronicle-slicing test relocated into iter-50/138 marketplace-suite auto-discovery ──"

# 2.A: chronicle test is at the NEW location
if [[ -f "$CHRONICLE_TEST_ABSOLUTE_PATH" ]] && [[ -x "$CHRONICLE_TEST_ABSOLUTE_PATH" ]]; then
    ASSERTION_COUNT_PASSED_FOR_ITER141_RELEASE_PIPELINE_INSTRUMENTATION_COHORT_REGRESSION_TEST=$((ASSERTION_COUNT_PASSED_FOR_ITER141_RELEASE_PIPELINE_INSTRUMENTATION_COHORT_REGRESSION_TEST + 1))
    echo "  ✓ PASS: Iter-138.B1: chronicle test exists + executable at .mise/tasks/tests/test-chronicle-slicing-37-assertion-*.sh"
else
    ASSERTION_COUNT_FAILED_FOR_ITER141_RELEASE_PIPELINE_INSTRUMENTATION_COHORT_REGRESSION_TEST=$((ASSERTION_COUNT_FAILED_FOR_ITER141_RELEASE_PIPELINE_INSTRUMENTATION_COHORT_REGRESSION_TEST + 1))
    echo "  ✗ FAIL: Iter-138.B1: chronicle test missing or not executable at $CHRONICLE_TEST_ABSOLUTE_PATH"
fi

# 2.B: chronicle test is NOT at the OLD location (regression: file moved back)
if [[ ! -e "$LEGACY_CHRONICLE_TEST_RELEASE_DIR_PATH" ]]; then
    ASSERTION_COUNT_PASSED_FOR_ITER141_RELEASE_PIPELINE_INSTRUMENTATION_COHORT_REGRESSION_TEST=$((ASSERTION_COUNT_PASSED_FOR_ITER141_RELEASE_PIPELINE_INSTRUMENTATION_COHORT_REGRESSION_TEST + 1))
    echo "  ✓ PASS: Iter-138.B2: chronicle test ABSENT at legacy .mise/tasks/release/test-chronicle-slicing path (iter-138 relocation pinned)"
else
    ASSERTION_COUNT_FAILED_FOR_ITER141_RELEASE_PIPELINE_INSTRUMENTATION_COHORT_REGRESSION_TEST=$((ASSERTION_COUNT_FAILED_FOR_ITER141_RELEASE_PIPELINE_INSTRUMENTATION_COHORT_REGRESSION_TEST + 1))
    echo "  ✗ FAIL: Iter-138.B2: chronicle test reintroduced at legacy location (iter-138 relocation regressed)"
fi

# 2.C: chronicle test patched to reference ../release/chronicle
chronicle_test_source="$(cat "$CHRONICLE_TEST_ABSOLUTE_PATH" 2>/dev/null || echo "")"
# shellcheck disable=SC2016
# SC2016 deliberate-suppress: the third arg is a LITERAL substring we expect to find
# in the chronicle test source file. The test source contains \$(dirname "\$0")/../release/chronicle
# as bash code that resolves at runtime; here we want to grep for those literal bytes,
# so single-quoting (no expansion) is required.
__iter141_assert_substring_present \
    "Iter-138.B3: chronicle test CHRONICLE_SCRIPT path patched to ../release/chronicle (relative-path adapter for iter-138 relocation)" \
    "$chronicle_test_source" \
    '$(dirname "$0")/../release/chronicle'

# 2.D: preflight has the "ABSORBED into Check 4e" stub comment (Check 4d gone)
__iter141_assert_substring_present \
    "Iter-138.B4: preflight Check 4d block replaced with 'ABSORBED into Check 4e by iter-138' stub comment" \
    "$preflight_script_source" \
    "ABSORBED into Check 4e by iter-138"

# 2.E: preflight no longer invokes `mise run release:test-chronicle-slicing` (regression: re-added the duplicate)
# Use grep -E with a comment-excluding anchor: matches lines where the task-name
# appears OUTSIDE of a comment context. The iter-138 ABSORBED stub-comment
# legitimately references the old task name inside a comment line ("Operators
# previously running `mise run release:test-chronicle-slicing` can now invoke...");
# that comment mention must NOT trigger a regression failure. Only an ACTIVE
# code-form invocation (`if ! mise run ...` or `mise run release:test-chronicle-slicing >/tmp/...`)
# should fail. Discriminator: line begins with optional whitespace + non-#
# character + ... + task-name (i.e., not a comment line).
if grep -E '^[[:space:]]*[^#[:space:]].*mise run release:test-chronicle-slicing' "$PREFLIGHT_SCRIPT_ABSOLUTE_PATH" >/dev/null 2>&1; then
    ASSERTION_COUNT_FAILED_FOR_ITER141_RELEASE_PIPELINE_INSTRUMENTATION_COHORT_REGRESSION_TEST=$((ASSERTION_COUNT_FAILED_FOR_ITER141_RELEASE_PIPELINE_INSTRUMENTATION_COHORT_REGRESSION_TEST + 1))
    echo "  ✗ FAIL: Iter-138.B5: preflight has an ACTIVE invocation of 'mise run release:test-chronicle-slicing' (would reintroduce ~670ms sequential cost; iter-138 ABSORBED comment mention is fine)"
else
    ASSERTION_COUNT_PASSED_FOR_ITER141_RELEASE_PIPELINE_INSTRUMENTATION_COHORT_REGRESSION_TEST=$((ASSERTION_COUNT_PASSED_FOR_ITER141_RELEASE_PIPELINE_INSTRUMENTATION_COHORT_REGRESSION_TEST + 1))
    echo "  ✓ PASS: Iter-138.B5: preflight has NO ACTIVE 'mise run release:test-chronicle-slicing' invocation (comment-only mentions in iter-138 ABSORBED stub are OK)"
fi

echo ""
echo "── ITER-139: RELEASE_TIMING_PROFILE pipeline-level instrumentation in release/full ──"

# 3.A: env-var-driven opt-in
__iter141_assert_substring_present \
    "Iter-139.C1: RELEASE_TIMING_PROFILE env-var referenced in release/full orchestrator" \
    "$release_full_orchestrator_source" \
    "RELEASE_TIMING_PROFILE"

# 3.B: phase-wrap helper defined
__iter141_assert_substring_present \
    "Iter-139.C2: __iter139_wrap_release_phase_invocation_with_epochrealtime_wall_clock_capture helper defined" \
    "$release_full_orchestrator_source" \
    "__iter139_wrap_release_phase_invocation_with_epochrealtime_wall_clock_capture_for_release_timing_profile_top_n_bottleneck_ranking"

# 3.C: top-N ranking emitter defined
__iter141_assert_substring_present \
    "Iter-139.C3: __iter139_emit_top_n_slowest_release_phases bottleneck-ranking summary helper defined" \
    "$release_full_orchestrator_source" \
    "__iter139_emit_top_n_slowest_release_phases_ranked_by_elapsed_milliseconds_descending_bottleneck_summary"

# 3.D: depends=["release:preflight"] frontmatter REMOVED (otherwise preflight runs outside the wrapper)
# The mise frontmatter form is `#MISE depends=[...]` as a leading-hash comment
# directive at the top of the file. The iter-139 implementation comment legitimately
# REFERENCES the old frontmatter form inside an explanatory paragraph ("Removed the
# previous `#MISE depends=[\"release:preflight\"]` declaration..."). That comment
# mention must NOT fail the regression — only an ACTIVE frontmatter line at the top
# of the file would. Discriminator: a line matching exactly `#MISE depends=[...]`
# (mise frontmatter format) — not a body text mention.
if grep -E '^#MISE depends=\[.*release:preflight.*\]' "$RELEASE_FULL_ORCHESTRATOR_ABSOLUTE_PATH" >/dev/null 2>&1; then
    ASSERTION_COUNT_FAILED_FOR_ITER141_RELEASE_PIPELINE_INSTRUMENTATION_COHORT_REGRESSION_TEST=$((ASSERTION_COUNT_FAILED_FOR_ITER141_RELEASE_PIPELINE_INSTRUMENTATION_COHORT_REGRESSION_TEST + 1))
    echo "  ✗ FAIL: Iter-139.C4: release/full has an ACTIVE '#MISE depends=[\"release:preflight\"]' frontmatter line (preflight would run outside the iter-139 timing wrapper; iter-139 implementation-comment mention is fine)"
else
    ASSERTION_COUNT_PASSED_FOR_ITER141_RELEASE_PIPELINE_INSTRUMENTATION_COHORT_REGRESSION_TEST=$((ASSERTION_COUNT_PASSED_FOR_ITER141_RELEASE_PIPELINE_INSTRUMENTATION_COHORT_REGRESSION_TEST + 1))
    echo "  ✓ PASS: Iter-139.C4: release/full has NO ACTIVE '#MISE depends=[\"release:preflight\"]' frontmatter line (preflight is wrapped explicitly inside orchestrator for iter-139 timing capture)"
fi

# 3.E: all 7 phases wrapped (count callsites of the helper)
iter139_phase_wrap_callsite_count=$(grep -cF '__iter139_wrap_release_phase_invocation_with_epochrealtime_wall_clock_capture_for_release_timing_profile_top_n_bottleneck_ranking' "$RELEASE_FULL_ORCHESTRATOR_ABSOLUTE_PATH")
# Subtract 1 for the function definition itself.
iter139_phase_wrap_callsite_count=$((iter139_phase_wrap_callsite_count - 1))
if [[ "$iter139_phase_wrap_callsite_count" -ge 7 ]]; then
    ASSERTION_COUNT_PASSED_FOR_ITER141_RELEASE_PIPELINE_INSTRUMENTATION_COHORT_REGRESSION_TEST=$((ASSERTION_COUNT_PASSED_FOR_ITER141_RELEASE_PIPELINE_INSTRUMENTATION_COHORT_REGRESSION_TEST + 1))
    echo "  ✓ PASS: Iter-139.C5: 7 release phases wrapped with timing helper ($iter139_phase_wrap_callsite_count call-sites; preflight + presync + version + sync + verify + chronicle + postflight)"
else
    ASSERTION_COUNT_FAILED_FOR_ITER141_RELEASE_PIPELINE_INSTRUMENTATION_COHORT_REGRESSION_TEST=$((ASSERTION_COUNT_FAILED_FOR_ITER141_RELEASE_PIPELINE_INSTRUMENTATION_COHORT_REGRESSION_TEST + 1))
    echo "  ✗ FAIL: Iter-139.C5: phase-wrap call-site count below threshold (expected ≥7, got $iter139_phase_wrap_callsite_count)"
fi

# 3.F: whole-pipeline timer for sum-of-phases vs wall-clock sanity check
__iter141_assert_substring_present \
    "Iter-139.C6: whole-pipeline EPOCHREALTIME start-time capture exists (sum-of-phases vs wall-clock sanity)" \
    "$release_full_orchestrator_source" \
    "release_timing_profile_whole_pipeline_start_seconds_using_epochrealtime"

# 3.G: ITER139 top-N override env-var
__iter141_assert_substring_present \
    "Iter-139.C7: ITER139_TOP_N_SLOWEST_RELEASE_PHASES_TO_DISPLAY operator-tunable override exists" \
    "$release_full_orchestrator_source" \
    "ITER139_TOP_N_SLOWEST_RELEASE_PHASES_TO_DISPLAY"

echo ""
echo "── ITER-140: successCmd per-step instrumentation + sleep-2 elimination forensic pin ──"

# 4.A: per-step start/end helpers defined in extracted script (iter-142 relocated
# from .releaserc.yml YAML literal heredoc to scripts/iter142-...sh — same
# invariants, new location.)
__iter141_assert_substring_present \
    "Iter-140.D1: __iter140_start_post_release_successcmd_step_with_epochrealtime_wall_clock_capture helper defined in iter-142 extracted post-release verification script" \
    "$iter142_extracted_post_release_verification_script_source_for_iter140_helper_assertions" \
    "__iter140_start_post_release_successcmd_step_with_epochrealtime_wall_clock_capture"

__iter141_assert_substring_present \
    "Iter-140.D2: __iter140_end_post_release_successcmd_step_with_epochrealtime_wall_clock_capture helper defined in iter-142 extracted script" \
    "$iter142_extracted_post_release_verification_script_source_for_iter140_helper_assertions" \
    "__iter140_end_post_release_successcmd_step_with_epochrealtime_wall_clock_capture"

# 4.B: timing record accumulator array
__iter141_assert_substring_present \
    "Iter-140.D3: per-step timing record accumulator array exists in iter-142 extracted script" \
    "$iter142_extracted_post_release_verification_script_source_for_iter140_helper_assertions" \
    "__iter140_per_successcmd_step_timing_record_array_for_top_n_slowest_bottleneck_ranking_summary"

# 4.C: ITER140 top-N override env-var
__iter141_assert_substring_present \
    "Iter-140.D4: ITER140_TOP_N_SLOWEST_SUCCESSCMD_STEPS_TO_DISPLAY operator-tunable override exists in iter-142 extracted script" \
    "$iter142_extracted_post_release_verification_script_source_for_iter140_helper_assertions" \
    "ITER140_TOP_N_SLOWEST_SUCCESSCMD_STEPS_TO_DISPLAY"

# 4.D: end-of-block top-N ranking renders sort -rn pipeline (mirrors iter-130 / iter-139)
__iter141_assert_substring_present \
    "Iter-140.D5: end-of-block top-N ranking uses sort -rn -k1 | head -n N | awk pipeline (mirrors iter-130/139 ranking format) in iter-142 extracted script" \
    "$iter142_extracted_post_release_verification_script_source_for_iter140_helper_assertions" \
    "sort -rn -k1"

# 4.E: 6 functional steps wrapped (Step 1, 2, 4, 5, 6, 7 — Step 3 is the eliminated sleep)
iter140_step_wrap_callsite_count=$(echo "$iter142_extracted_post_release_verification_script_source_for_iter140_helper_assertions" | grep -cF '__iter140_start_post_release_successcmd_step_with_epochrealtime_wall_clock_capture')
# Subtract 1 for the function definition itself.
iter140_step_wrap_callsite_count=$((iter140_step_wrap_callsite_count - 1))
if [[ "$iter140_step_wrap_callsite_count" -ge 6 ]]; then
    ASSERTION_COUNT_PASSED_FOR_ITER141_RELEASE_PIPELINE_INSTRUMENTATION_COHORT_REGRESSION_TEST=$((ASSERTION_COUNT_PASSED_FOR_ITER141_RELEASE_PIPELINE_INSTRUMENTATION_COHORT_REGRESSION_TEST + 1))
    echo "  ✓ PASS: Iter-140.D6: 6 successCmd steps wrapped with timing helper ($iter140_step_wrap_callsite_count call-sites; Steps 1, 2, 4, 5, 6, 7 — Step 3 is the eliminated sleep) in iter-142 extracted script"
else
    ASSERTION_COUNT_FAILED_FOR_ITER141_RELEASE_PIPELINE_INSTRUMENTATION_COHORT_REGRESSION_TEST=$((ASSERTION_COUNT_FAILED_FOR_ITER141_RELEASE_PIPELINE_INSTRUMENTATION_COHORT_REGRESSION_TEST + 1))
    echo "  ✗ FAIL: Iter-140.D6: step-wrap call-site count below threshold (expected ≥6, got $iter140_step_wrap_callsite_count) in iter-142 extracted script"
fi

# 4.F: FORENSIC PIN — Step 3 sleep-2 ELIMINATED
# This is the load-bearing assertion preventing iter-140's perf win from
# regressing. A future maintainer reintroducing `sleep 2` (e.g., thinking
# it's needed for cache propagation) would silently burn 2s/release.
# Iter-142: assertion now scans the extracted script (not .releaserc.yml).
__iter141_assert_substring_absent \
    "Iter-140.D7: FORENSIC PIN — the literal 'sleep 2' ABSENT from iter-142 extracted post-release verification script (iter-140 elimination invariant)" \
    "$iter142_extracted_post_release_verification_script_source_for_iter140_helper_assertions" \
    $'\nsleep 2\n'

# 4.G: ELIMINATED-by-iter-140 stub comment exists where sleep 2 used to be
__iter141_assert_substring_present \
    "Iter-140.D8: 'Step 3: ELIMINATED by iter-140' stub comment exists in iter-142 extracted script (explains why sleep 2 was removed)" \
    "$iter142_extracted_post_release_verification_script_source_for_iter140_helper_assertions" \
    "Step 3: ELIMINATED by iter-140"

# ─── Summary ─────────────────────────────────────────────────────────────
echo ""
echo "═══════════════════════════════════════════════════════════════════════════════"
echo "  Iter-141 regression — Summary"
echo "═══════════════════════════════════════════════════════════════════════════════"
echo "  Assertions passed: $ASSERTION_COUNT_PASSED_FOR_ITER141_RELEASE_PIPELINE_INSTRUMENTATION_COHORT_REGRESSION_TEST"
echo "  Assertions failed: $ASSERTION_COUNT_FAILED_FOR_ITER141_RELEASE_PIPELINE_INSTRUMENTATION_COHORT_REGRESSION_TEST"
echo "═══════════════════════════════════════════════════════════════════════════════"

if [[ "$ASSERTION_COUNT_FAILED_FOR_ITER141_RELEASE_PIPELINE_INSTRUMENTATION_COHORT_REGRESSION_TEST" -gt 0 ]]; then
    echo "  ✗ FAIL — $ASSERTION_COUNT_FAILED_FOR_ITER141_RELEASE_PIPELINE_INSTRUMENTATION_COHORT_REGRESSION_TEST assertion(s) failed"
    exit 1
fi

echo "  ✓ PASS — all $ASSERTION_COUNT_PASSED_FOR_ITER141_RELEASE_PIPELINE_INSTRUMENTATION_COHORT_REGRESSION_TEST assertions passed"
echo ""
echo "  🚀 iter-137/138/139/140 cohort regression-guarded across four invariants:"
echo "     1. Iter-137 parallelism-aware bucket labels in iter-130 ranking + critical-path NOTE"
echo "     2. Iter-138 chronicle-slicing test absorbed into iter-50 marketplace-suite auto-discovery"
echo "     3. Iter-139 RELEASE_TIMING_PROFILE pipeline-level timing across all 7 phases"
echo "     4. Iter-140 successCmd per-step timing + sleep-2 ELIMINATED (forensic pin)"
