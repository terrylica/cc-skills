#!/usr/bin/env bash
#MISE description="Audit every plugins/*/hooks/hooks.json REGISTERED Stop hook source file for emission of the additionalContext field in stdout JSON. Per the official Anthropic Stop-hook schema (verbatim example in GitHub #19115), Stop and SubagentStop hooks read only {decision, reason} from stdout JSON — any additionalContext field is silently dropped. iter-66 fixed the itp-hooks stop-orchestrator silent-drop bug; this audit prevents future regressions across the entire marketplace. Strips JSDoc and line comments before scanning to avoid false positives on documentation references. Escape hatch: STOP-HOOK-ADDITIONAL-CONTEXT-OK source comment with reason ≥ 10 chars (e.g., for legitimate internal protocols where a Stop hook reads additionalContext from subhook stdout but never emits it to its own stdout). Exits non-zero on any unjustified emission. Symmetric companion to iter-60 / iter-62 / iter-65 schema-correctness gates."
#
# audit-stop-hooks-for-additionalContext-emission-which-claude-code-silently-drops-per-official-anthropic-schema-only-decision-and-reason-fields-are-read-from-stop-hook-stdout-json
#
# Iter-67 self-explanatory-scaffolding audit — preventive companion to
# iter-66 (single-hook orchestrator additionalContext silent-drop fix).
#
# Background (mechanism):
#
#   Per the official Anthropic Claude Code Stop-hook schema (verbatim
#   example documented in GitHub issue #19115 and the official docs at
#   code.claude.com/docs/en/hooks):
#
#     {
#       "decision": "block" | undefined,
#       "reason":   "Must be provided when Claude is blocked from stopping"
#     }
#
#   These are the ONLY top-level fields Claude Code reads from a Stop
#   hook's stdout JSON. Any other field — most notably `additionalContext`
#   (top-level OR nested inside hookSpecificOutput) — is silently
#   ignored. From the hook author's perspective the JSON looks valid;
#   from Claude Code's perspective the extra field doesn't exist.
#
#   This is a different schema from PostToolUse / UserPromptSubmit /
#   SessionStart, where hookSpecificOutput.additionalContext IS read
#   and injected as a system reminder into Claude's next-turn context.
#
#   iter-66 forensic: itp-hooks stop-orchestrator was pre-iter-66
#   emitting {additionalContext: <aggregated subhook summary>} to its
#   stdout JSON. Claude Code parsed the JSON, found no `decision`
#   field, treated the Stop as "don't block", and silently ignored
#   the additionalContext field entirely. Subhook summaries from
#   stop-markdown-lint, stop-ty-project-check, and stop-hook-error-
#   summary reached no one — operators got no transcript visibility,
#   Claude got no context. The fix routed the summary to STDERR
#   (transcript-visible) instead of pretending stdout JSON would
#   reach Claude.
#
#   iter-67 (this audit) scales the iter-66 fix into preventive
#   infrastructure marketplace-wide.
#
# What this audit checks:
#
#   For every plugins/*/hooks/hooks.json that registers a Stop hook,
#   resolve the source file pointed to by the hook command and scan
#   for the literal `additionalContext` token. Strips line comments
#   (// ...) and JSDoc block comments (/* ... */) before scanning,
#   so documentation references like the iter-66 forensic JSDoc
#   block don't false-positive.
#
# Escape hatch (legitimate uses):
#
#   Some Stop hook orchestrators READ additionalContext from subhook
#   stdout as part of an internal aggregation protocol — that's
#   safe (the orchestrator reads it but doesn't re-emit it). To
#   opt out of the audit for these cases, add to the source:
#
#     // STOP-HOOK-ADDITIONAL-CONTEXT-OK: <reason ≥ 10 chars>
#     # STOP-HOOK-ADDITIONAL-CONTEXT-OK: <reason ≥ 10 chars>
#
#   The 10-char minimum prevents low-effort opt-outs like "ok"
#   or "tbd". The reason should explain WHY the source references
#   additionalContext despite the Stop-hook schema not supporting it
#   (typical: "reads additionalContext from subhook stdout, routes
#   aggregated text to stderr per iter-66 fix" for orchestrators).
#
# What this audit does NOT check (out of scope):
#
#   - Hooks NOT registered as Stop hooks in hooks.json — they're
#     subhooks invoked by orchestrators, can legitimately emit
#     additionalContext to a parent orchestrator over their stdout.
#   - SubagentStop hooks (same schema rules, separate audit if needed).
#   - Whether additionalContext appears in JSON.stringify call sites
#     via data-flow analysis. Static analysis with comment-stripping
#     catches the common cases; deep data-flow would require AST
#     analysis. Operator can use the OK marker after manual review.
#
# Verbose name encodes WHAT it audits (Stop hooks), WHICH anti-
# pattern (additionalContext emission), WHY it matters (Claude Code
# silently drops per schema), and the authoritative schema fact
# (only decision + reason). Future maintainers searching for "stop
# hook additionalContext", "stop hook silent drop", "GitHub 19115",
# "iter-66", or "iter-67" surface this audit immediately.
#
# Re-run cadence:
#   - Manual: `mise run audit-stop-hooks-for-additionalContext-emission-...`
#   - Automatic: release:preflight Check 4j (iter-67 wire-up).

