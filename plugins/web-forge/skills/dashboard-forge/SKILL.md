---
name: dashboard-forge
description: >
  Supervised browser automation of vendor dashboards for operations that have NO public API —
  minting scoped API tokens, creating OAuth apps, flipping account-level toggles. Drives a real
  Chrome over CDP with a persistent per-site profile (human logs in once, supervised; scripts do
  the rest), extracts secrets DOM-to-vault without ever exposing them, and survives UI drift via
  the step-and-shoot method. Use when a task needs a dashboard click-path (Cloudflare token/Zero
  Trust, GitHub OAuth apps, any admin console) and the vendor offers no API or your token lacks
  the scope to grant itself more. Triggers: "no API for this", "create an OAuth app", "mint a
  token in the dashboard", "automate the admin console", "browser-automate the setup".
allowed-tools: Read, Bash, Grep, Glob
---

# dashboard-forge — supervised dashboard automation doctrine

Some operations exist ONLY behind a vendor's web UI (GitHub fine-grained PATs and OAuth apps have
no creation API; a Cloudflare token cannot grant itself new scopes). This skill is the canonical
method for automating those click-paths safely: the human supervises and handles logins/2FA; the
scripts do everything else, reproducibly.

**Harness (SSoT):** [`../../lib/browser-forge.mjs`](../../lib/browser-forge.mjs) — per-site
persistent Chrome profiles + CDP attach + login-wait + identity preflight + consent dismissal +
vault sinks. node ONLY (Bun's `connectOverCDP` times out). Requires `playwright-core` (pinned at
the repo root) and Chrome at the standard macOS path.

> **Self-Evolving Skill**: dashboards drift constantly. When a selector misses or a flow changes,
> fix the forge script AND append the drift note to the Vendor Quirks section below — immediately,
> not later. Only update for real, reproducible breakage.

## The method — step-and-shoot

Write the forge as small, resumable steps against a LONG-LIVED Chrome (launch once; each step
connects, acts, disconnects — `browser.close()` on a CDP connection only detaches, Chrome keeps
running). Never author one monolithic script against an unseen UI.

1. **Launch + human login.** `launchChrome(site, loginUrl)`; the human signs in (incl. 2FA).
   Detect completion with `waitForLogin(ctx, probeUrl, ok)` — poll an authenticated endpoint via
   `ctx.request` with the context cookies. NEVER navigate a visible tab to poll: you would reload
   a half-typed login form.
2. **Identity preflight.** Before ANY mutating step, extract the signed-in identity (a meta tag,
   a settings-page marker, an API echo) and `assertIdentity(actual, expected, resource)`. An
   account-owned resource created under the wrong login is a silent disaster (it happened:
   an OAuth app landed under the wrong GitHub user mid-forge because the human switched accounts).
3. **Act in small steps, screenshot between.** One interaction cluster per step; `shot(page, name)`
   after each. When a locator misses, READ the latest shot, adapt, re-run just that step. Prefer
   role/label-based locators (`getByRole`, description-text anchoring) over CSS classes; for
   checkbox grids, `page.evaluate` walking from a UNIQUE description text up to its row is far
   more drift-proof than nth-child chains.
