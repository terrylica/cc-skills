#!/usr/bin/env bash
# test-identity-guard-fails-closed-for-registry-owners.sh
#
# Pins the 2026-10-04 fail-closed rule in gh-repo-identity-guard.mjs: for a target owner the
# path-owner registry knows, a write is ALLOWED only when it goes through the gh routing shim
# (~/.local/bin/gh) and the mapped account's profile (~/.config/gh-<account>) exists; otherwise DENIED.
# Uses a synthetic HOME and registry, so it touches no real account or token.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
hook="$here/../gh-repo-identity-guard.mjs"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

mkdir -p "$tmp/home/.local/bin" "$tmp/home/.config/gh-orgadmin" "$tmp/work"
printf '#!/bin/sh\n' >"$tmp/home/.local/bin/gh"
cat >"$tmp/registry.toml" <<'EOF'
[[mapping]]
path_prefix = "~/gh/exampleorg"
owner       = "exampleorg"
account     = "orgadmin"
EOF

run() { # $1 = command string; prints the decision ("deny" or "allow")
  local json out
  json=$(printf '{"tool_name":"Bash","tool_input":{"command":%s}}' "$(printf '%s' "$1" | bun -e 'console.log(JSON.stringify(await Bun.stdin.text()))')")
  out=$(cd "$tmp/work" && printf '%s' "$json" | env -u GH_TOKEN HOME="$tmp/home" PATH_OWNER_REGISTRY="$tmp/registry.toml" bun "$hook" 2>/dev/null || true)
  case "$out" in *'"permissionDecision":"deny"'*) echo deny ;; *) echo allow ;; esac
}

fail=0
expect() { local got; got=$(run "$2"); if [[ "$got" == "$1" ]]; then echo "ok   $1  $2"; else echo "FAIL want $1 got $got  $2"; fail=1; fi; }

expect allow 'gh issue close 3 --repo exampleorg/app'
expect deny  '/opt/homebrew/bin/gh issue close 3 --repo exampleorg/app'
expect allow 'gh api repos/exampleorg/app/issues/3 -X PATCH -f state=closed'
rm -rf "$tmp/home/.config/gh-orgadmin"
expect deny  'gh issue close 3 --repo exampleorg/app'
expect allow 'ALLOW_OWNER_MISMATCH=1 true'   # not a gh write: ignored
mkdir -p "$tmp/home/.config/gh-orgadmin"; rm -f "$tmp/home/.local/bin/gh"
expect deny  'gh issue close 3 --repo exampleorg/app'
exit "$fail"
