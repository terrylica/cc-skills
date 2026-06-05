---
name: send-notification
description: Send a Pushover push notification to the user's devices, optionally with an image attachment. Use when the user wants to send/push a notification, alert, or message via Pushover, or programmatically notify their phone. For repeating-alarm emergency alerts that require acknowledgement use emergency-priority2-receipt instead; for rendering a verbose incident-report image use render-incident-report-image. TRIGGERS - send pushover, push notification, notify my phone, pushover alert.
---

# send-notification

> **Self-Evolving Skill**: This skill improves through use. If instructions are wrong, parameters drifted, or a workaround was needed — fix this file immediately, don't defer. Only update for real, reproducible issues.

Send a Pushover notification via the TypeScript core `pushover_core.ts` (Bun). Secrets resolve via `_lib/resolve_pushover_secret.sh` from an **env-configured 1Password item** (`PUSHOVER_OP_VAULT` / `PUSHOVER_OP_ITEM`, set in your private config — see [`_lib/references/private-config-setup.md`](../_lib/references/private-config-setup.md)) with a macOS Keychain fallback — never hardcode tokens.

## Usage

```bash
env -u HTTPS_PROXY -u HTTP_PROXY bun "${CLAUDE_PLUGIN_ROOT}/skills/_lib/pushover_core.ts" send \
  --message "your message" --title "Title" [--priority N] [--attach image.png] \
  [--sound NAME] [--url https://link] [--url-title "link title"] [--html|--monospace] [--app main|test] [--force]
```

- `--app test` (default) uses the test application token; `--app main` uses the production token.
- `--html` / `--monospace` enable rich formatting (mutually exclusive — preflight refuses both).
- All limits live in `skills/_lib/pushover_api_limits.json` (SSoT). **Preflight** validates every send: it **refuses**
  url>512, attachment>5 MB, html+monospace (override with `--force`) and **warns** on message/title
  truncation or a sound not in the account — turning Pushover's silent failures into explicit output.
- Every send is **audited** to `~/.local/state/pushover/po-audit.jsonl` (UUID-keyed) and **quota** remaining
  is read from the response headers (warns when low). See **health-check** for `doctor`/`quota`.

## Notes

- `env -u *PROXY*` makes Bun's `fetch` bypass the sandbox MITM proxy (else 502). Validates `user`+`device`
  before sending; transient 5xx/network errors are retried (×3, backoff). Type-checked via `bunx tsc --noEmit`.

## Post-Execution Reflection

After this skill completes, check before closing:

1. **Did the notification (and any image) land on the device?** If it silently failed, fix the auth/payload/proxy cause before assuming success.
2. **Did the image attachment render?** If it was dropped, check the size/format limits in `_lib/pushover_api_limits.json`.

Only update if the issue is real and reproducible — not speculative.
