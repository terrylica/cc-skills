#!/usr/bin/env bash
#MISE description="Iter-107 marketplace-wide informational inventory audit: enumerates hand-rolled escape-hatch-marker detection patterns across plugins/itp-hooks/hooks/ source files and reports which hooks would benefit from migrating to the iter-107 canonical shared helper (lib/shared-escape-hatch-marker-detection-helper-cross-pretooluse-and-posttooluse-iter107.ts). Informational by default — future iters may promote to --strict once all migrations land."

# ────────────────────────────────────────────────────────────────────────
# Full design rationale
# ────────────────────────────────────────────────────────────────────────
#
# Marketplace state pre-iter-107: each hook with an escape-hatch comment
# rolled its own detection logic — a regex literal (varying grammar) plus
# (for window-scoped variants) a hand-coded preceding-window lookup loop.
# Web research (2026 Anthropic Claude Code hook docs + Anthropic GitHub
# issue #20259 + community-validated patterns) confirmed there is NO
# official Claude Code escape-hatch convention; each hook author defines
# their own. The marketplace inherits the resulting drift:
#
#   - Some markers require a ≥10-char reason (LAYER3-STRIPPED-PATH-OK,
#     HOOK-OUTPUT-SIZE-CAP-OK); others accept bare `-OK` (most others)
#   - Some scope file-wide (FILE-SIZE-OK, BASH-LAUNCHD-OK, SSoT-OK);
#     others scope per-line with a preceding-N-lines window (LAYER3-...);
#     one scopes same-line-only (INLINE-IGNORE-OK)
#   - Comment-style support varies (#, //, <!-- --> — only some hooks
#     handle the HTML variant for plist files)
#
# Iter-107 establishes the canonical shared helper that supports all 3
# window-semantics modes + optional reason policy + comment-style-
# agnostic substring matching (the UPPER-KEBAB-CASE marker convention
# never collides with code identifiers, so substring match is safe).
#
# This audit:
#   1. Discovers every hook source file with an `ESCAPE_HATCH` constant
#      or a marker-regex literal (`/[A-Z][A-Z0-9-]+-OK/`)
#   2. Reports which hooks have ALREADY migrated to the shared helper
#      (via `from "./lib/shared-escape-hatch-marker-detection-helper-..."`
#      import)
#   3. Reports which hooks still use hand-rolled detection and would
#      benefit from migration
#
# Informational — never blocks release.
#
# Parallel to:
#   - iter-99 audit: raw-stdout-emission silent-drop (PostToolUse invariant)
#   - iter-101 audit: matcher-hygiene (Write|Edit|MultiEdit invariant)
#   - iter-103 audit: NotebookEdit applicability matrix
#   - iter-105 audit: unbounded-emission truncation-helper invariant
#   - iter-106 audit: truncation-helper canonical-home invariant
#   - iter-107 audit (THIS): escape-hatch-marker hand-rolled detection inventory

set -euo pipefail
shopt -u patsub_replacement 2>/dev/null || true

SCRIPT_DIR_ABSOLUTE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR_ABSOLUTE/../.." && pwd)"
ITP_HOOKS_SOURCE_DIRECTORY="$REPO_ROOT/plugins/itp-hooks/hooks"
ITER107_SHARED_HELPER_RELATIVE_IMPORT_PATH="./lib/shared-escape-hatch-marker-detection-helper-cross-pretooluse-and-posttooluse-iter107.ts"

print_banner() {
    echo "════════════════════════════════════════════════════════════════════════════════"
    echo "  $1"
    echo "════════════════════════════════════════════════════════════════════════════════"
}

print_banner "Iter-107 marketplace-wide escape-hatch-marker detection inventory"
echo ""
echo "  Theory: marketplace pre-iter-107 had no shared escape-hatch detection"
echo "          helper; each hook rolled its own regex + window-lookup loop."
echo "          Iter-107 establishes the canonical shared helper at:"
echo "            $ITER107_SHARED_HELPER_RELATIVE_IMPORT_PATH"
echo "  Source: https://code.claude.com/docs/en/hooks (no official escape-hatch convention)"
echo "  This audit: informational inventory + migration recommendations."
echo ""

# ══════════════════════════════════════════════════════════════════════════
#  Step 1 — Verify the iter-107 shared helper exists
# ══════════════════════════════════════════════════════════════════════════

if [[ ! -f "$ITP_HOOKS_SOURCE_DIRECTORY/${ITER107_SHARED_HELPER_RELATIVE_IMPORT_PATH#./}" ]]; then
    echo "  ✗ AUDIT FAILED — iter-107 shared helper file not found:"
    echo "      $ITER107_SHARED_HELPER_RELATIVE_IMPORT_PATH"
    exit 1
