#!/usr/bin/env bash
#MISE description="Iter-147 regression test pinning two dual deliverables: (a) variance-characterization harness script structurally valid + executable + python-compile-clean + correctly invokes iter-144 parser + emits p50/p95/mean/stddev/min/max/range columns + flags HIGH variance + honors REPLAY env var, (b) .mise/tasks/release/full mise task gained env-var-scoped SSH ControlMaster opt-in block guarded by RELEASE_SSH_MULTIPLEXING_ENABLED env var that idempotent-creates ~/.ssh/controlmasters with mode 0700 + exports GIT_SSH_COMMAND with ControlMaster=auto + ControlPath + ControlPersist=10m directives, (c) docs/RELEASE.md surfaces both knobs in the perf-knobs reference for operator discovery."
set -euo pipefail

ITER147_REPO_ROOT="${AUDIT_REPO_ROOT_OVERRIDE:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
cd "$ITER147_REPO_ROOT"

ITER147_VARIANCE_HARNESS_PYTHON_SCRIPT_RELATIVE_PATH="scripts/iter147-empirical-n-run-variance-characterization-harness-for-semantic-release-namespace-timings-via-iter144-parser-emitting-p50-p95-mean-stddev-min-max-range.py"
ITER147_VARIANCE_HARNESS_PYTHON_SCRIPT_ABSOLUTE_PATH="$ITER147_REPO_ROOT/$ITER147_VARIANCE_HARNESS_PYTHON_SCRIPT_RELATIVE_PATH"
ITER147_RELEASE_FULL_MISE_TASK_RELATIVE_PATH=".mise/tasks/release/full"
ITER147_RELEASE_FULL_MISE_TASK_ABSOLUTE_PATH="$ITER147_REPO_ROOT/$ITER147_RELEASE_FULL_MISE_TASK_RELATIVE_PATH"
ITER147_RELEASE_MD_DOC_RELATIVE_PATH="docs/RELEASE.md"

ITER147_TOTAL_ASSERTIONS_EVALUATED=0
ITER147_TOTAL_ASSERTIONS_FAILED=0

iter147_assert_substring_present_in_file() {
    local human_readable_assertion_label="$1"
    local file_path_to_grep="$2"
    local expected_substring="$3"
    ITER147_TOTAL_ASSERTIONS_EVALUATED=$((ITER147_TOTAL_ASSERTIONS_EVALUATED + 1))
    if grep -qF -- "$expected_substring" "$file_path_to_grep" 2>/dev/null; then
        echo "  ✓ $human_readable_assertion_label"
    else
        echo "  ✗ $human_readable_assertion_label"
        echo "    expected substring: ${expected_substring:0:120}"
        ITER147_TOTAL_ASSERTIONS_FAILED=$((ITER147_TOTAL_ASSERTIONS_FAILED + 1))
    fi
}

iter147_assert_filesystem_predicate_holds() {
    local human_readable_assertion_label="$1"
    local bash_test_expression="$2"
    ITER147_TOTAL_ASSERTIONS_EVALUATED=$((ITER147_TOTAL_ASSERTIONS_EVALUATED + 1))
    if eval "[[ $bash_test_expression ]]" 2>/dev/null; then
        echo "  ✓ $human_readable_assertion_label"
    else
        echo "  ✗ $human_readable_assertion_label"
        echo "    failed bash predicate: $bash_test_expression"
        ITER147_TOTAL_ASSERTIONS_FAILED=$((ITER147_TOTAL_ASSERTIONS_FAILED + 1))
    fi
}

echo ""
echo "═══════════════════════════════════════════════════════════════════════════════"
echo "  ITER-147 VARIANCE-HARNESS + ENV-VAR-SSH-CONTROLMASTER REGRESSION TEST"
echo "═══════════════════════════════════════════════════════════════════════════════"

# ─── Group A: Variance harness structural validity ────────────────────────────
echo ""
echo "GROUP A (4 assertions): Variance harness Python script structurally valid"

iter147_assert_filesystem_predicate_holds \
    "A1: variance harness exists at iter-147 verbose path" \
    "-f \"$ITER147_VARIANCE_HARNESS_PYTHON_SCRIPT_ABSOLUTE_PATH\""

iter147_assert_filesystem_predicate_holds \
    "A2: variance harness is executable (chmod +x)" \
    "-x \"$ITER147_VARIANCE_HARNESS_PYTHON_SCRIPT_ABSOLUTE_PATH\""

