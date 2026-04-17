# gemini-deep-research Plugin

> Gemini Deep Research via browser automation: Playwright CDP, 8-step flow, 40k+ char reports.

**Hub**: [Root CLAUDE.md](../../CLAUDE.md) | **Sibling**: [plugins/CLAUDE.md](../CLAUDE.md)

## Overview

Automates Google's Gemini Deep Research through Chrome DevTools Protocol (CDP). Connects to a persistent Chrome instance, drives the Gemini web UI through the full Deep Research workflow, and extracts the final markdown report.

## Architecture

```
plugins/gemini-deep-research/
├── CLAUDE.md                           # This file
├── skills/
│   └── research/
│       └── SKILL.md                    # Main skill (CLI + programmatic usage)
└── scripts/
    ├── research.ts                     # Unified CLI entrypoint
    ├── client.ts                       # GeminiDeepResearchClient class
    ├── selectors.ts                    # CSS selector registry (13 groups)
    └── probes/
        ├── dom-inspector.ts            # DOM probing (5 commands)
        ├── research-monitor.ts         # Execution monitor + share probe
        └── share-link.ts              # Share link extraction
```

## Prerequisites

- **Chrome**: Running with `--remote-debugging-port=9222`
- **Auth**: Logged into gemini.google.com with Gemini Advanced subscription
- **Runtime**: `playwright-core` (Bun or npm)

## Automation Flow

1. Connect to Chrome via CDP (port 9222)
2. Navigate to `gemini.google.com/app`
3. Activate Deep Research mode (Tools → Deep research chip)
4. Type query (30ms/char) + send
5. Wait for research plan (~18-120s)
6. Confirm/start research (auto or manual)
7. Poll for completion (mic button + text stability, 30min max, 5s intervals)
8. Extract report + optional share link + Firecrawl scrape

## Conventions

- **Selector SSoT**: `scripts/selectors.ts` — all CSS selectors centralized, verified dates in comments
- **Completion signal**: Mic button reappearance (not spinner disappearance)
- **Report extraction**: Longest `.markdown.markdown-main-panel` element (report is 40k+, plan is ~1.3k)
- **Text stability**: 3 consecutive identical lengths before marking done

## Key Paths

| Resource       | Path                   |
| -------------- | ---------------------- |
| CLI entrypoint | `scripts/research.ts`  |
| Client class   | `scripts/client.ts`    |
| Selectors      | `scripts/selectors.ts` |
| Debug probes   | `scripts/probes/`      |

## Dependencies

| Package         | Purpose                           |
| --------------- | --------------------------------- |
| playwright-core | Browser automation via Chrome CDP |
| tsx             | TypeScript execution (dev)        |

## Cross-References

- Firecrawl scraping: [devops-tools](../devops-tools/CLAUDE.md) (self-hosted Firecrawl patterns)

## Skills

- [research](./skills/research/SKILL.md)
