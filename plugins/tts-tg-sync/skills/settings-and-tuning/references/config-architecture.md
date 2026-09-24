# Configuration Architecture Reference

How the tts-tg-sync bot gets its configuration, its secrets, its Bun runtime and its tasks. The bot is orchestrated by moon + proto + Bun; jdx/mise is retired and not used.

## Layout

```
~/.claude/automation/claude-telegram-sync/
├── .prototools            # proto pins: bun, moon
├── moon.yml               # project `env:` (all tunable config) + `tasks:`
├── .env                   # values the launchd service needs (gitignored; Bun auto-loads it)
├── telegram-bot-runner    # signed Swift runner exec'd by launchd
└── src/                   # TypeScript bot source
~/.claude/.secrets/ccterrybot-telegram   # secrets (dotenv format, mode 600)
```

## Where a value comes from depends on how the process was started

| Started by                                              | Tunable config                                                                             | Secrets                                                         |
| ------------------------------------------------------- | ------------------------------------------------------------------------------------------ | --------------------------------------------------------------- |
| `moon run telegram-sync:<task>`                         | `moon.yml` `env:` (applied to every task in the project)                                   | `.env` (tasks run from the bot directory, so Bun auto-loads it) |
| launchd service (`telegram-bot-runner`)                 | `.env` in the bot directory — the runner sets cwd there and Bun auto-loads `.env` from cwd | `.env` in the bot directory                                     |
| Claude Code hook (`src/hooks/auto-continue-wrapper.sh`) | self-contained defaults in the hook                                                        | `~/.claude/.secrets/ccterrybot-telegram`, sourced with `set -a` |
| ad-hoc `bun run src/main.ts` from the bot directory     | `.env` (Bun auto-load)                                                                     | `.env`                                                          |

The launchd runner sets only `HOME` and `PATH`. It execs a proto shim, and proto shims do not inject project env, so `moon.yml` `env:` does NOT reach the launchd service. A value that must change the running service goes in `.env`; keep `moon.yml` `env:` in step so `moon run` tasks agree. The bot's own `CLAUDE.md` ("Known gaps" #2) tracks this split and `src/config/secrets.ts` prints the same guidance when a required value is missing.

## Secrets

`~/.claude/.secrets/ccterrybot-telegram` holds the tokens (never committed); the hook wrapper sources it. The launchd service and `moon run` tasks read their copy from `.env`, so a rotated token must be updated in both files:

```
TELEGRAM_BOT_TOKEN=<telegram-bot-token>
TELEGRAM_CHAT_ID=<telegram-chat-id>
```

`SUB2API_API_KEY` (summarization) is also required at startup. Never put a secret in `moon.yml`.

## Tasks

Tasks live in `moon.yml` `tasks:` and run as `moon run telegram-sync:<task>`. Task ids use dashes, not colons, because moon's target syntax is `project:task`.

| Task            | Purpose                                                      |
| --------------- | ------------------------------------------------------------ |
| `start`         | `bun --watch run src/main.ts`                                |
| `stop`          | Kill the bot process                                         |
| `restart`       | Kill, then relaunch with `nohup bun --watch run src/main.ts` |
| `status`        | Show bot process status                                      |
| `logs-tail`     | Tail the NDJSON audit log                                    |
| `preflight-all` | typecheck + bot process + required env                       |
| `health-all`    | Kokoro, Telegram and `say` health checks                     |
| `check-all`     | typecheck + tests                                            |

Run `moon query tasks --project telegram-sync` (from the bot directory) for the full list.

## Bun runtime

Bun is pinned in the bot directory's `.prototools`. Install the pinned version with `proto install` from that directory; change the pin with `proto pin bun <version>`.

## Environment variable flow

```
moon.yml env:  ──►  moon run tasks
.env           ──►  launchd service, moon run tasks, ad-hoc bun run
.secrets file  ──►  hook wrapper
         │
         └── Environment variables
              ├── TypeScript bot (Bun.env.VAR)
              ├── Shell scripts (${VAR:-default})
              └── Python scripts (os.environ.get("VAR", "default"))
```

All components read the same variable names with fallback defaults.

## Editing guidelines

1. In `moon.yml` quote every value as a string: `TTS_SPEED: "1.20"`. `$HOME` is interpolated by moon.
2. Group related settings under comment headers (e.g. `# --- TTS voices ---`).
3. Never put secrets in `moon.yml`.
4. Restart the bot after changing a value; env is read at process start, not dynamically.
