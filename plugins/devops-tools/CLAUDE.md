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
| Token 1P item | Employee vault, ID `<token-item>`                         |

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

Services run on two GPU workstations: **bigblack** (RTX 4090) for primary compute, **littleblack** (RTX 2080 Ti) for secondary workloads. Access via Tailscale primary path or legacy ZeroTier fallback.

| Service    | Host        | Port | Tunnel          | Skill                                             |
| ---------- | ----------- | ---- | --------------- | ------------------------------------------------- |
| ClickHouse | bigblack    | 8123 | localhost:18123 | `Skill(devops-tools:clickhouse-cloud-management)` |
| VNC (MT5)  | bigblack    | 5900 | localhost:5900  | x11vnc, display :99, MT5/WINE                     |
| Firecrawl  | littleblack | 3002 | —               | `Skill(devops-tools:firecrawl-research-patterns)` |

**ClickHouse (bigblack)**: Range bar data with 47 microstructure features (260M+ bars). Used by `rangebar-py` package. ClickHouse listens on localhost only — access via SSH tunnel (rangebar preflight handles automatically).

```bash
# Env vars (set in .mise.local.toml per-project, gitignored):
RANGEBAR_CH_HOSTS=bigblack    # SSH alias, NOT raw IP (tunnel required)
RANGEBAR_MODE=remote          # Skip local ClickHouse check

# Test connectivity:
ssh bigblack "curl -s 'http://localhost:8123/?query=SELECT+1'"
```

**Network**: Tailscale primary (`ssh bigblack`), Cloudflare Access fallback (`ssh bigblack-cf`). See [ssh-tunnel-companion CLAUDE.md](../ssh-tunnel-companion/CLAUDE.md).

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
- [worktree-manager](./skills/worktree-manager/SKILL.md)

## Hooks

| Hook                                              | Event            | Matcher             | Purpose                                                                                                                                                             |
| ------------------------------------------------- | ---------------- | ------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `pretooluse-firecrawl-research-reminder.ts`       | PreToolUse       | WebFetch\|WebSearch | Routes academic-paper fetches to `Skill(firecrawl-research-patterns)`                                                                                               |
| `posttooluse-1password-pattern-reminder.sh`       | PostToolUse      | Bash                | Reminds Claude of the SA-token-first, biometric-fallback pattern when `op` is run "bare"                                                                            |
| `posttooluse-crown-jewel-plain-keychain-nudge.sh` | PostToolUse      | Bash                | Nudges crown-jewel `security add-generic-password … -T /usr/bin/security` toward the Touch-ID-gated tier (`vault set --gated`); escape hatch `CROWN-JEWEL-PLAIN-OK` |
| `userpromptsubmit-1password-context-injection.sh` | UserPromptSubmit | (any)               | Injects the canonical 1Password pattern upfront when the user mentions 1Password in chat                                                                            |

### 1Password pattern reminder (iter 4, 2026-05-19)

The two 1Password hooks above implement the canonical credential-management pattern as a hook chain rather than a documentation-only rule. The chain has three layers:

1. **`UserPromptSubmit` (proactive)**: when the user types something containing `1Password`, `1P`, `op item`, `op read`, `op vault`, `service account`, `SA token`, `Claude Automation vault`, or `op://`, inject upfront context about the pattern. Claude sees this before planning.

2. **`PostToolUse` on `Bash` (reactive)**: when Claude runs an `op` command that doesn't already use `OP_SERVICE_ACCOUNT_TOKEN=...` and isn't an obvious meta command (`op --version`, `op --help`, `op signin`, `op account list`) or biometric-fallback (`unset OP_SERVICE_ACCOUNT_TOKEN`), emit the reminder so future commands follow the pattern. Does NOT undo the command — just makes Claude SEE the reminder via the cc-skills `{decision: "block"}` convention (see [docs/HOOKS.md "Hook Output Visibility"](/docs/HOOKS.md)).

3. **Both reminders include**: the proxy bypass (`unset HTTPS_PROXY HTTP_PROXY` — Claude Code OAuth proxy at `127.0.0.1:52205` returns 502 on `api.1password.com`), the SA token path, and the biometric-fallback path. Discovered during iter 4 when registering the Pushover credential.

Skip rules in the PostToolUse hook prevent nag-loops:

- Skips if command already uses `OP_SERVICE_ACCOUNT_TOKEN=...`
- Skips if command uses `unset OP_SERVICE_ACCOUNT_TOKEN` (biometric fallback by design)
- Skips meta commands (`op --version|--help|-h|signin|account list`)
- Word-boundary detection prevents false positives on `open`, `stop`, etc.

## Environment Variables

| Variable        | Required | Description                                                                                                                                                         |
| --------------- | -------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `MINIMAX_MODEL` | No       | MiniMax model ID for `session-debrief` and `prompt-benchmark`; SSoT is `~/.config/mise/config.toml`; default `MiniMax-M3` (switched from M2.7-highspeed 2026-06-01) |
