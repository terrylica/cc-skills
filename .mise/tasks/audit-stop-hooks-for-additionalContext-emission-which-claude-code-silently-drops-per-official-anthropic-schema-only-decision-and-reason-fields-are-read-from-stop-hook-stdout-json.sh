#!/usr/bin/env bash
#MISE description="Audit every plugins/*/hooks/hooks.json REGISTERED Stop, SubagentStop, AND SessionEnd hook source file for emission of the additionalContext field in stdout JSON. All three event types share the same silent-drop mechanism: Stop+SubagentStop hooks read only {decision, reason} per Anthropic schema (GitHub #19115); SessionEnd hooks read NO output fields at all (per Go type definitions in CorridorSecurity/hookshot — SessionEndOK returns empty output, session is terminating). Any additionalContext field on these three event types is silently dropped by Claude Code. iter-66 fixed the itp-hooks stop-orchestrator silent-drop bug; iter-67 scaled the fix into a Stop-only audit; iter-68 extends coverage to SubagentStop + SessionEnd (iter-67 deferred SubagentStop explicitly; SessionEnd added preventively per same schema family). Strips JSDoc and line comments before scanning. Escape hatch: STOP-HOOK-ADDITIONAL-CONTEXT-OK source comment with reason ≥ 10 chars applies to all three event types. Exits non-zero on any unjustified emission. Symmetric companion to iter-60 / iter-62 / iter-65 / iter-67 schema-correctness gates."
#
# audit-stop-hooks-for-additionalContext-emission-which-claude-code-silently-drops-per-official-anthropic-schema-only-decision-and-reason-fields-are-read-from-stop-hook-stdout-json
#
# Iter-67 self-explanatory-scaffolding audit — preventive companion to
# iter-66 (single-hook orchestrator additionalContext silent-drop fix).
# Iter-68 expansion: extended scope from Stop-only to the full trinity
# of additionalContext-silently-dropped event types — Stop, SubagentStop,
# and SessionEnd. See "Iter-68 scope expansion" section below.
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
# Iter-68 scope expansion (post-event-terminal-additionalContext trinity):
#
#   Iter-67 covered only Stop hooks and explicitly deferred SubagentStop
#   (file comment line 74: "SubagentStop hooks (same schema rules,
#   separate audit if needed)"). Iter-68 extends coverage to the full
#   trinity of event types where additionalContext is silently dropped:
#
#     1. Stop hooks — reads only {decision, reason} per iter-66/67.
#     2. SubagentStop hooks — same schema as Stop per
#        https://code.claude.com/docs/en/hooks ("SubagentStop hooks
#        use the same decision control format as Stop hooks"). Marketplace
#        has 0 registrations today; preventive gate catches future
#        regressions when subagent-based workflows add SubagentStop hooks.
#     3. SessionEnd hooks — per Go type definitions in CorridorSecurity/
#        hookshot (https://pkg.go.dev/github.com/CorridorSecurity/hookshot/
#        claude), SessionEndOK returns EMPTY output — SessionEnd cannot
#        inject any context because the session is terminating. Any
#        additionalContext (or any other output field) is silently
#        dropped. Marketplace has 0 registrations today; preventive gate.
#
#   All three event types share the same root cause (the field is
#   absent from the consumer-side schema), the same operator-facing
#   symptom (silent drop), and the same remediation (route summary
#   text to stderr instead of stdout JSON, OR for legitimate read-only
#   aggregation, add an OK marker). Unifying them under one audit
#   reduces conceptual surface area and per-event-type tracking gives
#   precise violation diagnostics.
#
# What this audit checks:
#
#   For every plugins/*/hooks/hooks.json that registers a Stop,
#   SubagentStop, or SessionEnd hook, resolve the source file pointed
#   to by the hook command and scan for the literal `additionalContext`
#   token. Strips line comments (// ...) and JSDoc block comments
#   (/* ... */) before scanning, so documentation references like the
#   iter-66 forensic JSDoc block don't false-positive.
#
# Escape hatch (legitimate uses):
#
#   Some hooks READ additionalContext from subhook stdout as part of
#   an internal aggregation protocol — that's safe (the orchestrator
#   reads it but doesn't re-emit it). To opt out of the audit for
#   these cases, add to the source:
#
#     // STOP-HOOK-ADDITIONAL-CONTEXT-OK: <reason ≥ 10 chars>
#     # STOP-HOOK-ADDITIONAL-CONTEXT-OK: <reason ≥ 10 chars>
#
#   The marker name is historical (introduced in iter-67 for Stop
#   hooks); per iter-68 expansion it now applies equivalently to
#   SubagentStop and SessionEnd hooks. The 10-char minimum prevents
#   low-effort opt-outs like "ok" or "tbd". The reason should explain
#   WHY the source references additionalContext despite the schema not
#   supporting it (typical: "reads additionalContext from subhook
#   stdout, routes aggregated text to stderr per iter-66 fix" for
#   orchestrators).
#
# What this audit does NOT check (out of scope):
#
#   - Hooks NOT registered as Stop/SubagentStop/SessionEnd hooks in
#     hooks.json — they're subhooks invoked by orchestrators, can
#     legitimately emit additionalContext to a parent orchestrator
#     over their stdout.
#   - Whether additionalContext appears in JSON.stringify call sites
#     via data-flow analysis. Static analysis with comment-stripping
#     catches the common cases; deep data-flow would require AST
#     analysis. Operator can use the OK marker after manual review.
#
# Verbose name encodes WHAT it audits (Stop hooks — file name was
# fixed in iter-67 before SubagentStop+SessionEnd expansion landed
# in iter-68; renaming the file would invalidate operator muscle
# memory and the release:preflight Check 4j invocation. The MISE
# description field is the authoritative scope declaration; this
# header comment block contains the per-event-type details). WHICH
# anti-pattern (additionalContext emission), WHY it matters (Claude
# Code silently drops per schema), and the authoritative schema fact
# (only decision + reason for Stop+SubagentStop; nothing read at all
# for SessionEnd). Future maintainers searching for "stop hook
# additionalContext", "subagent stop additionalContext",
# "session end additionalContext", "stop hook silent drop",
# "GitHub 19115", "iter-66", "iter-67", or "iter-68" surface this
# audit immediately.
#
# Re-run cadence:
#   - Manual: `mise run audit-stop-hooks-for-additionalContext-emission-...`
#   - Automatic: release:preflight Check 4j (iter-67 wire-up,
#     iter-68 scope expansion preserved through Check 4j).

