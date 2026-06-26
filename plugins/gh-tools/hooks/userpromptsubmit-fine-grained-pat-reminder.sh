#!/usr/bin/env bash
# userpromptsubmit-fine-grained-pat-reminder.sh
#
# When the user's prompt shows intent to create / obtain a GitHub token, inject
# a reminder that the `gh-fine-grained-pat` skill exists — so we never hand-roll
# a token by clicking through the UI, nor reach for a broad classic token, when
# a declarative, scoped, browser-automated fine-grained PAT is one command away.
#
# Trigger: UserPromptSubmit
# Output:  additionalContext (stdout) — visible to Claude when planning
# Plugin:  gh-tools (cc-skills marketplace)
#
# Escape hatch: include FGPAT-REMINDER-OK in the prompt to suppress.

set -euo pipefail

# Iter-35 bash-5.2 patsub-replacement defense (disable &-as-backreference).
shopt -u patsub_replacement 2>/dev/null || true

PAYLOAD=$(cat)

# ---------------------------------------------------------------------------
# PRE-JQ FASTPATH (bash-builtin case-glob, no process spawn): this hook fires on
# EVERY UserPromptSubmit. Bail before jq unless a token keyword is present.
# Intentionally over-inclusive; the precise \b-grep below drops false positives.
shopt -s nocasematch
case "$PAYLOAD" in
    *fine-grained*|*personal\ access\ token*|*access\ token*|*github_pat*|*ghp_*|\
    *personal-access-tokens*|*settings/tokens*|*classic\ token*|*scoped\ token*|\
    *\ pat\ *|*\ pats\ *|*github\ token*|*gh\ token*|*release\ token*|*ci\ token*) ;;
    *) shopt -u nocasematch; exit 0 ;;
esac
shopt -u nocasematch

PROMPT=$(echo "$PAYLOAD" | jq -r '.prompt // empty' 2>/dev/null) || exit 0
[[ -z "$PROMPT" ]] && exit 0

# Escape hatch.
case "$PROMPT" in *FGPAT-REMINDER-OK*) exit 0 ;; esac

LOWER=$(echo "$PROMPT" | tr '[:upper:]' '[:lower:]')

# PRECISE filter (\b word boundaries). Matches genuine token-creation intent.
if ! echo "$LOWER" | grep -qE '\b(fine-grained|personal access tokens?|github (personal )?access tokens?|classic tokens?|scoped tokens?|github_pat_|ghp_[a-z0-9]|personal-access-tokens|settings/tokens|(create|generate|mint|issue|rotate|make|need) [a-z0-9 ,-]{0,24}\b(token|pat)\b|\b(token|pat) for (a |the )?(repo|release|ci|github))\b'; then
    exit 0
fi

# Inject the reminder. UserPromptSubmit honors stdout as additional context.
cat <<'CONTEXT_EOF'
[gh-fine-grained-pat] GitHub token intent detected. Prefer the
`gh-fine-grained-pat` skill (plugins/gh-tools/skills/gh-fine-grained-pat) over
hand-clicking the UI or using a broad classic (ghp_*) token.

GitHub has NO API to create fine-grained PATs — the skill browser-automates the
web UI from a declarative JSON spec, so creation is repeatable, narrowly scoped,
and verifiable. Login is one-time (persistent profile).

  node scripts/pat.mjs login                 # once
  node scripts/pat.mjs create specs/<purpose>.json --vault <scope>:<dot.path>
  node scripts/pat.mjs rotate specs/<purpose>.json --vault <scope>:<dot.path>

Templates: release-bot, read-only-auditor, ci-status-reporter, account-scoped,
kitchen-sink (+ specs/examples/). The token value is never printed — it goes to
a 0600 file or straight into the SCS vault. See that skill's SKILL.md / CLAUDE.md.
(Suppress this reminder with FGPAT-REMINDER-OK.)
CONTEXT_EOF

exit 0
