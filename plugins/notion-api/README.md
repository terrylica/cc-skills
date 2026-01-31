# Notion API Plugin

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Skills](https://img.shields.io/badge/Skills-1-blue.svg)]()
[![Claude Code](https://img.shields.io/badge/Claude%20Code-Plugin-purple.svg)]()

Programmatically control Notion using the official `notion-client` Python SDK.

**Trigger phrases:** "Notion API", "create page", "query database", "add blocks"

## Features

- **Create pages** in databases with full property support
- **Manipulate blocks** - paragraphs, headings, lists, code, callouts
- **Query databases** with filters, sorts, and pagination
- **Search workspace** by title
- **Automatic retry** for rate limits and transient errors

## Installation

This plugin is part of the cc-skills marketplace:

```
/plugin install notion-api@cc-skills
```

## Prerequisites

1. Create a Notion integration at [notion.so/my-integrations](https://www.notion.so/my-integrations)
2. Copy the **Internal Integration Secret** (starts with `ntn_` or `secret_`)
3. Share each page/database with the integration:
   - Open page → ... menu → Connections → Add connection → Select integration

## Quick Start

```python
from notion_client import Client

# Initialize client
client = Client(auth="ntn_your_token_here")

# Create a page in a database
page = client.pages.create(
    parent={"type": "data_source_id", "data_source_id": "database-id"},
    properties={
        "Name": {"title": [{"text": {"content": "New Task"}}]},
        "Status": {"status": {"name": "In Progress"}}
    }
)
print(f"Created: {page['url']}")
```

## Skills

| Skill        | Description                                                 |
| ------------ | ----------------------------------------------------------- |
| `notion-sdk` | Full Notion API integration with preflight token collection |

## Scripts

| Script              | Purpose                                       |
| ------------------- | --------------------------------------------- |
| `notion_client.py`  | Client setup, token validation, retry wrapper |
| `create_page.py`    | Create pages with property builders           |
| `add_blocks.py`     | Block manipulation with type builders         |
| `query_database.py` | Query, filter, sort, search                   |

## References

- [Property Types](./skills/notion-sdk/references/property-types.md) - All 24 property types
- [Block Types](./skills/notion-sdk/references/block-types.md) - All block types
- [Rich Text](./skills/notion-sdk/references/rich-text.md) - Formatting, links, mentions
- [Pagination](./skills/notion-sdk/references/pagination.md) - Handling large datasets

## Requirements

- Python 3.11+
- `notion-client>=2.6.0`

```bash
uv pip install notion-client>=2.6.0
```

## Constraints

- **Rate limit**: 3 requests/second (scripts include auto-retry)
- **Auth model**: Page-level sharing required
- **API version**: Uses latest multi-source database model

## Troubleshooting

| Issue               | Cause                 | Solution                                                                 |
| ------------------- | --------------------- | ------------------------------------------------------------------------ |
| 401 Unauthorized    | Invalid token         | Verify token starts with `ntn_` or `secret_`                             |
| 403 Forbidden       | Page not shared       | Share page with integration via Connections menu                         |
| 429 Rate limited    | Too many requests     | Scripts auto-retry; reduce request frequency                             |
| Property type error | Wrong property format | Check [Property Types](./skills/notion-sdk/references/property-types.md) |
| Database not found  | Incorrect ID          | Use 32-char ID without dashes from URL                                   |

## License

MIT
