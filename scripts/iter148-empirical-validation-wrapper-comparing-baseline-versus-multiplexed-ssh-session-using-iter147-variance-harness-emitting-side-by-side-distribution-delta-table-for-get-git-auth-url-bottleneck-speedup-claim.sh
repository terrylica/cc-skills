#!/usr/bin/env bash
# iter-148 empirical validation wrapper for the iter-146/147 SSH ControlMaster
# optimization claim. Runs the iter-147 variance harness in BOTH conditions
# back-to-back and emits a side-by-side distribution delta table proving (or
# disproving) that the `semantic-release:get-git-auth-url` speedup is real
# and not single-sample-variance.
#
# WHY THIS EXISTS:
#
#   Iter-146 documented the SSH ControlMaster optimization with a CONJECTURAL
#   "1.7s → ~100-200ms (10-15x speedup)" claim sourced from OpenSSH community
#   docs on warm-handshake reuse. Iter-147 shipped two opt-in paths
#   (~/.ssh/config-modifying setup script + env-var-scoped GIT_SSH_COMMAND)
#   targeting that bottleneck, but neither was empirically validated on this
#   actual machine, in this actual release pipeline, against this actual
#   semantic-release version.
#
#   Per the iter-147 single-sample-variance discipline, an unvalidated
#   optimization claim is a hypothesis. The variance harness only KILLS
#   the single-sample trap; it doesn't itself validate optimizations. This
#   iter-148 wrapper takes the next scientific step: it RUNS the harness
#   under both conditions and emits a structured BEFORE/AFTER comparison so
#   the speedup claim can be falsified or confirmed with distribution-level
#   data (p50, p95, stddev) rather than point estimates.
#
# WHAT IT DOES:
#
#   1. Verifies the iter-147 variance harness exists at its expected path.
#
#   2. Captures BASELINE distribution (N back-to-back dry-runs with NO
#      multiplexing). Default N=5 (tunable via the same
#      ITER147_VARIANCE_PROFILE_RUN_COUNT env var the harness already honors).
#
#   3. Sets up SSH ControlMaster: idempotently creates ~/.ssh/controlmasters/
#      with mode 0700, then PRE-WARMS the cached session by running a
#      no-op `ssh -T git@github.com` with the multiplexing directives.
#      Without pre-warming, run-1 of the AFTER cohort would pay the cold
#      handshake cost (the first connection establishes the cached session),
#      polluting the warm-distribution measurement.
#
#   4. Captures MULTIPLEXED distribution (N back-to-back dry-runs WITH
#      GIT_SSH_COMMAND set to the iter-146-pattern ControlMaster directives).
#
#   5. Parses the harness output from both captures and emits a side-by-side
#      delta table sorted by descending baseline-p50, showing for each
#      namespace: baseline p50/p95/stddev, multiplexed p50/p95/stddev,
#      absolute and percent delta. A verdict footer summarizes whether the
#      iter-146-claimed speedup holds at distribution level.
#
# USAGE:
#
#   scripts/iter148-empirical-validation-wrapper-comparing-baseline-versus-multiplexed-ssh-session-using-iter147-variance-harness-emitting-side-by-side-distribution-delta-table-for-get-git-auth-url-bottleneck-speedup-claim.sh
#
#   # With custom run count (same env var as iter-147):
#   ITER147_VARIANCE_PROFILE_RUN_COUNT=10 scripts/iter148-...sh
#
# DURATION: ~N × 26s × 2 conditions. For N=3 default, ~52s. For N=5, ~85s.
# For N=10, ~3 minutes. Set N high enough that p50 stabilizes but not so high
# that the operator gives up and reverts to single-sample comparisons.
#
# WORKING-DIRECTORY-CLEANLINESS GOTCHA (inherited from iter-147 harness):
#
#   The downstream `npx semantic-release --dry-run` invokes our preflight
#   gate which aborts on dirty working directory. When this happens,
#   downstream namespaces like `semantic-release:get-tags` will not appear
#   in either capture. The delta table will still render correctly (showing
#   only namespaces that did execute), but the cohort coverage will be
#   narrower. Commit or stash pending changes for full namespace coverage.

set -euo pipefail

ITER148_REPO_ROOT="${AUDIT_REPO_ROOT_OVERRIDE:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
cd "$ITER148_REPO_ROOT"

