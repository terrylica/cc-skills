# devops-tools Plugin

> DevOps automation: ClickHouse, Doppler, MLflow, Cloudflare Workers, pueue, secrets management, self-hosted services.

**Hub**: [Root CLAUDE.md](../../CLAUDE.md) | **Sibling**: [itp-hooks CLAUDE.md](../itp-hooks/CLAUDE.md)

## Secrets Management

**Self-Custody Secrets first.** Store and read secrets through the operator's own stores, starting with the `vault` CLI (`vault get|set|run`), which wraps the macOS Keychain, SOPS/age backup and the manifest. 1Password is the last resort, for company-shared items only and never client-confidential ones. The full ladder is injected by `userpromptsubmit-1password-context-injection.sh` whenever a prompt mentions credentials, so it is not repeated here.

- **Company-shared 1Password items** use the service account (Claude Automation vault). Setup and the proxy caveat: [onep-credential-setup.md](./skills/cloudflare-workers-publish/references/onep-credential-setup.md).
- **Doppler** projects: `Skill(devops-tools:doppler-secret-validation)` | `Skill(itp:pypi-doppler)`.

## Self-Hosted Services

Services run on two GPU workstations: **<gpu-host>** (RTX 4090) for primary compute, **gpu-host-2** (RTX 2080 Ti) for secondary workloads. Access via Tailscale (primary) with Cloudflare Access SSH as the fallback — see the SSoT, [ssh-tunnel-companion/CLAUDE.md](../ssh-tunnel-companion/CLAUDE.md). **ZeroTier is gone** (removed 2026-04-06, macOS kernel-extension fragility); this line advertised it as a "legacy fallback" until 2026-09-05, contradicting its own linked SSoT.

| Service    | Host       | Port | Tunnel          | Skill                                             |
| ---------- | ---------- | ---- | --------------- | ------------------------------------------------- |
| ClickHouse | <gpu-host> | 8123 | localhost:18123 | `Skill(devops-tools:clickhouse-cloud-management)` |

> Do not add a self-hosted Firecrawl here. It ran on gpu-host-2:3002 until 2026-08-13 and was retired for the public API at `https://api.firecrawl.dev` — see `Skill(devops-tools:firecrawl-research-patterns)`.

**ClickHouse (<gpu-host>)**: Range bar data with 47 microstructure features (260M+ bars). Used by `rangebar-py` package. ClickHouse listens on localhost only — access via SSH tunnel (rangebar preflight handles automatically).

```bash
# Env vars (export per-project, e.g. from a gitignored .env):
RANGEBAR_CH_HOSTS=<gpu-host>    # SSH alias, NOT raw IP (tunnel required)
RANGEBAR_MODE=remote          # Skip local ClickHouse check

# Test connectivity:
ssh <gpu-host> "curl -s 'http://localhost:8123/?query=SELECT+1'"
```

**Network**: Tailscale primary (`ssh <gpu-host>`), Cloudflare Access fallback (`ssh <gpu-host>-cf`). See [ssh-tunnel-companion CLAUDE.md](../ssh-tunnel-companion/CLAUDE.md).

## Skills

- [agentic-process-monitor](./skills/agentic-process-monitor/SKILL.md)
- [claude-code-proxy-patterns](./skills/claude-code-proxy-patterns/SKILL.md)
- [clickhouse-cloud-management](./skills/clickhouse-cloud-management/SKILL.md)
- [clickhouse-pydantic-config](./skills/clickhouse-pydantic-config/SKILL.md)
- [cloudflare-workers-publish](./skills/cloudflare-workers-publish/SKILL.md)
- [disk-hygiene](./skills/disk-hygiene/SKILL.md)
- [distributed-job-safety](./skills/distributed-job-safety/SKILL.md)
- [doppler-secret-validation](./skills/doppler-secret-validation/SKILL.md)
- [doppler-workflows](./skills/doppler-workflows/SKILL.md)
- [dual-channel-watchexec](./skills/dual-channel-watchexec/SKILL.md)
- [firecrawl-research-patterns](./skills/firecrawl-research-patterns/SKILL.md)
- [macbook-desktop-mode](./skills/macbook-desktop-mode/SKILL.md)
- [ml-data-pipeline-architecture](./skills/ml-data-pipeline-architecture/SKILL.md)
- [ml-failfast-validation](./skills/ml-failfast-validation/SKILL.md)
- [mlflow-python](./skills/mlflow-python/SKILL.md)
- [project-directory-migration](./skills/project-directory-migration/SKILL.md)
- [pueue-job-orchestration](./skills/pueue-job-orchestration/SKILL.md)
- [macos-fda-grant-helper](./skills/macos-fda-grant-helper/SKILL.md) — interactive Full Disk Access (FDA) grant walkthrough for launchd-spawned binaries (iter 21)
- Pushover notifications **moved 2026-06-05** to the dedicated [`pushover-commander`](../pushover-commander/CLAUDE.md) plugin (send, emergency, headless app/sound management, incident-report rendering, UUID/JSONL verbatim audit). The former `pushover-verbatim-notify` skill is now `pushover-commander:verbatim-audit-notify`.
- [python-logging-best-practices](./skills/python-logging-best-practices/SKILL.md)
- [python-memory-safe-scripts](./skills/python-memory-safe-scripts/SKILL.md)
- [session-chronicle](./skills/session-chronicle/SKILL.md)
- [session-debrief](./skills/session-debrief/SKILL.md)
- [session-recovery](./skills/session-recovery/SKILL.md)

## Hooks

| Hook                                              | Event            | Matcher             | Purpose                                                                                                                                                                                                               |
| ------------------------------------------------- | ---------------- | ------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `pretooluse-firecrawl-research-reminder.ts`       | PreToolUse       | WebFetch\|WebSearch | Routes academic-paper fetches to `Skill(firecrawl-research-patterns)`                                                                                                                                                 |
| `posttooluse-1password-pattern-reminder.sh`       | PostToolUse      | Bash                | Reminds that 1Password is last resort (SCS ladder) when `op` is run "bare"                                                                                                                                            |
| `posttooluse-crown-jewel-plain-keychain-nudge.sh` | PostToolUse      | Bash                | Nudges crown-jewel `security add-generic-password … -T /usr/bin/security` toward a crown-strict vault scope (Secure Enclave + offline recovery key, never in the plain Keychain); escape hatch `CROWN-JEWEL-PLAIN-OK` |
| `userpromptsubmit-1password-context-injection.sh` | UserPromptSubmit | (any)               | Injects the Self-Custody Secrets ladder when the user mentions 1Password in chat                                                                                                                                      |

### Credential hooks

`userpromptsubmit-1password-context-injection.sh` injects the Self-Custody Secrets ladder when a prompt mentions credentials. `posttooluse-1password-pattern-reminder.sh` reminds after an `op` command that 1Password is the last resort, and skips meta commands (`op --version`, `signin`, `account list`). Their stdout is the SSoT for the wording.
