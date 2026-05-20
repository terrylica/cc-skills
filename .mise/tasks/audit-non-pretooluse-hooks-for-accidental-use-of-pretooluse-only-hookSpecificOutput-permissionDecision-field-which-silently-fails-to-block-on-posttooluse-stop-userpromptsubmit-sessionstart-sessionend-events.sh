#!/usr/bin/env bash
#MISE description="Audit every plugins/*/hooks/{posttooluse,stop,userpromptsubmit,sessionstart,sessionend}-*.{sh,ts,mjs,py} for the INVERSE silent-fail of iter-60: accidental use of the PreToolUse-only 'hookSpecificOutput.permissionDecision' field. Per the Claude Code v2.0.10+ spec, only PreToolUse hooks read permissionDecision; non-PreToolUse events expect top-level 'decision: block|null'. A non-PreToolUse hook emitting permissionDecision is read by NO field consumer in Claude Code and silently FAILS TO BLOCK. Exits non-zero if any wrong-field-for-event hook is found (release:preflight gate candidate, symmetric companion to iter-60's PreToolUse audit)."
#
# audit-non-pretooluse-hooks-for-accidental-use-of-pretooluse-only-hookSpecificOutput-permissionDecision-field-which-silently-fails-to-block-on-posttooluse-stop-userpromptsubmit-sessionstart-sessionend-events
#
# Iter-62 self-explanatory-scaffolding audit — symmetric companion to
# iter-60's PreToolUse schema audit. Background:
#
#   The Claude Code v2.0.10+ hook schema has an asymmetric quirk that
#   causes BIDIRECTIONAL silent-fail categories:
#
#     - PreToolUse blocking decisions use:
#         hookSpecificOutput.permissionDecision: "allow"|"deny"|"ask"
#         hookSpecificOutput.permissionDecisionReason
#
#     - Non-PreToolUse blockable events (PostToolUse, Stop,
#       UserPromptSubmit) use the TOP-LEVEL pattern:
#         decision: "block" | null
#         reason: <string, required if blocking>
#
#   Iter-60 audits the PreToolUse → DEPRECATED-WARNING category:
#   PreToolUse hooks accidentally using the top-level decision:"block"
#   schema. This audit covers the INVERSE: PostToolUse/Stop/
#   UserPromptSubmit/SessionStart/SessionEnd hooks accidentally using
#   the PreToolUse-only hookSpecificOutput.permissionDecision schema.
#
#   In both directions the failure is SILENT — Claude Code reads only
#   the canonical field for the event, the hook emits a different
#   field, the decision lands in nowhere, and the tool/turn proceeds
#   as if the hook had returned `allow`/`null`. Forensics on a "hook
#   didn't block" incident are hard without a dedicated audit because
#   the hook AUTHOR sees their decision being emitted to stdout, just
#   to /dev/null effectively from Claude Code's perspective.
#
# Authority (official docs at https://code.claude.com/docs/en/hooks):
#
#   "A common mistake is mixing decision schemas. Most events use
#    top-level `decision`, but PreToolUse uses
#    `hookSpecificOutput.permissionDecision`. Reading the wrong field
#    means your block doesn't fire."
#
# Classification (per non-PreToolUse hook script):
#
#   SCHEMA-CORRECT-FOR-EVENT
#     Either:
#       (a) emits top-level decision:"block" + reason (the modern
#           non-PreToolUse blocking schema), OR
#       (b) emits hookSpecificOutput.additionalContext (a valid,
#           non-blocking informational pattern for PostToolUse +
#           UserPromptSubmit + SessionStart), OR
#       (c) doesn't emit ANY decision pattern (pure side-effect /
#           reminder / logger hook), OR
#       (d) calls a helper function that internally emits the correct
#           schema (HELPER-WRAPPED — analogous to iter-60).
#     Safe.
#
#   WRONG-FIELD-SILENT-FAIL
#     Emits `hookSpecificOutput.permissionDecision` (the PreToolUse-
#     only field). Claude Code reads NO blocking decision from this
#     hook on its registered non-PreToolUse event. EXIT NON-ZERO —
#     release:preflight should gate on this.
#
# What this audit does NOT check (out of scope, separate concerns):
#
#   - additionalContext field on Stop hooks: docs are ambiguous about
#     whether Stop hooks support hookSpecificOutput.additionalContext
#     vs top-level additionalContext. Community evidence shows both
#     work depending on Claude Code version. Skipping until a clean
#     repro is captured.
#   - PermissionRequest events use hookSpecificOutput.decision (not
#     permissionDecision). Out of scope here — separate audit if
#     needed.
#
# Verbose name encodes WHAT it audits (non-PreToolUse hooks), WHICH
# specific silent-fail (PreToolUse-only field used on wrong event),
# WHY (silent fail on blockable events), and WHICH events are scoped
# (posttooluse/stop/userpromptsubmit/sessionstart/sessionend).
# Future maintainers searching for "wrong field for event",
# "permissionDecision on PostToolUse", "PostToolUse not blocking",
# "Stop hook not blocking", or "inverse PreToolUse audit" surface
# this audit immediately.
#
# Re-run cadence:
#   - Manual: `mise run audit-non-pretooluse-hooks-...`
#   - Automatic: release:preflight Check 4h (iter-62 wire-up).
#     Sits alongside iter-60 (Check 4f, PreToolUse direction) for
#     symmetric schema-correctness enforcement.

