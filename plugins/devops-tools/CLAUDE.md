# devops-tools Plugin

> DevOps automation: ClickHouse, Doppler, MLflow, Cloudflare Workers, pueue, secrets management, self-hosted services.

**Hub**: [Root CLAUDE.md](../../CLAUDE.md) | **Sibling**: [itp-hooks CLAUDE.md](../itp-hooks/CLAUDE.md)

## Secrets Management

| Type       | Location  | Access                                                      |
| ---------- | --------- | ----------------------------------------------------------- |
| API tokens | Doppler   | `doppler secrets get SECRET --project X --config Y --plain` |
| SaaS creds | 1Password | `op item get "Item" --vault Engineering --reveal`           |

**1Password Service Account (biometric-free access)**:

| What          | Location                                                  |
| ------------- | --------------------------------------------------------- |
| Token cache   | `~/.claude/.secrets/op-service-account-token` (chmod 600) |
| Vault access  | **Claude Automation** vault only (read + write)           |
| Token 1P item | Employee vault, ID `xtzirdfnngcgbir7wy4ohfu7i4`           |

**Usage** (headless/automation — no biometric prompt):

```bash
OP_SERVICE_ACCOUNT_TOKEN="$(cat ~/.claude/.secrets/op-service-account-token)" op item get "Item" --vault "Claude Automation" --reveal
```

**Usage** (interactive — biometric OK):

```bash
op item get "Item" --vault "Claude Automation" --reveal
```

**Per-project refs**: Each repo's `.mise.local.toml` stores `op://Claude Automation/...` reference paths (never raw secrets). Resolve with `op read "op://Claude Automation/ITEM_ID/field"`.

**1Password vault-first rule**: When looking for API credentials, check the **Claude Automation** vault first — most project credentials (Cal.com, Supabase, Telegram, AWS, Lark CalDAV, GitHub PATs) are stored there. A PreToolUse hook auto-injects the service account token for `op` commands targeting this vault (no biometric prompt). Always use `--vault "Claude Automation"` when accessing these credentials.

**Skills**: `Skill(devops-tools:doppler-secret-validation)` | `Skill(itp:pypi-doppler)`

## Self-Hosted Services

| Service    | Host        | Port | Skill                                             |
| ---------- | ----------- | ---- | ------------------------------------------------- |
| Firecrawl  | littleblack | 3003 | `Skill(devops-tools:firecrawl-research-patterns)` |
| ClickHouse | bigblack    | 8123 | `Skill(devops-tools:clickhouse-cloud-management)` |

**Firecrawl**: Web scraping for JS-heavy pages (Gemini/ChatGPT shares). Use `curl` not `WebFetch` (ZeroTier only).

```bash
curl "http://172.25.236.1:3003/scrape?url=URL&name=NAME"
```

**ClickHouse (bigblack)**: Range bar data with 47 microstructure features (260M+ bars). Used by `rangebar-py` package. ClickHouse listens on localhost only — access via SSH tunnel (rangebar preflight handles automatically).

```bash
# Env vars (set in .mise.local.toml per-project, gitignored):
RANGEBAR_CH_HOSTS=bigblack    # SSH alias, NOT raw IP (tunnel required)
RANGEBAR_MODE=remote          # Skip local ClickHouse check

# Test connectivity:
ssh bigblack "curl -s 'http://localhost:8123/?query=SELECT+1'"
```

**Reference**: [ZeroTier Network](/docs/infrastructure/zerotier-network.md)

## Skills

| Skill                           | Purpose                                                                                                      |
| ------------------------------- | ------------------------------------------------------------------------------------------------------------ |
| `clickhouse-cloud-management`   | ClickHouse schema management and query optimization                                                          |
| `clickhouse-pydantic-config`    | ClickHouse connection config with Pydantic validation                                                        |
| `doppler-secret-validation`     | Doppler secret rotation and validation                                                                       |
| `doppler-workflows`             | Doppler project/config management workflows                                                                  |
| `firecrawl-research-patterns`   | Programmatic Firecrawl: search, scrape, academic routing, deep research, corpus persistence, self-hosted ops |
| `pueue-job-orchestration`       | Pueue job queue management for long-running tasks                                                            |
| `distributed-job-safety`        | Safety patterns for distributed job execution                                                                |
| `session-recovery`              | Claude Code session recovery and continuation                                                                |
| `session-chronicle`             | Session event logging and chronicle                                                                          |
| `disk-hygiene`                  | Disk space management and cleanup                                                                            |
| `cloudflare-workers-publish`    | Cloudflare Workers deployment                                                                                |
| `python-logging-best-practices` | Python logging configuration patterns                                                                        |
| `mlflow-python`                 | MLflow experiment tracking setup                                                                             |
| `project-directory-migration`   | Project directory restructuring                                                                              |
| `dual-channel-watchexec`        | File watcher with dual notification channels                                                                 |
| `ml-failfast-validation`        | ML pipeline fast-fail validation                                                                             |
| `ml-data-pipeline-architecture` | ML data pipeline design patterns                                                                             |
