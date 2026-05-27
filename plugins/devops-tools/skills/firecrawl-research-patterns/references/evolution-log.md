# Evolution Log

> **Convention**: Reverse chronological order (newest on top, oldest at bottom). Prepend new entries. Refer to releases by date, not by version tag — semantic-release owns the version SSoT (see `.releaserc.yml`).

---

## 2026-05-27 (b): Antifragile reconciliation of the morning's URL-routing guard

**Trigger**: A live session later the same day invoked the skill on a `chatgpt.com/share/*` URL and hit a contradiction — the morning's URL-routing guard said "route AI chat shares out to `Skill(gh-tools:research-archival)`, this skill cannot handle them," while Section 5's port-routing table explicitly listed `Gemini/ChatGPT shares → Port 3003 (Needs JS rendering)`. The operator (Claude) had to make a judgment call mid-flow, chose Section 5, and port 3003 returned a 75 KB / 1,734-line scrape successfully. Section 5 was right; the guard was overcautious.

**Root cause**: When the URL-routing guard was introduced in the morning's patch to make AI-chat-share routing visible at the top of the templates section, it was framed as a hand-off ("Templates A–E are for research-grade source material, not AI chat transcripts") instead of an **intent split**. Both skills wrap the same Firecrawl backend; the difference is what happens to the bytes after they come back (raw file vs. frontmatter + GH issue + provenance). The original line-11 reference to `gh-tools:research-archival` was a _suggestion_, but the guard upgraded it to _exclusion_ without empirical justification.

**Fix 1 — Intent-based routing**: Replaced the URL-pattern hand-off table with an intent-decision table. Operator picks based on what output they want (read-only conversation text vs. full archival pipeline), not based on the URL string. Both rows are valid uses of the same backend.

**Fix 2 — Documented the port-3003 → Caddy two-step**: The skill's Section 5 example showed `curl :3003/scrape?url=...&name=...` as if it returned markdown directly. It does not. It returns JSON of the shape `{"url": "<caddy-url>", "file": "<filename>"}` — a pointer. The operator must then `GET` the Caddy URL to retrieve the actual markdown. Added the two-step bash snippet, plus a note that the JSON's `url` field embeds the legacy ZeroTier IP and should be reconstructed against the operator's preferred host base.

**Fix 3 — Shell-quoting trap**: Documented that `python3 -c '... print(...)'` inside command substitution leaves a trailing `\n` which becomes `%0A` in the URL-encoded payload and is silently rejected by the wrapper. Recommend `print(..., end='')`.

**Files modified**:

- `SKILL.md` — replaced "URL-routing guard" section (now "Intent routing — AI chat share URLs") and Section 5 port-3003/3004 bash block.

**Validation evidence**: The triggering session's port-3003 invocation against `https://chatgpt.com/share/6a168eb9-b118-83e8-8397-2a4ef1a93a5c` returned 75,353 bytes / 1,734 lines of markdown via the Caddy two-step. Cannot be retroactively reproduced without re-scraping; the live trace from 2026-05-27T07:10:40Z is the audit record.

---

## 2026-05-27 (a): Three broken-instruction bugs from the prior MINOR release

**Trigger**: A diagnostic session caught — and the very next invocation of the skill demonstrated — three documented-but-unfixed bugs that survived the prior MINOR release:

1. `/v1/health` does not exist on this Firecrawl build. Probing returns HTTP 404 (Express HTML error page) which looks like service-down but isn't.
2. Bare `littleblack` hostname was labeled "Preferred" in the access table but doesn't resolve over HTTP on the m3max client (MagicDNS isn't pushing the search suffix to the system resolver; SSH works only because `~/.ssh/config` hard-codes the FQDN).
3. Templates A–E had no entry-point guard against AI chat-share URLs.

**Fix**: Replaced all `/v1/health` references with `GET /` (returns 200 + Firecrawl banner). Demoted bare hostname to "Conditional" with `dscacheutil`/`getent` preflight; promoted Tailscale FQDN to "Preferred". Added URL-routing guard at the top of templates section. (The guard's framing was over-strict — see entry 2026-05-27 (b) above for the reconciliation.)

**Files modified**: `SKILL.md`.

---

## 2026-03-02: Merged firecrawl-self-hosted into this skill

**What**: Absorbed `firecrawl-self-hosted` skill — its SKILL.md condensed into `self-hosted-operations.md` reference, and its 3 reference docs (bootstrap-guide, best-practices, troubleshooting) moved here.

**Why**: The two skills covered the same service (self-hosted Firecrawl). Consolidation eliminates skill discovery friction — one skill for all Firecrawl concerns.

**Files added**:

- `references/self-hosted-operations.md` (new — condensed from old SKILL.md)
- `references/self-hosted-bootstrap-guide.md` (moved + renamed)
- `references/self-hosted-best-practices.md` (moved + renamed)
- `references/self-hosted-troubleshooting.md` (moved + renamed)

**Files modified**:

- `SKILL.md` — added self-hosted triggers, Section 5, updated references, removed scope boundary note

---

## 2026-02-26: Initial Evolution Log

**Status**: Skill is in use and maintained. Track improvements here.

### Purpose

This evolution log tracks updates to the skill. Each entry should note:

- What changed (content, structure, tooling)
- Why it changed (bug fix, feature request, best practice)
- Files affected

### How to Use

1. When updating SKILL.md or references, add an entry here with the date
2. Keep entries reverse-chronological (newest first)
3. Link to ADRs or GitHub issues when relevant
4. Reference specific line changes when helpful

---
