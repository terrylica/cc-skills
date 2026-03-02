# API Endpoint Reference

Firecrawl self-hosted API contracts for the two endpoints used in research workflows, plus health check.

**Base URL**: `http://172.25.236.1:3002` (ZeroTier, no API key needed)

---

## POST /v1/search

Combined search + scrape. Searches the web for a query and returns scraped markdown for each result.

### Request

```json
{
  "query": "mixture of experts scaling laws",
  "limit": 5,
  "scrapeOptions": {
    "formats": ["markdown"]
  }
}
```

| Field                   | Type     | Required | Default        | Description               |
| ----------------------- | -------- | -------- | -------------- | ------------------------- |
| `query`                 | string   | Yes      | —              | Search query              |
| `limit`                 | number   | No       | 5              | Max results to return     |
| `scrapeOptions.formats` | string[] | No       | `["markdown"]` | Content formats to return |

### Response (200 OK)

```json
{
  "success": true,
  "data": [
    {
      "url": "https://example.com/page1",
      "markdown": "# Page Title\n\nContent...",
      "metadata": {
        "title": "Page Title",
        "description": "Meta description",
        "sourceURL": "https://example.com/page1"
      }
    }
  ]
}
```

| Field             | Type    | Description                              |
| ----------------- | ------- | ---------------------------------------- |
| `success`         | boolean | Whether the search succeeded             |
| `data`            | array   | Array of scraped results                 |
| `data[].url`      | string  | Source URL                               |
| `data[].markdown` | string  | Scraped page content as markdown         |
| `data[].metadata` | object  | Page metadata (title, description, etc.) |

### Error Responses

| Status  | Meaning                         | Action                                                                               |
| ------- | ------------------------------- | ------------------------------------------------------------------------------------ |
| 400     | Invalid request (missing query) | Check request body                                                                   |
| 408     | Search timeout                  | Retry with shorter query or fewer results                                            |
| 500     | Internal server error           | Check Firecrawl logs, restart if needed                                              |
| 502/503 | Service unavailable             | Container may be dead — see [self-hosted-operations.md](./self-hosted-operations.md) |

### curl Example

```bash
curl -s -X POST http://172.25.236.1:3002/v1/search \
   -H "Content-Type: application/json" \
   -d '{
      "query": "transformer attention mechanism",
      "limit": 3,
      "scrapeOptions": { "formats": ["markdown"] }
   }' | jq '.data[].url'
```

### fetch() Example

```typescript
async function firecrawlSearch(
  query: string,
  limit = 5,
): Promise<SearchResult> {
  const controller = new AbortController();
  const timeoutId = setTimeout(() => controller.abort(), 15_000);

  try {
    const res = await fetch("http://172.25.236.1:3002/v1/search", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        query,
        limit,
        scrapeOptions: { formats: ["markdown"] },
      }),
      signal: controller.signal,
    });

    if (!res.ok) {
      throw new Error(
        `Firecrawl search failed: ${res.status} ${res.statusText}`,
      );
    }

    return await res.json();
  } finally {
    clearTimeout(timeoutId);
  }
}
```

---

## POST /v1/scrape

Single URL scrape. Fetches a specific URL and returns its content as markdown.

### Request

```json
{
  "url": "https://arxiv.org/abs/2401.12345",
  "formats": ["markdown"],
  "waitFor": 3000
}
```

| Field     | Type     | Required | Default        | Description                           |
| --------- | -------- | -------- | -------------- | ------------------------------------- |
| `url`     | string   | Yes      | —              | URL to scrape                         |
| `formats` | string[] | No       | `["markdown"]` | Content formats                       |
| `waitFor` | number   | No       | 0              | Milliseconds to wait for JS rendering |

**When to use `waitFor`**: JS-heavy SPAs (IEEE Xplore, ACM DL, NeurIPS proceedings). Static pages (arxiv, blogs) don't need it.

### Response (200 OK)

```json
{
  "success": true,
  "data": {
    "markdown": "# Paper Title\n\nAbstract...",
    "metadata": {
      "title": "Paper Title",
      "description": "Abstract text",
      "sourceURL": "https://arxiv.org/abs/2401.12345"
    }
  }
}
```

| Field           | Type    | Description                  |
| --------------- | ------- | ---------------------------- |
| `success`       | boolean | Whether the scrape succeeded |
| `data.markdown` | string  | Page content as markdown     |
| `data.metadata` | object  | Page metadata                |

### curl Example

```bash
# Simple static page
curl -s -X POST http://172.25.236.1:3002/v1/scrape \
   -H "Content-Type: application/json" \
   -d '{"url":"https://arxiv.org/abs/2401.12345","formats":["markdown"]}' \
   | jq -r '.data.markdown'

# JS-heavy page (wait for rendering)
curl -s -X POST http://172.25.236.1:3002/v1/scrape \
   -H "Content-Type: application/json" \
   -d '{"url":"https://dl.acm.org/doi/10.1145/12345","formats":["markdown"],"waitFor":3000}' \
   | jq -r '.data.markdown'
```

### fetch() Example

```typescript
async function firecrawlScrape(
  url: string,
  waitFor?: number,
): Promise<ScrapeResult> {
  const controller = new AbortController();
  const timeoutId = setTimeout(() => controller.abort(), 30_000);

  try {
    const res = await fetch("http://172.25.236.1:3002/v1/scrape", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        url,
        formats: ["markdown"],
        ...(waitFor ? { waitFor } : {}),
      }),
      signal: controller.signal,
    });

    if (!res.ok) {
      throw new Error(
        `Firecrawl scrape failed: ${res.status} ${res.statusText}`,
      );
    }

    return await res.json();
  } finally {
    clearTimeout(timeoutId);
  }
}
```

---

## GET /v1/health

Health check endpoint. Use before starting a research session.

### Response (200 OK)

```json
{
  "status": "ok"
}
```

### curl Example

```bash
curl -sf http://172.25.236.1:3002/v1/health && echo "Firecrawl OK" || echo "Firecrawl UNHEALTHY"
```

### fetch() Example

```typescript
async function checkFirecrawlHealth(): Promise<boolean> {
  try {
    const res = await fetch("http://172.25.236.1:3002/v1/health", {
      signal: AbortSignal.timeout(5_000),
    });
    return res.ok;
  } catch {
    return false;
  }
}
```

---

## Self-Hosted Specifics

| Property           | Value                                               |
| ------------------ | --------------------------------------------------- |
| Base URL           | `http://172.25.236.1:3002`                          |
| API key            | Not required (self-hosted, no auth)                 |
| Network            | ZeroTier (must be connected)                        |
| Host               | littleblack                                         |
| Wrapper (optional) | `http://172.25.236.1:3003/scrape?url=URL&name=NAME` |

The wrapper at `:3003` saves markdown to disk and returns a file URL. For programmatic research workflows, prefer the direct API at `:3002` — it gives you full control over the response.
