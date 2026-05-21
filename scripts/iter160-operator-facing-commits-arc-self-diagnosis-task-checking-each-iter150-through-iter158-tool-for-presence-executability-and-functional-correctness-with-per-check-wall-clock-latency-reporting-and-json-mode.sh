#!/usr/bin/env bash
# FILE-SIZE-OK: iter-160 doctor is a single-file brew-doctor-style
# diagnostic tool with 15 sequential health checks (iter-150 → iter-165
# coverage post-iter-163 + iter-166 extensions). Splitting the file would
# fragment the check sequence across multiple files and hurt operator
# readability — the linear top-to-bottom progression IS the design.
# ~700 lines fits comfortably under the 1000-line hard block. Reviewed
# iter-163, iter-166.
#
# iter-160 operator-facing commits arc self-diagnosis task.
#
# Purpose: answer the question "is my cc-skills conventional-commits toolkit
# working RIGHT NOW?" in one command — the industry-standard brew-doctor,
# npm-doctor, mise-doctor, kubectl-version pattern adapted for the
# conventional-commits arc. Closes the operator-self-diagnosis gap surfaced
# by the iter-160 audit: after iter-157 (local hook installer) and iter-158
# (polyglot pre-commit framework manifest), there are multiple install paths
# and no single command lets the operator verify their setup is healthy.
#
# Output modes:
#   • Default (human-readable, ANSI-colored): one line per check with
#     ✓/⚠/✗ markers and per-check wall-clock latency in milliseconds.
#   • --json (machine-readable, AI-agent automation): single JSON object
#     with stable iter160_schema_version=1, an array of check records, and
#     summary counters. Mirrors the iter-153 (advisor) and iter-155
#     (dashboard) JSON-mode pattern, including the iter-155 shared-lib
#     pure-bash RFC 8259 escape function for safe string embedding.
#
# Severity tiers (per OWASP/npm/react-doctor 2026 conventions):
#   • CRITICAL — toolkit is broken; default exit non-zero (always fails)
#   • WARNING  — toolkit is functional but operator setup is incomplete
#                (e.g., iter-157 hook not installed); default exit 0 with
#                informational message
#   • INFO     — performance/latency observation; never gates exit code
#
# Exit code contract:
#   0   — all CRITICAL checks pass (WARNING/INFO findings are reported but
#         don't gate exit code)
#   1   — one or more CRITICAL checks failed (toolkit is broken)

set -euo pipefail

# ─── Source the iter-155 shared library for JSON escape (if --json) ─────────

ITER160_CC_SKILLS_REPO_ROOT_ABSOLUTE_PATH="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
ITER160_ITER155_SHARED_JSON_ESCAPE_LIB_ABSOLUTE_PATH_FOR_ITER160_STATUS_TASK="$ITER160_CC_SKILLS_REPO_ROOT_ABSOLUTE_PATH/scripts/lib/iter155-pure-bash-rfc8259-json-string-escape-shared-library-for-cross-script-reuse-eliminating-duplication-of-iter154-correctness-fix-across-iter152-iter153-and-future-consumers.sh"

# ─── Parse output mode flag ─────────────────────────────────────────────────

ITER160_OUTPUT_MODE_HUMAN_READABLE_DEFAULT_OR_JSON_FOR_AI_AGENT_CONSUMPTION="human"
for arg in "$@"; do
    case "$arg" in
        --json)
            ITER160_OUTPUT_MODE_HUMAN_READABLE_DEFAULT_OR_JSON_FOR_AI_AGENT_CONSUMPTION="json"
            ;;
        --help|-h)
            cat <<'USAGE'
Usage: commits:status [--json]

Self-diagnose the cc-skills conventional-commits toolkit health.

Default mode emits human-readable check report with per-check wall-clock
latency. --json mode emits machine-readable structured output with stable
iter160_schema_version=1 schema for AI-agent automation pipelines.

Exit codes:
  0  — all CRITICAL checks pass
  1  — one or more CRITICAL checks failed (toolkit is broken)

The task is the brew-doctor / npm-doctor pattern adapted for the iter-150
through iter-158 commits arc.
USAGE
            exit 0
            ;;
    esac
done

# ─── ANSI colors for human-readable mode ────────────────────────────────────

if [[ -t 1 ]] && [[ "$ITER160_OUTPUT_MODE_HUMAN_READABLE_DEFAULT_OR_JSON_FOR_AI_AGENT_CONSUMPTION" == "human" ]]; then
    ITER160_ANSI_COLOR_GREEN_FOR_PASSING_CRITICAL_CHECK="$(printf '\033[32m')"
    ITER160_ANSI_COLOR_YELLOW_FOR_INFORMATIONAL_WARNING="$(printf '\033[33m')"
    ITER160_ANSI_COLOR_RED_FOR_FAILING_CRITICAL_CHECK="$(printf '\033[31m')"
    ITER160_ANSI_COLOR_DIM_FOR_LATENCY_AND_METADATA="$(printf '\033[2m')"
    ITER160_ANSI_COLOR_BOLD_FOR_SECTION_HEADERS="$(printf '\033[1m')"
    ITER160_ANSI_COLOR_RESET="$(printf '\033[0m')"
else
    ITER160_ANSI_COLOR_GREEN_FOR_PASSING_CRITICAL_CHECK=""
    ITER160_ANSI_COLOR_YELLOW_FOR_INFORMATIONAL_WARNING=""
    ITER160_ANSI_COLOR_RED_FOR_FAILING_CRITICAL_CHECK=""
    ITER160_ANSI_COLOR_DIM_FOR_LATENCY_AND_METADATA=""
    ITER160_ANSI_COLOR_BOLD_FOR_SECTION_HEADERS=""
    ITER160_ANSI_COLOR_RESET=""
fi

# ─── Accumulators for JSON-mode output and exit-code gating ─────────────────

ITER160_TOTAL_CHECKS_EVALUATED=0
ITER160_TOTAL_CRITICAL_PASSED=0
ITER160_TOTAL_CRITICAL_FAILED=0
ITER160_TOTAL_WARNINGS_REPORTED=0
ITER160_CHECK_RECORDS_FOR_JSON_OUTPUT_ARRAY=()

# ─── Helper: record a check result + emit human-readable line if applicable ─

