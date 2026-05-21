#!/usr/bin/env bash
#MISE description="Iter-164 regression test pinning the SemVer next-version resolver shared lib + iter-153 advisor integration. Iter-161 surfaces the bump LABEL (MAJOR/MINOR/PATCH/NONE) but stops short of the operator's actual question 'what version number lands?'. Iter-164 closes that gap with a pure-bash resolver applying semver.org §2 increment rules to the current git tag. Asserts (a) iter-164 shared lib structurally valid, (b) all four bump-label increment rules correct (MAJOR resets minor+patch to 0, MINOR resets patch to 0, PATCH increments only patch, NONE emits empty), (c) tag-prefix convention preserved (v-prefix in → v-prefix out, no prefix → no prefix), (d) pre-release suffix per semver.org §11 stripped before parsing (v21.71.0-rc.1 → still bumps base), (e) malformed/missing inputs gracefully fail to empty, (f) iter-153 advisor human-readable output contains 'next version: <current> → <next>' line for conformant subjects, (g) iter-153 advisor --json mode embeds iter164_next_version_preview nested object with stable iter164_schema_version=1 + current_git_tag + next_version + resolution_rationale fields."
set -euo pipefail

ITER164_REPO_ROOT="${AUDIT_REPO_ROOT_OVERRIDE:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
cd "$ITER164_REPO_ROOT"

ITER164_SHARED_LIB_ABSOLUTE_PATH="$ITER164_REPO_ROOT/scripts/lib/iter164-semver-next-version-resolver-applying-iter161-bump-label-to-parsed-major-minor-patch-components-of-current-git-describe-tag-per-semver-org-specification-section-2-increment-rules.sh"
ITER164_ADVISOR_TASK_ABSOLUTE_PATH="$ITER164_REPO_ROOT/.mise/tasks/commits/advise"

ITER164_TOTAL_ASSERTIONS_EVALUATED=0
ITER164_TOTAL_ASSERTIONS_FAILED=0

iter164_assert_truthy_with_human_readable_label() {
    local human_readable_label="$1"
    local truthy_or_falsy_condition_result="$2"
    ITER164_TOTAL_ASSERTIONS_EVALUATED=$((ITER164_TOTAL_ASSERTIONS_EVALUATED + 1))
    if [[ "$truthy_or_falsy_condition_result" == "true" ]]; then
        echo "  ✓ $human_readable_label"
    else
        echo "  ✗ $human_readable_label"
        ITER164_TOTAL_ASSERTIONS_FAILED=$((ITER164_TOTAL_ASSERTIONS_FAILED + 1))
    fi
}

iter164_invoke_resolver_capturing_next_version_string_from_global_output_variable_via_subshell() {
    local current_tag="$1" bump_label="$2"
    bash -c "
        source '$ITER164_SHARED_LIB_ABSOLUTE_PATH'
        iter164_compute_concrete_next_semver_version_string_by_applying_bump_label_to_parsed_components_of_current_git_tag_per_semver_org_specification_section_2_increment_rules '$current_tag' '$bump_label'
        echo \"\$ITER164_RESOLVED_NEXT_SEMVER_VERSION_STRING_AFTER_APPLYING_BUMP_LABEL_TO_CURRENT_TAG\"
    "
}

echo ""
echo "═══════════════════════════════════════════════════════════════════════════════"
echo "  ITER-164 SEMVER-NEXT-VERSION-RESOLVER REGRESSION TEST"
echo "═══════════════════════════════════════════════════════════════════════════════"

# ─── Group A: shared lib structural validity ─────────────────────────────────
echo ""
echo "GROUP A (3 assertions): iter-164 shared lib structurally valid"

ITER164_TOTAL_ASSERTIONS_EVALUATED=$((ITER164_TOTAL_ASSERTIONS_EVALUATED + 1))
if [[ -f "$ITER164_SHARED_LIB_ABSOLUTE_PATH" ]]; then
    echo "  ✓ A1: iter-164 shared lib exists at canonical path"
else
    echo "  ✗ A1: iter-164 shared lib missing"
    ITER164_TOTAL_ASSERTIONS_FAILED=$((ITER164_TOTAL_ASSERTIONS_FAILED + 1))
fi

