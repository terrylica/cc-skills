#!/usr/bin/env bash
# userpromptsubmit-1password-context-injection.sh
#
# Detects credential-related keywords in user prompts and injects the
# Self-Custody Secrets (SCS) doctrine BEFORE Claude takes any action — so the
# default is operator-controlled stores, with an employer-managed 1Password
# demoted to last-resort. Proactive companion to
# posttooluse-1password-pattern-reminder.sh (which corrects after-the-fact).
#
# Trigger: UserPromptSubmit
# Output:  additionalContext (stdout) — visible to Claude when planning
# Plugin:  devops-tools (cc-skills marketplace)
#
# NOTE: This file is public. It stays AGNOSTIC — no real vault names, item IDs,
# usernames, hosts, or client identifiers. Concrete item references live in a
# local, git-ignored credential registry on the operator's machine.

set -euo pipefail

# Iter-35 bash-5.2-patsub-replacement-defense (cross-plugin sweep):
# disable bash 5.2+ `&`-as-backreference in ${VAR//PATTERN/REPLACEMENT}.
shopt -u patsub_replacement 2>/dev/null || true

PAYLOAD=$(cat)

# ===========================================================================
# PRE-JQ-FASTPATH (bash-builtin-case-glob, no process spawn ~0.05 ms):
# This hook fires on EVERY UserPromptSubmit. ~95% of prompts contain no
# credential keyword; bail before spawning jq. INTENTIONALLY OVER-INCLUSIVE
# substring match — ambiguous hits fall through to the precise \b-grep below
# (which drops false positives like "1page", "options", "manage", "page").
shopt -s nocasematch
case "$PAYLOAD" in
    *1password*|*1p*|*service\ account*|*sa\ token*|*claude\ automation*|*op://*|*op\ item*|*op\ read*|*op\ vault*|*op\ list*|*op\ create*|*op\ edit*|*op\ delete*|*keychain*|*sops*|*age-keygen*|*self-custody*|*credential*|*generic-password*|*password\ manager*|*vault*) ;;
    *) shopt -u nocasematch; exit 0 ;;
esac
shopt -u nocasematch
# ===========================================================================

PROMPT=$(echo "$PAYLOAD" | jq -r '.prompt // empty' 2>/dev/null) || exit 0
[[ -z "$PROMPT" ]] && exit 0

LOWER=$(echo "$PROMPT" | tr '[:upper:]' '[:lower:]')

# PRECISE filter (\b word boundaries). Covers both the SCS stack (keychain,
# sops, age-keygen, self-custody, generic-password) and legacy 1Password
# (1password, op subcommands, service account). Deliberately avoids bare
# "age"/"key"/"secret"/"password" (too noisy).
if ! echo "$LOWER" | grep -qE '\b(1password|1p|op item|op read|op vault|op list|op create|op edit|op delete|service account|sa token|claude automation vault|op://|keychain|sops|age-keygen|self-custody|credentials?|generic-password|password manager|vault (get|set|new-scope|list|manifest|backup-keys|recover|doctor))\b'; then
    exit 0
fi

# Inject the SCS doctrine. UserPromptSubmit honors stdout as additional context.
cat <<'CONTEXT_EOF'
[SELF-CUSTODY SECRETS] Credential work detected. Default to the Self-Custody
Secrets (SCS) doctrine — store secrets ONLY in operator-controlled stores,
NEVER an employer/company-managed vault.

PREFERRED (the breadcrumb): if a self-custody `vault` CLI is present
(e.g. ~/.claude/tools/vault — `vault get|set|new-scope|list|manifest|
backup-keys|recover|doctor`), USE IT. It wraps the entire ladder below behind
one interface, keeps a machine-readable secrets/manifest.toml index for
discovery, captures values via a hidden native prompt, and verifies encryption.
Start with `vault doctor` / `vault spec`. Do NOT invent ad-hoc storage.

Otherwise apply the SCS ladder directly (top-down):

1) macOS login Keychain = machine SSoT (agent-readable, no prompt):
     add:  security add-generic-password -U -s <scope>-<service> -a <user> \
             -w <secret> -T /usr/bin/security -j "<desc + url>" \
             "$HOME/Library/Keychains/login.keychain-db"
     read: security find-generic-password -s <scope>-<service> -w

2) Versioned backup = SOPS + age (keys readable, values encrypted; age key in
   Keychain). sops uses Go RE2 (NO lookahead) — keep _meta readable via
   `unencrypted_regex: "^_meta$"`, NEVER a negative-lookahead `encrypted_regex`
   (it silently encrypts NOTHING — always verify values show ENC[...]):
     export SOPS_AGE_KEY_CMD='security find-generic-password -s <age-key-item> -w'
     unset HTTPS_PROXY HTTP_PROXY      # the OAuth proxy 502s sops/age

3) Off-device backup = iCloud DRIVE (a plain synced folder, fully CLI-writable).
   The iCloud *Passwords app* / iCloud Keychain CANNOT be written from any CLI
   (Apple entitlement wall — errSecMissingEntitlement; verified). `security`
   items live in the LOCAL login keychain and do NOT sync. Back the age key up
   to iCloud Drive passphrase-encrypted — and note `age -p` needs a TTY, so use
   `gpg --batch --pinentry-mode loopback -c --cipher-algo AES256`.

4) Provenance = commit a restore-runbook + manifest beside the backup so a
   future agent (or a fresh Mac) can recover deterministically.

Naming for self-discovery: `<scope>-<service>` Keychain items + a descriptive
`-j` comment. Keep an agnostic registry/runbook in the repo.

1Password is LAST RESORT — company-shared secrets only, NEVER client-
confidential (the company vault is admin-visible/recoverable). If you reach for
`op`, first ask: can this live in the SCS ladder instead? If 1Password is
genuinely required: `unset HTTPS_PROXY HTTP_PROXY` first (the OAuth proxy 502s
on api.1password.com), and resolve item refs from the local credential registry.
CONTEXT_EOF

exit 0
