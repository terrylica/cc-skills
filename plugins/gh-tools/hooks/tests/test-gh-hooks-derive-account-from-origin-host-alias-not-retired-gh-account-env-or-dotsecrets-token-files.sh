#!/usr/bin/env bash
# test-gh-hooks-derive-account-from-origin-host-alias-not-retired-gh-account-env-or-dotsecrets-token-files.sh
#
# Regression test for the ADR 2026-06-21 host-alias migration of the gh-tools
# hooks. Before this change both hooks detected the active GitHub account from
# `GH_ACCOUNT` (set by mise per-directory) with a fallback that scanned
# ~/.claude/.secrets/gh-token-* files. That doctrine was RETIRED: mise no longer
# injects tokens, GH_ACCOUNT is gone, and the plaintext .secrets files are
# deleted. The single source of truth is now the origin remote's host-alias:
#
#     git@github.com-<account>:owner/repo.git   →   <account>
#
# This test pins the new contract for both hooks:
#
#   (A) STRUCTURAL — the retired signals are GONE from executable code:
#       (A1) no `process.env.GH_ACCOUNT` reads,
#       (A2) no `.secrets` / `readdirSync` / `gh-token-` token-file scanning,
#       (A3) the host-alias parse regex `github\.com-` IS present in both hooks.
#
#   (B) BEHAVIORAL — gh-repo-identity-guard.mjs:
#       (B1) ALIAS-OWNER FAST PATH: a push-required command targeting a repo
#            whose owner equals the origin host-alias account is ALLOWED with
#            NO GH_TOKEN set. (Pre-migration this fell into the "no token →
#            fail-open" branch by accident; now it is an explicit, token-free
#            allow — the central behavioral improvement.)
#       (B2) CROSS-ACCOUNT, NO TOKEN: a push-required command targeting a repo
#            owned by a DIFFERENT account, with no GH_TOKEN, fails open (exit 0,
#            no deny JSON) — the hook never runs `gh` to mint a token
#            (process-storm rule), so it cannot verify and must not block blind.
#       (B3) NON-WRITE: a read command is ignored (exit 0, silent).
#
#   (C) BEHAVIORAL — gh-issue-title-reminder.mjs:
#       (C1) issue-create path emits the title-maximization reminder
#            (decision:block) without needing any account detection.
#
# Verbose filename per user directive — encodes the exact contract
# ("derive-account-from-origin-host-alias-not-retired-gh-account-env-or-
# dotsecrets-token-files") so future maintainers searching for "host alias",
# "GH_ACCOUNT retired", ".secrets removed", or "gh-token-for-repo" find it.

set -uo pipefail

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GUARD="$HOOK_DIR/gh-repo-identity-guard.mjs"
REMINDER="$HOOK_DIR/gh-issue-title-reminder.mjs"

fail=0
pass() { printf '  PASS  %s\n' "$1"; }
err()  { printf '  FAIL  %s\n' "$1"; fail=1; }

# Run a hook in a throwaway git repo with a chosen origin URL.
# args: <runtime> <hook> <origin-url> <input-json> ; echoes "<exit>\t<stdout>"
run_in_repo() {
  local runtime="$1" hook="$2" origin="$3" json="$4"
  local tmp out rc
  tmp="$(mktemp -d)"
  (
    cd "$tmp" || exit 99
    git init -q
    git remote add origin "$origin"
  )
  out="$(cd "$tmp" && printf '%s' "$json" | env -u GH_TOKEN -u GITHUB_TOKEN -u GH_ACCOUNT -u GH_ORGS "$runtime" "$hook" 2>/dev/null)"
  rc=$?
  rm -rf "$tmp"
  printf '%s\t%s' "$rc" "$out"
}

echo "[A] STRUCTURAL — retired signals gone, host-alias parse present"
for h in "$GUARD" "$REMINDER"; do
  name="$(basename "$h")"
  # strip comments so we only inspect executable code for the retired signals
  code="$(grep -vE '^\s*(//|\*|/\*)' "$h")"
  if grep -q 'process\.env\.GH_ACCOUNT' <<<"$code"; then err "$name: still reads process.env.GH_ACCOUNT"; else pass "$name: no GH_ACCOUNT read"; fi
  # Retired = scanning the .secrets dir for gh-token-<user> files. The
  # gh-token-for-repo HELPER is the new correct path, so it must NOT trip this.
  if grep -qE '\.secrets|readdirSync' <<<"$code"; then err "$name: still scans .secrets/gh-token files"; else pass "$name: no .secrets token scanning"; fi
  if grep -qE 'github\\?\.com-' "$h"; then pass "$name: host-alias parse present"; else err "$name: missing host-alias parse regex"; fi
done

echo "[B] BEHAVIORAL — gh-repo-identity-guard.mjs"
# B1: alias account == owner, NO token → allow (silent)
IFS=$'\t' read -r rc out < <(run_in_repo bun "$GUARD" "git@github.com-alice:alice/widgets.git" \
  '{"tool_name":"Bash","tool_input":{"command":"gh issue edit 5 --repo alice/widgets --title x"}}')
if [ "$rc" = "0" ] && [ -z "$out" ]; then pass "B1 alias-owner fast path allows with no token"; else err "B1 expected silent allow, got rc=$rc out=$out"; fi

# B2: alias account != owner, NO token → fail-open (silent allow, no deny JSON)
IFS=$'\t' read -r rc out < <(run_in_repo bun "$GUARD" "git@github.com-alice:bob/things.git" \
  '{"tool_name":"Bash","tool_input":{"command":"gh issue edit 5 --repo bob/things --title x"}}')
if [ "$rc" = "0" ] && ! grep -q '"permissionDecision":"deny"' <<<"$out"; then pass "B2 cross-account no-token fails open"; else err "B2 expected fail-open, got rc=$rc out=$out"; fi

# B3: non-write command ignored
IFS=$'\t' read -r rc out < <(run_in_repo bun "$GUARD" "git@github.com-alice:bob/things.git" \
  '{"tool_name":"Bash","tool_input":{"command":"gh issue list --repo bob/things"}}')
if [ "$rc" = "0" ] && [ -z "$out" ]; then pass "B3 non-write command ignored"; else err "B3 expected silent ignore, got rc=$rc out=$out"; fi

echo "[C] BEHAVIORAL — gh-issue-title-reminder.mjs"
# C1: issue create emits a block reminder (no account detection needed)
IFS=$'\t' read -r rc out < <(run_in_repo node "$REMINDER" "git@github.com-alice:alice/widgets.git" \
  '{"tool_name":"Bash","tool_input":{"command":"gh issue create --repo alice/widgets --title hi"}}')
if [ "$rc" = "0" ] && grep -q '"decision":"block"' <<<"$out"; then pass "C1 issue-create reminder fires"; else err "C1 expected block reminder, got rc=$rc out=$out"; fi

echo
if [ "$fail" = "0" ]; then echo "ALL TESTS PASSED"; else echo "SOME TESTS FAILED"; fi
exit "$fail"
