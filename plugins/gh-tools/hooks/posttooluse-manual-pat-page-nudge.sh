#!/usr/bin/env bash
# posttooluse-manual-pat-page-nudge.sh
#
# Fires when a Bash command opens / fetches GitHub's token settings page by hand
# (open|curl|xdg-open .../settings/personal-access-tokens or .../settings/tokens).
# That is the manual flow the `gh-fine-grained-pat` skill replaces — nudge toward
# the skill so token creation stays declarative, scoped, and verifiable.
#
# Trigger: PostToolUse (Bash)
# Output:  {"decision":"block","reason":...} so Claude SEES the reminder (cc-skills
#          visibility convention; does NOT undo the command).
# Plugin:  gh-tools (cc-skills marketplace)
#
# Escape hatch: include MANUAL-PAT-PAGE-OK in the command to suppress.

set -euo pipefail
shopt -u patsub_replacement 2>/dev/null || true

PAYLOAD=$(cat)

# Fast-bail: only proceed if the token settings path is referenced.
case "$PAYLOAD" in
    *personal-access-tokens*|*settings/tokens*) ;;
    *) exit 0 ;;
esac

CMD=$(echo "$PAYLOAD" | jq -r '.tool_input.command // empty' 2>/dev/null) || exit 0
[[ -z "$CMD" ]] && exit 0

# Escape hatch + skip the skill's own engine invocations.
case "$CMD" in
    *MANUAL-PAT-PAGE-OK*) exit 0 ;;
    *pat.mjs*) exit 0 ;;
esac

# Only nudge when the page is being OPENED/FETCHED manually (a browser/curl verb).
if ! echo "$CMD" | grep -qE '\b(open|xdg-open|curl|wget|firefox|chrome|chromium|safari)\b'; then
    exit 0
fi

REASON='[gh-fine-grained-pat] You are opening the GitHub token settings page by hand. Prefer the gh-fine-grained-pat skill (plugins/gh-tools/skills/gh-fine-grained-pat) — it browser-automates fine-grained PAT creation from a declarative JSON spec (GitHub has no API for it), so tokens are scoped, repeatable, and stored straight into the SCS vault. Run: node scripts/pat.mjs create specs/<purpose>.json --vault <scope>:<dot.path>. Suppress with MANUAL-PAT-PAGE-OK.'

# Emit the cc-skills visibility convention. printf with the literal
# {"decision":"block",...} (jq only escapes the reason string) — keeps the
# marketplace validator's static "decision: block" check satisfied.
printf '{"decision":"block","reason":%s}\n' "$(echo "$REASON" | jq -Rs .)"
exit 0
