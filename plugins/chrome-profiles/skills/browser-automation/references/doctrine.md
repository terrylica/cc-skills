# Browser automation — the mechanics behind the rules

Reference for [`../SKILL.md`](../SKILL.md). Each section states what is true, how it was established, and what to do about it. Measurements were taken on macOS with Google Chrome 152–154 and `chrome-devtools-mcp` 1.9–1.10, `@playwright/mcp` 0.0.8x.

## Protocol is not library

CDP (Chrome DevTools Protocol) is the wire protocol; Playwright, Puppeteer and Selenium 4 are clients that speak it. `connect_over_cdp()` **is** Playwright. Moving from rung 2 to rung 3 changes **which browser** Playwright drives — bundled Chromium with automation launch flags, versus genuine Chrome — not the library. Describe the axis as _launch-a-bundled-browser vs attach-to-real-Chrome_.

## Why real Chrome beats bundled Chromium: TLS, before any JavaScript

Bundled Chromium's TLS handshake fingerprint (JA3/JA4) matches no real Chrome release, so an anti-bot origin can classify it during the handshake, before any page script runs. Stealth patches (`navigator.webdriver` and friends) act after the connection they were meant to save. If a hermetic run is blocked at connect time with no challenge page, suspect TLS and stop patching JavaScript.

## The default Chrome folder and debug ports (Chrome 136+)

`--remote-debugging-port` and `--remote-debugging-pipe` are **ignored on the default user-data folder** (hardening against cookie-stealing malware; a non-default folder gets a different encryption key). The failure is silent: a connect that hangs, or `DevTools remote debugging requires a non-default data directory`. Also silent: launching Chrome while it is already running just opens a window in the running instance and drops every flag. `--profile-directory` does not help; the check is on the user-data folder.

Consequences:

- A debug port works only with a **separate** `--user-data-dir` — a brand-new profile with no logins (sign in once there, by hand). `scripts/chrome-debug-port-control.sh` does exactly this and refuses the default folder.
- Copying your real profile into another folder does **not** carry your logins: macOS Chrome Safe Storage will not decrypt the cookie jar in a foreign folder (measured). Do not keep such copies; they are sensitive and useless.
- An open port lets any local process drive that browser and read its cookies. Close it when done; loopback only.

## Reaching your everyday Chrome: two first-party routes

### Route A — `chrome://inspect` remote debugging + `chrome-devtools-mcp --autoConnect`

Chrome 144+ can serve debugging from the default folder, gated by an in-browser opt-in: tick _Allow remote debugging_ at `chrome://inspect/#remote-debugging`. Chrome writes `DevToolsActivePort` (port, path) in the user-data folder; `--autoConnect` reads it and connects to the WebSocket.

