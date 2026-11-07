# headless-browser-tier-reminder

**Hook:** `hooks/pretooluse-headless-browser-tier-reminder.ts` · **Event:** PreToolUse (Bash orchestrator, plus throwaway Playwright MCP tool calls) · **Kind:** soft reminder, never denies · **Escape:** `HEADLESS-TIER-SKIP`

When a command starts a full browser for work that needs no window, or publishes an HTML page whose rendering is about to be checked, this hook adds a reminder to the model's context: use the lightest browser that can do the job, all driven by Vercel's [`agent-browser`](https://github.com/vercel-labs/agent-browser) CLI.

| Tier | Use                                                | Command                                                                                                                                                  | Memory (measured) |
| ---- | -------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------- |
| 1    | public pages, the default                          | `agent-browser --session S --engine lightpanda open <url>`                                                                                               | about 145 MB      |
| 2    | a login, or a page Lightpanda cannot render        | `agent-browser --session S --executable-path ~/.local/share/browser-stack/chrome-headless-shell/chrome-headless-shell [--state <login.json>] open <url>` | about 600 MB      |
| 3    | only when the real Chrome profile itself is needed | `agent-browser --session S --profile "<Profile dir>" open <url>` (a copy, deleted on close)                                                              | about 2.3 GB      |

End every job with `agent-browser close --all`.

**Lightpanda reads, it does not draw.** It returns a page's text, links and structure, but its screenshots have no CSS layout, and CJK text shows as empty boxes (example.com, 2026-11-07). A check of how a page *looks*, such as a just-published page's layout, styling or glyphs, takes a tier-2 screenshot with chrome-headless-shell.

## Why

On 2026-11-07 a machine ran out of memory with many agent sessions and desktop Chrome open, and had to be hard-rebooted. A measured trial ran the same five-page agent workload through each candidate engine, and the operator chose the three tiers above. Moli and Obscura were measured too and rejected: both used more memory than Lightpanda, and Obscura was slower and refused profiles and logins.

Agents still reach for what they know, such as a Playwright `chromium.launch()`, `npx playwright screenshot`, or branded Chrome run with `--headless`. Each of these costs tier-3 memory for tier-1 work. The decision only takes effect if the agent sees it at the moment it starts a browser, which is what this hook does.

## When it fires

A Bash command that

- **starts a heavy browser:** a Playwright `chromium|firefox|webkit.launch(…)` or `launch_persistent_context`, `connect_over_cdp`, `puppeteer.launch(…)`, `npx|bunx playwright …` or `@playwright/mcp`, `playwright screenshot|pdf|open|codegen`, or branded Chrome / Chromium with `--headless`; or
- **publishes an HTML page:** `orca artifacts share|update`, `wrangler deploy` or `wrangler pages deploy`.

It also fires on a tool call to a Playwright MCP server whose name contains `throwaway` (a signed-out full Chromium).

## When it stays silent

- **Already on the decided stack:** the command uses `agent-browser`, `lightpanda` or `chrome-headless-shell`. This includes Playwright connecting over CDP to a Lightpanda server, or launching chrome-headless-shell.
- **The real profile is involved:** the command names one (`--profile`, `--profile-directory`, `--user-data-dir`) or uses the chrome-profiles tools (`chrome-profile.sh`, `mcp-drive.ts`, `fill-secret.mjs`). Signed-in work in the operator's own Chrome is the legitimate exception.
- **The command only reads text:** it starts with `rg`, `grep`, `cat`, `sed`, `git` or a similar reader.
- **It runs inside a subagent.**
- **It already fired:** once per 20 minutes per session for each of the two kinds (launch, publish).

## Tests

`hooks/pretooluse-headless-browser-tier-reminder.test.ts` is hermetic: each test gets its own temp directory and a minimal environment, and nothing touches the network. It covers each firing pattern, each silent case, the cooldown, the reminder text (which must contain no personal detail), and `main()` run as Claude Code runs it.

Three mutants were checked by hand, and each fails the suite:

- the hook never reports a launch (12 failures);
- the "already on the stack" exemption is removed (2 failures);
- the read-only exemption is removed (3 failures).
