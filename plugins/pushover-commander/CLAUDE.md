# pushover-commander — plugin SSoT

Hub: [`../CLAUDE.md`](../CLAUDE.md) · Siblings: [gmail-commander](../gmail-commander/CLAUDE.md) · [calcom-commander](../calcom-commander/CLAUDE.md) · [devops-tools](../devops-tools/CLAUDE.md)

The single home for all Pushover automation. Migrated + consolidated 2026-06-05
from the orphaned private `~/.claude/po-plugin` (`po` suite) **plus** the
`pushover-verbatim-notify` skill formerly in `devops-tools` — so any future
Claude Code session finds every Pushover capability in one registered place.

## Public-tool / private-config split (READ FIRST)

This plugin is **public + generic** — it contains NO account email, 1Password item
ID, app token, or operator-specific app→repo map. All per-user secrets/config live
**privately under `~/.claude`** and are read via env vars:

- Private config (gitignored, per-user): `~/.claude/pushover-commander.private/pushover-commander.local.env`
  (template: [`skills/_lib/pushover-commander.local.env.example`](skills/_lib/pushover-commander.local.env.example)).
- `skills/_lib/resolve_pushover_secret.sh` sources it, then reads
  `op://$PUSHOVER_OP_VAULT/$PUSHOVER_OP_ITEM/<field>` (1Password) with a macOS
  Keychain fallback. Fails loud if neither is configured.
- Fork users: copy the `.example`, point it at their own 1Password item — done.
- Full guide: [`skills/_lib/references/private-config-setup.md`](skills/_lib/references/private-config-setup.md).

## File map

| Path                                                                  | Role                                                                                             |
| --------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------ |
| `skills/send-notification/`                                           | quick send (+image) via the TS core                                                              |
| `skills/emergency-priority2-receipt/`                                 | priority-2 repeat-until-ack + receipt poll                                                       |
| `skills/manage-apps-and-sounds-headless/`                             | **headless pushover.net login + create/delete apps (mints token) + sounds**                      |
| `skills/custom-sounds/`                                               | enumerate/validate/upload custom sounds                                                          |
| `skills/render-incident-report-image/`                                | monospace incident-report PNG (word-wrapped)                                                     |
| `skills/verbatim-audit-notify/`                                       | UUID+JSONL audit sender + lookup/prune/quota/heartbeat (+ launchd templates)                     |
| `skills/loop-briefing/`                                               | `/loop` block/done briefings                                                                     |
| `skills/health-check/`                                                | doctor / quota                                                                                   |
| `skills/_lib/pushover_core.ts`                                        | Bun/TS core: send · emergency · sounds · render · loop-brief · doctor · quota (Satori→resvg PNG) |
| `skills/_lib/pushover_headless_web_control.ts`                        | Playwright (Bun/TS) headless dashboard: `apps/create-app/delete-app/edit-app/sounds`             |
| `skills/_lib/chrome_for_testing_resolver.ts`                          | Playwright-free lookup of the newest Chrome for Testing; shared by web-control and `doctor`      |
| `skills/_lib/pushover_headless_web_control.test.ts`                   | `bun test`: browser selection, fallback, `doctor` deps, import safety on a root-only install     |
| `skills/_lib/resolve_pushover_secret.sh`                              | env/1Password/Keychain credential resolver (generic)                                             |
| `skills/_lib/batch_create_pushover_apps.ts`                           | batch create apps from a plan JSON (reuses web-control helpers)                                  |
| `skills/_lib/{make_app_icon.py,make_custom_sound.sh,find_jingles.sh}` | icon/sound sourcing pipeline                                                                     |
| `skills/_lib/pushover_api_limits.json`                                | SSoT for Pushover caps + silent-failure rules                                                    |
| `skills/_lib/references/`                                             | app-naming scheme (generic template), device calibration + API limits, private-config setup      |

## The headless app-creation flow (why it exists)

Pushover has **no API to create an application token** — it is a deliberate,
website-only action. To mint one programmatically:

```bash
# creds come from your private config via resolve_pushover_secret.sh
export PO_EMAIL="$(bash "$(cc-plugin-root pushover-commander)/skills/_lib/resolve_pushover_secret.sh" login_email)"
export PO_PW="$(bash "$(cc-plugin-root pushover-commander)/skills/_lib/resolve_pushover_secret.sh" login_password)"
export PO_USER="$(bash "$(cc-plugin-root pushover-commander)/skills/_lib/resolve_pushover_secret.sh" user_key)"
env -u HTTPS_PROXY -u HTTP_PROXY \
  bun "$(cc-plugin-root pushover-commander)/skills/_lib/pushover_headless_web_control.ts" create-app --name "my-app" --reveal
```