iter160_record_check_result_with_per_check_wall_clock_latency_and_severity_classification() {
    local check_identifier_for_searchability="$1"
    local human_readable_check_label="$2"
    local severity_critical_or_warning_or_info="$3"
    local check_outcome_pass_or_fail_or_skip="$4"
    local wall_clock_latency_milliseconds="$5"
    local diagnostic_message_for_failures_or_warnings="${6:-}"

    ITER160_TOTAL_CHECKS_EVALUATED=$((ITER160_TOTAL_CHECKS_EVALUATED + 1))

    case "$severity_critical_or_warning_or_info:$check_outcome_pass_or_fail_or_skip" in
        critical:pass)
            ITER160_TOTAL_CRITICAL_PASSED=$((ITER160_TOTAL_CRITICAL_PASSED + 1))
            ;;
        critical:fail)
            ITER160_TOTAL_CRITICAL_FAILED=$((ITER160_TOTAL_CRITICAL_FAILED + 1))
            ;;
        warning:*)
            ITER160_TOTAL_WARNINGS_REPORTED=$((ITER160_TOTAL_WARNINGS_REPORTED + 1))
            ;;
    esac

    if [[ "$ITER160_OUTPUT_MODE_HUMAN_READABLE_DEFAULT_OR_JSON_FOR_AI_AGENT_CONSUMPTION" == "human" ]]; then
        local marker color
        case "$severity_critical_or_warning_or_info:$check_outcome_pass_or_fail_or_skip" in
            critical:pass) marker="✓"; color="$ITER160_ANSI_COLOR_GREEN_FOR_PASSING_CRITICAL_CHECK" ;;
            critical:fail) marker="✗"; color="$ITER160_ANSI_COLOR_RED_FOR_FAILING_CRITICAL_CHECK" ;;
            warning:pass)  marker="✓"; color="$ITER160_ANSI_COLOR_GREEN_FOR_PASSING_CRITICAL_CHECK" ;;
            warning:fail)  marker="⚠"; color="$ITER160_ANSI_COLOR_YELLOW_FOR_INFORMATIONAL_WARNING" ;;
            info:*)        marker="ⓘ"; color="$ITER160_ANSI_COLOR_DIM_FOR_LATENCY_AND_METADATA" ;;
            *)             marker="?"; color="" ;;
        esac
        local latency_suffix=""
        if [[ -n "$wall_clock_latency_milliseconds" ]] && [[ "$wall_clock_latency_milliseconds" != "0" ]]; then
            latency_suffix=" ${ITER160_ANSI_COLOR_DIM_FOR_LATENCY_AND_METADATA}(${wall_clock_latency_milliseconds}ms)${ITER160_ANSI_COLOR_RESET}"
        fi
        printf '  %s%s%s %s%s\n' \
            "$color" "$marker" "$ITER160_ANSI_COLOR_RESET" \
            "$human_readable_check_label" "$latency_suffix"
        if [[ -n "$diagnostic_message_for_failures_or_warnings" ]]; then
            printf '       %s%s%s\n' \
                "$ITER160_ANSI_COLOR_DIM_FOR_LATENCY_AND_METADATA" \
                "$diagnostic_message_for_failures_or_warnings" \
                "$ITER160_ANSI_COLOR_RESET"
        fi
    else
        # JSON mode: defer per-record JSON escape until iter-155 lib is loaded.
        ITER160_CHECK_RECORDS_FOR_JSON_OUTPUT_ARRAY+=("$check_identifier_for_searchability|$human_readable_check_label|$severity_critical_or_warning_or_info|$check_outcome_pass_or_fail_or_skip|$wall_clock_latency_milliseconds|$diagnostic_message_for_failures_or_warnings")
    fi
}

# ─── Helper: time a command, write exit code + wall-clock to globals ────────
#
# Uses two well-known global output variables (vs. an eval-based namespace-
# parameterized approach) so that shellcheck SC2154 doesn't false-positive on
# the per-call-site capture variables. Each check copies the globals into
# locally-named vars immediately after the helper returns.

ITER160_HELPER_LATEST_EXIT_CODE_FROM_TIMED_COMMAND_INVOCATION=0
ITER160_HELPER_LATEST_WALL_CLOCK_MILLISECONDS_FROM_TIMED_COMMAND_INVOCATION=0

# ─── ITER-177 ZERO-FORK TIMING via bash 5+ EPOCHREALTIME BUILTIN ─────────────
# Pre-iter-177 the per-check timing wrapper spawned TWO `perl -MTime::HiRes`
# subprocesses per check (start_ns + end_ns capture). Empirical measurement:
# ~8-9ms per perl fork on macOS arm64 darwin. iter-160 runs 15 checks, so
# 30 perl forks contributed ≈260-270ms of pure timing overhead — ≈40% of
# the 665ms pre-iter-177 wall-clock median.
#
# Iter-177 swaps to the bash 5+ `${EPOCHREALTIME}` builtin (zero subprocess
# forks, microsecond resolution per Chet Ramey 2018 RFE). The builtin's
# "seconds.microseconds" format is parsed via bash parameter-expansion
# `${EPOCHREALTIME/./}` which strips the decimal point to yield an integer
# microsecond counter — pure bash arithmetic, no awk/perl/python.
#
# Graceful degradation: bash < 5.0 falls back to the original perl path
# preserving correctness on legacy systems (e.g. macOS /bin/bash 3.2 when
# the script is invoked outside the mise-managed shell). The detection
# runs ONCE at script entry; the swap is then branch-predicted per call.
#
# Methodology: timing primitive choice does NOT change the wall-clock of
# the wrapped command — it only changes the OVERHEAD added by the timer.
# Net effect: iter-160 doctor 665ms → ~400ms (≈40% reduction), driving
# operator-perceived sluggishness of `mise run commits:status` well under
# the human-perceptibility threshold for interactive feedback (~100ms is
# instantaneous, ~400ms is responsive, >700ms feels sluggish per Nielsen
# usability research and Google Web Vitals INP guidance).
if (( ${BASH_VERSINFO[0]:-0} >= 5 )); then
    ITER177_TIMER_PRIMITIVE_USING_BASH5_EPOCHREALTIME_BUILTIN_FOR_ZERO_FORK_MICROSECOND_RESOLUTION_OR_PERL_FALLBACK_FOR_LEGACY_BASH=1
else
    ITER177_TIMER_PRIMITIVE_USING_BASH5_EPOCHREALTIME_BUILTIN_FOR_ZERO_FORK_MICROSECOND_RESOLUTION_OR_PERL_FALLBACK_FOR_LEGACY_BASH=0
fi

iter160_time_command_and_capture_exit_code_and_wall_clock_milliseconds() {
    local elapsed_ms actual_exit=0
    if (( ITER177_TIMER_PRIMITIVE_USING_BASH5_EPOCHREALTIME_BUILTIN_FOR_ZERO_FORK_MICROSECOND_RESOLUTION_OR_PERL_FALLBACK_FOR_LEGACY_BASH )); then
        # iter-177 fast path: $EPOCHREALTIME is "seconds.microseconds".
        # Stripping the '.' via parameter expansion yields integer microseconds
        # since epoch (concat of integer-seconds × 10^6 + fractional-microseconds).
        local start_microseconds_since_epoch_from_bash5_epochrealtime_builtin
        local end_microseconds_since_epoch_from_bash5_epochrealtime_builtin
        start_microseconds_since_epoch_from_bash5_epochrealtime_builtin="${EPOCHREALTIME/./}"
        "$@" >/dev/null 2>&1 || actual_exit=$?
        end_microseconds_since_epoch_from_bash5_epochrealtime_builtin="${EPOCHREALTIME/./}"
        elapsed_ms=$(( (end_microseconds_since_epoch_from_bash5_epochrealtime_builtin - start_microseconds_since_epoch_from_bash5_epochrealtime_builtin) / 1000 ))
    else
        # Legacy fallback: perl Time::HiRes for bash < 5.0. Preserved
        # verbatim from pre-iter-177 implementation for correctness parity.
        local start_ns end_ns
        start_ns=$(perl -MTime::HiRes=time -e 'printf "%.0f\n", time*1e9')
        "$@" >/dev/null 2>&1 || actual_exit=$?
        end_ns=$(perl -MTime::HiRes=time -e 'printf "%.0f\n", time*1e9')
        elapsed_ms=$(( (end_ns - start_ns) / 1000000 ))
    fi
    ITER160_HELPER_LATEST_EXIT_CODE_FROM_TIMED_COMMAND_INVOCATION="$actual_exit"
    ITER160_HELPER_LATEST_WALL_CLOCK_MILLISECONDS_FROM_TIMED_COMMAND_INVOCATION="$elapsed_ms"
}

