# pushover-commander — plugin SSoT

Hub: [`../CLAUDE.md`](../CLAUDE.md) · Siblings: [gmail-commander](../gmail-commander/CLAUDE.md) · [calcom-commander](../calcom-commander/CLAUDE.md) · [devops-tools](../devops-tools/CLAUDE.md)

The single home for all Pushover automation. Migrated + consolidated 2026-06-05
from the orphaned private `~/.claude/po-plugin` (`po` suite) **plus** the
`pushover-verbatim-notify` skill formerly in `devops-tools` — so any future
Claude Code session finds every Pushover capability in one registered place.

## Public-tool / private-config split (READ FIRST)

This plugin is **public + generic** — it contains NO account email, 1Password item
ID, app token, or operator-specific app→repo map. All per-user secrets/config live
**privately under `~/.claude`** and are read via env vars:

- Private config (gitignored, per-user): `~/.claude/pushover-commander.private/pushover-commander.local.env`
  (template: [`skills/_lib/pushover-commander.local.env.example`](skills/_lib/pushover-commander.local.env.example)).
- `skills/_lib/resolve_pushover_secret.sh` sources it, then reads
  `op://$PUSHOVER_OP_VAULT/$PUSHOVER_OP_ITEM/<field>` (1Password) with a macOS
  Keychain fallback. Fails loud if neither is configured.
- Fork users: copy the `.example`, point it at their own 1Password item — done.
- Full guide: [`skills/_lib/references/private-config-setup.md`](skills/_lib/references/private-config-setup.md).

## File map

| Path                                                                  | Role                                                                                             |
| --------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------ |
| `skills/send-notification/`                                           | quick send (+image) via the TS core                                                              |
| `skills/emergency-priority2-receipt/`                                 | priority-2 repeat-until-ack + receipt poll                                                       |
| `skills/manage-apps-and-sounds-headless/`                             | **headless pushover.net login + create/delete apps (mints token) + sounds**                      |
| `skills/custom-sounds/`                                               | enumerate/validate/upload custom sounds                                                          |
| `skills/render-incident-report-image/`                                | monospace incident-report PNG (word-wrapped)                                                     |
| `skills/verbatim-audit-notify/`                                       | UUID+JSONL audit sender + lookup/prune/quota/heartbeat (+ launchd templates)                     |
| `skills/loop-briefing/`                                               | `/loop` block/done briefings                                                                     |
| `skills/health-check/`                                                | doctor / quota                                                                                   |
| `skills/_lib/pushover_core.ts`                                        | Bun/TS core: send · emergency · sounds · render · loop-brief · doctor · quota (Satori→resvg PNG) |
| `skills/_lib/pushover_headless_web_control.ts`                        | Playwright (Bun/TS) headless dashboard: `apps/create-app/delete-app/edit-app/sounds`             |
| `skills/_lib/resolve_pushover_secret.sh`                              | env/1Password/Keychain credential resolver (generic)                                             |
| `skills/_lib/batch_create_pushover_apps.ts`                           | batch create apps from a plan JSON (reuses web-control helpers)                                  |
| `skills/_lib/{make_app_icon.py,make_custom_sound.sh,find_jingles.sh}` | icon/sound sourcing pipeline                                                                     |
| `skills/_lib/pushover_api_limits.json`                                | SSoT for Pushover caps + silent-failure rules                                                    |
| `skills/_lib/references/`                                             | app-naming scheme (generic template), device calibration + API limits, private-config setup      |

## The headless app-creation flow (why it exists)

Pushover has **no API to create an application token** — it is a deliberate,
website-only action. To mint one programmatically:

```bash
# creds come from your private config via resolve_pushover_secret.sh
export PO_EMAIL="$(bash skills/_lib/resolve_pushover_secret.sh login_email)"
export PO_PW="$(bash skills/_lib/resolve_pushover_secret.sh login_password)"
export PO_USER="$(bash skills/_lib/resolve_pushover_secret.sh user_key)"
env -u HTTPS_PROXY -u HTTP_PROXY \
  bun skills/_lib/pushover_headless_web_control.ts create-app --name "my-app" --reveal
```

Drives system Chrome via Playwright; pushover.net login is plain email/password
(no CAPTCHA/2FA, verified 2026-05-30), so plain Playwright + selectors suffice.

## Conventions

- All Pushover HTTPS + `op` calls run with `env -u HTTPS_PROXY -u HTTP_PROXY` (the
  sandbox MITM proxy 502s on api.pushover.net / 1Password).
- The TS core (`pushover_core.ts`) needs `bun install` in `skills/_lib/` (Satori,
  @resvg/resvg-js, Playwright). `node_modules/` is gitignored.
- State (audit JSONL) defaults to `~/.local/state/pushover/` (env `PUSHOVER_AUDIT_PATH`).
- Never hardcode tokens; never commit the private config or the app-token cache.
