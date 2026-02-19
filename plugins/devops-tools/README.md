# devops-tools

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Skills](https://img.shields.io/badge/Skills-17-blue.svg)]()
[![Claude Code](https://img.shields.io/badge/Claude%20Code-Plugin-purple.svg)]()

DevOps automation plugin for Claude Code: ClickHouse Cloud management, Doppler credentials, secret validation, MLflow queries, notifications, and session recovery.

Merged: `notification-tools` (dual-channel-watchexec) moved here.

> **Migration Notice**: asciinema skills have moved to the dedicated `asciinema-tools` plugin.

## Skills

| Skill                             | Description                                                                |
| --------------------------------- | -------------------------------------------------------------------------- |
| **clickhouse-cloud-management**   | ClickHouse Cloud user creation, permissions, and credential management     |
| **clickhouse-pydantic-config**    | Generate DBeaver configurations from Pydantic ClickHouse models            |
| **doppler-workflows**             | PyPI publishing, AWS credential rotation, multi-service patterns           |
| **doppler-secret-validation**     | Add, validate, and test API tokens/credentials in Doppler                  |
| **firecrawl-self-hosted**         | Self-hosted Firecrawl deployment, Docker restart policies, troubleshooting |
| **ml-data-pipeline-architecture** | Polars vs Pandas decision tree, zero-copy patterns for ML pipelines        |
| **ml-failfast-validation**        | POC validation patterns for ML experiments (10-check framework)            |
| **mlflow-python**                 | Log backtest metrics, query experiments, QuantStats integration            |
| **session-recovery**              | Troubleshoot Claude Code session issues and HOME variable problems         |
| **session-chronicle**             | Session provenance tracking with S3 artifact sharing for team access       |
| **dual-channel-watchexec**        | Send notifications to Telegram + Pushover on process events                |
| **python-logging-best-practices** | Unified Python logging with loguru, platformdirs, RotatingFileHandler      |
| **disk-hygiene**                  | macOS disk cleanup, cache pruning, stale file detection, Downloads triage  |
| **project-directory-migration**   | Migrate Claude Code sessions when renaming project directories             |
| **cloudflare-workers-publish**    | Deploy static HTML to Cloudflare Workers with 1Password credentials        |
| **pueue-job-orchestration**       | Pueue job lifecycle orchestration for long-running tasks                   |
| **distributed-job-safety**        | Concurrency safety patterns for pueue + mise + systemd-run job pipelines   |

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
- "firecrawl setup", "self-hosted scraper", "docker restart policy" -> firecrawl-self-hosted
- "Polars vs Pandas", "ML data pipeline", "zero-copy" -> ml-data-pipeline-architecture
- "POC validation", "fail-fast checks", "ML experiment validation" -> ml-failfast-validation
- "log backtest", "MLflow metrics", "search runs" -> mlflow-python
- "no conversations found to resume" -> session-recovery
- "who created this", "trace origin", "provenance" -> session-chronicle
- "watchexec notifications", "Telegram + Pushover" -> dual-channel-watchexec
- "loguru", "python logging", "structured logging" -> python-logging-best-practices
- "disk space", "cleanup", "stale files", "cache clean", "forgotten files" -> disk-hygiene
- "rename directory", "move project", "migrate sessions", "project path change" -> project-directory-migration
- "cloudflare deploy", "publish static", "wrangler deploy", "workers.dev", "HTML hosting" -> cloudflare-workers-publish
- "pueue jobs", "pueue status", "pueue orchestration", "job queue" -> pueue-job-orchestration
- "concurrent jobs", "checkpoint race", "cgroup memory", "systemd-run", "autoscale" -> distributed-job-safety

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

### Firecrawl Self-Hosted

- Docker Compose deployment with restart policies
- Troubleshooting guide for container failures
- Best practices: `restart: unless-stopped` for all services
- YAML anchors for consistent configuration
- ZeroTier network integration

### ML Data Pipeline Architecture

- Polars vs Pandas decision tree
- Zero-copy patterns for Arrow interop
- Memory-mapped file handling
- Lazy evaluation strategies

### ML Fail-Fast Validation

- 10-check POC framework for ML experiments
- Model instantiation, gradient flow, prediction sanity
- NDJSON logging validation
- Bayesian warmup verification

### Python Logging Best Practices

- Unified loguru patterns
- platformdirs for XDG-compliant log locations
- RotatingFileHandler with compression
- Structured JSONL/NDJSON output

### Disk Hygiene

- Cache audit and cleanup (uv, brew, pip, npm, cargo, rustup, Docker)
- Forgotten file detection (>50MB, untouched 180+ days)
- Disk analysis tool benchmarks (dust, dua, gdu, ncdu)
- Downloads triage with interactive AskUserQuestion flow
- Quick wins summary ordered by typical savings

### Project Directory Migration

- Interactive AskUserQuestion workflow for safe migration
- Automatic session count audit and dry-run preview
- Backup, rollback, and symlink backward-compatibility
- Environment fixups: mise trust, venv recreation, direnv/asdf warnings
- Universal script for any Claude Code project

### Cloudflare Workers Publish

- Static HTML deployment to workers.dev (Bokeh charts, dashboards, reports)
- 1Password credential management (Claude Automation vault integration)
- Auto-generated directory listing (index.html)
- 15 documented anti-patterns from production deployment (CFW-01..CFW-15)
- Git LFS pointer detection before deploy
- Minimal wrangler.toml template (3 fields for static-only)

### Distributed Job Safety

- 7 formal concurrency invariants (filename isolation, atomic writes, idempotent cleanup)
- 7 anti-patterns learned from production failures
- Mise + pueue + systemd-run stack with responsibility boundaries
- Per-job cgroup memory caps with MemorySwapMax=0
- Autoscaler concept with incremental scaling protocol
- Two-layer pattern: universal skill + project-specific `*-job-safety` extension

## Requirements

- Doppler CLI (`brew install dopplerhq/cli/doppler`)
- Brotli (`brew install brotli`) - for session-chronicle
- AWS CLI (`brew install awscli`) - for session-chronicle S3 upload
- 1Password CLI (`brew install 1password-cli`) - for session-chronicle and cloudflare-workers-publish credentials
- wrangler (`npx wrangler` via Node.js) - for cloudflare-workers-publish
- Claude Code CLI

## Troubleshooting

| Issue                         | Cause               | Solution                                 |
| ----------------------------- | ------------------- | ---------------------------------------- |
| Doppler auth failed           | Token expired       | `doppler login` to re-authenticate       |
| S3 upload fails               | Missing credentials | Verify AWS credentials via 1Password CLI |
| ClickHouse connection refused | Network/firewall    | Check ClickHouse Cloud IP allowlist      |
| MLflow tracking error         | Server unreachable  | Check MLflow tracking URI configuration  |
| Wrangler deploy fails         | Wrong directory     | `cd` to directory with wrangler.toml     |
| Cloudflare 403 on workers.dev | Subdomain disabled  | Enable workers.dev in CF dashboard       |

## License

MIT
