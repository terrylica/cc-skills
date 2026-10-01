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
- **Look-alikes exist** ("Playwright CRX" and others). Only the id above works with `@playwright/mcp --extension`; `doctor` flags the rest.
- Keep the hermetic `playwright` server and the extension servers registered separately; merging them silently moves hermetic runs onto a logged-in profile.

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
- **Volume, not automation, is what anti-bot sites punish.** Measured: a sequential scrape at one request per 2 s was IP-blocked after ~212 requests; a handful of authenticated actions on the same site over rung 3 drew no challenge. Bound the request count.
