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

# ===========================================================================
# Iter-41 PRE-JQ-FASTPATH-USERPROMPT-1PASSWORD-KEYWORD-SUBSTRING-SHORTCIRCUIT:
#
# This hook fires on EVERY UserPromptSubmit event. Pre-iter-41 it
# unconditionally spawned jq (~5-7 ms) + tr (~1-2 ms) + grep (~2 ms) to
# determine that ~95% of real-world prompts contain NO 1Password
# keyword. Total bail-out cost: ~10 ms per prompt, compounding across a
# multi-prompt session.
#
# This pre-check uses bash's built-in `case` pattern match (no process
# spawn, ~0.05 ms) with `shopt -s nocasematch` for case-insensitive
# substring detection. ~95% of prompts bail in <100 µs instead of ~10 ms.
#
# Safety: the fast-path is INTENTIONALLY OVER-INCLUSIVE (substring match,
# not word-boundary match). Prompts that hit ANY of the substrings
# `1password`, `1p`, `service account`, `sa token`, `claude automation`,
# `op://`, `op item`, `op read`, `op vault`, `op list`, `op create`,
# `op edit`, or `op delete` (in any case) fall through to the precise
# downstream grep, which still uses the original \b-bounded regex to
# correctly filter false positives like "1page" or "options" or "stop
# item from running".
#
# Pattern follows iter-40's pre-jq-fastpath on posttooluse-1password-
# pattern-reminder.sh — same idiom, different hook.

shopt -s nocasematch
case "$PAYLOAD" in
    *1password*|*1p*|*service\ account*|*sa\ token*|*claude\ automation*|*op://*|*op\ item*|*op\ read*|*op\ vault*|*op\ list*|*op\ create*|*op\ edit*|*op\ delete*) ;;
    *) shopt -u nocasematch; exit 0 ;;
esac
shopt -u nocasematch
# ===========================================================================

# Extract user prompt
PROMPT=$(echo "$PAYLOAD" | jq -r '.prompt // empty' 2>/dev/null) || exit 0
[[ -z "$PROMPT" ]] && exit 0

# Case-insensitive keyword detection — must match a 1P-related concept
# without being too noisy (e.g., "open" alone is not enough).
LOWER=$(echo "$PROMPT" | tr '[:upper:]' '[:lower:]')

# Keywords that should trigger the reminder. This is the PRECISE filter
# (with \b word boundaries) — the fast-path above is intentionally over-
# inclusive and forwards ambiguous matches (like "options" or "1page")
# down here for the precise check.
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
