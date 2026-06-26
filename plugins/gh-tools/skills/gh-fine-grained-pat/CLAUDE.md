# gh-fine-grained-pat — maintainer SSoT

Per-skill compass (sibling to [SKILL.md](./SKILL.md)). **Hub**: [gh-tools CLAUDE.md](../../CLAUDE.md). Read this before editing the engine — the GitHub UI is the fragile part and the load-bearing knowledge lives here.

## Why this exists

GitHub has **no API to create fine-grained PATs** (only the web UI). We created one by hand-driven browser automation, hit every gotcha, and codified the result here so it never has to be re-learned. The declarative JSON spec is the SSoT; the engine is a thin, anti-fragile UI driver.

## File map

| File                            | Role                                                                                                               |
| ------------------------------- | ------------------------------------------------------------------------------------------------------------------ |
| `scripts/pat.mjs`               | CLI: `login \| doctor \| create \| list \| inspect \| delete \| quit`. Secure token output (0600 / vault).         |
| `scripts/browser.mjs`           | Chrome launch (persistent profile), CDP attach (`/json/version` → `connectOverCDP`, retry), specific-PID teardown. |
| `scripts/form.mjs`              | The form driver — all the gotchas. `createToken / listTokens / inspectToken / deleteToken`.                        |
| `scripts/selectors.mjs`         | Selector constants + generic click/wait/DOM-fallback/screenshot helpers.                                           |
| `schema/token-spec.schema.json` | JSON Schema 2020-12 — formal spec SSoT.                                                                            |
| `specs/*.json`                  | Five templates (release-bot, read-only-auditor, ci-status-reporter, account-scoped, kitchen-sink).                 |
| `test/campaign.mjs`             | Empirical create→verify→delete harness + forced-failure + leak sweep.                                              |

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

When adding a new permission to a spec, confirm its detail noun (create one token, read the detail page) and add it to `NOUN` — otherwise verification reports a false "perm missing".

## Security invariants

- Token value never reaches stdout/chat: `--out` writes 0600; `--vault scope:dot` shells `vault set` (value in-process). `inspect`/`list` never expose the value (the value is not on any later page anyway).
- Persistent profile (`~/.local/share/gh-pat-automation/profile`) holds the GitHub session cookie → sensitive, outside the repo, never committed.

## Recent changes

- **2026-06-26** — skill created. Engine + 5 spec templates + JSON Schema + empirical campaign harness. Codifies the gotchas learned while minting `cc-skills-release`. Empirically validated by create→verify→delete across all 5 specs + a forced-failure case (PASS). The campaign surfaced gotchas 5–7 (two-tab permissions, regenerate-link list scrape, friendly-noun detail page) which are now encoded + documented.
