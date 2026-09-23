---
name: manage-apps-and-sounds-headless
description: Control the pushover.net web dashboard headlessly for things the HTTP API cannot do - log in, list applications, CREATE or DELETE Pushover applications (returning the new app's API token), and ADD or REMOVE custom notification sounds (with a sourcing+loudness pipeline for free MP3 jingles). Drives Playwright's Google Chrome for Testing (never your own Google Chrome unless asked with --browser chrome). Use when the user wants to automate the Pushover website/dashboard rather than send notifications (that is send-notification). TRIGGERS - pushover dashboard, create pushover app, delete pushover app, new api token, add custom sound, upload pushover sound, remove custom sound, find jingle, pushover web automation.
---

# manage-apps-and-sounds-headless

> **Self-Evolving Skill**: This skill improves through use. If instructions are wrong, parameters drifted, or a workaround was needed — fix this file immediately, don't defer. Only update for real, reproducible issues.

Headless dashboard automation via `pushover_headless_web_control.ts` (function/enum-driven Bun TypeScript — run directly, no build; needs `bun install` in `skills/_lib/` for `playwright-core`). pushover.net login is a plain email/password form (**no anti-bot / CAPTCHA / 2FA** — verified 2026-05-30), so plain Playwright + Chrome for Testing works.

```bash
export PO_EMAIL="$(bash "$(cc-plugin-root pushover-commander)/skills/_lib/resolve_pushover_secret.sh" login_email)"
export PO_PW="$(bash "$(cc-plugin-root pushover-commander)/skills/_lib/resolve_pushover_secret.sh" login_password)"
export PO_USER="$(bash "$(cc-plugin-root pushover-commander)/skills/_lib/resolve_pushover_secret.sh" user_key)"   # create-app token disambiguation
WEB() { env -u HTTPS_PROXY -u HTTP_PROXY \
  bun "$(cc-plugin-root pushover-commander)/skills/_lib/pushover_headless_web_control.ts" "$@"; }

WEB apps                                              # list application names
WEB create-app --name "My App" --desc "..." --reveal # create app, print its API token (--reveal = full)
WEB delete-app --name "My App"                        # delete app (by --name or --slug)
WEB list-sounds                                       # list custom sound names
WEB add-sound --name po_fanfare --file x.mp3 --desc "..."   # upload a custom sound
WEB remove-sound --name po_fanfare                   # delete a custom sound
```

## Browser: Chrome for Testing, not your own Chrome

🔴 **The script drives Playwright's "Google Chrome for Testing.app" by default, NOT the operator's Google Chrome.** On 2026-09-22 a second Google Chrome instance (Playwright's `channel: "chrome"`, on a separate profile) collided with the operator's own Chrome in macOS LaunchServices: links stopped opening and every Chrome had to be force-quit. Chrome for Testing has its own bundle id, so the two never collide.

```bash
# once per machine — uses this plugin's own pinned playwright-core
(cd "$(cc-plugin-root pushover-commander)/skills/_lib" && bunx playwright-core install chromium)

WEB apps                     # default: --browser cft (newest chromium-<N> Chrome for Testing)
WEB apps --browser chrome    # deliberately drive your own Google Chrome (collision risk accepted)
PUSHOVER_WEB_BROWSER=chrome WEB apps   # same, via env; --browser wins over the env var
```

- No Chrome for Testing installed and no explicit choice → it **falls back to system Chrome with a loud stderr warning** naming the risk and the install command. It never falls back silently.
- `--browser cft` (or `PUSHOVER_WEB_BROWSER=cft`) with none installed → **exits 1** with the install command.
- It looks in `~/Library/Caches/ms-playwright` (or `PLAYWRIGHT_BROWSERS_PATH`) for the **numerically highest** `chromium-<N>`; `chromium_headless_shell-*` is skipped.

## Custom sounds: constraints + sourcing pipeline (verified 2026-05-30)

Pushover custom sounds: **MP3 only, < 500 KB, ≤ 30 s** (iOS won't play longer). Sweet spot for
"loud + as long as possible": **~29 s at 128 kbps ≈ 454 KB**. Two helpers automate sourcing/processing:

```bash
# 1) discover free MP3 jingles (Mixkit free license, attribution optional)
bash "$(cc-plugin-root pushover-commander)/skills/_lib/find_jingles.sh" win        # or game musical alarm celebration
bash "$(cc-plugin-root pushover-commander)/skills/_lib/find_jingles.sh" tag/happy  # stock-music tags (longer tracks)

# 2) trim + LOUDNESS-NORMALIZE + size-fit to a compliant sound (loudnorm I=-10, peak -1dB, <500KB)
bash "$(cc-plugin-root pushover-commander)/skills/_lib/make_custom_sound.sh" <url|file> out.mp3 [start_s] [dur] [bitrate]
#   -> JSON {kb, dur, max_db, mean_db, under_500kb}; non-zero exit if >=500KB (then lower bitrate)

# 3) upload it
WEB add-sound --name my_jingle --file out.mp3 --desc "loud 29s jingle"
```

Always analyze with `make_custom_sound.sh` output (or `ffmpeg -af volumedetect`) to confirm **loud** (max ≈ 0 dB)
and **long** (≈29 s) before upload. Loaded so far: `po_fanfare`, `po_uplift`, `po_celebrate`
(all 29 s / 454 KB / peak ≈ -1 dB). Pre-existing custom: `dune, piano, toy_story, vibe20sec`.

## Verified autonomous capability (full lifecycle)

- **create-app**: `application[name]` + terms checkbox + submit; captures the 30-char API token from the app page (excludes `PO_USER`). **delete-app**: `/apps/edit/<slug>` → `/apps/destroy/<slug>`. 🔴 **The name field was RENAMED upstream** — it was `application[short_name]` / `#application_short_name` and is now `application[name]` / `#application_name` (measured live on `/apps/build` 2026-09-20, after every `create-app` died with `fill: Timeout 30000ms exceeded — waiting for locator('#application_short_name')`). The script now tries both spellings, newest first, and throws naming the page URL if neither is present, rather than submitting a form whose name field was never filled.
- **add-sound**: `/sounds/build` (`sound[name]`, `sound[description]`, file `sound[sound_data_file]`).
  **remove-sound**: `/sounds/edit/<name>` → `/sounds/destroy/<name>`. Rails `data-method=post`;
  the script auto-accepts the confirm dialog. Both verify the result by re-listing.

## Tooling notes

- Default: Playwright + Chrome for Testing via `executablePath` (see "Browser" above); `channel: "chrome"` only with `--browser chrome` or as the announced fallback. Scrapling/Obscura unnecessary here.
- The module is importable: its CLI runs only under `import.meta.main`, so `batch_create_pushover_apps.ts` (and any other script) can import `login`/`createApp`/`editApp`/`withDashboard` without running the CLI.
- Network: prefix `op`/HTTP with `env -u *PROXY*` (and curl `--noproxy '*'`) to bypass the sandbox proxy.

## Post-Execution Reflection

After this skill completes, check before closing:

1. **Did the headless Playwright flow log in and mint/delete the app token without a selector break?** A pushover.net UI change silently breaks selectors — fix them immediately if so.
2. **Did the returned token work on a test send?** A minted-but-dead token means the create flow needs fixing.

Only update if the issue is real and reproducible — not speculative.
