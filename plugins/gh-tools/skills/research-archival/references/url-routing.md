# URL Routing

Route scrape requests to the correct backend based on URL pattern.

## Routing Table

| URL Pattern                 | Scraper   | Why                                      | Endpoint                                   |
| --------------------------- | --------- | ---------------------------------------- | ------------------------------------------ |
| `chatgpt.com/share/*`       | Firecrawl | JS-rendered SPA; Jina truncates it badly | `POST https://api.firecrawl.dev/v2/scrape` |
| `gemini.google.com/share/*` | Firecrawl | JS-heavy SPA, needs a headless browser   | `POST https://api.firecrawl.dev/v2/scrape` |
| `claude.ai/artifacts/*`     | Firecrawl | JS-rendered                              | `POST https://api.firecrawl.dev/v2/scrape` |
| Simple static pages         | Either    | Jina is one GET and adequate             | `https://r.jina.ai/{URL}`                  |

**Default to Firecrawl for anything JS-rendered.** On two `chatgpt.com/share/*` links measured
2026-08-13, Jina returned 9,397 and 15,960 chars against Firecrawl's 57,616 and 136,590 — **17% and
12% coverage** — and truncated mid-sentence, while Firecrawl reached the true page footer both
times. The extra bulk was real content (76 vs 12 headings, 128 vs 22 table rows), not boilerplate.

## Firecrawl (public API)

**Base**: `https://api.firecrawl.dev` — public internet, **no API key required**, no tunnel, no
tailnet, no host to be down. There is no health endpoint; do not probe for one.

```bash
curl -sS --max-time 180 -X POST https://api.firecrawl.dev/v2/scrape \
  -H "Content-Type: application/json" \
  -d "$(jq -n --arg u "$URL" \
        '{url: $u, formats: ["markdown"], waitFor: 8000, timeout: 60000}')" \
  | jq -r '.data.markdown // empty'
```

**Parameters that matter**:

- `waitFor` — milliseconds to let the SPA render. Without it a share link returns the app shell.
  Raise to 15000 if output looks like chrome rather than content.
- `timeout` — server-side cap, in milliseconds.

**Use v2, not v1.** Both answer unauthenticated, but the `search` response shape differs
(`v1: data: [...]` vs `v2: data: {web: [...]}`) and v1 is being sunset — a malformed v1 body is
answered with _"please review the v2 API documentation"_.

> **Do not reintroduce a self-hosted Firecrawl.** The littleblack deployment (ports 3002/3003) was
> retired 2026-08-13, reclaiming ~18 GB. At this repo's volume the public API is sufficient, and it
> removes the health-check, container-restart and WORKER-STALLED triage the self-hosted stack needed.

## Jina Reader (fallback)

**Endpoint**: `https://r.jina.ai/{URL}`

```bash
curl -s -H "x-timeout: 30" "https://r.jina.ai/${URL}"
```

The `x-timeout` header is **required** — without it, a JS-rendered page returns ~321 bytes of login
chrome that reads like a successful scrape. Always check the byte count before trusting the output.

## Fallback Chain

```
1. Firecrawl public API
2. If Firecrawl returns no `.data.markdown` → retry once (transient), then Jina Reader
3. If Jina also fails → report failure (do not silently continue)
```

## Troubleshooting

| Issue                          | Diagnosis                        | Fix                                             |
| ------------------------------ | -------------------------------- | ----------------------------------------------- |
| Firecrawl returns no markdown  | Transient API failure            | Retry once, then fall back to Jina              |
| Response is the page shell     | SPA had not rendered             | Raise `waitFor` to 15000 and `timeout` to 90000 |
| Jina returns ~321 bytes        | Missing `x-timeout` header       | Add `-H "x-timeout: 30"`                        |
| Jina returns truncated content | Jina under-covers JS-heavy pages | Expected — use Firecrawl                        |
| Empty response from both       | URL requires auth                | Cannot scrape — note it in the frontmatter      |
