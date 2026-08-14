# Evolution Log

> **Convention**: Reverse chronological order (newest on top, oldest at bottom). Prepend new entries. Refer to releases by date, not by version tag — semantic-release owns the version SSoT (see `.releaserc.yml`).

---

## 2026-08-13: Self-hosted deployment retired — this skill is now public-API only

**Trigger**: The operator asked to prioritize Firecrawl's official public "website to markdown" service for a small, occasional conversion volume, and to retire the self-hosted instances as no longer active.

**Correction to the stated premise**: littleblack's Firecrawl was **not** dead. It answered HTTP 200 in 21 ms with five containers up five weeks. bigblack (`el02`) was already clean. The instance was therefore retired deliberately, not reaped — worth recording, because "assume it's already gone" would have left a live service running.

**What was removed** (littleblack, user `yca`): containers `firecrawl-{api-1,nuq-postgres-1,rabbitmq-1,redis-1,playwright-service-1}`; images `firecrawl-api`, `firecrawl-playwright-service`, `firecrawl-nuq-postgres`, `rabbitmq:3-management`, `redis:alpine`; plus volume and build-cache prune. **~18 GB reclaimed (61.99 → 44.04 GB).** Port 3002 refuses connections. The compose directory `/home/kab/firecrawl` was permission-denied, so removal was done by container name rather than `docker compose down`. sub2api (3 containers) and clickhouse-server were explicitly preserved.

**Validation that justified the switch** — public Firecrawl v2 vs Jina Reader on two `chatgpt.com/share/*` links:

| Link | Firecrawl `v2/scrape`                       | Jina `r.jina.ai` | Jina coverage |
| ---- | ------------------------------------------- | ---------------- | ------------- |
| 1    | 57,616 chars · 76 headings · 128 table rows | 9,397 · 12 · 22  | **17%**       |
| 2    | 136,590 chars · 85 headings · 69 table rows | 15,960 · 13 · 9  | **12%**       |

Neither hit the login wall, so this is a coverage difference, not an auth failure. Jina truncated mid-sentence; Firecrawl reached the true footer both times. Firecrawl's extra bulk was content, not boilerplate. Jina also needs `-H "x-timeout: 30"` or it returns ~321 bytes of login chrome.

**Skill changes**: SKILL.md 38,700 → 31,934 chars. Section 5 (Self-Hosted Operations) excised to a six-line retirement fence. The four `self-hosted-*.md` reference docs (~16 KB) deleted. All base URLs repointed to `https://api.firecrawl.dev`; v1 → v2 with the `search` response-shape difference documented in `api-endpoint-reference.md`. The health-check surface was removed outright — the public API has no health endpoint, so gating a run on liveness is now an anti-pattern rather than a best practice.

**Downstream reconciliation**: `devops-tools/CLAUDE.md` (self-hosted services table), `gemini-deep-research` (client default, CLI default, help text, options table), and `gh-tools:research-archival` (decision tree, scrape block, troubleshooting, `url-routing.md`) were all repointed in the same change.

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
