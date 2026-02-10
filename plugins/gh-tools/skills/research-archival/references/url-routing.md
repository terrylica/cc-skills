# URL Routing

Route scrape requests to the correct backend based on URL pattern.

## Routing Table

| URL Pattern                 | Scraper     | Why                                                | Endpoint                          |
| --------------------------- | ----------- | -------------------------------------------------- | --------------------------------- |
| `chatgpt.com/share/*`       | Jina Reader | Cleaner markdown than Firecrawl (no escaped chars) | `https://r.jina.ai/{URL}`         |
| `gemini.google.com/share/*` | Firecrawl   | JS-heavy SPA, needs headless browser               | `http://172.25.236.1:3003/scrape` |
| `claude.ai/artifacts/*`     | Jina Reader | Static content, no JS rendering needed             | `https://r.jina.ai/{URL}`         |
| Other web pages             | Jina Reader | Default fallback for static pages                  | `https://r.jina.ai/{URL}`         |

> **2026-02-09 finding**: ChatGPT share URLs moved from Firecrawl to Jina Reader.
> Firecrawl produced escaped markdown (`\*\*bold\*\*`) and included ChatGPT UI chrome.
> Jina Reader via `curl` produces clean, structured conversation output.

## Firecrawl (Self-Hosted)

**Host**: `littleblack` via ZeroTier (`172.25.236.1:3003`)

### Preflight Check

```bash
# Verify ZeroTier connectivity
ping -c1 -W2 172.25.236.1 >/dev/null 2>&1 && echo "OK" || echo "UNREACHABLE"
```

### Scrape Command

```bash
curl -s "http://172.25.236.1:3003/scrape?url=${URL}&name=${SLUG}"
```

**Parameters**:

- `url` - Full URL to scrape (URL-encoded)
- `name` - Slug for the scrape job (used in logs)

### Response

Returns markdown content directly. Check for non-empty response.

## Jina Reader (Fallback)

**Endpoint**: `https://r.jina.ai/{URL}`

### Usage via WebFetch

```
WebFetch(url="https://r.jina.ai/https://example.com/page", prompt="Extract all content")
```

### Usage via curl

```bash
curl -s "https://r.jina.ai/${URL}"
```

## Fallback Chain

```
1. Route to primary scraper (Firecrawl or Jina based on URL pattern)
2. If Firecrawl fails → try Jina Reader
3. If Jina fails → report failure (do not silently continue)
```

## Troubleshooting

| Issue                          | Diagnosis              | Fix                                 |
| ------------------------------ | ---------------------- | ----------------------------------- |
| Firecrawl connection refused   | ZeroTier not connected | `zerotier-cli status`, join network |
| Firecrawl timeout              | Page too complex       | Increase timeout, try Jina fallback |
| Jina returns truncated content | Page is JS-heavy       | Use Firecrawl instead               |
| Empty response                 | URL requires auth      | Cannot scrape — note in frontmatter |