ITER164_TOTAL_ASSERTIONS_EVALUATED=$((ITER164_TOTAL_ASSERTIONS_EVALUATED + 1))
if bash -n "$ITER164_SHARED_LIB_ABSOLUTE_PATH" 2>/dev/null; then
    echo "  ✓ A2: iter-164 shared lib bash -n syntax check passes"
else
    echo "  ✗ A2: iter-164 shared lib FAILS bash -n syntax check"
    ITER164_TOTAL_ASSERTIONS_FAILED=$((ITER164_TOTAL_ASSERTIONS_FAILED + 1))
fi

ITER164_TOTAL_ASSERTIONS_EVALUATED=$((ITER164_TOTAL_ASSERTIONS_EVALUATED + 1))
if command -v shellcheck >/dev/null 2>&1; then
    if shellcheck "$ITER164_SHARED_LIB_ABSOLUTE_PATH" >/dev/null 2>&1; then
        echo "  ✓ A3: iter-164 shared lib passes shellcheck (zero warnings)"
    else
        echo "  ✗ A3: iter-164 shared lib has shellcheck warnings"
        ITER164_TOTAL_ASSERTIONS_FAILED=$((ITER164_TOTAL_ASSERTIONS_FAILED + 1))
    fi
else
    echo "  ⊘ A3: shellcheck not installed — SKIPPED"
    ITER164_TOTAL_ASSERTIONS_EVALUATED=$((ITER164_TOTAL_ASSERTIONS_EVALUATED - 1))
fi

# ─── Group B: four bump-label increment rules correct (semver.org §2) ───────
echo ""
echo "GROUP B (4 assertions): semver.org §2 increment rules applied correctly per bump label"

ITER164_RESOLVER_RESULT_FOR_MAJOR_BUMP_RESETS_MINOR_AND_PATCH=$(iter164_invoke_resolver_capturing_next_version_string_from_global_output_variable_via_subshell "v21.71.5" "MAJOR")
iter164_assert_truthy_with_human_readable_label \
    "B1: MAJOR bump increments major + RESETS minor and patch to 0 (v21.71.5 → v22.0.0)" \
    "$([[ "$ITER164_RESOLVER_RESULT_FOR_MAJOR_BUMP_RESETS_MINOR_AND_PATCH" == "v22.0.0" ]] && echo true || echo false)"

ITER164_RESOLVER_RESULT_FOR_MINOR_BUMP_RESETS_PATCH=$(iter164_invoke_resolver_capturing_next_version_string_from_global_output_variable_via_subshell "v21.71.5" "MINOR")
iter164_assert_truthy_with_human_readable_label \
    "B2: MINOR bump increments minor + RESETS patch to 0 (v21.71.5 → v21.72.0)" \
    "$([[ "$ITER164_RESOLVER_RESULT_FOR_MINOR_BUMP_RESETS_PATCH" == "v21.72.0" ]] && echo true || echo false)"

ITER164_RESOLVER_RESULT_FOR_PATCH_BUMP_INCREMENTS_PATCH_ONLY=$(iter164_invoke_resolver_capturing_next_version_string_from_global_output_variable_via_subshell "v21.71.5" "PATCH")
iter164_assert_truthy_with_human_readable_label \
    "B3: PATCH bump increments patch only (v21.71.5 → v21.71.6)" \
    "$([[ "$ITER164_RESOLVER_RESULT_FOR_PATCH_BUMP_INCREMENTS_PATCH_ONLY" == "v21.71.6" ]] && echo true || echo false)"

ITER164_RESOLVER_RESULT_FOR_NONE_BUMP_EMITS_EMPTY=$(iter164_invoke_resolver_capturing_next_version_string_from_global_output_variable_via_subshell "v21.71.5" "NONE")
iter164_assert_truthy_with_human_readable_label \
    "B4: NONE bump emits empty next-version string (semantic-release skips, no tag computed)" \
    "$([[ -z "$ITER164_RESOLVER_RESULT_FOR_NONE_BUMP_EMITS_EMPTY" ]] && echo true || echo false)"

# ─── Group C: tag-prefix convention preservation ────────────────────────────
echo ""
echo "GROUP C (2 assertions): tag-prefix convention preserved (matches operator's existing convention)"

