#!/usr/bin/env bash
# Resolve a Pushover secret field from 1Password (`op`) with a macOS Keychain fallback.
#
# GENERIC + fork-friendly: per-user config (which vault / which item) comes from env
# vars, optionally sourced from a PRIVATE config file under ~/.claude. This public
# script contains NO operator specifics — fork users point it at THEIR OWN 1Password
# item. See pushover-commander.local.env.example + references/private-config-setup.md.
#
# Logical fields → 1Password labels: the two login fields are ALIASED so this works
# with a standard 1Password "Login" item (username/password) OR custom-labelled
# fields, with a macOS Keychain fallback for each candidate:
#   login_email    -> login_email | username | email
#   login_password -> login_password | password
#   (user_key, device, api_token_main, api_token_test resolve by their own label)
#
# Config (set as env vars, or in the private config file below):
#   PUSHOVER_OP_VAULT                   your 1Password vault name
#   PUSHOVER_OP_ITEM                    1Password item name/id holding the fields
#   PUSHOVER_KEYCHAIN_SERVICE           macOS Keychain service for fallback (default: pushover-commander)
#   PUSHOVER_OP_SA_TOKEN_FILE           file with an op Service Account token (default: ~/.claude/.secrets/op-service-account-token)
#   PUSHOVER_COMMANDER_PRIVATE_CONFIG   path to the private env file
#                                       (default: ~/.claude/pushover-commander.private/pushover-commander.local.env)
#
# Usage: resolve_pushover_secret.sh <field>
#   field in: api_token_main api_token_test user_key device login_email login_password
set -euo pipefail
field="${1:?usage: resolve_pushover_secret.sh <field>}"

# Source the private config first (if present) so PUSHOVER_OP_* become available.
PRIVATE_CONFIG="${PUSHOVER_COMMANDER_PRIVATE_CONFIG:-$HOME/.claude/pushover-commander.private/pushover-commander.local.env}"
if [ -f "$PRIVATE_CONFIG" ]; then
  # shellcheck disable=SC1090
  . "$PRIVATE_CONFIG"
fi

VAULT="${PUSHOVER_OP_VAULT:-}"
ITEM="${PUSHOVER_OP_ITEM:-}"
SVC="${PUSHOVER_KEYCHAIN_SERVICE:-pushover-commander}"
SA_FILE="${PUSHOVER_OP_SA_TOKEN_FILE:-$HOME/.claude/.secrets/op-service-account-token}"

# Ordered candidate labels for the requested logical field (login aliases).
case "$field" in
  login_email)    candidates="login_email username email" ;;
  login_password) candidates="login_password password" ;;
  *)              candidates="$field" ;;
esac

op_read_label() {
  local ref="op://${VAULT}/${ITEM}/$1"
  # op network calls must bypass the sandbox/OAuth MITM proxy (env -u *PROXY*).
  if [ -f "${SA_FILE}" ]; then
    OP_SERVICE_ACCOUNT_TOKEN="$(cat "${SA_FILE}")" \
      env -u HTTPS_PROXY -u HTTP_PROXY -u https_proxy -u http_proxy -u ALL_PROXY -u all_proxy \
      op read "${ref}" 2>/dev/null || true
  else
    env -u HTTPS_PROXY -u HTTP_PROXY -u https_proxy -u http_proxy -u ALL_PROXY -u all_proxy \
      op read "${ref}" 2>/dev/null || true
  fi
}

val=""
for label in $candidates; do
  # 1Password first (only when a vault + item are configured).
  if [ -n "$VAULT" ] && [ -n "$ITEM" ]; then
    val="$(op_read_label "$label")"
    [ -n "$val" ] && break
  fi
  # macOS Keychain fallback for this candidate label.
  val="$(security find-generic-password -s "${SVC}" -a "$label" -w 2>/dev/null || true)"
  [ -n "$val" ] && break
done

if [ -z "$val" ]; then
  echo "resolve_pushover_secret: could not resolve '${field}' (tried labels: ${candidates}). Set PUSHOVER_OP_VAULT + PUSHOVER_OP_ITEM (e.g. in ${PRIVATE_CONFIG}) pointing at a 1Password item with these fields, or store them in the macOS Keychain service '${SVC}'. See pushover-commander.local.env.example / references/private-config-setup.md." >&2
  exit 1
fi
printf '%s' "${val}"
