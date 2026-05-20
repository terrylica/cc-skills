#!/usr/bin/env bash
# userpromptsubmit-1password-context-injection.sh
#
# Detects 1Password-related keywords in user prompts and injects upfront context
# about the cc-skills credential pattern, BEFORE Claude takes any action. This
# is the proactive companion to posttooluse-1password-pattern-reminder.sh
# (which corrects after-the-fact).
#
# Trigger: UserPromptSubmit
# Output:  additionalContext field — visible to Claude when planning the response
# Plugin:  devops-tools (cc-skills marketplace)

set -euo pipefail

# Iter-35 bash-5.2-patsub-replacement-defense (cross-plugin sweep):
# disable bash 5.2+ `&`-as-backreference. See
# plugins/autoloop/hooks/heartbeat-tick.sh for full rationale.
shopt -u patsub_replacement 2>/dev/null || true

PAYLOAD=$(cat)

# Extract user prompt
PROMPT=$(echo "$PAYLOAD" | jq -r '.prompt // empty' 2>/dev/null) || exit 0
[[ -z "$PROMPT" ]] && exit 0

# Case-insensitive keyword detection — must match a 1P-related concept
# without being too noisy (e.g., "open" alone is not enough).
LOWER=$(echo "$PROMPT" | tr '[:upper:]' '[:lower:]')

# Keywords that should trigger the reminder
if ! echo "$LOWER" | grep -qE '\b(1password|1p|op item|op read|op vault|op list|op create|op edit|op delete|service account|sa token|claude automation vault|op://)\b'; then
    exit 0
fi

# Inject context. UserPromptSubmit honors stdout as additional context.
cat <<'CONTEXT_EOF'
[1PASSWORD-CONTEXT] User prompt mentions 1Password. Canonical cc-skills pattern:

1) Always unset HTTPS_PROXY HTTP_PROXY before `op` (the Claude Code OAuth proxy
   at 127.0.0.1:52205 returns 502 Bad Gateway on api.1password.com).

2) For R/W on the "Claude Automation" vault, prioritize the Service Account
   token (item f7zsfibfvzluw4ahe2qxv3ddee). It's scriptable, no biometric prompt:
       OP_SERVICE_ACCOUNT_TOKEN="$(cat ~/.claude/.secrets/op-service-account-token)" \
       op <command> --vault "Claude Automation"

3) Fall back to biometric (Touch ID) ONLY when SA returns permission denied
   (some item-create operations require user auth):
       unset OP_SERVICE_ACCOUNT_TOKEN
       op <command> --vault "Claude Automation"

4) Registry of stored items: docs/1password-credential-registry.md

5) Vaults other than "Claude Automation" (Engineering, Finance, etc.) are
   user-session-only — must use biometric path.
CONTEXT_EOF

exit 0
