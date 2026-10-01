# Gmail Commander

Gmail CLI, canonical draft builder and shared Telegram bot code for Claude Code.

## Features

- **Gmail CLI**: Full email access (list, search, read, export, draft) via 1Password OAuth
- **Draft builder**: `scripts/gmail-draft.ts`, the only sanctioned way to create or replace a Gmail draft (wrap-immune `multipart/alternative`)
- **Sender Alignment**: Auto-detect reply sender, confirm for new emails
- **Telegram bot code**: `buildBot()` in `scripts/bot.ts` wires 10 slash commands, inline keyboards, a compose/reply flow and AI free-text routing (Agent SDK), with no transport attached
- **On-demand triage**: the bot's `/digest [hours]` sorts recent mail into System/Work/Personal by urgency

## Deployment model

The bot and a scheduled digest run unattended in a private Restate deployment on an always-on Mac mini, which imports `buildBot()` and ships the Gmail CLI binary built from this plugin. Nothing in this plugin runs as a background job on a workstation; the former launchd bot and digest jobs were retired on 2026-09-24, and the plugin's digest entry point and Kokoro voice briefing were removed on 2026-09-26. See [CLAUDE.md](./CLAUDE.md#where-things-run) for the contract the deployment depends on.

## Quick Start

```bash
# Install plugin
claude plugin marketplace add terrylica/cc-skills

# Set up Gmail CLI access (in Claude Code)
/gmail-commander:setup
```

## Skills

| Skill                 | Purpose                                                          |
| --------------------- | ---------------------------------------------------------------- |
| `gmail-access`        | Gmail CLI access with 1Password OAuth                            |
| `setup`               | OAuth credentials, CLI build from its lockfile, access check     |
| `health`              | Local CLI, token cache, `buildBot()` contract, retired-job check |
| `email-triage`        | Triage prompt and parser behind the bot's `/digest` command      |
| `interactive-bot`     | Telegram bot commands, safety controls and source map            |
| `bot-process-control` | Where the bot and digest run, and what never to start locally    |

## License

Private plugin.