ITER148_VARIANCE_HARNESS_PYTHON_SCRIPT_RELATIVE_PATH="scripts/iter147-empirical-n-run-variance-characterization-harness-for-semantic-release-namespace-timings-via-iter144-parser-emitting-p50-p95-mean-stddev-min-max-range.py"
ITER148_VARIANCE_HARNESS_PYTHON_SCRIPT_ABSOLUTE_PATH="$ITER148_REPO_ROOT/$ITER148_VARIANCE_HARNESS_PYTHON_SCRIPT_RELATIVE_PATH"
ITER148_SSH_CONTROLMASTERS_DIR_FOR_CACHED_SESSION_SOCKETS="$HOME/.ssh/controlmasters"
ITER148_SSH_CONTROLPERSIST_TTL_DURATION="10m"
ITER148_BASELINE_HARNESS_OUTPUT_LOG_PATH="/tmp/iter148-baseline-harness-output-$$.log"
ITER148_MULTIPLEXED_HARNESS_OUTPUT_LOG_PATH="/tmp/iter148-multiplexed-harness-output-$$.log"

iter148_verify_iter147_variance_harness_dependency_exists_or_abort() {
    if [[ ! -x "$ITER148_VARIANCE_HARNESS_PYTHON_SCRIPT_ABSOLUTE_PATH" ]]; then
        echo "  ✗ iter-147 variance harness not found or not executable at:" >&2
        echo "    $ITER148_VARIANCE_HARNESS_PYTHON_SCRIPT_ABSOLUTE_PATH" >&2
        exit 2
    fi
}

iter148_setup_ssh_controlmasters_directory_with_owner_only_permissions_if_absent() {
    mkdir -p "$ITER148_SSH_CONTROLMASTERS_DIR_FOR_CACHED_SESSION_SOCKETS"
    chmod 700 "$ITER148_SSH_CONTROLMASTERS_DIR_FOR_CACHED_SESSION_SOCKETS"
}

iter148_compose_git_ssh_command_string_with_controlmaster_auto_directives() {
    echo "ssh -o ControlMaster=auto -o ControlPath=$ITER148_SSH_CONTROLMASTERS_DIR_FOR_CACHED_SESSION_SOCKETS/%r@%h:%p -o ControlPersist=$ITER148_SSH_CONTROLPERSIST_TTL_DURATION"
}

iter148_prewarm_ssh_controlmaster_session_to_github_com_so_first_after_run_does_not_pay_cold_handshake_cost() {
    echo "  → Pre-warming SSH ControlMaster session to github.com (10-second budget)..."
    timeout 10 ssh \
        -o ControlMaster=auto \
        -o ControlPath="$ITER148_SSH_CONTROLMASTERS_DIR_FOR_CACHED_SESSION_SOCKETS/%r@%h:%p" \
        -o ControlPersist="$ITER148_SSH_CONTROLPERSIST_TTL_DURATION" \
        -o BatchMode=yes \
        -T git@github.com 2>&1 | head -1 || true
    if [[ -S "$ITER148_SSH_CONTROLMASTERS_DIR_FOR_CACHED_SESSION_SOCKETS/git@github.com:22" ]]; then
        echo "  ✓ Cached session socket created: git@github.com:22"
    else
        echo "  ⚠ No cached session socket found after pre-warm — multiplexing may not activate"
    fi
}

iter148_invoke_iter147_variance_harness_under_specified_environment_redirecting_output_to_capture_log() {
    local human_readable_condition_label_for_log_banner="$1"
    local output_capture_log_path="$2"
    local optional_git_ssh_command_value_to_export_for_this_invocation="${3:-}"

    echo ""
    echo "═══════════════════════════════════════════════════════════════════════════════"
    echo "  ITER-148 condition: ${human_readable_condition_label_for_log_banner}"
    echo "═══════════════════════════════════════════════════════════════════════════════"

    if [[ -n "$optional_git_ssh_command_value_to_export_for_this_invocation" ]]; then
        GIT_SSH_COMMAND="$optional_git_ssh_command_value_to_export_for_this_invocation" \
            python3 "$ITER148_VARIANCE_HARNESS_PYTHON_SCRIPT_ABSOLUTE_PATH" 2>&1 \
            | tee "$output_capture_log_path"
    else
        # Explicitly unset any inherited GIT_SSH_COMMAND so the baseline truly
        # measures the no-multiplexing path.
        env -u GIT_SSH_COMMAND \
            python3 "$ITER148_VARIANCE_HARNESS_PYTHON_SCRIPT_ABSOLUTE_PATH" 2>&1 \
            | tee "$output_capture_log_path"
    fi
}