fi
echo "  ✓ Step 1: iter-107 shared helper exists at canonical home"
echo ""

# ══════════════════════════════════════════════════════════════════════════
#  Step 2 — Enumerate every hook source file and classify by escape-hatch
#  detection pattern (migrated / hand-rolled / no-marker)
# ══════════════════════════════════════════════════════════════════════════

declare -a MIGRATED_HOOKS_USING_SHARED_HELPER=()
declare -a HAND_ROLLED_HOOKS_WITH_OWN_MARKER_REGEX=()

# Find all .ts files in hooks/ (NOT in lib/ — those are libraries, not
# hooks). The audit is concerned with hooks-that-have-escape-hatches.
shopt -s nullglob
for hook_source_file_absolute_path in "$ITP_HOOKS_SOURCE_DIRECTORY"/*.ts "$ITP_HOOKS_SOURCE_DIRECTORY"/*.mjs; do
    # Skip test files
    case "$hook_source_file_absolute_path" in
        *.test.ts|*.test.mjs) continue ;;
    esac
    hook_relative_path="${hook_source_file_absolute_path#"$REPO_ROOT/"}"

    # Migrated: hook imports from the iter-107 shared helper
    if grep -q "from \"\\./lib/shared-escape-hatch-marker-detection-helper-cross-pretooluse-and-posttooluse-iter107" "$hook_source_file_absolute_path" 2>/dev/null; then
        MIGRATED_HOOKS_USING_SHARED_HELPER+=("$hook_relative_path")
        continue
    fi

    # Hand-rolled detection signals:
    #   - `ESCAPE_HATCH` constant declaration with a regex literal
    #   - Marker regex literal matching the UPPER-KEBAB-CASE-OK shape
    #     (e.g., /BASH-LAUNCHD-OK/, /LAYER3-STRIPPED-PATH-OK:.../, etc.)
    # Note: this is a heuristic — the audit is informational, so a false
    # positive is fine (the hook author can confirm migration is moot).
    if grep -qE 'ESCAPE_HATCH\s*=|/[A-Z][A-Z0-9-]+-OK[/:\\]' "$hook_source_file_absolute_path" 2>/dev/null; then
        HAND_ROLLED_HOOKS_WITH_OWN_MARKER_REGEX+=("$hook_relative_path")
    fi
done
shopt -u nullglob

# ══════════════════════════════════════════════════════════════════════════
#  Step 3 — Report
# ══════════════════════════════════════════════════════════════════════════

echo "  ┌─ Hooks already MIGRATED to the iter-107 shared helper (canonical):"
if [[ ${#MIGRATED_HOOKS_USING_SHARED_HELPER[@]} -eq 0 ]]; then
    echo "  │   (none yet)"
else
    for migrated_hook in "${MIGRATED_HOOKS_USING_SHARED_HELPER[@]}"; do
        echo "  │   ✓ $migrated_hook"
    done
fi
echo "  │"
echo "  ├─ Hooks with HAND-ROLLED marker detection (candidates for iter-108+ migration):"
if [[ ${#HAND_ROLLED_HOOKS_WITH_OWN_MARKER_REGEX[@]} -eq 0 ]]; then
    echo "  │   (none — marketplace fully migrated)"
else
    for hand_rolled_hook in "${HAND_ROLLED_HOOKS_WITH_OWN_MARKER_REGEX[@]}"; do
        echo "  │   ⚠ $hand_rolled_hook"
    done
fi
echo "  └─"
echo ""
echo "  Inventory summary:"
echo "    - Migrated to shared helper: ${#MIGRATED_HOOKS_USING_SHARED_HELPER[@]} hook(s)"
echo "    - Still hand-rolled:         ${#HAND_ROLLED_HOOKS_WITH_OWN_MARKER_REGEX[@]} hook(s) (informational only — not a release blocker)"
echo ""
echo "  Migration pattern (iter-78 reference design):"
echo "    1. Replace marker regex literal + window-lookup loop with a single"
echo "       configuration object + call to"
echo "       detectEscapeHatchMarkerCoveringTargetSourceLine(...)"
echo "    2. For file-wide markers, use hasFileWideEscapeHatchMarkerInContent(...)"
echo "    3. Verify existing regression test still passes (behavior-preserving)"
echo ""
echo "  ✓ AUDIT PASSED (informational — never blocks release)"
exit 0
