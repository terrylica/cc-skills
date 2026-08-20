---
name: research-archival
description: Scrape AI research URLs, archive with frontmatter, create GitHub Issues with identity verification.
allowed-tools: Read, Bash, Grep, Glob, Edit, Write
---

# Research Archival

Scrape AI research conversations (ChatGPT, Gemini, Claude) and web pages, archive them as markdown files with YAML frontmatter, and create cross-referenced GitHub Issues — with mandatory identity verification at every step.

> **Self-Evolving Skill**: This skill improves through use. If instructions are wrong, parameters drifted, or a workaround was needed — fix this file immediately, don't defer. Only update for real, reproducible issues.

## FIRST - TodoWrite Task Templates

**MANDATORY**: Select and load the appropriate template before any archival work.

### Template A - Full Archival (scrape + save + issue)

```
1. Identity preflight — verify GH_ACCOUNT or resolve via curl /user
2. Scrape URL — route to Firecrawl or Jina per url-routing.md
3. Save to file — YYYY-MM-DD-{slug}-{source_type}.md with frontmatter
4. Survey labels — gh label list, reuse existing, max 3-6
5. Create GitHub Issue — use --body with heredoc or --body-file
6. Update frontmatter — add github_issue_url and github_issue_number
7. Post canonical backlink comment on Issue
```

### Template B - Save Only (no issue)

```
1. Identity preflight (still required for consistency)
2. Scrape URL — route to Firecrawl or Jina per url-routing.md
3. Save to file — YYYY-MM-DD-{slug}-{source_type}.md with frontmatter
```

### Template C - Issue Only (file already exists)

```
1. Identity preflight
2. Read existing file frontmatter
3. Survey labels — gh label list, reuse existing, max 3-6
4. Create GitHub Issue — use --body with heredoc or --body-file
5. Update file frontmatter with issue cross-reference
6. Post canonical backlink comment on Issue
```

---

## Identity Preflight (MANDATORY — Step 0)

**MUST execute before any `gh` write command. Non-negotiable.**

The `gh-repo-identity-guard.mjs` PreToolUse hook provides a safety net, but this skill performs its own check as defense-in-depth.

### Resolution Order

1. **Fast-path** — `GH_ACCOUNT` env var (set by mise per-directory)
2. **Token filename** — scan `~/.claude/.secrets/gh-token-*` for single base match
3. **API call** — `curl -sH "Authorization: token $GH_TOKEN" https://api.github.com/user`

### Verification

```bash
/usr/bin/env bash << 'IDENTITY_EOF'
# Resolve authenticated user
if [ -n "$GH_ACCOUNT" ]; then
  AUTH_USER="$GH_ACCOUNT"
  AUTH_SOURCE="GH_ACCOUNT"
else
  AUTH_USER=$(curl -sf --max-time 5 -H "Authorization: token $GH_TOKEN" \
    https://api.github.com/user 2>/dev/null | grep -o '"login":"[^"]*"' | cut -d'"' -f4)
  AUTH_SOURCE="API /user"
fi

# Resolve target repo owner
REPO_SLUG=$(git remote get-url origin 2>/dev/null | sed -n 's|.*github\.com[:/]\([^/]*/[^/.]*\).*|\1|p')
REPO_OWNER=${REPO_SLUG%%/*}

echo "Authenticated as: $AUTH_USER (via $AUTH_SOURCE)"
echo "Target repo owner: $REPO_OWNER"

if [ "$AUTH_USER" = "$REPO_OWNER" ]; then
  echo "Identity verified (personal repo, owner == authenticated user)"
  exit 0
fi

# NOT automatically a failure. On an ORGANISATION repo the owner is the org, never a user, so a
# string comparison can never match however correct the credential is. The real question is
# whether this identity may write here.
API_RC=0
REPO_JSON=$(gh api "repos/$REPO_SLUG" 2>/tmp/gh-identity-err) || API_RC=$?
OWNER_TYPE=$(printf '%s' "$REPO_JSON" | jq -r '.owner.type // empty')
CAN_PUSH=$(printf '%s' "$REPO_JSON" | jq -r '.permissions.push // empty')

if [ "$OWNER_TYPE" = "Organization" ] && [ "$CAN_PUSH" = "true" ]; then
  echo "Identity verified (organisation repo; $AUTH_USER holds push on $REPO_SLUG)"
  exit 0
fi

echo ""
echo "MISMATCH — do NOT proceed with gh write commands"
# Print what GitHub actually returned. A field that is absent prints as nothing, because absent is
# a state -- substituting a word like "unknown" would report a value GitHub never sent.
[ -n "$OWNER_TYPE" ] && echo "  owner.type       : $OWNER_TYPE"
[ -n "$CAN_PUSH" ] && echo "  permissions.push : $CAN_PUSH"
[ "$API_RC" -ne 0 ] && echo "  gh exit code     : $API_RC"
[ -s /tmp/gh-identity-err ] && echo "  gh stderr        : $(head -1 /tmp/gh-identity-err)"
echo "Fix: export GH_TOKEN=\$(~/.claude/tools/bin/gh-token-for-repo)"
exit 1
IDENTITY_EOF
```