ITER147_TOTAL_ASSERTIONS_EVALUATED=$((ITER147_TOTAL_ASSERTIONS_EVALUATED + 1))
if python3 -c "import py_compile; py_compile.compile('$ITER147_VARIANCE_HARNESS_PYTHON_SCRIPT_ABSOLUTE_PATH', doraise=True)" 2>/dev/null; then
    echo "  ✓ A3: variance harness passes py_compile syntax check"
else
    echo "  ✗ A3: variance harness FAILS py_compile syntax check"
    ITER147_TOTAL_ASSERTIONS_FAILED=$((ITER147_TOTAL_ASSERTIONS_FAILED + 1))
fi

iter147_assert_substring_present_in_file \
    "A4: variance harness has correct shebang (#!/usr/bin/env python3)" \
    "$ITER147_VARIANCE_HARNESS_PYTHON_SCRIPT_ABSOLUTE_PATH" \
    "#!/usr/bin/env python3"

# ─── Group B: Variance harness emits expected percentile column structure ────
echo ""
echo "GROUP B (7 assertions): Variance harness emits expected percentile columns + invariants"

iter147_assert_substring_present_in_file \
    "B1: harness function name encodes the iter-144 parser dependency" \
    "$ITER147_VARIANCE_HARNESS_PYTHON_SCRIPT_ABSOLUTE_PATH" \
    "iter147_invoke_iter144_parser_on_one_per_run_stderr_log"

iter147_assert_substring_present_in_file \
    "B2: harness implements p50 nearest-rank percentile" \
    "$ITER147_VARIANCE_HARNESS_PYTHON_SCRIPT_ABSOLUTE_PATH" \
    "iter147_compute_percentile_p_of_integer_value_sample_list_using_nearest_rank_method"

iter147_assert_substring_present_in_file \
    "B3: harness honors ITER147_VARIANCE_PROFILE_RUN_COUNT env var" \
    "$ITER147_VARIANCE_HARNESS_PYTHON_SCRIPT_ABSOLUTE_PATH" \
    "ITER147_VARIANCE_PROFILE_RUN_COUNT"

iter147_assert_substring_present_in_file \
    "B4: harness honors ITER147_VARIANCE_PROFILE_REPLAY_FROM_EXISTING_LOGS env var" \
    "$ITER147_VARIANCE_HARNESS_PYTHON_SCRIPT_ABSOLUTE_PATH" \
    "ITER147_VARIANCE_PROFILE_REPLAY_FROM_EXISTING_LOGS"

iter147_assert_substring_present_in_file \
    "B5: harness emits HIGH variance trap flag with sigma/p50 ratio threshold 0.20" \
    "$ITER147_VARIANCE_HARNESS_PYTHON_SCRIPT_ABSOLUTE_PATH" \
    "ITER147_VARIANCE_FLAG_HIGH_STDDEV_TO_P50_RATIO_THRESHOLD_FOR_TRAP_WARNING = 0.20"

iter147_assert_substring_present_in_file \
    "B6: harness documents the iter-143 single-sample variance trap as motivation" \
    "$ITER147_VARIANCE_HARNESS_PYTHON_SCRIPT_ABSOLUTE_PATH" \
    "iter-143"

iter147_assert_substring_present_in_file \
    "B7: harness documents the working-directory-cleanliness gotcha for full namespace cohort" \
    "$ITER147_VARIANCE_HARNESS_PYTHON_SCRIPT_ABSOLUTE_PATH" \
    "WORKING-DIRECTORY-CLEANLINESS GOTCHA"

# ─── Group C: Variance harness functional smoke test in REPLAY mode ──────────
echo ""
echo "GROUP C (3 assertions): Variance harness functional smoke test via REPLAY mode"

# Stage two identical replay logs so the harness can compute distribution
# without actually invoking semantic-release.
ITER147_REPLAY_FIXTURE_STDERR_LOG_PATH_FOR_HARNESS_FUNCTIONAL_VALIDATION="/tmp/iter147-test-replay-fixture-$$.log"
cat > "$ITER147_REPLAY_FIXTURE_STDERR_LOG_PATH_FOR_HARNESS_FUNCTIONAL_VALIDATION" <<'EOF_REPLAY_FIXTURE'
2026-05-21T14:00:00.000Z semantic-release:config foo
2026-05-21T14:00:00.500Z semantic-release:config bar
2026-05-21T14:00:02.000Z semantic-release:get-tags found tags
EOF_REPLAY_FIXTURE
cp "$ITER147_REPLAY_FIXTURE_STDERR_LOG_PATH_FOR_HARNESS_FUNCTIONAL_VALIDATION" /tmp/iter147-variance-profile-run-1.log
cp "$ITER147_REPLAY_FIXTURE_STDERR_LOG_PATH_FOR_HARNESS_FUNCTIONAL_VALIDATION" /tmp/iter147-variance-profile-run-2.log

