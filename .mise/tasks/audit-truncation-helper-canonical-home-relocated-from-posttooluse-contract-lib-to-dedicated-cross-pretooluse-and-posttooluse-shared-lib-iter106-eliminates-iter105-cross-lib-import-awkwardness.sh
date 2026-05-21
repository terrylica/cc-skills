#!/usr/bin/env bash
#MISE description="Iter-106 audit: verifies the iter-104/iter-105 truncation helper has been relocated to its iter-106 canonical home (a dedicated cross-Pre/PostToolUse shared lib, eliminating the iter-105 cross-lib import awkwardness where pretooluse-vale-claude-md-guard imported from the PostToolUse contract lib). Verifies (1) the iter-106 shared-lib file exists and holds the literal exports; (2) the PostToolUse contract lib re-exports for backward compat; (3) all 8 iter-105 cohort hooks import the helper from the shared-lib canonical home (NOT from the PostToolUse contract lib)."

# ────────────────────────────────────────────────────────────────────────
# Full design rationale
# ────────────────────────────────────────────────────────────────────────
#
# Iter-104 introduced the canonical truncation helper inside the PostToolUse
# contract lib because the FIRST adopter was a PostToolUse classifier
# (posttooluse-vale-claude-md.ts). Iter-105 scaled the helper marketplace-wide
# to 8 cohort hooks — including ONE PreToolUse classifier (pretooluse-vale-
# claude-md-guard.ts), creating an awkward cross-lib import pattern: a
# PreToolUse hook importing from a PostToolUse contract lib.
#
# Iter-106 relocates the canonical home of the helper + threshold constant +
# truncation-marker suffix to a dedicated cross-Pre/PostToolUse shared lib:
#
#   plugins/itp-hooks/hooks/lib/shared-truncation-helper-against-claude-file-
#   spillover-threshold-cross-pretooluse-and-posttooluse-iter106.ts
#
# Backward compat is preserved by transitive re-exports from the PostToolUse
# contract lib (so external audit tasks, regression tests, and documentation
# references to the original iter-104 import-source continue to work). All 8
# iter-105 cohort hooks have been migrated to import the helper directly from
# the iter-106 canonical home — eliminating the cross-lib import pattern AND
# making the helper's semantic home (cross-cutting, neither Pre nor Post
# specific) unambiguous in the source code.
#
# This audit enforces the iter-106 canonical-home invariant:
#   - the shared-lib file exists at the documented path
#   - it holds the literal `export const` / `export function` definitions
#     (not just re-exports)
#   - all 8 cohort hooks import the helper from the shared-lib path
#     (NOT from the PostToolUse contract lib, even though backward-compat
#     re-exports remain available)
#
# Parallel to:
#   - iter-99 audit: no-raw-stdout-emission-in-PostToolUse (silent-drop invariant)
#   - iter-101 audit: matcher Write|Edit must include MultiEdit (universal invariant)
#   - iter-103 audit: NotebookEdit applicability matrix (informational variant)
#   - iter-105 audit: unbounded-emission truncation-helper invariant
#   - iter-106 audit (THIS): canonical-home invariant for the truncation helper

set -euo pipefail
shopt -u patsub_replacement 2>/dev/null || true

SCRIPT_DIR_ABSOLUTE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR_ABSOLUTE/../.." && pwd)"

print_banner() {
    echo "════════════════════════════════════════════════════════════════════════════════"
    echo "  $1"
    echo "════════════════════════════════════════════════════════════════════════════════"
}

print_banner "Iter-106 Audit: truncation helper canonical home is the dedicated cross-Pre/PostToolUse shared lib"
echo ""
echo "  Theory: iter-105 cross-lib import (PreToolUse classifier importing from"
echo "          PostToolUse contract lib) was a known iter-105-era pragmatism;"
echo "          iter-106 eliminates it by establishing a dedicated shared lib"
echo "          as the canonical home for cross-Pre/PostToolUse helpers."
echo ""

SHARED_LIB_RELATIVE_PATH="plugins/itp-hooks/hooks/lib/shared-truncation-helper-against-claude-file-spillover-threshold-cross-pretooluse-and-posttooluse-iter106.ts"
SHARED_LIB_ABSOLUTE_PATH="$REPO_ROOT/$SHARED_LIB_RELATIVE_PATH"
POSTTOOLUSE_CONTRACT_LIB_RELATIVE_PATH="plugins/itp-hooks/hooks/lib/posttooluse-subhook-contract-for-in-process-orchestrator-with-multi-aggregation-additional-context-merging-iter93.ts"
POSTTOOLUSE_CONTRACT_LIB_ABSOLUTE_PATH="$REPO_ROOT/$POSTTOOLUSE_CONTRACT_LIB_RELATIVE_PATH"

