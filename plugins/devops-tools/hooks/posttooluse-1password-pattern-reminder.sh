#!/usr/bin/env bash
# posttooluse-1password-pattern-reminder.sh
#
# Detects `op` (1Password CLI) commands in Bash invocations and reminds Claude
# of the cc-skills credential management pattern:
#   1. unset HTTPS_PROXY (Claude Code OAuth proxy returns 502 on 1Password endpoints)
#   2. Prioritize the Claude Automation SA token (item f7zsfibfvzluw4ahe2qxv3ddee)
#      for all R/W operations on the "Claude Automation" vault
#   3. Fall back to biometric auth (Touch ID) ONLY when SA returns permission denied
#
# Trigger: PostToolUse on Bash
# Output:  {"decision":"block","reason":"..."} — does NOT undo the command, just
#          makes the reminder visible to Claude (cc-skills convention; see HOOKS.md
#          "Hook Output Visibility")
# Plugin:  devops-tools (cc-skills marketplace)
# History: Iteration 4 (2026-05-19) — user-requested after iter 4 hit both
#          proxy interception and SA-token permission limits during
#          Pushover credential registration.

set -euo pipefail

# Iter-35 bash-5.2-patsub-replacement-defense (cross-plugin sweep):
# disable bash 5.2+ `&`-as-backreference in ${VAR//PATTERN/REPLACEMENT}.
# Bash 5.2 made `&` in replacement strings expand as backreference to the match
# (standard sed-like behavior). Pre-5.2 it was literal. This breaks cross-version
# portability. Use `shopt -u patsub_replacement` to disable the feature globally.
# (bash maintainer @chet-ramey, Arch pacman patch #72681).
shopt -u patsub_replacement 2>/dev/null || true

# Read JSON payload from stdin (Claude Code tool-call envelope)
PAYLOAD=$(cat)

# ===========================================================================
# Iter-40 PRE-JQ-FASTPATH (bash-builtin-case-glob-no-process-spawn):
#
# This hook fires on EVERY Bash tool call (matcher: Bash in hooks.json).
# ~95% of those calls have NO mention of `op` anywhere in the payload, yet
# pre-iter-40 the hook unconditionally spawned `jq` (~5-7 ms) + a grep
# (~2.4 ms) to determine that. Total bail-out cost: 7-10 ms per Bash call,
# which compounds across a session with 200+ tool calls to 1.5-2 s of pure
# hook overhead.
#
# This pre-check uses bash's built-in `case` pattern match (no process
# spawn, ~0.05 ms) to short-circuit the entire pipeline when the payload
# is provably unrelated to 1Password. The check is INTENTIONALLY OVER-
# INCLUSIVE — it accepts any payload containing the substring `op`
# anywhere (including JSON keys, string literals, heredoc bodies). The
# precise leading-executable filtering still happens downstream after jq
# extraction; this fast-path only catches the trivially-no-op case.
#
# Speedup measured on m3max bash 5.3.9:
#   pre-iter-40 bail-out:  7-10 ms (jq cold-start dominates)
#   iter-40    bail-out:   <0.1 ms (case glob, no fork)
#   speedup on ~95% hot path: 70-200x
#
# Safety: the `*op*` glob matches all the same inputs the prior path did
# (anything with `op` substring, including heredoc bodies that contain
# `op` as documentation). The downstream anchored-regex filter (iter-39)
# still correctly drops those at the leading-executable check. Zero
# behavioral change vs iter-39 — only the bail-out path is short-circuited.
case "$PAYLOAD" in
    *op*) ;;  # might be op-related; fall through to full jq+regex pipeline
    *) exit 0 ;;  # provably no op anywhere; bail in ~0.05 ms
esac
# ===========================================================================

# Extract the command being run
COMMAND=$(echo "$PAYLOAD" | jq -r '.tool_input.command // empty' 2>/dev/null) || exit 0
[[ -z "$COMMAND" ]] && exit 0