ITER164_RESOLVER_RESULT_FOR_V_PREFIX_INPUT_PRESERVES_V_IN_OUTPUT=$(iter164_invoke_resolver_capturing_next_version_string_from_global_output_variable_via_subshell "v1.2.3" "MINOR")
iter164_assert_truthy_with_human_readable_label \
    "C1: 'v'-prefix input preserves 'v' prefix in output (v1.2.3 → v1.3.0)" \
    "$([[ "$ITER164_RESOLVER_RESULT_FOR_V_PREFIX_INPUT_PRESERVES_V_IN_OUTPUT" == "v1.3.0" ]] && echo true || echo false)"

ITER164_RESOLVER_RESULT_FOR_NO_PREFIX_INPUT_KEEPS_NO_PREFIX=$(iter164_invoke_resolver_capturing_next_version_string_from_global_output_variable_via_subshell "1.2.3" "MINOR")
iter164_assert_truthy_with_human_readable_label \
    "C2: no-prefix input keeps no prefix in output (1.2.3 → 1.3.0)" \
    "$([[ "$ITER164_RESOLVER_RESULT_FOR_NO_PREFIX_INPUT_KEEPS_NO_PREFIX" == "1.3.0" ]] && echo true || echo false)"

# ─── Group D: pre-release + build-metadata suffix stripping (semver §10, §11)
echo ""
echo "GROUP D (2 assertions): pre-release and build-metadata suffixes stripped per semver §10 and §11"

ITER164_RESOLVER_RESULT_FOR_PRERELEASE_SUFFIX_STRIPPED=$(iter164_invoke_resolver_capturing_next_version_string_from_global_output_variable_via_subshell "v21.71.0-rc.1" "MINOR")
iter164_assert_truthy_with_human_readable_label \
    "D1: pre-release suffix stripped per semver §11 (v21.71.0-rc.1 → v21.72.0)" \
    "$([[ "$ITER164_RESOLVER_RESULT_FOR_PRERELEASE_SUFFIX_STRIPPED" == "v21.72.0" ]] && echo true || echo false)"

ITER164_RESOLVER_RESULT_FOR_BUILD_METADATA_SUFFIX_STRIPPED=$(iter164_invoke_resolver_capturing_next_version_string_from_global_output_variable_via_subshell "v21.71.0+sha.abc123" "MINOR")
iter164_assert_truthy_with_human_readable_label \
    "D2: build-metadata suffix stripped per semver §10 (v21.71.0+sha.abc123 → v21.72.0)" \
    "$([[ "$ITER164_RESOLVER_RESULT_FOR_BUILD_METADATA_SUFFIX_STRIPPED" == "v21.72.0" ]] && echo true || echo false)"

# ─── Group E: graceful fail on malformed inputs ──────────────────────────────
echo ""
echo "GROUP E (3 assertions): graceful fail to empty on malformed inputs"

ITER164_RESOLVER_RESULT_FOR_EMPTY_TAG_INPUT_EMITS_EMPTY=$(iter164_invoke_resolver_capturing_next_version_string_from_global_output_variable_via_subshell "" "MINOR")
iter164_assert_truthy_with_human_readable_label \
    "E1: empty current-tag input emits empty next-version (no git tag → cannot compute)" \
    "$([[ -z "$ITER164_RESOLVER_RESULT_FOR_EMPTY_TAG_INPUT_EMITS_EMPTY" ]] && echo true || echo false)"

ITER164_RESOLVER_RESULT_FOR_MALFORMED_TAG_EMITS_EMPTY=$(iter164_invoke_resolver_capturing_next_version_string_from_global_output_variable_via_subshell "not-a-semver-string" "MINOR")
iter164_assert_truthy_with_human_readable_label \
    "E2: malformed tag input emits empty next-version (cannot parse MAJOR.MINOR.PATCH)" \
    "$([[ -z "$ITER164_RESOLVER_RESULT_FOR_MALFORMED_TAG_EMITS_EMPTY" ]] && echo true || echo false)"

ITER164_RESOLVER_RESULT_FOR_UNKNOWN_BUMP_LABEL_EMITS_EMPTY=$(iter164_invoke_resolver_capturing_next_version_string_from_global_output_variable_via_subshell "v1.0.0" "WEIRD_LABEL")
iter164_assert_truthy_with_human_readable_label \
    "E3: unknown bump label emits empty next-version (only MAJOR/MINOR/PATCH/NONE accepted)" \
    "$([[ -z "$ITER164_RESOLVER_RESULT_FOR_UNKNOWN_BUMP_LABEL_EMITS_EMPTY" ]] && echo true || echo false)"

