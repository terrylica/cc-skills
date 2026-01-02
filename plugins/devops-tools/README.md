# devops-tools

DevOps automation plugin for Claude Code: ClickHouse Cloud management, Doppler credentials, secret validation, Telegram bot management, MLflow queries, notifications, and session recovery.

Merged: `notification-tools` (dual-channel-watchexec) moved here.

> **Migration Notice**: asciinema skills have moved to the dedicated `asciinema-tools` plugin.

## Skills

| Skill                           | Description                                                            |
| ------------------------------- | ---------------------------------------------------------------------- |
| **clickhouse-cloud-management** | ClickHouse Cloud user creation, permissions, and credential management |
| **clickhouse-pydantic-config**  | Generate DBeaver configurations from Pydantic ClickHouse models        |
| **doppler-workflows**           | PyPI publishing, AWS credential rotation, multi-service patterns       |
| **doppler-secret-validation**   | Add, validate, and test API tokens/credentials in Doppler              |
| **telegram-bot-management**     | Production bot management, monitoring, restart, and troubleshooting    |
| **mlflow-python**               | Log backtest metrics, query experiments, QuantStats integration        |
| **session-recovery**            | Troubleshoot Claude Code session issues and HOME variable problems     |
| **session-chronicle**           | Session provenance tracking with S3 artifact sharing for team access   |
| **dual-channel-watchexec**      | Send notifications to Telegram + Pushover on process events            |

## Installation

```bash
/plugin marketplace add terrylica/cc-skills
/plugin install devops-tools@cc-skills
```

## Usage

Skills are model-invoked — Claude automatically activates them based on context.

**Trigger phrases:**

- "create ClickHouse user", "ClickHouse permissions" -> clickhouse-cloud-management
- "DBeaver config", "connection setup" -> clickhouse-pydantic-config
- "publish to PyPI" -> doppler-workflows
- "add to Doppler", "validate token" -> doppler-secret-validation
- "telegram bot", "bot status", "restart bot" -> telegram-bot-management
- "log backtest", "MLflow metrics", "search runs" -> mlflow-python
- "no conversations found to resume" -> session-recovery
- "who created this", "trace origin", "provenance" -> session-chronicle
- "watchexec notifications", "Telegram + Pushover" -> dual-channel-watchexec

## Key Features

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

### Session Chronicle

- Trace UUID chains across auto-compacted sessions
- Capture provenance for research findings and ADR decisions
- Brotli compression for efficient artifact storage
- S3 artifact sharing with 1Password credential injection
- Embedded retrieval commands in git commit messages
- [S3 Sharing ADR](/docs/adr/2026-01-02-session-chronicle-s3-sharing.md)

### Dual-Channel Watchexec

- Simultaneous Telegram + Pushover delivery
- HTML formatting for Telegram, plain text for Pushover
- Restart detection (startup, code change, crash)
- Message archiving for debugging

## Requirements

- Doppler CLI (`brew install dopplerhq/cli/doppler`)
- Brotli (`brew install brotli`) - for session-chronicle
- AWS CLI (`brew install awscli`) - for session-chronicle S3 upload
- 1Password CLI (`brew install 1password-cli`) - for session-chronicle credentials
- Claude Code CLI

## License

MIT