set -euo pipefail
shopt -u patsub_replacement 2>/dev/null || true

# REPO_ROOT defaults to the cc-skills working tree (resolved from this
# task's location). Override via AUDIT_REPO_ROOT_OVERRIDE for testing
# the audit against a synthetic-fixture fleet.
REPO_ROOT="${AUDIT_REPO_ROOT_OVERRIDE:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"

# Minimum length of STOP-HOOK-ADDITIONAL-CONTEXT-OK justification.
MIN_OK_REASON_LENGTH=10

echo "═══════════════════════════════════════════════════════════════════════════"
echo "  Stop-Hook additionalContext-Emission Audit"
echo "═══════════════════════════════════════════════════════════════════════════"
echo "→ Scans registered Stop hook source files for additionalContext"
echo "→ Per official Anthropic schema (GitHub #19115), Stop hooks read ONLY"
echo "  {decision, reason} from stdout JSON. Any additionalContext field is"
echo "  silently dropped — operator gets no transcript visibility, Claude"
echo "  gets no context. The hook author sees JSON being emitted normally."
echo "→ Comment-aware: strips // line and /* */ block comments before scan,"
echo "  so JSDoc references (like iter-66 forensic docs) don't false-positive."
echo "→ Escape hatch: 'STOP-HOOK-ADDITIONAL-CONTEXT-OK: <reason>' source"
echo "  comment with reason ≥ ${MIN_OK_REASON_LENGTH} chars."
echo ""

# Classification counters
no_additionalContext_count=0
with_ok_marker_count=0
emission_violation_count=0
total_registered_stop_hooks=0

# Accumulator for violation report
VIOLATION_LINES=""

# Helper: extract the hook source basename from a hooks.json command string.
# Command examples:
#   "bun ${CLAUDE_PLUGIN_ROOT}/hooks/stop-orchestrator.ts"
#   "${CLAUDE_PLUGIN_ROOT}/hooks/stop-cleanup.sh"
#   "bash $HOME/.claude/plugins/marketplaces/cc-skills/plugins/foo/hooks/stop-bar.ts"
extract_hook_basename_from_command_string() {
  local cmd="$1"
  local basename_with_args="${cmd##*/}"
  echo "${basename_with_args%% *}"
}

# Helper: strip JSDoc block comments and // line comments from source.
# Returns comment-stripped text. Two-step:
#   1. Strip /* ... */ blocks (multi-line)
#   2. Strip // ... to end of line
# Uses Perl for multi-line regex (BSD/GNU sed don't reliably do multi-line).
strip_comments_from_source_for_pure_code_scan() {
  local source_path="$1"
  # Use perl -0 (slurp mode) to handle multi-line /* */ blocks.
  # Then strip // line comments from each line.
  perl -0pe 's{/\*.*?\*/}{}gs' "$source_path" | sed 's|//.*$||'
}

# Helper: check for a valid STOP-HOOK-ADDITIONAL-CONTEXT-OK marker.
stop_hook_source_has_valid_additional_context_ok_marker() {
  local source_path="$1"
  if [ ! -f "$source_path" ]; then
    return 1
  fi
  local marker_line
  marker_line=$(grep -oE 'STOP-HOOK-ADDITIONAL-CONTEXT-OK:.*' "$source_path" 2>/dev/null | head -1 || true)
  if [ -z "$marker_line" ]; then
    return 1
  fi
  local reason
  reason=$(echo "$marker_line" | sed -E 's/^STOP-HOOK-ADDITIONAL-CONTEXT-OK:[[:space:]]*//')
  reason=$(echo "$reason" | sed -E 's/[[:space:]]+$//')
  if [ -z "$reason" ]; then
    return 1
  fi
  if [ "${#reason}" -lt "$MIN_OK_REASON_LENGTH" ]; then
    return 1
  fi
  return 0
}