4. **Expect interceptors.** Cookie/consent overlays (OneTrust & co.) swallow clicks and produce
   pure timeouts with no visible cause — call `dismissConsent(page)` when a click times out
   mysteriously, then retry. GitHub-style sudo/2FA walls mid-flow: pause and let the supervising
   human clear them (or see gh-fine-grained-pat's `autosudo.mjs` for the autonomous passkey path).
5. **Extract secrets DOM-only.** On a token/secret reveal page: `page.evaluate` → match the value
   → `vaultSet(scope, path, value)`. **NEVER screenshot a reveal page** — an agent reading that
   screenshot puts the secret into the conversation context permanently. If a reveal was
   accidentally captured, purge the file AND treat the secret as context-exposed (rotate if the
   transcript leaves the machine).
6. **End-of-run hygiene.** `purgeShots()` (breadcrumbs can show near-secret state), then
   `teardown(site)` — kills the SPECIFIC pid on the CDP port, never `pkill -f` (process-storm
   policy, `~/.claude/CLAUDE.md`).

## Hybrid rule — forge the key, then use the door

Browser-automate the MINIMUM: usually just (a) the login and (b) the one form that mints a
scoped credential. Everything after that goes through the vendor's REAL API with the minted
credential, written as an **idempotent GET-before-POST bootstrap** (see the cf-access-wall skill
for the worked template). UI automation is the crowbar, not the workflow.

## Secrets discipline (non-negotiable)

- Values ride PIPES: `vault set --stdin <scope> <path>` (SCS vault). Never argv, never stdout,
  never a chat transcript.
- Scripts print LENGTHS and vault paths, not values (`✓ vaulted (len 53)`).
- Profile dirs (`~/.local/share/web-forge/profile-<site>`) hold live sessions — sensitive, never
  committed, listed in backups as credential-equivalent.
- Public identifiers (OAuth client_id, account ids) may be logged; anything CONCEALED may not.

## Vendor quirks (drift log — append, with dates)

- **Cloudflare 2026-07 token UI**: the old template-picker → 3-combobox flow is GONE. "Create
  Token" lands directly on a categorized checkbox form ("Cloudflare One / Zero Trust" section →
  per-group Read/Revoke/Edit boxes); submit is **"Review token"** → "Create token" → modal reveal.
  Tokens are `cfat_…` (53 chars), not the old 40-char format.
- **Cloudflare account-owned tokens** (2026-07-23): `/user/tokens/verify` ALWAYS rejects them
  ("Invalid API Token"); verify with `/accounts/{id}/tokens/verify`. Don't misdiagnose a working
  token as dead.
- **Cloudflare dashboard consent** (2026-07-23): OneTrust overlay appears minutes into a session
  and intercepts pointer events page-wide.
- **GitHub OAuth apps** (2026-07-23): no creation API (same as fine-grained PATs). Form fields:
  `oauth_application[name|url|callback_url]`. "Generate a new client secret" triggers sudo mode;
  a FRESH login usually has a sudo grace window — create the app right after login and the secret
  generation is prompt-free. Client secrets render as a 40-hex blob.
- **Azure Portal — ambiguous accessible names** (2026-08-02): every blade's close button is labelled
  `"Close content '<Blade Title>'"`, so on "Register an application" a fuzzy
  `getByRole("button", {name:/register/i}).first()` matches the CLOSE button, not the submit. It
  clicks, Playwright reports success, the blade shuts and nothing is created. Cost two runs, and the
  second created a DUPLICATE once the truth surfaced. Use `clickExact()` — it refuses on a non-exact
  name and prints the candidate list (verified live: `["Close content 'Register an application'","Register"]`).
- **Azure Portal — two elements match `input[placeholder*="Search"]`** (2026-08-02): the page-wide
  search in the masthead matches BEFORE any blade's own filter. Typing the role name into it left the
  role grid unfiltered, so an exact row lookup found 0 rows and the wizard advanced with no role
  selected. Anchor on the distinctive placeholder (`"Search by role name, description, permission, or ID"`).
