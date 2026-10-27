---
name: browser-automation
description: Let Claude Code drive a browser with the least friction and the right identity on macOS - pick the rung (no browser > hermetic Playwright launch > your real signed-in Chrome), and for your everyday Chrome use the standing tools instead of hand-rolling a launch - chrome-profile.sh setup/doctor/open/tabs/rotate-token (choose a profile by ACCOUNT EMAIL, Microsoft's Playwright Extension with a stored token for zero-click control, list and close any tab of any profile), the chrome-main auto-connect server, and chrome-debug-port-control.sh for a separate profile on a debug port.
when_to_use: TRIGGERS - browser automation, drive Chrome, signed-in Chrome profile, Chrome profile by email, Playwright extension, Playwright MCP, chrome-devtools MCP, autoConnect, chrome://inspect remote debugging, remote debugging port, attach to Chrome, connect_over_cdp, headless Chrome, scrape a page that needs JavaScript, logged-in site automation, Allow remote debugging dialog, Playwright extension connect page, Allow & select, leftover tabs, close tabs, too many tabs, extension token exposed, anti-bot.
---

# Browser automation

> **Self-Evolving Skill**: This skill improves through use. If a step is wrong, Chrome or an MCP server changed behaviour, or a workaround was needed — fix this file (and `scripts/chrome-profile.sh`) immediately, don't defer. Only update for real, reproducible issues, and never add a real account, profile folder name or token.

Procedure here; the mechanics and measurements behind each rule are in [`references/doctrine.md`](references/doctrine.md). Scripts are in this plugin's `scripts/`; resolve the path with `cc-plugin-root chrome-profiles` (or use `~/.claude/plugins/marketplaces/cc-skills/plugins/chrome-profiles/scripts/`).

```bash
CP="$(cc-plugin-root chrome-profiles)/scripts/chrome-profile.sh"
```

## 1. Pick the rung — start at the top

| Rung                                  | Mechanism                                                                                                                                                            | Use when                                                                                                                            |
| ------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------- |
| 0. **An API or OAuth token**          | the site's API with a scoped, short-lived token from the vault/Keychain                                                                                              | The site has an API for the job. **No browser at all**: the most reliable and the safest identity.                                  |
| 1. **No browser, plain HTTP**         | `curl` / `httpx`                                                                                                                                                     | The page renders server-side.                                                                                                       |
| 2. **A browser with its own profile** | the `playwright-throwaway-headless` MCP server or `chromium.launch()` (throwaway); a per-tool, sign-in-once profile on a debug port (`chrome-debug-port-control.sh`) | You need JavaScript; and, if a login is needed, the tool signs in once in **its own** profile. The default for anything unattended. |
| 3. **Your real Chrome**               | the servers below                                                                                                                                                    | Supervised work that needs **your own signed-in session**, or a site that blocks automated browsers.                                |

## Who signs in, and how

- **Unattended work never runs in your real profile.** It uses rung 0, or a per-tool profile (rung 2) that holds only the one site it needs, so a mistake or a hostile page can reach that site and nothing else. This is how the agent platforms do it too (Browserbase _Contexts_, Steel and Kernel _Profiles_).
- **Your real profile (rung 3) is for work you are watching or have explicitly asked for.** It acts with every session in that profile at once.
- **When a per-tool profile's session expires, refill the login from the Keychain or vault, never by having the AI read or type the password**:

  ```bash
  node "$(cc-plugin-root chrome-profiles)/scripts/fill-secret.mjs" --port 9222 --page <url-part> \
    --selector '#password' --keychain <service>:<account> [--submit]     # or --vault <scope>:<key>
  ```

  It reads the secret inside its own process, types it into exactly one field of exactly one tab, and prints only a character count. It refuses a field too short for the secret (which would silently save a truncated one), an ambiguous selector, or a missing secret. 2FA and passkeys still need a person.

## 2. Before any rung-3 work: run the doctor

```bash
bash "$CP" doctor [<account-email>]
```

It checks: Chrome against the latest stable release (and whether Google is actually offering it to this Mac yet); whether `chrome://inspect` remote debugging is ON; the shape and the target account of every browser MCP server, in `~/.claude.json` (every session) and in the on-demand file `~/.claude/mcp-browser.json` (loaded only with `claude --mcp-config ~/.claude/mcp-browser.json`; when that file exists, `setup` registers there, because Claude Code starts a private copy of every user-scope server in every session and a browser server holds 0.1–0.9 GB); that the email is signed in to **exactly one** profile; that the token is stored; and that no look-alike "Playwright …" extension is standing in for the real one. Fix what it flags before acting.

## 3. Choose the profile by ACCOUNT EMAIL — never by folder name

Chrome names profile folders itself (`Default`, `Profile 7`), differently on every machine, and renames them when a profile is rebuilt. A server pinned to a folder name drifts onto a different account without any error. So everything here takes an email and resolves it at the moment of use, refusing if zero or several profiles match.

```bash
bash "$CP" resolve <email>          # → the folder name, or a clear failure
bash "$CP" open <email> <url>       # open a page in THAT profile of the running Chrome (no debug flags)
```

## 4. Set up once, then automate with no clicks

```bash
bash "$CP" setup <email>            # per account you want automated
bash "$CP" setup-main               # optional: one server that sees every profile's tabs
```

`setup <email>`: resolves the profile → opens the Chrome Web Store page for Microsoft's **Playwright Extension** in that profile only (you click _Add to Chrome_) → opens the extension's status page, which makes the extension create its token, and reads that token from the profile's own Local Storage (`scripts/extension-token-from-profile.ts`, on a private copy; nothing to paste) → stores it in the login Keychain → a hidden macOS dialog asks for the token only when it cannot be read (`setup` says why) → registers an MCP server (default name `chrome-<local part of the email>`) that starts `@playwright/mcp --extension` pinned to that profile. **Restart Claude Code** so the new tools load.

| Server                                                                                  | Reaches                                                                                                                                                                       | Clicks                                                                                                                                                       |
| --------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `chrome-<name>` (from `setup`)                                                          | ONE profile, resolved by email at every start                                                                                                                                 | **None**, once the token is stored. With no token or a stale one the extension opens a "… is trying to connect" page that waits for a person; `playwright-mcp` now refuses instead and `doctor` flags drift, so fix it with `setup <email>`, never by clicking _Allow & select_. Chrome shows a "started debugging this browser" bar while attached — leave it |
| `chrome-main` (from `setup-main`)                                                       | Every profile's tabs in one list. Target a page by opening it with `open <email> <url>` first, then selecting it; confirm the signed-in account **on the page** before acting | Chrome's **Allow** dialog, once per Claude Code session. It cannot be remembered (by design)                                                                 |
| `playwright-throwaway-headless` (`npx -y @playwright/mcp@latest --headless --isolated`) | Its own throwaway browser (rung 2), in memory, no window                                                                                                                      | None                                                                                                                                                         |

Prefer `chrome-<name>` for unattended work. Use `chrome-main` when you need DevTools-level inspection (network, performance) or a page in a profile you have not set up.

### No restart needed: drive a server from Bash

When the server you need is registered on demand (in `~/.claude/mcp-browser.json`) and this session did not load it, do not restart Claude Code. `scripts/mcp-drive.ts` starts it as a stdio process and runs a JSON list of tool calls:

```bash
D="$(cc-plugin-root chrome-profiles)/scripts/mcp-drive.ts"
bun "$D" ext <account-email> steps.json   # that profile's extension server: stored token, no Allow dialog
bun "$D" cdp steps.json                   # chrome-devtools-mcp --autoConnect: every profile's tabs (Allow once)
```

Each step is `{"tool": "...", "args": {...}, "quiet": true|false, "max": N}`; `quiet` prints only ok/ERROR and a length. In `cdp` mode `{{uid:REGEX}}` and `{{page:REGEX}}` resolve against the last `take_snapshot` / `list_pages` of the same run (page ids are renumbered per connection, so never reuse one from an earlier run). Use `cdp` for a profile that has no extension installed.

Two things learned driving it (2026-10-18):

- **Every `ext` run attaches to a fresh tab**, so a multi-step form (a wizard, a reveal) must run inside ONE `browser_run_code_unsafe` step with Playwright locators, re-navigating at its start.
- **That code runs in a sandbox with no `process` and no dynamic import**, so it cannot hand a secret to a local process. Never return a secret from a step. Write it out of the page as a Blob download, then `vault set --stdin` from the file and `rm -P` it; avoid the clipboard, whose history managers keep a copy.

### Tabs: every run closes what it opened

The extension server sees only its own session's tabs, so tabs a run leaves behind are invisible to it and pile up in the operator's Chrome. Three tools, all on Chrome's own AppleScript (no extension, no debug port, no dialog):

```bash
bash "$CP" tabs list [--json] [--url-match <re>]                  # every tab of every profile: window id, tab id, URL, title
bash "$CP" tabs close --id <tabId> [--id …] [--dry-run]            # exact ids only; refuses ids that are not open
bash "$CP" tabs close --url-match <re> [--max n]                   # refuses more than --max matches (default 1)
bash "$CP" rotate-token <email>                                    # after a token was exposed: new token, stored, page closed
```

`tabs close` refuses to empty a window unless `--allow-window-close` (closing a profile's last tab closes its window). `mcp-drive.ts` lists tabs before and after every run and closes the ones that appeared on a host named in its steps, plus the extension's connect page; `MCP_DRIVE_NO_SWEEP=1` turns that off. Never hand-write a JSON-RPC client instead of `mcp-drive.ts`: an ad-hoc client closes at most its own tab and leaks the rest. These need a terminal inside the Mac's desktop session (Orca, Terminal); from ssh or launchd osascript fails with -600, which `tabs` names.

## 5. Things that will bite

- **The throwaway server must be headless, isolated and named as such.** Registered as plain `playwright`, it opened a visible, signed-out Chrome window (with an "unsupported command-line flag: --disable-blink-features=AutomationControlled" bar) in every session that called it, and since its tools share names with the signed-in extension servers, sessions wanting your signed-in profile picked it by mistake. `doctor` flags a throwaway registration without `--headless --isolated` or without `throwaway` in its name.
- **Install the extension in the target profile only.** Every profile that has it is drivable by anything holding its token.
- **A password manager's inline menu can break the extension's connection** (another extension's frame in the page detaches it). Turn off that extension's site access for the sites you automate, or finish that page through `chrome-main`. Measured 2026-10-18 on an email "chips" field in the Google Cloud console: even a scripted `fill` detached it, because the field took focus. What worked without focus: set the value through the element, dispatch `input`, then dispatch a synthetic `keydown` Enter whose `keyCode` is defined as 13.
- **Set form values by script rather than synthetic keystrokes** when a field misbehaves; it also stops autofill pop-ups from opening. For a message, fill the whole text once, read the field back and compare it (whitespace-normalised) with the intended text, and only then press Send; clear the field and stop on a mismatch, then confirm the message in the thread afterwards.
- **Nobody uses the automated window while a run is going.** A person clicking in that window moves focus and breaks the run. Tell the operator which window is in use (or give the run its own window) before starting.
- **Never trust on-page "success" text** for a state change. Re-read the state, and prove the negative.
- **Never script a fresh debugging connection per command against your everyday Chrome.** Each new connection through `chrome://inspect` costs the operator one _Allow_ click; a stopgap client that reconnected per call raised about fifteen in one session (2026-10-07). If a profile has no `chrome-<name>` server, run `setup <email>` for it instead: when the extension is already installed it needs no click and no paste.
- **Never retry a login form** on a surprise (captcha, 2FA, odd page): stop and look.
- **Secrets never pass through the chat.** Download or read them into the Keychain/vault by script, and print only lengths.
- **"Chrome is being controlled by automated test software"** appears only on browsers that automation _launched_ (rung 2); your everyday Chrome never shows it.

## 6. A separate profile on a debug port (no Allow dialog, not your logins)

For a sign-in-once automation profile that never touches your everyday Chrome:

```bash
P="$(cc-plugin-root chrome-profiles)/scripts/chrome-debug-port-control.sh"
bash "$P" up       # port 9222, profile ~/.local/share/chrome-debug-profile (CHROME_DEBUG_PROFILE / CHROME_DEBUG_PORT to change)
bash "$P" status   # reports the profile ACTUALLY attached
bash "$P" down     # always, when done — an open port lets any local process read that profile's cookies
```

It refuses the default Chrome folder, because Chrome 136+ silently ignores `--remote-debugging-port` there. Connect with `--browser-url=http://127.0.0.1:9222` or `connect_over_cdp`. Never bind the port beyond loopback.

## Post-Execution Reflection

After this skill completes, check before closing:

1. **Did `doctor` agree with what actually happened?** If a server connected to the wrong account, or a check passed while the route failed, fix the check in `chrome-profile.sh`.
2. **Did any click or dialog appear that this skill said would not?** Record the Chrome or extension version and the cause in `references/doctrine.md`.
3. **Did a secret pass through the conversation?** If so, rotate it and fix the step that exposed it.

Only update if the issue is real and reproducible — not speculative.
