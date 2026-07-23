# web-forge

Supervised browser automation for the operations vendors refuse to give APIs for — and the
declarative Cloudflare Access wall built on top of it.

**Why it exists:** GitHub fine-grained PATs and OAuth apps have no creation API; a Cloudflare
token cannot grant itself new scopes. The only path is the dashboard — so drive it with a real
Chrome over CDP, with the human supervising logins/2FA, and make everything else scripted,
secrets-safe, and replayable.

## Skills

- **dashboard-forge** — the method: step-and-shoot against a long-lived Chrome, identity
  preflight before mutating anything, DOM-to-vault secret extraction (never screenshots),
  consent-overlay handling, and a dated Vendor Quirks drift log.
- **cf-access-wall** — JSON spec → idempotent Cloudflare Access setup: GitHub SSO + emailed
  one-time PIN side by side, email allow-lists, per-app sessions, service tokens for CLIs.
  Works directly on `*.workers.dev` — no custom domain required.

## Quick start

```bash
# 1. Read the method skill first
cat skills/dashboard-forge/SKILL.md

# 2. Wall a set of sites (after forging the scoped token per the method):
node skills/cf-access-wall/scripts/gh-oauth-app.mjs --name my-app \
  --callback https://TEAM.cloudflareaccess.com/cdn-cgi/access/callback \
  --expect-account my-org --vault-scope my-project-access
node skills/cf-access-wall/scripts/setup-access.mjs path/to/access-spec.json
```

Requires: node, `playwright-core` (repo root), Chrome, the SCS `vault` CLI.

Provenance: generalized from the gh-fine-grained-pat harness (gh-tools) after the 2026-07-23
curve-dental run proved it vendor-agnostic. Reference decision record: that project's
security-and-compliance README §D10.
