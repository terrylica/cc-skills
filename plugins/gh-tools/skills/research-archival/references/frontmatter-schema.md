# Frontmatter Schema

YAML frontmatter contract for archived research files.

## Required Fields

| Field         | Type     | Description                | Example                                  |
| ------------- | -------- | -------------------------- | ---------------------------------------- |
| `source_url`  | URL      | Original share URL         | `https://chatgpt.com/share/698a7c4b-...` |
| `source_type` | Enum     | Source platform identifier | `chatgpt-share`                          |
| `scraped_at`  | ISO 8601 | UTC timestamp of scrape    | `2026-02-09T18:30:00Z`                   |

## Optional Fields

| Field                 | Type    | Description                                 | Example                                  |
| --------------------- | ------- | ------------------------------------------- | ---------------------------------------- |
| `model_name`          | String  | AI model used in conversation               | `gpt-4o`, `gemini-2.0-flash`             |
| `model_version`       | String  | Specific version if known                   | `2026-02-01`                             |
| `custom_gpt_name`     | String  | Custom GPT name if applicable               | `Cosmo`                                  |
| `claude_code_uuid`    | UUID    | Claude Code session that performed archival | `d093612a-e4c1-...`                      |
| `github_issue_url`    | URL     | Cross-reference to GitHub Issue             | `https://github.com/owner/repo/issues/8` |
| `github_issue_number` | Integer | Issue number for quick reference            | `8`                                      |

## Valid `source_type` Values

| Value             | Platform                      | Scraper     |
| ----------------- | ----------------------------- | ----------- |
| `chatgpt-share`   | ChatGPT shared conversations  | Jina Reader |
| `gemini-share`    | Google Gemini shared outputs  | Firecrawl   |
| `claude-artifact` | Claude artifacts/shared links | Jina Reader |
| `web-page`        | General web pages             | Jina Reader |

## File Naming Convention

```
YYYY-MM-DD-{slug}-{source_type}.md
```

- `slug` - Kebab-case summary of content (max 50 chars)
- `source_type` - From the enum above

**Examples**:

- `2026-02-09-natasha-tc-executive-mou-chatgpt.md`
- `2026-01-15-cda-training-benchmarks-gemini.md`

## Frontmatter Template

```yaml
---
source_url: https://chatgpt.com/share/...
source_type: chatgpt-share
scraped_at: "2026-02-09T18:30:00Z"
model_name: gpt-4o
custom_gpt_name: Cosmo
claude_code_uuid: d093612a-e4c1-49cc-bac0-2eac01a3957d
github_issue_url: https://github.com/owner/repo/issues/8
github_issue_number: 8
---
```
