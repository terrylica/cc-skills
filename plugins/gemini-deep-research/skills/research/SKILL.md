---
name: gemini-deep-research
description: Run Gemini Deep Research via browser automation. Persistent Chrome on CDP port 9222. Use when user asks to research a topic with Gemini, run deep research, or wants comprehensive AI-powered research reports. TRIGGERS - Gemini research, deep research, research report, Gemini Deep Research
allowed-tools:
  - Bash
  - Read
  - Write
  - Glob
  - Grep
---

# Gemini Deep Research

Run long-form research queries through Google's Gemini Deep Research via browser automation (Playwright CDP). Produces 40k+ char markdown reports with source citations.

## Prerequisites

1. **Chrome with debug port**: Must be running with `--remote-debugging-port=9222`
2. **Gemini Advanced subscription**: Logged into gemini.google.com in the debug Chrome
3. **playwright-core**: `bun add -g playwright-core` (or project-local)
4. **Runtime**: Use `npx tsx` (not `bun run`) — Bun's CDP connectOverCDP times out; Node.js connects in <1s

### Launch Chrome (if not running)

```bash
/Applications/Google\ Chrome.app/Contents/MacOS/Google\ Chrome \
  --remote-debugging-port=9222 \
  --user-data-dir="/tmp/gemini-research-profile" \
  "https://gemini.google.com/app" &
```

Then log in manually with a Gemini Advanced account.

## Usage

### CLI (direct)

```bash
# Health check — verify Chrome CDP + Gemini login
npx tsx {{skill_dir}}/scripts/research.ts --health

# Basic research (runs preflight automatically)
npx tsx {{skill_dir}}/scripts/research.ts "your research query"

# Save to specific file
npx tsx {{skill_dir}}/scripts/research.ts \
  --output /tmp/report.md \
  --timeout 45 \
  "comprehensive analysis of quantum computing error correction 2025-2026"

# Auto-save to directory (creates {date}-{slug}.md)
npx tsx {{skill_dir}}/scripts/research.ts \
  --output-dir ~/.claude/automation/gemini-deep-research/output \
  "your query"

# Without auto-confirming plan (lets you review first)
npx tsx {{skill_dir}}/scripts/research.ts --no-confirm "query"
```

### Programmatic (import)

```typescript
import { GeminiDeepResearchClient } from "{{skill_dir}}/scripts/client.js";

const client = new GeminiDeepResearchClient({
  cdpUrl: "http://127.0.0.1:9222",
  maxResearchTimeMs: 30 * 60 * 1000,
  autoConfirm: true,
  onProgress: (msg) => console.log(msg),
});

await client.init();
const result = await client.research("your query");
// result.report — full markdown report (40k+ chars)
// result.plan — research plan text
// result.completed — boolean
// result.durationMs — execution time
// result.shareLink — Gemini share URL (if Firecrawl enabled)
await client.close();
```

## Preflight

Every research run starts with an automatic preflight health check that verifies:

1. **Chrome CDP reachable** on configured port
2. **Browser connection** via WebSocket succeeds
3. **Gemini page open** at gemini.google.com
4. **Login state OK** (not showing sign-in wall)

If any check fails, research aborts with a clear error message. Use `--no-preflight` to skip.

## Automation Flow

```
Preflight (CDP + login check) → abort if unhealthy
    ↓
Chrome CDP:9222 → Navigate gemini.google.com/app
    ↓
Tools button → Deep Research drawer item → Active chip verification
    ↓
Type query (30ms/char) → Send button (or Enter fallback)
    ↓
Wait for research plan (~18-120s) → Extract plan text
    ↓
Auto-confirm "Start research" (or manual)
    ↓
Poll completion: mic button + text stability (5s intervals, 30min max)
    ↓
Extract report (longest .markdown element) → Optional share link + Firecrawl
```

## Debug Probes

When selectors break (Google updates Gemini UI), use the probe scripts:

```bash
# Check Chrome connectivity
bun run {{skill_dir}}/scripts/probes/dom-inspector.ts status

# Test all selectors against live DOM
bun run {{skill_dir}}/scripts/probes/dom-inspector.ts selectors

# Full DOM inspection
bun run {{skill_dir}}/scripts/probes/dom-inspector.ts probe

# Monitor active research execution
bun run {{skill_dir}}/scripts/probes/research-monitor.ts confirm-and-monitor

# Check research completion + extract share link
bun run {{skill_dir}}/scripts/probes/share-link.ts status
bun run {{skill_dir}}/scripts/probes/share-link.ts extract
```

## Selector Registry

All CSS selectors live in `scripts/selectors.ts`. When Google updates the Gemini UI:

1. Run `dom-inspector.ts selectors` to identify broken selectors
2. Run `dom-inspector.ts probe` to inspect current DOM
3. Update `selectors.ts` with new selectors
4. Re-test with `dom-inspector.ts selectors`

Selectors last verified: **2026-03-13** (Tools button: now `button.toolbox-drawer-button`, aria-label removed)

## Key Files

| File                                 | Purpose                                          |
| ------------------------------------ | ------------------------------------------------ |
| `scripts/research.ts`                | Unified CLI entrypoint                           |
| `scripts/client.ts`                  | `GeminiDeepResearchClient` class                 |
| `scripts/selectors.ts`               | CSS selector registry (13 groups with fallbacks) |
| `scripts/probes/dom-inspector.ts`    | DOM probing (5 commands)                         |
| `scripts/probes/research-monitor.ts` | Research execution monitor                       |
| `scripts/probes/share-link.ts`       | Share link extraction                            |

## Options Reference

| Option              | Default                 | Description                                 |
| ------------------- | ----------------------- | ------------------------------------------- |
| `cdpUrl`            | `http://127.0.0.1:9222` | Chrome CDP endpoint                         |
| `maxResearchTimeMs` | `1800000` (30 min)      | Max wait for research completion            |
| `pollIntervalMs`    | `5000` (5s)             | How often to check for completion           |
| `autoConfirm`       | `true`                  | Auto-click "Start research" on plan         |
| `enableFirecrawl`   | `false`                 | Extract share link + scrape via Firecrawl   |
| `firecrawlUrl`      | `http://localhost:3002` | Self-hosted Firecrawl endpoint              |
| `--no-preflight`    | (preflight runs)        | Skip automatic health check before research |

## Completion Detection

Research completion is detected via three signals:

1. **Mic button visible** — `button[data-node-type="speech_dictation_mic_button"]` reappears
2. **Report text > 500 chars** — longest `.markdown.markdown-main-panel` element
3. **Text stability** — 3 consecutive identical text lengths (15s total)

The spinner may remain visible as a stale artifact after completion — the mic button is the primary signal.


## Post-Execution Reflection

After this skill completes, check before closing:

1. **Did the command succeed?** — If not, fix the instruction or error table that caused the failure.
2. **Did parameters or output change?** — If the underlying tool's interface drifted, update Usage examples and Parameters table to match.
3. **Was a workaround needed?** — If you had to improvise (different flags, extra steps), update this SKILL.md so the next invocation doesn't need the same workaround.

Only update if the issue is real and reproducible — not speculative.
