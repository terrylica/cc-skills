---
name: pushover-verbatim-notify
description: Send Pushover notifications with UUID-linked verbatim JSONL audit trail. TRIGGERS - pushover notify, send pushover, observability alert, verbatim notification, fleet alert, pushover-lookup, audit log notification, push notification with UUID
---

# Pushover Verbatim+UUID Notification

> **Self-Evolving Skill**: This skill improves through use. If instructions are wrong, parameters drifted, or a workaround was needed — fix this file immediately, don't defer. Only update for real, reproducible issues.

A two-script skill that solves the **"Pushover message hit my phone but I don't remember what it was about"** problem for personal automation fleets. Every notification carries a UUID; the full verbatim payload (including everything that didn't fit in Pushover's 1024-char body) lands in a local JSONL audit log keyed by that UUID. You look it up by pasting the UUID back.

**Designed for**: cron-fired scripts, launchd daemons, hook outputs — any place that wants "fire-and-forget alerting with full context if you ever need to dig in." Personal scale; one Mac; one Pushover account. Not a microservices observability stack.

## Why this exists

Pushover messages are limited to 1024 UTF-8 characters in the body and 250 in the title (per [pushover.net/api](https://pushover.net/api)). Real failure events often need thousands of chars of context: stack traces, full env dumps, file paths, the exact failing command. Truncating loses what you actually need to debug.

The fix is the **correlation-ID-plus-JSONL** pattern: short summary on the device, full verbatim payload in a local newline-delimited JSON file, UUID linking them. When a notification fires, the body contains the UUID and a `pushover-lookup` command. Run that and you get the complete entry.

## Two scripts

| Script               | Role                                                                                 |
| -------------------- | ------------------------------------------------------------------------------------ |
| `pushover-notify.sh` | Sender: generates UUID, writes verbatim JSONL, dispatches Pushover with summary+UUID |
| `pushover-lookup.sh` | Retriever: given a UUID (or prefix), prints the pretty-printed JSONL entry           |

Add them to your PATH:

```bash
ln -sf "$HOME/.claude/plugins/marketplaces/cc-skills/plugins/devops-tools/skills/pushover-verbatim-notify/scripts/pushover-notify.sh" ~/.local/bin/pushover-notify
ln -sf "$HOME/.claude/plugins/marketplaces/cc-skills/plugins/devops-tools/skills/pushover-verbatim-notify/scripts/pushover-lookup.sh" ~/.local/bin/pushover-lookup
```

## Quick start

### Send a notification

```bash
pushover-notify \
    --title "maccy-backup failure" \
    --message "Maccy DB unreadable for 31 days; backup script needs TCC Full Disk Access" \
    --service maccy-backup \
    --level ERROR \
    --extra '{"db_path":"/Users/terryli/Library/Containers/org.p0deje.Maccy/Data/Library/Application Support/Maccy/Storage.sqlite","last_success":"2026-04-17","days_since":31}'
```

Output (stdout): the UUID, e.g.

```
3f8c2d9e-4a1b-4c5d-8e7f-1a2b3c4d5e6f
```

Your phone receives:

```
[maccy-backup] level=ERROR priority=1
Maccy DB unreadable for 31 days; backup script needs TCC Full Disk Access

lookup: pushover-lookup 3f8c2d9e-4a1b-4c5d-8e7f-1a2b3c4d5e6f

UUID: 3f8c2d9e-4a1b-4c5d-8e7f-1a2b3c4d5e6f
```

### Look it up

Paste the UUID back:

```bash
pushover-lookup 3f8c2d9e-4a1b-4c5d-8e7f-1a2b3c4d5e6f
```

Or pipe the whole Pushover message body:

```bash
pbpaste | pushover-lookup
```

Output: full pretty-printed JSON with **every** field that was in `--extra`, plus the canonical schema.

## JSONL schema

Each line in `~/.local/state/pushover/audit-YYYYMMDD.jsonl` is one event:

```json
{
  "run_id": "3f8c2d9e-4a1b-4c5d-8e7f-1a2b3c4d5e6f",
  "ts": "2026-05-19T07:23:01.123Z",
  "host": "terryli-mbp",
  "service": "maccy-backup",
  "actor": "launchd",
  "target": "Storage.sqlite",
  "level": "ERROR",
  "title": "maccy-backup failure",
  "message": "Maccy DB unreadable...",
  "priority": 1,
  "extra": {
    "db_path": "...",
    "last_success": "2026-04-17",
    "days_since": 31
  }
}
```

Followups (the Pushover API response, dispatch failures) are appended as separate lines with the same `run_id` — so `jq -c 'select(.run_id == "...")' *.jsonl` reconstructs the full timeline.

## Credentials

By default, the sender pulls Pushover credentials from 1Password Claude Automation vault, item `dg5ng7vgj6dmmtc2vavo5kfko4` (registered in `docs/1password-credential-registry.md`). It follows the cc-skills canonical pattern:

1. Unset `HTTPS_PROXY` / `HTTP_PROXY` (Claude Code OAuth proxy returns 502 on 1P endpoints)
2. Try Service Account token first (`~/.claude/.secrets/op-service-account-token`)
3. Fall back to biometric (`unset OP_SERVICE_ACCOUNT_TOKEN; op read ...`) on permission denied

Override for testing / non-1P environments:

```bash
PUSHOVER_TOKEN=... PUSHOVER_USER=... pushover-notify ...
```

Or skip the remote call entirely (write JSONL only):

```bash
NO_PUSHOVER=1 pushover-notify ...
```

## Priority and TTL

| Level | Default priority | Phone behavior                                                |
| ----- | ---------------- | ------------------------------------------------------------- |
| INFO  | -1               | Silent (no sound, no vibration); inbox-only                   |
| WARN  | 0                | Default sound and vibration                                   |
| ERROR | 1                | Bypass quiet hours                                            |
| —     | 2 (manual)       | Emergency — repeats until acknowledged (retry=30, expire=600) |

For low-signal events (heartbeats, "nothing changed" pings) set a TTL so the message self-expires on the phone:

```bash
pushover-notify --level INFO --ttl 300 --title heartbeat --message "..." --service some-service
```

## Wrapper patterns for common use cases

### Wrap a launchd script (alert on failure only)

```bash
#!/bin/bash
set -e
LOG=$(mktemp)
if ! /path/to/your/script.sh > "$LOG" 2>&1; then
    pushover-notify \
        --title "script.sh failed (exit $?)" \
        --message "$(tail -c 400 "$LOG")" \
        --service script-name \
        --level ERROR \
        --extra "$(jq -Rs '{stdout_tail: .}' < "$LOG")"
    exit 1
fi
```

### Use from a pipe

```bash
some-long-running-job 2>&1 \
    | tee /tmp/job.log \
    | tail -n 0  # block until job done
pushover-notify \
    --title "job completed" \
    --service my-job \
    --message "$(tail -c 500 /tmp/job.log)" \
    --extra "$(jq -Rs --arg exit "$?" '{exit_code: ($exit | tonumber), log_tail: .}' < /tmp/job.log)"
```

## Operational notes

- **Log location**: `~/.local/state/pushover/audit-YYYYMMDD.jsonl` — one file per UTC day, simplifies retention.
- **Rotation**: not yet wired into `~/.config/log-rotation.conf` — if your fleet emits a lot, add it. Today's footprint will be small.
- **Privacy**: JSONL is on the local Mac. Pushover only sees what's in the message body (1024 chars max). Secrets should NOT go in `--message` or `--title`.
- **Tested**: Pushover-side validated end-to-end during iter 4 (test UUID `C3B649E1-BF34-4346-A211-511EFE7CDCBD` delivered).

## References

- [Pushover API docs](https://pushover.net/api) — message format, priorities, receipts
- [Pushover May 2026 quota changes](https://blog.pushover.net/posts/2026/4/app-limits) — per-account 10k msgs/month
- 1Password registry: `docs/1password-credential-registry.md`
- Companion hook: `plugins/devops-tools/hooks/posttooluse-1password-pattern-reminder.sh` (reminds Claude of credential pattern)

## Post-Execution Reflection

After this skill completes, check before closing:

1. **Did the notification deliver?** — Pushover returns a receipt token; if delivery silently failed, fix the instruction (auth, rate-limit, malformed body) that caused it.
2. **Did the JSONL audit entry write correctly?** — `pushover-lookup <uuid>` should round-trip the full payload. If not, the writer is dropping fields — fix the schema.
3. **Was the message truncated?** — If the body exceeded 1024 chars, confirm the `--extra` payload captured everything that didn't fit. Update Usage examples if the truncation boundary moved.
4. **Did `pushover-lookup` find by UUID prefix?** — If only the full UUID worked, the prefix-search needs fixing.

Only update if the issue is real and reproducible — not speculative.