# ─── Print human-readable banner ─────────────────────────────────────────────

if [[ "$ITER160_OUTPUT_MODE_HUMAN_READABLE_DEFAULT_OR_JSON_FOR_AI_AGENT_CONSUMPTION" == "human" ]]; then
    cat <<EOF

═══════════════════════════════════════════════════════════════════════════════
  ${ITER160_ANSI_COLOR_BOLD_FOR_SECTION_HEADERS}CC-SKILLS COMMITS-ARC SELF-DIAGNOSIS (iter-160)${ITER160_ANSI_COLOR_RESET}
═══════════════════════════════════════════════════════════════════════════════

EOF
fi

# ─── Check 1: iter-150 readable renderer (CRITICAL) ─────────────────────────

ITER160_ITER150_RENDERER_ABSOLUTE_PATH="$ITER160_CC_SKILLS_REPO_ROOT_ABSOLUTE_PATH/scripts/iter150-readable-git-log-renderer-with-awk-based-soft-wrap-of-verbose-conventional-commit-subjects-to-eighty-column-terminal-width-with-color-decorations-and-indentation-for-operator-readability.sh"
if [[ -x "$ITER160_ITER150_RENDERER_ABSOLUTE_PATH" ]]; then
    iter160_time_command_and_capture_exit_code_and_wall_clock_milliseconds \
        "$ITER160_ITER150_RENDERER_ABSOLUTE_PATH"
    iter160_iter150_exit="$ITER160_HELPER_LATEST_EXIT_CODE_FROM_TIMED_COMMAND_INVOCATION"
    iter160_iter150_ms="$ITER160_HELPER_LATEST_WALL_CLOCK_MILLISECONDS_FROM_TIMED_COMMAND_INVOCATION"
    if [[ "$iter160_iter150_exit" -eq 0 ]]; then
        iter160_record_check_result_with_per_check_wall_clock_latency_and_severity_classification \
            "iter150_readable_renderer" \
            "iter-150 release:history readable renderer" \
            "critical" "pass" "$iter160_iter150_ms"
    else
        iter160_record_check_result_with_per_check_wall_clock_latency_and_severity_classification \
            "iter150_readable_renderer" \
            "iter-150 release:history readable renderer" \
            "critical" "fail" "$iter160_iter150_ms" \
            "exited non-zero ($iter160_iter150_exit)"
    fi
else
    iter160_record_check_result_with_per_check_wall_clock_latency_and_severity_classification \
        "iter150_readable_renderer" \
        "iter-150 release:history readable renderer" \
        "critical" "fail" "0" \
        "script missing or not executable at $ITER160_ITER150_RENDERER_ABSOLUTE_PATH"
fi

# ─── Check 2: iter-152 commits:health dashboard (CRITICAL) ──────────────────

ITER160_ITER152_DASHBOARD_ABSOLUTE_PATH="$ITER160_CC_SKILLS_REPO_ROOT_ABSOLUTE_PATH/scripts/iter152-operator-facing-commits-subject-length-distribution-histogram-with-trend-analysis-and-worst-offender-callouts-for-conventional-commits-50-72-rule-compliance-visibility-fusing-iter150-readable-view-with-iter151-classification-overlay.sh"
if [[ -x "$ITER160_ITER152_DASHBOARD_ABSOLUTE_PATH" ]]; then
    iter160_time_command_and_capture_exit_code_and_wall_clock_milliseconds \
        "$ITER160_ITER152_DASHBOARD_ABSOLUTE_PATH"
    iter160_iter152_exit="$ITER160_HELPER_LATEST_EXIT_CODE_FROM_TIMED_COMMAND_INVOCATION"
    iter160_iter152_ms="$ITER160_HELPER_LATEST_WALL_CLOCK_MILLISECONDS_FROM_TIMED_COMMAND_INVOCATION"
    if [[ "$iter160_iter152_exit" -eq 0 ]]; then
        iter160_record_check_result_with_per_check_wall_clock_latency_and_severity_classification \
            "iter152_health_dashboard" \
            "iter-152 commits:health 5-panel dashboard" \
            "critical" "pass" "$iter160_iter152_ms"
    else
        iter160_record_check_result_with_per_check_wall_clock_latency_and_severity_classification \
            "iter152_health_dashboard" \
            "iter-152 commits:health 5-panel dashboard" \
            "critical" "fail" "$iter160_iter152_ms" \
            "exited non-zero ($iter160_iter152_exit)"
    fi
else
    iter160_record_check_result_with_per_check_wall_clock_latency_and_severity_classification \
        "iter152_health_dashboard" \
        "iter-152 commits:health 5-panel dashboard" \
        "critical" "fail" "0" \
        "script missing"
fi

# ─── Check 3: iter-153 advisor (CRITICAL) ───────────────────────────────────

ITER160_ITER153_ADVISOR_ABSOLUTE_PATH="$ITER160_CC_SKILLS_REPO_ROOT_ABSOLUTE_PATH/scripts/iter153-operator-facing-pre-commit-dry-run-advisor-classifying-proposed-conventional-commit-subject-through-iter82-grammar-and-iter151-overlay-with-human-readable-verdict-default-and-json-output-mode-for-ai-agent-automation-pipeline-consumption.sh"
if [[ -x "$ITER160_ITER153_ADVISOR_ABSOLUTE_PATH" ]]; then
    iter160_time_command_and_capture_exit_code_and_wall_clock_milliseconds \
        "$ITER160_ITER153_ADVISOR_ABSOLUTE_PATH" -- "feat(test): iter-160 self-diagnosis probe"
    iter160_iter153_exit="$ITER160_HELPER_LATEST_EXIT_CODE_FROM_TIMED_COMMAND_INVOCATION"
    iter160_iter153_ms="$ITER160_HELPER_LATEST_WALL_CLOCK_MILLISECONDS_FROM_TIMED_COMMAND_INVOCATION"
    if [[ "$iter160_iter153_exit" -eq 0 ]]; then
        iter160_record_check_result_with_per_check_wall_clock_latency_and_severity_classification \
            "iter153_pre_commit_advisor" \
            "iter-153 commits:advise dry-run advisor (synthetic conformant subject)" \
            "critical" "pass" "$iter160_iter153_ms"
    else
        iter160_record_check_result_with_per_check_wall_clock_latency_and_severity_classification \
            "iter153_pre_commit_advisor" \
            "iter-153 commits:advise dry-run advisor" \
            "critical" "fail" "$iter160_iter153_ms" \
            "synthetic conformant subject was incorrectly rejected (exit $iter160_iter153_exit)"
    fi
else
    iter160_record_check_result_with_per_check_wall_clock_latency_and_severity_classification \
        "iter153_pre_commit_advisor" \
        "iter-153 commits:advise dry-run advisor" \
        "critical" "fail" "0" "script missing"