ITER147_HARNESS_REPLAY_FUNCTIONAL_SMOKE_TEST_STDOUT_CAPTURE=$(
    ITER147_VARIANCE_PROFILE_RUN_COUNT=2 \
    ITER147_VARIANCE_PROFILE_REPLAY_FROM_EXISTING_LOGS=1 \
    python3 "$ITER147_VARIANCE_HARNESS_PYTHON_SCRIPT_ABSOLUTE_PATH" 2>&1 || true
)

ITER147_TOTAL_ASSERTIONS_EVALUATED=$((ITER147_TOTAL_ASSERTIONS_EVALUATED + 1))
if [[ "$ITER147_HARNESS_REPLAY_FUNCTIONAL_SMOKE_TEST_STDOUT_CAPTURE" == *"VARIANCE CHARACTERIZATION"* ]]; then
    echo "  ✓ C1: harness REPLAY mode emits VARIANCE CHARACTERIZATION banner"
else
    echo "  ✗ C1: harness REPLAY mode banner missing"
    ITER147_TOTAL_ASSERTIONS_FAILED=$((ITER147_TOTAL_ASSERTIONS_FAILED + 1))
fi

ITER147_TOTAL_ASSERTIONS_EVALUATED=$((ITER147_TOTAL_ASSERTIONS_EVALUATED + 1))
if [[ "$ITER147_HARNESS_REPLAY_FUNCTIONAL_SMOKE_TEST_STDOUT_CAPTURE" == *"p50"* ]] && \
   [[ "$ITER147_HARNESS_REPLAY_FUNCTIONAL_SMOKE_TEST_STDOUT_CAPTURE" == *"p95"* ]] && \
   [[ "$ITER147_HARNESS_REPLAY_FUNCTIONAL_SMOKE_TEST_STDOUT_CAPTURE" == *"stddev"* ]]; then
    echo "  ✓ C2: harness REPLAY mode emits p50/p95/stddev column headers"
else
    echo "  ✗ C2: harness REPLAY mode missing one of p50/p95/stddev"
    ITER147_TOTAL_ASSERTIONS_FAILED=$((ITER147_TOTAL_ASSERTIONS_FAILED + 1))
fi

ITER147_TOTAL_ASSERTIONS_EVALUATED=$((ITER147_TOTAL_ASSERTIONS_EVALUATED + 1))
# Capture output first (separately from grep) so the pipeline's non-zero exit
# from python's deliberate variance-undefined-rejection does not collide with
# `set -euo pipefail`. We WANT python to exit non-zero here; we're verifying
# the rejection message accompanies the non-zero exit.
ITER147_HARNESS_N_LESS_THAN_TWO_REJECTION_OUTPUT_CAPTURE=$(
    ITER147_VARIANCE_PROFILE_RUN_COUNT=1 \
    ITER147_VARIANCE_PROFILE_REPLAY_FROM_EXISTING_LOGS=1 \
    python3 "$ITER147_VARIANCE_HARNESS_PYTHON_SCRIPT_ABSOLUTE_PATH" 2>&1 || true
)
if [[ "$ITER147_HARNESS_N_LESS_THAN_TWO_REJECTION_OUTPUT_CAPTURE" == *"undefined for a single sample"* ]]; then
    echo "  ✓ C3: harness rejects N<2 with explanatory error (variance undefined for n=1)"
else
    echo "  ✗ C3: harness should reject N<2 explicitly"
    echo "    got: ${ITER147_HARNESS_N_LESS_THAN_TWO_REJECTION_OUTPUT_CAPTURE:0:200}"
    ITER147_TOTAL_ASSERTIONS_FAILED=$((ITER147_TOTAL_ASSERTIONS_FAILED + 1))
fi

# Cleanup test-staged replay fixture files.
rm -f "$ITER147_REPLAY_FIXTURE_STDERR_LOG_PATH_FOR_HARNESS_FUNCTIONAL_VALIDATION" \
      /tmp/iter147-variance-profile-run-1.log \
      /tmp/iter147-variance-profile-run-2.log

