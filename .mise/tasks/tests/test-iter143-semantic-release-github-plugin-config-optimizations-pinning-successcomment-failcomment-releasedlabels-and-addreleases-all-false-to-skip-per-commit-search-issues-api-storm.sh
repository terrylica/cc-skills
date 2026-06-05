#!/usr/bin/env bash
#MISE description="Iter-143 source-fingerprint regression test pinning the four community-validated @semantic-release/github plugin config optimizations applied to skip per-commit search-issues API storm and other unused release-comment features. Forensic-pins successComment:false (skip GET /search/issues per-commit PR/issue lookup — documented dominant success-step slowdown in semantic-release/github#542/#867/#2204), failComment:false (skip auto-opening GitHub issue on release failure — cc-skills surfaces failures via iter-139 RELEASE_TIMING_PROFILE local logs), releasedLabels:false (skip applying 'released' label to resolved PRs/issues — cc-skills uses tag-as-SSoT not issue-tagging), addReleases:false (skip injecting 'previous releases' link block — CHANGELOG.md already links inter-version diffs). All four flags are load-bearing for performance; reintroducing any of them would re-add API-call cost. Asserts (a) plugin entry is the array form [name, config] not bare string, (b) all four explicit flags present and set to false, (c) YAML parses as valid semantic-release plugins config."
set -euo pipefail

ITER143_REPO_ROOT="${AUDIT_REPO_ROOT_OVERRIDE:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
cd "$ITER143_REPO_ROOT"

ITER143_RELEASERC_YML_PATH=".releaserc.yml"

ITER143_TOTAL_ASSERTIONS_EVALUATED=0
ITER143_TOTAL_ASSERTIONS_FAILED=0

iter143_assert_yaml_python_predicate_holds() {
    local human_readable_assertion_label_for_iter143="$1"
    local python_predicate_expression_returning_truthy_when_assertion_holds="$2"
    ITER143_TOTAL_ASSERTIONS_EVALUATED=$((ITER143_TOTAL_ASSERTIONS_EVALUATED + 1))
    local python_evaluation_exit_status=0
    # 2026-06-05: parse via `uv run --python 3.14 --with pyyaml` — the system
    # `python3` (3.13) has no PyYAML, so a bare `python3 -c "import yaml"`
    # false-negatives every assertion here. Honors the Python-3.14-only
    # directive + mirrors the repo-canonical uv pattern
    # (plugins/pushover-commander/CLAUDE.md). Do NOT revert to bare python3.
    uv run --python 3.14 --with pyyaml python -c "
import yaml, sys
plugins_config_loaded_from_releaserc_yml = yaml.safe_load(open('$ITER143_RELEASERC_YML_PATH'))['plugins']
github_plugin_entry_from_releaserc_yml_plugin_list = None
for plugin_entry in plugins_config_loaded_from_releaserc_yml:
    if isinstance(plugin_entry, list) and plugin_entry[0] == '@semantic-release/github':
        github_plugin_entry_from_releaserc_yml_plugin_list = plugin_entry
        break
    if isinstance(plugin_entry, str) and plugin_entry == '@semantic-release/github':
        # Bare string form — iter-143 regression catches this: must be array form to carry config.
        github_plugin_entry_from_releaserc_yml_plugin_list = plugin_entry
        break
if not ($python_predicate_expression_returning_truthy_when_assertion_holds):
    sys.exit(1)
" 2>/dev/null || python_evaluation_exit_status=$?
    if [[ "$python_evaluation_exit_status" -eq 0 ]]; then
        echo "  ✓ $human_readable_assertion_label_for_iter143"
    else
        echo "  ✗ $human_readable_assertion_label_for_iter143"
        ITER143_TOTAL_ASSERTIONS_FAILED=$((ITER143_TOTAL_ASSERTIONS_FAILED + 1))
    fi
}

iter143_assert_grep_pattern_present() {
    local human_readable_assertion_label_for_iter143="$1"
    local extended_regex_to_match="$2"
    ITER143_TOTAL_ASSERTIONS_EVALUATED=$((ITER143_TOTAL_ASSERTIONS_EVALUATED + 1))
    if grep -Eq -- "$extended_regex_to_match" "$ITER143_RELEASERC_YML_PATH" 2>/dev/null; then
        echo "  ✓ $human_readable_assertion_label_for_iter143"
    else
        echo "  ✗ $human_readable_assertion_label_for_iter143"
        echo "    expected pattern: $extended_regex_to_match"
        ITER143_TOTAL_ASSERTIONS_FAILED=$((ITER143_TOTAL_ASSERTIONS_FAILED + 1))
    fi
}

echo ""
echo "═══════════════════════════════════════════════════════════════════════════════"
echo "  ITER-143 SOURCE-FINGERPRINT REGRESSION TEST"
echo "  Pins: @semantic-release/github plugin config optimizations forbidding"
echo "        per-commit GET /search/issues API storm + 3 other unused features."
echo "        All 4 flags are load-bearing; reintroducing any silently re-adds"
echo "        the documented Phase 2 wall-clock cost."
echo "═══════════════════════════════════════════════════════════════════════════════"

