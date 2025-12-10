# devops-tools

DevOps automation plugin for Claude Code: ClickHouse Cloud management, Doppler credentials, secret validation, Telegram bot management, MLflow queries, and session recovery.

## Skills

| Skill                           | Description                                                            |
| ------------------------------- | ---------------------------------------------------------------------- |
| **clickhouse-cloud-management** | ClickHouse Cloud user creation, permissions, and credential management |
| **clickhouse-pydantic-config**  | Generate DBeaver configurations from Pydantic ClickHouse models        |
| **doppler-workflows**           | PyPI publishing, AWS credential rotation, multi-service patterns       |
| **doppler-secret-validation**   | Add, validate, and test API tokens/credentials in Doppler              |
| **telegram-bot-management**     | Production bot management, monitoring, restart, and troubleshooting    |
| **mlflow-query**                | Query MLflow experiments, compare runs, analyze model metrics          |
| **session-recovery**            | Troubleshoot Claude Code session issues and HOME variable problems     |

## Installation

```bash
/plugin marketplace add terrylica/cc-skills
/plugin install devops-tools@cc-skills
```

## Usage

Skills are model-invoked — Claude automatically activates them based on context.

**Trigger phrases:**

- "create ClickHouse user", "ClickHouse permissions" → clickhouse-cloud-management
- "DBeaver config", "connection setup" → clickhouse-pydantic-config
- "publish to PyPI" → doppler-workflows
- "add to Doppler", "validate token" → doppler-secret-validation
- "telegram bot", "bot status", "restart bot" → telegram-bot-management
- "MLflow experiments", "compare runs" → mlflow-query
- "no conversations found to resume" → session-recovery

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

### MLflow Query

- List and search experiments
- Compare run metrics and parameters
- Security patterns for credential management

### Session Recovery

- HOME variable diagnosis
- Session file location troubleshooting
- IDE/terminal configuration checks

## Requirements

- Doppler CLI (`brew install dopplerhq/cli/doppler`)
- Claude Code CLI

## License

MIT
