#!/usr/bin/env bash
#MISE description="Iter-99 marketplace-wide preventive audit: detects PostToolUse TypeScript hooks emitting raw console.log text (template-literal or plain string) which Anthropic PostToolUse schema silently drops from Claude context (operator transcript only). Scales the iter-98 single-hook silent-context-drop fix to a marketplace invariant. Escape hatch: POSTTOOLUSE-RAW-STDOUT-OK same-line or within 3 preceding lines. Parallel to the iter-94 spawnSync audit."

# Full design rationale:
#
# Per the iter-66/93 forensic finding + Anthropic PostToolUse schema docs,
# plain-text stdout from PostToolUse hooks is rendered into the operator
# transcript (Ctrl-R visible) but is NEVER delivered to Claude's next-turn
# context. The only two Claude-visible PostToolUse stdout schemas are:
#
#   (a) {decision: "block", reason: "..."} JSON — surfaces the reason as a
#       Claude-visible system reminder. Used by the iter-93+ orchestrator
#       + its 7 inlined subhook classifiers + the bash 1password-reminder +
#       the bash code-correctness-guard.
#
#   (b) {hookSpecificOutput: {hookEventName: "PostToolUse",
#       additionalContext: "..."}} JSON — wraps additionalContext as a
#       system-reminder injected next to the tool result. Used by
#       rust-sota-reminder.
#
# This audit catches the silent-drop bug pattern preventively for TypeScript
# PostToolUse hooks. Template-literal `console.log(`...`)` emissions and
# string-literal `console.log("...")` emissions are obvious raw text and
# bypass BOTH valid Claude-visible schemas.
#
# Escape hatch:
#   // POSTTOOLUSE-RAW-STDOUT-OK: <reason ≥ 10 chars>
# on the same line or within the 3 preceding lines.
#
# Parallel to the iter-94 spawnSync audit which scales the iter-93
# single-classifier async-spawn fix to a marketplace invariant.

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

print_banner "Iter-99 Static Audit: no raw-stdout silent-context-drop in PostToolUse TypeScript hooks"
echo ""
echo "  Theory: PostToolUse stdout that is NOT valid Claude-visible JSON"
echo "          (decision:block OR hookSpecificOutput.additionalContext) is"
echo "          silently dropped by Claude Code — operator transcript only."
echo "  Source: iter-66/93 forensic finding + Anthropic PostToolUse schema docs."
echo "  Iter-98 incident: posttooluse-memory-efficiency-reminder.ts emitted"
echo "          console.log(\`[MEMORY-EFFICIENCY] ...\`) raw template-literal text"
echo "          for the entire hook's lifetime — Claude NEVER saw the reminder."
echo "  Iter-99 invariant: catch this pattern preventively in TS hooks."
echo ""

# ══════════════════════════════════════════════════════════════════════════
#  Step 1 — Enumerate every PostToolUse TypeScript / MJS hook in marketplace
# ══════════════════════════════════════════════════════════════════════════
#
# Convention: every PostToolUse hook lives under
# `plugins/<name>/hooks/posttooluse-*.{ts,mjs}` per the marketplace
# naming convention. Glob-discover all of them — this naturally includes:
#   - Standalone PostToolUse hooks wired in plugins/*/hooks/hooks.json
#   - Orchestrator-imported classifiers (their `import.meta.main` standalone
#     CLI paths emit JSON and are audited the same way)
#   - The orchestrator entry-point itself
# Bash PostToolUse hooks are audited via separate review — their emission
# shapes differ (echo + jq vs console.log + JSON.stringify).

mapfile -t POSTTOOLUSE_TYPESCRIPT_HOOK_ABSOLUTE_PATHS_TO_AUDIT < <(
    find "$REPO_ROOT/plugins" \
        -type f \
        \( -name 'posttooluse-*.ts' -o -name 'posttooluse-*.mjs' \) \
        -not -path '*/hooks/lib/*' \
        2>/dev/null \
        | sort -u
)

# Iter-100 scope refinement: `*/hooks/lib/*` files are SHARED IMPLEMENTATION
# DETAILS imported by classifiers, NOT PostToolUse hooks themselves. They
# never emit to stdout (their exported helpers return values to callers).
# Excluding them keeps the audit scope precise — only files that ACTUALLY
# run as PostToolUse-event entry points get scanned. Pre-iter-100 the audit
# scanned 17 files (including 2 lib helpers); post-iter-100 it scans ~15
# real hooks. No semantic change — both audits surface 0 violations on the
# current marketplace state — but the scope is tighter and future false-
# positives on lib helpers cannot occur.

echo "  PostToolUse TypeScript hooks discovered across marketplace: ${#POSTTOOLUSE_TYPESCRIPT_HOOK_ABSOLUTE_PATHS_TO_AUDIT[@]}"
echo ""

