#!/usr/bin/env bash
#MISE description="Audit every plugins/*/hooks/hooks.json that registers PreToolUse or PostToolUse hooks for the WILDCARD-MATCHER anti-pattern: matcher = '*' or null/missing. Per iter-63 + iter-64 forensic findings, wildcard matchers cause Claude Code to cold-start bun on EVERY tool call (~12-17ms each), even when the hook only does meaningful work for a subset of tools. PreToolUse wildcard hooks add user-visible latency (block the tool); PostToolUse wildcard hooks waste CPU+battery (async or sync). Exits non-zero on any wildcard-matcher hook lacking the WILDCARD-MATCHER-OK escape-hatch comment in source. Symmetric scaling of iter-63 (PreToolUse stdin-inlet-guard fix) and iter-64 (PostToolUse orphan-cleanup fix) into preventive infrastructure."
#
# audit-pretooluse-and-posttooluse-hooks-for-wildcard-matcher-star-or-null-which-cold-starts-bun-on-every-tool-call-causing-12-17ms-cpu-or-latency-waste-per-non-meaningful-invocation
#
# Iter-65 self-explanatory-scaffolding audit — preventive companion to
# iter-63 (PreToolUse stdin-inlet-guard matcher narrowing) and iter-64
# (PostToolUse orphan-cleanup matcher narrowing).
#
# Background (mechanism):
#
#   PreToolUse and PostToolUse hooks are filtered by Claude Code BEFORE
#   the hook process is spawned. The `matcher` field selects which tool
#   names invoke the hook. A wildcard matcher ("*" or unset) means the
#   hook fires on EVERY tool call: Read, Glob, Grep, Edit, Write, Bash,
#   Task, mcp__*, WebSearch, WebFetch, etc.
#
#   Each invocation costs ~12-17ms of bun cold-start (measured by the
#   iter-63 warm-cache benchmark). In a typical session with ~100 tool
#   calls and ~80% non-meaningful invocations (the hook just calls
#   `allow()` and exits), that's ~960-1360ms of pure waste per session.
#
#   - PreToolUse wildcard: USER-VISIBLE LATENCY (blocks each tool call
#     until hook returns).
#   - PostToolUse wildcard: CPU+battery cost (may be async:true via
#     iter-57, but still spawns bun + runs the no-op handler).
#
#   iter-63 narrowed pretooluse-subprocess-stdin-inlet-guard from "*"
#   to "Bash". iter-64 did the same for posttooluse-subprocess-
#   orphan-cleanup. Both were the same anti-pattern.
#
# What this audit checks (PRE-SPAWN filter scope):
#
#   For every plugins/*/hooks/hooks.json:
#     - Walk .hooks.PreToolUse[] and .hooks.PostToolUse[]
#     - For each registered hook-group, examine the `matcher` value:
#         - "*"     → WILDCARD-MATCHER violation
#         - null    → MISSING-MATCHER violation (Claude Code interprets
#                     missing matcher as wildcard for these events)
#         - ""      → EMPTY-MATCHER violation (same as wildcard)
#         - "Bash" / "Write|Edit" / etc. → SCOPED-MATCHER ok
#
# Escape hatch (legitimate broad scope):
#
#   Some hooks legitimately need wildcard scope (e.g., a session-once
#   reminder that should surface on ANY tool interaction with the
#   target repo). To opt out, add a comment to the hook SOURCE:
#
#     // WILDCARD-MATCHER-OK: <reason>  (for TypeScript/MJS/JS)
#     # WILDCARD-MATCHER-OK: <reason>   (for bash/python)
#
#   The audit greps the source file for this marker and skips the
#   violation if found. The <reason> is required to be ≥ 10 chars
#   to prevent low-effort opt-outs.
#
# What this audit does NOT check (out of scope):
#
#   - Multi-tool matchers like "Read|Glob|Grep|Bash|Edit|Write" that
#     are broader than necessary. Detecting whether the source actually
#     handles each named tool is harder (requires AST/regex parsing of
#     hook source). Iter-63/64 manual sweep covered known cases; a
#     full audit would have high false-positive rate. Deferred.
#
#   - Stop, UserPromptSubmit, SessionStart, SessionEnd hooks. These
#     events have no tool_name to match against — their matcher is
#     legitimately null/missing.
#
# Verbose name encodes WHAT it audits (PreToolUse/PostToolUse hooks),
# WHICH anti-pattern (wildcard matcher), the perf cost (~12-17ms per
# call), and the impact dimension (CPU or latency). Future maintainers
# searching for "wildcard matcher audit", "matcher star check",
# "iter-63", "iter-64", or "bun cold-start waste" surface this audit.
#
# Re-run cadence:
#   - Manual: `mise run audit-pretooluse-and-posttooluse-hooks-...`
#   - Automatic: release:preflight Check 4i (iter-65 wire-up).

