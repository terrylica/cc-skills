# ADR: Autonomous, multi-account GitHub web-auth for the PAT engine — virtual passkey (primary) + password/TOTP (fallback)

- **Status**: Accepted (2026-06-26) — multi-account, Touch-ID gated, one-tap-per-session guarantee.
- **Date**: 2026-06-26
- **Related**: [`gh-fine-grained-pat` skill](/plugins/gh-tools/skills/gh-fine-grained-pat/SKILL.md) · [Self-Custody Secrets](/docs/self-custody-secrets.md) · [SCS tiered Touch-ID + dotenvx ADR](/docs/adr/2026-06-26-scs-tiered-touchid-and-dotenvx-last-mile.md) · [gh-tools multi-account host-alias model](/plugins/gh-tools/CLAUDE.md)

## Context

The `gh-fine-grained-pat` engine drives GitHub's web UI (there is **no API** to create fine-grained PATs). The one remaining manual step is GitHub's **sudo mode** ("Confirm access") — and the initial login on a fresh profile — which today need a human gesture (the engine waits via `ensureFormReady()`).

The operator wants this **autonomous** and **applicable to ALL their GitHub accounts** — not a single identity. This Mac already runs a **multi-account model**: a repo's `origin` remote `git@github.com-<account>:owner/repo.git` (host-alias) is the single source of truth for which account owns it, and the neutral `gh` wrapper derives the account + isolated `GH_CONFIG_DIR` from that alias (see gh-tools CLAUDE.md). The autonomous web-auth system must plug into that model: given a target, resolve the **account**, then present **that account's** self-custodied credential.

There is no GitHub API shortcut — the web challenge must be satisfied in-browser, so each account needs a credential the agent can present unattended, held in the SCS vault.

## Findings (research-confirmed)

