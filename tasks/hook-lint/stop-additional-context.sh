#!/usr/bin/env bash
# Audit every plugins/*/hooks/hooks.json REGISTERED Stop, SubagentStop, SessionEnd, PreCompact and Notification hook source file for the additionalContext field in non-comment code. For Stop and SubagentStop the field is NOT dropped: upstream "Stop decision control" (https://code.claude.com/docs/en/hooks#stop-decision-control) documents hookSpecificOutput.additionalContext as feedback that keeps the conversation going ("The conversation continues so Claude can act on it"), through the same loop protections as decision:"block". So an informational Stop summary emitted that way forces another turn instead of informing anyone; real continuation should be an explicit decision:"block" + reason. PreCompact, SessionEnd and Notification have no additionalContext in their output schema. Strips JSDoc and line comments before scanning. Escape hatch: STOP-HOOK-ADDITIONAL-CONTEXT-OK source comment with reason >= 10 chars applies to all five event types. Exits non-zero on any unjustified use.
#
# tasks/hook-lint/stop-additional-context.sh
#
# Why each event type is in scope (upstream: https://code.claude.com/docs/en/hooks):
#
#   1. Stop / SubagentStop. The "Stop decision control" table lists
#      `hookSpecificOutput.additionalContext` as "Non-error feedback for
#      Claude. The conversation continues so Claude can act on it, but
#      unlike `decision: "block"` it is shown in the transcript as hook
#      feedback rather than a hook error", and adds: "It keeps the
#      conversation going through the same loop protections as
#      `decision: "block"`, namely the `stop_hook_active` input and the
#      8-consecutive-continuation cap". SubagentStop "use[s] the same
#      decision control format as Stop hooks". A Stop hook that prints an
#      informational summary this way therefore prevents Claude from
#      stopping on every turn it fires, up to the cap. That is the hazard
#      this audit guards: the itp-hooks stop-orchestrator once emitted its
#      aggregated subhook summary as additionalContext; it now routes that
#      summary to stderr. A hook that genuinely wants Claude to continue
#      should say so with decision:"block" + reason, or carry the marker.
#   2. PreCompact. The decision-control table gives PreCompact only
#      top-level `decision: "block"` + `reason`; "Stop and SubagentStop
#      also accept `hookSpecificOutput.additionalContext`", PreCompact
#      does not, so the field is ignored.
#   3. SessionEnd. "SessionEnd hooks have no decision control ... Claude
#      Code discards their JSON output fields".
#   4. Notification. No decision control and no additionalContext field.
#
#   Events that DO deliver additionalContext to Claude (PreToolUse,
#   PostToolUse, PostToolUseFailure, PostToolBatch, UserPromptSubmit,
#   UserPromptExpansion, SessionStart, …) are out of scope.
#
# What this audit checks:
#
#   For every plugins/*/hooks/hooks.json that registers one of the five
#   event types above, resolve the source file the hook command points to
#   and scan it for the literal `additionalContext` token after stripping
#   // line comments and /* */ block comments, so documentation references
#   do not false-positive.
#
# Escape hatch (legitimate uses):
#
#   A hook that READS additionalContext from subhook stdout as part of an
#   internal aggregation protocol (and does not re-emit it), or a Stop hook
#   that deliberately uses it to continue the conversation, adds:
#
#     // STOP-HOOK-ADDITIONAL-CONTEXT-OK: <reason ≥ 10 chars>
#     # STOP-HOOK-ADDITIONAL-CONTEXT-OK: <reason ≥ 10 chars>
#
#   The 10-char minimum prevents low-effort opt-outs like "ok" or "tbd".
#
# What this audit does NOT check (out of scope):
#
#   - Hooks not registered for these events in hooks.json — orchestrator
#     subhooks may legitimately pass additionalContext to their parent.
#   - Data flow: a field name built dynamically is not seen. Static
#     scanning with comment-stripping catches the common cases.
#
# Re-run cadence:
#   - Manual: `bash tasks/hook-lint/stop-additional-context.sh`
#   - Automatic: `moon run repo:hook-lint` and release preflight Check 4j.

set -euo pipefail
shopt -u patsub_replacement 2>/dev/null || true