set -euo pipefail
shopt -u patsub_replacement 2>/dev/null || true

# REPO_ROOT defaults to the cc-skills working tree (resolved from this
# task's location). Override via AUDIT_REPO_ROOT_OVERRIDE for testing
# the audit against a synthetic-fixture fleet.
REPO_ROOT="${AUDIT_REPO_ROOT_OVERRIDE:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"

# Minimum length of STOP-HOOK-ADDITIONAL-CONTEXT-OK justification.
MIN_OK_REASON_LENGTH=10

echo "═══════════════════════════════════════════════════════════════════════════"
echo "  Stop / SubagentStop / SessionEnd additionalContext-Emission Audit"
echo "  (iter-67 audit + iter-68 scope expansion)"
echo "═══════════════════════════════════════════════════════════════════════════"
echo "→ Scans registered Stop, SubagentStop, AND SessionEnd hook source files"
echo "  for additionalContext emission."
echo "→ Per official Anthropic schema (GitHub #19115 + code.claude.com/docs/en/"
echo "  hooks), Stop and SubagentStop hooks read ONLY {decision, reason}; per"
echo "  Go type defs (CorridorSecurity/hookshot), SessionEnd reads NOTHING"
echo "  (empty output — session is terminating). Any additionalContext field"
echo "  on these three event types is silently dropped — operator gets no"
echo "  transcript visibility, Claude gets no context. The hook author sees"
echo "  JSON being emitted normally."
echo "→ Comment-aware: strips // line and /* */ block comments before scan,"
echo "  so JSDoc references (like iter-66 forensic docs) don't false-positive."
echo "→ Escape hatch: 'STOP-HOOK-ADDITIONAL-CONTEXT-OK: <reason>' source"
echo "  comment with reason ≥ ${MIN_OK_REASON_LENGTH} chars. (Marker name is"
echo "  historical from iter-67 Stop-only scope; per iter-68 it applies"
echo "  equivalently to SubagentStop and SessionEnd hooks.)"
echo ""

