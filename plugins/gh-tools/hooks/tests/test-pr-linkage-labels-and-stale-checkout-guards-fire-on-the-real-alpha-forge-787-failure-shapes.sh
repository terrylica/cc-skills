#!/usr/bin/env bash
# test-pr-linkage-labels-and-stale-checkout-guards-fire-on-the-real-alpha-forge-787-failure-shapes.sh
#
# Both hooks under test were written from one incident: Eon-Labs/alpha-forge#787, 2026-09-15.
#
#   - The PR silently acquired a promise to close an unrelated issue, because its body contained the
#     ordinary English sentence "rejected two of the three fixes #788 first proposed". GitHub parsed
#     the last two words as the closing keyword. Nothing in the diff, title or review showed it.
#   - The PR carried no labels, in a repository where no PR carries labels, so nothing objected.
#   - A sibling issue asserted repository facts read from a checkout 47 commits stale, and a reviewer
#     refuted it.
#
# So the tests are written against those shapes rather than against invented ones.
#
# The point of every assertion here is that the hooks FIRE. A hook that never fires is
# indistinguishable from a hook that was never installed, and both read as "we have a guard for
# that" — which is worse than having no guard, because it stops anyone looking.
#
# NOTE ON STYLE: every assertion is an explicit if/then/else. The `cmd && ok || fail` idiom is
# forbidden here (shellcheck SC2015) because the failure branch also runs when the SUCCESS branch
# fails — a test harness that can report a pass as a failure is not a harness.

set -euo pipefail

HOOKS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LINKAGE="${HOOKS_DIR}/posttooluse-pr-linkage-and-label-reminder.mjs"
STALE="${HOOKS_DIR}/pretooluse-stale-checkout-claim-guard.mjs"

pass=0
fail=0

# ok <description> — record a passing assertion.
ok() {
  echo "  PASS  $1"
  pass=$((pass + 1))
}

# no <description> [detail] — record a failing assertion, with optional observed output.
no() {
  echo "  FAIL  $1"
  if [[ -n "${2:-}" ]]; then
    echo "        got: $2"
  fi
  fail=$((fail + 1))
}

# feed <hook-path> <command-json-payload> — run a hook with a synthetic payload, return its stdout.
# stderr is discarded and a non-zero exit is tolerated: what is under test is what the hook SAYS.
feed() {
  local hook="$1" payload="$2" out
  out="$(printf '%s' "$payload" | node "$hook" 2>/dev/null)" || true
  printf '%s' "$out"
}

# bash_payload <command> — the PreToolUse/PostToolUse envelope Claude Code actually sends.
bash_payload() {
  printf '{"tool_name":"Bash","tool_input":{"command":"%s"}}' "$1"
}

echo "== structural: both hooks exist and are executable =="
if [[ -x "$LINKAGE" ]]; then ok "linkage/label reminder is executable"; else no "linkage/label reminder is executable"; fi
if [[ -x "$STALE" ]]; then ok "stale-checkout guard is executable"; else no "stale-checkout guard is executable"; fi

echo
echo "== both hooks are registered in hooks.json, on the right event =="
HOOKS_JSON="${HOOKS_DIR}/hooks.json"
if node -e 'JSON.parse(require("fs").readFileSync(process.argv[1],"utf8"))' "$HOOKS_JSON"; then
  ok "hooks.json parses as JSON"
else
  no "hooks.json parses as JSON"
fi
# The JS below uses string concatenation rather than a template literal on purpose: a `${...}` inside
# a single-quoted shell argument reads to shellcheck (SC2016) as a shell expansion that will not
# expand, and it is right to say so — the two syntaxes are indistinguishable from outside.
registered="$(node -e '
  const h = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8")).hooks;
  const cmds = (event) => (h[event] ?? []).flatMap((m) => (m.hooks ?? []).map((x) => x.command)).join(" ");
  const pre = cmds("PreToolUse").includes("pretooluse-stale-checkout-claim-guard.mjs");
  const post = cmds("PostToolUse").includes("posttooluse-pr-linkage-and-label-reminder.mjs");
  console.log(String(pre) + " " + String(post));
' "$HOOKS_JSON")"
if [[ "$registered" == "true true" ]]; then
  ok "stale guard on PreToolUse, linkage reminder on PostToolUse"
else
  no "stale guard on PreToolUse, linkage reminder on PostToolUse" "$registered"
fi