iter148_extract_per_namespace_row_dictionary_from_harness_output_log_file_using_awk() {
    # Parses the iter-147 harness table rows (lines starting with two spaces
    # then a non-dash word character — the dimension-1 namespace rows) and
    # emits TSV: namespace<TAB>p50<TAB>p95<TAB>stddev for downstream join.
    local harness_output_log_path_to_extract_from="$1"
    awk '
        /^  semantic-release:/ {
            # Columns: namespace p50 p95 mean stddev min max range [flag...]
            printf "%s\t%s\t%s\t%s\n", $1, $2, $3, $5
        }
    ' "$harness_output_log_path_to_extract_from"
}

iter148_render_side_by_side_baseline_versus_multiplexed_distribution_delta_table() {
    echo ""
    echo "═══════════════════════════════════════════════════════════════════════════════"
    echo "  ITER-148 BASELINE-VS-MULTIPLEXED DISTRIBUTION DELTA"
    echo "  (BEFORE = no SSH multiplexing; AFTER = GIT_SSH_COMMAND with ControlMaster=auto)"
    echo "═══════════════════════════════════════════════════════════════════════════════"
    echo ""

    local baseline_tsv_path_for_per_namespace_p50_p95_stddev_rows="/tmp/iter148-baseline-rows-$$.tsv"
    local multiplexed_tsv_path_for_per_namespace_p50_p95_stddev_rows="/tmp/iter148-multiplexed-rows-$$.tsv"

    iter148_extract_per_namespace_row_dictionary_from_harness_output_log_file_using_awk \
        "$ITER148_BASELINE_HARNESS_OUTPUT_LOG_PATH" > "$baseline_tsv_path_for_per_namespace_p50_p95_stddev_rows"
    iter148_extract_per_namespace_row_dictionary_from_harness_output_log_file_using_awk \
        "$ITER148_MULTIPLEXED_HARNESS_OUTPUT_LOG_PATH" > "$multiplexed_tsv_path_for_per_namespace_p50_p95_stddev_rows"

    printf "  %-42s %8s %8s %8s   %8s %8s %8s   %10s %8s\n" \
        "namespace" "BEFORE-p50" "p95" "stddev" "AFTER-p50" "p95" "stddev" "Δp50" "speedup"
    printf "  %-42s %8s %8s %8s   %8s %8s %8s   %10s %8s\n" \
        "$(printf '%0.s-' {1..42})" "----------" "--------" "--------" "---------" "--------" "--------" "----------" "--------"

    # Join the two TSVs on namespace (column 1). For each namespace present in
    # baseline, look up its multiplexed row and compute delta.
    while IFS=$'\t' read -r namespace_for_row baseline_p50_for_row baseline_p95_for_row baseline_stddev_for_row; do
        local multiplexed_row_lookup_result
        multiplexed_row_lookup_result=$(awk -F'\t' -v ns="$namespace_for_row" \
            '$1 == ns { print $2 "\t" $3 "\t" $4 }' \
            "$multiplexed_tsv_path_for_per_namespace_p50_p95_stddev_rows")
        if [[ -z "$multiplexed_row_lookup_result" ]]; then
            printf "  %-42s %8s %8s %8s   %8s %8s %8s   %10s %8s\n" \
                "$namespace_for_row" "$baseline_p50_for_row" "$baseline_p95_for_row" "$baseline_stddev_for_row" \
                "—" "—" "—" "n/a" "—"
            continue
        fi
        local multiplexed_p50_for_row multiplexed_p95_for_row multiplexed_stddev_for_row
        IFS=$'\t' read -r multiplexed_p50_for_row multiplexed_p95_for_row multiplexed_stddev_for_row \
            <<< "$multiplexed_row_lookup_result"

        local delta_p50_milliseconds_signed_for_this_namespace_row
        delta_p50_milliseconds_signed_for_this_namespace_row=$((multiplexed_p50_for_row - baseline_p50_for_row))
        local speedup_ratio_baseline_over_multiplexed_for_this_namespace_row="—"
        if [[ "$multiplexed_p50_for_row" -gt 0 ]]; then
            speedup_ratio_baseline_over_multiplexed_for_this_namespace_row=$(
                awk -v b="$baseline_p50_for_row" -v m="$multiplexed_p50_for_row" \
                    'BEGIN { printf "%.2fx", b / m }'
            )
        fi

        printf "  %-42s %8s %8s %8s   %8s %8s %8s   %10s %8s\n" \
            "$namespace_for_row" \
            "$baseline_p50_for_row" "$baseline_p95_for_row" "$baseline_stddev_for_row" \
            "$multiplexed_p50_for_row" "$multiplexed_p95_for_row" "$multiplexed_stddev_for_row" \
            "$delta_p50_milliseconds_signed_for_this_namespace_row" \
            "$speedup_ratio_baseline_over_multiplexed_for_this_namespace_row"
    done < <(sort -t$'\t' -k2,2 -rn "$baseline_tsv_path_for_per_namespace_p50_p95_stddev_rows")

    rm -f "$baseline_tsv_path_for_per_namespace_p50_p95_stddev_rows" \
          "$multiplexed_tsv_path_for_per_namespace_p50_p95_stddev_rows"

    echo ""
    echo "  ⧗ Δp50 = (multiplexed p50) - (baseline p50). Negative = multiplexing faster."
    echo "  ⧗ speedup = (baseline p50) / (multiplexed p50). > 1.0x = multiplexing faster."
    echo "  ⧗ If get-git-auth-url speedup is ≥ 2.0x, iter-146/147 SSH multiplexing claim is VALIDATED."
    echo "  ⧗ If close to 1.0x, the claim does NOT hold on this machine — investigate."
}

