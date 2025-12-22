# devops-tools

DevOps automation plugin for Claude Code: asciinema player and recorder, ClickHouse Cloud management, Doppler credentials, secret validation, Telegram bot management, MLflow queries, and session recovery.

## Skills

| Skill                           | Description                                                            |
| ------------------------------- | ---------------------------------------------------------------------- |
| **asciinema-player**            | Play .cast terminal recordings in iTerm2 with CLI controls             |
| **asciinema-recorder**          | Record Claude Code sessions with dynamic workspace-based filenames     |
| **asciinema-streaming-backup**  | Real-time recording backup to GitHub with idle-chunking and brotli     |
| **clickhouse-cloud-management** | ClickHouse Cloud user creation, permissions, and credential management |
| **clickhouse-pydantic-config**  | Generate DBeaver configurations from Pydantic ClickHouse models        |
| **doppler-workflows**           | PyPI publishing, AWS credential rotation, multi-service patterns       |
| **doppler-secret-validation**   | Add, validate, and test API tokens/credentials in Doppler              |
| **telegram-bot-management**     | Production bot management, monitoring, restart, and troubleshooting    |
| **mlflow-python**               | Log backtest metrics, query experiments, QuantStats integration        |
| **session-recovery**            | Troubleshoot Claude Code session issues and HOME variable problems     |

## Installation

```bash
/plugin marketplace add terrylica/cc-skills
/plugin install devops-tools@cc-skills
```

## Usage

Skills are model-invoked — Claude automatically activates them based on context.

**Trigger phrases:**

- "asciinema", ".cast file", "play recording", "terminal recording" → asciinema-player
- "record session", "asciinema record", "capture terminal", "demo recording", "record ASCII", "ASCII terminal", "terminal screen capture", "shell screen capture", "ASCII screen capture", "screen recording" → asciinema-recorder
- "streaming backup", "recording backup", "asciinema backup", "continuous recording", "session backup", "orphan branch recording", "zstd streaming", "chunked recording", "real-time backup", "github recording storage" → asciinema-streaming-backup
- "create ClickHouse user", "ClickHouse permissions" → clickhouse-cloud-management
- "DBeaver config", "connection setup" → clickhouse-pydantic-config
- "publish to PyPI" → doppler-workflows
- "add to Doppler", "validate token" → doppler-secret-validation
- "telegram bot", "bot status", "restart bot" → telegram-bot-management
- "log backtest", "MLflow metrics", "search runs" → mlflow-python
- "no conversations found to resume" → session-recovery

## Key Features

### asciinema Player

- Play .cast terminal recordings in iTerm2 (handles large files >100MB)
- Full playback controls: speed (2x, 6x, 16x), pause, step
- Spawns clean iTerm2 window via AppleScript
- Interactive speed and options selection

### asciinema Recorder

- Record Claude Code sessions with asciinema
- Dynamic filename generation (workspace + datetime)
- Saves to workspace tmp/ folder (gitignored)
- Step-by-step guidance for recording workflow

### asciinema Streaming Backup

- Real-time backup to GitHub orphan branch (isolated history)
- Idle-detection chunking (chunks during 30s+ inactivity)
- zstd streaming compression (concatenatable frames)
- GitHub Actions auto-recompression to brotli (~300x compression)
- Self-correcting validation with auto-fix
- Complete setup scripts and workflow templates

### ClickHouse Cloud Management

- Create and manage database users via SQL over HTTP
- Permission grants (GRANT/REVOKE) for fine-grained access control
- Credential retrieval from 1Password Engineering vault
- Connection testing and troubleshooting

### ClickHouse Pydantic Config

- Generate DBeaver connection configurations from Pydantic v2 models
- mise `[env]` as Single Source of Truth (SSoT)
- Support for local and cloud connection modes
- Semi-prescriptive patterns adaptable to each repository

### Doppler Workflows

- PyPI token management with project-scoped tokens
- AWS credential rotation with zero-exposure workflow
- Multi-token/multi-account patterns

### Doppler Secret Validation

- Validate token format before storage
- Test secret retrieval and environment injection
- API authentication testing with bundled scripts

### Telegram Bot Management

- Bot status, restart, and log monitoring
- Launchd service management
- Troubleshooting connectivity and state issues

### MLflow Python

- Log backtest metrics using QuantStats (70+ trading metrics)
- Query experiments and runs with DataFrame output
- Create experiments and retrieve metric history
- Idiomatic authentication with mise `[env]` pattern

### Session Recovery

- HOME variable diagnosis
- Session file location troubleshooting
- IDE/terminal configuration checks

## Requirements

- Doppler CLI (`brew install dopplerhq/cli/doppler`)
- Claude Code CLI

## License

MIT