# ══════════════════════════════════════════════════════════════════════════
#  Step 1 — Verify the iter-106 shared-lib file exists and holds the
#  literal exports (the canonical home, not just re-exports)
# ══════════════════════════════════════════════════════════════════════════

if [[ ! -f "$SHARED_LIB_ABSOLUTE_PATH" ]]; then
    echo "  ✗ AUDIT FAILED — iter-106 shared-lib file not found at:"
    echo "      $SHARED_LIB_RELATIVE_PATH"
    exit 1
fi

if ! grep -qE "^export const MAX_HOOK_OUTPUT_SAFE_LENGTH_BEFORE_CLAUDE_FILE_SPILLOVER" "$SHARED_LIB_ABSOLUTE_PATH"; then
    echo "  ✗ AUDIT FAILED — iter-106 shared-lib does NOT hold the literal"
    echo "    'export const MAX_HOOK_OUTPUT_SAFE_LENGTH_BEFORE_CLAUDE_FILE_SPILLOVER' definition."
    exit 1
fi

if ! grep -qE "^export function truncateHookOutputToStayBelowClaudeFileSpilloverThreshold" "$SHARED_LIB_ABSOLUTE_PATH"; then
    echo "  ✗ AUDIT FAILED — iter-106 shared-lib does NOT hold the literal"
    echo "    'export function truncateHookOutputToStayBelowClaudeFileSpilloverThreshold' definition."
    exit 1
fi

echo "  ✓ Step 1: iter-106 shared-lib exists and holds the literal canonical definitions"

# ══════════════════════════════════════════════════════════════════════════
#  Step 2 — Verify the PostToolUse contract lib re-exports for backward
#  compatibility (so iter-104-era external references continue to work)
# ══════════════════════════════════════════════════════════════════════════

# The PostToolUse contract lib should have `export { ... } from "./shared-truncation-helper-..."`
# rather than `export const ...` / `export function ...` for the three symbols.
if ! grep -q 'truncateHookOutputToStayBelowClaudeFileSpilloverThreshold' "$POSTTOOLUSE_CONTRACT_LIB_ABSOLUTE_PATH"; then
    echo "  ✗ AUDIT FAILED — PostToolUse contract lib does NOT re-export the truncation helper"
    echo "    (backward-compat break for iter-104-era external consumers)."
    exit 1
fi

if ! grep -q 'from "./shared-truncation-helper-against-claude-file-spillover-threshold-cross-pretooluse-and-posttooluse-iter106' "$POSTTOOLUSE_CONTRACT_LIB_ABSOLUTE_PATH"; then
    echo "  ✗ AUDIT FAILED — PostToolUse contract lib does NOT re-export FROM the iter-106 shared lib"
    echo "    (the re-export must transitively delegate to the canonical home)."
    exit 1
fi

# Conversely, the PostToolUse contract lib must NOT still hold the literal
# `export const MAX_HOOK_OUTPUT_SAFE_LENGTH_BEFORE_CLAUDE_FILE_SPILLOVER` —
# that would mean iter-106 created a duplicate definition.
if grep -qE "^export const MAX_HOOK_OUTPUT_SAFE_LENGTH_BEFORE_CLAUDE_FILE_SPILLOVER" "$POSTTOOLUSE_CONTRACT_LIB_ABSOLUTE_PATH"; then
    echo "  ✗ AUDIT FAILED — PostToolUse contract lib STILL holds the literal"
    echo "    'export const MAX_HOOK_OUTPUT_SAFE_LENGTH_BEFORE_CLAUDE_FILE_SPILLOVER' definition."
    echo "    Iter-106 requires this to be a re-export, not a duplicate definition."
    exit 1
fi

echo "  ✓ Step 2: PostToolUse contract lib re-exports from iter-106 shared lib (backward compat preserved, no duplicate definitions)"

# ══════════════════════════════════════════════════════════════════════════
#  Step 3 — Verify all 8 iter-105 cohort hooks import the helper from the
#  iter-106 shared-lib canonical home (NOT from the PostToolUse contract lib)
# ══════════════════════════════════════════════════════════════════════════

declare -a EIGHT_COHORT_HOOK_RELATIVE_PATHS=(
    "plugins/itp-hooks/hooks/posttooluse-vale-claude-md.ts"
    "plugins/itp-hooks/hooks/posttooluse-ty-type-check.ts"
    "plugins/itp-hooks/hooks/posttooluse-tsgo-type-check.ts"
    "plugins/itp-hooks/hooks/posttooluse-oxlint-check.ts"
    "plugins/itp-hooks/hooks/posttooluse-biome-lint.ts"
    "plugins/itp-hooks/hooks/posttooluse-ssot-principles.ts"
    "plugins/itp-hooks/hooks/pretooluse-vale-claude-md-guard.ts"
    "plugins/itp-hooks/hooks/posttooluse-edit-time-orchestrator-aggregating-context-injecting-subhooks-into-single-bun-process-iter93-corrects-iter89-async-true-strict-dominance-claim.ts"
)

