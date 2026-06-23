# Self-Custody Secrets (SCS)

> Credential doctrine for keeping secrets in stores **the operator controls** —
> never an employer/company-managed vault. Glossary term: **Self-Custody Secrets
> (SCS)**. This document is public and **agnostic**: it uses placeholders only;
> real vault names, item IDs, usernames, hosts, and client identifiers live in a
> **local, git-ignored** credential registry on the operator's machine.

## Why

A company-provided password manager (e.g. 1Password Business/Teams) is convenient
but **not private from the employer**: shared vaults are visible to teammates, and
even an "Employee/Private" vault is recoverable by account admins and exposes item
counts in reports. Anything confidential to a _client_ or contracting relationship
therefore must not live there. SCS moves those secrets to stores you alone hold.

## The SCS ladder (prefer top-down)

1. **macOS login Keychain — machine SSoT.** Agent-readable with no prompt when the
   item ACL trusts the `security` binary; a human still needs Touch ID to _view_ it
   in Keychain Access.

   ```bash
   # store
   security add-generic-password -U -s <scope>-<service> -a <user> -w <secret> \
     -T /usr/bin/security -j "<description + url>" "$HOME/Library/Keychains/login.keychain-db"
   # read (no prompt, scriptable)
   security find-generic-password -s <scope>-<service> -w
   ```

2. **SOPS + age — versioned backup in the project repo.** Values encrypted, keys
   readable (the repo self-documents structure). The age private key lives in the
   Keychain, sourced at decrypt time:

   ```bash
   export SOPS_AGE_KEY_CMD='security find-generic-password -s <age-key-item> -w'
   sops <repo>/secrets/<scope>.sops.json     # edit decrypted; re-encrypts on save
   ```

3. **iCloud — personal off-device backup.** iCloud Drive for _files_ (e.g. the age
   key), the Passwords app for _logins_.

   > **Gotcha:** items created by `security` land in the **local `login`** keychain,
   > which does **not** sync to iCloud and does **not** appear in the Passwords app.
   > Back the age key up to iCloud Drive (or Passwords) **separately**.

4. **Provenance — a restore runbook + checksum manifest** committed beside the
   encrypted backup, so a future agent or a fresh machine can recover
   deterministically (which key, which repo/commit, which Keychain items).

## Naming convention (for AI-agent self-discovery)

- Keychain service id: **`<scope>-<service>`** — e.g. a project/client prefix plus
  the system. Account (`-a`) = the username; comment (`-j`) = human description + URL.
- SOPS file: `secrets/<scope>.sops.json`; age key item: `<scope>-age-key` (or shared).
- Keep an **agnostic registry/runbook** in the repo describing the convention and
  what _categories_ of items exist — never the secret values, and in public repos
  never the real ids/hosts (point to the local registry instead).

## 1Password is LAST RESORT

Use the company vault **only** for company-shared, non-confidential secrets, and
ask first whether the secret could live on the SCS ladder instead. When `op` is
genuinely required: `unset HTTPS_PROXY HTTP_PROXY` (the OAuth proxy 502s on
`api.1password.com`), prefer a service-account token for scriptable R/W, and resolve
concrete ids from the **local** registry.

## Enforcement

Two `devops-tools` hooks nudge toward this doctrine:

- `userpromptsubmit-1password-context-injection.sh` — injects the SCS ladder when a
  prompt mentions credentials/keychain/sops/age/1Password.
- `posttooluse-1password-pattern-reminder.sh` — after an `op` command, reminds that
  1Password is last-resort and points back to the SCS ladder.

Both are agnostic; broaden/adjust triggers there, keep secrets out of this repo.