1. **Virtual WebAuthn authenticator (CDP).** Chrome's DevTools Protocol `WebAuthn` domain mounts a _virtual authenticator_ that signs passkey challenges **with no biometric**: `WebAuthn.enable` → `addVirtualAuthenticator({ protocol:'ctap2', transport:'internal', hasResidentKey:true, hasUserVerification:true, isUserVerified:true, automaticPresenceSimulation:true })` → `addCredential` / `getCredentials`. Chromium-only; Playwright reaches it via `page.context().newCDPSession(page)`. Enable presence simulation **before** triggering the prompt (race condition). ([Chrome DevTools WebAuthn](https://developer.chrome.com/docs/devtools/webauthn), [CDP WebAuthn domain](https://chromedevtools.github.io/devtools-protocol/tot/WebAuthn/), [Corbado](https://www.corbado.com/blog/passkeys-e2e-playwright-testing-webauthn-virtual-authenticator))
2. **Password + TOTP** is the fallback the sudo page already offers ("Use your password" + "authenticator app"); TOTP via `oathtool --totp -b <seed>`.
3. **GitHub ToS allows one machine account per person** — so a _per-account_ dedicated low-privilege identity is available where wanted. ([GitHub fine-grained PAT blog](https://github.blog/security/application-security/introducing-fine-grained-personal-access-tokens-for-github/))
4. **Host-alias is the existing identity SSoT** — the engine reuses `~/.claude/tools/bin/gh-token-for-repo`'s account-resolution model rather than inventing a new one.

## Decision

Build a **hybrid, multi-account autonomous authenticator** into the engine, invoked when `ensureFormReady()` detects the sudo/login challenge.

### Identity resolution ("the search system")

Resolve the target account in priority order, then load that account's vault credential:

1. explicit `--account <login>` flag, else
2. the working repo's `origin` host-alias (`git@github.com-<account>:…`), else
3. the token spec's `owner`, else
4. the profile's currently-logged-in account.

A small **identity registry** (`vault list` of `github-web-<account>` scopes + a manifest line per account) answers "which of my accounts have autonomous web-auth provisioned?" — discoverable, self-documenting, and aligned with the host-alias SSoT.

### Authentication

- **Primary — virtual passkey.** Mount a CDP virtual authenticator, inject the resolved account's passkey credential from the vault, satisfy the challenge autonomously.
- **Fallback — password + TOTP.** If passkey isn't offered/fails: "Use your password" → fill password → "authenticator app" → fill `oathtool` TOTP. Both from the same account's vault entry.

### Vault integration — per account, **Touch-ID gated (decided)**

Each account's web credential is a **crown jewel** → stored in the gated Touch-ID tier (per the tiered-SCS ADR), NOT the plain agent-readable tier. To keep the biometric to **exactly one tap**, all of an account's web secrets live in **one gated JSON blob** (not three separate items — three items would mean three Touch-ID prompts):

| Gated item (per account `<a>`) | Contents                                                                                                    |
| ------------------------------ | ----------------------------------------------------------------------------------------------------------- |
| `github-web-<a>`               | one JSON: `{ passkey:{credentialId, privateKey(PKCS#8), rpId, userHandle, signCount}, password, totpSeed }` |

### Biometric frequency — the operator's hard requirement: ONE tap, then nothing

The design **guarantees a single Touch-ID prompt** when you "go inside to operate," then no further prompts for the rest of the session:

1. **One blob → one `get` → one prompt.** Reading `github-web-<a>` is a single gated read = one Touch ID, unlocking passkey + password + TOTP together.
2. **In-process cache.** Within one engine run (a `register` ceremony, a `create`/`rotate`, or the whole campaign batch — all one process), the decrypted blob is held in memory for the run → the single tap covers every action in that run.
3. **Session agent (memory-only) for multiple commands.** Because separate `pat` invocations are separate processes, an optional **ssh-agent-style web-auth agent** holds the unlocked blob in a session-scoped, memory-only process (configurable TTL, default = session). The first command taps once; later commands in the same session reuse the agent with **zero** further taps. Kill the agent (or session end) re-locks.

The decrypted material never touches disk or chat; the passkey private key enters only the in-memory virtual authenticator. Headless/cron is **not** supported by design (gated needs that one live tap at session start) — the accepted trade-off for "the agent can't impersonate any of my accounts while I'm away."

## Security analysis

A web credential grants a **full GitHub web session** for that account — broader than the scoped PATs; GitHub has no "session scoped to token creation." Mitigations, now layered on the multi-account design:

1. **Touch-ID gated (decided)** — one unlock per account per session; the agent cannot silently authenticate as any account across sessions.
2. **Per-account least privilege (operator's per-account choice)** — for any account where blast radius matters, provision the autonomous credential on a **dedicated low-privilege machine account** (ToS-permitted) that is only a least-privilege collaborator on the needed repos, instead of a primary human account. The system treats bot and human accounts identically; this choice is made per account at setup.
3. **Audit + rotation** — every autonomous auth logs to the vault JSONL audit (account, timestamp, action); rotate passkey/password periodically; each account's own fine-grained-PAT activity stays independently visible.

## One-time setup runbook (per account, interactive once)

1. (Optional, recommended for risky scopes) create/least-privilege a dedicated machine account for `<a>`.
2. `pat login --account <a>` into the persistent profile.
3. **Registration ceremony** (`pat register --account <a>`): engine mounts the virtual authenticator → GitHub → Settings → Passkeys → "Add a passkey" → virtual authenticator creates a resident credential → `WebAuthn.getCredentials` captures it; the engine assembles the **single JSON blob** (passkey + password + TOTP seed, the latter two collected in the same ceremony) and pipes it into `vault set --gated github-web-<a>` (never to chat).
4. (TOTP seed from GitHub 2FA "Set up using an app" → text code; password entered into the same ceremony's secure prompt.)
5. `vault doctor` + a dry-run sudo challenge on a repo owned by `<a>` to confirm one-tap autonomous pass.

Repeat per account; the identity registry grows as accounts are provisioned.

## Implementation plan (after approval)

- `scripts/identity.mjs` — resolve account (flag → host-alias → spec owner → logged-in) + registry listing.
- `scripts/webauthn.mjs` — CDP virtual-authenticator helpers (enable/add/get/remove) + credential (de)serialize.
- `scripts/autosudo.mjs` — orchestrate: resolve account → unlock its single gated blob (one Touch ID, via the session agent if running) → try passkey → fall back to password/TOTP.
- `scripts/webauth-agent.mjs` — optional memory-only session agent (ssh-agent pattern): holds the unlocked blob, TTL-bounded, so repeated `pat` commands re-use one tap. `pat agent start|stop|status`.
- `form.mjs` `ensureFormReady()` — when sudo detected and `GH_PAT_AUTONOMOUS=1`, call `autosudo`; keep the human-wait as default/fallback.
- `pat.mjs` — `register --account` verb; `--account` flag on create/rotate; `agent` subcommands.
- Vault — one gated `github-web-<account>` JSON blob per account; no plain-tier copies.

## Verification

- Dry-run per account: fresh profile (sudo required) → `pat create … --account <a>` completes after **one Touch-ID unlock**, no further gesture.
- Negative: corrupt the passkey → falls back to password/TOTP → succeeds; corrupt both → fails loudly (no silent bypass).
- Multi-account: two accounts provisioned; resolution picks the right one by host-alias; each unlocks independently.
- Audit: each autonomous auth appears in the vault JSONL log with its account.

## Open decision (resolved / remaining)

- **Tier**: ✅ decided — Touch-ID gated for every account.
- **Identity scope**: ✅ multi-account — applies to all accounts via the host-alias SSoT.
- **Remaining (per account, at setup, not blocking)**: dedicated low-privilege machine account vs the real account — chosen per account when running the ceremony.

## Consequences

- **+** One-touch autonomy for token ops across **all** accounts; passkey private keys self-custodied + gated.
- **+** Reuses the existing host-alias identity SSoT; reusable for any GitHub web sudo action.
- **+** Gated tier keeps the SCS "agent can't use crown jewels unattended" invariant intact.
- **−** No fully-headless/cron support (gated needs a human at session start) — deliberate.
- **−** Chromium-only (already an engine constraint).
- **−** GitHub passkey/2FA setup UI may drift — the registration ceremony needs its own selector map (same maintenance model as the rest of the skill).