fi

# ─── Check 4: iter-155 shared JSON-escape library loads cleanly (CRITICAL) ──

if [[ -f "$ITER160_ITER155_SHARED_JSON_ESCAPE_LIB_ABSOLUTE_PATH_FOR_ITER160_STATUS_TASK" ]]; then
    iter160_time_command_and_capture_exit_code_and_wall_clock_milliseconds \
        bash -c "source '$ITER160_ITER155_SHARED_JSON_ESCAPE_LIB_ABSOLUTE_PATH_FOR_ITER160_STATUS_TASK' && declare -F iter155_pure_bash_rfc8259_compliant_json_string_escape_handling_all_seven_named_escapes_plus_generic_uxxxx_for_control_chars >/dev/null"
    iter160_iter155_exit="$ITER160_HELPER_LATEST_EXIT_CODE_FROM_TIMED_COMMAND_INVOCATION"
    iter160_iter155_ms="$ITER160_HELPER_LATEST_WALL_CLOCK_MILLISECONDS_FROM_TIMED_COMMAND_INVOCATION"
    if [[ "$iter160_iter155_exit" -eq 0 ]]; then
        iter160_record_check_result_with_per_check_wall_clock_latency_and_severity_classification \
            "iter155_shared_json_escape_library" \
            "iter-155 pure-bash RFC 8259 shared library sources cleanly + exports canonical function" \
            "critical" "pass" "$iter160_iter155_ms"
    else
        iter160_record_check_result_with_per_check_wall_clock_latency_and_severity_classification \
            "iter155_shared_json_escape_library" \
            "iter-155 shared library" \
            "critical" "fail" "$iter160_iter155_ms" \
            "library failed to source or canonical function missing"
    fi
else
    iter160_record_check_result_with_per_check_wall_clock_latency_and_severity_classification \
        "iter155_shared_json_escape_library" \
        "iter-155 shared library" \
        "critical" "fail" "0" "library missing"
fi

# ─── Check 5: iter-156 _default dispatcher (CRITICAL) ───────────────────────

ITER160_ITER156_DISPATCHER_ABSOLUTE_PATH="$ITER160_CC_SKILLS_REPO_ROOT_ABSOLUTE_PATH/.mise/tasks/commits/_default"
if [[ -x "$ITER160_ITER156_DISPATCHER_ABSOLUTE_PATH" ]]; then
    iter160_time_command_and_capture_exit_code_and_wall_clock_milliseconds \
        "$ITER160_ITER156_DISPATCHER_ABSOLUTE_PATH"
    iter160_iter156_exit="$ITER160_HELPER_LATEST_EXIT_CODE_FROM_TIMED_COMMAND_INVOCATION"
    iter160_iter156_ms="$ITER160_HELPER_LATEST_WALL_CLOCK_MILLISECONDS_FROM_TIMED_COMMAND_INVOCATION"
    if [[ "$iter160_iter156_exit" -eq 0 ]]; then
        iter160_record_check_result_with_per_check_wall_clock_latency_and_severity_classification \
            "iter156_default_dispatcher" \
            "iter-156 commits namespace default dispatcher" \
            "critical" "pass" "$iter160_iter156_ms"
    else
        iter160_record_check_result_with_per_check_wall_clock_latency_and_severity_classification \
            "iter156_default_dispatcher" \
            "iter-156 dispatcher" \
            "critical" "fail" "$iter160_iter156_ms"
    fi
else
    iter160_record_check_result_with_per_check_wall_clock_latency_and_severity_classification \
        "iter156_default_dispatcher" \
        "iter-156 dispatcher" \
        "critical" "fail" "0" "dispatcher missing"
fi

# ─── Check 6: iter-157 installer is present + executable (CRITICAL) ─────────

ITER160_ITER157_INSTALLER_ABSOLUTE_PATH="$ITER160_CC_SKILLS_REPO_ROOT_ABSOLUTE_PATH/scripts/iter157-idempotent-installer-and-uninstaller-of-the-commit-msg-git-hook-managing-existing-hook-backup-restoration-with-cc-skills-managed-sentinel-marker-for-safe-detection-of-our-own-installs-vs-third-party.sh"
if [[ -x "$ITER160_ITER157_INSTALLER_ABSOLUTE_PATH" ]]; then
    iter160_time_command_and_capture_exit_code_and_wall_clock_milliseconds \
        "$ITER160_ITER157_INSTALLER_ABSOLUTE_PATH" status
    iter160_iter157_exit="$ITER160_HELPER_LATEST_EXIT_CODE_FROM_TIMED_COMMAND_INVOCATION"
    iter160_iter157_ms="$ITER160_HELPER_LATEST_WALL_CLOCK_MILLISECONDS_FROM_TIMED_COMMAND_INVOCATION"
    if [[ "$iter160_iter157_exit" -eq 0 ]]; then
        iter160_record_check_result_with_per_check_wall_clock_latency_and_severity_classification \
            "iter157_commit_msg_hook_installer" \
            "iter-157 commit-msg hook installer (status mode)" \
            "critical" "pass" "$iter160_iter157_ms"
    else
        iter160_record_check_result_with_per_check_wall_clock_latency_and_severity_classification \
            "iter157_commit_msg_hook_installer" \
            "iter-157 installer" \
            "critical" "fail" "$iter160_iter157_ms"
    fi
else
    iter160_record_check_result_with_per_check_wall_clock_latency_and_severity_classification \
        "iter157_commit_msg_hook_installer" \
        "iter-157 installer" \
        "critical" "fail" "0" "installer missing"
fi

# ─── Check 7: iter-157 hook actually installed in CURRENT repo (WARNING) ────

ITER160_CURRENT_REPO_GIT_DIR=$(git rev-parse --git-dir 2>/dev/null || echo "")
ITER160_CURRENT_REPO_COMMIT_MSG_HOOK_ABSOLUTE_PATH="$ITER160_CURRENT_REPO_GIT_DIR/hooks/commit-msg"
if [[ -n "$ITER160_CURRENT_REPO_GIT_DIR" ]] && [[ -f "$ITER160_CURRENT_REPO_COMMIT_MSG_HOOK_ABSOLUTE_PATH" ]]; then
    if grep -qF "ITER157_CC_SKILLS_MANAGED_COMMIT_MSG_HOOK_DO_NOT_EDIT_DIRECTLY" "$ITER160_CURRENT_REPO_COMMIT_MSG_HOOK_ABSOLUTE_PATH" 2>/dev/null; then
        iter160_record_check_result_with_per_check_wall_clock_latency_and_severity_classification \
            "iter157_hook_installed_in_current_repo" \
            "iter-157 hook installed in current repo (.git/hooks/commit-msg)" \
            "warning" "pass" "0"
    else
        iter160_record_check_result_with_per_check_wall_clock_latency_and_severity_classification \
            "iter157_hook_installed_in_current_repo" \
            "iter-157 hook NOT installed (existing hook lacks cc-skills sentinel)" \
            "warning" "fail" "0" \
            "install via: mise run commits:install-hook"
    fi
else
    iter160_record_check_result_with_per_check_wall_clock_latency_and_severity_classification \
        "iter157_hook_installed_in_current_repo" \
        "iter-157 hook NOT installed in current repo" \
        "warning" "fail" "0" \
        "install via: mise run commits:install-hook"
