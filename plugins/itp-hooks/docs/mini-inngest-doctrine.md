# Mini-Inngest Doctrine Hook

**File**: `plugins/itp-hooks/hooks/posttooluse-mini-inngest-doctrine.ts`

**Status**: Soft nudge (non-blocking reminder via PostToolUse channel, per ADR 2025-12-17)

**Operator directive**: 2026-07-06

---

## What It Does

The hook emits a soft, non-blocking reminder when you appear to be **setting up an external/web-facing service or off-web monitor locally or manually**, instead of on the Mac Mini as an **Inngest application** (the shared, durable workflow engine).

The nudge surfaces via the Claude system message channel; it does NOT block or undo your work. It is purely informational.

---

## Trigger Heuristic

The hook fires when EITHER:

### 1. Explicit Launchd/Cron Context (Strong Signal)

These patterns alone are sufficient to trigger (no external target required):

- `launchctl bootstrap` / `launchctl load`
- `LaunchAgent` / `LaunchDaemons` (in file paths or config labels)
- `StartInterval` (plist key — indicates periodic execution)
- Crontab creation (`crontab -e`)
- References to `.plist` files with `launchd` in the name

### 2. Service Keywords + External Target (Actionable Pattern)

Fires when BOTH are present:

- **Keywords**: `webhook`, `poll`, `monitor`, `uptime`, `scrape`, `imap`, `smtp`, `deploy`, `serve`, `forward`, `redirect`, `notify`
- **Actionable context**: keywords appear in parameter assignments or function calls:
  - `webhook_url=https://external.com`
  - `--poll-endpoint https://api.example.com`
  - `monitor-host https://alerts.io`
  - `forward_to https://service.io`
- **External target**: hostnames like `example.com`, `api.service.io` (excludes `localhost`, `127.0.0.1`, `.local`, `.ts.net`, `.tailnet`)

---

## When It Does NOT Fire

- Localhost / 127.0.0.1 development servers
- `.local` domain references (local network)
- `.ts.net` / `.tailnet` tailnet references
- Read-only operations (grep, cat, etc.)
- Simple documentation (e.g., `echo 'webhook example.com'`)
- Valid uses of the `MINI-INNGEST-OK` escape hatch

---

## Escape Hatch: `MINI-INNGEST-OK`

Add the marker `MINI-INNGEST-OK` anywhere in your file or command to suppress the nudge.

**Examples**:

```bash
# Bash command
launchctl bootstrap ~/Library/LaunchAgents webhook.plist # MINI-INNGEST-OK
```

```python
# Python file (as a comment)
# MINI-INNGEST-OK
# Temporary local webhook for debugging
```

```xml
<!-- XML/plist file -->
<!-- MINI-INNGEST-OK -->
<plist>...</plist>
```

---

## The Standard: Running on the Mac Mini

External/web-facing services should run on the Mac Mini as **Inngest applications** (the workflow engine).

### Deployment Path

1. **Define the tenant service** in `~/vj/cpc/mini-services/`
2. **Deploy** via the `mini-deploy` CLI from `~/vj/cpc/mini-platform`
3. **Access the UI** at `https://terrys-mac-mini.tail0f299b.ts.net/` (tailnet only)

### Note on Terminology

"Inngest" here refers to the **workflow engine**, distinct from the `coa ingest` CLI command (which is for data ingestion).

---

## References

- **How-To**: See the homelab skill `~/.claude/skills/homelab/` (private local skill, not in this repo) for setup instructions
- **Architecture**: The explanation SSoT lives at `~/.claude/skills/homelab/references/workflows.md`
- **ADR**: `cc-skills/docs/adr/2026-07-06-mini-inngest-doctrine-hook.md` (repo root, not this plugin dir)
- **Registry**: Escape-hatch marker registered in `lib/marketplace-wide-escape-hatch-producer-marker-canonical-registry-cross-plugin-iter111.ts`

---

## Related Hooks

- `pretooluse-process-storm-guard.mjs` — guards against fork bombs and process storms
- `posttooluse-pushover-budget-reminder.ts` — nudges on message-budget usage