set -euo pipefail
shopt -u patsub_replacement 2>/dev/null || true

# REPO_ROOT defaults to the cc-skills working tree (resolved from this
# task's location). Override via AUDIT_REPO_ROOT_OVERRIDE for testing
# the audit against a synthetic-fixture fleet.
REPO_ROOT="${AUDIT_REPO_ROOT_OVERRIDE:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"

echo "═══════════════════════════════════════════════════════════════════════════"
echo "  Non-PreToolUse Hook Schema-Correctness Audit (inverse of iter-60)"
echo "═══════════════════════════════════════════════════════════════════════════"
echo "→ Scans plugins/*/hooks/{posttooluse,stop,userpromptsubmit,sessionstart,sessionend}-*"
echo "→ Detects: hookSpecificOutput.permissionDecision (PreToolUse-only field)"
echo "→ Why this matters: non-PreToolUse hooks emitting permissionDecision"
echo "  are read by NO field consumer in Claude Code — silent failure to block."
echo "→ Canonical schema for these events: top-level decision:\"block\" + reason"
echo ""

# Classification counters
schema_correct_count=0
helper_wrapped_count=0
no_blocking_emitted_count=0
wrong_field_silent_fail_count=0
total_non_pretooluse_hooks=0

# Accumulator for the WRONG-FIELD-SILENT-FAIL report section
WRONG_FIELD_LINES=""

# Verify that pretooluse-helpers.ts (the canonical helper module)
# itself is properly scoped: it should emit permissionDecision (the
# correct schema for PreToolUse helpers). This is a sanity check —
# if helpers.ts ever started being used by non-PreToolUse hooks, the
# HELPER-WRAPPED classification would become a silent-fail risk.
verify_pretooluse_helpers_module_scope() {
  local helpers_path="$REPO_ROOT/plugins/itp-hooks/hooks/pretooluse-helpers.ts"
  if [ ! -f "$helpers_path" ]; then
    return 0
  fi
  # No checks needed — iter-60 already verifies this module emits
  # MODERN PreToolUse schema. We're just noting it exists for context.
  return 0
}

# Classify a single non-PreToolUse hook source file.
classify_non_pretooluse_hook_schema() {
  local hook_path="$1"

  # Tier 1: does it emit the PreToolUse-only permissionDecision field?
  # This is the silent-fail category we're hunting.
  if grep -qE '"permissionDecision"[[:space:]]*:|permissionDecision[[:space:]]*:' "$hook_path" 2>/dev/null; then
    echo "WRONG-FIELD-SILENT-FAIL"
    return
  fi

  # Tier 2: does it emit the canonical non-PreToolUse blocking schema?
  # Top-level decision:"block" + reason.
  if grep -qE '"decision"[[:space:]]*:[[:space:]]*"block"|decision:[[:space:]]*['"'"'"]block['"'"'"]' "$hook_path" 2>/dev/null; then
    echo "SCHEMA-CORRECT-FOR-EVENT"
    return
  fi

  # Tier 3: does it emit additionalContext (non-blocking informational)?
  if grep -qE 'additionalContext' "$hook_path" 2>/dev/null; then
    echo "SCHEMA-CORRECT-FOR-EVENT"
    return
  fi

  # Tier 4: does it call a known PostToolUse/Stop/UserPromptSubmit
  # helper that internally emits the correct schema?
  # (No such helper module exists in cc-skills yet; reserved for future.)
  # Pattern would match imports like: import { blockTurn, ... } from "./posttooluse-helpers.ts";
  if grep -qE 'from[[:space:]]+["'"'"'][^"'"'"']*posttooluse-helpers' "$hook_path" 2>/dev/null; then
    echo "HELPER-WRAPPED"
    return
  fi

  # Tier 5: no blocking decision emission at all (reminder-only hook).
  echo "NO-BLOCKING-EMITTED"
}

verify_pretooluse_helpers_module_scope || exit 2

