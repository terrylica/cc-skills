# Notion API Plugin

Programmatically control Notion using the official `notion-client` Python SDK.

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
- **API version**: Uses v2.6.0+ multi-source database model

## License

MIT