# REPO_ROOT defaults to the cc-skills working tree (resolved from this
# task's location). Override via AUDIT_REPO_ROOT_OVERRIDE for testing
# the audit against a synthetic-fixture fleet.
REPO_ROOT="${AUDIT_REPO_ROOT_OVERRIDE:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"

# Hook-command parsing SSoT. Resolved from THIS FILE's location, not from
# REPO_ROOT — AUDIT_REPO_ROOT_OVERRIDE points at a synthetic fixture tree that
# has no tasks/lib/.
AUDIT_TASK_DIRECTORY_ABSOLUTE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=tasks/lib/hook-command-parsing.sh
source "$AUDIT_TASK_DIRECTORY_ABSOLUTE/../lib/hook-command-parsing.sh"

# Minimum length of STOP-HOOK-ADDITIONAL-CONTEXT-OK justification.
MIN_OK_REASON_LENGTH=10

echo "═══════════════════════════════════════════════════════════════════════════"
echo "  additionalContext-Silently-Dropped Pentad Audit"
echo "  (Stop / SubagentStop / SessionEnd / PreCompact / Notification)"
echo "  (iter-67 audit + iter-68 trinity expansion + iter-69 pentad completion)"
echo "═══════════════════════════════════════════════════════════════════════════"
echo "→ Scans registered Stop, SubagentStop, SessionEnd, PreCompact, AND"
echo "  Notification hook source files for additionalContext emission."
echo "→ Per https://code.claude.com/docs/en/hooks:"
echo "  • Stop, SubagentStop: additionalContext KEEPS THE CONVERSATION GOING"
echo "    (\"Stop decision control\"), so informational output there forces"
echo "    another turn; use decision:'block' + reason when continuing is intended"
echo "  • PreCompact: reads only {decision:'block', reason}; the field is ignored"
echo "  • SessionEnd: JSON output fields are discarded"
echo "  • Notification: no decision control, no additionalContext field"
echo "→ Comment-aware: strips // line and /* */ block comments before scan,"
echo "  so JSDoc references (like iter-66 forensic docs) don't false-positive."
echo "→ Escape hatch: 'STOP-HOOK-ADDITIONAL-CONTEXT-OK: <reason>' source"
echo "  comment with reason ≥ ${MIN_OK_REASON_LENGTH} chars. (Marker name is"
echo "  historical from iter-67 Stop-only scope; per iter-68/69 it applies"
echo "  equivalently to SubagentStop, SessionEnd, PreCompact, Notification.)"
echo ""

# Classification counters (aggregate across all five event types in the pentad).
no_additionalContext_count=0
with_ok_marker_count=0
emission_violation_count=0
total_scanned_event_terminal_hooks=0

# Per-event-type counters for precise summary breakdown.
# Initialize each pentad-member event type to 0 so the summary table always
# shows all five rows (clarifies "no hooks of type X exist" vs. "audit
# skipped X"). Pentad order matches iter-66 → iter-67 → iter-68 → iter-69
# expansion sequence for forensic traceability.
declare -A scanned_count_by_event_type=( ["Stop"]=0 ["SubagentStop"]=0 ["SessionEnd"]=0 ["PreCompact"]=0 ["Notification"]=0 )
declare -A violation_count_by_event_type=( ["Stop"]=0 ["SubagentStop"]=0 ["SessionEnd"]=0 ["PreCompact"]=0 ["Notification"]=0 )

# Accumulator for violation report
VIOLATION_LINES=""

