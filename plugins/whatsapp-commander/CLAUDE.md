# whatsapp-commander — agent hub

Reach WhatsApp contacts from Claude Code. WhatsApp is the odd one out among the comms
plugins: **there is no sanctioned personal-account send API** (contrast `tlg` = MTProto
personal send, `gmail-commander` = OAuth API send). So this plugin is organized by
**capability tier**, defaulting to the safe one.

## Tiers

| Tier        | Method                                                        | Sends?                       | Creds                                                     |
| ----------- | ------------------------------------------------------------- | ---------------------------- | --------------------------------------------------------- |
| 1 (default) | `wa.me` click-to-chat link (text pre-filled, human taps Send) | no                           | none                                                      |
| 3           | WhatsApp Business Cloud API text send                         | yes (24h window / templates) | `WHATSAPP_TOKEN` + `WHATSAPP_PHONE_NUMBER_ID` (1Password) |

Tier 2 (WhatsApp Web browser automation) is intentionally **not built** — DOM-fragile and
ToS-gray. See [`skills/send-message/SKILL.md`](skills/send-message/SKILL.md) and
[`references/business-cloud-api.md`](references/business-cloud-api.md).

## CLI

`scripts/wa-cli.ts` — function/enum-driven **Bun TypeScript** (run directly, no build):

```bash
SCRIPT="${CLAUDE_PLUGIN_ROOT:-$HOME/.claude/plugins/marketplaces/cc-skills/plugins/whatsapp-commander}/scripts/wa-cli.ts"
bun "$SCRIPT" link "+1 604 816 8818" "message"   # Tier 1 → prints a wa.me URL
bun "$SCRIPT" send 16048168818 "message"          # Tier 3 → Cloud API (needs env creds)
```

`Command`/`ExitCode`/`EnvVar` are enums; commands dispatch through an enum-keyed
`Record<Command, Handler>` table — adding a command forces a handler.

## Conventions (shared with tlg / gmail-commander)

- **Credentials in 1Password** (`Claude Automation` vault), resolved into env at call time —
  never hardcoded.
- **CLI in a typed local language** (Bun/TS preferred over shell/Python) — function-driven,
  enum-driven over string literals.
- SKILL.md is **self-evolving**: fix it in place when reality drifts; keep the Evolution Log
  current.
