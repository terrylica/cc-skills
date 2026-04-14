# Academic Paper Routing

Decision tree for choosing the best retrieval method based on paper source. Optimized for content quality and reliability.

---

## Routing Table

| Source                | Best Method                     | Why                                                                                      | Fallback                          | `waitFor` |
| --------------------- | ------------------------------- | ---------------------------------------------------------------------------------------- | --------------------------------- | --------- |
| arxiv.org             | Port 3003 (`/scrape?url=...`)   | **+17% more content** than Jina (99KB vs 85KB), 13 figures vs 12, identical to port 3002 | Jina Reader (when gpu-host down)  | No        |
| Semantic Scholar      | API (`api.semanticscholar.org`) | Structured JSON, free, rate-limited                                                      | Firecrawl search for paper title  | No        |
| ACL Anthology         | Firecrawl `/v1/scrape`          | Clean HTML, free access                                                                  | Direct PDF download               | No        |
| NeurIPS/ICML/ICLR     | Firecrawl `/v1/scrape`          | JS-rendered proceedings pages                                                            | Firecrawl search by title         | 2000      |
| IEEE Xplore           | Firecrawl `/v1/scrape`          | Heavy JS SPA                                                                             | Author's personal website         | 3000      |
| ACM Digital Library   | Firecrawl `/v1/scrape`          | Heavy JS SPA                                                                             | Author's personal website         | 3000      |
| Author blogs/websites | Jina Reader (`r.jina.ai`)       | Static HTML, fast, clean output                                                          | Firecrawl `/v1/scrape`            | No        |
| Google Scholar        | Firecrawl `/v1/search`          | Needs JS rendering for results                                                           | Direct search query reformulation | No        |

---

## Source-Specific Patterns

### arxiv.org

arxiv provides multiple access paths. Prefer HTML over PDF for LLM consumption.

```
arxiv.org/abs/2401.12345      → metadata page (abstract, authors)
arxiv.org/html/2401.12345     → full HTML paper (preferred for LLM)
arxiv.org/pdf/2401.12345      → PDF (less useful for text extraction)
```

**Primary**: Port 3003 (Firecrawl wrapper) — empirically gets 17% more content than Jina:

```bash
curl "http://gpu-host:3003/scrape?url=https://arxiv.org/html/2401.12345&name=paper-slug"
# Returns: {"url":"http://gpu-host:8080/paper-slug-TIMESTAMP.md","file":"..."}
```

**Fallback** (when gpu-host is down): Jina Reader:

```bash
curl -s "https://r.jina.ai/https://arxiv.org/html/2401.12345" -o paper.md
```

**Empirically validated (arXiv:2312.00752v2, Mamba paper, March 2026)**:

- Port 3003: 99,104 bytes, 1,267 lines, 13 figures (absolute inline URLs ✅)
- Jina Reader: 84,832 bytes, 596 lines, 12 figures (absolute inline URLs ✅)
- Both emit absolute figure URLs — no URL reconstruction needed
- The earlier session timeout was machine downtime, not a routing issue — port 3003 reaches arxiv.org fine when gpu-host is online

**Math rendering gap** (empirically validated): Both Jina and Firecrawl double all equations — each equation appears as Unicode render + raw LaTeX source in the same table cell with `\displaystyle` prefixes, no `$...$` delimiters. Unreadable on GitHub for humans; LaTeX is still parseable by LLMs. For human-readable GFM math, use Pandoc from the arXiv LaTeX source tarball (`--to gfm+tex_math_dollars`) — produces proper `$inline$` and ` ```math ``` ` blocks GitHub renders, but paper-specific custom macros (`\A`, `\B`, `\R`, etc.) need the preamble's `\newcommand` definitions prepended (see Section 6 of SKILL.md).

#### arXiv Figure URL Pattern

arXiv HTML papers store figures at sequential absolute URLs (`x1.png`, `x2.png`, …). The correct approach is to **keep these URLs inline in the markdown body** and **catalog them in the YAML frontmatter** — do NOT download to local paths (relative paths break on GitHub).

```bash
# Probe sequential URLs to discover figure_count — collect absolute URLs for frontmatter
ARXIV_ID="2401.12345"
BASE="https://arxiv.org/html/${ARXIV_ID}/"
FIGURE_URLS=()

for i in $(seq 1 50); do
  url="${BASE}x${i}.png"
  http_code=$(curl -s -o /dev/null -w "%{http_code}" "$url")
  if [ "$http_code" = "404" ]; then
    echo "Found ${#FIGURE_URLS[@]} figures (stopped at x${i}.png)"
    break
  fi
  FIGURE_URLS+=("$url")
done

# Embed inline in GFM corpus markdown (renders on GitHub without hosting):
for i in "${!FIGURE_URLS[@]}"; do
  echo "![Figure $((i+1))](${FIGURE_URLS[$i]})"
done
```

**Frontmatter catalog** (YAML, inside the corpus `.md` file):

```yaml
has_figures: true
figure_count: 12
figure_urls:
  - https://arxiv.org/html/2401.12345/x1.png
  - https://arxiv.org/html/2401.12345/x2.png
  - https://arxiv.org/html/2401.12345/x3.png
```

**Notes**:

- Files are `x1.png`, `x2.png`, … (sequential, 1-indexed); first 404 means no more figures
- Some papers use `.svg` or `.jpg`; probe `.png` first, then alternatives
- Version suffix: `https://arxiv.org/html/2401.12345v2/` for a specific version
- Port 3003 already embeds these as inline absolute URLs — just extract them with `grep -oE 'https://arxiv.org/html/[^)]+\.png'`

**Fallback**: If `/html/` is unavailable (older papers), use Firecrawl to scrape `/abs/`:

```typescript
const res = await fetch("http://gpu-host:3002/v1/scrape", {
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
const res = await fetch("http://gpu-host:3002/v1/search", {
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
const res = await fetch("http://gpu-host:3002/v1/scrape", {
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
const res = await fetch("http://gpu-host:3002/v1/scrape", {
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