set -euo pipefail
shopt -u patsub_replacement 2>/dev/null || true

# REPO_ROOT defaults to the cc-skills working tree (resolved from this
# task's location). Override via AUDIT_REPO_ROOT_OVERRIDE for testing
# the audit against a synthetic-fixture fleet.
REPO_ROOT="${AUDIT_REPO_ROOT_OVERRIDE:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"

# Minimum length of WILDCARD-MATCHER-OK justification to count as valid.
# Prevents low-effort opt-outs like "// WILDCARD-MATCHER-OK: ok".
MIN_OK_REASON_LENGTH=10

echo "═══════════════════════════════════════════════════════════════════════════"
echo "  Wildcard-Matcher Audit (PreToolUse + PostToolUse hooks)"
echo "═══════════════════════════════════════════════════════════════════════════"
echo "→ Scans plugins/*/hooks/hooks.json for matcher = '*', null, or missing"
echo "→ Why this matters: Claude Code cold-starts bun on EVERY tool call"
echo "  when the matcher is wildcard. ~12-17ms per call wasted on non-"
echo "  meaningful invocations (PreToolUse = user-visible latency;"
echo "  PostToolUse = CPU+battery cost even when async:true)."
echo "→ Escape hatch: add 'WILDCARD-MATCHER-OK: <reason>' comment to source"
echo "  with reason ≥ ${MIN_OK_REASON_LENGTH} chars."
echo ""

# Classification counters
scoped_matcher_count=0
wildcard_with_ok_marker_count=0
wildcard_violation_count=0
total_pre_or_post_tool_use_entries=0

# Accumulator for violation report
VIOLATION_LINES=""

# Helper: extract the source path from a hook command string.
# The hook command looks like one of:
#   "bun ${CLAUDE_PLUGIN_ROOT}/hooks/foo.ts"
#   "${CLAUDE_PLUGIN_ROOT}/hooks/foo.sh"
#   "bash $HOME/.claude/plugins/marketplaces/cc-skills/plugins/foo/hooks/bar.ts"
# We extract the basename of the script for `find`-based source lookup.
extract_hook_source_basename() {
  local cmd="$1"
  # Strip everything up to and including the last "/"
  local basename_with_args="${cmd##*/}"
  # Strip arguments after the script (anything after whitespace)
  echo "${basename_with_args%% *}"
}

# Helper: check if the hook source contains a valid WILDCARD-MATCHER-OK
# marker with reason ≥ MIN_OK_REASON_LENGTH characters.
hook_source_has_valid_wildcard_ok_marker() {
  local plugin_dir="$1" hook_basename="$2"
  local source_path="$plugin_dir/hooks/$hook_basename"

  if [ ! -f "$source_path" ]; then
    return 1
  fi

  # Match both // and # comment styles. Extract the reason after the colon.
  # Pattern: WILDCARD-MATCHER-OK: <reason>
  #
  # Use `.*` (greedy match to end of line) rather than `[^\r\n]+` because
  # BSD grep on macOS interprets `\r` and `\n` inside character classes as
  # literal backslash + r/n rather than escape sequences — that caused the
  # iter-65 regression-test fixture #3 to be misclassified during initial
  # development (the regex stopped at the first 'n' character in the reason
  # text, truncating "session-once" to "sessio" before the length check).
  local marker_line
  marker_line=$(grep -oE 'WILDCARD-MATCHER-OK:.*' "$source_path" 2>/dev/null | head -1 || true)

  if [ -z "$marker_line" ]; then
    return 1
  fi

  # Strip the prefix to get just the reason.
  local reason
  reason=$(echo "$marker_line" | sed -E 's/^WILDCARD-MATCHER-OK:[[:space:]]*//')
  # Strip trailing whitespace
  reason=$(echo "$reason" | sed -E 's/[[:space:]]+$//')

  if [ -z "$reason" ]; then
    return 1
  fi

  if [ "${#reason}" -lt "$MIN_OK_REASON_LENGTH" ]; then
    return 1
  fi

  return 0
}

