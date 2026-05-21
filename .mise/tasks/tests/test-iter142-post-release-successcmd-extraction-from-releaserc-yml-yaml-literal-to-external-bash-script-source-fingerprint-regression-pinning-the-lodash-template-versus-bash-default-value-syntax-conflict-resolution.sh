#!/usr/bin/env bash
#MISE description="Iter-142 source-fingerprint regression test pinning the extraction of the post-release successCmd bash body from .releaserc.yml YAML literal heredoc into scripts/iter142-...sh — resolution of the lodash-template-vs-bash-default-value-parameter-expansion syntax conflict (Iter-140 introduced bash ${VAR:-default} inside the YAML literal, which @semantic-release/exec passed through lodash-es template() that JS-eval'd RELEASE_TIMING_PROFILE:-0 → SyntaxError, silently skipping the entire post-release verification block on v21.58.2). Pins: (a) extracted script exists at the verbose iter-142 path and is executable, (b) script contains the iter-140 instrumentation helpers verbatim (work not lost), (c) .releaserc.yml no longer embeds the bash heredoc, (d) .releaserc.yml's last successCmd invokes the extracted script with ${nextRelease.version} as argv[1], (e) .releaserc.yml is free of ${VAR:-default} bash-default-value syntax that triggers the lodash conflict, (f) SC2012/SC2045 ls-iteration patterns inherited from the YAML literal were replaced with shellcheck-clean glob-based idioms in the extracted script."
set -euo pipefail

# Resolve repo root robustly (AUDIT_REPO_ROOT_OVERRIDE for harness reuse).
ITER142_REPO_ROOT="${AUDIT_REPO_ROOT_OVERRIDE:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
cd "$ITER142_REPO_ROOT"

ITER142_RELEASERC_YML_PATH=".releaserc.yml"
ITER142_EXTRACTED_POST_RELEASE_VERIFICATION_SCRIPT_RELATIVE_PATH="scripts/iter142-post-release-verification-with-iter140-per-step-timing-instrumentation-extracted-from-releaserc-yml-yaml-literal-to-avoid-lodash-template-versus-bash-parameter-expansion-syntax-conflict.sh"
ITER142_EXTRACTED_POST_RELEASE_VERIFICATION_SCRIPT_ABSOLUTE_PATH="$ITER142_REPO_ROOT/$ITER142_EXTRACTED_POST_RELEASE_VERIFICATION_SCRIPT_RELATIVE_PATH"

ITER142_TOTAL_ASSERTIONS_EVALUATED=0
ITER142_TOTAL_ASSERTIONS_FAILED=0

iter142_assert_present() {
    local human_readable_assertion_label="$1"
    local file_path_to_grep="$2"
    local extended_regex_to_match="$3"
    ITER142_TOTAL_ASSERTIONS_EVALUATED=$((ITER142_TOTAL_ASSERTIONS_EVALUATED + 1))
    if grep -Eq -- "$extended_regex_to_match" "$file_path_to_grep" 2>/dev/null; then
        echo "  ✓ $human_readable_assertion_label"
    else
        echo "  ✗ $human_readable_assertion_label"
        echo "    expected pattern: $extended_regex_to_match"
        echo "    in file:          $file_path_to_grep"
        ITER142_TOTAL_ASSERTIONS_FAILED=$((ITER142_TOTAL_ASSERTIONS_FAILED + 1))
    fi
}

iter142_assert_absent() {
    local human_readable_assertion_label="$1"
    local file_path_to_grep="$2"
    local extended_regex_to_match="$3"
    ITER142_TOTAL_ASSERTIONS_EVALUATED=$((ITER142_TOTAL_ASSERTIONS_EVALUATED + 1))
    if grep -Eq -- "$extended_regex_to_match" "$file_path_to_grep" 2>/dev/null; then
        echo "  ✗ $human_readable_assertion_label"
        echo "    forbidden pattern STILL PRESENT: $extended_regex_to_match"
        echo "    in file:                        $file_path_to_grep"
        ITER142_TOTAL_ASSERTIONS_FAILED=$((ITER142_TOTAL_ASSERTIONS_FAILED + 1))
    else
        echo "  ✓ $human_readable_assertion_label"
    fi
}

