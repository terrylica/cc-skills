#!/usr/bin/env bash
# Both-directions proof for gmail-draft-guard. Run with GMAIL_DRAFT_ADHOC_OK=1 so the probe strings
# in this script do not trip the guard that is invoking it.
G="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/gmail-draft-guard.sh"
export GMAIL_DRAFT_TEST_GATE_SKIP=1
fail=0

probe() {
  local want="$1" desc="$2" cmd="$3" rc got
  printf '%s' "$(python3 -c 'import json,sys; print(json.dumps({"tool_input":{"command":sys.argv[1]}}))' "$cmd")" | bash "$G" >/dev/null 2>&1
  rc=$?
  got="ALLOW"; [ "$rc" -ne 0 ] && got="BLOCK"
  if [ "$got" = "$want" ]; then printf '  ok   %-5s %s\n' "$got" "$desc"
  else printf '  FAIL expected %s got %s — %s\n' "$want" "$got" "$desc"; fail=1; fi
}

CANON_ABS="$HOME/.claude/plugins/marketplaces/cc-skills/plugins/gmail-commander/scripts/gmail-draft.ts"
STALE='~/eon/cc-skills/plugins/gmail-commander/scripts/gmail-draft.ts'
DRAFTS='https://gmail.googleapis.com/gmail/v1/users/me/drafts'

echo "MUST ALLOW — the canonical builder, however it is spelled"
probe ALLOW 'canonical via ~'      "bun ~/.claude/plugins/marketplaces/cc-skills/plugins/gmail-commander/scripts/gmail-draft.ts --account a"
probe ALLOW 'canonical via $HOME'  'bun $HOME/.claude/plugins/marketplaces/cc-skills/plugins/gmail-commander/scripts/gmail-draft.ts --account a'
probe ALLOW 'canonical absolute'   "bun $CANON_ABS --account a"

echo "MUST ALLOW — reads and unrelated work"
probe ALLOW 'read-only GET'            "curl -s $DRAFTS/r1?format=full"
probe ALLOW 'GET whose prose says PUT' "echo 'after the failed PUT?' && curl -s $DRAFTS/r1?format=metadata"
probe ALLOW 'unrelated command'        'git status && echo POST'

echo "MUST BLOCK — the wrong copy of the right tool"
probe BLOCK 'stale source checkout' "bun $STALE --account a --body b.md"

echo "MUST BLOCK — ad-hoc writes, in every spelling that used to slip through"
probe BLOCK 'uppercase -X POST'      "curl -X POST $DRAFTS"
probe BLOCK 'lowercase -X put'       "curl -X put $DRAFTS/r1"
probe BLOCK '-XPATCH, no space'      "curl -XPATCH $DRAFTS/r1"
probe BLOCK '--request delete'       "curl --request delete $DRAFTS/r1"
probe BLOCK 'implicit POST via -d'   "curl -d '{}' $DRAFTS"
probe BLOCK 'implicit via --data-binary' "curl --data-binary @m.json $DRAFTS"
probe BLOCK 'python inline method'   "python3 -c 'requests.request(method=\"POST\", url=\"$DRAFTS\")'"

echo "MUST ALLOW — working ON the builder is not staging a draft"
# Blocking these made plugin development itself require the escape hatch on every command, which is
# how a hatch stops meaning anything. The builder's own required flags are the discriminator.
probe ALLOW 'bun test the builder suite' "bun test $HOME/eon/cc-skills/plugins/gmail-commander/scripts/gmail-draft.test.ts"
probe ALLOW 'bun build the builder'      "bun build $HOME/eon/cc-skills/plugins/gmail-commander/scripts/gmail-draft.ts --target=bun"
probe ALLOW 'grep the builder'           "grep -n linkify $HOME/eon/cc-skills/plugins/gmail-commander/scripts/gmail-draft.ts"
probe ALLOW 'read the builder'           "cat $HOME/eon/cc-skills/plugins/gmail-commander/scripts/gmail-draft.ts"

exit "$fail"
