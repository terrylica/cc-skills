# Academic Paper Routing

Decision tree for choosing the best retrieval method based on paper source. Optimized for content quality and reliability.

---

## Routing Table

| Source                | Best Method                     | Why                                 | Fallback                            | `waitFor` |
| --------------------- | ------------------------------- | ----------------------------------- | ----------------------------------- | --------- |
| arxiv.org             | Direct HTML (`/html/ID`)        | Free, structured, no JS             | Firecrawl `/v1/scrape` on `/abs/ID` | No        |
| Semantic Scholar      | API (`api.semanticscholar.org`) | Structured JSON, free, rate-limited | Firecrawl search for paper title    | No        |
| ACL Anthology         | Firecrawl `/v1/scrape`          | Clean HTML, free access             | Direct PDF download                 | No        |
| NeurIPS/ICML/ICLR     | Firecrawl `/v1/scrape`          | JS-rendered proceedings pages       | Firecrawl search by title           | 2000      |
| IEEE Xplore           | Firecrawl `/v1/scrape`          | Heavy JS SPA                        | Author's personal website           | 3000      |
| ACM Digital Library   | Firecrawl `/v1/scrape`          | Heavy JS SPA                        | Author's personal website           | 3000      |
| Author blogs/websites | Jina Reader (`r.jina.ai`)       | Static HTML, fast, clean output     | Firecrawl `/v1/scrape`              | No        |
| Google Scholar        | Firecrawl `/v1/search`          | Needs JS rendering for results      | Direct search query reformulation   | No        |

---

## Source-Specific Patterns

### arxiv.org

arxiv provides multiple access paths. Prefer HTML over PDF for LLM consumption.

```
arxiv.org/abs/2401.12345      → metadata page (abstract, authors)
arxiv.org/html/2401.12345     → full HTML paper (preferred for LLM)
arxiv.org/pdf/2401.12345      → PDF (less useful for text extraction)
```

**Primary**: Direct `fetch()` on the HTML version:

```typescript
const arxivId = "2401.12345";
const res = await fetch(`https://arxiv.org/html/${arxivId}`);
const html = await res.text();
// Convert HTML to markdown or pass to Firecrawl for conversion
```

**Important**: Use port 3003 (not Jina Reader) for arXiv papers that contain figures. Playwright resolves `<img src>` attributes to absolute URLs so you can extract and download them. Jina Reader is text-only and silently drops all figures.

#### Downloading arXiv Figures

arXiv HTML papers store figures with sequential names (`x1.png`, `x2.png`, …) at the paper's HTML base URL.

```bash
# Pattern: https://arxiv.org/html/{id}v{version}/x{N}.png
# (version defaults to latest if omitted)
ARXIV_ID="2401.12345"
BASE="https://arxiv.org/html/${ARXIV_ID}/"
mkdir -p "figures/${ARXIV_ID}"

for i in $(seq 1 50); do
  url="${BASE}x${i}.png"
  out="figures/${ARXIV_ID}/x${i}.png"
  http_code=$(curl -s -o "$out" -w "%{http_code}" "$url")
  if [ "$http_code" = "404" ]; then
    rm -f "$out"
    break   # sequential naming — first 404 means no more figures
  fi
  echo "Downloaded x${i}.png (HTTP $http_code)"
done
```

**Notes**:

- Files are `x1.png`, `x2.png`, … (sequential, 1-indexed)
- Stop at the first 404 — naming is contiguous with no gaps
- Some papers use `.svg` or `.jpg`; try `.png` first, then probe alternatives
- Version suffix: `https://arxiv.org/html/2401.12345v2/` for a specific version

**Fallback**: If `/html/` is unavailable (older papers), use Firecrawl to scrape `/abs/`:

```typescript
const res = await fetch("http://172.25.236.1:3002/v1/scrape", {
  method: "POST",
  headers: { "Content-Type": "application/json" },
  body: JSON.stringify({
    url: `https://arxiv.org/abs/${arxivId}`,
    formats: ["markdown"],
  }),
});
```

### Semantic Scholar

API-first approach for structured metadata. Free tier: 100 requests/5 minutes.

```typescript
// Search by title
const res = await fetch(
  `https://api.semanticscholar.org/graph/v1/paper/search?query=${encodeURIComponent(title)}&limit=5&fields=title,abstract,url,year,authors,citationCount`,
);
const { data } = await res.json();

