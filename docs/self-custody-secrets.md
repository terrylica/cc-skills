# Self-Custody Secrets (SCS)

> Credential doctrine for keeping secrets in stores **the operator controls** — never an employer/company-managed vault. Glossary term: **Self-Custody Secrets (SCS)**. This document is public and **agnostic**: it uses placeholders only; real vault names, item IDs, usernames, hosts, and client identifiers live in a **local, git-ignored** credential registry on the operator's machine.

## Why

A company-provided password manager (e.g. 1Password Business/Teams) is convenient but **not private from the employer**: shared vaults are visible to teammates, and even an "Employee/Private" vault is recoverable by account admins and exposes item counts in reports. Anything confidential to a _client_ or contracting relationship therefore must not live there. SCS moves those secrets to stores you alone hold.

## The SCS ladder (prefer top-down)

1. **macOS login Keychain — machine SSoT, in TWO tiers.**

   - **Automation tier (agent-readable).** Items stored with `-T /usr/bin/security` are readable by any process running as you — **including an AI coding agent** (`security find-generic-password -w` returns them with **no prompt**; empirically verified in-session). Use this tier ONLY for narrow, low-blast-radius automation tokens (e.g. a scoped release PAT):

     ```bash security add-generic-password -U -s <scope>-<service> -a <user> -w <secret> \
       -T /usr/bin/security -j "<description + url>" "$HOME/Library/Keychains/login.keychain-db"
     security find-generic-password -s <scope>-<service> -w   # no prompt, scriptable
     ```

   - **Crown-jewel tier (crown-strict scopes).** Master/private/age/signing keys and client-confidential secrets must require a live biometric so a headless agent cannot read them. Put them in a vault scope whose name the vault's `# tier: crown-strict` rule matches: it is encrypted ONLY to the owner's Secure Enclave key (Touch ID enforced by the chip) and an offline recovery key, and `vault` never mirrors it into the plain Keychain:

     ```bash
     vault new-scope <name> "why"          # crown-strict recipients from .sops.yaml
     vault set --stdin <name> <dot.path>   # value on stdin (one Touch ID)
     vault get <name> <dot.path>           # prompts Touch ID, explaining who asks
     ```

     > **Security finding (2026-06-26):** the agent CAN silently read plain `-T /usr/bin/security` items — proven this session. _Cryptographic_ item-level gating via the Keychain (`kSecAccessControl`) needs a paid Apple Developer ID, but **Secure Enclave keys through CryptoKit do not** (corrected 2026-10-04): `age-plugin-se` keeps the enclave-wrapped key in a plain file, so an ad-hoc build works as a sops recipient. The earlier app-level Touch-ID helper was retired the same day — re-signing a look-alike with its self-signed identity ran silently, so it could be impersonated; the enclave cannot.

2. **SOPS + age — versioned backup in the project repo.** Values encrypted, keys readable (the repo self-documents structure). The age private key lives in the Keychain, sourced at decrypt time:

   ```bash
   export SOPS_AGE_KEY_CMD='security find-generic-password -s <age-key-item> -w'
   sops <repo>/secrets/<scope>.sops.json     # edit decrypted; re-encrypts on save
   ```

3. **iCloud — personal off-device backup.** iCloud Drive for _files_ (e.g. the age key), the Passwords app for _logins_.

   > **Gotcha:** items created by `security` land in the **local `login`** keychain, which does **not** sync to iCloud and does **not** appear in the Passwords app. Back the age key up to iCloud Drive (or Passwords) **separately**.

4. **Provenance — a restore runbook + checksum manifest** committed beside the encrypted backup, so a future agent or a fresh machine can recover deterministically (which key, which repo/commit, which Keychain items).

## Runtime injection (use secrets without writing plaintext)

`vault run <scope> -- <cmd>` decrypts a scope **in memory** and injects its secrets as env vars into `<cmd>` — nothing touches disk. A crown-strict scope costs one Touch ID per run. For per-repo committed-and-encrypted env files, **dotenvx** (`dotenvx run -- <cmd>`) is the alternative last-mile injector; keep its private key in a crown-strict scope, never in a plaintext `.env.keys`.

## Naming convention (for AI-agent self-discovery)

- Keychain service id: **`<scope>-<service>`** — e.g. a project/client prefix plus the system. Account (`-a`) = the username; comment (`-j`) = human description + URL.
- SOPS file: `secrets/<scope>.sops.json`; age key item: `<scope>-age-key` (or shared).
- Keep an **agnostic registry/runbook** in the repo describing the convention and what _categories_ of items exist — never the secret values, and in public repos never the real ids/hosts (point to the local registry instead).

## 1Password is LAST RESORT

Use the company vault **only** for company-shared, non-confidential secrets, and ask first whether the secret could live on the SCS ladder instead. When `op` is genuinely required: `unset HTTPS_PROXY HTTP_PROXY` (the OAuth proxy 502s on `api.1password.com`), prefer a service-account token for scriptable R/W, and resolve concrete ids from the **local** registry.

