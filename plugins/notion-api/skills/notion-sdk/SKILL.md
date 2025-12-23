---
name: notion-sdk
description: Programmatically control Notion using notion-client Python SDK. Create pages in databases, manipulate blocks, query and filter data. Use when user wants to automate Notion, create pages via API, add content programmatically, query database entries, or build Notion integrations. PREFLIGHT - requires Notion Integration Token from notion.so/my-integrations.
---

# Notion SDK Skill

Control Notion programmatically using the official `notion-client` Python SDK (v2.6.0+).

## Preflight: Token Collection

Before any Notion API operation, collect the integration token:

```
AskUserQuestion(questions=[{
    "question": "Please provide your Notion Integration Token (starts with ntn_ or secret_)",
    "header": "Notion Token",
    "options": [
        {"label": "I have a token ready", "description": "Token from notion.so/my-integrations"},
        {"label": "Need to create one", "description": "Go to notion.so/my-integrations → New integration"}
    ],
    "multiSelect": false
}])
```

After user provides token:

1. Validate format (must start with `ntn_` or `secret_`)
2. Test with `validate_token()` from `scripts/notion_client.py`
3. Remind user: **Each page/database must be shared with the integration**

## Quick Start

### 1. Create a Page in Database

```python
from notion_client import Client
from scripts.create_page import (
    create_database_page,
    title_property,
    status_property,
    date_property,
)

client = Client(auth="ntn_...")
page = create_database_page(
    client,
    data_source_id="abc123...",  # Database ID
    properties={
        "Name": title_property("My New Task"),
        "Status": status_property("In Progress"),
        "Due Date": date_property("2025-12-31"),
    }
)
print(f"Created: {page['url']}")
```

### 2. Add Content Blocks

```python
from scripts.add_blocks import (
    append_blocks,
    heading,
    paragraph,
    bullet,
    code_block,
    callout,
)

blocks = [
    heading("Overview", level=2),
    paragraph("This page was created via the Notion API."),
    callout("Remember to share the page with your integration!", emoji="⚠️"),
    heading("Tasks", level=3),
    bullet("First task"),
    bullet("Second task"),
    code_block("print('Hello, Notion!')", language="python"),
]
append_blocks(client, page["id"], blocks)
```

### 3. Query Database

```python
from scripts.query_database import (
    query_data_source,
    checkbox_filter,
    status_filter,
    and_filter,
    sort_by_property,
)

# Find incomplete high-priority items
results = query_data_source(
    client,
    data_source_id="abc123...",
    filter_obj=and_filter(
        checkbox_filter("Done", False),
        status_filter("Priority", "High")
    ),
    sorts=[sort_by_property("Due Date", "ascending")]
)
for page in results:
    title = page["properties"]["Name"]["title"][0]["plain_text"]
    print(f"- {title}")
```

## Available Scripts

| Script              | Purpose                                       |
| ------------------- | --------------------------------------------- |
| `notion_client.py`  | Client setup, token validation, retry wrapper |
| `create_page.py`    | Create pages, property builders               |
| `add_blocks.py`     | Append blocks, block type builders            |
| `query_database.py` | Query, filter, sort, search                   |

## References

- [Property Types](./references/property-types.md) - All 24 property types with examples
- [Block Types](./references/block-types.md) - All block types with structures
- [Rich Text](./references/rich-text.md) - Formatting, links, mentions
- [Pagination](./references/pagination.md) - Handling large result sets

## Important Constraints

### Rate Limits

- **3 requests/second** average (burst tolerated briefly)
- Use `api_call_with_retry()` for automatic rate limit handling
- 429 responses include `Retry-After` header

### Authentication Model

- **Page-level sharing** required (not workspace-wide)
- User must explicitly add integration to each page/database:
  - Page → ... menu → Connections → Add connection → Select integration

### API Version (v2.6.0+)

- Uses `data_source_id` instead of `database_id` for multi-source databases
- Legacy `database_id` still works for simple databases
- Scripts handle both patterns automatically

### Operations NOT Supported

- Workspace settings modification
- User permissions management
- Template creation/management
- Billing/subscription access

## Error Handling

```python
from notion_client import APIResponseError, APIErrorCode

try:
    result = client.pages.create(...)
except APIResponseError as e:
    if e.code == APIErrorCode.ObjectNotFound:
        print("Page/database not found or not shared with integration")
    elif e.code == APIErrorCode.Unauthorized:
        print("Token invalid or expired")
    elif e.code == APIErrorCode.RateLimited:
        print(f"Rate limited. Retry after {e.additional_data.get('retry_after')}s")
    else:
        raise
```

## Installation

```bash
uv pip install notion-client>=2.6.0
```

Or use PEP 723 inline dependencies (scripts include them).