# Walk every hooks.json that registers Stop hooks.
while IFS= read -r hooks_json; do
  [ -f "$hooks_json" ] || continue

  plugin_dir=$(dirname "$(dirname "$hooks_json")")
  plugin_name=$(basename "$plugin_dir")

  # For each registered Stop hook, emit the first command string.
  while IFS= read -r hook_command; do
    [ -z "$hook_command" ] && continue
    total_registered_stop_hooks=$((total_registered_stop_hooks + 1))

    hook_basename=$(extract_hook_basename_from_command_string "$hook_command")

    # Resolve source file. Try plugin's hooks/ dir first.
    source_path="$plugin_dir/hooks/$hook_basename"
    if [ ! -f "$source_path" ]; then
      # Try repo-wide find as fallback (for synthetic fixtures).
      source_path=$(find "$REPO_ROOT/plugins" -name "$hook_basename" -path '*/hooks/*' -type f 2>/dev/null | grep -v '/tests/' | head -1)
    fi

    if [ -z "$source_path" ] || [ ! -f "$source_path" ]; then
      echo "  ⊘ SOURCE-NOT-FOUND: $plugin_name/$hook_basename (skipped)"
      continue
    fi

    # Strip comments and search for additionalContext in remaining code.
    code_only=$(strip_comments_from_source_for_pure_code_scan "$source_path")

    if ! echo "$code_only" | grep -q 'additionalContext'; then
      # No emission patterns in non-comment code.
      no_additionalContext_count=$((no_additionalContext_count + 1))
      continue
    fi

    # additionalContext found in non-comment code. Check for OK marker.
    if stop_hook_source_has_valid_additional_context_ok_marker "$source_path"; then
      with_ok_marker_count=$((with_ok_marker_count + 1))
      echo "  ◯ WITH-OK-MARKER: $plugin_name/hooks/$hook_basename"
      continue
    fi

    # Violation.
    emission_violation_count=$((emission_violation_count + 1))
    VIOLATION_LINES+="  ✗ $plugin_name/hooks/$hook_basename"$'\n'
    VIOLATION_LINES+="      Issue:   source references 'additionalContext' in non-comment code."$'\n'
    VIOLATION_LINES+="               Per official Anthropic Stop-hook schema (verbatim in GitHub #19115),"$'\n'
    VIOLATION_LINES+="               Stop hooks read ONLY {decision, reason} from stdout JSON. Any"$'\n'
    VIOLATION_LINES+="               additionalContext field is silently dropped — the hook author sees"$'\n'
    VIOLATION_LINES+="               the field being emitted, but Claude Code never reads it."$'\n'
    VIOLATION_LINES+="      Fix:     route the summary text to PROCESS.STDERR instead of stdout JSON."$'\n'
    VIOLATION_LINES+="               Stderr is transcript-visible via Ctrl-R; operators can still see"$'\n'
    VIOLATION_LINES+="               summaries during debugging. To inject context that Claude actually"$'\n'
    VIOLATION_LINES+="               reads on next turn, use decision:\"block\" + reason (which keeps"$'\n'
    VIOLATION_LINES+="               Claude running and surfaces reason as a system reminder)."$'\n'
    VIOLATION_LINES+="               OR add to source: // STOP-HOOK-ADDITIONAL-CONTEXT-OK: <reason ≥ ${MIN_OK_REASON_LENGTH} chars>"$'\n'
    VIOLATION_LINES+="      Refs:    iter-66 (single-hook orchestrator fix), iter-67 (this audit),"$'\n'
    VIOLATION_LINES+="               GitHub #19115 (Anthropic schema verbatim example),"$'\n'
    VIOLATION_LINES+="               https://code.claude.com/docs/en/hooks (official docs)."$'\n'

  done < <(jq -r '
    (.hooks // {}) | to_entries[]
    | select(.key == "Stop")
    | .value[]?
    | .hooks[].command // empty
  ' "$hooks_json" 2>/dev/null)

done < <(find "$REPO_ROOT/plugins" -path '*/hooks/hooks.json' -type f 2>/dev/null | sort)

# Emit structured report.
echo ""
echo "═══════════════════════════════════════════════════════════════════════════"
echo "  Stop-Hook Schema-Correctness Audit Summary"
echo "═══════════════════════════════════════════════════════════════════════════"
echo "  Total registered Stop hooks scanned:           $total_registered_stop_hooks"
echo "  CLEAN (no additionalContext in code):          $no_additionalContext_count"
echo "  WITH-OK-MARKER (justified internal usage):     $with_ok_marker_count"
echo "  EMISSION-VIOLATION (silent-drop risk):         $emission_violation_count"
echo ""

if [ "$emission_violation_count" -gt 0 ]; then
  echo "─── EMISSION-VIOLATION ($emission_violation_count) — Stop hooks emitting additionalContext to /dev/null from Claude Code's perspective ───"
  printf "%s" "$VIOLATION_LINES"
  echo ""
  echo "═══════════════════════════════════════════════════════════════════════════"
  echo "  EXITING NON-ZERO — release:preflight should gate on this."
  echo "═══════════════════════════════════════════════════════════════════════════"
  exit 1
fi

echo "═══════════════════════════════════════════════════════════════════════════"
echo "  ✓ No Stop hooks emit additionalContext to stdout JSON. All registered"
echo "    Stop hooks honor the official Anthropic schema ({decision, reason})."
echo "═══════════════════════════════════════════════════════════════════════════"