# ─── Group D: release/full mise task ships env-var-scoped SSH ControlMaster ──
echo ""
echo "GROUP D (5 assertions): release/full mise task gained iter-147 env-var-scoped SSH multiplexing opt-in"

iter147_assert_substring_present_in_file \
    "D1: release/full guards block on RELEASE_SSH_MULTIPLEXING_ENABLED env var" \
    "$ITER147_RELEASE_FULL_MISE_TASK_ABSOLUTE_PATH" \
    'RELEASE_SSH_MULTIPLEXING_ENABLED:-0'

# Single-quoted literal search strings on next two assertions intentionally
# preserve the `$VARNAME` dollar-sign as part of the substring being searched
# for in the source file. Shellcheck SC2016 (no-expansion-in-single-quotes)
# is the desired behavior here, so suppress.
# shellcheck disable=SC2016
iter147_assert_substring_present_in_file \
    "D2: release/full creates ~/.ssh/controlmasters dir with mkdir -p" \
    "$ITER147_RELEASE_FULL_MISE_TASK_ABSOLUTE_PATH" \
    'mkdir -p "$ITER147_SSH_CONTROLMASTERS_DIR_FOR_CACHED_SESSION_SOCKETS_PER_RELEASE_INVOCATION"'

# shellcheck disable=SC2016
iter147_assert_substring_present_in_file \
    "D3: release/full tightens ~/.ssh/controlmasters dir perms to 0700 (chmod 700)" \
    "$ITER147_RELEASE_FULL_MISE_TASK_ABSOLUTE_PATH" \
    'chmod 700 "$ITER147_SSH_CONTROLMASTERS_DIR_FOR_CACHED_SESSION_SOCKETS_PER_RELEASE_INVOCATION"'

iter147_assert_substring_present_in_file \
    "D4: release/full exports GIT_SSH_COMMAND with ControlMaster=auto + ControlPersist=10m" \
    "$ITER147_RELEASE_FULL_MISE_TASK_ABSOLUTE_PATH" \
    'export GIT_SSH_COMMAND="ssh -o ControlMaster=auto -o ControlPath='

iter147_assert_substring_present_in_file \
    "D5: release/full sets ControlPersist=10m TTL matching iter-146 invariant" \
    "$ITER147_RELEASE_FULL_MISE_TASK_ABSOLUTE_PATH" \
    'ControlPersist=10m"'

# ─── Group E: docs/RELEASE.md surfaces both iter-147 knobs ───────────────────
echo ""
echo "GROUP E (3 assertions): docs/RELEASE.md surfaces both iter-147 knobs"

iter147_assert_substring_present_in_file \
    "E1: docs/RELEASE.md mentions ITER147_VARIANCE_PROFILE_RUN_COUNT knob" \
    "$ITER147_RELEASE_MD_DOC_RELATIVE_PATH" \
    "ITER147_VARIANCE_PROFILE_RUN_COUNT"

iter147_assert_substring_present_in_file \
    "E2: docs/RELEASE.md mentions RELEASE_SSH_MULTIPLEXING_ENABLED knob" \
    "$ITER147_RELEASE_MD_DOC_RELATIVE_PATH" \
    "RELEASE_SSH_MULTIPLEXING_ENABLED"

iter147_assert_substring_present_in_file \
    "E3: docs/RELEASE.md cross-references iter-146 as the ~/.ssh/config-modifying sibling path" \
    "$ITER147_RELEASE_MD_DOC_RELATIVE_PATH" \
    "iter-146"

# ─── Final report ─────────────────────────────────────────────────────────────
echo ""
echo "═══════════════════════════════════════════════════════════════════════════════"
if (( ITER147_TOTAL_ASSERTIONS_FAILED == 0 )); then
    echo "  ✓ ITER-147 REGRESSION TEST: ${ITER147_TOTAL_ASSERTIONS_EVALUATED}/${ITER147_TOTAL_ASSERTIONS_EVALUATED} assertions PASSED"
    echo "═══════════════════════════════════════════════════════════════════════════════"
    exit 0
else
    echo "  ✗ ITER-147 REGRESSION TEST: $((ITER147_TOTAL_ASSERTIONS_EVALUATED - ITER147_TOTAL_ASSERTIONS_FAILED))/${ITER147_TOTAL_ASSERTIONS_EVALUATED} assertions passed, ${ITER147_TOTAL_ASSERTIONS_FAILED} FAILED"
    echo "═══════════════════════════════════════════════════════════════════════════════"
    exit 1
fi