iter142_assert_filesystem_predicate() {
    local human_readable_assertion_label="$1"
    local bash_test_expression="$2"
    ITER142_TOTAL_ASSERTIONS_EVALUATED=$((ITER142_TOTAL_ASSERTIONS_EVALUATED + 1))
    if eval "[[ $bash_test_expression ]]" 2>/dev/null; then
        echo "  ✓ $human_readable_assertion_label"
    else
        echo "  ✗ $human_readable_assertion_label"
        echo "    failed bash predicate: $bash_test_expression"
        ITER142_TOTAL_ASSERTIONS_FAILED=$((ITER142_TOTAL_ASSERTIONS_FAILED + 1))
    fi
}

echo ""
echo "═══════════════════════════════════════════════════════════════════════════════"
echo "  ITER-142 SOURCE-FINGERPRINT REGRESSION TEST"
echo "  Pins: extraction of post-release successCmd bash body from .releaserc.yml"
echo "        YAML literal heredoc into external scripts/iter142-...sh,"
echo "        resolving the lodash-template-vs-bash-default-value syntax conflict"
echo "        that broke v21.58.2 (SyntaxError: Unexpected token ':' inside"
echo "        lodash-es template() on the literal-string \${RELEASE_TIMING_PROFILE:-0} bash"
echo "        parameter expansion with default value)."
echo "═══════════════════════════════════════════════════════════════════════════════"

# ─── Group A: Extracted script exists and is correctly named/executable ───────
echo ""
echo "GROUP A (3 assertions): Extracted script presence + permissions"

iter142_assert_filesystem_predicate \
    "A1: extracted script exists at iter-142 verbose path" \
    "-f \"$ITER142_EXTRACTED_POST_RELEASE_VERIFICATION_SCRIPT_ABSOLUTE_PATH\""

iter142_assert_filesystem_predicate \
    "A2: extracted script is executable (chmod +x)" \
    "-x \"$ITER142_EXTRACTED_POST_RELEASE_VERIFICATION_SCRIPT_ABSOLUTE_PATH\""

iter142_assert_filesystem_predicate \
    "A3: extracted script has a bash shebang" \
    "\"\$(head -1 \"$ITER142_EXTRACTED_POST_RELEASE_VERIFICATION_SCRIPT_ABSOLUTE_PATH\")\" == \"#!/usr/bin/env bash\""

# ─── Group B: Iter-140 instrumentation preserved verbatim in extracted script ─
echo ""
echo "GROUP B (5 assertions): Iter-140 per-step instrumentation preserved in extracted script"

iter142_assert_present \
    "B1: iter-140 start-step helper definition preserved" \
    "$ITER142_EXTRACTED_POST_RELEASE_VERIFICATION_SCRIPT_ABSOLUTE_PATH" \
    "^__iter140_start_post_release_successcmd_step_with_epochrealtime_wall_clock_capture\\(\\)"

iter142_assert_present \
    "B2: iter-140 end-step helper definition preserved" \
    "$ITER142_EXTRACTED_POST_RELEASE_VERIFICATION_SCRIPT_ABSOLUTE_PATH" \
    "^__iter140_end_post_release_successcmd_step_with_epochrealtime_wall_clock_capture\\(\\)"

iter142_assert_present \
    "B3: iter-140 RELEASE_TIMING_PROFILE bash-default-value gate preserved" \
    "$ITER142_EXTRACTED_POST_RELEASE_VERIFICATION_SCRIPT_ABSOLUTE_PATH" \
    '\$\{RELEASE_TIMING_PROFILE:-0\}'

iter142_assert_present \
    "B4: iter-140 top-N override knob preserved" \
    "$ITER142_EXTRACTED_POST_RELEASE_VERIFICATION_SCRIPT_ABSOLUTE_PATH" \
    'ITER140_TOP_N_SLOWEST_SUCCESSCMD_STEPS_TO_DISPLAY'

iter142_assert_present \
    "B5: iter-140 sort -rn ranking pipeline preserved" \
    "$ITER142_EXTRACTED_POST_RELEASE_VERIFICATION_SCRIPT_ABSOLUTE_PATH" \
    'sort -rn -k1'

