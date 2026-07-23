#!/usr/bin/env bash
# gmail-draft-guard — global PreToolUse(Bash) hook: block AD-HOC Gmail drafts-API calls.
#
# WHY (regression 2026-07-23): a draft built ad hoc (python + MIMEText text/plain) picked up a
# markdown-formatter-wrapped body AND Gmail's ingestion re-encoding hard-folded the long lines —
# the composed draft showed forced mid-paragraph line breaks. The canonical builder
# (../scripts/gmail-draft.ts, installed at ~/.claude/plugins/marketplaces/cc-skills/plugins/gmail-commander/scripts/) is structurally immune (multipart/alternative with a
# text/html part, paragraphs unwrapped), so every Gmail draft MUST go through it.
#
# Blocks a Bash command when it looks like a drafts-API call NOT made via gmail-draft.ts:
#   - matches: users/me/drafts  OR  (gmail.googleapis.com AND "draft")
#   - allowed: command mentions gmail-draft.ts (the canonical tool), is read-only draft inspection
#              (GET/format= fetches are fine), or carries the escape hatch GMAIL_DRAFT_ADHOC_OK=1.
# Fail-open on parse errors (advisory infrastructure must never wedge the session).
set -euo pipefail

INPUT=$(cat 2>/dev/null || true)
CMD=$(printf '%s' "$INPUT" | python3 -c 'import json,sys
try: print(json.load(sys.stdin).get("tool_input",{}).get("command",""))
except Exception: print("")' 2>/dev/null || true)

[ -z "$CMD" ] && exit 0
case "$CMD" in
  *GMAIL_DRAFT_ADHOC_OK=1*) exit 0 ;;                      # explicit, auditable escape hatch
  *scripts/gmail-draft.ts*) exit 0 ;;                              # the canonical tool itself
esac

if printf '%s' "$CMD" | grep -qE 'users/me/drafts|gmail\.googleapis\.com[^ ]*draft'; then
  # Write detection is deliberately COARSE (quote-escaping variants defeated a precise regex):
  # any POST/PUT/PATCH token in a drafts-API command blocks. Read-only GET fetches pass; a rare
  # false positive is a loud pointer to the canonical tool, not damage — and the escape hatch exists.
  if printf '%s' "$CMD" | grep -qE '(POST|PUT|PATCH)'; then
    cat >&2 <<'MSG'
BLOCKED: ad-hoc Gmail drafts-API write. Use the canonical builder instead:

  bun ~/.claude/plugins/marketplaces/cc-skills/plugins/gmail-commander/scripts/gmail-draft.ts --account <tokenbase> --body <file.md> \
    --from 'Name <addr>' [--reply-to <msgId>] [--to ...] [--cc ...] [--subject ...] [--replace <draftId>]

Why: Gmail re-encodes ingested text/plain and HARD-FOLDS long lines (~72 cols) — ad-hoc drafts show
forced mid-paragraph line breaks in the compose window (regression 2026-07-23). The tool builds
multipart/alternative with a text/html part (wrap-immune) and unwraps formatter-wrapped sources.
Escape hatch (deliberate ad-hoc use): prefix the command with GMAIL_DRAFT_ADHOC_OK=1.
MSG
    exit 2
  fi
fi
exit 0