# Walk every hooks.json that registers PreToolUse or PostToolUse hooks.
while IFS= read -r hooks_json; do
  [ -f "$hooks_json" ] || continue

  plugin_dir=$(dirname "$(dirname "$hooks_json")")
  plugin_name=$(basename "$plugin_dir")

  # Use jq to emit one TSV row per hook entry in PreToolUse + PostToolUse.
  # Fields: event_name<TAB>matcher_value<TAB>first_command
  # We use a tab-separator and a "MATCHER_NULL_SENTINEL" placeholder
  # because IFS=$'\t' read collapses consecutive empty fields.
  while IFS=$'\t' read -r event_name matcher_value first_command; do
    [ -z "$event_name" ] && continue
    total_pre_or_post_tool_use_entries=$((total_pre_or_post_tool_use_entries + 1))

    # Restore sentinel → actual semantic value
    if [ "$matcher_value" = "MATCHER_NULL_SENTINEL" ]; then
      matcher_value=""
      matcher_display="<null/missing>"
    else
      matcher_display="$matcher_value"
    fi

    # Classify
    if [ "$matcher_value" = "*" ] || [ -z "$matcher_value" ]; then
      # Wildcard matcher detected. Check for OK marker in source.
      hook_basename=$(extract_hook_source_basename "$first_command")

      if hook_source_has_valid_wildcard_ok_marker "$plugin_dir" "$hook_basename"; then
        wildcard_with_ok_marker_count=$((wildcard_with_ok_marker_count + 1))
        echo "  ◯ WILDCARD-WITH-OK-MARKER: $plugin_name/$hook_basename"
        echo "     event=$event_name matcher=$matcher_display"
      else
        wildcard_violation_count=$((wildcard_violation_count + 1))
        VIOLATION_LINES+="  ✗ $plugin_name/hooks/hooks.json"$'\n'
        VIOLATION_LINES+="      event:   $event_name"$'\n'
        VIOLATION_LINES+="      matcher: $matcher_display"$'\n'
        VIOLATION_LINES+="      hook:    $hook_basename"$'\n'
        VIOLATION_LINES+="      Issue:   wildcard matcher cold-starts bun on every tool call."$'\n'
        VIOLATION_LINES+="               Cost: ~12-17ms per call (PreToolUse: user-visible latency;"$'\n'
        VIOLATION_LINES+="               PostToolUse: CPU+battery, even when async:true)."$'\n'
        VIOLATION_LINES+="      Fix:     narrow matcher to the specific tool name(s) the hook actually"$'\n'
        VIOLATION_LINES+="               handles. Example: matcher: 'Bash' or 'Write|Edit'."$'\n'
        VIOLATION_LINES+="               OR add to the hook source file:"$'\n'
        VIOLATION_LINES+="                 // WILDCARD-MATCHER-OK: <reason ≥ ${MIN_OK_REASON_LENGTH} chars>"$'\n'
        VIOLATION_LINES+="      Refs:    iter-63 (PreToolUse stdin-inlet-guard fix),"$'\n'
        VIOLATION_LINES+="               iter-64 (PostToolUse orphan-cleanup fix),"$'\n'
        VIOLATION_LINES+="               iter-65 (this audit)."$'\n'
      fi
    else
      scoped_matcher_count=$((scoped_matcher_count + 1))
    fi
  done < <(jq -r '
    (.hooks // {})
    | to_entries[]
    | select(.key == "PreToolUse" or .key == "PostToolUse")
    | .key as $event
    | .value[]?
    | [
        $event,
        (if .matcher == null then "MATCHER_NULL_SENTINEL" else .matcher end),
        (.hooks[0].command // "")
      ]
    | @tsv
  ' "$hooks_json" 2>/dev/null)

done < <(find "$REPO_ROOT/plugins" -mindepth 3 -maxdepth 3 -name 'hooks.json' -type f 2>/dev/null | sort)  # iter-125: bounded depth, ~65ms -> ~7ms

# Emit structured report.
echo ""
echo "═══════════════════════════════════════════════════════════════════════════"
echo "  Wildcard-Matcher Audit Summary"
echo "═══════════════════════════════════════════════════════════════════════════"
echo "  Total PreToolUse/PostToolUse hook entries scanned: $total_pre_or_post_tool_use_entries"
echo "  SCOPED-MATCHER (correctly narrowed):               $scoped_matcher_count"
echo "  WILDCARD-WITH-OK-MARKER (legitimate broad scope):  $wildcard_with_ok_marker_count"
echo "  WILDCARD-VIOLATION (unjustified broad scope):      $wildcard_violation_count"
echo ""

if [ "$wildcard_violation_count" -gt 0 ]; then
  echo "─── WILDCARD-VIOLATION ($wildcard_violation_count) — wastes ~12-17ms bun cold-start per non-meaningful tool call ───"
  printf "%s" "$VIOLATION_LINES"
  echo ""
  echo "═══════════════════════════════════════════════════════════════════════════"
  echo "  EXITING NON-ZERO — release:preflight should gate on this."
  echo "═══════════════════════════════════════════════════════════════════════════"
  exit 1
fi

echo "═══════════════════════════════════════════════════════════════════════════"
echo "  ✓ No unjustified wildcard matchers found. Bun cold-start cost is"
echo "    incurred ONLY for tool calls where the hook does meaningful work."
echo "═══════════════════════════════════════════════════════════════════════════"
