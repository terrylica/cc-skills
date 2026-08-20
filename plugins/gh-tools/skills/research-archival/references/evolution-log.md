# Evolution Log

Reverse chronological — newest entries on top.

<!-- INVENTED-FALLBACK-OK: this log QUOTES retired code in order to record why it was retired.
     The 2026-08-20 entry names `${OWNER_TYPE:-unknown}` as the pattern the INVENTED-FALLBACK hook
     correctly rejected. It is prose about a deleted line, not a live fallback — the shipped
     identity block in SKILL.md contains no parameter-expansion defaults. Removing the quotation
     would delete the evidence for the fix. -->

## 2026-08-20 — Identity preflight could never pass on an ORG repo; backlink template tripped the hard-wrap guard

- **The identity check blocked every legitimate archival into a shared organisation repository.** It was `AUTH_USER != REPO_OWNER → block`, but on an org repo the owner is the **org**, so the comparison can never match however correct the credential is. Measured on `Eon-Labs/alpha-forge`: authenticated `terrylica`, owner `Eon-Labs`, `owner.type = Organization`, `permissions.push = true` — the correct identity, called a mismatch. Fixed by falling through to `owner.type == Organization && permissions.push == true` when equality fails. The equality path is kept as the fast offline case; the org path costs one API call and is only reached on mismatch.
- **Reframed what the guard is actually asking.** Its purpose is to stop writes reaching the _wrong account_; "may this identity write here" is answered by `permissions.push`, not by string equality with the owner. Equality is a sufficient condition, never a necessary one.
- Also hardened the slug parse: `REPO_SLUG` is now captured as `owner/repo` (so the org branch can call `gh api repos/$REPO_SLUG`) with `REPO_OWNER` derived from it, instead of scraping the owner alone.
- **The skill's own canonical backlink template was rejected by `GH-HARD-WRAP-GUARD`.** Four stacked `Key: value` lines are indistinguishable from hard-wrapped prose to the hook, and GitHub renders each newline as `<br>` anyway. Replaced with a markdown list, which states "separate items" structurally — the meaning intended and the form the guard accepts. Explicitly recorded that `GH-HARD-WRAP-OK` is the wrong remedy here: the complaint was correct.
- Added a general rule that **issue and PR bodies must be authored as unbroken paragraphs**, with an `awk` one-liner to check, since soft-wrapping editors hide the problem. Long lines are correct for prose; runs of ~80–100-column lines are the defect.
- The mismatch diagnostic first used `${OWNER_TYPE:-unknown}`, and the `INVENTED-FALLBACK` hook rejected it — correctly. Substituting the word "unknown" reports a value GitHub never sent. Rewritten to print each field **only when present**, plus `gh`'s own exit code and the first line of its stderr when the API call itself failed. Absent is a state, and the honest rendering of a state is nothing at all.
- New troubleshooting rows: the hard-wrap guard; the org-repo identity fall-through; and `gh pr create` reporting "you must first push the current branch" **after a successful push** when run from a linked worktree — pass `--head <branch> --base main` explicitly, and confirm with `git ls-remote --heads origin <branch>` rather than trusting the error.

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

- Created from incident: wrong GitHub account posted Issue #6 to `work/example-job-board`
- Skill codifies research archival workflow with mandatory identity preflight
- Companion hook: `gh-repo-identity-guard.mjs` (PreToolUse)
- Three TodoWrite templates: Full Archival (A), Save Only (B), Issue Only (C)
- Bundled references: frontmatter-schema.md, url-routing.md