- **Azure Portal — a list view can lie about creation** (2026-08-02): after successfully creating an
  app registration as a GUEST (`#EXT#`) user, **App registrations → Owned applications** said "This
  account isn't listed as an owner of any applications in this directory." True (a guest creator is not
  auto-assigned owner) and deeply misleading. Ground truth is the **notifications pane** ("Successfully
  created application X") or the **All applications** tab. Never confirm a mutation from the same
  console's default list view.
- **Azure Portal — tokens are in memory, not localStorage** (2026-08-02): an MSAL SPA of this
  generation keeps ARM/Graph access tokens in memory; a localStorage sweep returns nothing. Capture
  them off the wire with `captureBearer(page, "management.azure.com" | "graph.microsoft.com")`. With an
  ARM token the whole 3-tab role-assignment wizard collapses into one idempotent `PUT` (HTTP 201 first
  try) — the clearest instance of the Hybrid rule in this log.
- **Azure Portal — a cached blade issues no request** (2026-08-02): navigating to a view the SPA has
  already hydrated produces zero traffic, so token capture silently yields `null`, which reads exactly
  like "no permission". `captureBearer` retries with a `reload()` for this reason. The
  App-registrations LIST blade reliably re-queries Graph; the Entra Overview blade often does not.
- **Azure — the Portal and the CLI are DIFFERENT Entra apps** (2026-08-02): portal
  `c44b4083-3bb0-49c1-b47d-974e53cbdf3c`, CLI `04b07795-8ddb-461a-bbee-02f9e1bf7b46`. A Conditional
  Access policy scoped to the CLI (`AADSTS530035`, "Device state: Unregistered") therefore does **not**
  block the portal. This asymmetry is what makes a browser forge the only way in — and note that
  `az account list` then returns `[]`, which is a consequence of the block and **not** evidence that no
  subscription exists.
- **Tailscale — console moved and OAuth clients were renamed** (2026-08-05): `login.tailscale.com`
  redirects to **`console.tailscale.com`**, and `/admin/settings/oauth` redirects to
  **`/admin/settings/trust-credentials`** ("OAuth clients" is now "Trust credentials", created via a
  button labelled just **`Credential`**). Auth keys stayed at `/admin/settings/keys`.
- **Tailscale — Radix checkboxes: the `<input>` is a decoy** (2026-08-05): every scope checkbox
  renders a real `<input type=checkbox>` that is `aria-hidden`, `opacity:0`, **`pointer-events:none`**,
  next to a `<button role="checkbox" data-state="checked|unchecked">` that holds the actual state.
  Clicking the input — even with `{force:true}` — reports success and changes NOTHING; it cost a run
  that looked like it selected six scopes and submitted an empty form. Click
  `button[role=checkbox][id="<scope>"]` and assert via `data-state`. Bonus: **the button ids ARE the
  API scope names** (`auth_keys` = write, `auth_keys:read` = read, `devices:core`, `policy_file`),
  which is the most drift-proof selector on the page — better than the row-title walk.
- **Tailscale — a 50-char cap silently disables the wizard** (2026-08-05): the OAuth/credential
  description is labelled "(optional)" but capped at 50 characters, and exceeding it leaves
  **`Continue` disabled with no inline error** near the button. Symptom is a permanently disabled
  submit; the rule is only visible in body text ("Descriptions can be a maximum of 50 characters").
  When a submit stays disabled, dump the form's body text before suspecting the click.
- **Tailscale — write scopes are gated on tags, so OAuth clients need an ACL change first**
  (2026-08-05): selecting ANY write scope surfaces "Tags (required for write scope)", and tags only
  exist if the tailnet policy file declares them. So an OAuth client (the durable, non-expiring
  credential) cannot be minted in one pass on a tailnet with no tags — it needs a policy-file edit,
  which is a security change the operator should approve. A plain **user-owned auth key** from
  `/admin/settings/keys` has no tag requirement and is the right unblock when the goal is just
  joining one device.
- **Seeding a forge profile from the operator's real Chrome** (2026-08-05): when the per-site profile
  has no session and an interactive login would be the only manual step, copy `Local State` +
  `Default/Cookies` (+ `Default/Network/Cookies` if present) from
  `~/Library/Application Support/Google/Chrome` into a throwaway dir and point
  `WEB_FORGE_PROFILE_DIR` at it. Cookies decrypt because the macOS Keychain key is per-user, not
  per-profile, and no Keychain prompt appears (same Chrome binary). The operator's running Chrome is
  untouched — different `--user-data-dir`. **Delete the seeded dir afterwards**: it holds a copy of
  live session cookies and is credential-equivalent.

## Relationship to gh-fine-grained-pat

The PAT skill (gh-tools) is the origin of this harness and keeps its own battle-tested copy +
GitHub-specific machinery (autosudo/webauthn/multi-account). NEW forges build on web-forge's
`lib/browser-forge.mjs`; the PAT skill migrates here only in a deliberate, tested pass — never
casually (anti-fragility: don't destabilize a working credential forge for DRY points).

## Reference implementation

`~/work/project-a/scripts/access-bootstrap/` — the 2026-07-23 run that canonicalized this
skill: Cloudflare scoped-token forge + GitHub OAuth-app forge + idempotent Access bootstrap,
end-to-end in one supervised session (decision record: that repo's compliance README §D10).

## Post-Execution Reflection

After this skill completes, check before closing:

1. **Did the dashboard automation succeed?** — If selectors failed or the flow changed, update the forge script and add a drift note to the Vendor Quirks section.
2. **Were secrets stored safely?** — Verify no secrets appear in screenshots, argv, or stdout—only in the SCS vault.
3. **Did the supervised step succeed?** — If the human had to intervene (2FA, sudo, account switch), document the new quirk for future runs.
