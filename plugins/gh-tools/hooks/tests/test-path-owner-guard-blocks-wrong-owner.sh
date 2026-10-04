#!/usr/bin/env bash
# test-path-owner-guard-blocks-wrong-owner.sh
#
# Regression test for pretooluse-path-owner-guard.mjs — the guard that enforces the
# local-path → GitHub-owner policy (SSoT: ~/.claude/path-owner-registry.toml).
#
# Incident 2026-07-18: ~/vj/cpc/scanners was created under `terrylica` instead of
# `vanjobbers` because `gh repo create … --source=. --push` ran with no `--owner`
# and no guard knew ~/vj → vanjobbers. This pins the fix:
#
#   (1) `gh repo create` with NO explicit owner in a mapped path → DENY.
#   (2) `gh repo create <wrong-owner>/name` → DENY;  <right-owner>/name → ALLOW.
#   (3) an org listed in allow_orgs (e.g. Eon-Labs under ~/eon) → ALLOW.
#   (4) `git remote set-url` / `git push` to a mismatched owner → DENY;
#       the correct host-alias owner → ALLOW.
#   (5) ALLOW_OWNER_MISMATCH=1 escape hatch → ALLOW.
#   (6) unmapped path / non-matching command → FAIL-OPEN (silent allow).
#
# Hermetic: a fixture registry is supplied via PATH_OWNER_REGISTRY, and the target
# path is passed as `cwd` in the hook JSON (no real dirs or network needed).

set -uo pipefail

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GUARD="$HOOK_DIR/pretooluse-path-owner-guard.mjs"

fail=0
pass() { printf '  PASS  %s\n' "$1"; }
err()  { printf '  FAIL  %s\n' "$1"; fail=1; }

# Fixture registry (mirrors the real house mappings we care about here).
REG="$(mktemp)"
cat >"$REG" <<'TOML'
schema_version = 1
[[mapping]]
path_prefix = "~/vj"
owner       = "vanjobbers"
[[mapping]]
path_prefix = "~/eon/cc-skills"
owner       = "terrylica"
allow_orgs  = ["Eon-Labs"]
[[mapping]]
path_prefix = "~/eon"
owner       = "terrylica"
allow_orgs  = ["Eon-Labs", "EonLabs-Spartan"]
[[mapping]]
path_prefix = "~/gh/vjspc"
owner       = "vjspc"
account     = "vjown"
[[mapping]]
path_prefix = "~/gh/kudoai"
owner       = "kudoai"
mode        = "read-only"
[reserved]
names_under_vanjobbers = ["sys-internal", "cpc-inbox"]
TOML

# run <cwd> <command-json-string> [EXTRA_ENV=val ...] ; echoes "<exit>\t<stdout>"
# Any trailing args are passed verbatim as env assignments (e.g. ALLOW_OWNER_MISMATCH=1).
run() {
  local cwd="$1" cmd="$2"
  shift 2
  local json out rc
  json="$(printf '{"tool_name":"Bash","tool_input":{"command":%s},"cwd":"%s"}' "$cmd" "$cwd")"
  out="$(printf '%s' "$json" | env -u GH_TOKEN -u GITHUB_TOKEN -u GH_ACCOUNT -u GH_ORGS \
    PATH_OWNER_REGISTRY="$REG" "$@" bun "$GUARD" 2>/dev/null)"
  rc=$?
  printf '%s\t%s' "$rc" "$out"
}
is_deny() { grep -q '"permissionDecision":"deny"' <<<"$1"; }

VJ="$HOME/vj/cpc/scanners"
EON="$HOME/eon/some-repo"

echo "[1] gh repo create with no explicit owner in ~/vj → DENY"
IFS=$'\t' read -r rc out < <(run "$VJ" '"gh repo create foo --source=. --push"')
if is_deny "$out"; then pass "no-owner create blocked"; else err "expected deny, got rc=$rc out=$out"; fi

echo "[2] gh repo create vanjobbers/foo in ~/vj → ALLOW"
IFS=$'\t' read -r rc out < <(run "$VJ" '"gh repo create vanjobbers/foo --source=. --push"')
if [ "$rc" = 0 ] && [ -z "$out" ]; then pass "correct owner allowed"; else err "expected silent allow, got rc=$rc out=$out"; fi

echo "[3] gh repo create terrylica/foo in ~/vj → DENY"
IFS=$'\t' read -r rc out < <(run "$VJ" '"gh repo create terrylica/foo"')
if is_deny "$out"; then pass "wrong owner blocked"; else err "expected deny, got rc=$rc out=$out"; fi

echo "[4] gh repo create Eon-Labs/foo in ~/eon → ALLOW (allow_orgs)"
IFS=$'\t' read -r rc out < <(run "$EON" '"gh repo create Eon-Labs/foo"')
if [ "$rc" = 0 ] && [ -z "$out" ]; then pass "allow_orgs owner allowed"; else err "expected allow, got rc=$rc out=$out"; fi

echo "[5] git remote set-url to terrylica in ~/vj → DENY"
IFS=$'\t' read -r rc out < <(run "$VJ" '"git remote set-url origin git@github.com:terrylica/x.git"')
if is_deny "$out"; then pass "wrong remote owner blocked"; else err "expected deny, got rc=$rc out=$out"; fi