**BLOCK if mismatch** — display diagnostic and do NOT continue to any `gh` write operation.

> **Why the organisation branch exists.** The original check was `AUTH_USER != REPO_OWNER → block`.
> On an organisation repository the owner is the **org**, so that comparison can never match no
> matter how correct the credential is — it blocked every legitimate archival into a shared repo.
> Measured 2026-08-20 on `Eon-Labs/alpha-forge`: authenticated `terrylica`, owner `Eon-Labs`,
> `owner.type = Organization`, `permissions.push = true`. That is the correct identity, and the
> check called it a mismatch.
>
> The guard's purpose is to stop writes going to the **wrong account**, and "may this identity write
> here" is answered by `permissions.push`, not by string equality with the owner. The personal-repo
> equality path is kept as the fast, offline case; the org path costs one API call and is only
> reached when equality fails.

---

## Scraping Workflow

Route scrape requests based on URL pattern. See [url-routing.md](./references/url-routing.md) for full details.

### Decision Tree

```
Any JS-rendered share link (chatgpt.com/share/, gemini.google.com/share/, claude.ai/artifacts/)
  → Firecrawl public API (POST https://api.firecrawl.dev/v2/scrape)
  → Use curl (not WebFetch — it summarizes instead of returning raw)

Simple static page
  → Either works. Jina Reader (https://r.jina.ai/{URL}) is one GET and fine here.
```

**Default to Firecrawl.** Measured 2026-08-13 on two `chatgpt.com/share/*` links, Jina returned
**17% and 12%** of Firecrawl's content and truncated mid-sentence; Firecrawl reached the true page
footer both times. Jina also needs `-H "x-timeout: 30"` or it returns ~321 bytes of login chrome.

### Firecrawl Scrape

No health check, no preflight, no revival. The public API needs no key and has no host to be down —
handle a failed request per request rather than gating the run on a liveness probe.

```bash
/usr/bin/env bash << 'SCRAPE_EOF'
set -euo pipefail

# waitFor gives the SPA time to render; without it a share link returns the shell.
RESPONSE=$(curl -sS --max-time 180 -X POST https://api.firecrawl.dev/v2/scrape \
  -H "Content-Type: application/json" \
  -d "$(jq -n --arg u "$URL" \
        '{url: $u, formats: ["markdown"], waitFor: 8000, timeout: 60000}')")

CONTENT=$(printf '%s' "$RESPONSE" | jq -r '.data.markdown // empty')

if [ -z "$CONTENT" ]; then
  echo "ERROR: Firecrawl returned no markdown:" >&2
  printf '%s\n' "$RESPONSE" | head -c 400 >&2
  echo "Retry once, then fall back to: curl -H 'x-timeout: 30' https://r.jina.ai/${URL}" >&2
  exit 1
fi

printf '%s\n' "$CONTENT"
SCRAPE_EOF
```

