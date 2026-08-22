#!/usr/bin/env bash
#MISE description="Iter-86 preventive audit: statically verifies every file in plugins/itp-hooks/hooks/ that exports a classify*ForOrchestrator function conforms to the PreToolUseSubhookContract: (a) the classify* function body MUST NOT contain process.exit/process.stdout.write/process.stdin/console.log calls (pure-function discipline — orchestrator owns I/O), AND (b) the file MUST gate its standalone main() under 'if (import.meta.main)' so importing the classifier from the orchestrator does NOT double-execute main(). Addresses HIGH FOOTGUN #1 (import.meta.main not statically enforced) and HIGH FOOTGUN #2 (contract enforcement runtime-only) from the iter-85 adversarial audit. Designed as a release:preflight gate (informational by default, --strict for blocking) so future iter-86+ migrations cannot regress the contract without surfacing a diagnostic."

set -euo pipefail
shopt -u patsub_replacement 2>/dev/null || true

# --- Argument parsing ---
STRICT_MODE_GATE_RELEASE_ON_CONTRACT_VIOLATION=0
while [[ $# -gt 0 ]]; do
    case "$1" in
        --strict)
            STRICT_MODE_GATE_RELEASE_ON_CONTRACT_VIOLATION=1
            shift
            ;;
        --help|-h)
            echo "Usage: $0 [--strict]"
            echo "  --strict   Exit non-zero on any contract violation (release-gate mode)."
            echo "             Default: informational (exits 0 regardless)."
            exit 0
            ;;
        *)
            echo "Unknown argument: $1"
            exit 2
            ;;
    esac
done

# --- Locate repo root + hook dir ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AUDIT_TASK_OWN_REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
REPO_ROOT="${AUDIT_REPO_ROOT_OVERRIDE:-$AUDIT_TASK_OWN_REPO_ROOT}"
HOOK_DIRECTORY="$REPO_ROOT/plugins/itp-hooks/hooks"

if [[ ! -d "$HOOK_DIRECTORY" ]]; then
    echo "FAIL: hook directory not found at $HOOK_DIRECTORY"
    exit 1
fi

echo "════════════════════════════════════════════════════════════════════════════════"
echo "  Iter-86 PreToolUse Orchestrator Subhook Contract Static Checker"
echo "════════════════════════════════════════════════════════════════════════════════"
printf "  Hook directory:                    %s\n" "$HOOK_DIRECTORY"
if [[ "$STRICT_MODE_GATE_RELEASE_ON_CONTRACT_VIOLATION" == "1" ]]; then
    echo "  Mode:                              STRICT (exits non-zero on violation)"
else
    echo "  Mode:                              informational (exits 0 regardless)"
fi
echo "════════════════════════════════════════════════════════════════════════════════"
echo ""

# --- Discover candidate files ---
# A "subhook file" is any .ts/.mjs file in $HOOK_DIRECTORY that exports a
# function matching `classify*ForOrchestrator` (the iter-84/85 naming
# convention from PreToolUseSubhookClassifierFunction).
CANDIDATE_SUBHOOK_FILES_WITH_EXPORTED_CLASSIFIER_FUNCTION=()
while IFS= read -r candidate_file; do
    if grep -qE '^export[[:space:]]+(async[[:space:]]+)?function[[:space:]]+classify[A-Za-z]+ForOrchestrator' "$candidate_file"; then
        CANDIDATE_SUBHOOK_FILES_WITH_EXPORTED_CLASSIFIER_FUNCTION+=("$candidate_file")
    fi
done < <(find "$HOOK_DIRECTORY" -maxdepth 1 -type f \( -name '*.ts' -o -name '*.mjs' \) -not -name '*.test.ts' -print)

if [[ "${#CANDIDATE_SUBHOOK_FILES_WITH_EXPORTED_CLASSIFIER_FUNCTION[@]}" -eq 0 ]]; then
    echo "  ⚠ No subhook files discovered (no files export classify*ForOrchestrator)"
    echo "    This is unexpected — iter-84+ should have at least file-size-guard inlined."
    exit 0
fi

printf "  Subhook files discovered:          %d\n" "${#CANDIDATE_SUBHOOK_FILES_WITH_EXPORTED_CLASSIFIER_FUNCTION[@]}"
echo ""