echo
echo "== the linkage hook asks GitHub for its parse, rather than regexing the body =="
# A body regex cannot tell an intentional "Fixes #123" from the accidental "three fixes #788". The
# intentional case is the COMMON one, so such a guard is noise if it warns and wrong if it blocks.
if grep -q 'closingIssuesReferences' "$LINKAGE"; then
  ok "asks GitHub for its own parse"
else
  no "asks GitHub for its own parse"
fi

echo
echo "== stale-checkout guard: fires on a publishing command in a never-fetched clone =="
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
git -C "$TMP" init -q
git -C "$TMP" commit -q --allow-empty -m "seed"
# A fresh clone has no FETCH_HEAD at all, which the hook treats as maximally stale — not as fine.
out="$(cd "$TMP" && feed "$STALE" "$(bash_payload 'gh issue create --title x --body y')")"
if [[ "$out" == *'"permissionDecision":"deny"'* ]]; then
  ok "denies gh issue create in a never-fetched clone"
else
  no "denies gh issue create in a never-fetched clone" "$out"
fi
if [[ "$out" == *'git fetch --all --prune'* ]]; then
  ok "the denial says exactly what to run"
else
  no "the denial says exactly what to run" "$out"
fi

echo
echo "== stale-checkout guard: the escape works, and non-publishing commands are untouched =="
out="$(cd "$TMP" && feed "$STALE" "$(bash_payload 'gh issue create --title x --body y # STALE-CHECKOUT-OK')")"
if [[ -z "$out" ]]; then ok "STALE-CHECKOUT-OK suppresses the guard"; else no "STALE-CHECKOUT-OK suppresses the guard" "$out"; fi

out="$(cd "$TMP" && feed "$STALE" "$(bash_payload 'gh issue list --limit 5')")"
if [[ -z "$out" ]]; then ok "a read-only gh command is ignored"; else no "a read-only gh command is ignored" "$out"; fi

out="$(cd "$TMP" && feed "$STALE" "$(bash_payload 'gh pr merge 787')")"
if [[ -z "$out" ]]; then ok "gh pr merge publishes no prose, so it is ignored"; else no "gh pr merge publishes no prose, so it is ignored" "$out"; fi

out="$(cd "$TMP" && feed "$STALE" '{"tool_name":"Read","tool_input":{"file_path":"/tmp/x"}}')"
if [[ -z "$out" ]]; then ok "a non-Bash tool is ignored"; else no "a non-Bash tool is ignored" "$out"; fi

echo
echo "== stale-checkout guard: a FRESH fetch is allowed through =="
# This is the assertion that proves the guard measures something. Without it, a hook that denied
# unconditionally would pass every test above.
touch "$TMP/.git/FETCH_HEAD"
out="$(cd "$TMP" && feed "$STALE" "$(bash_payload 'gh pr create --title x --body y')")"
if [[ -z "$out" ]]; then
  ok "a just-fetched checkout publishes without objection"
else
  no "a just-fetched checkout publishes without objection" "$out"
fi

echo
echo "== stale-checkout guard: staleness is measured, not assumed =="
# Backdate FETCH_HEAD past the two-hour threshold. Same clone, same command, opposite verdict —
# so the only thing that changed the answer is the quantity the hook claims to measure.
touch -t "$(date -v-9H '+%Y%m%d%H%M' 2>/dev/null || date -d '9 hours ago' '+%Y%m%d%H%M')" "$TMP/.git/FETCH_HEAD"
out="$(cd "$TMP" && feed "$STALE" "$(bash_payload 'gh pr create --title x --body y')")"
if [[ "$out" == *'"permissionDecision":"deny"'* ]]; then
  ok "a 9-hour-old fetch is denied where a fresh one passed"
else
  no "a 9-hour-old fetch is denied where a fresh one passed" "$out"
fi
if [[ "$out" == *"9h ago"* ]]; then
  ok "the denial reports the measured age, not a boolean"
else
  no "the denial reports the measured age, not a boolean" "$out"
fi

echo
echo "== linkage hook: ignores everything that is not a PR write =="
out="$(feed "$LINKAGE" "$(bash_payload 'gh issue create --title x')")"
if [[ -z "$out" ]]; then ok "gh issue create is not a PR command"; else no "gh issue create is not a PR command" "$out"; fi

out="$(feed "$LINKAGE" '{"tool_name":"Read","tool_input":{"file_path":"/tmp/x"}}')"
if [[ -z "$out" ]]; then ok "a non-Bash tool is ignored"; else no "a non-Bash tool is ignored" "$out"; fi

