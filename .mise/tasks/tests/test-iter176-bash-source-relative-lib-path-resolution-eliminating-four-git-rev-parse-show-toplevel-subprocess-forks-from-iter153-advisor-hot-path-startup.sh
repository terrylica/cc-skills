#!/usr/bin/env bash
#MISE description="Iter-176 regression test pinning the BASH_SOURCE-relative lib-path resolution optimization in iter-153 advisor. Pre-iter-176 the lib-resolve block at file head used FOUR separate dollar-paren-git-rev-parse-show-toplevel command substitutions to resolve absolute paths for the iter-155 JSON escape lib, iter-161 bump classifier lib, iter-162 footer detector lib, and iter-164 next-version resolver lib. Each spawn forked git as a subprocess; empirical measurement on macOS arm64 darwin: approximately 10ms per fork. At 4 forks per advisor invocation that was approximately 40ms of pure subprocess-fork overhead — most of iter-153 pre-iter-176 ~44ms wall-clock median. Critically iter-153 is the only HOT PATH in the toolkit (fires on EVERY git commit via iter-157 commit-msg hook and iter-158 pre-commit framework integration). Iter-176 hoists the BASH_SOURCE-relative own-directory to a single bash parameter expansion (zero subprocess forks — bash builtin string-op) and all 4 shared-lib absolute paths derive from that single anchor. Pattern mirrors iter-172 fix for iter-152. Empirical median wall-clock improvement: 44ms to 21ms approximately 52 percent reduction. Test asserts (a) iter-153 source contains iter-176 top-of-file hot-path optimization doc block, (b) iter-176 BASH_SOURCE-relative anchor variable defined at correct location, (c) all 4 shared-lib paths derive from the iter-176 anchor not from git rev-parse forks, (d) remaining git rev-parse count is exactly 2 (line 288 conditional auto-detect inside iter154 function plus the docstring comment reference at top, the git describe at line 602 is a different command), (e) bash -n passes, (f) shellcheck passes, (g) end-to-end smoke test in default mode produces expected COMMITS ADVISE output, (h) end-to-end --json mode smoke test still emits valid JSON envelope with iter161 bump preview and iter164 next-version preview both present (proving iter-161 + iter-164 shared libs sourced correctly via BASH_SOURCE-relative paths)."
set -euo pipefail

ITER176_REPO_ROOT="${AUDIT_REPO_ROOT_OVERRIDE:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
cd "$ITER176_REPO_ROOT"

ITER176_ITER153_ADVISOR_ABSOLUTE_PATH="$ITER176_REPO_ROOT/scripts/iter153-operator-facing-pre-commit-dry-run-advisor-classifying-proposed-conventional-commit-subject-through-iter82-grammar-and-iter151-overlay-with-human-readable-verdict-default-and-json-output-mode-for-ai-agent-automation-pipeline-consumption.sh"

ITER176_TOTAL_ASSERTIONS_EVALUATED=0
ITER176_TOTAL_ASSERTIONS_FAILED=0

iter176_assert_substring_present_with_human_readable_label() {
    local human_readable_label="$1"
    local expected_substring="$2"
    ITER176_TOTAL_ASSERTIONS_EVALUATED=$((ITER176_TOTAL_ASSERTIONS_EVALUATED + 1))
    if grep -qF "$expected_substring" "$ITER176_ITER153_ADVISOR_ABSOLUTE_PATH"; then
        echo "  ✓ $human_readable_label"
    else
        echo "  ✗ $human_readable_label (substring missing: ${expected_substring:0:80})"
        ITER176_TOTAL_ASSERTIONS_FAILED=$((ITER176_TOTAL_ASSERTIONS_FAILED + 1))
    fi
}

echo ""
echo "═══════════════════════════════════════════════════════════════════════════════"
echo "  ITER-176 BASH_SOURCE-RELATIVE LIB-PATH RESOLUTION REGRESSION TEST"
echo "═══════════════════════════════════════════════════════════════════════════════"

# ─── Group A: iter-153 source contains iter-176 top-of-file doc block ──────
echo ""
echo "GROUP A (3 assertions): iter-153 source documents iter-176 hot-path optimization rationale"

iter176_assert_substring_present_with_human_readable_label \
    "A1: iter-153 contains 'ITER-176 HOT-PATH OPTIMIZATION' banner header" \
    "ITER-176 HOT-PATH OPTIMIZATION"

iter176_assert_substring_present_with_human_readable_label \
    "A2: iter-153 documents the iter-157 commit-msg hot-path provenance (fires on every git commit)" \
    "iter-157 commit-msg hook"

