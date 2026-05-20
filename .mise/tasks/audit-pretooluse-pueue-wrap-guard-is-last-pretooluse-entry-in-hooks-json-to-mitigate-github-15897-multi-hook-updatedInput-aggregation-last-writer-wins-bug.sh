#!/usr/bin/env bash
#MISE description="Audit every plugins/*/hooks/hooks.json that registers pretooluse-pueue-wrap-guard.ts and assert it is the LAST PreToolUse entry. Per GitHub #15897 (Claude Code's multi-hook updatedInput aggregation bug — the last hook's hookSpecificOutput response replaces earlier ones, including resetting updatedInput to undefined), any PreToolUse hook running AFTER pueue-wrap-guard can silently clobber its OP_SERVICE_ACCOUNT_TOKEN injection and pueue command-wrapping mutations. This audit is the structural enforcement of the documented invariant in itp-hooks/CLAUDE.md ('MUST be LAST PreToolUse entry'). Exits non-zero on any violation (release:preflight gate candidate)."
#
# audit-pretooluse-pueue-wrap-guard-is-last-pretooluse-entry-in-hooks-json-to-mitigate-github-15897-multi-hook-updatedInput-aggregation-last-writer-wins-bug
#
# Iter-61 self-explanatory-scaffolding audit. Born from an adversarial
# review that discovered the documented invariant in itp-hooks/CLAUDE.md
# ("pretooluse-pueue-wrap-guard.ts ... MUST be LAST PreToolUse entry")
# was VIOLATED in production: pretooluse-parquet-duckdb-nudge.ts had
# been added AFTER pueue-wrap-guard at some point, placing it at the
# tail of the PreToolUse array.
#
# Why the ordering matters (mechanism, in detail):
#
#   GitHub #15897 documents that when MULTIPLE PreToolUse hooks fire on
#   the same tool invocation, Claude Code does NOT merge their
#   hookSpecificOutput responses field-by-field. Instead the LAST hook's
#   response replaces earlier ones. Critically, if the last hook emits
#   NO updatedInput field (e.g., a soft-nudge hook calling allow() that
#   only sets permissionDecision), the merged result has updatedInput =
#   undefined — silently dropping the earlier mutation.
#
#   pretooluse-pueue-wrap-guard performs TWO load-bearing mutations:
#     1. Injects OP_SERVICE_ACCOUNT_TOKEN for Claude Automation vault
#        commands (otherwise op CLI prompts for biometric auth).
#     2. Wraps long-running commands with pueue (synchronous queue+wait
#        pattern, plus session-scoped task-ID logging for cleanup).
#
#   Both mutations live in updatedInput.command. If any later hook
#   emits its own hookSpecificOutput response — even a benign allow()
#   with no updatedInput — pueue-wrap-guard's mutations are LOST.
#
# What this audit checks:
#
#   For every plugins/*/hooks/hooks.json that registers
#   pretooluse-pueue-wrap-guard.ts, walks the PreToolUse hooks array
#   IN-ORDER and asserts the LAST entry's command path contains
#   pretooluse-pueue-wrap-guard. Reports OK / VIOLATION per file.
#
# What this audit does NOT check (future-iter candidates):
#
#   - Whether other plugins (outside cc-skills) register hooks that
#     run AFTER itp-hooks' pueue-wrap-guard. Cross-plugin ordering is
#     governed by plugin load order, which we don't control here.
#   - Whether pueue-wrap-guard hook config itself has changed shape
#     (matcher, timeout). Those are separate invariants.
#
# Verbose name encodes WHAT it audits (pueue-wrap-guard position),
# WHICH invariant (last-entry), and WHY (GitHub #15897 mitigation).
# Future maintainers searching for "pueue-wrap-guard ordering",
# "updatedInput aggregation", "GitHub 15897", or "last PreToolUse
# entry" surface this audit immediately.
#
# Re-run cadence:
#   - Manual: `mise run audit-pretooluse-pueue-wrap-guard-...`
#   - Automatic: release:preflight Check 4g (iter-61 wire-up)

set -euo pipefail
shopt -u patsub_replacement 2>/dev/null || true

# REPO_ROOT defaults to the cc-skills working tree (resolved from this
# task's location). Override via AUDIT_REPO_ROOT_OVERRIDE for testing
# the audit against a synthetic-fixture fleet.
REPO_ROOT="${AUDIT_REPO_ROOT_OVERRIDE:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"

echo "═══════════════════════════════════════════════════════════════════════════"
echo "  Pueue-Wrap-Guard Last-PreToolUse-Entry Ordering Audit"
echo "═══════════════════════════════════════════════════════════════════════════"
echo "→ Mitigates GitHub #15897 (multi-hook updatedInput aggregation bug)"
echo "→ Scans plugins/*/hooks/hooks.json that register pueue-wrap-guard.ts"
echo "→ Asserts pueue-wrap-guard is the LAST PreToolUse entry in each"
echo ""

# Counters
files_scanned=0
files_with_pueue_wrap_guard=0
files_ok=0
files_violation=0
VIOLATION_LINES=""