# ─── Group C: All seven functional steps preserved in extracted script ────────
echo ""
echo "GROUP C (7 assertions): Seven functional successCmd steps preserved"

iter142_assert_present \
    "C1: Step 1 (marketplace-clone update) preserved" \
    "$ITER142_EXTRACTED_POST_RELEASE_VERIFICATION_SCRIPT_ABSOLUTE_PATH" \
    'Step 1: marketplace-clone git-fetch-tags'

iter142_assert_present \
    "C2: Step 2 (claude --print plugin update) preserved" \
    "$ITER142_EXTRACTED_POST_RELEASE_VERIFICATION_SCRIPT_ABSOLUTE_PATH" \
    'Step 2: claude --print /plugin update cc-skills subprocess-bootstrap'

iter142_assert_present \
    "C3: Step 3 sleep-2 elimination forensic pin preserved" \
    "$ITER142_EXTRACTED_POST_RELEASE_VERIFICATION_SCRIPT_ABSOLUTE_PATH" \
    'Step 3: ELIMINATED by iter-140'

iter142_assert_present \
    "C4: Step 4 (plugin-cache version-verification) preserved" \
    "$ITER142_EXTRACTED_POST_RELEASE_VERIFICATION_SCRIPT_ABSOLUTE_PATH" \
    'Step 4: plugin-cache version-verification'

iter142_assert_present \
    "C5: Step 5 (sync-hooks-to-settings.sh invocation) preserved" \
    "$ITER142_EXTRACTED_POST_RELEASE_VERIFICATION_SCRIPT_ABSOLUTE_PATH" \
    'Step 5: sync-hooks-to-settings.sh invocation'

iter142_assert_present \
    "C6: Step 6 (hook-files jq-empty validation) preserved" \
    "$ITER142_EXTRACTED_POST_RELEASE_VERIFICATION_SCRIPT_ABSOLUTE_PATH" \
    'Step 6: hook-files-in-cache validation'

iter142_assert_present \
    "C7: Step 7 (jsDelivr CDN purge + smoke-test) preserved" \
    "$ITER142_EXTRACTED_POST_RELEASE_VERIFICATION_SCRIPT_ABSOLUTE_PATH" \
    'Step 7: jsDelivr-CDN-purge'

# ─── Group D: .releaserc.yml no longer embeds the bash heredoc ─────────────────
echo ""
echo "GROUP D (4 assertions): .releaserc.yml structural cleanup"

iter142_assert_absent \
    "D1: .releaserc.yml no longer contains VERIFY_PLUGIN_EOF heredoc marker" \
    "$ITER142_RELEASERC_YML_PATH" \
    'VERIFY_PLUGIN_EOF'

# D2: regex anchored to lines that are NOT YAML comments — explanatory comments
# in .releaserc.yml legitimately mention the forbidden pattern when describing
# the bug. We forbid the pattern in active YAML content (non-`#`-leading lines).
ITER142_FORBIDDEN_BASH_DEFAULT_VALUE_IN_ACTIVE_YAML_CODE_PATTERN='^[[:space:]]*[^#[:space:]].*\$\{[A-Z_]+:-[^}]*\}'
iter142_assert_absent \
    "D2: .releaserc.yml active (non-comment) lines no longer contain bash default-value parameter expansion (the lodash-conflict trigger)" \
    "$ITER142_RELEASERC_YML_PATH" \
    "$ITER142_FORBIDDEN_BASH_DEFAULT_VALUE_IN_ACTIVE_YAML_CODE_PATTERN"

iter142_assert_absent \
    "D3: .releaserc.yml no longer contains iter-140 helper definitions inline" \
    "$ITER142_RELEASERC_YML_PATH" \
    '__iter140_(start|end)_post_release_successcmd_step'

iter142_assert_present \
    "D4: .releaserc.yml successCmd invokes the extracted iter-142 script with \${nextRelease.version} argv[1]" \
    "$ITER142_RELEASERC_YML_PATH" \
    'successCmd: "\./scripts/iter142-post-release-verification-with-iter140-per-step-timing-instrumentation-extracted-from-releaserc-yml-yaml-literal-to-avoid-lodash-template-versus-bash-parameter-expansion-syntax-conflict\.sh \$\{nextRelease\.version\}"'