# Walk every non-PreToolUse hook source file. The naming convention
# scope is: posttooluse-*, stop-*, userpromptsubmit-*, sessionstart-*,
# sessionend-* — the canonical prefixes for these event categories
# across the marketplace.
while IFS= read -r hook_path; do
  [ -f "$hook_path" ] || continue
  # Skip test files — they're test fixtures, not registered hooks.
  case "$hook_path" in
    *.test.ts|*.test.mjs|*.test.js|*.test.sh) continue ;;
  esac
  total_non_pretooluse_hooks=$((total_non_pretooluse_hooks + 1))

  plugin_name="$(basename "$(dirname "$(dirname "$hook_path")")")"
  hook_basename="$(basename "$hook_path")"

  # Determine the event from the filename prefix for diagnostic clarity.
  event_name="UNKNOWN"
  case "$hook_basename" in
    posttooluse-*)     event_name="PostToolUse" ;;
    stop-*)            event_name="Stop" ;;
    userpromptsubmit-*) event_name="UserPromptSubmit" ;;
    sessionstart-*)    event_name="SessionStart" ;;
    sessionend-*)      event_name="SessionEnd" ;;
  esac

  classification=$(classify_non_pretooluse_hook_schema "$hook_path")
  case "$classification" in
    SCHEMA-CORRECT-FOR-EVENT)
      schema_correct_count=$((schema_correct_count + 1))
      ;;
    HELPER-WRAPPED)
      helper_wrapped_count=$((helper_wrapped_count + 1))
      ;;
    NO-BLOCKING-EMITTED)
      no_blocking_emitted_count=$((no_blocking_emitted_count + 1))
      ;;
    WRONG-FIELD-SILENT-FAIL)
      wrong_field_silent_fail_count=$((wrong_field_silent_fail_count + 1))
      WRONG_FIELD_LINES+="  - $plugin_name/hooks/$hook_basename  (event: $event_name)"$'\n'
      WRONG_FIELD_LINES+="      Issue: emits hookSpecificOutput.permissionDecision (PreToolUse-only field)"$'\n'
      WRONG_FIELD_LINES+="             on a $event_name hook."$'\n'
      WRONG_FIELD_LINES+="             Claude Code reads NO field consumer for permissionDecision on"$'\n'
      WRONG_FIELD_LINES+="             $event_name events — the block silently does not fire."$'\n'
      WRONG_FIELD_LINES+="      Fix:   change to top-level decision:\"block\" + reason fields."$'\n'
      WRONG_FIELD_LINES+="             Example: console.log(JSON.stringify({ decision: \"block\","$'\n'
      WRONG_FIELD_LINES+="                                                     reason: \"why\" }));"$'\n'
      WRONG_FIELD_LINES+="             For non-blocking informational output use"$'\n'
      WRONG_FIELD_LINES+="             hookSpecificOutput.additionalContext instead."$'\n'
      ;;
  esac
done < <(find "$REPO_ROOT/plugins" \
            \( -path '*/hooks/posttooluse-*' \
            -o -path '*/hooks/stop-*' \
            -o -path '*/hooks/userpromptsubmit-*' \
            -o -path '*/hooks/sessionstart-*' \
            -o -path '*/hooks/sessionend-*' \) \
            -type f 2>/dev/null | sort)

# Emit the structured report.
echo "═══════════════════════════════════════════════════════════════════════════"
echo "  Schema Audit Summary (non-PreToolUse events)"
echo "═══════════════════════════════════════════════════════════════════════════"
echo "  Total non-PreToolUse hook source files scanned: $total_non_pretooluse_hooks"
echo "  SCHEMA-CORRECT-FOR-EVENT:                       $schema_correct_count"
echo "  HELPER-WRAPPED:                                 $helper_wrapped_count"
echo "  NO-BLOCKING-EMITTED (reminder-only):            $no_blocking_emitted_count"
echo "  WRONG-FIELD-SILENT-FAIL (permissionDecision):   $wrong_field_silent_fail_count"
echo ""

if [ "$wrong_field_silent_fail_count" -gt 0 ]; then
  echo "─── WRONG-FIELD-SILENT-FAIL ($wrong_field_silent_fail_count) — these hooks silently fail to block ───"
  printf "%s" "$WRONG_FIELD_LINES"
  echo ""
  echo "═══════════════════════════════════════════════════════════════════════════"
  echo "  EXITING NON-ZERO — release:preflight should gate on this."
  echo "═══════════════════════════════════════════════════════════════════════════"
  exit 1
fi

echo "═══════════════════════════════════════════════════════════════════════════"
echo "  ✓ All non-PreToolUse hooks use the canonical schema for their event."
echo "  ✓ No silent-fail risk from PreToolUse-only field misuse."
echo "═══════════════════════════════════════════════════════════════════════════"
