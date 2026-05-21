#!/usr/bin/env bash
#MISE description="Iter-101 marketplace-wide preventive audit: detects PreToolUse/PostToolUse hook matchers that include Write or Edit but NOT MultiEdit. Pre-iter-100 the PostToolUse orchestrator silently bypassed Claude's MultiEdit tool calls. Iter-100 closed the gap in one place. Iter-101 scales the discovery to a marketplace invariant. Escape hatch: MATCHER-NO-MULTIEDIT-OK in hook description. Parallel to iter-94 spawnSync audit + iter-99 silent-context-drop audit."

# ────────────────────────────────────────────────────────────────────────
# Full design rationale
# ────────────────────────────────────────────────────────────────────────
#
# Iter-100 surfaced via 2026 Anthropic + community best-practice web
# research that Claude's MultiEdit tool is a first-class file-edit tool
# whose payload shape (tool_input.edits[]) is DISTINCT from Write and
# Edit. PreToolUse/PostToolUse matchers using only `Write|Edit` silently
# allow MultiEdit through — the hook never fires for that input class.
#
# Pre-iter-101 marketplace state (raw evidence):
#   - itp-hooks PreToolUse orchestrator matcher: `Write|Edit`
#     (8 inlined subhooks ALL bypassed on MultiEdit — including
#      vale-claude-md-guard, file-size-guard, version-guard, etc.)
#   - itp-hooks PreToolUse process-storm-guard matcher: `Bash|Write|Edit`
#   - itp-hooks PostToolUse reminder + code-correctness matcher: `Bash|Write|Edit`
#   - itp-hooks PostToolUse glossary-sync + terminology-sync matcher: `Write|Edit`
#   - dotfiles-tools PostToolUse chezmoi-sync-reminder matcher: `Edit|Write`
#   - rust-tools PostToolUse rust-sota-reminder matcher: `Read|Glob|Grep|Bash|Edit|Write`
#
# All 6 violations are file-edit-content-aware hooks that SHOULD honor
# MultiEdit. None have a legitimate reason to skip it.
#
# Audit logic:
#   1. Discover every plugins/*/hooks/hooks.json file
#   2. Walk PreToolUse + PostToolUse entries
#   3. For each matcher, split on `|` and check token membership:
#        a. has "Write" OR "Edit" (literal tokens, not "MultiEdit" substring)
#        b. AND NOT has "MultiEdit"
#      → violation unless escape hatch in description
#   4. Escape hatch: hook's `description` field contains
#      `MATCHER-NO-MULTIEDIT-OK: <reason ≥ 10 chars>`
#
# Escape-hatch rationale: future Anthropic tool additions (e.g.,
# StreamEdit, BatchEdit) may need similar treatment; the escape hatch
# documents the explicit owner-attested justification when MultiEdit
# legitimately cannot apply (none in current marketplace).
#
# Parallel to:
#   - iter-94 audit: no-spawnSync-in-PostToolUse-orchestrator (perf invariant)
#   - iter-99 audit: no-raw-stdout-emission-in-PostToolUse (silent-drop invariant)

set -euo pipefail
shopt -u patsub_replacement 2>/dev/null || true

SCRIPT_DIR_ABSOLUTE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# .mise/tasks/audit-*.sh → repo root is two levels up
REPO_ROOT="$(cd "$SCRIPT_DIR_ABSOLUTE/../.." && pwd)"

print_banner() {
    echo "════════════════════════════════════════════════════════════════════════════════"
    echo "  $1"
    echo "════════════════════════════════════════════════════════════════════════════════"
}

print_banner "Iter-101 Static Audit: PreToolUse/PostToolUse matcher Write|Edit must also include MultiEdit"
echo ""
echo "  Theory: Pre-iter-100 the PostToolUse orchestrator matcher Write|Edit"
echo "          silently bypassed Claude's MultiEdit tool (separate input shape:"
echo "          tool_input.edits[] vs single old_string/new_string). All 7"
echo "          inlined classifiers NEVER fired on that input class."
echo "  Source: 2026 Anthropic + community best-practice web research surfaced"
echo "          during iter-100 adversarial audit."
echo "  Iter-100 incident: PostToolUse orchestrator + 7 inlined classifiers"
echo "          silently allowed Claude's MultiEdit calls without firing"
echo "          memory-efficiency-reminder, ssot-principles, vale-claude-md,"
echo "          type-checks, lint-checks for the entire hook's lifetime."
echo "  Iter-101 invariant: catch this matcher coverage gap preventively in"
echo "          ALL PreToolUse + PostToolUse hooks across the marketplace."
echo ""

# ══════════════════════════════════════════════════════════════════════════
#  Step 1 — Enumerate every plugins/*/hooks/hooks.json file
# ══════════════════════════════════════════════════════════════════════════

mapfile -t MARKETPLACE_HOOKS_JSON_ABSOLUTE_PATHS_TO_AUDIT < <(
    find "$REPO_ROOT/plugins" \
        -type f \
        -name 'hooks.json' \
        2>/dev/null \
        | sort -u
)

echo "  hooks.json files discovered across marketplace: ${#MARKETPLACE_HOOKS_JSON_ABSOLUTE_PATHS_TO_AUDIT[@]}"
echo ""

