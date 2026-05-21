#!/usr/bin/env bash
#MISE description="Audit every plugins/*/hooks/hooks.json REGISTERED Stop, SubagentStop, SessionEnd, PreCompact, AND Notification hook source file for emission of the additionalContext field in stdout JSON. All five event types share the same silent-drop mechanism but with three distinct schema sub-rules: (1) Stop+SubagentStop+PreCompact read only {decision:'block', reason} per Anthropic docs (code.claude.com/docs/en/hooks); (2) SessionEnd reads NO output fields at all (per Go type definitions in CorridorSecurity/hookshot — SessionEndOK returns empty output, session is terminating); (3) Notification is purely informational with no decision/blocking capability (Anthropic docs: 'no blocking — exit 2 shows stderr only'). Any additionalContext field on any of these five event types is silently dropped by Claude Code. iter-66 fixed the itp-hooks stop-orchestrator silent-drop bug; iter-67 scaled to a Stop-only audit; iter-68 extended to SubagentStop + SessionEnd; iter-69 completes the additionalContext-silently-dropped pentad by adding PreCompact + Notification. Strips JSDoc and line comments before scanning. Escape hatch: STOP-HOOK-ADDITIONAL-CONTEXT-OK source comment with reason ≥ 10 chars applies to all five event types. Exits non-zero on any unjustified emission. Symmetric companion to iter-60 / iter-62 / iter-65 / iter-67 schema-correctness gates."
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
# Iter-68/69 scope expansion (additionalContext-silently-dropped pentad):
#
#   Iter-67 covered only Stop hooks and explicitly deferred SubagentStop
#   (file comment line 74: "SubagentStop hooks (same schema rules,
#   separate audit if needed)"). Iter-68 extended to SubagentStop +
#   SessionEnd. Iter-69 completes the pentad by adding PreCompact +
#   Notification — the remaining two hook event types where
#   additionalContext is silently dropped per official Anthropic schema:
#
#     1. Stop hooks — reads only {decision:'block', reason} per
#        iter-66/67. additionalContext silently dropped.
#     2. SubagentStop hooks — same schema as Stop per
#        https://code.claude.com/docs/en/hooks ("SubagentStop hooks
#        use the same decision control format as Stop hooks").
#        additionalContext silently dropped. Marketplace 0.
#     3. SessionEnd hooks — per Go type definitions in CorridorSecurity/
#        hookshot (https://pkg.go.dev/github.com/CorridorSecurity/hookshot/
#        claude), SessionEndOK returns EMPTY output — SessionEnd cannot
#        inject any context because the session is terminating. Any
#        additionalContext (or any other output field) is silently
#        dropped. Marketplace 0.
#     4. PreCompact hooks (iter-69) — supports only {decision:'block',
#        reason} per official Anthropic docs (the 'decision' field is
#        used by UserPromptSubmit, UserPromptExpansion, PostToolUse,
#        PostToolUseFailure, PostToolBatch, Stop, SubagentStop,
#        ConfigChange, and PreCompact — the only value is 'block').
#        additionalContext is NOT in the PreCompact output schema.
#        Common use case: pre-compaction transcript backup via
#        async: true (Jan 2026 feature). Marketplace 0.
#     5. Notification hooks (iter-69) — purely informational, NO decision
#        capability per official docs ('Exit Code 2 Behavior: N/A —
#        shows stderr to user only, no blocking capability'). Subtypes:
#        permission_prompt, idle_prompt, auth_success. Any output field
#        including additionalContext is silently dropped — only stderr
#        on exit 2 reaches the user. Marketplace 0.
#
#   All five event types share the same root cause (the field is
#   absent from the consumer-side schema), the same operator-facing
#   symptom (silent drop), and the same remediation (route summary
#   text to stderr instead of stdout JSON, OR for legitimate read-only
#   aggregation, add an OK marker). Unifying them under one audit
#   reduces conceptual surface area and per-event-type tracking gives
#   precise violation diagnostics.
#
#   Events EXCLUDED from this audit because they DO support
#   additionalContext (and emitting it is CORRECT, not a violation):
#     - PreToolUse / PostToolUse — hookSpecificOutput.additionalContext
#       (caveat: GitHub #55889 documents v2.1.123 regression where Bash
#       matcher silently drops all 3 context channels; that's a runtime
#       bug, not a schema bug — out of scope for this static audit. See
#       docs/HOOKS.md "Runtime Bash-Matcher Context-Channel Silent Drop"
#       section for operator-facing guidance on the bug.)
#     - UserPromptSubmit / SessionStart — hookSpecificOutput.additional-
#       Context + plain stdout both reach Claude.
#     - UserPromptExpansion (iter-71 verified) — joined with
#       UserPromptSubmit and SessionStart as the 3 events where stdout
#       is added directly to Claude's context. Per official Anthropic
#       docs (code.claude.com/docs/en/hooks), this is the documented
#       3-event "stdout-reaches-context" cohort.
#     - PostToolBatch (iter-71 verified) — additionalContext appears
#       "next to the tool result" per the official Anthropic docs.
#       NOT a silent-drop event.
#     - PostToolUseFailure (iter-71 verified) — documented schema
#       shape: { "hookSpecificOutput": { "hookEventName":
#       "PostToolUseFailure", "additionalContext": "..." } }. NOT a
#       silent-drop event.
#
#   2026 event-type landscape note (iter-71 research, May 2026 v2.1.141+):
#     The full 27-event 2026 set includes many newer event types not
#     yet covered by this audit: SubagentStart, StopFailure, PostCompact,
#     Setup, PermissionRequest, PermissionDenied, InstructionsLoaded,
#     CwdChanged, FileChanged, WorktreeCreate, WorktreeRemove,
#     ConfigChange, TeammateIdle, TaskCreated, TaskCompleted, Elicitation,
#     ElicitationResult. Their additionalContext support varies:
#       • Setup: documented as supporting additionalContext for context
#         injection (cannot block; observability-only with context).
#       • PostCompact: likely mirrors PreCompact (decision:"block" only)
#         — silent-drop candidate but unverified.
#       • SubagentStart: likely mirrors SubagentStop (decision:"block"
#         only) — silent-drop candidate but unverified.
#       • StopFailure: likely mirrors Stop (decision:"block" only) —
#         silent-drop candidate but unverified.
#       • ConfigChange: ambiguous — official docs do not enumerate
#         event-specific output fields. Verification deferred.
#       • TeammateIdle / TaskCreated / TaskCompleted / InstructionsLoaded
#         / CwdChanged / FileChanged / WorktreeCreate / WorktreeRemove
#         / PermissionRequest / PermissionDenied / Elicitation* —
#         observability-or-lifecycle events; additionalContext support
#         unverified.
#     Marketplace currently has 0 hooks of any of these newer event
#     types. A future iter-72+ extending the pentad → heptad+ would
#     verify schemas (likely against official Anthropic docs + the
#     CorridorSecurity/hookshot Go type defs) before adding event
#     types to the jq filter and case-statement diagnostic branches.
#
# Schema-Evolution Watch (iter-72 forensic confirmation + future-proofing):
#
#   GitHub #60993 — "Revive #24244 — Stop hook needs additionalContext
#   (or continueWith) for clean workflow continuation" (filed 2026-05-20,
#   OPEN, label: enhancement + area:hooks) — provides upstream community
#   confirmation that the iter-66/67/68/69 audit's premise is correct.
#   The issue body contains the exact validator-side rejection message
#   the reporter received when attempting to emit additionalContext from
#   a Stop hook:
#
#       "hookEventName: Stop is not a permitted value for hookSpecificOutput"
#
#   This validator error message is a hard upstream signal — stronger
#   than third-party blog research — that the Claude Code schema CURRENTLY
#   rejects Stop hook additionalContext at the input-validation layer.
#   This audit's premise (Stop hooks silently drop additionalContext) is
#   forensically validated by an independent community-filed bug report.
#
#   Schema-evolution contingency: if Anthropic accepts #60993 (or the
#   related #24244, #50682, #46191, #34600 duplicates predating it) and
#   ships a schema change adding additionalContext support to Stop hooks
#   OR introducing a continueWith field that delivers context without
#   the decision:"block" red-error-banner side effects — this audit
#   would generate false-positives on legitimate Stop hooks. Mitigation:
#     1. Track #60993 close-status (re-check before each marketplace
#        release with significant Stop-hook changes).
#     2. If schema changes ship: extend the audit's case statement with
#        a new branch differentiating "additionalContext now supported
#        in newer Claude Code versions" from "still silent-dropped".
#     3. Operators on the affected Claude Code version range can use
#        the STOP-HOOK-ADDITIONAL-CONTEXT-OK marker to opt out per-hook
#        without waiting for the audit to be updated.
#
#   Related upstream issues (forensic citation chain):
#     - #19115 — original Stop schema documentation
#     - #19432, #20062 — earlier PreToolUse additionalContext drops (closed)
#     - #55889 — v2.1.123 PreToolUse/PostToolUse Bash-matcher silent-drop
#       regression (OPEN, documented in docs/HOOKS.md)
#     - #24244 — original Stop hook continueWith feature request (closed)
#     - #50682, #46191, #34600 — duplicate predecessor feature requests
#     - #60993 — currently-open revival of #24244 (filed 2026-05-20)
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
echo "  additionalContext-Silently-Dropped Pentad Audit"
echo "  (Stop / SubagentStop / SessionEnd / PreCompact / Notification)"
echo "  (iter-67 audit + iter-68 trinity expansion + iter-69 pentad completion)"
echo "═══════════════════════════════════════════════════════════════════════════"
echo "→ Scans registered Stop, SubagentStop, SessionEnd, PreCompact, AND"
echo "  Notification hook source files for additionalContext emission."
echo "→ Per official Anthropic schema (GitHub #19115 + code.claude.com/docs/en/"
echo "  hooks), three distinct schema sub-rules but a unified silent-drop"
echo "  symptom:"
echo "  • Stop, SubagentStop, PreCompact: read only {decision:'block', reason}"
echo "  • SessionEnd: reads NOTHING (empty output — session terminating)"
echo "  • Notification: no decision, purely informational (exit 2 stderr only)"
echo "  Any additionalContext field on any of these five event types is"
echo "  silently dropped — operator gets no transcript visibility, Claude gets"
echo "  no context. The hook author sees JSON being emitted normally."
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
      source_path=$(find "$REPO_ROOT/plugins" -mindepth 3 -maxdepth 3 -name "$hook_basename" -path '*/hooks/*' -type f 2>/dev/null | grep -v '/tests/' | head -1)  # iter-125: bounded depth fallback
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
      Stop|SubagentStop|PreCompact)
        VIOLATION_LINES+="               Per official Anthropic ${event_type}-hook schema (verbatim in"$'\n'
        VIOLATION_LINES+="               GitHub #19115; ${event_type} uses the same decision-control format"$'\n'
        VIOLATION_LINES+="               as Stop per code.claude.com/docs/en/hooks), ${event_type} hooks read"$'\n'
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
    VIOLATION_LINES+="      Fix:     route the summary text to PROCESS.STDERR instead of stdout JSON."$'\n'
    VIOLATION_LINES+="               Stderr is transcript-visible via Ctrl-R; operators can still see"$'\n'
    VIOLATION_LINES+="               summaries during debugging. For Stop/SubagentStop/PreCompact only,"$'\n'
    VIOLATION_LINES+="               to inject context that Claude actually reads on next turn, use"$'\n'
    VIOLATION_LINES+="               decision:\"block\" + reason (which keeps Claude running and surfaces"$'\n'
    VIOLATION_LINES+="               reason as a system reminder). SessionEnd cannot inject context at all"$'\n'
    VIOLATION_LINES+="               — for end-of-session context use SessionStart on the NEXT session."$'\n'
    VIOLATION_LINES+="               Notification can only surface via stderr on exit 2 — for context"$'\n'
    VIOLATION_LINES+="               injection use a different event type (UserPromptSubmit, SessionStart)."$'\n'
    VIOLATION_LINES+="               OR add to source: // STOP-HOOK-ADDITIONAL-CONTEXT-OK: <reason ≥ ${MIN_OK_REASON_LENGTH} chars>"$'\n'
    VIOLATION_LINES+="      Refs:    iter-66 (single-hook orchestrator fix), iter-67 (Stop-only audit),"$'\n'
    VIOLATION_LINES+="               iter-68 (audit scope expansion to SubagentStop + SessionEnd),"$'\n'
    VIOLATION_LINES+="               iter-69 (pentad completion: + PreCompact + Notification),"$'\n'
    VIOLATION_LINES+="               GitHub #19115 (Anthropic schema verbatim example),"$'\n'
    VIOLATION_LINES+="               https://code.claude.com/docs/en/hooks (official docs)."$'\n'

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
echo "  ✓ No Stop, SubagentStop, SessionEnd, PreCompact, or Notification hooks"
echo "    emit additionalContext to stdout JSON. All five event types in the"
echo "    silently-dropped pentad honor their respective official Anthropic"
echo "    schemas (Stop+SubagentStop+PreCompact: {decision:'block', reason} only;"
echo "    SessionEnd: empty output; Notification: no fields, exit-2 stderr only)."
echo "═══════════════════════════════════════════════════════════════════════════"