declare -a COHORT_HOOKS_MISSING_DIRECT_SHARED_LIB_IMPORT=()
COHORT_HOOKS_WITH_DIRECT_SHARED_LIB_IMPORT_COUNT=0

for cohort_hook_relative_path in "${EIGHT_COHORT_HOOK_RELATIVE_PATHS[@]}"; do
    cohort_hook_absolute_path="$REPO_ROOT/$cohort_hook_relative_path"
    if [[ ! -f "$cohort_hook_absolute_path" ]]; then
        COHORT_HOOKS_MISSING_DIRECT_SHARED_LIB_IMPORT+=("$cohort_hook_relative_path (FILE NOT FOUND)")
        continue
    fi
    # Each cohort hook MUST import `truncateHookOutputToStayBelowClaudeFileSpilloverThreshold`
    # from the iter-106 shared-lib path. The single-line import grep is robust:
    if grep -qE 'truncateHookOutputToStayBelowClaudeFileSpilloverThreshold.*from "\./lib/shared-truncation-helper-against-claude-file-spillover-threshold-cross-pretooluse-and-posttooluse-iter106' "$cohort_hook_absolute_path"; then
        COHORT_HOOKS_WITH_DIRECT_SHARED_LIB_IMPORT_COUNT=$((COHORT_HOOKS_WITH_DIRECT_SHARED_LIB_IMPORT_COUNT + 1))
        continue
    fi
    # Otherwise, check if the helper is imported via a separate import line
    # from the shared lib (covers the multi-line { ... } from "..." style).
    helper_imported_from_shared_lib=$(awk '
        /truncateHookOutputToStayBelowClaudeFileSpilloverThreshold/ { in_block=1 }
        in_block && /from .*shared-truncation-helper-against-claude-file-spillover-threshold-cross-pretooluse-and-posttooluse-iter106/ {
            print "YES"; exit
        }
        /^[^/]*from "/ { in_block=0 }
        END { if (!found) print "" }
    ' "$cohort_hook_absolute_path")
    if [[ "$helper_imported_from_shared_lib" == "YES" ]]; then
        COHORT_HOOKS_WITH_DIRECT_SHARED_LIB_IMPORT_COUNT=$((COHORT_HOOKS_WITH_DIRECT_SHARED_LIB_IMPORT_COUNT + 1))
    else
        COHORT_HOOKS_MISSING_DIRECT_SHARED_LIB_IMPORT+=("$cohort_hook_relative_path")
    fi
done

if [[ ${#COHORT_HOOKS_MISSING_DIRECT_SHARED_LIB_IMPORT[@]} -eq 0 ]]; then
    echo "  ✓ Step 3: all 8 cohort hooks import the helper directly from the iter-106 shared-lib canonical home"
    echo ""
    echo "  ✓ AUDIT PASSED — iter-106 canonical-home invariant established"
    echo ""
    echo "  Iter-106 shared-lib canonical home:"
    echo "    $SHARED_LIB_RELATIVE_PATH"
    echo "  Re-export (backward compat) from:"
    echo "    $POSTTOOLUSE_CONTRACT_LIB_RELATIVE_PATH"
    echo ""
    echo "  Cohort hooks (8/8) importing directly from canonical home:"
    for cohort_hook in "${EIGHT_COHORT_HOOK_RELATIVE_PATHS[@]}"; do
        echo "    ✓ $cohort_hook"
    done
    exit 0
fi

echo "  ✗ Step 3: ${#COHORT_HOOKS_MISSING_DIRECT_SHARED_LIB_IMPORT[@]} of ${#EIGHT_COHORT_HOOK_RELATIVE_PATHS[@]} cohort hooks do NOT import from the iter-106 shared-lib canonical home:"
echo ""
for violation in "${COHORT_HOOKS_MISSING_DIRECT_SHARED_LIB_IMPORT[@]}"; do
    echo "    ✗ $violation"
done
echo ""
echo "  Fix: import truncateHookOutputToStayBelowClaudeFileSpilloverThreshold from"
echo "       ./lib/shared-truncation-helper-against-claude-file-spillover-threshold-cross-pretooluse-and-posttooluse-iter106.ts"
echo "       NOT from ./lib/posttooluse-subhook-contract-for-in-process-orchestrator-..."
echo "       (the iter-106 canonical home is the dedicated shared lib; PostToolUse"
echo "       contract lib re-exports remain available for backward compat but new"
echo "       code should import from the canonical home directly)."
echo ""
exit 1
