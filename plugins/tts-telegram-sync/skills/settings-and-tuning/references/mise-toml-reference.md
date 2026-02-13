# mise.toml Architecture Reference

How the tts-telegram-sync bot uses mise.toml for configuration, secret loading, and task orchestration.

## Hub/Spoke Structure

```
~/.claude/automation/claude-telegram-sync/
├── mise.toml              # Hub: [tools] + [env] (SSoT for all config)
├── .mise.local.toml       # Secrets: _.file loads BOT_TOKEN/CHAT_ID (gitignored)
├── .mise/
│   └── tasks/
│       ├── bot.toml       # Spoke: bot lifecycle tasks (start, stop, restart, logs)
│       └── validate.toml  # Spoke: validation DAG tasks
└── src/                   # TypeScript bot source
```

### Hub: mise.toml

The root `mise.toml` owns two responsibilities:

1. **[tools]**: Runtime versions (Bun)
2. **[env]**: All configuration as environment variables

```toml
[tools]
bun = "1.3"

[env]
# All 30+ config values live here
TTS_VOICE_EN = "af_heart"
TTS_SPEED = "1.25"
# ... (see config-reference.md for full list)

[task_config]
includes = [".mise/tasks/bot.toml", ".mise/tasks/validate.toml"]
```

### Secrets: .mise.local.toml

Secrets are loaded from a separate file that is gitignored:

```toml
# .mise.local.toml (NEVER committed to git)
[env]
_.file = "{{env.HOME}}/.claude/.secrets/ccterrybot-telegram"
```

The secrets file contains:

```
BOT_TOKEN=<telegram-bot-token>
CHAT_ID=<telegram-chat-id>
```

### Why \_.file for Secrets

The `_.file` directive loads a dotenv-style file as environment variables. Benefits:

- Secrets stay in a single file at `~/.claude/.secrets/` (not in mise.toml)
- The `.mise.local.toml` is gitignored, so the `_.file` path itself is not committed
- Same pattern used across all projects with secrets

## Spoke: Task Files

Task files are included via `[task_config].includes` in the hub. They define bot lifecycle operations.

### bot.toml (Core Tasks)

Typical tasks:

| Task          | Purpose                                          |
| ------------- | ------------------------------------------------ |
| `bot:start`   | Start the bot with `bun --watch run src/main.ts` |
| `bot:stop`    | Stop the bot process                             |
| `bot:restart` | Stop then start                                  |
| `bot:logs`    | Tail bot log output                              |
| `bot:status`  | Show bot process status                          |

### validate.toml (Validation DAG)

Validation tasks for checking configuration and health. Tasks can depend on each other to form a validation DAG.

## Environment Variable Flow

```
mise.toml [env]          (default values, committed)
    │
    ├── .mise.local.toml (secrets via _.file, gitignored)
    │
    └── Environment Variables
         │
         ├── TypeScript bot (process.env.VAR)
         ├── Shell scripts (${VAR:-default})
         └── Python scripts (os.environ.get("VAR", "default"))
```

All components use the same environment variables with fallback defaults, so they work both with and without mise.

## Editing Guidelines

When editing `mise.toml`:

1. **All values are strings** in TOML (mise convention). Use quotes: `TTS_SPEED = "1.25"`
2. **Group related settings** with comment headers (e.g., `# --- TTS Voice Configuration ---`)
3. **Never put secrets** in `mise.toml`. Use `.mise.local.toml` with `_.file`
4. **Restart the bot** after changing values (mise loads env on process start, not dynamically)

## Template Syntax

mise uses Tera templates in TOML values:

```toml
[env]
# Reference HOME directory
KOKORO_VENV = "{{env.HOME}}/.local/share/kokoro/.venv"

# Reference config_root (directory containing mise.toml)
LOCAL_SCRIPTS = "{{config_root}}/scripts"
```

Common template variables:

| Variable          | Description                             |
| ----------------- | --------------------------------------- |
| `{{env.HOME}}`    | User home directory                     |
| `{{env.VAR}}`     | Any existing environment variable       |
| `{{config_root}}` | Directory containing the mise.toml file |