iter176_assert_substring_present_with_human_readable_label \
    "A3: iter-153 documents the iter-172 pattern provenance (BASH_SOURCE-relative path)" \
    "mirrors iter-172"

# ─── Group B: iter-176 anchor variable defined ──────────────────────────────
echo ""
echo "GROUP B (1 assertion): iter-176 BASH_SOURCE-relative anchor variable defined"

iter176_assert_substring_present_with_human_readable_label \
    "B1: iter-176 anchor variable declared with verbose self-explanatory name" \
    "ITER176_ITER153_ADVISOR_SCRIPT_OWN_DIRECTORY_RESOLVED_VIA_BASH_SOURCE_FOR_ZERO_FORK_LIB_PATH_RESOLUTION_ON_HOT_PATH=\"\$(cd \"\$(dirname \"\${BASH_SOURCE[0]}\")\" && pwd)\""

# ─── Group C: all 4 shared-lib paths derive from the iter-176 anchor ───────
echo ""
echo "GROUP C (1 assertion): all 4 shared-lib absolute paths derive from iter-176 anchor (not git rev-parse forks)"

ITER176_TOTAL_ASSERTIONS_EVALUATED=$((ITER176_TOTAL_ASSERTIONS_EVALUATED + 1))
# Single-quoted literal-dollar-sign search string is intentional — we want
# grep to match the literal `$ITER176_…` source-text substring used as a
# bash variable reference in the source file.
# shellcheck disable=SC2016
ITER176_OBSERVED_ANCHOR_CONSUMER_COUNT=$(grep -cF '$ITER176_ITER153_ADVISOR_SCRIPT_OWN_DIRECTORY_RESOLVED_VIA_BASH_SOURCE_FOR_ZERO_FORK_LIB_PATH_RESOLUTION_ON_HOT_PATH/lib/' "$ITER176_ITER153_ADVISOR_ABSOLUTE_PATH")
ITER176_EXPECTED_ANCHOR_CONSUMER_COUNT=4
if (( ITER176_OBSERVED_ANCHOR_CONSUMER_COUNT == ITER176_EXPECTED_ANCHOR_CONSUMER_COUNT )); then
    echo "  ✓ C1: iter-153 contains exactly ${ITER176_OBSERVED_ANCHOR_CONSUMER_COUNT} anchor-derived lib paths (iter-155 JSON escape + iter-161 bump classifier + iter-162 footer detector + iter-164 next-version resolver)"
else
    echo "  ✗ C1: iter-153 contains ${ITER176_OBSERVED_ANCHOR_CONSUMER_COUNT} anchor-derived lib paths (expected ${ITER176_EXPECTED_ANCHOR_CONSUMER_COUNT}: one per shared lib)"
    ITER176_TOTAL_ASSERTIONS_FAILED=$((ITER176_TOTAL_ASSERTIONS_FAILED + 1))
fi

# ─── Group D: count of git rev-parse + git describe fork invocations ───────
echo ""
echo "GROUP D (2 assertions): git rev-parse + git describe fork-invocation counts confirm hot-path reduction"

ITER176_TOTAL_ASSERTIONS_EVALUATED=$((ITER176_TOTAL_ASSERTIONS_EVALUATED + 1))
# Count ACTUAL git rev-parse executions (excludes comment references that
# don't actually execute). Match lines where `git rev-parse` is preceded
# by `$(` (command substitution) AND the line does not begin with optional
# whitespace + `#` (shell comment) — that's the executable form.
ITER176_OBSERVED_GIT_REV_PARSE_EXECUTION_COUNT=$(grep -E '\$\(git rev-parse' "$ITER176_ITER153_ADVISOR_ABSOLUTE_PATH" | grep -cvE '^[[:space:]]*#')
ITER176_EXPECTED_GIT_REV_PARSE_EXECUTION_COUNT=1
if (( ITER176_OBSERVED_GIT_REV_PARSE_EXECUTION_COUNT == ITER176_EXPECTED_GIT_REV_PARSE_EXECUTION_COUNT )); then
    echo "  ✓ D1: iter-153 contains exactly ${ITER176_OBSERVED_GIT_REV_PARSE_EXECUTION_COUNT} executable 'git rev-parse' invocation (conditional auto-detect inside iter154_auto_detect_commit_editmsg_path; lib-resolve block forks ELIMINATED)"
else
    echo "  ✗ D1: iter-153 contains ${ITER176_OBSERVED_GIT_REV_PARSE_EXECUTION_COUNT} executable 'git rev-parse' invocations (expected ${ITER176_EXPECTED_GIT_REV_PARSE_EXECUTION_COUNT}: only conditional auto-detect should remain)"
    ITER176_TOTAL_ASSERTIONS_FAILED=$((ITER176_TOTAL_ASSERTIONS_FAILED + 1))