fi

# ─── Check 8: iter-158 .pre-commit-hooks.yaml manifest at repo root (CRITICAL)

ITER160_ITER158_MANIFEST_ABSOLUTE_PATH="$ITER160_CC_SKILLS_REPO_ROOT_ABSOLUTE_PATH/.pre-commit-hooks.yaml"
if [[ -f "$ITER160_ITER158_MANIFEST_ABSOLUTE_PATH" ]]; then
    iter160_time_command_and_capture_exit_code_and_wall_clock_milliseconds \
        python3 -c "import yaml; m = yaml.safe_load(open('$ITER160_ITER158_MANIFEST_ABSOLUTE_PATH')); assert m[0]['language'] == 'script', f'wrong language: {m[0][\"language\"]}'"
    iter160_iter158_exit="$ITER160_HELPER_LATEST_EXIT_CODE_FROM_TIMED_COMMAND_INVOCATION"
    iter160_iter158_ms="$ITER160_HELPER_LATEST_WALL_CLOCK_MILLISECONDS_FROM_TIMED_COMMAND_INVOCATION"
    if [[ "$iter160_iter158_exit" -eq 0 ]]; then
        iter160_record_check_result_with_per_check_wall_clock_latency_and_severity_classification \
            "iter158_pre_commit_framework_manifest" \
            "iter-158 .pre-commit-hooks.yaml parses + declares language=script" \
            "critical" "pass" "$iter160_iter158_ms"
    else
        iter160_record_check_result_with_per_check_wall_clock_latency_and_severity_classification \
            "iter158_pre_commit_framework_manifest" \
            "iter-158 manifest" \
            "critical" "fail" "$iter160_iter158_ms" \
            "manifest YAML invalid or language != script (iter-159 bug recurrence)"
    fi
else
    iter160_record_check_result_with_per_check_wall_clock_latency_and_severity_classification \
        "iter158_pre_commit_framework_manifest" \
        "iter-158 manifest" \
        "critical" "fail" "0" "manifest missing at $ITER160_ITER158_MANIFEST_ABSOLUTE_PATH"
fi

# ─── Check 9: iter-161 semver-bump classifier shared lib (CRITICAL) ─────────
#
# Iter-163 coverage extension: the iter-153 advisor SOURCES this lib at
# runtime to compute the MAJOR/MINOR/PATCH/NONE bump preview. If the
# lib is missing or the canonical classifier function is undefined, the
# advisor soft-fails (degrades to "UNAVAILABLE" preview) — which means
# the iter-160 doctor previously reported TOOLKIT_HEALTHY even though
# the advisor's semver-bump preview feature was silently broken. Iter-
# 163 closes this silent-regression gap by adding direct verification.

ITER163_ITER161_SEMVER_BUMP_CLASSIFIER_LIB_ABSOLUTE_PATH_FOR_ITER160_DOCTOR_COVERAGE_EXTENSION="$ITER160_CC_SKILLS_REPO_ROOT_ABSOLUTE_PATH/scripts/lib/iter161-semantic-release-version-bump-classifier-mapping-conventional-commit-type-and-breaking-change-marker-to-the-actual-major-minor-patch-bump-per-cc-skills-releaserc-yml-bump-rules-for-pre-commit-preview-overlay.sh"
if [[ -f "$ITER163_ITER161_SEMVER_BUMP_CLASSIFIER_LIB_ABSOLUTE_PATH_FOR_ITER160_DOCTOR_COVERAGE_EXTENSION" ]]; then
    iter160_time_command_and_capture_exit_code_and_wall_clock_milliseconds \
        bash -c "source '$ITER163_ITER161_SEMVER_BUMP_CLASSIFIER_LIB_ABSOLUTE_PATH_FOR_ITER160_DOCTOR_COVERAGE_EXTENSION' && declare -F iter161_classify_semantic_release_version_bump_from_conventional_commit_type_and_breaking_change_marker_against_cc_skills_releaserc_yml_release_rules >/dev/null"
    iter163_iter161_exit="$ITER160_HELPER_LATEST_EXIT_CODE_FROM_TIMED_COMMAND_INVOCATION"
    iter163_iter161_ms="$ITER160_HELPER_LATEST_WALL_CLOCK_MILLISECONDS_FROM_TIMED_COMMAND_INVOCATION"
    if [[ "$iter163_iter161_exit" -eq 0 ]]; then
        iter160_record_check_result_with_per_check_wall_clock_latency_and_severity_classification \
            "iter161_semver_bump_classifier_library" \
            "iter-161 semver-bump classifier shared library sources cleanly + exports canonical function" \
            "critical" "pass" "$iter163_iter161_ms"
    else
        iter160_record_check_result_with_per_check_wall_clock_latency_and_severity_classification \
            "iter161_semver_bump_classifier_library" \
            "iter-161 semver-bump classifier library" \
            "critical" "fail" "$iter163_iter161_ms" \
            "library failed to source or canonical classifier function missing"
    fi
else
    iter160_record_check_result_with_per_check_wall_clock_latency_and_severity_classification \
        "iter161_semver_bump_classifier_library" \
        "iter-161 semver-bump classifier library" \
        "critical" "fail" "0" "library missing"
fi

# ─── Check 10: iter-162 BREAKING-CHANGE footer detector lib (CRITICAL) ──────

ITER163_ITER162_BREAKING_CHANGE_FOOTER_DETECTOR_LIB_ABSOLUTE_PATH_FOR_ITER160_DOCTOR_COVERAGE_EXTENSION="$ITER160_CC_SKILLS_REPO_ROOT_ABSOLUTE_PATH/scripts/lib/iter162-conventional-commits-breaking-change-footer-token-detector-applying-uppercase-required-and-blank-line-separator-rules-per-conventional-commits-v1-section-13-and-semantic-release-commit-analyzer-default-angular-preset-behavior.sh"
if [[ -f "$ITER163_ITER162_BREAKING_CHANGE_FOOTER_DETECTOR_LIB_ABSOLUTE_PATH_FOR_ITER160_DOCTOR_COVERAGE_EXTENSION" ]]; then
    iter160_time_command_and_capture_exit_code_and_wall_clock_milliseconds \
        bash -c "source '$ITER163_ITER162_BREAKING_CHANGE_FOOTER_DETECTOR_LIB_ABSOLUTE_PATH_FOR_ITER160_DOCTOR_COVERAGE_EXTENSION' && declare -F iter162_detect_conventional_commits_breaking_change_footer_token_at_start_of_any_line_in_commit_message_body_per_section_13_uppercase_required_rule_and_angular_preset_plural_synonym_acceptance >/dev/null"
    iter163_iter162_exit="$ITER160_HELPER_LATEST_EXIT_CODE_FROM_TIMED_COMMAND_INVOCATION"
    iter163_iter162_ms="$ITER160_HELPER_LATEST_WALL_CLOCK_MILLISECONDS_FROM_TIMED_COMMAND_INVOCATION"
    if [[ "$iter163_iter162_exit" -eq 0 ]]; then
        iter160_record_check_result_with_per_check_wall_clock_latency_and_severity_classification \
            "iter162_breaking_change_footer_detector_library" \
            "iter-162 BREAKING-CHANGE footer-token detector library sources cleanly + exports canonical function" \
            "critical" "pass" "$iter163_iter162_ms"
    else
        iter160_record_check_result_with_per_check_wall_clock_latency_and_severity_classification \
            "iter162_breaking_change_footer_detector_library" \
            "iter-162 footer detector library" \
            "critical" "fail" "$iter163_iter162_ms" \
            "library failed to source or canonical detector function missing"
    fi