// Get by paper ID (S2 ID, DOI, arxiv ID, etc.)
const paper = await fetch(
  `https://api.semanticscholar.org/graph/v1/paper/${paperId}?fields=title,abstract,url,year,authors,references,citations`,
);
```

**Fallback**: If API rate-limited or paper not indexed, search via Firecrawl:

```typescript
const res = await fetch("http://172.25.236.1:3002/v1/search", {
  method: "POST",
  headers: { "Content-Type": "application/json" },
  body: JSON.stringify({
    query: `"${paperTitle}" site:semanticscholar.org`,
    limit: 3,
    scrapeOptions: { formats: ["markdown"] },
  }),
});
```

### Conference Proceedings (NeurIPS, ICML, ICLR)

These use JS-rendered pages. Always use `waitFor`:

```typescript
const res = await fetch("http://172.25.236.1:3002/v1/scrape", {
  method: "POST",
  headers: { "Content-Type": "application/json" },
  body: JSON.stringify({
    url: proceedingsUrl,
    formats: ["markdown"],
    waitFor: 2000,
  }),
});
```

### IEEE Xplore / ACM Digital Library

Heavy JS SPAs that require extended wait times:

```typescript
const res = await fetch("http://172.25.236.1:3002/v1/scrape", {
  method: "POST",
  headers: { "Content-Type": "application/json" },
  body: JSON.stringify({
    url: ieeeOrAcmUrl,
    formats: ["markdown"],
    waitFor: 3000, // Critical — page won't render without this
  }),
});
```

**Note**: Paywalled content may return only abstract + metadata. For full text, check if the author has a preprint on arxiv or their personal website.

### Author Blogs / Personal Websites

Static HTML — Jina Reader is faster and cleaner than Firecrawl:

```bash
curl -s "https://r.jina.ai/https://author-blog.com/post-about-paper"
```

Or via WebFetch in Claude Code:

```
WebFetch(url="https://r.jina.ai/https://author-blog.com/post", prompt="Extract full content")
```

---

## DOI Resolution

DOIs redirect to the publisher's canonical URL. Resolve first, then route:

```typescript
// Follow redirects to get the publisher URL
const res = await fetch(`https://doi.org/${doi}`, { redirect: "follow" });
const publisherUrl = res.url;

// Route based on publisher domain
if (publisherUrl.includes("arxiv.org")) {
  // → arxiv path
} else if (publisherUrl.includes("dl.acm.org")) {
  // → ACM DL path with waitFor: 3000
} else if (publisherUrl.includes("ieeexplore.ieee.org")) {
  // → IEEE path with waitFor: 3000
} else {
  // → Generic Firecrawl scrape
}
```

---

## Preprint vs Published Version Detection

When a paper exists in multiple locations:

1. **Prefer arxiv HTML** — free, structured, no paywalls
2. **Check Semantic Scholar** for citation metadata + links to all versions
3. **Use published version** only when arxiv version is significantly outdated (check version dates)

```typescript
// Semantic Scholar returns all known versions
const paper = await fetch(
  `https://api.semanticscholar.org/graph/v1/paper/search?query=${title}&fields=externalIds,url`,
);
// externalIds: { ArXiv: "2401.12345", DOI: "10.1145/...", ... }
```

---

## Citation Extraction

For extracting references from a paper's bibliography:

1. **Semantic Scholar API** — best for structured citation data:

```typescript
const refs = await fetch(
  `https://api.semanticscholar.org/graph/v1/paper/${paperId}/references?fields=title,authors,year,externalIds&limit=100`,
);
```

1. **Firecrawl scrape** of references section — when API doesn't have the paper

---

## Complement to Existing Routing

This table extends `Skill(gh-tools:research-archival)` URL routing, which covers:

- ChatGPT share URLs → Jina Reader
- Gemini share URLs → Firecrawl
- Claude artifacts → Jina Reader

This skill adds academic-specific routing. The two are complementary — use `research-archival` for AI chat conversations, this skill for academic papers and research content.
