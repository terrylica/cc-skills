#!/usr/bin/env bash
#MISE description="Iter-154 regression test pinning two hardening fixes to the iter-153 advisor: (a) pure-bash JSON escape function replacing the python3-dependent path that emitted broken JSON when python3 was absent — verifies all 7 RFC 8259 § 7 special chars (\", \\, \\b, \\f, \\n, \\r, \\t) escape correctly and that downstream JSON parsers can round-trip the output; (b) .git/COMMIT_EDITMSG auto-detect closing the natural workflow loop (operator opens editor → types subject → saves → runs commits:advise in another terminal → sees verdict on in-progress commit). Asserts no python3 dependency remains in the JSON escape path, pure-bash escape function is declared with the verbose-self-explanatory iter154_json_escape_string_in_pure_bash_handling_all_seven_json_specification_special_characters_without_external_dependency name, all 7 special-char round-trip tests parse cleanly via independent python3 json.loads, and the COMMIT_EDITMSG auto-detect block is wired into the arg-parsing fallback path."
set -euo pipefail

ITER154_REPO_ROOT="${AUDIT_REPO_ROOT_OVERRIDE:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
cd "$ITER154_REPO_ROOT"

ITER154_ADVISOR_SCRIPT_RELATIVE_PATH="scripts/iter153-operator-facing-pre-commit-dry-run-advisor-classifying-proposed-conventional-commit-subject-through-iter82-grammar-and-iter151-overlay-with-human-readable-verdict-default-and-json-output-mode-for-ai-agent-automation-pipeline-consumption.sh"
ITER154_ADVISOR_SCRIPT_ABSOLUTE_PATH="$ITER154_REPO_ROOT/$ITER154_ADVISOR_SCRIPT_RELATIVE_PATH"

ITER154_TOTAL_ASSERTIONS_EVALUATED=0
ITER154_TOTAL_ASSERTIONS_FAILED=0

iter154_assert_substring_present_in_file() {
    local human_readable_assertion_label="$1"
    local file_path_to_grep="$2"
    local expected_substring="$3"
    ITER154_TOTAL_ASSERTIONS_EVALUATED=$((ITER154_TOTAL_ASSERTIONS_EVALUATED + 1))
    if grep -qF -- "$expected_substring" "$file_path_to_grep" 2>/dev/null; then
        echo "  ✓ $human_readable_assertion_label"
    else
        echo "  ✗ $human_readable_assertion_label"
        echo "    expected substring: ${expected_substring:0:120}"
        ITER154_TOTAL_ASSERTIONS_FAILED=$((ITER154_TOTAL_ASSERTIONS_FAILED + 1))
    fi
}

iter154_assert_substring_absent_from_file() {
    local human_readable_assertion_label="$1"
    local file_path_to_grep="$2"
    local unwanted_substring="$3"
    ITER154_TOTAL_ASSERTIONS_EVALUATED=$((ITER154_TOTAL_ASSERTIONS_EVALUATED + 1))
    if ! grep -qF -- "$unwanted_substring" "$file_path_to_grep" 2>/dev/null; then
        echo "  ✓ $human_readable_assertion_label"
    else
        echo "  ✗ $human_readable_assertion_label"
        echo "    unwanted substring still present: ${unwanted_substring:0:120}"
        ITER154_TOTAL_ASSERTIONS_FAILED=$((ITER154_TOTAL_ASSERTIONS_FAILED + 1))
    fi
}

iter154_assert_json_roundtrip_via_python3_json_module_preserves_input_string_exactly() {
    local human_readable_assertion_label="$1"
    local proposed_subject_input_with_potentially_json_sensitive_special_characters="$2"
    ITER154_TOTAL_ASSERTIONS_EVALUATED=$((ITER154_TOTAL_ASSERTIONS_EVALUATED + 1))

    local advisor_json_output_captured
    advisor_json_output_captured=$(
        "$ITER154_ADVISOR_SCRIPT_ABSOLUTE_PATH" --json -- "$proposed_subject_input_with_potentially_json_sensitive_special_characters" 2>/dev/null
    )
    local parsed_subject_via_python3_json_loads
    parsed_subject_via_python3_json_loads=$(
        printf '%s' "$advisor_json_output_captured" \
            | python3 -c 'import json,sys; print(json.load(sys.stdin)["subject"], end="")' 2>/dev/null
    )

    if [[ "$parsed_subject_via_python3_json_loads" == "$proposed_subject_input_with_potentially_json_sensitive_special_characters" ]]; then
        echo "  ✓ $human_readable_assertion_label"
    else
        echo "  ✗ $human_readable_assertion_label"
        echo "    input:  $(printf '%q' "$proposed_subject_input_with_potentially_json_sensitive_special_characters")"
        echo "    output: $(printf '%q' "$parsed_subject_via_python3_json_loads")"
        ITER154_TOTAL_ASSERTIONS_FAILED=$((ITER154_TOTAL_ASSERTIONS_FAILED + 1))
    fi
}

echo ""
echo "═══════════════════════════════════════════════════════════════════════════════"
echo "  ITER-154 ADVISOR-HARDENING REGRESSION TEST"
echo "═══════════════════════════════════════════════════════════════════════════════"

# ─── Group A: pure-bash JSON escape function structural pin ─────────────────
echo ""
echo "GROUP A (4 assertions): pure-bash JSON escape function structurally pinned"

iter154_assert_substring_present_in_file \
    "A1: pure-bash JSON escape function declared with verbose-self-explanatory name" \
    "$ITER154_ADVISOR_SCRIPT_ABSOLUTE_PATH" \
    "iter154_json_escape_string_in_pure_bash_handling_all_seven_json_specification_special_characters_without_external_dependency"