else
    iter160_record_check_result_with_per_check_wall_clock_latency_and_severity_classification \
        "iter162_breaking_change_footer_detector_library" \
        "iter-162 footer detector library" \
        "critical" "fail" "0" "library missing"
fi

# ─── Check 11: iter-153 → iter-161 → iter-162 end-to-end chain probe (CRITICAL)
#
# Iter-163 end-to-end chain probe: structural lib checks (9, 10) prove
# each lib loads in isolation, but DON'T prove the iter-153 advisor
# correctly wires them together. This probe runs a synthetic
# --message-file fixture (subject `feat: foo` + body footer `BREAKING
# CHANGE: bar`) through the real advisor and asserts the iter-161 bump
# label is MAJOR — the exact value iter-162 footer detection enables.
# If any link in the chain regresses (iter-153 stops sourcing iter-161
# or iter-162, iter-153 stops OR'ing the footer flag, iter-161 stops
# accepting boolean input, iter-162 stops emitting the correct
# variant), this probe fails CRITICAL.

ITER163_END_TO_END_ADVISOR_CHAIN_PROBE_SYNTHETIC_COMMIT_MESSAGE_FILE_ABSOLUTE_PATH=$(mktemp -t iter163-end-to-end-chain-probe-XXXXXX)
printf 'feat: synthetic iter-163 probe subject\n\nthis is a body explaining the change.\n\nBREAKING CHANGE: synthetic body footer for chain probe\n' \
    > "$ITER163_END_TO_END_ADVISOR_CHAIN_PROBE_SYNTHETIC_COMMIT_MESSAGE_FILE_ABSOLUTE_PATH"

ITER163_END_TO_END_PROBE_EXPECTED_BUMP_LABEL_FROM_INTACT_ITER153_TO_ITER161_TO_ITER162_CHAIN="MAJOR"
if [[ -x "$ITER160_ITER153_ADVISOR_ABSOLUTE_PATH" ]]; then
    iter160_time_command_and_capture_exit_code_and_wall_clock_milliseconds \
        bash -c "\"$ITER160_ITER153_ADVISOR_ABSOLUTE_PATH\" --json --message-file \"$ITER163_END_TO_END_ADVISOR_CHAIN_PROBE_SYNTHETIC_COMMIT_MESSAGE_FILE_ABSOLUTE_PATH\" 2>/dev/null | grep -q '\"bump_label_per_cc_skills_releaserc_yml_rules\": \"$ITER163_END_TO_END_PROBE_EXPECTED_BUMP_LABEL_FROM_INTACT_ITER153_TO_ITER161_TO_ITER162_CHAIN\"'"
    iter163_end_to_end_exit="$ITER160_HELPER_LATEST_EXIT_CODE_FROM_TIMED_COMMAND_INVOCATION"
    iter163_end_to_end_ms="$ITER160_HELPER_LATEST_WALL_CLOCK_MILLISECONDS_FROM_TIMED_COMMAND_INVOCATION"
    if [[ "$iter163_end_to_end_exit" -eq 0 ]]; then
        iter160_record_check_result_with_per_check_wall_clock_latency_and_severity_classification \
            "iter163_end_to_end_advisor_chain_probe" \
            "iter-163 end-to-end iter-153→iter-161→iter-162 chain probe (synthetic footer-form fixture → MAJOR)" \
            "critical" "pass" "$iter163_end_to_end_ms"
    else
        iter160_record_check_result_with_per_check_wall_clock_latency_and_severity_classification \
            "iter163_end_to_end_advisor_chain_probe" \
            "iter-163 end-to-end advisor chain probe" \
            "critical" "fail" "$iter163_end_to_end_ms" \
            "synthetic footer-form fixture failed to produce MAJOR bump — chain wiring regressed"
    fi
else
    iter160_record_check_result_with_per_check_wall_clock_latency_and_severity_classification \
        "iter163_end_to_end_advisor_chain_probe" \
        "iter-163 end-to-end advisor chain probe" \
        "critical" "fail" "0" "iter-153 advisor not executable"
fi
rm -f "$ITER163_END_TO_END_ADVISOR_CHAIN_PROBE_SYNTHETIC_COMMIT_MESSAGE_FILE_ABSOLUTE_PATH"

# ─── Check 12: iter-164 SemVer next-version resolver shared lib (CRITICAL) ──
#
# Iter-166 coverage extension. Parallel to iter-163's iter-161 lib check.
# The iter-153 advisor SOURCES this lib at runtime to compute the
# concrete next-version string from the iter-161 bump label + current
# git tag. The iter-165 aggregator ALSO sources it. If the lib is
# missing or the canonical resolver function is undefined, both
# consumers soft-fail (advisor degrades to empty "next version" line,
# aggregator emits empty next_version field) — silent breakage the
# pre-iter-166 doctor would not have caught.

ITER166_ITER164_SEMVER_NEXT_VERSION_RESOLVER_LIB_ABSOLUTE_PATH_FOR_ITER160_DOCTOR_COVERAGE_EXTENSION="$ITER160_CC_SKILLS_REPO_ROOT_ABSOLUTE_PATH/scripts/lib/iter164-semver-next-version-resolver-applying-iter161-bump-label-to-parsed-major-minor-patch-components-of-current-git-describe-tag-per-semver-org-specification-section-2-increment-rules.sh"
if [[ -f "$ITER166_ITER164_SEMVER_NEXT_VERSION_RESOLVER_LIB_ABSOLUTE_PATH_FOR_ITER160_DOCTOR_COVERAGE_EXTENSION" ]]; then
    iter160_time_command_and_capture_exit_code_and_wall_clock_milliseconds \
        bash -c "source '$ITER166_ITER164_SEMVER_NEXT_VERSION_RESOLVER_LIB_ABSOLUTE_PATH_FOR_ITER160_DOCTOR_COVERAGE_EXTENSION' && declare -F iter164_compute_concrete_next_semver_version_string_by_applying_bump_label_to_parsed_components_of_current_git_tag_per_semver_org_specification_section_2_increment_rules >/dev/null"
    iter166_iter164_exit="$ITER160_HELPER_LATEST_EXIT_CODE_FROM_TIMED_COMMAND_INVOCATION"
    iter166_iter164_ms="$ITER160_HELPER_LATEST_WALL_CLOCK_MILLISECONDS_FROM_TIMED_COMMAND_INVOCATION"
    if [[ "$iter166_iter164_exit" -eq 0 ]]; then
        iter160_record_check_result_with_per_check_wall_clock_latency_and_severity_classification \
            "iter164_semver_next_version_resolver_library" \
            "iter-164 SemVer next-version resolver shared library sources cleanly + exports canonical function" \
            "critical" "pass" "$iter166_iter164_ms"
    else
        iter160_record_check_result_with_per_check_wall_clock_latency_and_severity_classification \
            "iter164_semver_next_version_resolver_library" \
            "iter-164 next-version resolver library" \
            "critical" "fail" "$iter166_iter164_ms" \
            "library failed to source or canonical resolver function missing"
    fi