Drives **Playwright's "Google Chrome for Testing.app" by default, never the operator's own Google Chrome**; pushover.net login is plain email/password (no CAPTCHA/2FA, verified 2026-05-30), so plain Playwright + selectors suffice.

### Browser selection — why not system Chrome (2026-09-22)

The script used to launch `chromium.launch({ channel: "chrome" })`, i.e. a second instance of `/Applications/Google Chrome.app` on a throwaway profile. Both instances share the bundle id `com.google.Chrome`, and on 2026-09-22 that second instance collided with the operator's running Chrome in macOS LaunchServices: links stopped opening anywhere and every Chrome had to be force-quit. Chrome for Testing is a separate bundle (`com.google.chrome.for.testing`), so LaunchServices never confuses the two.

- `--browser cft|chrome` (flag) beats `PUSHOVER_WEB_BROWSER=cft|chrome` (env), which beats the default `cft`. `batch_create_pushover_apps.ts` reads the env var.
- `cft` resolves the **numerically highest** `chromium-<N>` under `~/Library/Caches/ms-playwright` (or `PLAYWRIGHT_BROWSERS_PATH`) that holds `chrome-mac*/Google Chrome for Testing.app/Contents/MacOS/Google Chrome for Testing`, launched by `executablePath`. `chromium_headless_shell-*` and `chromium-tip-of-tree-*` are skipped. The resolver is `resolveChromeForTestingExecutable(cacheRoot)` in `chrome_for_testing_resolver.ts`, which imports only `node:` builtins so `doctor` can use it without loading Playwright; it is tested against a temp directory.
- `po doctor` reports this browser, not the operator's: `deps.chrome_for_testing` is `ok (<executable>)` or `MISSING — install once: <command>`, and `deps.chrome_system_fallback` reports `/Applications/Google Chrome.app` as what a run falls back to. Until 2026-09-22 it had a single `deps.chrome` key for `/Applications/Google Chrome.app`. That key was wrong both ways once cft became the default: it said MISSING where the web-control worked, and ok where every run fell back.
- **Default and none installed:** falls back to `channel: "chrome"` with a loud stderr banner naming the LaunchServices risk and the install command. Never silent.
- **Explicit `cft` and none installed:** exits 1 with the install command. The browser is resolved before credentials, so this needs no secrets to diagnose.
- Install Chrome for Testing once, with this plugin's own pinned `playwright-core`: `(cd "$(cc-plugin-root pushover-commander)/skills/_lib" && bunx playwright-core install chromium)`.

### Importable modules

Every CLI in `skills/_lib/` (`pushover_headless_web_control.ts`, `batch_create_pushover_apps.ts`, `pushover_core.ts`, `pushover_inbox.ts`) runs only under `if (import.meta.main)`. Before 2026-09-22 the web-control module called `main()` at import, so `batch_create_pushover_apps.ts` — which imports its `login`/`createApp`/`editApp`/`withDashboard` helpers — ran a second CLI as a side effect that parsed the batch's argv, logged in on its own, and could `process.exit()` the batch mid-run. Keep new modules guarded; `pushover_headless_web_control.test.ts` imports each one in a child process and fails if anything runs.

## Conventions

- All Pushover HTTPS + `op` calls run with `env -u HTTPS_PROXY -u HTTP_PROXY` (the
  sandbox MITM proxy 502s on api.pushover.net / 1Password).
- `bun install --frozen-lockfile` in `skills/_lib/` provides Satori, @resvg/resvg-js and playwright-core; `node_modules/` is gitignored. Only `render`/`loop-brief` need Satori and resvg, and `pushover_core.ts` loads them on first use (`loadRenderer()`), so `send`, `emergency`, `sounds`, `quota`, `doctor` and any import of the module need no plugin-local package; a missing install fails `render` with the install command. The web-control needs playwright-core and, once, Chrome for Testing (see "Browser selection" above).
- Tests: `bun test plugins/pushover-commander/skills/_lib/` from the repo root. They are also picked up by `moon run repo:test`, which runs every tracked `*.test.ts`. No test launches a browser or reaches the network.
- 🔴 **Tests must pass on a checkout that ran ONLY the repo-root `bun install`.** `repo:test` installs nothing per plugin, and every branch is a fresh worktree, so a test that needs `skills/_lib/node_modules` turns the whole `repo:check` gate red on every new branch. Never import a plugin-local package at the top of a module a test imports: load it where it is used, as `loadRenderer()` does. A test proves `pushover_core.ts` imports against a copy of `_lib` with no packages at all. The web-control's `playwright-core` import resolves, on a root-only install, from the repo root's own `playwright-core` dependency; if that root dependency is ever dropped, its tests need the same treatment.
- State (audit JSONL) defaults to `~/.local/state/pushover/` (env `PUSHOVER_AUDIT_PATH`).
- Never hardcode tokens; never commit the private config or the app-token cache.
