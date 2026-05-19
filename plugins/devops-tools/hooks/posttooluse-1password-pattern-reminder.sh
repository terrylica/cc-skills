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

# Read JSON payload from stdin (Claude Code tool-call envelope)
PAYLOAD=$(cat)

# Extract the command being run
COMMAND=$(echo "$PAYLOAD" | jq -r '.tool_input.command // empty' 2>/dev/null) || exit 0
[[ -z "$COMMAND" ]] && exit 0

# Fast-path: skip if no `op` token in command. Word-boundary aware to avoid
# matching "open", "stop", "loop", etc.
if ! echo "$COMMAND" | grep -qE '(^|[[:space:];|&(])op([[:space:]]|$)'; then
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