# Helper: extract the hook source basename from a hooks.json command string,
# via the repo-wide parsing SSoT (tasks/lib/hook-command-parsing.sh).
#
# The former body was `${cmd##*/}` then `%% *` — "last /-segment, first
# whitespace token" — a shape guess rather than a parse. It returns `b` for
# `bun …/hooks/stop-foo.ts --config a/b` and is only correct today because no
# marketplace hook command carries an argument. Same defect class as the
# iter-92 and async-true audits, which silently audited zero hooks once the
# `env -u AI_AGENT -u CLAUDECODE` prefix landed.
extract_hook_basename_from_command_string() {
  extract_hook_script_basename_from_hook_command "$1"
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
      source_path=$(find "$REPO_ROOT/plugins" -mindepth 3 -maxdepth 3 -name "$hook_basename" -path '*/hooks/*' -type f 2>/dev/null | grep -v '/tests/' | head -1)  # iter-125: bounded depth fallback
    fi

    if [ -z "$source_path" ] || [ ! -f "$source_path" ]; then
      echo "  ⊘ SOURCE-NOT-FOUND ($event_type): $plugin_name/$hook_basename (skipped)"
      continue
    fi

    # Strip comments and search for additionalContext in remaining code.
    code_only=$(strip_comments_from_source_for_pure_code_scan "$source_path")

    if ! grep -q 'additionalContext' <<<"$code_only"; then
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
        VIOLATION_LINES+="               Upstream \"Stop decision control\" (code.claude.com/docs/en/hooks"$'\n'
        VIOLATION_LINES+="               #stop-decision-control): hookSpecificOutput.additionalContext on a"$'\n'
        VIOLATION_LINES+="               ${event_type} hook is feedback that keeps the conversation going —"$'\n'
        VIOLATION_LINES+="               \"The conversation continues so Claude can act on it\" — through the"$'\n'
        VIOLATION_LINES+="               same loop protections as decision:\"block\" (stop_hook_active, the"$'\n'
        VIOLATION_LINES+="               8-consecutive-continuation cap). Informational output emitted this"$'\n'
        VIOLATION_LINES+="               way stops Claude from stopping instead of informing anyone."$'\n'
        ;;
      PreCompact)
        VIOLATION_LINES+="               Per official Anthropic ${event_type}-hook schema (decision-control"$'\n'
        VIOLATION_LINES+="               table at code.claude.com/docs/en/hooks, where only Stop and"$'\n'
        VIOLATION_LINES+="               SubagentStop also accept additionalContext), ${event_type} hooks read"$'\n'
        VIOLATION_LINES+="               ONLY {decision:'block', reason} from stdout JSON. Any"$'\n'
        VIOLATION_LINES+="               additionalContext field is silently dropped — the hook author sees"$'\n'
        VIOLATION_LINES+="               the field being emitted, but Claude Code never reads it."$'\n'
        ;;
      SessionEnd)
        VIOLATION_LINES+="               Per Go type definitions in CorridorSecurity/hookshot (mirroring"$'\n'
        VIOLATION_LINES+="               the official schema), SessionEndOK returns EMPTY output —"$'\n'
        VIOLATION_LINES+="               SessionEnd hooks cannot inject any context (session is"$'\n'
        VIOLATION_LINES+="               terminating). Any additionalContext field (or any other output"$'\n'
        VIOLATION_LINES+="               field) is silently dropped — the hook author sees the field being"$'\n'
        VIOLATION_LINES+="               emitted, but Claude Code never reads it."$'\n'
        ;;
      Notification)
        VIOLATION_LINES+="               Per official Anthropic docs (code.claude.com/docs/en/hooks),"$'\n'
        VIOLATION_LINES+="               Notification hooks are purely informational with NO decision-"$'\n'
        VIOLATION_LINES+="               control capability ('Exit Code 2 Behavior: N/A — shows stderr to"$'\n'
        VIOLATION_LINES+="               user only, no blocking capability'). Subtypes: permission_prompt,"$'\n'
        VIOLATION_LINES+="               idle_prompt, auth_success. Any output field including"$'\n'
        VIOLATION_LINES+="               additionalContext is silently dropped — only stderr on exit 2"$'\n'
        VIOLATION_LINES+="               reaches the user."$'\n'
        ;;
    esac
    VIOLATION_LINES+="      Fix:     route informational summary text to PROCESS.STDERR instead of stdout"$'\n'
    VIOLATION_LINES+="               JSON. Stderr is transcript-visible via Ctrl-R. For Stop/SubagentStop,"$'\n'
    VIOLATION_LINES+="               when Claude really should continue, say so explicitly with"$'\n'
    VIOLATION_LINES+="               decision:\"block\" + reason (or keep additionalContext and add the"$'\n'
    VIOLATION_LINES+="               marker below with the reason). SessionEnd cannot inject context at all"$'\n'
    VIOLATION_LINES+="               — for end-of-session context use SessionStart on the NEXT session."$'\n'
    VIOLATION_LINES+="               Notification can only surface via stderr on exit 2 — for context"$'\n'
    VIOLATION_LINES+="               injection use a different event type (UserPromptSubmit, SessionStart)."$'\n'
    VIOLATION_LINES+="               OR add to source: // STOP-HOOK-ADDITIONAL-CONTEXT-OK: <reason ≥ ${MIN_OK_REASON_LENGTH} chars>"$'\n'
    VIOLATION_LINES+="      Refs:    iter-66 (single-hook orchestrator fix), iter-67 (Stop-only audit),"$'\n'
    VIOLATION_LINES+="               iter-68 (audit scope expansion to SubagentStop + SessionEnd),"$'\n'
    VIOLATION_LINES+="               iter-69 (pentad completion: + PreCompact + Notification),"$'\n'
    VIOLATION_LINES+="               https://code.claude.com/docs/en/hooks#stop-decision-control"$'\n'
    VIOLATION_LINES+="               (official docs)."$'\n'

  done < <(jq -r '
    (.hooks // {}) | to_entries[]
    | select(.key == "Stop" or .key == "SubagentStop" or .key == "SessionEnd" or .key == "PreCompact" or .key == "Notification")
    | . as $entry
    | $entry.value[]?
    | .hooks[]?.command // empty
    | "\($entry.key)\t\(.)"
  ' "$hooks_json" 2>/dev/null)

done < <(find "$REPO_ROOT/plugins" -mindepth 3 -maxdepth 3 -name 'hooks.json' -type f 2>/dev/null | sort)  # iter-125: bounded depth, ~65ms -> ~7ms

# Emit structured report.
echo ""
echo "═══════════════════════════════════════════════════════════════════════════"
echo "  additionalContext-Silently-Dropped Pentad Audit Summary"
echo "  (Stop / SubagentStop / SessionEnd / PreCompact / Notification)"
echo "═══════════════════════════════════════════════════════════════════════════"
echo "  Total registered pentad-member hooks scanned: $total_scanned_event_terminal_hooks"
echo "  CLEAN (no additionalContext in code):          $no_additionalContext_count"
echo "  WITH-OK-MARKER (justified internal usage):     $with_ok_marker_count"
echo "  EMISSION-VIOLATION (silent-drop risk):         $emission_violation_count"
echo ""
echo "  Per-event-type breakdown (scanned / violations):"
printf "    Stop:         %s scanned / %s violations\n" "${scanned_count_by_event_type[Stop]}" "${violation_count_by_event_type[Stop]}"
printf "    SubagentStop: %s scanned / %s violations\n" "${scanned_count_by_event_type[SubagentStop]}" "${violation_count_by_event_type[SubagentStop]}"
printf "    SessionEnd:   %s scanned / %s violations\n" "${scanned_count_by_event_type[SessionEnd]}" "${violation_count_by_event_type[SessionEnd]}"
printf "    PreCompact:   %s scanned / %s violations\n" "${scanned_count_by_event_type[PreCompact]}" "${violation_count_by_event_type[PreCompact]}"
printf "    Notification: %s scanned / %s violations\n" "${scanned_count_by_event_type[Notification]}" "${violation_count_by_event_type[Notification]}"
echo ""

if [ "$emission_violation_count" -gt 0 ]; then
  echo "─── EMISSION-VIOLATION ($emission_violation_count) — pentad-member hooks emitting additionalContext to /dev/null from Claude Code's perspective ───"
  printf "%s" "$VIOLATION_LINES"
  echo ""
  echo "═══════════════════════════════════════════════════════════════════════════"
  echo "  EXITING NON-ZERO — release:preflight should gate on this."
  echo "═══════════════════════════════════════════════════════════════════════════"
  exit 1
fi

echo "═══════════════════════════════════════════════════════════════════════════"
echo "  ✓ No Stop, SubagentStop, SessionEnd, PreCompact, or Notification hook"
echo "    uses additionalContext without a justified marker. (Stop/SubagentStop:"
echo "    it would keep the conversation going; PreCompact/SessionEnd/"
echo "    Notification: it is not part of their output schema.)"
echo "═══════════════════════════════════════════════════════════════════════════"