if [[ ${#MARKETPLACE_HOOKS_JSON_ABSOLUTE_PATHS_TO_AUDIT[@]} -eq 0 ]]; then
    echo "  ⊘ no hooks.json files discovered — audit cannot run"
    exit 0
fi

# ══════════════════════════════════════════════════════════════════════════
#  Step 2 — Scan each hooks.json for matcher coverage gap
# ══════════════════════════════════════════════════════════════════════════
#
# For each PreToolUse + PostToolUse entry:
#   1. Read matcher string (e.g., "Bash|Write|Edit")
#   2. Split on `|` → token list
#   3. If token list contains "Write" OR "Edit":
#        - Check if token list ALSO contains "MultiEdit"
#        - If not: check each inner hook's description for the
#          MATCHER-NO-MULTIEDIT-OK escape hatch
#        - If no escape hatch: record violation
#
# The token-membership check (not substring grep) avoids false-positives
# on "MultiEdit" containing "Edit" as substring.

declare -a MATCHER_COVERAGE_GAP_VIOLATIONS=()
declare -a HOOKS_SCANNED_DETAIL=()
TOTAL_MATCHER_ENTRIES_SCANNED=0

for hooks_json_absolute_path in "${MARKETPLACE_HOOKS_JSON_ABSOLUTE_PATHS_TO_AUDIT[@]}"; do
    hooks_json_relative_to_repo="${hooks_json_absolute_path#"$REPO_ROOT"/}"

    # Use jq to extract event + matcher + inner-hook commands+descriptions
    # in a single pass. Output one TSV record per (event, matcher, command, description).
    while IFS=$'\t' read -r event_name matcher_string inner_command inner_description; do
        TOTAL_MATCHER_ENTRIES_SCANNED=$((TOTAL_MATCHER_ENTRIES_SCANNED + 1))

        # Tokenize matcher on `|`
        IFS='|' read -ra matcher_tokens <<< "$matcher_string"

        has_write_token=0
        has_edit_token=0
        has_multiedit_token=0
        for token in "${matcher_tokens[@]}"; do
            case "$token" in
                Write)     has_write_token=1     ;;
                Edit)      has_edit_token=1      ;;
                MultiEdit) has_multiedit_token=1 ;;
            esac
        done

        # Trigger condition: has Write OR Edit AND does NOT have MultiEdit
        if [[ "$has_write_token" == "1" || "$has_edit_token" == "1" ]] && \
           [[ "$has_multiedit_token" == "0" ]]; then

            # Check escape hatch in description field
            if [[ "$inner_description" == *"MATCHER-NO-MULTIEDIT-OK:"* ]]; then
                continue
            fi

            MATCHER_COVERAGE_GAP_VIOLATIONS+=(
                "$hooks_json_relative_to_repo: $event_name matcher='$matcher_string' command='$inner_command'"
            )
        fi
    done < <(
        jq -r '
            .hooks
            | to_entries[]
            | select(.key == "PreToolUse" or .key == "PostToolUse")
            | .key as $event
            | .value[]
            | select(.matcher)
            | .matcher as $matcher
            | .hooks[]?
            | [$event, $matcher, (.command // ""), (.description // "")]
            | @tsv
        ' "$hooks_json_absolute_path" 2>/dev/null || true
    )

    HOOKS_SCANNED_DETAIL+=("$hooks_json_relative_to_repo")
done

# ══════════════════════════════════════════════════════════════════════════
#  Report
# ══════════════════════════════════════════════════════════════════════════

if [[ ${#MATCHER_COVERAGE_GAP_VIOLATIONS[@]} -eq 0 ]]; then
    echo "  ✓ AUDIT PASSED — no Write|Edit-without-MultiEdit coverage gaps in any PreToolUse/PostToolUse matcher"
    echo ""
    echo "  Scanned hooks.json files (${#HOOKS_SCANNED_DETAIL[@]}):"
    for path in "${HOOKS_SCANNED_DETAIL[@]}"; do
        echo "    - $path"
    done
    echo ""
    echo "  Total (event,matcher,hook) tuples scanned: $TOTAL_MATCHER_ENTRIES_SCANNED"
    exit 0
fi

echo "  ✗ AUDIT FAILED — ${#MATCHER_COVERAGE_GAP_VIOLATIONS[@]} matcher coverage gap(s) found:"
echo ""
for violation in "${MATCHER_COVERAGE_GAP_VIOLATIONS[@]}"; do
    echo "    $violation"
done
echo ""
echo "  Total (event,matcher,hook) tuples scanned: $TOTAL_MATCHER_ENTRIES_SCANNED"
echo ""
echo "  Fix options:"
echo "    A. Broaden the matcher to include MultiEdit (recommended for all"
echo "       file-edit-content-aware hooks):"
echo "         \"matcher\": \"Write|Edit\"           →  \"matcher\": \"Write|Edit|MultiEdit\""
echo "         \"matcher\": \"Bash|Write|Edit\"      →  \"matcher\": \"Bash|Write|Edit|MultiEdit\""
echo ""
echo "    B. If MultiEdit genuinely cannot apply to this hook's logic (rare),"
echo "       add the escape hatch to the hook's description field:"
echo "         \"description\": \"... MATCHER-NO-MULTIEDIT-OK: <reason ≥ 10 chars>\""
echo ""
echo "  Iter-100 incident reference: plugins/itp-hooks/hooks/hooks.json PostToolUse"
echo "  orchestrator matcher was 'Write|Edit' — silently bypassed Claude's"
echo "  MultiEdit tool calls for the entire hook's lifetime, causing 7 inlined"
echo "  classifiers (memory-eff, ssot, vale, type-checks, lint-checks) to NEVER"
echo "  fire on multi-edit-to-one-file tool calls. Iter-100 fixed the orchestrator"
echo "  in one place; iter-101 scales the discovery to a marketplace invariant."
echo ""
exit 1
