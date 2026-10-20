# web-forge

Browser automation for the operations vendors give no API for: console-only settings, scoped API tokens, OAuth apps, account toggles. A human supervises sign-in; scripts do the rest, reproducibly, with secrets going straight to the vault.

**Why it exists:** GitHub fine-grained PATs and OAuth apps have no creation API; a Cloudflare token cannot grant itself new scopes; Google Workspace's Gmail Default routing is absent from every admin API and from GAM. The only path is the console, so drive it with a real Chrome and make everything else scripted, secrets-safe and replayable.

## Two connection modes

- **extension** — a profile of your everyday Chrome, chosen by account email, through Microsoft's Playwright Extension (set up once with the [chrome-profiles](../chrome-profiles/README.md) plugin: `chrome-profile.sh setup you@example.com`). Use it when the session you need is already signed in there.
- **cdp** — a persistent per-site profile under `~/.local/share/web-forge/` on its own debug port. A human logs in once; the session survives across runs.

## Skills

- **dashboard-forge** — the method: step-and-shoot, identity preflight before mutating anything, DOM-to-vault secret extraction (never screenshots), consent-overlay handling, and a dated Vendor Quirks drift log.
- **admin-console** — Google Workspace Admin settings that no API reaches, as recipes: idempotent ensure, read-back after Save, per-step screenshots, a re-authentication gate that alerts a human and never types a password. First recipe: `gmail-default-routing`.
- **cf-access-wall** — JSON spec → idempotent Cloudflare Access setup: GitHub SSO + emailed one-time PIN, email allow-lists, per-app sessions, service tokens. Works directly on `*.workers.dev`.
- **azure-provision** — mint an Azure service principal through a portal session when `az login` is blocked by Conditional Access, then provision over REST.

## Quick start

```bash
WF="$(cc-plugin-root web-forge)/scripts/web-forge.ts"
bun "$WF" recipes --json     # every recipe, verb, flag and exit code
bun "$WF" gmail-default-routing ensure --account admin@example.com \
  --match group:team@example.com --change-envelope-recipient inbox@example.com \
  --add-original-to-header --dry-run --screenshots ./shots
```

Recipe flags can also live in a JSON file kept in the project's own repository: `bun "$WF" gmail-default-routing ensure --spec ./routing.json`.

Requires: Bun (recipes), node + `playwright-core` (forge scripts), Chrome, the chrome-profiles plugin, the SCS `vault` CLI.