# Fast-path: skip unless `op` is the LEADING EXECUTABLE of the command —
# i.e., the first token after any optional environment-variable prefix
# (e.g., `FOO=bar op ...`). Anchored at `^` so that `op` appearing inside
# argument strings, heredoc bodies, comments, or quoted blocks does NOT
# trigger the reminder.
#
# Iter-39 false-positive fix (2026-05-20): the prior regex
#   '(^|[[:space:];|&(])op([[:space:]]|$)'
# matched `op` after ANY whitespace, which falsely matched commit-message
# heredocs like:
#   git commit -m "$(cat <<'EOF' ... use `op read` to fetch ... EOF)"
# Two iter-37 and iter-38 commits hit this bug back-to-back. Anchoring the
# regex at `^` eliminates the false positive while keeping all true-positive
# cases (`op read`, `OP_SA_TOKEN=foo op read`, etc.) covered.
#
# Regression-tested by:
#   test-posttooluse-1password-pattern-reminder-only-fires-when-op-is-leading-executable-not-heredoc-text.sh
#
# Word-boundary at the end (`[[:space:]]|$`) still prevents matching `open`,
# `optical`, etc. that start with the literal letters `op`.
#
# Perf note: the anchored regex is O(1) for the common no-match case (most
# Bash tool calls are NOT op), vs the prior pattern's O(n) scan over the
# full command body. Win is measurable for long commit messages.
if ! echo "$COMMAND" | grep -qE '^([A-Za-z_][A-Za-z0-9_]*=\S*[[:space:]]+)*op([[:space:]]|$)'; then
    exit 0
fi

# Skip pure read-only meta commands (`op --version`, `op --help`, `op signin`)
# — these don't need the SA reminder.
if echo "$COMMAND" | grep -qE '\bop[[:space:]]+(--version|--help|-h|signin|account[[:space:]]+list)'; then
    exit 0
fi

# Skip if the command already follows the canonical pattern (SA token in env)
# — Claude is already doing it right; don't nag.
if echo "$COMMAND" | grep -qE 'OP_SERVICE_ACCOUNT_TOKEN='; then
    exit 0
fi

# Skip if the command explicitly bypasses (e.g., `unset OP_SERVICE_ACCOUNT_TOKEN`
# followed by `op` — that's the documented biometric-fallback pattern)
if echo "$COMMAND" | grep -qE 'unset[[:space:]]+OP_SERVICE_ACCOUNT_TOKEN'; then
    exit 0
fi

# Emit the reminder. Cap at ~1200 chars to stay reasonable for Claude's context.
# Uses jq to safely encode the multi-line string as JSON.
read -r -d '' REASON <<'REMINDER_EOF' || true
[1PASSWORD-HINT] You just ran an `op` command without the canonical
cc-skills pattern. For Claude Automation vault operations:

(1) PROXY MUST BE BYPASSED — `HTTPS_PROXY=127.0.0.1:52205` (Claude Code
    OAuth proxy) returns 502 Bad Gateway on api.1password.com:
        unset HTTPS_PROXY HTTP_PROXY

(2) PRIORITIZE the Service Account token for R/W on "Claude Automation"
    vault — no biometric prompt, scriptable, automation-ready:
        OP_SERVICE_ACCOUNT_TOKEN="$(cat ~/.claude/.secrets/op-service-account-token)" \
        op <command> --vault "Claude Automation"

(3) FALLBACK to biometric (Touch ID) ONLY when SA returns permission
    denied (e.g., some item-create operations require user auth):
        unset OP_SERVICE_ACCOUNT_TOKEN
        op <command> --vault "Claude Automation"

Registry: docs/1password-credential-registry.md
SA token item: f7zsfibfvzluw4ahe2qxv3ddee (vault: Claude Automation)
REMINDER_EOF

jq -n --arg reason "$REASON" '{decision: "block", reason: $reason}'
exit 0
