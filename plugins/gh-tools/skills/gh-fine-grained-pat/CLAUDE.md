# gh-fine-grained-pat — maintainer SSoT

Per-skill compass (sibling to [SKILL.md](./SKILL.md)). **Hub**: [gh-tools CLAUDE.md](../../CLAUDE.md). Read this before editing the engine — the GitHub UI is the fragile part and the load-bearing knowledge lives here.

## Why this exists

GitHub has **no API to create fine-grained PATs** (only the web UI). We created one by hand-driven browser automation, hit every gotcha, and codified the result here so it never has to be re-learned. The declarative JSON spec is the SSoT; the engine is a thin, anti-fragile UI driver.

## File map

| File                            | Role                                                                                                                   |
| ------------------------------- | ---------------------------------------------------------------------------------------------------------------------- |
| `scripts/pat.mjs`               | CLI: `login \| doctor \| create \| rotate \| list \| inspect \| delete \| register \| agent \| accounts \| quit`.      |
| `scripts/browser.mjs`           | Chrome launch (persistent profile), CDP attach (`/json/version` → `connectOverCDP`, retry), specific-PID teardown.     |
| `scripts/form.mjs`              | The form driver — all the gotchas. `createToken / listTokens / inspectToken / deleteToken` + `ensureFormReady` (sudo). |
| `scripts/selectors.mjs`         | Selector constants + generic click/wait/DOM-fallback/screenshot helpers.                                               |
| `scripts/identity.mjs`          | Resolve target account (flag → host-alias → spec owner → logged-in) + provisioned-account registry. (ADR 2026-06-26)   |
| `scripts/webauthn.mjs`          | CDP virtual-authenticator helpers (mount/inject/getCredentials) — autonomous passkey, no biometric at run time.        |
| `scripts/autosudo.mjs`          | Clear GitHub sudo via the gated `github-web-<account>` blob: passkey primary, password/TOTP fallback.                  |
| `scripts/webauth-agent.mjs`     | Memory-only session agent (ssh-agent pattern) → one Touch-ID unlock lasts the session.                                 |
| `schema/token-spec.schema.json` | JSON Schema 2020-12 — formal spec SSoT.                                                                                |
| `specs/*.json`                  | Five templates (release-bot, read-only-auditor, ci-status-reporter, account-scoped, kitchen-sink) + `specs/examples/`. |
| `test/campaign.mjs`             | Empirical create→verify→delete harness + forced-failure + leak sweep.                                                  |
| `test/autonomous.test.mjs`      | Unit tests (identity parsing, credential serde, agent put/get/TTL).                                                    |
| `test/webauthn-smoke.mjs`       | Live CDP proof: virtual-authenticator create→capture→restore on localhost (GitHub-independent).                        |

## Runtime invariants (do NOT change blindly)

- **node, never bun.** Bun's `connectOverCDP` times out; node attaches in <1s. All scripts are `.mjs` run with `node`.
- **`--remote-allow-origins=*`** on the Chrome launch — Chrome 111+ rejects the CDP websocket without it.
- **CDP attach** = fetch `http://127.0.0.1:9222/json/version` → `webSocketDebuggerUrl` → `chromium.connectOverCDP()` (mirrors `gemini-deep-research/scripts/client.ts`). Retry both steps.
- `playwright-core` resolves from the repo root `node_modules` (pinned `^1.58.2`); scripts just `import { chromium } from "playwright-core"`.
- **Teardown kills a specific PID** found via `lsof -iTCP:<port>`; never `pkill -f` (process-storm policy in `~/.claude/CLAUDE.md`).
- **`browser.close()` after each command** disconnects Playwright only — the externally-launched Chrome keeps running (persistent session). Use `pat quit` to actually kill it.

## The four hard-won gotchas (encoded in `form.mjs`)

1. **Generate-confirmation overlay is NOT `role="dialog"`.** After clicking the form's "Generate token", a summary overlay ("New personal access token") appears with its own "Generate token" button portaled to the end of `<body>`. Detection by `role=dialog` fails. Fix: click the **last** visible button whose text is exactly "Generate token" (`generate()`). _This cost two failed attempts originally._
2. **Repo picker intercepts pointer events.** After selecting repos in `#repository-menu-list-dialog`, the dialog stays open and swallows the next click. Fix: close it via `button[aria-label="Close"]` before continuing (`setRepoAccess()`).
3. **"No expiration"** is selectable inline (no immediate modal); its confirmation arrives at the generate-time summary overlay — handled by (1). The inline amber "GitHub strongly recommends…" warning is not a blocker.
4. **Permission access levels.** Newly added permissions default to "Read-only". Each row has an "Access:" button → menu with `menuitemradio` "No access" / "Read-only" / "Read and write". Match the row by its heading prefix, then pick the target level. **Never touch Metadata** (auto-required RO).
5. **Permissions are split across two tabs.** The Permissions section has "Repositories" and "Account" tabs, each with its **own** "Add permissions" menu ("Select repository permissions" / "Select account permissions"). Repository perms (`Contents`, …) are only in the repo menu; account perms (`Gists`, …) only in the account menu. Add + set-level each group while its tab is active (`applyGroup`). _Discovered empirically: searching "Gists" in the repo menu returns "No items available"._
6. **Token-list scrape: capture only the name link.** Each token row has a name link `/settings/personal-access-tokens/<id>` AND a `…/<id>/regenerate?index_page=1` link that shares the id. A naive id-keyed map lets the regenerate link (text "This token has no expiration date") overwrite the name. Fix: match `/\/personal-access-tokens\/(\d+)(?:[?#]|$)/` so only the bare-id href is captured. _This caused a false "cc-skills-release MISSING" sweep on the first run._
7. **Detail-page verification uses friendly nouns, not labels.** A token's detail page renders permissions as prose grouped by access level — e.g. _"Read access to actions, metadata, and repository hooks"_ / _"Read and Write access to code, commit statuses, deployments, and environments"_ — NOT per-label rows. `test/campaign.mjs` parses these clauses and maps UI label → detail noun (below).
8. **GitHub sudo mode ("Confirm access").** On a session that hasn't re-authed recently (e.g. after a Chrome restart), navigating to the new-token page shows a "Confirm access" passkey/2FA challenge instead of the form — `input[name="user_programmatic_access[name]"]` is absent. This cannot be bypassed programmatically. `createToken` → `ensureFormReady()` detects it (page title "Confirm access") and waits up to 3 min for the operator to confirm in the browser, then proceeds. _The campaign needs a sudo-confirmed session; confirm once at the start of a run._

