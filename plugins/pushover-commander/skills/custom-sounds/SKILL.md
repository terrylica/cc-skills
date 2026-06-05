---
name: custom-sounds
description: List or validate Pushover notification sounds (built-in plus this account's custom uploaded sounds) via the /1/sounds.json API. Use when choosing a notification sound, checking whether a custom sound exists, or picking a safe fallback before sending. TRIGGERS - pushover sounds, list sounds, validate sound, custom sound, which sounds.
---

# custom-sounds

Enumerate/validate sounds via the TS core `pushover_core.ts sounds`.

```bash
env -u HTTPS_PROXY -u HTTP_PROXY bun "${CLAUDE_PLUGIN_ROOT}/skills/_lib/pushover_core.ts" sounds list                # name<TAB>label
env -u HTTPS_PROXY -u HTTP_PROXY bun "${CLAUDE_PLUGIN_ROOT}/skills/_lib/pushover_core.ts" sounds has piano            # exit 0 if present
env -u HTTPS_PROXY -u HTTP_PROXY bun "${CLAUDE_PLUGIN_ROOT}/skills/_lib/pushover_core.ts" sounds resolve piano pianobar  # echo first that exists
```

## Notes (verified 2026-05-30)

- Pushover **silently accepts invalid sound names** (no API error) — so always `resolve`/`has` before relying on a custom sound; a typo would just fall back to the user's default silently.
- `piano` is a **custom** sound on this account; `pianobar` is built-in. Custom sounds are per application token, so pass `--app main|test` to query the right app.
