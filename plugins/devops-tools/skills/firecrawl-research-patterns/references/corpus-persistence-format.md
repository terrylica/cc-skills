# Corpus Persistence Format

Defines how raw Firecrawl output is saved for future Claude Code sessions to re-read and re-analyze.

**Design follows existing cc-skills patterns**:

- YAML frontmatter + raw markdown body from `Skill(gh-tools:research-archival)`
- NDJSON append-only registry from `Skill(devops-tools:session-chronicle)`

---

## Directory Layout

```
{project-root}/
├── docs/research/
│   ├── corpus/                              # Raw scraped pages (committed to git)
│   │   ├── 2026-02-25-moe-scaling-arxiv-2401-12345.md
│   │   ├── 2026-02-25-switch-transformer-google.md
│   │   └── ...
│   ├── sessions/                            # Synthesized research reports (committed)
│   │   ├── 2026-02-25-moe-scaling.md
│   │   └── ...
│   └── corpus-index.jsonl                   # Append-only registry (committed)
```

| Directory                          | Committed? | Purpose                                         |
| ---------------------------------- | ---------- | ----------------------------------------------- |
| `docs/research/corpus/`            | Yes        | Raw scraped pages — one file per URL per scrape |
| `docs/research/sessions/`          | Yes        | Synthesized reports referencing corpus files    |
| `docs/research/corpus-index.jsonl` | Yes        | Master index for quick corpus queries           |

---

## Raw Corpus File Format

Each file in `docs/research/corpus/` = one Firecrawl-scraped URL, preserved exactly as returned.

### File Naming

```
YYYY-MM-DD-{slug}.md
```

- `YYYY-MM-DD` — date of scrape
- `slug` — kebab-case derived from page title or URL path (max 60 chars)

**Examples**:

- `2026-02-25-moe-scaling-arxiv-2401-12345.md`
- `2026-02-25-switch-transformer-google-research.md`
- `2026-02-25-expert-parallelism-deepspeed-docs.md`

### YAML Frontmatter

```yaml
---
source_url: https://arxiv.org/html/2401.12345
scraped_at: "2026-02-25T14:30:00Z"
scraper: firecrawl
firecrawl_endpoint: /v1/search
search_query: "mixture of experts scaling"
result_index: 2
research_session: "2026-02-25-moe-scaling"
depth_level: 1
claude_code_uuid: SESSION_UUID
content_tokens_approx: 4200
---
```

| Field                   | Type     | Required               | Description                                   |
| ----------------------- | -------- | ---------------------- | --------------------------------------------- |
| `source_url`            | URL      | Yes                    | Original URL that was scraped                 |
| `scraped_at`            | ISO 8601 | Yes                    | UTC timestamp of scrape                       |
| `scraper`               | Enum     | Yes                    | `firecrawl`, `jina-reader`, or `direct`       |
| `firecrawl_endpoint`    | String   | If scraper=firecrawl   | `/v1/search` or `/v1/scrape`                  |
| `search_query`          | String   | If endpoint=/v1/search | The search query that found this page         |
| `result_index`          | Number   | If endpoint=/v1/search | Position in search results (0-based)          |
| `research_session`      | String   | Yes                    | Session slug (links to session report)        |
| `depth_level`           | Number   | Yes                    | Recursion depth when scraped (1 = top level)  |
| `claude_code_uuid`      | UUID     | Yes                    | Claude Code session that performed the scrape |
| `content_tokens_approx` | Number   | Yes                    | Approximate token count (chars / 3.5)         |

### Body Content

Everything below the closing `---` is the **exact markdown Firecrawl returned**. Rules:

1. **Never modify** — no summarization, no trimming, no reformatting
2. **No added headers** — don't prepend `# Title` if Firecrawl didn't include one
3. **Preserve whitespace** — keep original line breaks, spacing, formatting
4. **Include artifacts** — if Firecrawl returned table markdown, code blocks, etc., keep them

### One File Per Scrape

If the same URL is scraped in multiple sessions:

- Each scrape gets its own timestamped file
- The corpus index tracks all versions
- Deduplication is the _index's_ job, not the file system's

This preserves temporal snapshots — content at a URL may change between scrapes.

---

## Corpus Index Format

`docs/research/corpus-index.jsonl` — append-only NDJSON, one line per scraped page.

### Schema

```json
{
  "url": "https://arxiv.org/html/2401.12345",
  "file": "corpus/2026-02-25-moe-scaling-arxiv-2401-12345.md",
  "scraped_at": "2026-02-25T14:30:00Z",
  "session": "2026-02-25-moe-scaling",
  "tokens": 4200,
  "scraper": "firecrawl"
}
```

