---
status: accepted
date: 2026-06-26
decision-maker: Terry Li
consulted: [WebSearch, Explore, empirical macOS testing]
research-method: web-search + in-session empirical probes
perspectives: [ThreatModelVsAgent, SelfCustody, Autonomy]
---

# ADR: SCS evolution — tiered Touch-ID vault + dotenvx last-mile

> **Amendment (2026-10-04) — the key finding below is wrong for the CryptoKit route.** It holds for keys persisted *in the Keychain* (`SecItem` with an access group), which need the `keychain-access-groups` entitlement. CryptoKit `SecureEnclave.P256` keys are not stored by the system at all: `dataRepresentation` is an enclave-wrapped blob the caller keeps in a plain file, usable only by that Mac's Secure Enclave, with Touch ID enforced by the enclave. `age-plugin-se` (remko) works this way, and an **ad-hoc-signed** build created an `any-biometry` key on macOS 15 and served as a sops recipient — no Developer ID, no entitlement. Unattended, a decrypt waited 20 minutes and released nothing; with the operator present it took one Touch ID. The "master key untouched" deferral is therefore no longer forced: the vault is migrating its master key into the Secure Enclave in stages (additive recipients first, the old silent key retired last), with an offline recovery recipient because enclave keys cannot be exported. Two further lessons from the same audit: the app-level helper's Touch ID check can be bypassed by re-signing a look-alike with the same self-signed identity (which signs silently), and a Touch ID prompt must be written by the authenticator from what it can verify — signing identities of the requesting processes first, claimed command lines last and sanitised — never by the requester.

> **Note (2026-09-24):** jdx/mise has since been retired; proto manages toolchains and moon runs tasks. Any mise commands below are historical and no longer run; the decision text is unchanged.

## Context and Problem Statement

While scoping the mise→Moon/proto migration's secrets layer, we re-examined how this Mac handles secrets and **empirically proved** that Claude Code's own Bash tool can **silently read** Keychain items stored with `-T /usr/bin/security` (the exact flag the `vault` tool uses) — no prompt, no sandbox. So the existing vault gives **no protection against the agent itself**. We also wanted to lean on FOSS for the runtime "last mile" rather than hand-roll, and to defend crown-jewel keys against the agent.

## Decision

Evolve Self-Custody Secrets (SCS) into a **tiered** model and add a runtime injector, keeping the existing `vault` (Keychain + SOPS/age + iCloud) as the master store.

- **Automation tier** — narrow, low-blast-radius tokens (e.g. a scoped release PAT) stay in the plain, agent-readable Keychain (`-T /usr/bin/security`). This is acceptable _because_ the blast radius is small and unattended flows need no-prompt reads.
- **Crown-jewel tier** — master/private/age/signing keys and client-confidential secrets go to a **Touch-ID-gated** store via `vault set --gated` (a stably-signed app-level helper, `touchid/vault-touchid`), which a headless agent cannot read (it satisfies neither the Touch ID nor a GUI keychain prompt).
- **Runtime injection** — `vault run <scope> -- <cmd>` decrypts a scope in memory and injects secrets as env vars (nothing on disk); `--gated <name>=<ENV>` pulls a crown jewel with one Touch ID. **dotenvx** is installed as the FOSS alternative for committed, encrypted per-repo `.env` files.
- **Enforcement** — a PostToolUse hook nudges crown-jewel `security add … -T /usr/bin/security` toward `vault set --gated` (escape hatch `CROWN-JEWEL-PLAIN-OK`).
- **Master key untouched** — left plain for now so `vault get` + autonomous release keep working; re-gating is deferred.

## Key finding (the constraint that shaped this)

**Cryptographic item-level gating is impossible autonomously on macOS.** Every native path — `kSecAccessControl(.userPresence)` keychain items, Secure-Enclave keys (`SecKeyCreateRandomKey` + `kSecAttrTokenIDSecureEnclave`) — goes through `securityd`, which enforces the `keychain-access-groups` entitlement via the Apple **Developer Program**. Empirically: a self-signed entitlement is **killed by AMFI** (`SIGKILL`/exit 137); without it, `errSecMissingEntitlement` (-34018). The only bypasses are a **paid Developer ID** (provides a Team-ID-anchored entitlement) or an **AMFIExemption KEXT / disabling SIP** (a security _downgrade_ — rejected). So the gated tier is **app-level Touch ID** today; the **strong path is staged** (`touchid/main.swift` Secure-Enclave code + `vault-touchid.entitlements`) for a one-line re-sign once a Developer ID exists.

## Considered Alternatives

- **dotenvx "Armored Keys"** (off-device cloud key store) — rejected, it is not self-custody.
- **A self-signed code-signing cert** for item-level gating — created + trusted in-session, still **killed by AMFI** (no Apple Team ID to anchor the access group). Kept only as a stable signing identity for the app-level helper.
- **gopass / teller / 1Password** for injection — more supply-chain surface (Miasma worm targets pass/gopass/1Password); `sops exec-env` / `vault run` / `dotenvx run` cover the need with the stack already in use.

## Consequences

- **Positive:** crown jewels are no longer silently agent-readable; a FOSS, no-disk runtime injector (`vault run`); the upgrade to cryptographic gating is a single re-sign post-enrollment; the existing vault + autonomous release are untouched.
- **Negative / accepted:** app-level (not yet cryptographic) gating until a paid Apple Developer ID is enrolled; the automation tier remains agent-readable by design (narrow tokens only).

## Verification

`bun test ~/.claude/tools/vault/vault.test.ts` (11 tests); `vault run macmini` injects env (names+lengths only, no values printed); `vault-touchid` item is **not** silently readable by `security` (blocked); the enforcement hook nudges crown-jewel adds and stays silent on narrow tokens + escape hatch + unrelated commands.
