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

# Resolve the REAL bun binary now, under the real HOME. `bun` on PATH is usually proto's shim,
# which looks for its tools under $HOME/.proto; with the synthetic HOME below it fails whenever
# PROTO_BUN_VERSION is exported (gate-slot exports it, so the pre-push gate did). The hook then
# never ran, and the empty output used to be scored "allow" -- every deny case failed and every
# allow case passed vacuously (found 2026-10-05).
bun_bin="$(bun -e 'console.log(process.execPath)')"

run() { # $1 = command string; prints the decision ("deny", "allow", or "error" if the hook did not run)
  local json out rc=0
  json=$(printf '{"tool_name":"Bash","tool_input":{"command":%s}}' "$(printf '%s' "$1" | "$bun_bin" -e 'console.log(JSON.stringify(await Bun.stdin.text()))')")
  out=$(cd "$tmp/work" && printf '%s' "$json" | env -u GH_TOKEN HOME="$tmp/home" PATH_OWNER_REGISTRY="$tmp/registry.toml" "$bun_bin" "$hook" 2>/dev/null) || rc=$?
  if (( rc != 0 )); then echo "error(rc=$rc)"; return; fi   # the guard always exits 0; anything else means it did not run
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
