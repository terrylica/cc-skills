#!/usr/bin/env bash
# test-token-get.sh — token_get reads the Keychain first and decrypts the vault only when it must
# (2026-10-16, Touch ID storms). Stubs `security` and `vault` on PATH; no real Keychain or vault access.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
mkdir -p "$T/bin"
# The functions under test, extracted from the script (it runs its CLI when executed).
sed -n '/^VAULT_SCOPE=/p; /^KC_SERVICE=/p; /^token_key()/p; /^vault_holds()/,/^}/p; /^token_get()/,/^}/p' "$HERE/chrome-profile.sh" > "$T/fns.sh"
cat > "$T/bin/security" <<'EOF'
#!/usr/bin/env bash
# args: find-generic-password -s SERVICE [-a ACCOUNT] -w
svc=""; for ((i=1; i<=$#; i++)); do [ "${!i}" = "-s" ] && { j=$((i+1)); svc="${!j}"; }; done
v=$(printf '%s' "${STUB_KC_ENTRIES:-}" | tr ';' '\n' | awk -v s="$svc" '{ i = index($0, "="); if (substr($0, 1, i - 1) == s) print substr($0, i + 1) }')
[ -n "$v" ] && { printf '%s\n' "$v"; exit 0; }; exit 44
EOF
cat > "$T/bin/vault" <<'EOF'
#!/usr/bin/env bash
echo "$*" >> "$STUB_VAULT_LOG"
case "$1" in
  list) printf '\n[other]  x\n  a_b_c\n\n[chrome-extension-tokens]  tokens\n'; printf '%s\n' ${STUB_VAULT_KEYS:-} | sed 's/^/  /' ;;
  get) echo "vault-$3" ;;
esac
EOF
chmod +x "$T/bin/security" "$T/bin/vault"
export PATH="$T/bin:$PATH" STUB_VAULT_LOG="$T/vault.log"
# shellcheck disable=SC1091
. "$T/fns.sh"
fail=0
check() { if [ "$2" = "$3" ]; then echo "ok   $1"; else echo "FAIL $1: got '$2', want '$3'"; fail=1; fi; }
gets() { grep -c '^get ' "$T/vault.log" 2>/dev/null || true; }

: > "$T/vault.log"; export STUB_KC_ENTRIES="chrome-extension-tokens-a_b_c=MIRROR;playwright-extension-token=OWN" STUB_VAULT_KEYS="a_b_c"
check "the vault's Keychain mirror wins, and the vault is never called" "$(token_get a@b.c)|$(gets)|$(wc -l < "$T/vault.log" | tr -d ' ')" "MIRROR|0|0"
: > "$T/vault.log"; export STUB_KC_ENTRIES="playwright-extension-token=PLAYWRIGHT_MCP_EXTENSION_TOKEN=OWN" STUB_VAULT_KEYS=""
check "own Keychain item next (prefix stripped); no vault get" "$(token_get a@b.c)|$(gets)" "OWN|0"
: > "$T/vault.log"; export STUB_KC_ENTRIES="" STUB_VAULT_KEYS="x_y_z"
check "no Keychain entry and the vault does NOT hold the key: no decrypt" "$(token_get a@b.c)|$(gets)" "|0"
: > "$T/vault.log"; export STUB_KC_ENTRIES="" STUB_VAULT_KEYS="a_b_c"
check "no Keychain entry and the vault holds it: exactly one vault get" "$(token_get a@b.c)|$(gets)" "vault-a_b_c|1"
: > "$T/vault.log"; export STUB_KC_ENTRIES="" STUB_VAULT_KEYS="a_b_c_d"
check "a longer key with the same prefix is not a match" "$(token_get a@b.c)|$(gets)" "|0"
exit $fail