if [[ ${#POSTTOOLUSE_TYPESCRIPT_HOOK_ABSOLUTE_PATHS_TO_AUDIT[@]} -eq 0 ]]; then
    echo "  ⊘ no PostToolUse TypeScript hooks discovered — audit cannot run"
    exit 0
fi

# ══════════════════════════════════════════════════════════════════════════
#  Step 2 — Scan each hook for the silent-context-drop emission pattern
# ══════════════════════════════════════════════════════════════════════════
#
# DENY patterns (raw text — bypasses both Claude-visible JSON schemas):
#   console.log(`...`)   — template-literal emission (iter-98 incident shape)
#   console.log("...")   — string-literal emission (alternative raw-text shape)
#   console.log('...')   — single-quoted string-literal emission
#
# ALLOW patterns:
#   console.log(JSON.stringify(...))     — explicit JSON encoding
#   console.log(variableName)             — defer to manual review (too hard
#                                           to statically verify the variable
#                                           always holds JSON; trust author)
#
# Escape hatch (same-line OR within 3 preceding lines):
#   // POSTTOOLUSE-RAW-STDOUT-OK: <reason ≥ 10 chars>
#
# Emission-pattern grep (not prose-comment grep): skip lines whose first
# non-whitespace character is `*` (JSDoc continuation) or `//` (line comment).
# Mirrors the iter-94 spawnSync audit's prose-vs-emission distinction.

declare -a SILENT_CONTEXT_DROP_VIOLATIONS=()

for hook_absolute_path in "${POSTTOOLUSE_TYPESCRIPT_HOOK_ABSOLUTE_PATHS_TO_AUDIT[@]}"; do
    hook_relative_to_repo="${hook_absolute_path#"$REPO_ROOT"/}"

    # Find lines matching the DENY patterns
    while IFS= read -r matched_line_with_lineno; do
        # Strip leading line-number prefix `<N>:`
        line_body_only="${matched_line_with_lineno#*:}"

        # Skip JSDoc continuation lines (^\s*\*)
        case "$line_body_only" in
            *) leading_stripped="${line_body_only#"${line_body_only%%[![:space:]]*}"}" ;;
        esac
        if [[ "$leading_stripped" == \** ]]; then
            continue
        fi
        # Skip pure line-comments (^\s*//)
        if [[ "$leading_stripped" == //* ]]; then
            continue
        fi

        # Check for escape hatch on the same line
        if [[ "$line_body_only" == *"POSTTOOLUSE-RAW-STDOUT-OK:"* ]]; then
            continue
        fi

        # Check for escape hatch within 3 preceding lines
        line_number="${matched_line_with_lineno%%:*}"
        # Compute the 3-line preceding window
        window_start=$((line_number - 3))
        [[ "$window_start" -lt 1 ]] && window_start=1
        window_end=$((line_number - 1))
        if [[ "$window_end" -ge "$window_start" ]]; then
            preceding_window=$(awk -v start="$window_start" -v end="$window_end" 'NR>=start && NR<=end' "$hook_absolute_path")
            if [[ "$preceding_window" == *"POSTTOOLUSE-RAW-STDOUT-OK:"* ]]; then
                continue
            fi
        fi

        SILENT_CONTEXT_DROP_VIOLATIONS+=("$hook_relative_to_repo:$matched_line_with_lineno")
    done < <(grep -nE 'console\.log\((`|"|'"'"')' "$hook_absolute_path" 2>/dev/null || true)
done

# ══════════════════════════════════════════════════════════════════════════
#  Report
# ══════════════════════════════════════════════════════════════════════════

if [[ ${#SILENT_CONTEXT_DROP_VIOLATIONS[@]} -eq 0 ]]; then
    echo "  ✓ AUDIT PASSED — no raw-stdout silent-context-drop emissions in any PostToolUse TypeScript hook"
    echo ""
    echo "  Scanned hooks:"
    for path in "${POSTTOOLUSE_TYPESCRIPT_HOOK_ABSOLUTE_PATHS_TO_AUDIT[@]}"; do
        echo "    - ${path#"$REPO_ROOT"/}"
    done
    echo ""
    echo "  Note: bash PostToolUse hooks are audited via separate review."
    echo "  Both valid Claude-visible PostToolUse stdout schemas are accepted:"
    echo "    1. {decision:\"block\", reason:\"...\"} JSON — used by orchestrator + 8 inlined subhooks + bash 1password-reminder + bash code-correctness-guard"
    echo "    2. {hookSpecificOutput:{hookEventName:\"PostToolUse\", additionalContext:\"...\"}} JSON — used by rust-sota-reminder"
    exit 0
fi

echo "  ✗ AUDIT FAILED — ${#SILENT_CONTEXT_DROP_VIOLATIONS[@]} silent-context-drop emission(s) found:"
echo ""
for violation in "${SILENT_CONTEXT_DROP_VIOLATIONS[@]}"; do
    echo "    $violation"
done
echo ""
echo "  Fix options:"
echo "    A. Wrap the emission in JSON.stringify(...) with one of the two valid schemas:"
echo "       console.log(JSON.stringify({decision: \"block\", reason: \"...\"}))"
echo "       console.log(JSON.stringify({hookSpecificOutput: {hookEventName: \"PostToolUse\", additionalContext: \"...\"}}))"
echo ""
echo "    B. If the raw stdout is genuinely operator-only intent (e.g., a"
echo "       diagnostic that should appear in the Ctrl-R transcript but NOT in"
echo "       Claude's context), route via console.error(...) instead — stderr"
echo "       is the documented operator-only surface."
echo ""
echo "    C. If you have a legitimate reason to emit raw text to stdout AND"
echo "       you've verified Claude's intended behavior, add the escape hatch:"
echo "         // POSTTOOLUSE-RAW-STDOUT-OK: <reason ≥ 10 chars>"
echo "       on the same line or within the 3 preceding lines."
echo ""
echo "  Iter-98 incident reference: plugins/itp-hooks/hooks/posttooluse-memory-efficiency-reminder.ts"
echo "  was emitting console.log(\`[MEMORY-EFFICIENCY] ...\`) — operator-visible but Claude-invisible"
echo "  for the entire lifetime of the hook. Iter-98 fixed it by inlining into the orchestrator"
echo "  (which wraps additional_context decisions in proper {decision:block,reason} JSON)."
echo ""
exit 1
