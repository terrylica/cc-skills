#!/usr/bin/env bash
# posttooluse-crown-jewel-plain-keychain-nudge.sh
#
# Detects storing a CROWN-JEWEL secret (master/private/age/dotenv signing key)
# into the macOS Keychain with `-T /usr/bin/security`, which makes the item
# SILENTLY readable by any process — including this AI agent (empirically proven:
# `security find-generic-password -w` returns with no prompt). Crown jewels
# should instead use the Touch-ID-gated tier (`vault set --gated`), which the
# headless agent cannot read without a live biometric.
#
# Self-Custody Secrets (SCS) doctrine, tiered model:
#   • automation/narrow tokens  -> plain Keychain (`-T /usr/bin/security`) OK
#   • crown jewels (master/private keys, client-confidential) -> `vault set --gated`
#
# Trigger: PostToolUse on Bash
# Output:  {"decision":"block","reason":"..."} — does NOT undo the command, just
#          surfaces the reminder (cc-skills convention; see docs/HOOKS.md).
# Escape hatch: include the marker `CROWN-JEWEL-PLAIN-OK` in the command.
# Plugin:  devops-tools (cc-skills marketplace)

set -euo pipefail
shopt -u patsub_replacement 2>/dev/null || true

PAYLOAD=$(cat)

# Fast bail (bash builtin case, no fork) — 95%+ of Bash calls never store a
# generic-password, so short-circuit unless the substring is present.
case "$PAYLOAD" in
    *add-generic-password*) ;;
    *) exit 0 ;;
esac

COMMAND=$(echo "$PAYLOAD" | jq -r '.tool_input.command // empty' 2>/dev/null) || exit 0
[[ -z "$COMMAND" ]] && exit 0

# Operator opt-out for a deliberately-plain crown-jewel item.
case "$COMMAND" in
    *CROWN-JEWEL-PLAIN-OK*) exit 0 ;;
esac

# Must be an actual agent-readable add: add-generic-password trusting the
# `security` binary (`-T /usr/bin/security`). Other adds (no -T) already prompt.
case "$COMMAND" in
    *add-generic-password*-T*/usr/bin/security*) ;;
    *) exit 0 ;;
esac

# Only nudge when the item LOOKS like a crown jewel (case-insensitive).
shopt -s nocasematch
crown=0
for kw in "master" "private" "age-key" "age_key" "secret-key" "secret_key" \
          "dotenv_private" "dotenv-private" "signing" "decrypt"; do
    if [[ "$COMMAND" == *"$kw"* ]]; then crown=1; break; fi
done
shopt -u nocasematch
[[ "$crown" -eq 0 ]] && exit 0

read -r -d '' REASON <<'REMINDER_EOF' || true
[SCS CROWN-JEWEL] You stored what looks like a crown-jewel secret into the
Keychain with `-T /usr/bin/security` — that item is SILENTLY readable by any
process running as you, INCLUDING this agent (`security find-generic-password
-w` returns it with no prompt). Under the tiered Self-Custody Secrets model,
crown jewels (master/private/age/signing keys, client-confidential secrets)
belong in the Touch-ID-gated tier instead:

    vault set --gated <name>          # stored only in the Touch-ID Keychain
    vault run <scope> --gated <name>=<ENV> -- <cmd>   # one biometric to use it

Only narrow, low-blast-radius automation tokens (e.g. a scoped release PAT)
should use the plain `-T /usr/bin/security` form. If this item is genuinely
such a token, add the marker `CROWN-JEWEL-PLAIN-OK` to the command to silence
this. SSoT: ~/.claude/tools/vault/CLAUDE.md and cc-skills docs/self-custody-secrets.md.
REMINDER_EOF

printf '{"decision":"block","reason":%s}\n' "$(echo "$REASON" | jq -Rs .)"
exit 0