iter148_main_entry_point_orchestrates_baseline_then_multiplexed_capture_then_delta_render() {
    echo ""
    echo "═══════════════════════════════════════════════════════════════════════════════"
    echo "  ITER-148 EMPIRICAL VALIDATION OF ITER-146/147 SSH MULTIPLEXING CLAIM"
    echo "  Two back-to-back captures via iter-147 variance harness, then delta render."
    echo "═══════════════════════════════════════════════════════════════════════════════"

    iter148_verify_iter147_variance_harness_dependency_exists_or_abort

    # CONDITION A: baseline (no SSH multiplexing)
    iter148_invoke_iter147_variance_harness_under_specified_environment_redirecting_output_to_capture_log \
        "BASELINE (no SSH multiplexing)" \
        "$ITER148_BASELINE_HARNESS_OUTPUT_LOG_PATH" \
        ""

    # SETUP between conditions: ensure ~/.ssh/controlmasters/ + pre-warm session
    iter148_setup_ssh_controlmasters_directory_with_owner_only_permissions_if_absent
    iter148_prewarm_ssh_controlmaster_session_to_github_com_so_first_after_run_does_not_pay_cold_handshake_cost

    # CONDITION B: multiplexed (GIT_SSH_COMMAND with ControlMaster directives)
    local git_ssh_command_string_with_iter146_pattern_controlmaster_directives
    git_ssh_command_string_with_iter146_pattern_controlmaster_directives=$(
        iter148_compose_git_ssh_command_string_with_controlmaster_auto_directives
    )
    iter148_invoke_iter147_variance_harness_under_specified_environment_redirecting_output_to_capture_log \
        "MULTIPLEXED (GIT_SSH_COMMAND with ControlMaster=auto + ControlPersist=10m)" \
        "$ITER148_MULTIPLEXED_HARNESS_OUTPUT_LOG_PATH" \
        "$git_ssh_command_string_with_iter146_pattern_controlmaster_directives"

    iter148_render_side_by_side_baseline_versus_multiplexed_distribution_delta_table

    # Preserve the capture logs for operator inspection — these are valuable
    # forensic artifacts and small enough to keep in /tmp.
    echo ""
    echo "  ⧗ Capture logs preserved for inspection:"
    echo "    BASELINE:    $ITER148_BASELINE_HARNESS_OUTPUT_LOG_PATH"
    echo "    MULTIPLEXED: $ITER148_MULTIPLEXED_HARNESS_OUTPUT_LOG_PATH"
}

iter148_main_entry_point_orchestrates_baseline_then_multiplexed_capture_then_delta_render