else
    iter160_record_check_result_with_per_check_wall_clock_latency_and_severity_classification \
        "iter164_semver_next_version_resolver_library" \
        "iter-164 next-version resolver library" \
        "critical" "fail" "0" "library missing"
fi

# ─── Check 13: iter-165 pending-release aggregator script (CRITICAL) ────────
#
# Iter-166 coverage extension. iter-165 is the operator's entry point
# for "what does my next release look like?" — and unlike a lib (which
# is sourced by a wrapper), iter-165 is an executable consumer in its
# own right. We verify: file exists, is executable, bash -n passes,
# and `--help` runs cleanly (no missing dependency surfaces).

ITER166_ITER165_PENDING_RELEASE_AGGREGATOR_SCRIPT_ABSOLUTE_PATH_FOR_ITER160_DOCTOR_COVERAGE_EXTENSION="$ITER160_CC_SKILLS_REPO_ROOT_ABSOLUTE_PATH/scripts/iter165-pending-release-aggregator-computing-cumulative-semver-bump-across-all-unreleased-commits-since-most-recent-git-tag-by-aggregating-iter161-classifier-output-and-rendering-concrete-iter164-next-version-preview.sh"
if [[ -x "$ITER166_ITER165_PENDING_RELEASE_AGGREGATOR_SCRIPT_ABSOLUTE_PATH_FOR_ITER160_DOCTOR_COVERAGE_EXTENSION" ]]; then
    iter160_time_command_and_capture_exit_code_and_wall_clock_milliseconds \
        bash -c "bash -n '$ITER166_ITER165_PENDING_RELEASE_AGGREGATOR_SCRIPT_ABSOLUTE_PATH_FOR_ITER160_DOCTOR_COVERAGE_EXTENSION' && '$ITER166_ITER165_PENDING_RELEASE_AGGREGATOR_SCRIPT_ABSOLUTE_PATH_FOR_ITER160_DOCTOR_COVERAGE_EXTENSION' --help >/dev/null 2>&1"
    iter166_iter165_exit="$ITER160_HELPER_LATEST_EXIT_CODE_FROM_TIMED_COMMAND_INVOCATION"
    iter166_iter165_ms="$ITER160_HELPER_LATEST_WALL_CLOCK_MILLISECONDS_FROM_TIMED_COMMAND_INVOCATION"
    if [[ "$iter166_iter165_exit" -eq 0 ]]; then
        iter160_record_check_result_with_per_check_wall_clock_latency_and_severity_classification \
            "iter165_pending_release_aggregator_script" \
            "iter-165 pending-release aggregator script passes bash -n + --help runs cleanly" \
            "critical" "pass" "$iter166_iter165_ms"
    else
        iter160_record_check_result_with_per_check_wall_clock_latency_and_severity_classification \
            "iter165_pending_release_aggregator_script" \
            "iter-165 pending-release aggregator script" \
            "critical" "fail" "$iter166_iter165_ms" \
            "script failed bash -n syntax check or --help invocation (likely missing shared-lib dependency)"
    fi
else
    iter160_record_check_result_with_per_check_wall_clock_latency_and_severity_classification \
        "iter165_pending_release_aggregator_script" \
        "iter-165 pending-release aggregator script" \
        "critical" "fail" "0" "script missing or not executable"
fi

# ─── Check 14: iter-153→iter-161→iter-164→iter-165 end-to-end probe (CRITICAL)
#
# Iter-166 end-to-end chain probe — parallel to iter-163's iter-153→
# iter-161→iter-162 probe but exercising the OTHER half of the wiring:
# iter-165 aggregator → iter-161 classifier → iter-164 resolver. Builds
# a throwaway temp git repo with one tagged baseline + one synthetic
# `feat:` commit, runs iter-165 in --json mode against it via
# ITER165_REPO_ROOT_OVERRIDE, and asserts the aggregator emits both
# aggregate_bump_label=MINOR AND next_version=v1.1.0. This probe fails
# CRITICAL if any link regresses: iter-165 stops sourcing iter-161,
# iter-161 stops mapping feat→MINOR, iter-165 stops sourcing iter-164,
# iter-164 stops applying §2 increment rules, or iter-165's --json
# emission breaks.

ITER166_END_TO_END_AGGREGATOR_CHAIN_PROBE_TEMP_REPO_ABSOLUTE_PATH=$(mktemp -d -t iter166-end-to-end-aggregator-probe-XXXXXX)
iter166_end_to_end_aggregator_probe_setup_exit_code=0
(
    cd "$ITER166_END_TO_END_AGGREGATOR_CHAIN_PROBE_TEMP_REPO_ABSOLUTE_PATH"
    git init -q
    git config user.email "iter166-doctor-probe@example.com"
    git config user.name "iter166-doctor-probe"
    git commit --allow-empty -q -m "baseline before tag"
    git tag v1.0.0
    git commit --allow-empty -q -m "feat: synthetic iter-166 doctor probe commit"
) >/dev/null 2>&1 || iter166_end_to_end_aggregator_probe_setup_exit_code=$?

if [[ "$iter166_end_to_end_aggregator_probe_setup_exit_code" -ne 0 ]]; then
    iter160_record_check_result_with_per_check_wall_clock_latency_and_severity_classification \
        "iter166_end_to_end_aggregator_chain_probe" \
        "iter-166 end-to-end iter-153→iter-161→iter-164→iter-165 chain probe" \
        "critical" "fail" "0" "could not set up synthetic temp git repo for probe"
elif [[ -x "$ITER166_ITER165_PENDING_RELEASE_AGGREGATOR_SCRIPT_ABSOLUTE_PATH_FOR_ITER160_DOCTOR_COVERAGE_EXTENSION" ]]; then
    iter160_time_command_and_capture_exit_code_and_wall_clock_milliseconds \
        bash -c "cd '$ITER166_END_TO_END_AGGREGATOR_CHAIN_PROBE_TEMP_REPO_ABSOLUTE_PATH' && ITER165_REPO_ROOT_OVERRIDE='$ITER166_END_TO_END_AGGREGATOR_CHAIN_PROBE_TEMP_REPO_ABSOLUTE_PATH' '$ITER166_ITER165_PENDING_RELEASE_AGGREGATOR_SCRIPT_ABSOLUTE_PATH_FOR_ITER160_DOCTOR_COVERAGE_EXTENSION' --json 2>/dev/null | grep -q '\"aggregate_bump_label_per_semver_precedence\": \"MINOR\"' && cd '$ITER166_END_TO_END_AGGREGATOR_CHAIN_PROBE_TEMP_REPO_ABSOLUTE_PATH' && ITER165_REPO_ROOT_OVERRIDE='$ITER166_END_TO_END_AGGREGATOR_CHAIN_PROBE_TEMP_REPO_ABSOLUTE_PATH' '$ITER166_ITER165_PENDING_RELEASE_AGGREGATOR_SCRIPT_ABSOLUTE_PATH_FOR_ITER160_DOCTOR_COVERAGE_EXTENSION' --json 2>/dev/null | grep -q '\"next_version\": \"v1.1.0\"'"
    iter166_end_to_end_aggregator_exit="$ITER160_HELPER_LATEST_EXIT_CODE_FROM_TIMED_COMMAND_INVOCATION"
    iter166_end_to_end_aggregator_ms="$ITER160_HELPER_LATEST_WALL_CLOCK_MILLISECONDS_FROM_TIMED_COMMAND_INVOCATION"
    if [[ "$iter166_end_to_end_aggregator_exit" -eq 0 ]]; then
        iter160_record_check_result_with_per_check_wall_clock_latency_and_severity_classification \
            "iter166_end_to_end_aggregator_chain_probe" \
            "iter-166 end-to-end iter-153→iter-161→iter-164→iter-165 chain probe (synthetic feat → MINOR + v1.1.0)" \
            "critical" "pass" "$iter166_end_to_end_aggregator_ms"
    else
        iter160_record_check_result_with_per_check_wall_clock_latency_and_severity_classification \
            "iter166_end_to_end_aggregator_chain_probe" \
            "iter-166 end-to-end aggregator chain probe" \
            "critical" "fail" "$iter166_end_to_end_aggregator_ms" \
            "synthetic feat fixture failed to produce MINOR aggregate + v1.1.0 next-version — chain wiring regressed (iter-165→iter-161 or iter-165→iter-164 broken)"
    fi