> **Do not reintroduce a self-hosted Firecrawl.** The littleblack deployment (ports 3002/3003, five
> containers) was retired 2026-08-13 and reclaimed ~18 GB. It required health checks, container
> restarts, and WORKER-STALLED triage that the public API makes unnecessary at this volume.

---

## File Saving

### Naming Convention

```
YYYY-MM-DD-{slug}-{source_type}.md
```

- `slug` — kebab-case summary (max 50 chars)
- `source_type` — from enum: `chatgpt`, `gemini`, `claude`, `web`

**Default location**: `docs/research/` in the current project.

### YAML Frontmatter

See [frontmatter-schema.md](./references/frontmatter-schema.md) for the full field contract.

```yaml
---
source_url: https://chatgpt.com/share/...
source_type: chatgpt-share
scraped_at: "2026-02-09T18:30:00Z"
model_name: gpt-4o
custom_gpt_name: Cosmo
claude_code_uuid: SESSION_UUID
github_issue_url: ""
github_issue_number: ""
---
```

Leave `github_issue_url` and `github_issue_number` empty — update after Issue creation.

---

## GitHub Issue Creation

### Label Survey

Survey existing labels first — reuse preferred, create only when concept is genuinely novel.

```bash
gh label list --repo owner/repo --limit 100
```

**Policy**: Max 3-6 labels per issue. Common labels: `research`, `ai-output`, `chatgpt`, `gemini`, `archival`.

### Create Issue

Use `--body` with heredoc for inline composition, or `--body-file` for very large content.

```bash
/usr/bin/env bash << 'ISSUE_EOF'
# Write body to temp file
cat > "/tmp/issue-body-${SLUG}.md" << 'BODY_EOF'
## Summary

Brief description of the archived research content.

## Source

- **URL**: SOURCE_URL
- **Type**: source_type
- **Model**: model_name
- **Scraped**: scraped_at

## Key Findings

- Finding 1
- Finding 2

## Archived File

`docs/research/FILENAME.md`
BODY_EOF

# Create issue
gh issue create \
  --repo owner/repo \
  --title "Research: descriptive title here" \
  --body-file "/tmp/issue-body-${SLUG}.md" \
  --label "research,ai-output"

# Clean up
rm -f "/tmp/issue-body-${SLUG}.md"
ISSUE_EOF
```

### Update Frontmatter

After issue creation, update the archived file's frontmatter with the issue URL and number.

---

## Canonical Backlink Comment

Post a comment on the Issue linking back to the archived file. **Metadata goes in a markdown list,
not as consecutive prose lines:**

```
**Archived**: `docs/research/YYYY-MM-DD-slug-source_type.md`

- **Scraped**: 2026-02-09T18:30:00Z — scraper, byte count, whether it reached the page footer
- **Source**: [chatgpt-share](https://chatgpt.com/share/...)
- **Session**: `SESSION_UUID`
- **PR**: #NNN — commit `abcdef12`
```

> **Do not restore the bare consecutive-line version.** GitHub renders every newline in a comment as
> `<br>`, so four stacked `Key: value` lines are indistinguishable from hard-wrapped prose and the
> `GH-HARD-WRAP-GUARD` PreToolUse hook **rejects the command** (measured 2026-08-20 — the previous
> template in this file was itself the thing that tripped it). A list expresses "these are separate
> items" structurally, which is both what is meant and what the guard accepts. Reaching for the
> `GH-HARD-WRAP-OK` override here would suppress a correct complaint.

### Every issue/PR body must be authored as unbroken paragraphs

This applies to the Issue body and the PR body too, not just the backlink. Author each **paragraph**
as ONE long line and let GitHub reflow it; keep breaks only for list items, headings, code blocks and
blank lines. Editors that soft-wrap make this invisible — check with:

```bash
awk '{ if (length($0) > 100 && $0 !~ /^[-*|#> ]/) printf "L%d: %d cols\n", NR, length($0) }' body.md
```

Long lines are **expected and correct** for prose paragraphs; the failure mode is many lines of
~80–100 columns in a row.

---

## Post-Change Checklist

After modifying THIS skill:

1. [ ] YAML frontmatter valid (no colons in description)
2. [ ] Trigger keywords current in description
3. [ ] All `./references/` links resolve
4. [ ] Identity preflight section remains FIRST in workflow
5. [ ] Append changes to [evolution-log.md](./references/evolution-log.md)
6. [ ] Validate: `uv run plugins/plugin-dev/scripts/skill-creator/quick_validate.py plugins/gh-tools/skills/research-archival`
7. [ ] Validate links: `bun run plugins/plugin-dev/scripts/validate-links.ts plugins/gh-tools/skills/research-archival`

---

## Troubleshooting

| Issue                                                                                    | Cause                                                        | Fix                                                                                                                                              |
| ---------------------------------------------------------------------------------------- | ------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------ |
| `GH-HARD-WRAP-GUARD` rejects the command                                                 | Body authored as hard-wrapped prose                          | Reflow each paragraph to ONE line; use a list for stacked `Key: value` metadata. Do **not** reach for `GH-HARD-WRAP-OK` — the guard is right     |
| Identity preflight blocks on an org repo                                                 | Owner is the org, so `AUTH_USER != REPO_OWNER` always        | Expected — the check now falls through to `owner.type == Organization` + `permissions.push == true`. If it still blocks, you genuinely lack push |
| `gh pr create` says "you must first push the current branch" **after** a successful push | Run from a linked worktree; `gh` cannot resolve the upstream | Pass `--head <branch> --base main` explicitly. Confirm the branch is really remote with `git ls-remote --heads origin <branch>`                  |
| Wrong account posting                                                                    | GH_TOKEN mismatch                                            | Check `mise env \| grep GH_TOKEN`, verify `GH_ACCOUNT`                                                                                           |
| Body exceeds 65536 chars                                                                 | GitHub API limit                                             | Split across issue body + first comment                                                                                                          |
| Firecrawl returns no markdown                                                            | Transient API failure                                        | Retry once, then fall back to Jina with `-H "x-timeout: 30"`                                                                                     |
| Scrape returns the page shell                                                            | SPA had not rendered yet                                     | Raise `waitFor` (8000 → 15000) and `timeout` in the request body                                                                                 |
| Jina returns ~321 bytes                                                                  | Missing timeout header                                       | Add `-H "x-timeout: 30"` — without it Jina returns login chrome                                                                                  |
| Jina output truncated                                                                    | Jina under-covers JS-heavy pages                             | Expected — use Firecrawl; Jina got 17%/12% coverage in the 2026-08-13 test                                                                       |
| mise parse error                                                                         | Stale .mise.toml syntax                                      | Run `mise doctor`, check `[hooks.enter]` syntax                                                                                                  |
| Identity guard blocks                                                                    | Non-owner account                                            | `export GH_TOKEN=$(~/.claude/tools/bin/gh-token-for-repo)`                                                                                       |

## References

- [Frontmatter Schema](./references/frontmatter-schema.md) — YAML field contract
- [URL Routing](./references/url-routing.md) — Scraper routing table
- [Evolution Log](./references/evolution-log.md) — Change history

## Post-Execution Reflection

After this skill completes, check before closing:

1. **Did the command succeed?** — If not, fix the instruction or error table that caused the failure.
2. **Did parameters or output change?** — If the underlying tool's interface drifted, update Usage examples and Parameters table to match.
3. **Was a workaround needed?** — If you had to improvise (different flags, extra steps), update this SKILL.md so the next invocation doesn't need the same workaround.

Only update if the issue is real and reproducible — not speculative.
