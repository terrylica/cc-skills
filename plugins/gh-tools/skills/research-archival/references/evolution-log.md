# Evolution Log

Reverse chronological — newest entries on top.

## 2026-08-13 — Retire self-hosted Firecrawl; route everything JS-rendered to the public API

- The littleblack deployment was **found alive**, not dead as assumed — HTTP 200 in 21 ms, 5 containers up 5 weeks. Retired deliberately rather than declared dead: containers, images, volumes and build cache removed, reclaiming ~18 GB (61.99 → 44.04 GB). Port 3002 now refuses connections. sub2api and clickhouse-server on the same host were preserved.
- Replaced the health-check + auto-revival + WORKER-STALLED machinery with a single `POST https://api.firecrawl.dev/v2/scrape`. The public API needs no key and has no host to be down, so there is nothing to probe and nothing to restart; failures are handled per request.
- **Reversed the 2026-02-09 decision** to route `chatgpt.com/share/*` to Jina Reader. Measured on two share links: Jina returned 9,397 and 15,960 chars vs Firecrawl's 57,616 and 136,590 — 17% and 12% coverage — and truncated mid-sentence (one ended `"I would spend money on **Synol"`), while Firecrawl reached the true footer. The gap was real content: 76 vs 12 headings, 128 vs 22 table rows. The February escaped-markdown complaint no longer reproduces on v2.
- Jina requires `-H "x-timeout: 30"`; without it a JS-rendered page returns ~321 bytes of login chrome that reads like a successful scrape.
- Switched v1 → v2. Note the `search` shape differs (`v1: data: [...]` vs `v2: data: {web: [...]}`) — do not swap versions without changing the parser.

## 2026-02-13 — Add Firecrawl health check + auto-revival to scraping workflow

- Firecrawl containers can show "Up" while internal processes are dead (RAM/CPU overload: `WORKER STALLED cpuUsage=0.998 memoryUsage=0.858`)
- Added 3-step deep health check: Tailscale ping → API HTTP probe → log inspection
- Added auto-revival: `docker restart` with 20s wait and verification
- Escalation path: restart → force-recreate → manual intervention → Jina fallback
- Added "Container Up but dead" failure mode documentation with diagnosis and fix
- Added troubleshooting rows: "Firecrawl Up but dead", "WORKER STALLED", "Jina login page shell"
- Fixed frontmatter-schema.md: `chatgpt-share` scraper corrected from Firecrawl to Jina Reader (missed in 2026-02-09)
- Discovery: Gemini deep research scrape failed because Firecrawl was dead for 4+ days undetected

## 2026-02-09 — Route ChatGPT shares to Jina Reader

- Firecrawl produced escaped markdown (`\*\*bold\*\*`) and ChatGPT UI chrome for `chatgpt.com/share/*` URLs
- Jina Reader via `curl` produces clean, structured conversation output
- Updated url-routing.md and SKILL.md decision tree
- Gemini shares still route to Firecrawl (untested with Jina)

## 2026-02-09 — Initial creation

- Created from incident: wrong GitHub account posted Issue #6 to `work/client-career-opportunities`
- Skill codifies research archival workflow with mandatory identity preflight
- Companion hook: `gh-repo-identity-guard.mjs` (PreToolUse)
- Three TodoWrite templates: Full Archival (A), Save Only (B), Issue Only (C)
- Bundled references: frontmatter-schema.md, url-routing.md