# ─── Group A: Structural — plugin entry is array form (carries config) ────────
echo ""
echo "GROUP A (2 assertions): @semantic-release/github plugin entry structure"

iter143_assert_yaml_python_predicate_holds \
    "A1: @semantic-release/github plugin entry exists in .releaserc.yml plugins list" \
    "github_plugin_entry_from_releaserc_yml_plugin_list is not None"

iter143_assert_yaml_python_predicate_holds \
    "A2: @semantic-release/github plugin entry is array form [name, config] — bare-string form forbidden because it cannot carry the 4 optimization flags" \
    "isinstance(github_plugin_entry_from_releaserc_yml_plugin_list, list) and len(github_plugin_entry_from_releaserc_yml_plugin_list) == 2 and isinstance(github_plugin_entry_from_releaserc_yml_plugin_list[1], dict)"

# ─── Group B: Forensic-pin all four community-validated false-flags ──────────
echo ""
echo "GROUP B (4 assertions): Four load-bearing @semantic-release/github optimization flags"

iter143_assert_yaml_python_predicate_holds \
    "B1: successComment:false (skip per-resolved-commit GET /search/issues API storm — documented bottleneck in semantic-release/github#542/#867/#2204)" \
    "isinstance(github_plugin_entry_from_releaserc_yml_plugin_list, list) and github_plugin_entry_from_releaserc_yml_plugin_list[1].get('successComment') is False"

iter143_assert_yaml_python_predicate_holds \
    "B2: failComment:false (skip auto-opening GitHub issue on release failure — cc-skills uses iter-139 RELEASE_TIMING_PROFILE local logs instead)" \
    "isinstance(github_plugin_entry_from_releaserc_yml_plugin_list, list) and github_plugin_entry_from_releaserc_yml_plugin_list[1].get('failComment') is False"

iter143_assert_yaml_python_predicate_holds \
    "B3: releasedLabels:false (skip applying 'released' label to resolved PRs/issues — cc-skills uses tag-as-SSoT release tracking)" \
    "isinstance(github_plugin_entry_from_releaserc_yml_plugin_list, list) and github_plugin_entry_from_releaserc_yml_plugin_list[1].get('releasedLabels') is False"

iter143_assert_yaml_python_predicate_holds \
    "B4: addReleases:false (skip injecting 'previous releases' link block — CHANGELOG.md already links inter-version diffs)" \
    "isinstance(github_plugin_entry_from_releaserc_yml_plugin_list, list) and github_plugin_entry_from_releaserc_yml_plugin_list[1].get('addReleases') is False"

# ─── Group C: Provenance — iter-143 comment block exists explaining the why ──
echo ""
echo "GROUP C (2 assertions): Iter-143 provenance comments retained for future maintainers"

iter143_assert_grep_pattern_present \
    "C1: Iter-143 provenance block references semantic-release/github issue #542 OR #867 OR #2204 (documented bottleneck citations)" \
    "(semantic-release/github#542|semantic-release/github#867|semantic-release/github#2204)"

iter143_assert_grep_pattern_present \
    "C2: Iter-143 provenance block tags all four flags as 'LOAD-BEARING for performance'" \
    "LOAD-BEARING for performance"

# ─── Group D: YAML round-trip — overall config still parses ───────────────────
echo ""
echo "GROUP D (1 assertion): YAML parses as valid semantic-release plugins config"

iter143_assert_yaml_python_predicate_holds \
    "D1: .releaserc.yml parses as valid YAML with non-empty plugins list" \
    "isinstance(plugins_config_loaded_from_releaserc_yml, list) and len(plugins_config_loaded_from_releaserc_yml) >= 8"

# ─── Final report ─────────────────────────────────────────────────────────────
echo ""
echo "═══════════════════════════════════════════════════════════════════════════════"
if (( ITER143_TOTAL_ASSERTIONS_FAILED == 0 )); then
    echo "  ✓ ITER-143 REGRESSION TEST: ${ITER143_TOTAL_ASSERTIONS_EVALUATED}/${ITER143_TOTAL_ASSERTIONS_EVALUATED} assertions PASSED"
    echo "═══════════════════════════════════════════════════════════════════════════════"
    exit 0
else
    echo "  ✗ ITER-143 REGRESSION TEST: $((ITER143_TOTAL_ASSERTIONS_EVALUATED - ITER143_TOTAL_ASSERTIONS_FAILED))/${ITER143_TOTAL_ASSERTIONS_EVALUATED} assertions passed, ${ITER143_TOTAL_ASSERTIONS_FAILED} FAILED"
    echo "═══════════════════════════════════════════════════════════════════════════════"
    exit 1
fi