# Classification counters (aggregate across all three event types).
no_additionalContext_count=0
with_ok_marker_count=0
emission_violation_count=0
total_scanned_event_terminal_hooks=0

# Per-event-type counters for precise summary breakdown.
# Initialize each event type to 0 so the summary table always shows all
# three rows (clarifies "no hooks of type X exist" vs. "audit skipped X").
declare -A scanned_count_by_event_type=( ["Stop"]=0 ["SubagentStop"]=0 ["SessionEnd"]=0 )
declare -A violation_count_by_event_type=( ["Stop"]=0 ["SubagentStop"]=0 ["SessionEnd"]=0 )

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

# Walk every hooks.json that registers Stop, SubagentStop, or SessionEnd
# hooks. The jq filter emits TSV "event_type\tcommand" so the bash loop
# can attribute each scan to its event type for per-event-type accounting
# in the summary table.
while IFS= read -r hooks_json; do
  [ -f "$hooks_json" ] || continue

  plugin_dir=$(dirname "$(dirname "$hooks_json")")
  plugin_name=$(basename "$plugin_dir")

  # For each registered Stop/SubagentStop/SessionEnd hook, emit
  # "<event_type>\t<command>" TSV. Reading the event type per-hook lets
  # us attribute scan counts and violations to the originating event
  # type in the summary table — operators see "1 Stop violation, 2
  # SessionEnd violations" not just "3 violations".
  while IFS=$'\t' read -r event_type hook_command; do
    [ -z "$hook_command" ] && continue
    total_scanned_event_terminal_hooks=$((total_scanned_event_terminal_hooks + 1))
    scanned_count_by_event_type[$event_type]=$((scanned_count_by_event_type[$event_type] + 1))

    hook_basename=$(extract_hook_basename_from_command_string "$hook_command")

    # Resolve source file. Try plugin's hooks/ dir first.
    source_path="$plugin_dir/hooks/$hook_basename"
    if [ ! -f "$source_path" ]; then
      # Try repo-wide find as fallback (for synthetic fixtures).
      source_path=$(find "$REPO_ROOT/plugins" -name "$hook_basename" -path '*/hooks/*' -type f 2>/dev/null | grep -v '/tests/' | head -1)
    fi

    if [ -z "$source_path" ] || [ ! -f "$source_path" ]; then
      echo "  ⊘ SOURCE-NOT-FOUND ($event_type): $plugin_name/$hook_basename (skipped)"
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
      echo "  ◯ WITH-OK-MARKER ($event_type): $plugin_name/hooks/$hook_basename"
      continue
    fi

    # Violation. Per-event-type schema diagnostic so the operator sees
    # the precise schema rule violated (Stop+SubagentStop have a 2-field
    # schema; SessionEnd has an empty-output schema).
    emission_violation_count=$((emission_violation_count + 1))
    violation_count_by_event_type[$event_type]=$((violation_count_by_event_type[$event_type] + 1))
    VIOLATION_LINES+="  ✗ ($event_type) $plugin_name/hooks/$hook_basename"$'\n'
    VIOLATION_LINES+="      Issue:   source references 'additionalContext' in non-comment code."$'\n'
    case "$event_type" in
      Stop|SubagentStop)
        VIOLATION_LINES+="               Per official Anthropic ${event_type}-hook schema (verbatim in"$'\n'
        VIOLATION_LINES+="               GitHub #19115; ${event_type} uses the same decision-control format"$'\n'
        VIOLATION_LINES+="               as Stop per code.claude.com/docs/en/hooks), ${event_type} hooks read"$'\n'
        VIOLATION_LINES+="               ONLY {decision, reason} from stdout JSON. Any additionalContext"$'\n'
        VIOLATION_LINES+="               field is silently dropped — the hook author sees the field being"$'\n'
        VIOLATION_LINES+="               emitted, but Claude Code never reads it."$'\n'
        ;;
      SessionEnd)
        VIOLATION_LINES+="               Per Go type definitions in CorridorSecurity/hookshot (mirroring"$'\n'
        VIOLATION_LINES+="               the official schema), SessionEndOK returns EMPTY output —"$'\n'
        VIOLATION_LINES+="               SessionEnd hooks cannot inject any context (session is"$'\n'
        VIOLATION_LINES+="               terminating). Any additionalContext field (or any other output"$'\n'
        VIOLATION_LINES+="               field) is silently dropped — the hook author sees the field being"$'\n'
        VIOLATION_LINES+="               emitted, but Claude Code never reads it."$'\n'
        ;;
    esac
    VIOLATION_LINES+="      Fix:     route the summary text to PROCESS.STDERR instead of stdout JSON."$'\n'
    VIOLATION_LINES+="               Stderr is transcript-visible via Ctrl-R; operators can still see"$'\n'
    VIOLATION_LINES+="               summaries during debugging. For Stop/SubagentStop only, to inject"$'\n'
    VIOLATION_LINES+="               context that Claude actually reads on next turn, use"$'\n'
    VIOLATION_LINES+="               decision:\"block\" + reason (which keeps Claude running and surfaces"$'\n'
    VIOLATION_LINES+="               reason as a system reminder). SessionEnd cannot inject context at all"$'\n'
    VIOLATION_LINES+="               — for end-of-session context use SessionStart on the NEXT session."$'\n'
    VIOLATION_LINES+="               OR add to source: // STOP-HOOK-ADDITIONAL-CONTEXT-OK: <reason ≥ ${MIN_OK_REASON_LENGTH} chars>"$'\n'
    VIOLATION_LINES+="      Refs:    iter-66 (single-hook orchestrator fix), iter-67 (Stop-only audit),"$'\n'
    VIOLATION_LINES+="               iter-68 (audit scope expansion to SubagentStop + SessionEnd),"$'\n'
    VIOLATION_LINES+="               GitHub #19115 (Anthropic schema verbatim example),"$'\n'
    VIOLATION_LINES+="               https://code.claude.com/docs/en/hooks (official docs)."$'\n'

  done < <(jq -r '
    (.hooks // {}) | to_entries[]
    | select(.key == "Stop" or .key == "SubagentStop" or .key == "SessionEnd")
    | . as $entry
    | $entry.value[]?
    | .hooks[]?.command // empty
    | "\($entry.key)\t\(.)"
  ' "$hooks_json" 2>/dev/null)

done < <(find "$REPO_ROOT/plugins" -path '*/hooks/hooks.json' -type f 2>/dev/null | sort)

# Emit structured report.
echo ""
echo "═══════════════════════════════════════════════════════════════════════════"
echo "  Stop / SubagentStop / SessionEnd Schema-Correctness Audit Summary"
echo "═══════════════════════════════════════════════════════════════════════════"
echo "  Total registered Stop hooks scanned:           $total_scanned_event_terminal_hooks"
echo "  CLEAN (no additionalContext in code):          $no_additionalContext_count"
echo "  WITH-OK-MARKER (justified internal usage):     $with_ok_marker_count"
echo "  EMISSION-VIOLATION (silent-drop risk):         $emission_violation_count"
echo ""
echo "  Per-event-type breakdown (scanned / violations):"
printf "    Stop:         %s scanned / %s violations\n" "${scanned_count_by_event_type[Stop]}" "${violation_count_by_event_type[Stop]}"
printf "    SubagentStop: %s scanned / %s violations\n" "${scanned_count_by_event_type[SubagentStop]}" "${violation_count_by_event_type[SubagentStop]}"
printf "    SessionEnd:   %s scanned / %s violations\n" "${scanned_count_by_event_type[SessionEnd]}" "${violation_count_by_event_type[SessionEnd]}"
echo ""

if [ "$emission_violation_count" -gt 0 ]; then
  echo "─── EMISSION-VIOLATION ($emission_violation_count) — Stop/SubagentStop/SessionEnd hooks emitting additionalContext to /dev/null from Claude Code's perspective ───"
  printf "%s" "$VIOLATION_LINES"
  echo ""
  echo "═══════════════════════════════════════════════════════════════════════════"
  echo "  EXITING NON-ZERO — release:preflight should gate on this."
  echo "═══════════════════════════════════════════════════════════════════════════"
  exit 1
fi

echo "═══════════════════════════════════════════════════════════════════════════"
echo "  ✓ No Stop, SubagentStop, or SessionEnd hooks emit additionalContext to"
echo "    stdout JSON. All three event types honor their respective official"
echo "    Anthropic schemas (Stop+SubagentStop: {decision, reason} only;"
echo "    SessionEnd: empty output)."
echo "═══════════════════════════════════════════════════════════════════════════"
