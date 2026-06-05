---
name: health-check
description: Diagnose the po Pushover plugin and check remaining monthly quota. Runs a full self-test (credential resolution via 1Password/Keychain, /users/validate.json, quota, expected custom sounds present, deps bun/uv/chrome, audit log) and reports message quota remaining. Use when the user asks if Pushover is working, why a notification failed, how many messages are left, or wants a health/diagnostic check. TRIGGERS - pushover health, po doctor, pushover not working, pushover quota, messages left, diagnose pushover.
---

# health-check

> **Self-Evolving Skill**: This skill improves through use. If instructions are wrong, parameters drifted, or a workaround was needed — fix this file immediately, don't defer. Only update for real, reproducible issues.

Self-test + quota for the po plugin, via the TS core.

```bash
env -u HTTPS_PROXY -u HTTP_PROXY bun "${CLAUDE_PLUGIN_ROOT}/skills/_lib/pushover_core.ts" doctor   # full self-test (JSON)
env -u HTTPS_PROXY -u HTTP_PROXY bun "${CLAUDE_PLUGIN_ROOT}/skills/_lib/pushover_core.ts" quota     # {limit, remaining, reset}
```

`doctor` checks: creds (op→Keychain), `/users/validate.json`, monthly quota, the expected custom sounds
(`po_fanfare`/`po_uplift`/`po_celebrate`), deps (bun/uv/Chrome), and the audit log size. `quota` prints
remaining messages and warns when below `quota_warn_remaining` (see `pushover_api_limits.json`).

## Reliability primitives (apply to every send)

- **Limits SSoT** — `skills/_lib/pushover_api_limits.json` is the single source for all Pushover limits/rules
  (message 1024, title 250, url 512, attachment 5 MB, sound <500 KB/≤30 s, app name 20, desc 500,
  html⊕monospace, priority-2 needs retry+expire). Edit there, nowhere else.
- **Preflight** — `pushover_core.ts` validates every send against `pushover_api_limits.json` and turns Pushover's _silent_
  failures into explicit output: **refuses** (url>512, attachment>5 MB, html+monospace) — override with
  `--force` — and **warns** (message/title truncation, sound not in account).
- **Audit trail** — every send appends a UUID-keyed JSONL line to `~/.local/state/pushover/po-audit.jsonl`
  (`ts, uuid, app, priority, status, request, receipt, remaining, message_len, errors`). Retrieve with
  `grep <uuid> ~/.local/state/pushover/po-audit.jsonl | jq .`.
- **Quota guard** — each send reads `X-Limit-App-Remaining` and warns when low.
- **Retry/backoff** — transient network / 5xx are retried (×3, backoff) before failing.

## Post-Execution Reflection

After this skill completes, check before closing:

1. **Did the check surface real failures (credentials, quota, dependencies) with no false green?** If a broken subsystem reported healthy, fix the check.
2. **Was remaining quota reported accurately?** A stale or wrong quota reading needs fixing before it misleads.

Only update if the issue is real and reproducible — not speculative.