echo "[6] git remote set-url to correct vanjobbers host-alias in ~/vj → ALLOW"
IFS=$'\t' read -r rc out < <(run "$VJ" '"git remote set-url origin git@github.com-vanjobbers:vanjobbers/x.git"')
if [ "$rc" = 0 ] && [ -z "$out" ]; then pass "correct remote owner allowed"; else err "expected allow, got rc=$rc out=$out"; fi

echo "[7] git push to explicit terrylica URL in ~/vj → DENY"
IFS=$'\t' read -r rc out < <(run "$VJ" '"git push git@github.com:terrylica/x.git main"')
if is_deny "$out"; then pass "wrong push destination blocked"; else err "expected deny, got rc=$rc out=$out"; fi

echo "[8] ALLOW_OWNER_MISMATCH=1 escape hatch (hook-process env) → ALLOW"
IFS=$'\t' read -r rc out < <(run "$VJ" '"gh repo create foo"' ALLOW_OWNER_MISMATCH=1)
if [ "$rc" = 0 ] && [ -z "$out" ]; then pass "escape hatch allows"; else err "expected allow, got rc=$rc out=$out"; fi

echo "[8b] ALLOW_OWNER_MISMATCH=1 as an IN-COMMAND prefix → ALLOW"
# The real-world form: the override is part of the command string; the hook process never
# inherits it. Regression for the 2026-07-19 live-fire bug (env-only check made this a no-op).
IFS=$'\t' read -r rc out < <(run "$VJ" '"ALLOW_OWNER_MISMATCH=1 gh repo create terrylica/foo"')
if [ "$rc" = 0 ] && [ -z "$out" ]; then pass "in-command prefix allows"; else err "expected allow, got rc=$rc out=$out"; fi

echo "[9] unmapped path /tmp → FAIL-OPEN"
IFS=$'\t' read -r rc out < <(run "/tmp" '"gh repo create foo"')
if [ "$rc" = 0 ] && [ -z "$out" ]; then pass "unmapped path fails open"; else err "expected allow, got rc=$rc out=$out"; fi

echo "[10] non-matching command (ls) → IGNORED"
IFS=$'\t' read -r rc out < <(run "$VJ" '"ls -la"')
if [ "$rc" = 0 ] && [ -z "$out" ]; then pass "non-target command ignored"; else err "expected silent ignore, got rc=$rc out=$out"; fi

GHV="$HOME/gh/vjspc/some-repo"
KUDO="$HOME/gh/kudoai/chatgpt.js"

echo "[11] gh repo create vanjobbers/cpc-inbox (reserved) from an UNMAPPED path → DENY"
IFS=$'\t' read -r rc out < <(run "/tmp" '"gh repo create vanjobbers/cpc-inbox --private"')
if is_deny "$out" && grep -q 'reserved name' <<<"$out"; then pass "reserved name blocked anywhere"; else err "expected reserved deny, got rc=$rc out=$out"; fi

echo "[12] gh repo create sys-internal --owner vanjobbers (reserved, flag form) → DENY"
IFS=$'\t' read -r rc out < <(run "/tmp" '"gh repo create sys-internal --owner vanjobbers"')
if is_deny "$out" && grep -q 'reserved name' <<<"$out"; then pass "reserved name via --owner blocked"; else err "expected reserved deny, got rc=$rc out=$out"; fi

echo "[13] gh repo create vjspc/cpc-inbox (reserved only under vanjobbers) in ~/gh/vjspc → ALLOW"
IFS=$'\t' read -r rc out < <(run "$GHV" '"gh repo create vjspc/cpc-inbox --private"')
if [ "$rc" = 0 ] && [ -z "$out" ]; then pass "same name under another owner allowed"; else err "expected allow, got rc=$rc out=$out"; fi

echo "[14] git push in a read-only path (~/gh/kudoai) → DENY"
IFS=$'\t' read -r rc out < <(run "$KUDO" '"git push origin main"')
if is_deny "$out" && grep -q 'read-only' <<<"$out"; then pass "read-only push blocked"; else err "expected read-only deny, got rc=$rc out=$out"; fi

echo "[15] git remote set-url in a read-only path → DENY"
IFS=$'\t' read -r rc out < <(run "$KUDO" '"git remote set-url origin https://github.com/kudoai/chatgpt.js.git"')
if is_deny "$out"; then pass "read-only re-point blocked"; else err "expected deny, got rc=$rc out=$out"; fi

echo "[16] reserved name with the in-command escape → ALLOW"
IFS=$'\t' read -r rc out < <(run "/tmp" '"ALLOW_OWNER_MISMATCH=1 gh repo create vanjobbers/cpc-inbox"')
if [ "$rc" = 0 ] && [ -z "$out" ]; then pass "escape hatch allows reserved"; else err "expected allow, got rc=$rc out=$out"; fi

rm -f "$REG"
echo
if [ "$fail" = 0 ]; then echo "ALL TESTS PASSED"; else echo "SOME TESTS FAILED"; fi
exit "$fail"
