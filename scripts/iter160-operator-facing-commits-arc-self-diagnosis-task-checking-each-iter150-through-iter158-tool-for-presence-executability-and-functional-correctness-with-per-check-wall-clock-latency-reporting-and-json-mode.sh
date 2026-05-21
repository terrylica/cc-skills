#!/usr/bin/env bash
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

iter160_time_command_and_capture_exit_code_and_wall_clock_milliseconds() {
    local start_ns end_ns elapsed_ms actual_exit=0
    start_ns=$(perl -MTime::HiRes=time -e 'printf "%.0f\n", time*1e9')
    "$@" >/dev/null 2>&1 || actual_exit=$?
    end_ns=$(perl -MTime::HiRes=time -e 'printf "%.0f\n", time*1e9')
    elapsed_ms=$(( (end_ns - start_ns) / 1000000 ))
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

# ─── Check 9: pre-commit binary available for iter-158 polyglot path (WARN) ─

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