## Live selector map (update when GitHub drifts)

| Step              | Selector / strategy                                                                        |
| ----------------- | ------------------------------------------------------------------------------------------ | ------------- | ------ | ------------- |
| Name              | `input[name="user_programmatic_access[name]"]`                                             |
| Description       | `textarea[name="user_programmatic_access[description]"]`                                   |
| Expiration open   | `button` name `/days \(                                                                    | No expiration | Custom | Expiration/i` |
| Expiration pick   | exact text "No expiration" / `^<N> days` option                                            |
| Repo access radio | exact text "Public/All repositories" or "Only select repositories"                         |
| Repo picker open  | `button` name `/Select repositories/i`                                                     |
| Repo search       | `input[type="search"]:visible`                                                             |
| Repo option       | exact text `owner/name`                                                                    |
| Repo picker close | `#repository-menu-list-dialog button[aria-label="Close"]`                                  |
| Add permissions   | `button` name `/Add permissions/i`; check via `menuitemcheckbox` name = label              |
| Access level      | row "Access:" button → `menuitemradio` name = level                                        |
| Generate          | `button` name `/^Generate token$/i` (form), then **last** visible "Generate token" (modal) |
| Token value       | `input` whose value starts `github_pat_`                                                   |
| Token list        | `a[href*="/settings/personal-access-tokens/<id>"]` (text = name)                           |
| Account perms tab | `role=tab` name `/Account/i` → its own "Add permissions" menu                              |

## Detail-page noun map (for verification)

The token detail page names permissions with friendly nouns, not the UI labels. `test/campaign.mjs` (`NOUN`) maps them. Verified empirically:

| UI label      | Detail noun     |     | UI label        | Detail noun            |
| ------------- | --------------- | --- | --------------- | ---------------------- |
| Contents      | `code`          |     | Commit statuses | `commit statuses`      |
| Issues        | `issues`        |     | Deployments     | `deployments`          |
| Pull requests | `pull requests` |     | Environments    | `environments`         |
| Actions       | `actions`       |     | **Webhooks**    | **`repository hooks`** |
| Metadata      | `metadata`      |     | Gists (account) | `gists`                |

Verified for `specs/examples/dependabot-secrets.json`: `Dependabot secrets` → `dependabot secrets`, `Secrets` → `secrets`, `Secret scanning alerts` → `secret scanning alerts`.

When adding a new permission to a spec, confirm its detail noun (create one token, read the detail page) and add it to `NOUN` — otherwise verification reports a false "perm missing".

## Security invariants

- Token value never reaches stdout/chat: `--out` writes 0600; `--vault scope:dot` shells `vault set` (value in-process). `inspect`/`list` never expose the value (the value is not on any later page anyway).
- Persistent profile (`~/.local/share/gh-pat-automation/profile`) holds the GitHub session cookie → sensitive, outside the repo, never committed.

## Recent changes

- **2026-06-26** — skill created. Engine + 5 spec templates + JSON Schema + empirical campaign harness. Codifies the gotchas learned while minting `cc-skills-release`. Empirically validated by create→verify→delete across all 5 specs + a forced-failure case (PASS). The campaign surfaced gotchas 5–7 (two-tab permissions, regenerate-link list scrape, friendly-noun detail page) which are now encoded + documented.
- **2026-06-26 (follow-up)** — added `rotate`, two reminder hooks, `specs/examples/`, and **gotcha #8 (sudo mode)**: `createToken`→`ensureFormReady()` now waits (non-disruptively, no page reload) for the operator to clear GitHub's "Confirm access" challenge. Empirically verified `dependabot-secrets` and extended `NOUN` (dependabot secrets / secrets / secret scanning alerts).
- **2026-06-26 (autonomous web-auth, ADR-driven)** — multi-account autonomous sudo: virtual-authenticator passkey (primary) + password/TOTP fallback, gated `github-web-<account>` blob, session agent for one-tap-per-session, `register`/`agent`/`accounts` verbs + `--account` + `GH_PAT_AUTONOMOUS=1`. Core mechanism proven by `test/webauthn-smoke.mjs` (create→capture→restore) + `test/autonomous.test.mjs` (9 assertions). ADR: `/docs/adr/2026-06-26-autonomous-github-web-auth-virtual-passkey-and-totp-for-pat-engine.md`.
- **2026-06-26 (ceremony validated; autosudo pending)** — `register` ceremony works end-to-end: passkey URL is **`/settings/security`** (button "Add passkey"), NOT `/settings/passkeys` (404). Provisioned `terrylica` (gated `github-web-terrylica`). **Still unexercised live**: the autosudo passkey-assertion against a _real_ GitHub sudo challenge — GitHub sudo is server-side (~hours) and persisted from the ceremony, so a Chrome restart does NOT re-trigger it. `autosudo.mjs` sudo-page selectors ("Use passkey", password/TOTP) are best-effort and may need refinement on the first real sudo. Validate on the next natural sudo expiry.