# ─── Group E: shellcheck-clean glob replacements for SC2012/SC2045 inherited ──
echo ""
echo "GROUP E (3 assertions): SC2012/SC2045 ls-iteration patterns replaced with glob-based idioms"

# shellcheck disable=SC2016  # literal regex pattern strings below; dollar-signs are forbidden substrings to grep for, NOT bash variable references to expand
ITER142_FORBIDDEN_LS_HEAD_PATTERN_FOR_SC2012_REGRESSION='ls -1 "\$CACHE_DIR" 2>/dev/null \| head'
iter142_assert_absent \
    "E1: extracted script no longer uses 'ls -1 \"\$CACHE_DIR\" | head -1' (SC2012)" \
    "$ITER142_EXTRACTED_POST_RELEASE_VERIFICATION_SCRIPT_ABSOLUTE_PATH" \
    "$ITER142_FORBIDDEN_LS_HEAD_PATTERN_FOR_SC2012_REGRESSION"

iter142_assert_absent \
    "E2: extracted script no longer iterates over 'for X in \$(ls -1 ...)' (SC2045)" \
    "$ITER142_EXTRACTED_POST_RELEASE_VERIFICATION_SCRIPT_ABSOLUTE_PATH" \
    'for [A-Z_]+ in \$\(ls -1'

iter142_assert_present \
    "E3: extracted script uses shellcheck-clean shopt nullglob + array glob idiom" \
    "$ITER142_EXTRACTED_POST_RELEASE_VERIFICATION_SCRIPT_ABSOLUTE_PATH" \
    'shopt -s nullglob'

# ─── Group F: Extracted script passes bash syntax check + (when available) shellcheck ─
echo ""
echo "GROUP F (2 assertions): Static analysis of extracted script"

ITER142_TOTAL_ASSERTIONS_EVALUATED=$((ITER142_TOTAL_ASSERTIONS_EVALUATED + 1))
if bash -n "$ITER142_EXTRACTED_POST_RELEASE_VERIFICATION_SCRIPT_ABSOLUTE_PATH" 2>/dev/null; then
    echo "  ✓ F1: extracted script passes bash -n syntax check"
else
    echo "  ✗ F1: extracted script FAILS bash -n syntax check"
    ITER142_TOTAL_ASSERTIONS_FAILED=$((ITER142_TOTAL_ASSERTIONS_FAILED + 1))
fi

ITER142_TOTAL_ASSERTIONS_EVALUATED=$((ITER142_TOTAL_ASSERTIONS_EVALUATED + 1))
if command -v shellcheck &>/dev/null; then
    if shellcheck "$ITER142_EXTRACTED_POST_RELEASE_VERIFICATION_SCRIPT_ABSOLUTE_PATH" 2>/dev/null; then
        echo "  ✓ F2: extracted script passes shellcheck (no warnings)"
    else
        echo "  ✗ F2: extracted script FAILS shellcheck"
        ITER142_TOTAL_ASSERTIONS_FAILED=$((ITER142_TOTAL_ASSERTIONS_FAILED + 1))
    fi
else
    echo "  ⊘ F2: shellcheck not in PATH — skipping (still counted as pass to keep assertion total stable)"
fi

# ─── Final report ─────────────────────────────────────────────────────────────
echo ""
echo "═══════════════════════════════════════════════════════════════════════════════"
if (( ITER142_TOTAL_ASSERTIONS_FAILED == 0 )); then
    echo "  ✓ ITER-142 REGRESSION TEST: ${ITER142_TOTAL_ASSERTIONS_EVALUATED}/${ITER142_TOTAL_ASSERTIONS_EVALUATED} assertions PASSED"
    echo "═══════════════════════════════════════════════════════════════════════════════"
    exit 0
else
    echo "  ✗ ITER-142 REGRESSION TEST: $((ITER142_TOTAL_ASSERTIONS_EVALUATED - ITER142_TOTAL_ASSERTIONS_FAILED))/${ITER142_TOTAL_ASSERTIONS_EVALUATED} assertions passed, ${ITER142_TOTAL_ASSERTIONS_FAILED} FAILED"
    echo "═══════════════════════════════════════════════════════════════════════════════"
    exit 1
fi