out="$(feed "$LINKAGE" '{"tool_name":"Bash","tool_input":{"command":"gh pr create --title x"},"tool_output":"no url here"}')"
if [[ -z "$out" ]]; then ok "an unresolvable PR number exits silently"; else no "an unresolvable PR number exits silently" "$out"; fi

echo
echo "== linkage hook: the two reporting branches, against a stubbed gh =="
# The hook's whole value is in what it SAYS, and that depends on a network call. Stubbing `gh` puts
# both branches under test offline. This is not a convenience: measured against the real repository,
# 0 of the last 30 merged alpha-forge PRs carry a closing reference, so the branch that matters most
# has no live fixture to run against — and a branch with no fixture is a branch nobody has read.
STUB_DIR="$TMP/stub"
mkdir -p "$STUB_DIR"

write_gh_stub() { # write_gh_stub <json-that-gh-pr-view-should-print>
  cat >"$STUB_DIR/gh" <<STUB
#!/usr/bin/env bash
echo '$1'
STUB
  chmod +x "$STUB_DIR/gh"
}

# Branch A: GitHub reports a closing link. This is the alpha-forge#787 shape — the PR had acquired a
# promise to close #788 that nobody wrote on purpose.
write_gh_stub '{"number":787,"title":"t","labels":[{"name":"documentation"}],"closingIssuesReferences":[{"number":788}]}'
out="$(PATH="$STUB_DIR:$PATH" feed "$LINKAGE" '{"tool_name":"Bash","tool_input":{"command":"gh pr edit 787"}}')"
if [[ "$out" == *"MERGING THIS WILL CLOSE"* && "$out" == *"#788"* ]]; then
  ok "names every issue the merge would close"
else
  no "names every issue the merge would close" "$out"
fi
if [[ "$out" == *"parsed as the keyword"* ]]; then
  ok "explains that a closing link can be created by accident"
else
  no "explains that a closing link can be created by accident" "$out"
fi
if [[ "$out" == *"NO LABELS"* ]]; then
  no "stays quiet about labels when the PR has one" "$out"
else
  ok "stays quiet about labels when the PR has one"
fi

# Branch B: no closing link and no labels — the state every recent alpha-forge PR was actually in.
write_gh_stub '{"number":790,"title":"t","labels":[],"closingIssuesReferences":[]}'
out="$(PATH="$STUB_DIR:$PATH" feed "$LINKAGE" '{"tool_name":"Bash","tool_input":{"command":"gh pr edit 790"}}')"
if [[ "$out" == *"NO ISSUE WILL BE CLOSED"* ]]; then
  ok "says so when nothing will close"
else
  no "says so when nothing will close" "$out"
fi
if [[ "$out" == *"NO LABELS"* && "$out" == *"gh pr edit 790 --add-label"* ]]; then
  ok "reports missing labels with the exact command to add one"
else
  no "reports missing labels with the exact command to add one" "$out"
fi

# Branch C: `gh` itself fails. A reminder that cannot run must not interrupt the session.
printf '#!/usr/bin/env bash\nexit 1\n' >"$STUB_DIR/gh"
chmod +x "$STUB_DIR/gh"
out="$(PATH="$STUB_DIR:$PATH" feed "$LINKAGE" '{"tool_name":"Bash","tool_input":{"command":"gh pr edit 790"}}')"
if [[ -z "$out" ]]; then
  ok "a failing gh call is silent, not an interruption"
else
  no "a failing gh call is silent, not an interruption" "$out"
fi

echo
echo "== linkage hook: reports as a non-blocking PostToolUse, never a denial =="
# A PostToolUse hook cannot refuse anything — the command has already run. If this ever emits a
# PreToolUse-shaped deny, it is silently doing nothing at all.
if grep -q '"decision": *"block"\|decision: *"block"' "$LINKAGE"; then
  ok "emits the PostToolUse {decision:block} envelope"
else
  no "emits the PostToolUse {decision:block} envelope"
fi
if grep -q 'permissionDecision' "$LINKAGE"; then
  no "does not emit a PreToolUse permissionDecision"
else
  ok "does not emit a PreToolUse permissionDecision"
fi

echo
echo "== each hook carries its own incident, so the next reader sees the shape =="
if grep -q 'fixes #788' "$LINKAGE"; then
  ok "linkage hook records the real failing sentence"
else
  no "linkage hook records the real failing sentence"
fi
if grep -q '47' "$STALE"; then
  ok "stale guard records the 47-commit incident"
else
  no "stale guard records the 47-commit incident"
fi

echo
echo "-- ${pass} passed, ${fail} failed --"
if [[ "$fail" -ne 0 ]]; then
  exit 1
fi
