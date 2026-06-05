# pushover-commander

End-to-end [Pushover](https://pushover.net) automation as Claude Code skills — the
one place for everything Pushover: sending, emergency alerts, **headless app/sound
management** (the only way to mint an app token, since Pushover has no app-creation
API), incident-report image rendering, and an auditable JSONL trail.

**Public + generic.** No account, item ID, or token lives in this repo. Per-user
secrets stay private under `~/.claude` and are read via env vars — so a fork user
wires their own 1Password item + Pushover account. See
[`skills/_lib/references/private-config-setup.md`](skills/_lib/references/private-config-setup.md).

## Skills

| Skill                               | What it does                                                                                                                                                                   |
| ----------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| **send-notification**               | Send a push (optionally with an image attachment) via the Bun/TS core. Preflighted + retried + audited.                                                                        |
| **emergency-priority2-receipt**     | Priority-2 alert that repeats until acknowledged, then polls the receipt.                                                                                                      |
| **manage-apps-and-sounds-headless** | Headless pushover.net dashboard control via Playwright: **log in, CREATE/DELETE apps (returns the new API token), add/remove custom sounds.** The thing the HTTP API can't do. |
| **custom-sounds**                   | Enumerate / validate / source + upload custom notification sounds.                                                                                                             |
| **render-incident-report-image**    | Render a monospace, iPhone-tuned incident-report PNG (Satori→SVG→resvg), word-wrapped, attachable to a notification.                                                           |
| **verbatim-audit-notify**           | Audit-grade sender: every alert carries a UUID; the full payload lands in a local JSONL keyed by it. `pushover-lookup <uuid>` round-trips it. Plus prune/quota/heartbeat.      |
| **loop-briefing**                   | Notify-on-block / notify-on-done briefings for `/loop` autonomous runs.                                                                                                        |
| **health-check**                    | `doctor` / `quota` — validate creds + remaining monthly quota.                                                                                                                 |

## Quick start

1. **Secrets** — copy the template + fill in YOUR values (never commit them):

   ```bash
   mkdir -p ~/.claude/pushover-commander.private
   cp "${CLAUDE_PLUGIN_ROOT}/skills/_lib/pushover-commander.local.env.example" \
      ~/.claude/pushover-commander.private/pushover-commander.local.env
   chmod 600 ~/.claude/pushover-commander.private/pushover-commander.local.env
   # edit it: set PUSHOVER_OP_VAULT + PUSHOVER_OP_ITEM (your 1Password item)
   ```

2. **TS core deps** (for send / render / emergency):

   ```bash
   cd "${CLAUDE_PLUGIN_ROOT}/skills/_lib" && bun install
   ```

3. **Send a test:**

   ```bash
   env -u HTTPS_PROXY -u HTTP_PROXY bun "${CLAUDE_PLUGIN_ROOT}/skills/_lib/pushover_core.ts" \
     send --message "hello from pushover-commander" --title test
   ```

## Why headless web-control exists

Pushover has **no API to create an application token** (verified — it's a
deliberate, website-only step). `manage-apps-and-sounds-headless` drives system
Chrome via Playwright to log in and create/delete apps + sounds, scraping the new
30-char token. pushover.net login is a plain email/password form with no
CAPTCHA/2FA, so plain Playwright suffices.

See [`CLAUDE.md`](CLAUDE.md) for the file map, the headless-login flow, and the
public/private secrets pattern.
