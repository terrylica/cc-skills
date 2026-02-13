# Evolution Log

Reverse chronological — newest entries on top.

## 2026-02-13 — Add Firecrawl health check + auto-revival to scraping workflow

- Firecrawl containers can show "Up" while internal processes are dead (RAM/CPU overload: `WORKER STALLED cpuUsage=0.998 memoryUsage=0.858`)
- Added 3-step deep health check: ZeroTier ping → API HTTP probe → log inspection
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

- Created from incident: wrong GitHub account posted Issue #6 to `459ecs/dental-career-opportunities`
- Skill codifies research archival workflow with mandatory identity preflight
- Companion hook: `gh-repo-identity-guard.mjs` (PreToolUse)
- Three TodoWrite templates: Full Archival (A), Save Only (B), Issue Only (C)
- Bundled references: frontmatter-schema.md, url-routing.md