iter154_assert_substring_present_in_file \
    "A2: JSON escape function references RFC 8259 § 7 standard for traceability" \
    "$ITER154_ADVISOR_SCRIPT_ABSOLUTE_PATH" \
    "RFC 8259"

iter154_assert_substring_absent_from_file \
    "A3: python3-based JSON escape primary path eliminated (correctness bug fixed)" \
    "$ITER154_ADVISOR_SCRIPT_ABSOLUTE_PATH" \
    "python3 -c 'import json"

iter154_assert_substring_present_in_file \
    "A4: control-char handler emits \\uXXXX for non-named control chars per RFC 8259" \
    "$ITER154_ADVISOR_SCRIPT_ABSOLUTE_PATH" \
    'printf '"'"'\\u%04x'"'"

# ─── Group B: All 7 RFC 8259 special chars round-trip correctly ─────────────
echo ""
echo "GROUP B (7 assertions): all 7 RFC 8259 § 7 special chars round-trip via JSON parser"

iter154_assert_json_roundtrip_via_python3_json_module_preserves_input_string_exactly \
    "B1: double quote (U+0022) escapes correctly" \
    'feat: add "quoted" word'

iter154_assert_json_roundtrip_via_python3_json_module_preserves_input_string_exactly \
    "B2: backslash (U+005C) escapes correctly" \
    'feat: add path C:\foo\bar'

iter154_assert_json_roundtrip_via_python3_json_module_preserves_input_string_exactly \
    "B3: tab (U+0009) escapes correctly" \
    "$(printf 'feat: add\ttab')"

iter154_assert_json_roundtrip_via_python3_json_module_preserves_input_string_exactly \
    "B4: line feed (U+000A) escapes correctly" \
    "$(printf 'feat: line one\nline two')"

iter154_assert_json_roundtrip_via_python3_json_module_preserves_input_string_exactly \
    "B5: carriage return (U+000D) escapes correctly" \
    "$(printf 'feat: cr\rword')"

iter154_assert_json_roundtrip_via_python3_json_module_preserves_input_string_exactly \
    "B6: backspace (U+0008) escapes correctly" \
    "$(printf 'feat: bs\bword')"

iter154_assert_json_roundtrip_via_python3_json_module_preserves_input_string_exactly \
    "B7: form feed (U+000C) escapes correctly" \
    "$(printf 'feat: ff\fword')"

# ─── Group C: COMMIT_EDITMSG auto-detect path structural pin ────────────────
echo ""
echo "GROUP C (4 assertions): .git/COMMIT_EDITMSG auto-detect path structurally pinned"

iter154_assert_substring_present_in_file \
    "C1: auto-detect block references COMMIT_EDITMSG file by name" \
    "$ITER154_ADVISOR_SCRIPT_ABSOLUTE_PATH" \
    "COMMIT_EDITMSG"

iter154_assert_substring_present_in_file \
    "C2: auto-detect constructs absolute path via git rev-parse --show-toplevel" \
    "$ITER154_ADVISOR_SCRIPT_ABSOLUTE_PATH" \
    "ITER154_GIT_REPO_ROOT_FOR_COMMIT_EDITMSG_AUTO_DETECT"

iter154_assert_substring_present_in_file \
    "C3: auto-detect guards on TTY context to avoid surprising piped-input operators" \
    "$ITER154_ADVISOR_SCRIPT_ABSOLUTE_PATH" \
    '[[ -t 0 ]]'

iter154_assert_substring_present_in_file \
    "C4: auto-detect reads first non-comment non-empty line per git convention" \
    "$ITER154_ADVISOR_SCRIPT_ABSOLUTE_PATH" \
    "grep -v '^#'"

# ─── Group D: JSON output remains valid for trivial input ──────────────────
echo ""
echo "GROUP D (1 assertion): JSON output remains valid for trivial input (regression baseline)"

ITER154_TOTAL_ASSERTIONS_EVALUATED=$((ITER154_TOTAL_ASSERTIONS_EVALUATED + 1))
ITER154_TRIVIAL_JSON_OUTPUT_CAPTURE=$(
    "$ITER154_ADVISOR_SCRIPT_ABSOLUTE_PATH" --json -- "feat: foo" 2>/dev/null
)
if printf '%s' "$ITER154_TRIVIAL_JSON_OUTPUT_CAPTURE" | python3 -c 'import json,sys; json.load(sys.stdin)' 2>/dev/null; then
    echo "  ✓ D1: --json output parses cleanly via independent python3 json.loads for trivial input"
else
    echo "  ✗ D1: --json output fails to parse"
    ITER154_TOTAL_ASSERTIONS_FAILED=$((ITER154_TOTAL_ASSERTIONS_FAILED + 1))
fi

# ─── Final report ─────────────────────────────────────────────────────────────
echo ""
echo "═══════════════════════════════════════════════════════════════════════════════"
if (( ITER154_TOTAL_ASSERTIONS_FAILED == 0 )); then
    echo "  ✓ ITER-154 REGRESSION TEST: ${ITER154_TOTAL_ASSERTIONS_EVALUATED}/${ITER154_TOTAL_ASSERTIONS_EVALUATED} assertions PASSED"
    echo "═══════════════════════════════════════════════════════════════════════════════"
    exit 0
else
    echo "  ✗ ITER-154 REGRESSION TEST: $((ITER154_TOTAL_ASSERTIONS_EVALUATED - ITER154_TOTAL_ASSERTIONS_FAILED))/${ITER154_TOTAL_ASSERTIONS_EVALUATED} assertions passed, ${ITER154_TOTAL_ASSERTIONS_FAILED} FAILED"
    echo "═══════════════════════════════════════════════════════════════════════════════"
    exit 1
fi
