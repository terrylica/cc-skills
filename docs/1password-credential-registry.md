# 1Password Credential Registry (pattern — agnostic)

> **Public, agnostic file.** It documents the _shape_ of the 1Password integration
> only. **Real item IDs, vault IDs, integration IDs, account numbers, and hosts live
> in a LOCAL, git-ignored registry** — never here.
>
> Local registry (operator machine, mode `0600`, git-ignored):
> `~/.claude/.secrets/1password-credential-registry.local.md`
>
> **1Password is LAST RESORT** — see [Self-Custody Secrets](./self-custody-secrets.md).
> Client-confidential secrets belong on the SCS ladder (Keychain → SOPS/age → iCloud),
> NOT in a company-managed 1Password vault. Use `op` only for company-shared,
> non-confidential secrets.

## Service account model

Consolidate to **exactly ONE** service account scoped to a single automation vault,
read+write. Its secret value lives authoritatively in one 1Password item (cloud
master) and is materialized to one local cache file (mode `0600`) that every consumer
reads — no other copies.

```bash
# Retrieval (cloud master) — IDs come from the LOCAL registry, never hard-coded:
op item get <sa-token-item-id> --vault <automation-vault-id> --fields credential --reveal

# Usage (reads or writes — single R/W token):
OP_SERVICE_ACCOUNT_TOKEN="$(cat ~/.claude/.secrets/op-service-account-token)" \
  op <command> --vault <automation-vault-name>
```

## Proxy gotcha (applies to all `op` and many API calls)

The Claude Code OAuth proxy (`HTTPS_PROXY=127.0.0.1:<port>`) returns 502 on
`api.1password.com` and intercepts some provider APIs. Bypass before `op`:

```bash
unset HTTPS_PROXY HTTP_PROXY        # for op
curl --noproxy '*' ...             # or NO_PROXY=<api-host> for sender scripts
```

## Vault directory (shape)

| Vault role            | Access model                  | Notes                                                      |
| --------------------- | ----------------------------- | ---------------------------------------------------------- |
| `<automation-vault>`  | service-account read/write    | the only SA-accessible vault                               |
| `<personal/employee>` | user-session (biometric) only | SA cannot access; admin-recoverable → not for confidential |

## Credential items (shape)

Track each programmatic item in the **local** registry with: human label, item ID,
category (API credential / Login / Token), and "used by". For multi-field items,
retrieve specific fields by `op://<vault>/<item-id>/<field>`.

Example (multi-field notification credential — field names only, no IDs):

```bash
op read "op://<vault>/<item-id>/credential"        # e.g. app/API token
op read "op://<vault>/<item-id>/user_key"          # recipient identifier
```

## Migration note

Per the SCS doctrine, items here should be **migrating outward** to the operator's
self-custody stores over time. New client-confidential secrets must NOT be added to a
company vault — put them on the SCS ladder and record them in the local registry.