else
    iter160_record_check_result_with_per_check_wall_clock_latency_and_severity_classification \
        "iter166_end_to_end_aggregator_chain_probe" \
        "iter-166 end-to-end aggregator chain probe" \
        "critical" "fail" "0" "iter-165 aggregator not executable — cannot run end-to-end probe"
fi
rm -rf "$ITER166_END_TO_END_AGGREGATOR_CHAIN_PROBE_TEMP_REPO_ABSOLUTE_PATH"

# ─── Check 15: pre-commit binary available for iter-158 polyglot path (WARN) ─

if command -v pre-commit >/dev/null 2>&1; then
    ITER160_PRE_COMMIT_BINARY_VERSION_STRING_TRIMMED=$(pre-commit --version 2>&1 | head -1)
    iter160_record_check_result_with_per_check_wall_clock_latency_and_severity_classification \
        "pre_commit_framework_binary_available" \
        "pre-commit framework binary available ($ITER160_PRE_COMMIT_BINARY_VERSION_STRING_TRIMMED)" \
        "warning" "pass" "0"
else
    iter160_record_check_result_with_per_check_wall_clock_latency_and_severity_classification \
        "pre_commit_framework_binary_available" \
        "pre-commit framework binary NOT installed" \
        "warning" "fail" "0" \
        "install via: uv tool install pre-commit (needed for iter-158 polyglot consumption)"
fi

# ─── Emit final report ──────────────────────────────────────────────────────

if [[ "$ITER160_OUTPUT_MODE_HUMAN_READABLE_DEFAULT_OR_JSON_FOR_AI_AGENT_CONSUMPTION" == "human" ]]; then
    echo ""
    echo "═══════════════════════════════════════════════════════════════════════════════"
    if (( ITER160_TOTAL_CRITICAL_FAILED == 0 )); then
        printf '  %s✓%s Toolkit healthy: %d CRITICAL checks passed, %d warnings reported\n' \
            "$ITER160_ANSI_COLOR_GREEN_FOR_PASSING_CRITICAL_CHECK" \
            "$ITER160_ANSI_COLOR_RESET" \
            "$ITER160_TOTAL_CRITICAL_PASSED" \
            "$ITER160_TOTAL_WARNINGS_REPORTED"
    else
        printf '  %s✗%s Toolkit BROKEN: %d CRITICAL checks failed\n' \
            "$ITER160_ANSI_COLOR_RED_FOR_FAILING_CRITICAL_CHECK" \
            "$ITER160_ANSI_COLOR_RESET" \
            "$ITER160_TOTAL_CRITICAL_FAILED"
    fi
    echo "═══════════════════════════════════════════════════════════════════════════════"
else
    # JSON mode: source the iter-155 shared library, then emit a single
    # structured object with check records + summary counters.
    if [[ -f "$ITER160_ITER155_SHARED_JSON_ESCAPE_LIB_ABSOLUTE_PATH_FOR_ITER160_STATUS_TASK" ]]; then
        # shellcheck disable=SC1090
        source "$ITER160_ITER155_SHARED_JSON_ESCAPE_LIB_ABSOLUTE_PATH_FOR_ITER160_STATUS_TASK"
    fi
    iter160_render_check_record_pipe_separated_string_as_json_object_using_iter155_shared_escape() {
        local pipe_separated_record="$1"
        IFS='|' read -r identifier label severity outcome latency message <<< "$pipe_separated_record"
        local escaped_identifier escaped_label escaped_message
        escaped_identifier=$(iter155_pure_bash_rfc8259_compliant_json_string_escape_handling_all_seven_named_escapes_plus_generic_uxxxx_for_control_chars "$identifier")
        escaped_label=$(iter155_pure_bash_rfc8259_compliant_json_string_escape_handling_all_seven_named_escapes_plus_generic_uxxxx_for_control_chars "$label")
        escaped_message=$(iter155_pure_bash_rfc8259_compliant_json_string_escape_handling_all_seven_named_escapes_plus_generic_uxxxx_for_control_chars "$message")
        printf '{"identifier":%s,"label":%s,"severity":"%s","outcome":"%s","wall_clock_latency_milliseconds":%d,"diagnostic_message":%s}' \
            "$escaped_identifier" "$escaped_label" "$severity" "$outcome" "${latency:-0}" "$escaped_message"
    }

    printf '{\n'
    printf '  "iter160_schema_version": 1,\n'
    printf '  "summary": {\n'
    printf '    "total_checks_evaluated": %d,\n' "$ITER160_TOTAL_CHECKS_EVALUATED"
    printf '    "critical_passed": %d,\n' "$ITER160_TOTAL_CRITICAL_PASSED"
    printf '    "critical_failed": %d,\n' "$ITER160_TOTAL_CRITICAL_FAILED"
    printf '    "warnings_reported": %d,\n' "$ITER160_TOTAL_WARNINGS_REPORTED"
    if (( ITER160_TOTAL_CRITICAL_FAILED == 0 )); then
        printf '    "verdict": "TOOLKIT_HEALTHY"\n'
    else
        printf '    "verdict": "TOOLKIT_BROKEN"\n'
    fi
    printf '  },\n'
    printf '  "checks": [\n'
    local_iter160_first_record_emitted_yet=0
    for record in "${ITER160_CHECK_RECORDS_FOR_JSON_OUTPUT_ARRAY[@]}"; do
        if (( local_iter160_first_record_emitted_yet == 1 )); then
            printf ',\n'
        fi
        printf '    '
        iter160_render_check_record_pipe_separated_string_as_json_object_using_iter155_shared_escape "$record"
        local_iter160_first_record_emitted_yet=1
    done
    printf '\n  ]\n'
    printf '}\n'
fi

# ─── Exit gating per industry-standard severity-tier convention ─────────────

if (( ITER160_TOTAL_CRITICAL_FAILED == 0 )); then
    exit 0
else
    exit 1
fi