fi

ITER176_TOTAL_ASSERTIONS_EVALUATED=$((ITER176_TOTAL_ASSERTIONS_EVALUATED + 1))
ITER176_OBSERVED_GIT_DESCRIBE_EXECUTION_COUNT=$(grep -cE '\$\(git describe' "$ITER176_ITER153_ADVISOR_ABSOLUTE_PATH")
ITER176_EXPECTED_GIT_DESCRIBE_EXECUTION_COUNT=1
if (( ITER176_OBSERVED_GIT_DESCRIBE_EXECUTION_COUNT == ITER176_EXPECTED_GIT_DESCRIBE_EXECUTION_COUNT )); then
    echo "  ✓ D2: iter-153 contains exactly ${ITER176_OBSERVED_GIT_DESCRIBE_EXECUTION_COUNT} 'git describe' invocation (iter-164 next-version preview tag-lookup; cannot be replaced with BASH_SOURCE because git tag walk is the actual semantic)"
else
    echo "  ✗ D2: iter-153 contains ${ITER176_OBSERVED_GIT_DESCRIBE_EXECUTION_COUNT} 'git describe' invocations (expected ${ITER176_EXPECTED_GIT_DESCRIBE_EXECUTION_COUNT})"
    ITER176_TOTAL_ASSERTIONS_FAILED=$((ITER176_TOTAL_ASSERTIONS_FAILED + 1))
fi

# ─── Group E: bash -n syntax check + shellcheck ──────────────────────────
echo ""
echo "GROUP E (2 assertions): iter-153 passes bash -n + shellcheck after iter-176 hoist"

ITER176_TOTAL_ASSERTIONS_EVALUATED=$((ITER176_TOTAL_ASSERTIONS_EVALUATED + 1))
if bash -n "$ITER176_ITER153_ADVISOR_ABSOLUTE_PATH" 2>/dev/null; then
    echo "  ✓ E1: iter-153 passes bash -n syntax check after iter-176 hoist"
else
    echo "  ✗ E1: iter-153 FAILS bash -n syntax check after iter-176 hoist"
    ITER176_TOTAL_ASSERTIONS_FAILED=$((ITER176_TOTAL_ASSERTIONS_FAILED + 1))
fi

ITER176_TOTAL_ASSERTIONS_EVALUATED=$((ITER176_TOTAL_ASSERTIONS_EVALUATED + 1))
if command -v shellcheck >/dev/null 2>&1; then
    if shellcheck "$ITER176_ITER153_ADVISOR_ABSOLUTE_PATH" >/dev/null 2>&1; then
        echo "  ✓ E2: iter-153 passes shellcheck zero-warning after iter-176 hoist"
    else
        echo "  ✗ E2: iter-153 has shellcheck warnings after iter-176 hoist"
        ITER176_TOTAL_ASSERTIONS_FAILED=$((ITER176_TOTAL_ASSERTIONS_FAILED + 1))
    fi
else
    echo "  ⊘ E2: shellcheck not installed — SKIPPED (assertion uncounted)"
    ITER176_TOTAL_ASSERTIONS_EVALUATED=$((ITER176_TOTAL_ASSERTIONS_EVALUATED - 1))
fi

# ─── Group F: end-to-end smoke test default-mode + --json mode ──────────
echo ""
echo "GROUP F (3 assertions): end-to-end smoke test default + --json mode prove all 4 shared libs sourced correctly via BASH_SOURCE-relative paths"

ITER176_DEFAULT_MODE_OUTPUT_CAPTURE=$(bash "$ITER176_ITER153_ADVISOR_ABSOLUTE_PATH" -- "feat(iter-176): hot-path probe subject" 2>&1 || true)

ITER176_TOTAL_ASSERTIONS_EVALUATED=$((ITER176_TOTAL_ASSERTIONS_EVALUATED + 1))
if [[ "$ITER176_DEFAULT_MODE_OUTPUT_CAPTURE" == *"COMMITS ADVISE"* ]] && \
   [[ "$ITER176_DEFAULT_MODE_OUTPUT_CAPTURE" == *"classification:"* ]] && \
   [[ "$ITER176_DEFAULT_MODE_OUTPUT_CAPTURE" == *"iter-161 semver-bump preview"* ]] && \
   [[ "$ITER176_DEFAULT_MODE_OUTPUT_CAPTURE" == *"next version:"* ]]; then
    echo "  ✓ F1: default-mode advisor emits classification + iter-161 bump preview + iter-164 next-version preview (all 4 shared libs sourced correctly via BASH_SOURCE-relative paths)"