| Field        | Type   | Description                             |
| ------------ | ------ | --------------------------------------- |
| `url`        | string | Source URL (for dedup lookups)          |
| `file`       | string | Relative path within `docs/research/`   |
| `scraped_at` | string | ISO 8601 UTC timestamp                  |
| `session`    | string | Research session slug                   |
| `tokens`     | number | Approximate token count                 |
| `scraper`    | string | `firecrawl`, `jina-reader`, or `direct` |

### Usage

Claude Code can query the index to find relevant corpus files:

```bash
# Find all corpus files for a session
grep '"session":"2026-02-25-moe-scaling"' docs/research/corpus-index.jsonl | jq -r '.file'

# Check if a URL is already in the corpus
grep '"url":"https://arxiv.org/html/2401.12345"' docs/research/corpus-index.jsonl

# Count corpus entries per session
jq -r '.session' docs/research/corpus-index.jsonl | sort | uniq -c | sort -rn
```

### Append Pattern

```typescript
import { appendFileSync } from "node:fs";

function appendToCorpusIndex(entry: CorpusIndexEntry): void {
  const line = JSON.stringify(entry) + "\n";
  appendFileSync("docs/research/corpus-index.jsonl", line);
}
```

---

## Session Report Format

Synthesized reports in `docs/research/sessions/YYYY-MM-DD-{topic-slug}.md`.

### Structure

```markdown
---
topic: "Mixture of Experts Scaling Laws"
started_at: "2026-02-25T14:00:00Z"
completed_at: "2026-02-25T15:30:00Z"
breadth: 4
depth: 2
total_queries: 12
queries_succeeded: 10
queries_failed: 2
corpus_files: 35
total_tokens_scraped: 147000
claude_code_uuid: SESSION_UUID
---

# Mixture of Experts Scaling Laws

## Summary

[Synthesized findings organized by theme...]

## Key Findings

1. Finding 1 (from [source](../corpus/2026-02-25-moe-scaling-arxiv.md))
2. Finding 2 (from [source](../corpus/2026-02-25-switch-transformer.md))

## Open Questions

- Question that couldn't be fully answered
- Area needing more research

## Sources

| #   | Title                 | Corpus File                                                                                               | Tokens |
| --- | --------------------- | --------------------------------------------------------------------------------------------------------- | ------ |
| 1   | Scaling MoE Models... | [corpus/2026-02-25-moe-scaling-arxiv-2401-12345.md](../corpus/2026-02-25-moe-scaling-arxiv-2401-12345.md) | 4200   |
| 2   | Switch Transformer... | [corpus/2026-02-25-switch-transformer-google.md](../corpus/2026-02-25-switch-transformer-google.md)       | 6100   |
| 3   | Expert Parallelism    | [corpus/2026-02-25-expert-parallelism-deepspeed.md](../corpus/2026-02-25-expert-parallelism-deepspeed.md) | 3800   |

## Failed Queries

- "MoE training stability RLHF" — timeout
- "expert routing load balance GPU memory" — no results
```

### Source References

Every finding in the report should link to its source corpus file using relative paths. This lets any future Claude Code session:

1. Read the synthesized report for a quick overview
2. Drill into specific corpus files for full original content
3. Re-analyze raw sources with different questions or newer models

---

## Initialization

When starting the first research session in a project:

```bash
mkdir -p docs/research/corpus docs/research/sessions
touch docs/research/corpus-index.jsonl
```

Add to `.gitignore` if raw corpus files would be too large:

```gitignore
# Uncomment if corpus files are too large for git
# docs/research/corpus/
```

By default, commit everything — corpus files are markdown and diff cleanly.

---

## Consistency with Existing Patterns

| Field              | This Skill                         | `research-archival`                  | Match?                    |
| ------------------ | ---------------------------------- | ------------------------------------ | ------------------------- |
| `source_url`       | Yes                                | Yes                                  | Same field name           |
| `scraped_at`       | Yes                                | Yes                                  | Same field name, ISO 8601 |
| `claude_code_uuid` | Yes                                | Yes                                  | Same field name           |
| `scraper`          | `firecrawl`/`jina-reader`/`direct` | N/A (uses `source_type`)             | Extended                  |
| File naming        | `YYYY-MM-DD-{slug}.md`             | `YYYY-MM-DD-{slug}-{source_type}.md` | Similar pattern           |
| Index format       | JSONL                              | N/A                                  | From `session-chronicle`  |