# --- Run two contract checks per subhook file ---
TOTAL_FILES_SCANNED=0
TOTAL_FILES_VIOLATING_IMPORT_META_MAIN_GUARD=0
TOTAL_FILES_VIOLATING_PURE_CLASSIFIER_NO_IO_DISCIPLINE=0
declare -a IMPORT_META_MAIN_GUARD_VIOLATION_DIAGNOSTIC_LINES=()
declare -a PURE_CLASSIFIER_NO_IO_VIOLATION_DIAGNOSTIC_LINES=()

# Awk script: extracts the function body of every classify*ForOrchestrator export
# and reports any line within that body matching the FORBIDDEN_PURE_CLASSIFIER_IO_CALL_PATTERN.
# We do a brace-depth scan starting at the function signature line to bound the body.
# (Single-quoted awk source contains $0/$NR awk-field references that shellcheck
#  SC2016 mistakes for shell variable interpolation — false positive.)
# shellcheck disable=SC2016
PURE_CLASSIFIER_FUNCTION_BODY_FORBIDDEN_IO_CALL_EXTRACTOR_AWK_PROGRAM='
BEGIN {
    in_classifier_function = 0
    brace_depth = 0
    function_start_line = 0
}
/^export[[:space:]]+(async[[:space:]]+)?function[[:space:]]+classify[A-Za-z]+ForOrchestrator/ {
    in_classifier_function = 1
    brace_depth = 0
    function_start_line = NR
}
in_classifier_function == 1 {
    # Crude brace-depth tracking — does not understand /* { */ comments
    # or string contents, but for hook code (no string-embedded braces),
    # this is sound. Compute opens minus closes on this line.
    line_for_brace_count = $0
    opens = gsub(/\{/, "{", line_for_brace_count)
    line_for_brace_count_for_close = $0
    closes = gsub(/\}/, "}", line_for_brace_count_for_close)
    brace_depth += opens - closes

    # After the signature line, brace_depth becomes >0 on the body-open line.
    # When it returns to 0 (function close), we exit classifier scope.
    if (brace_depth == 0 && NR > function_start_line) {
        in_classifier_function = 0
        next
    }

    # Check for forbidden I/O calls inside the function body.
    # The pattern matches: process.exit, process.stdout.write, process.stderr.write,
    # process.stdin, console.log, console.error, Bun.stdin, Bun.write
    if (NR > function_start_line && \
        ($0 ~ /process\.exit[[:space:]]*\(/ \
         || $0 ~ /process\.stdout\.(write|cork|uncork)/ \
         || $0 ~ /process\.stderr\.(write|cork|uncork)/ \
         || $0 ~ /process\.stdin/ \
         || $0 ~ /console\.(log|error|warn|info|debug)[[:space:]]*\(/ \
         || $0 ~ /Bun\.stdin/ \
         || $0 ~ /Bun\.write[[:space:]]*\(/)) {
        # Strip leading whitespace for readability
        offending_code = $0
        sub(/^[[:space:]]+/, "", offending_code)
        printf "    line %d: %s\n", NR, offending_code
    }
}
'

for subhook_file_under_static_contract_check in "${CANDIDATE_SUBHOOK_FILES_WITH_EXPORTED_CLASSIFIER_FUNCTION[@]}"; do
    TOTAL_FILES_SCANNED=$((TOTAL_FILES_SCANNED + 1))
    subhook_file_relative_path="${subhook_file_under_static_contract_check#"$REPO_ROOT"/}"

    # CHECK 1: import.meta.main guard
    # If the file has an `async function main(` declaration, it MUST have
    # `if (import.meta.main)` somewhere AFTER the main declaration, so importing
    # this file from the orchestrator does NOT trigger main() side-effects.
    if grep -qE '^async[[:space:]]+function[[:space:]]+main[[:space:]]*\(' "$subhook_file_under_static_contract_check"; then
        if ! grep -qE 'if[[:space:]]*\([[:space:]]*import\.meta\.main' "$subhook_file_under_static_contract_check"; then
            TOTAL_FILES_VIOLATING_IMPORT_META_MAIN_GUARD=$((TOTAL_FILES_VIOLATING_IMPORT_META_MAIN_GUARD + 1))
            IMPORT_META_MAIN_GUARD_VIOLATION_DIAGNOSTIC_LINES+=(
                "  - ${subhook_file_relative_path}"
                "    Has async function main() but NO 'if (import.meta.main)' guard."
                "    Importing this file from the orchestrator would silently re-execute main()."
                "    Fix: wrap the main() invocation site in 'if (import.meta.main) { main().catch(...) }'"
            )
        fi
    fi

    # CHECK 2: pure-classifier no-I/O discipline
    # Use awk to extract the function body of every classify*ForOrchestrator export
    # and report forbidden I/O calls.
    forbidden_io_violations_in_classifier_function_body=$(
        awk "$PURE_CLASSIFIER_FUNCTION_BODY_FORBIDDEN_IO_CALL_EXTRACTOR_AWK_PROGRAM" \
            "$subhook_file_under_static_contract_check"
    )
    if [[ -n "$forbidden_io_violations_in_classifier_function_body" ]]; then
        TOTAL_FILES_VIOLATING_PURE_CLASSIFIER_NO_IO_DISCIPLINE=$((TOTAL_FILES_VIOLATING_PURE_CLASSIFIER_NO_IO_DISCIPLINE + 1))
        PURE_CLASSIFIER_NO_IO_VIOLATION_DIAGNOSTIC_LINES+=(
            "  - ${subhook_file_relative_path}"
            "    Classifier function body contains forbidden I/O calls:"
        )
        while IFS= read -r violation_line; do
            PURE_CLASSIFIER_NO_IO_VIOLATION_DIAGNOSTIC_LINES+=(
                "  $violation_line"
            )
        done <<< "$forbidden_io_violations_in_classifier_function_body"
        PURE_CLASSIFIER_NO_IO_VIOLATION_DIAGNOSTIC_LINES+=(
            "    Fix: return a PreToolUseSubhookDecision object (ALLOW_DECISION, denyDecision(reason),"
            "    askDecision(reason)) instead of calling allow()/deny()/process.stdout.write/etc."
        )
    fi
done

# --- Render summary ---
echo "  Total subhook files scanned:                  $TOTAL_FILES_SCANNED"
echo "  Files missing import.meta.main guard:         $TOTAL_FILES_VIOLATING_IMPORT_META_MAIN_GUARD"
echo "  Files with forbidden I/O in classifier body:  $TOTAL_FILES_VIOLATING_PURE_CLASSIFIER_NO_IO_DISCIPLINE"

if [[ "$TOTAL_FILES_VIOLATING_IMPORT_META_MAIN_GUARD" -gt 0 ]]; then
    echo ""
    echo "─── import.meta.main guard violations ─────────────────────────────────────────"
    printf '%s\n' "${IMPORT_META_MAIN_GUARD_VIOLATION_DIAGNOSTIC_LINES[@]}"
fi

if [[ "$TOTAL_FILES_VIOLATING_PURE_CLASSIFIER_NO_IO_DISCIPLINE" -gt 0 ]]; then
    echo ""
    echo "─── pure-classifier no-I/O discipline violations ──────────────────────────────"
    printf '%s\n' "${PURE_CLASSIFIER_NO_IO_VIOLATION_DIAGNOSTIC_LINES[@]}"
fi

echo ""

TOTAL_CONTRACT_VIOLATIONS_BLOCKING_STRICT_MODE=$((
    TOTAL_FILES_VIOLATING_IMPORT_META_MAIN_GUARD + TOTAL_FILES_VIOLATING_PURE_CLASSIFIER_NO_IO_DISCIPLINE
))

if [[ "$STRICT_MODE_GATE_RELEASE_ON_CONTRACT_VIOLATION" == "1" ]] \
   && [[ "$TOTAL_CONTRACT_VIOLATIONS_BLOCKING_STRICT_MODE" -gt 0 ]]; then
    echo "════════════════════════════════════════════════════════════════════════════════"
    echo "  ✗ STRICT MODE: $TOTAL_CONTRACT_VIOLATIONS_BLOCKING_STRICT_MODE subhook contract violation(s) detected"
    echo "════════════════════════════════════════════════════════════════════════════════"
    exit 1
fi

if [[ "$TOTAL_CONTRACT_VIOLATIONS_BLOCKING_STRICT_MODE" -eq 0 ]]; then
    echo "════════════════════════════════════════════════════════════════════════════════"
    echo "  ✓ All $TOTAL_FILES_SCANNED subhook files conform to the PreToolUseSubhookContract"
    echo "════════════════════════════════════════════════════════════════════════════════"
else
    echo "════════════════════════════════════════════════════════════════════════════════"
    echo "  ⚠ $TOTAL_CONTRACT_VIOLATIONS_BLOCKING_STRICT_MODE contract violation(s) (informational; not gating)"
    echo "════════════════════════════════════════════════════════════════════════════════"
fi
exit 0
