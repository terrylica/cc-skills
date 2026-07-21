#!/usr/bin/env bash
#MISE description="Iter-143 source-fingerprint regression test pinning the four community-validated @semantic-release/github plugin config optimizations applied to skip per-commit search-issues API storm and other unused release-comment features. Forensic-pins successComment:false (skip GET /search/issues per-commit PR/issue lookup — documented dominant success-step slowdown in semantic-release/github#542/#867/#2204), failComment:false (skip auto-opening GitHub issue on release failure — cc-skills surfaces failures via iter-139 RELEASE_TIMING_PROFILE local logs), releasedLabels:false (skip applying 'released' label to resolved PRs/issues — cc-skills uses tag-as-SSoT not issue-tagging), addReleases:false (skip injecting 'previous releases' link block — CHANGELOG.md already links inter-version diffs). All four flags are load-bearing for performance; reintroducing any of them would re-add API-call cost. Asserts (a) plugin entry is the array form [name, config] not bare string, (b) all four explicit flags present and set to false, (c) release.config.cjs require()s as a valid semantic-release plugins config. NOTE (2026-07-21): config migrated .releaserc.yml → release.config.cjs so the notes generator can carry a body-preserving writerOpts.transform (a JS function YAML cannot express); this test now loads the JS config via node require() instead of PyYAML."
set -euo pipefail

ITER143_REPO_ROOT="${AUDIT_REPO_ROOT_OVERRIDE:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
cd "$ITER143_REPO_ROOT"

ITER143_RELEASE_CONFIG_PATH="release.config.cjs"

ITER143_TOTAL_ASSERTIONS_EVALUATED=0
ITER143_TOTAL_ASSERTIONS_FAILED=0

# Evaluate a JavaScript predicate against the required release.config.cjs. The
# node snippet resolves the @semantic-release/github plugin entry into `gh`
# (array form [name, config], or bare string), then exits non-zero unless the
# supplied predicate is truthy.
iter143_assert_node_predicate_holds() {
    local human_readable_assertion_label_for_iter143="$1"
    local node_predicate_expression_returning_truthy_when_assertion_holds="$2"
    ITER143_TOTAL_ASSERTIONS_EVALUATED=$((ITER143_TOTAL_ASSERTIONS_EVALUATED + 1))
    local node_evaluation_exit_status=0
    node -e "
const cfg = require('./$ITER143_RELEASE_CONFIG_PATH');
const plugins = cfg.plugins;
let gh = null;
for (const entry of plugins) {
    if (Array.isArray(entry) && entry[0] === '@semantic-release/github') { gh = entry; break; }
    if (typeof entry === 'string' && entry === '@semantic-release/github') { gh = entry; break; }
}
if (!($node_predicate_expression_returning_truthy_when_assertion_holds)) process.exit(1);
" 2>/dev/null || node_evaluation_exit_status=$?
    if [[ "$node_evaluation_exit_status" -eq 0 ]]; then
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
    if grep -Eq -- "$extended_regex_to_match" "$ITER143_RELEASE_CONFIG_PATH" 2>/dev/null; then
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
echo "        (config: release.config.cjs — migrated from .releaserc.yml 2026-07-21)"
echo "═══════════════════════════════════════════════════════════════════════════════"

# ─── Group A: Structural — plugin entry is array form (carries config) ────────
echo ""
echo "GROUP A (2 assertions): @semantic-release/github plugin entry structure"

iter143_assert_node_predicate_holds \
    "A1: @semantic-release/github plugin entry exists in release.config.cjs plugins list" \
    "gh !== null"

iter143_assert_node_predicate_holds \
    "A2: @semantic-release/github plugin entry is array form [name, config] — bare-string form forbidden because it cannot carry the 4 optimization flags" \
    "Array.isArray(gh) && gh.length === 2 && typeof gh[1] === 'object' && gh[1] !== null"

# ─── Group B: Forensic-pin all four community-validated false-flags ──────────
echo ""
echo "GROUP B (4 assertions): Four load-bearing @semantic-release/github optimization flags"

iter143_assert_node_predicate_holds \
    "B1: successComment:false (skip per-resolved-commit GET /search/issues API storm — documented bottleneck in semantic-release/github#542/#867/#2204)" \
    "Array.isArray(gh) && gh[1].successComment === false"

iter143_assert_node_predicate_holds \
    "B2: failComment:false (skip auto-opening GitHub issue on release failure — cc-skills uses iter-139 RELEASE_TIMING_PROFILE local logs instead)" \
    "Array.isArray(gh) && gh[1].failComment === false"

iter143_assert_node_predicate_holds \
    "B3: releasedLabels:false (skip applying 'released' label to resolved PRs/issues — cc-skills uses tag-as-SSoT release tracking)" \
    "Array.isArray(gh) && gh[1].releasedLabels === false"

iter143_assert_node_predicate_holds \
    "B4: addReleases:false (skip injecting 'previous releases' link block — CHANGELOG.md already links inter-version diffs)" \
    "Array.isArray(gh) && gh[1].addReleases === false"

# ─── Group C: Provenance — iter-143 comment block exists explaining the why ──
echo ""
echo "GROUP C (2 assertions): Iter-143 provenance comments retained for future maintainers"

iter143_assert_grep_pattern_present \
    "C1: Iter-143 provenance block references semantic-release/github issue #542 OR #867 OR #2204 (documented bottleneck citations)" \
    "(semantic-release/github#542|semantic-release/github#867|semantic-release/github#2204)"

iter143_assert_grep_pattern_present \
    "C2: Iter-143 provenance block tags all four flags as 'LOAD-BEARING for performance'" \
    "LOAD-BEARING for performance"

# ─── Group D: require round-trip — overall config still loads ─────────────────
echo ""
echo "GROUP D (1 assertion): release.config.cjs require()s as a valid semantic-release plugins config"

iter143_assert_node_predicate_holds \
    "D1: release.config.cjs exports a non-empty plugins list (>= 8 entries)" \
    "Array.isArray(plugins) && plugins.length >= 8"

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