else
    echo "  ✗ F1: default-mode advisor missing classification or iter-161/iter-164 preview sections — BASH_SOURCE-relative lib-resolve may have broken"
    ITER176_TOTAL_ASSERTIONS_FAILED=$((ITER176_TOTAL_ASSERTIONS_FAILED + 1))
fi

ITER176_JSON_MODE_OUTPUT_CAPTURE=$(bash "$ITER176_ITER153_ADVISOR_ABSOLUTE_PATH" --json -- "feat(iter-176): hot-path probe subject" 2>/dev/null || true)

ITER176_TOTAL_ASSERTIONS_EVALUATED=$((ITER176_TOTAL_ASSERTIONS_EVALUATED + 1))
if [[ "$ITER176_JSON_MODE_OUTPUT_CAPTURE" == *'"classification"'* ]] && \
   [[ "$ITER176_JSON_MODE_OUTPUT_CAPTURE" == *'"iter161_semver_bump_preview"'* ]] && \
   [[ "$ITER176_JSON_MODE_OUTPUT_CAPTURE" == *'"iter164_next_version_preview"'* ]]; then
    echo "  ✓ F2: --json mode envelope contains classification + iter161 bump + iter164 next-version fields (iter-155 JSON-escape lib sourced correctly via BASH_SOURCE)"
else
    echo "  ✗ F2: --json envelope missing one or more expected fields"
    ITER176_TOTAL_ASSERTIONS_FAILED=$((ITER176_TOTAL_ASSERTIONS_FAILED + 1))
fi

# Iter-162 body-footer detector lib loaded check: invoke with --json and a
# multi-line body containing a BREAKING CHANGE footer token; verify the
# JSON reports breaking=true (which only triggers when iter-162 lib was
# loaded successfully).
ITER176_TOTAL_ASSERTIONS_EVALUATED=$((ITER176_TOTAL_ASSERTIONS_EVALUATED + 1))
ITER176_FOOTER_PROBE_TMPFILE=$(mktemp -t iter176-footer-probe.XXXXXX)
trap 'rm -f "$ITER176_FOOTER_PROBE_TMPFILE"' EXIT
printf 'feat(iter-176): hot-path probe\n\nBody text describing the change.\n\nBREAKING CHANGE: this footer is the iter-162 detection probe.\n' > "$ITER176_FOOTER_PROBE_TMPFILE"
ITER176_FOOTER_PROBE_JSON_OUTPUT=$(bash "$ITER176_ITER153_ADVISOR_ABSOLUTE_PATH" --json --message-file "$ITER176_FOOTER_PROBE_TMPFILE" 2>/dev/null || true)
if [[ "$ITER176_FOOTER_PROBE_JSON_OUTPUT" == *'"breaking": true'* ]] || \
   [[ "$ITER176_FOOTER_PROBE_JSON_OUTPUT" == *'"breaking":true'* ]] || \
   [[ "$ITER176_FOOTER_PROBE_JSON_OUTPUT" == *'BREAKING-CHANGE'* ]]; then
    echo "  ✓ F3: iter-162 footer-detector lib loaded correctly via BASH_SOURCE (BREAKING CHANGE footer detected in multi-line body probe)"
else
    echo "  ✗ F3: iter-162 footer-detector lib may not have loaded — BREAKING CHANGE body footer not detected in JSON envelope"
    echo "      (JSON output excerpt: $(echo "$ITER176_FOOTER_PROBE_JSON_OUTPUT" | head -20))"
    ITER176_TOTAL_ASSERTIONS_FAILED=$((ITER176_TOTAL_ASSERTIONS_FAILED + 1))
fi

# ─── Final report ───────────────────────────────────────────────────────────
echo ""
echo "═══════════════════════════════════════════════════════════════════════════════"
if (( ITER176_TOTAL_ASSERTIONS_FAILED == 0 )); then
    echo "  ✓ ITER-176 REGRESSION TEST: ${ITER176_TOTAL_ASSERTIONS_EVALUATED}/${ITER176_TOTAL_ASSERTIONS_EVALUATED} assertions PASSED"
    echo "═══════════════════════════════════════════════════════════════════════════════"
    exit 0
else
    echo "  ✗ ITER-176 REGRESSION TEST: $((ITER176_TOTAL_ASSERTIONS_EVALUATED - ITER176_TOTAL_ASSERTIONS_FAILED))/${ITER176_TOTAL_ASSERTIONS_EVALUATED} assertions passed, ${ITER176_TOTAL_ASSERTIONS_FAILED} FAILED"
    echo "═══════════════════════════════════════════════════════════════════════════════"
    exit 1
fi
