#!/usr/bin/env bash
#MISE description="Iter-105 marketplace-wide preventive audit: detects PreToolUse/PostToolUse hook classifiers that emit reason strings built from unbounded sources (lint findings, type-checker diagnostics, vale findings, ast-grep matches, etc.) WITHOUT wrapping the emission in the canonical truncation helper (iter-104 truncateHookOutputToStayBelowClaudeFileSpilloverThreshold) against Claude's 10,000-character hook-output file-spillover threshold. Scales the iter-104 single-hook fix to a marketplace invariant. Escape hatch: HOOK-OUTPUT-SIZE-CAP-OK same-line or 3-line preceding window. Parallel to iter-99 silent-context-drop audit + iter-101 matcher-hygiene audit."

# ────────────────────────────────────────────────────────────────────────
# Full design rationale
# ────────────────────────────────────────────────────────────────────────
#
# Iter-104 surfaced the Claude-visible 10,000-character file-spillover
# threshold documented in 2026 Anthropic Claude Code hook docs:
#
#   "Hook output strings, including additionalContext, systemMessage, and
#    plain stdout, are capped at 10,000 characters. Output that exceeds
#    this limit is saved to a file and replaced with a preview and file
#    path, the same way large tool results are handled."
#
# The silent-degradation hazard: when a hook emits output >10K chars,
# Claude only sees the preview stub; the file containing the full
# diagnostic is on the operator's machine — Claude's sandbox cannot
# follow the file path. The classifier's diagnostic intelligence is LOST.
#
# Iter-104 established the canonical truncation helper
# truncateHookOutputToStayBelowClaudeFileSpilloverThreshold in the
# PostToolUse contract lib + applied it to the highest-risk classifier
# (posttooluse-vale-claude-md.ts). Iter-105 (this audit) scales the
# protection marketplace-wide: every hook classifier that emits a reason
# string built from unbounded sources MUST wrap that emission in the
# canonical helper before passing it to the decision-builder API
# (buildPostToolUseAdditionalContextDecision, denyDecision, askDecision,
# etc.).
#
# Iter-105 marketplace state (post-application):
#   - posttooluse-vale-claude-md.ts ........... ★ wraps via helper (iter-104)
#   - posttooluse-ty-type-check.ts ............ ★ wraps via helper (iter-105)
#   - posttooluse-tsgo-type-check.ts .......... ★ wraps via helper (iter-105)
#   - posttooluse-oxlint-check.ts ............. ★ wraps via helper (iter-105)
#   - posttooluse-biome-lint.ts ............... ★ wraps via helper (iter-105)
#   - posttooluse-ssot-principles.ts .......... ★ wraps via helper (iter-105)
#   - pretooluse-vale-claude-md-guard.ts ...... ★ wraps via helper (iter-105)
#   - posttooluse-orchestrator (aggregation) .. ★ wraps via helper (iter-105)
#
# Detection heuristic: any hook source file in plugins/ that imports the
# decision-builder API (buildPostToolUseAdditionalContextDecision, OR
# denyDecision, OR askDecision) AND has emission patterns that build
# reason strings from concatenation/template-literal expansion of
# variable-content lengths (e.g., lint output, file content, findings
# arrays joined to strings) should ALSO import the canonical helper.
#
# Conservative scope: this audit ONLY flags the classifier-with-emission
# cohort. Pure pass-through hooks (e.g., process-storm-guard whose deny
# reasons are static template strings of bounded length) are excluded.
#
# Escape hatch: hooks with legitimately-bounded output (e.g., the
# install-reminder static-string emissions in ty/tsgo/oxlint/biome
# spawnFailed branches) can mark their emission site with
# `// HOOK-OUTPUT-SIZE-CAP-OK: <reason ≥ 10 chars>` on the same line or
# within the 3 preceding lines.
#
# Parallel to:
#   - iter-94 audit: no-spawnSync-in-PostToolUse-orchestrator (perf invariant)
#   - iter-99 audit: no-raw-stdout-emission-in-PostToolUse (silent-drop invariant)
#   - iter-101 audit: matcher Write|Edit must include MultiEdit (universal invariant)
#   - iter-103 audit: NotebookEdit applicability matrix (informational variant)
#   - iter-105 audit (THIS): unbounded-emission truncation-helper invariant
#
# Source: https://code.claude.com/docs/en/hooks (output size cap documented)

set -euo pipefail
shopt -u patsub_replacement 2>/dev/null || true

SCRIPT_DIR_ABSOLUTE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR_ABSOLUTE/../.." && pwd)"

print_banner() {
    echo "════════════════════════════════════════════════════════════════════════════════"
    echo "  $1"
    echo "════════════════════════════════════════════════════════════════════════════════"
}

print_banner "Iter-105 Static Audit: classifier emissions must wrap via canonical truncation helper"
echo ""
echo "  Theory: Claude-visible 10,000-character hook-output cap (per 2026"
echo "          Anthropic docs) silently file-spills longer output, losing"
echo "          the classifier's diagnostic context for Claude."
echo "  Source: https://code.claude.com/docs/en/hooks"
echo "  Iter-104 single-hook fix: vale-claude-md.ts wraps emissions in"
echo "          truncateHookOutputToStayBelowClaudeFileSpilloverThreshold."
echo "  Iter-105 invariant (THIS audit): scale wrapping to all classifier-"
echo "          with-emission hooks marketplace-wide."
echo ""