## Signing an agent into a web app from a vault item (verified 2026-11-12)

The operator may ask an agent to sign their own browser profile into an invite-only, password-login web app (an internal dashboard) using a login item from a vault. The password must reach the page without ever appearing in a transcript, a tool result, a log or a file that outlives the run. This recipe worked end to end on two such apps (a dev and a prod deployment of one dashboard), driving the operator's signed-in Chrome profile through the chrome-profiles plugin's `mcp-drive.ts ext <account-email> steps.json` (Playwright Extension, no Allow dialog). It works from a Linux host too, by running every step over SSH on the Mac that owns the browser and the vault app.

1. **Check for a live session first.** Navigate to the target page and snapshot. If the app shows its signed-in shell, no secret is needed at all. A redirect to `/auth/login?expired=1` means the stored token expired.
2. **Read only the metadata.** On the Mac, `op item get <id> --vault <v> --account <acct> --format json | jq '{title, urls: [.urls[]?.href], username: …, field_labels: [.fields[]?.label]}'`, so the filter runs before anything leaves the machine. This shows which item is which environment, e.g. two items with the same title whose URLs differ (prod vs dev). `op` biometric unlock works over SSH when the desktop app is unlocked; the Touch ID prompt, if any, appears on the Mac's screen.
3. **Build the steps file on the Mac, under `umask 077`, removed by `trap … EXIT`.** Pipe `op … --fields label=password --reveal` straight into `jq -R` and embed it with `tojson` (correct escaping for JSON and JS). The secret never transits the agent's host.
4. **Fill without focusing.** Typing into the field (`browser_type`, `locator.fill`) was intermittently fatal: right after the email field took focus, the tab's automation died with `Target page, context or browser has been closed`, on both apps, about half the time. The likely cause is the password manager's extension injecting its inline autofill frame, which detaches the debugger session. What worked every time: one `browser_run_code_unsafe` step whose `page.evaluate` sets both inputs through the native setter (`Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, "value").set.call(el, v)`), dispatches `input` and `change` (bubbling, so React-controlled forms see it), then calls `form.requestSubmit()`. No element ever takes focus.
5. **Never let a step print the secret.** Playwright MCP echoes the code it ran (`### Ran Playwright code`), so any step containing the password prints it. Two safe ways out, used together:
   - Pipe the whole `mcp-drive` output through a redaction filter **on the Mac**, before it reaches the agent: `perl -pe 'BEGIN{$p=$ENV{PW}; ($j=$p)=~s/([\\"])/\\$1/g; ($q=$p)=~s/([\\\x27])/\\$1/g} s/\Q$j\E/***/g; s/\Q$q\E/***/g; s/\Q$p\E/***/g'` (plain, JSON-escaped and JS-escaped forms).
   - Make the secret-bearing step return a short, fixed-length, character-whitelisted diagnostic (`url=… alerts=…`, padded to 200 chars, the password split out of it) and set the step's `max` so printing stops before the echoed code. Prove the cut with a fake sentinel password first (`grep -c SENTINEL` must be 0).
   - `quiet: true` also suppresses the text, but then a failure is opaque. Reading a diagnostic back from `localStorage` in the next step does not work: that step may land on `about:blank`.
6. **One run per sign-in.** In `ext` mode every run attaches to a fresh tab, but cookies and `localStorage` persist in the profile, so later runs are already signed in. Element refs change after any input (`Ref … not found in the current page snapshot`), and current Playwright MCP names the field `target`, not `ref`.
7. **Read data through the app's own API, inside the page.** Once signed in, a `browser_evaluate` that reads the bearer token from the app's persisted store (e.g. `localStorage['<auth-store-key>']`) and `fetch`es the same-origin `/api/...` endpoints returns exact JSON. The token stays in the page and is never returned. This beats scraping the rendered screen.

Over SSH, `mcp-drive`'s leftover-tab sweep refuses to run (AppleScript would prompt on the Mac's screen). That is expected; the run still closes its own tab.

## Enforcement

Two `devops-tools` hooks nudge toward this doctrine:

- `userpromptsubmit-1password-context-injection.sh` — injects the SCS ladder when a prompt mentions credentials/keychain/sops/age/1Password.
- `posttooluse-1password-pattern-reminder.sh` — after an `op` command, reminds that 1Password is last-resort and points back to the SCS ladder.
- `posttooluse-crown-jewel-plain-keychain-nudge.sh` — after a `security add-generic-password … -T /usr/bin/security` for a crown-jewel-looking item (master/private/age/signing key), nudges toward a crown-strict vault scope. Escape hatch for a deliberately-plain narrow token: `CROWN-JEWEL-PLAIN-OK`.

Both are agnostic; broaden/adjust triggers there, keep secrets out of this repo.