# ─── Group F: iter-153 advisor renders next-version line in human output ─────
echo ""
echo "GROUP F (3 assertions): iter-153 advisor renders 'next version' line for each bump label"

ITER164_ADVISOR_HUMAN_OUTPUT_FOR_FEAT=$(bash "$ITER164_ADVISOR_TASK_ABSOLUTE_PATH" -- "feat: add foo" 2>&1 || true)
ITER164_TOTAL_ASSERTIONS_EVALUATED=$((ITER164_TOTAL_ASSERTIONS_EVALUATED + 1))
if [[ "$ITER164_ADVISOR_HUMAN_OUTPUT_FOR_FEAT" =~ next\ version:\ v[0-9]+\.[0-9]+\.[0-9]+\ →\ v[0-9]+\.[0-9]+\.[0-9]+ ]]; then
    echo "  ✓ F1: 'feat:' subject in human mode shows 'next version: vCUR → vNEXT' line"
else
    echo "  ✗ F1: feat subject did not show next-version line in human output"
    ITER164_TOTAL_ASSERTIONS_FAILED=$((ITER164_TOTAL_ASSERTIONS_FAILED + 1))
fi

ITER164_ADVISOR_HUMAN_OUTPUT_FOR_BREAKING=$(bash "$ITER164_ADVISOR_TASK_ABSOLUTE_PATH" -- "feat!: rename" 2>&1 || true)
ITER164_TOTAL_ASSERTIONS_EVALUATED=$((ITER164_TOTAL_ASSERTIONS_EVALUATED + 1))
if [[ "$ITER164_ADVISOR_HUMAN_OUTPUT_FOR_BREAKING" =~ next\ version:\ v[0-9]+\.[0-9]+\.[0-9]+\ →\ v[0-9]+\.0\.0 ]]; then
    echo "  ✓ F2: 'feat!:' subject in human mode shows MAJOR-bump next-version with reset minor+patch (→ vN.0.0)"
else
    echo "  ✗ F2: feat! subject did not show MAJOR-reset next-version pattern"
    ITER164_TOTAL_ASSERTIONS_FAILED=$((ITER164_TOTAL_ASSERTIONS_FAILED + 1))
fi

ITER164_ADVISOR_HUMAN_OUTPUT_FOR_BAD_TYPE=$(bash "$ITER164_ADVISOR_TASK_ABSOLUTE_PATH" -- "not-a-conventional-commit" 2>&1 || true)
ITER164_TOTAL_ASSERTIONS_EVALUATED=$((ITER164_TOTAL_ASSERTIONS_EVALUATED + 1))
if [[ "$ITER164_ADVISOR_HUMAN_OUTPUT_FOR_BAD_TYPE" == *"NO BUMP"* ]] \
   && [[ "$ITER164_ADVISOR_HUMAN_OUTPUT_FOR_BAD_TYPE" != *"next version: v"* ]]; then
    echo "  ✓ F3: NO-BUMP commits do NOT emit concrete next-version line (semantic-release will skip)"
else
    echo "  ✗ F3: NO-BUMP commits incorrectly emitted next-version line"
    ITER164_TOTAL_ASSERTIONS_FAILED=$((ITER164_TOTAL_ASSERTIONS_FAILED + 1))
fi

# ─── Group G: iter-153 --json embeds iter164_next_version_preview object ─────
echo ""
echo "GROUP G (5 assertions): iter-153 --json mode embeds iter164_next_version_preview nested object"

ITER164_ADVISOR_JSON_OUTPUT_FOR_FEAT=$(bash "$ITER164_ADVISOR_TASK_ABSOLUTE_PATH" --json -- "feat: foo" 2>/dev/null || true)

ITER164_TOTAL_ASSERTIONS_EVALUATED=$((ITER164_TOTAL_ASSERTIONS_EVALUATED + 1))
if printf '%s' "$ITER164_ADVISOR_JSON_OUTPUT_FOR_FEAT" | python3 -c 'import json,sys; json.load(sys.stdin)' 2>/dev/null; then
    echo "  ✓ G1: --json output still parses cleanly via independent python3 json.loads after iter-164 extension"