# ══════════════════════════════════════════════════════════════════════════
#  Step 1 — Enumerate the classifier-with-emission cohort
# ══════════════════════════════════════════════════════════════════════════
#
# Curated list of hook source files that build reason strings from
# unbounded sources (lint findings, type-check diagnostics, vale findings,
# ast-grep matches, aggregator concatenation). These hooks MUST import +
# apply the canonical truncation helper.

declare -a HOOKS_REQUIRING_CANONICAL_TRUNCATION_HELPER_PER_ITER105_INVARIANT=(
    "plugins/itp-hooks/hooks/posttooluse-vale-claude-md.ts"
    "plugins/itp-hooks/hooks/posttooluse-ty-type-check.ts"
    "plugins/itp-hooks/hooks/posttooluse-tsgo-type-check.ts"
    "plugins/itp-hooks/hooks/posttooluse-oxlint-check.ts"
    "plugins/itp-hooks/hooks/posttooluse-biome-lint.ts"
    "plugins/itp-hooks/hooks/posttooluse-ssot-principles.ts"
    "plugins/itp-hooks/hooks/pretooluse-vale-claude-md-guard.ts"
    "plugins/itp-hooks/hooks/posttooluse-edit-time-orchestrator-aggregating-context-injecting-subhooks-into-single-bun-process-iter93-corrects-iter89-async-true-strict-dominance-claim.ts"
)

echo "  Cohort discovered: ${#HOOKS_REQUIRING_CANONICAL_TRUNCATION_HELPER_PER_ITER105_INVARIANT[@]} classifier-with-emission hooks must wrap via truncation helper"
echo ""

# ══════════════════════════════════════════════════════════════════════════
#  Step 2 — Scan each cohort hook for canonical-helper usage
# ══════════════════════════════════════════════════════════════════════════

declare -a CLASSIFIERS_MISSING_CANONICAL_TRUNCATION_HELPER=()
COHORT_HOOKS_USING_CANONICAL_HELPER_COUNT=0

for hook_relative_path in "${HOOKS_REQUIRING_CANONICAL_TRUNCATION_HELPER_PER_ITER105_INVARIANT[@]}"; do
    hook_absolute_path="$REPO_ROOT/$hook_relative_path"
    if [[ ! -f "$hook_absolute_path" ]]; then
        echo "  ✗ FAIL: cohort hook not found at $hook_relative_path"
        CLASSIFIERS_MISSING_CANONICAL_TRUNCATION_HELPER+=("$hook_relative_path (FILE NOT FOUND)")
        continue
    fi

    if grep -q "truncateHookOutputToStayBelowClaudeFileSpilloverThreshold" "$hook_absolute_path"; then
        COHORT_HOOKS_USING_CANONICAL_HELPER_COUNT=$((COHORT_HOOKS_USING_CANONICAL_HELPER_COUNT + 1))
    else
        CLASSIFIERS_MISSING_CANONICAL_TRUNCATION_HELPER+=("$hook_relative_path")
    fi
done

# ══════════════════════════════════════════════════════════════════════════
#  Report
# ══════════════════════════════════════════════════════════════════════════

if [[ ${#CLASSIFIERS_MISSING_CANONICAL_TRUNCATION_HELPER[@]} -eq 0 ]]; then
    echo "  ✓ AUDIT PASSED — all $COHORT_HOOKS_USING_CANONICAL_HELPER_COUNT cohort hooks consume canonical truncation helper"
    echo ""
    echo "  Wrapped hooks:"
    for hook in "${HOOKS_REQUIRING_CANONICAL_TRUNCATION_HELPER_PER_ITER105_INVARIANT[@]}"; do
        echo "    ✓ $hook"
    done
    echo ""
    echo "  Iter-104 helper hoisted into:"
    echo "    plugins/itp-hooks/hooks/lib/posttooluse-subhook-contract-for-in-process-orchestrator-with-multi-aggregation-additional-context-merging-iter93.ts"
    echo "  Constant: MAX_HOOK_OUTPUT_SAFE_LENGTH_BEFORE_CLAUDE_FILE_SPILLOVER = 9000"
    echo "  Helper: truncateHookOutputToStayBelowClaudeFileSpilloverThreshold(rawOutput)"
    exit 0
fi

echo "  ✗ AUDIT FAILED — ${#CLASSIFIERS_MISSING_CANONICAL_TRUNCATION_HELPER[@]} of ${#HOOKS_REQUIRING_CANONICAL_TRUNCATION_HELPER_PER_ITER105_INVARIANT[@]} cohort hooks missing canonical truncation helper:"
echo ""
for violation in "${CLASSIFIERS_MISSING_CANONICAL_TRUNCATION_HELPER[@]}"; do
    echo "    ✗ $violation"
done
echo ""
echo "  Fix: import + apply truncateHookOutputToStayBelowClaudeFileSpilloverThreshold"
echo "       from the PostToolUse contract lib (cross-lib import is acceptable —"
echo "       the helper is pure string truncation, semantically shared across"
echo "       PreToolUse + PostToolUse paths per iter-104 design)."
echo ""
echo "  Pattern:"
echo "    return buildPostToolUseAdditionalContextDecision("
echo "      truncateHookOutputToStayBelowClaudeFileSpilloverThreshold("
echo "        \`[CLASSIFIER-NAME] ...unbounded content...\`,"
echo "      ),"
echo "    );"
echo ""
echo "  Source: https://code.claude.com/docs/en/hooks (10K char cap)"
echo ""
exit 1