- **Chrome asks _Allow?_ on every new connection.** Chromium's `devtools_http_handler.cc` holds the WebSocket upgrade until the dialog is answered; there is no "remember" state, focus starts on Cancel and there is no default button, and the upstream request to persist approval was closed _not planned_ ([chrome-devtools-mcp#825](https://github.com/ChromeDevTools/chrome-devtools-mcp/issues/825)). One connection lasts for the MCP process, so in practice it is one click per Claude Code session. Do not try to defeat the dialog; use route B for zero clicks.
- **No HTTP discovery in this mode.** `/json/version` returns nothing; only `--autoConnect` attaches (maintainer, [#2283](https://github.com/ChromeDevTools/chrome-devtools-mcp/issues/2283)). `--browser-url` cannot reach the everyday Chrome.
- **Always pass `--userDataDir`.** Without it, discovery is handed to Puppeteer's `channel` logic, the path seen hanging in [#2778](https://github.com/ChromeDevTools/chrome-devtools-mcp/issues/2778). The connection is lazy (first tool call), so a slow click on _Allow_ can exceed a host's tool timeout; call `list_pages` once as a warm-up.
- **It sees every profile's tabs in one list**; there is no per-profile connection ([#694](https://github.com/ChromeDevTools/chrome-devtools-mcp/issues/694)). Target by page: open the page in the right profile first, select it, and confirm the signed-in account on the page. With many open tabs, restrict scope with `--allowedUrlPattern` (Chrome 149+).
- The official Claude Code plugin of chrome-devtools-mcp registers the server with no flags (it launches a fresh Chrome). Keep your own registration for attaching.

### Route B — Microsoft's Playwright Extension + `@playwright/mcp --extension`

The extension (Chrome Web Store id `mmlmfjhmonkocbjadbfplnigmagldckm`, named _Playwright Extension_; formerly _Playwright MCP Bridge_) runs inside one profile and drives it through `chrome.debugger`. It never touches the debug port, so Chrome's _Allow_ dialog never appears.

- **Zero clicks with a token.** The extension's status page shows `PLAYWRIGHT_MCP_EXTENSION_TOKEN=<token>`; with that variable set, connections are approved automatically ([README](https://github.com/microsoft/playwright/blob/main/packages/extension/README.md)). The token is per profile and is a real credential: anything that can read it can drive that profile unattended. Keep it in the Keychain, pass it only in the MCP process's environment, and revoke it by resetting it on the status page or removing the extension.
- **Pin the profile, always.** Without `--profile-dir-name`, it connects to the _last-used_ profile that has the extension — the wrong account, whenever you last clicked elsewhere. And because folder names drift, resolve the folder from the account email at every start (that is what `chrome-profile.sh playwright-mcp <email>` does). Install the extension in the target profile only.
- **What it shows:** after attaching, Chrome draws a browser-wide bar, _"… started debugging this browser"_. Its only button cancels the session. Treat it as the visible sign that automation is live, not as something to suppress (`--silent-debugger-extension-api` would hide it for every extension).
- **Another extension's frame in the page detaches it.** Measured: a password manager's inline menu on an email field dropped the session three times running; route A finished the same form. Remedy: turn off that extension's site access for the sites you automate, set field values by script instead of keystrokes, or use route A for that page.
- **Where the token lives, and reading it without copy-paste.** The extension (v0.4.0) keeps it in its own origin's localStorage under `auth-token` (`lib/ui/authToken.js`), generating it with `crypto.getRandomValues` the first time the status page opens. Chrome stores localStorage in LevelDB: keys are `_` + origin + NUL + key, values carry a one-byte encoding prefix (1 Latin-1, 0 UTF-16LE), new writes sit in the `*.log` and older ones in `*.ldb` tables with Snappy-compressed blocks, so grepping the files finds the record only while it is still in the log. `scripts/extension-token-from-profile.ts` reads both: it copies every file except `LOCK` into a private 0700 directory (Chrome holds the lock and keeps writing), reads the newest `auth-token` record of that origin, deletes the copy, and hands the token over only on file descriptor 3 (stdout gets a status line with the length). It replaced a Python draft on `ccl_chromium_reader` (measured 2026-10-07, set aside 2026-10-12), which pulled that library unpinned from GitHub at every run; measured with that draft, the token read from the profile matched a known-good stored token byte for byte, and three new profiles went from no token to zero-click control with no operator action. Its tests run against fixtures written by real LevelDB (`scripts/fixtures/extension-token/`).
- **Claude Code's own Chrome integration is not a substitute here.** `claude --chrome` (the _Claude in Chrome_ extension over native messaging) needs no Allow dialog, but it refuses API-key and gateway logins ([docs](https://code.claude.com/docs/en/chrome)); sessions routed through a fleet gateway get no browser tools from it. Use it only in sessions signed in with `/login`.
- **No token, or a stale one, means a human click per connection.** The extension then opens `connect.html`: _"\"<client>\" is trying to connect to the Playwright Extension"_, a warning, the token in plain text, and an _Allow & select_ button. A profile with no stored token stops every run there until a person clicks, and because the page shows the token, anyone shown that page holds the credential. Remedies, all in `chrome-profile.sh`: `playwright-mcp` refuses to start without a token; `doctor` compares digests of the stored and the extension's token; `setup` replaces a stale one; `rotate-token` regenerates it after an exposure.
- **Regenerating the token locks out the old one at once**, without a browser restart (measured 2026-10-27: a run presenting the old token was refused). The new token takes about 15 s to reach the profile's files, because Chrome writes localStorage lazily; read it too early and you store the old one, which is why `rotate-token` polls until the digest changes.
- **The extension's own buttons can be pressed without a person.** System Events sees the status page's _Generate new token_ button (AXButton, description "Generate new token") and `AXPress` works on it; `rotate-token` presses it only in the one window whose title ends with `(<email>)`. Chrome's window titles end with `- Google Chrome - <profile name> (<email>)`, which Chrome's own AppleScript dictionary does not expose.
- **Look-alikes exist** ("Playwright CRX" and others). Only the id above works with `@playwright/mcp --extension`; `doctor` flags the rest.
- Keep the hermetic `playwright-throwaway-headless` server (`--headless --isolated`) and the extension servers registered separately; merging them silently moves hermetic runs onto a logged-in profile.

### Seeing every tab: Chrome's AppleScript dictionary

Neither route lists every tab cheaply: the extension sees only its own session's tabs ([playwright-mcp#1111](https://github.com/microsoft/playwright-mcp/issues/1111)), and route A costs an _Allow_ per connection. Chrome's built-in scripting, driven as JXA by `osascript`, lists every tab of every window and profile and closes one by its permanent id, with nothing to install (a nonce test opens two tabs and closes exactly those: `CHROME_TABS_LIVE=1 bun test scripts/chrome-tabs.test.ts`). `scripts/chrome-tabs.ts` is the one implementation. What it had to learn:

- **Ids are numbers in JXA and strings in argv.** A strict comparison of the two matched nothing; compare as strings.
- **Close by id, never by index**: indices shift as tabs close. The dictionary does not say which profile a window belongs to, so select by id plus URL, never by window position.
- **Errors name their cause.** -600 ("application isn't running") means the call came from outside the logged-in desktop session (ssh, a launchd job, a tmux server started from ssh); -1743 means the calling app lacks the Automation grant for Google Chrome. The -600 cause is inferred, not yet reproduced here.
- **Touching the app object of a stopped Chrome launches it**; check `running()` first.

## Chrome versions

Google lists a stable release as soon as its staged rollout begins; a given Mac may not be offered it for days, and even the downloadable installer can lag. Before telling anyone to relaunch, ask the update server what it will hand this machine (`doctor` does). Opening `chrome://settings/help` checks immediately; the relaunch then installs it.

## Why "always attach" is the wrong default

- **Not hermetic:** results depend on whatever the profile holds — a correctness problem for tests.
- **Needs a prepared browser:** breaks cron, CI and unattended runs.
- **Poor concurrency:** one shared cookie jar.
- **Blast radius:** a wrong selector acts as you, on every site in that profile.

And the best browser is usually none: reaching for rung 3 against server-rendered HTML means rung 1 was skipped.

## Operational rules

- **Submit with `form.requestSubmit()`**, not a synthetic `.click()`, which can silently miss the page's handlers. A form whose fields are still filled after "submitting" was never posted.
- **Never accept on-page text as proof** of a state change; re-read the state independently, and prove the negative (for a credential change: the new value works _and_ the old one is refused).
- **Do not close contexts you did not create.** Closing a context obtained from an attached browser can terminate the browser itself.
- **Login forms carry autofill decoys.** Their being filled is normal browser behaviour, not a bot signal; assert that the real fields hold exactly the intended values.
- **Check `maxlength` before submitting a secret;** silent truncation stores a different credential while the confirm field still matches.
- **Fail closed on auth.** On a captcha, 2FA prompt or unexpected page, stop and look; retry loops lock accounts.
- **A value captured off a page is a guess until something downstream accepts it.** Measured 2026-10: a script that lifted a one-time generated credential out of a dialog with an unanchored text pattern stored a wrong 16-letter string, and the service then refused it as bad credentials, which looked like an account problem. Accept only an element whose WHOLE text is the expected shape, refuse when more than one matches, and prove the stored value by using it before calling the step done.
- **Some app frameworks ignore script-set text.** Measured 2026-10 in a large admin console: `execCommand('insertText')` into a dialog's textareas persisted for some fields and silently not for others (the field looked filled, Save succeeded, the value was empty on re-open). Fill through the automation server's own typing tool, then re-open the saved object and read the value back.
- **Custom listboxes need real input.** Synthetic `mousedown/click` events on `role=option` elements may do nothing, and options outside the popup's scroll area are "not interactive". Click the listbox with the automation tool, then move with ArrowDown and press Enter, reading `document.activeElement` to confirm which option has focus.
- **A wizard's review step is the truth, not the checkboxes.** Measured 2026-10 in a large admin console's rule editor: ticking a dependent checkbox (a recipient) right after a sibling (a notification channel) re-rendered the panel, the second click failed as "not interactive", and after going Back and ticking it again the box showed checked while the review step still said the notification was Off. Cancel and start the wizard over rather than repair it; tick the dependent box first, re-snapshot, then the sibling; and read the review summary before saving. Menu items such as "View rule" may open a new tab: list tabs after clicking and close the extras you made.
- **Read many detail pages through same-origin iframes, polled from page state.** One evaluate call that loops over dozens of pages hits the protocol timeout; start the loop, store results on `window`, return at once, and poll. Wait for the field you need, not a fixed delay.
- **Map tabs to windows before closing any.** Closing the last tab of a profile's window closes that window; `tabs close` refuses that unless `--allow-window-close`. Keep one tab per profile window and navigate it somewhere useful instead.
- **Volume, not automation, is what anti-bot sites punish.** Measured: a sequential scrape at one request per 2 s was IP-blocked after ~212 requests; a handful of authenticated actions on the same site over rung 3 drew no challenge. Bound the request count.