else
    echo "  ✗ G1: --json output does NOT parse cleanly"
    ITER164_TOTAL_ASSERTIONS_FAILED=$((ITER164_TOTAL_ASSERTIONS_FAILED + 1))
fi

ITER164_TOTAL_ASSERTIONS_EVALUATED=$((ITER164_TOTAL_ASSERTIONS_EVALUATED + 1))
if [[ "$ITER164_ADVISOR_JSON_OUTPUT_FOR_FEAT" == *'"iter164_next_version_preview"'* ]]; then
    echo "  ✓ G2: --json output includes iter164_next_version_preview nested field key"
else
    echo "  ✗ G2: iter164_next_version_preview field missing"
    ITER164_TOTAL_ASSERTIONS_FAILED=$((ITER164_TOTAL_ASSERTIONS_FAILED + 1))
fi

ITER164_TOTAL_ASSERTIONS_EVALUATED=$((ITER164_TOTAL_ASSERTIONS_EVALUATED + 1))
if [[ "$ITER164_ADVISOR_JSON_OUTPUT_FOR_FEAT" == *'"iter164_schema_version": 1'* ]]; then
    echo "  ✓ G3: --json preview object emits stable iter164_schema_version=1 (AI-agent consumer contract)"
else
    echo "  ✗ G3: iter164_schema_version field missing or wrong value"
    ITER164_TOTAL_ASSERTIONS_FAILED=$((ITER164_TOTAL_ASSERTIONS_FAILED + 1))
fi

ITER164_TOTAL_ASSERTIONS_EVALUATED=$((ITER164_TOTAL_ASSERTIONS_EVALUATED + 1))
if [[ "$ITER164_ADVISOR_JSON_OUTPUT_FOR_FEAT" == *'"current_git_tag"'* ]] \
   && [[ "$ITER164_ADVISOR_JSON_OUTPUT_FOR_FEAT" == *'"next_version"'* ]] \
   && [[ "$ITER164_ADVISOR_JSON_OUTPUT_FOR_FEAT" == *'"resolution_rationale"'* ]]; then
    echo "  ✓ G4: --json preview object emits canonical three-field schema (current_git_tag + next_version + resolution_rationale)"
else
    echo "  ✗ G4: iter164 preview object missing canonical fields"
    ITER164_TOTAL_ASSERTIONS_FAILED=$((ITER164_TOTAL_ASSERTIONS_FAILED + 1))
fi

# For feat (MINOR), next_version should match pattern vN.M.0 (patch=0 reset).
ITER164_TOTAL_ASSERTIONS_EVALUATED=$((ITER164_TOTAL_ASSERTIONS_EVALUATED + 1))
if [[ "$ITER164_ADVISOR_JSON_OUTPUT_FOR_FEAT" =~ \"next_version\":[[:space:]]*\"v[0-9]+\.[0-9]+\.0\" ]]; then
    echo "  ✓ G5: --json MINOR-bump next_version follows vN.M.0 pattern (patch reset to 0 per semver §2)"
else
    echo "  ✗ G5: MINOR-bump next_version did not reset patch to 0"
    ITER164_TOTAL_ASSERTIONS_FAILED=$((ITER164_TOTAL_ASSERTIONS_FAILED + 1))
fi

# ─── Final report ─────────────────────────────────────────────────────────────
echo ""
echo "═══════════════════════════════════════════════════════════════════════════════"
if (( ITER164_TOTAL_ASSERTIONS_FAILED == 0 )); then
    echo "  ✓ ITER-164 REGRESSION TEST: ${ITER164_TOTAL_ASSERTIONS_EVALUATED}/${ITER164_TOTAL_ASSERTIONS_EVALUATED} assertions PASSED"
    echo "═══════════════════════════════════════════════════════════════════════════════"
    exit 0
else
    echo "  ✗ ITER-164 REGRESSION TEST: $((ITER164_TOTAL_ASSERTIONS_EVALUATED - ITER164_TOTAL_ASSERTIONS_FAILED))/${ITER164_TOTAL_ASSERTIONS_EVALUATED} assertions passed, ${ITER164_TOTAL_ASSERTIONS_FAILED} FAILED"
    echo "═══════════════════════════════════════════════════════════════════════════════"
    exit 1
fi