# Walk every hooks.json that references pueue-wrap-guard.
# We use grep -l to find candidates first (fast), then jq for structural
# parsing (precise). This is the same pattern as iter-57's audit.
while IFS= read -r hooks_json; do
    [ -f "$hooks_json" ] || continue
    files_scanned=$((files_scanned + 1))

    plugin_name=$(basename "$(dirname "$(dirname "$hooks_json")")")

    # Skip files that don't register pueue-wrap-guard at all.
    if ! grep -q 'pretooluse-pueue-wrap-guard' "$hooks_json" 2>/dev/null; then
        continue
    fi
    files_with_pueue_wrap_guard=$((files_with_pueue_wrap_guard + 1))

    # Extract the LAST entry's command string from PreToolUse array.
    # The jq query walks .hooks.PreToolUse[-1].hooks[-1].command — the
    # last command of the last hook-group of the PreToolUse array.
    #
    # Note: hooks.json schema nests command-arrays inside hook-groups,
    # so a hook-group can have multiple commands. Operator convention
    # in cc-skills is one command per group, but we defensively pick
    # the last command of the last group regardless.
    last_command=$(jq -r '
        (.hooks.PreToolUse // [])
        | if length == 0 then "<NO-PRETOOLUSE-HOOKS>"
          else .[-1].hooks[-1].command // "<MALFORMED>"
          end
    ' "$hooks_json" 2>/dev/null) || last_command="<JQ-PARSE-ERROR>"

    # Compare: does the last command reference pueue-wrap-guard?
    if echo "$last_command" | grep -q 'pretooluse-pueue-wrap-guard'; then
        files_ok=$((files_ok + 1))
        echo "  ✓ $plugin_name/hooks/hooks.json — pueue-wrap-guard is LAST PreToolUse entry"
    else
        files_violation=$((files_violation + 1))
        # Extract the full PreToolUse ordering for diagnostics.
        ordering=$(jq -r '
            (.hooks.PreToolUse // [])
            | to_entries
            | map("    \(.key+1). matcher=\(.value.matcher // "<any>") cmd=\(.value.hooks[-1].command // "<MALFORMED>")")
            | join("\n")
        ' "$hooks_json" 2>/dev/null) || ordering="    <JQ-DIAGNOSTIC-ERROR>"

        VIOLATION_LINES+="  ✗ $plugin_name/hooks/hooks.json"$'\n'
        VIOLATION_LINES+="      Invariant: pueue-wrap-guard MUST be LAST PreToolUse entry"$'\n'
        VIOLATION_LINES+="      Found LAST entry: $last_command"$'\n'
        VIOLATION_LINES+="      Full PreToolUse ordering (1-indexed):"$'\n'
        VIOLATION_LINES+="$ordering"$'\n'
        VIOLATION_LINES+="      Fix: reorder hooks.json so the pueue-wrap-guard hook-group is the"$'\n'
        VIOLATION_LINES+="           LAST element of the .hooks.PreToolUse array."$'\n'
        VIOLATION_LINES+="      Reason: GitHub #15897 means any later hook's response (even allow()"$'\n'
        VIOLATION_LINES+="           with no updatedInput) silently clobbers pueue-wrap-guard's two"$'\n'
        VIOLATION_LINES+="           load-bearing mutations: OP token injection (OP_SERVICE_ACCOUNT_TOKEN)"$'\n'
        VIOLATION_LINES+="           and pueue command-wrapping (queue+wait synchronous execution)."$'\n'
    fi
done < <(find "$REPO_ROOT/plugins" -path '*/hooks/hooks.json' -type f 2>/dev/null | sort)

# Emit structured report.
echo ""
echo "═══════════════════════════════════════════════════════════════════════════"
echo "  Ordering Audit Summary"
echo "═══════════════════════════════════════════════════════════════════════════"
echo "  Total hooks.json files scanned:                  $files_scanned"
echo "  Files registering pueue-wrap-guard.ts:           $files_with_pueue_wrap_guard"
echo "  ORDERING-OK (pueue-wrap-guard is LAST):          $files_ok"
echo "  ORDERING-VIOLATION (pueue-wrap-guard NOT LAST):  $files_violation"
echo ""

if [ "$files_violation" -gt 0 ]; then
    echo "─── ORDERING-VIOLATION ($files_violation) — silent-failure risk for OP token + pueue wrap ───"
    printf "%s" "$VIOLATION_LINES"
    echo ""
    echo "═══════════════════════════════════════════════════════════════════════════"
    echo "  EXITING NON-ZERO — release:preflight should gate on this."
    echo "═══════════════════════════════════════════════════════════════════════════"
    exit 1
fi

if [ "$files_with_pueue_wrap_guard" -eq 0 ]; then
    echo "  ⚠  No hooks.json files register pueue-wrap-guard.ts."
    echo "     If this is unexpected, the audit's grep filter may need adjustment."
fi

echo "═══════════════════════════════════════════════════════════════════════════"
echo "  ✓ All hooks.json files honor the pueue-wrap-guard last-entry invariant."
echo "═══════════════════════════════════════════════════════════════════════════"
