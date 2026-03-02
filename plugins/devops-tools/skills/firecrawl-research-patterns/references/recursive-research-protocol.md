# Recursive Research Protocol

Step-by-step protocol for the iterative search → extract → recurse → synthesize pattern. Extracted from the working [deep-research Pi extension](~/fork-tools/pi-extensions/extensions/deep-research/).

---

## Parameters

| Parameter     | Default | Range      | Description                                  |
| ------------- | ------- | ---------- | -------------------------------------------- |
| `breadth`     | 4       | 1–10       | Search queries generated per recursion level |
| `depth`       | 2       | 1–5        | Maximum recursion depth (capped at 5)        |
| `concurrency` | 2       | 1–4        | Parallel Firecrawl requests via `p-limit`    |
| `limit`       | 5       | 1–10       | Results per Firecrawl `/v1/search` call      |
| `timeout`     | 15000ms | 5000–60000 | Per-search request timeout                   |

### Query Budget Estimation

Total queries at each depth level: `breadth` queries. Each recursion halves breadth.

```
Depth 1: breadth queries (e.g., 4)
Depth 2: breadth * ceil(breadth/2) queries (e.g., 4 * 2 = 8)
Depth 3: breadth * ceil(breadth/2) * ceil(ceil(breadth/2)/2) queries
```

For breadth=4, depth=2: approximately 4 + 8 = 12 total search queries.
For breadth=4, depth=3: approximately 4 + 8 + 8 = 20 total search queries.

---

## Protocol Steps

### Step 1: Health Check

Verify Firecrawl is reachable before starting. A failed health check saves minutes of wasted API calls.

```typescript
try {
  await fetch("http://172.25.236.1:3002/v1/health", {
    signal: AbortSignal.timeout(5_000),
  });
} catch {
  // Abort — see self-hosted-operations.md and troubleshooting.md references
}
```

If health check fails, do NOT proceed. Report the failure and suggest checking the Firecrawl deployment.

### Step 2: Generate Search Queries

Given the research topic and any prior learnings, generate N search queries (N = breadth).

**Input**: Topic string + accumulated learnings array
**Output**: Array of `{ query, researchGoal }` objects

```typescript
const queries = await generateSerpQueries(topic, breadth, priorLearnings);
// Returns: [{ query: "mixture of experts scaling", researchGoal: "understand scaling laws" }, ...]
```

The LLM generates diverse queries that avoid duplicating prior learnings. Each query has an explicit `researchGoal` used to focus follow-up recursion.

### Step 3: Execute Searches

For each query, call Firecrawl `/v1/search` with concurrency control via `p-limit`.

```typescript
import pLimit from "p-limit";

const limit = pLimit(concurrency); // default: 2

const results = await Promise.all(
  queries.map((q) =>
    limit(async () => {
      const searchResult = await firecrawlSearch(
        "http://172.25.236.1:3002",
        q.query,
        { timeout: 15_000, limit: 5 },
      );
      return { query: q, data: searchResult.data ?? [] };
    }),
  ),
);
```

### Step 4: Persist Raw Results

**CRITICAL**: Save each scraped page to `docs/research/corpus/` BEFORE any LLM processing. This ensures raw content survives even if the session is interrupted.

For each search result page:

1. Generate filename: `YYYY-MM-DD-{slug}.md`
2. Write file with YAML frontmatter + raw markdown body
3. Append entry to `docs/research/corpus-index.jsonl`

See [corpus-persistence-format.md](./corpus-persistence-format.md) for the exact file format.

### Step 5: Extract Learnings

For each set of search results, pass the scraped content to an LLM to extract:

- **Key learnings**: Factual findings, data points, conclusions
- **Follow-up questions**: Gaps in understanding that warrant deeper investigation

```typescript
// Trim each page to fit in context window
const trimmedContents = contents.map((c) => trimToTokenLimit(c, 25_000));

const extracted = await processSerpResult(
   query,
   trimmedContents,
   numLearnings: 3,    // Extract up to 3 learnings per result set
   numFollowUp: breadth / 2, // Generate follow-up questions for next depth
);
// Returns: { learnings: string[], followUpQuestions: string[] }
```

### Step 6: Recurse

For each follow-up question, recurse with halved breadth and decremented depth.

```typescript
const newBreadth = Math.ceil(breadth / 2);
const newDepth = depth - 1;

if (newDepth > 0) {
   const nextQuery = `Previous research goal: ${researchGoal}
Follow-up research directions: ${followUpQuestions.join("\n- ")}`;

   return researchLoop(nextQuery, newBreadth, newDepth, allLearnings, ...);
}
```

**Why halve breadth**: Deeper levels explore narrower sub-topics. Halving breadth prevents exponential query explosion while maintaining focus.

### Step 7: Base Case

When `depth = 0`, return accumulated learnings without further recursion.

```typescript
if (depth === 0) {
  return { learnings: allLearnings, visitedUrls: allUrls };
}
```

### Step 8: Early Stopping

Stop recursion early when all new learnings duplicate prior ones (no new information being discovered):

```typescript
const newLearnings = extracted.learnings.filter(
  (l) => !priorLearnings.some((p) => similarity(l, p) > 0.9),
);
if (newLearnings.length === 0) {
  // No new information — stop recursing this branch
  return { learnings: allLearnings, visitedUrls: allUrls };
}
```

### Step 9: Synthesize Final Report

Pass all accumulated learnings to an LLM for a structured markdown report.

```typescript
const report = await writeFinalReport(topic, allLearnings, visitedUrls);
```

The report should:

- Organize learnings by theme/subtopic
- Include a Sources section referencing raw corpus files by relative path
- Highlight areas of consensus and disagreement across sources
- Note gaps where information was unavailable

### Step 10: Write Session Report

Save the synthesized report to `docs/research/sessions/YYYY-MM-DD-{topic-slug}.md`.

The session report includes a Sources table linking to raw corpus files:

```markdown
## Sources

| #   | Title              | Corpus File                                                                           | Tokens |
| --- | ------------------ | ------------------------------------------------------------------------------------- | ------ |
| 1   | Scaling MoE...     | [corpus/2026-02-25-moe-scaling-arxiv.md](../corpus/2026-02-25-moe-scaling-arxiv.md)   | 4200   |
| 2   | Switch Transformer | [corpus/2026-02-25-switch-transformer.md](../corpus/2026-02-25-switch-transformer.md) | 6100   |
```

---

## Handling Partial Failures

The protocol is designed to tolerate failures at every level:

| Failure Point                | Impact                       | Recovery                                           |
| ---------------------------- | ---------------------------- | -------------------------------------------------- |
| Query generation fails       | No queries for this level    | Return accumulated learnings                       |
| Single search times out      | Misses one query's results   | Log failure, continue with remaining queries       |
| All searches at a level fail | No new content               | Return prior learnings (degraded but usable)       |
| Learning extraction fails    | Misses insights from results | Raw corpus files still preserved for manual review |
| Report generation fails      | No synthesized output        | Accumulated learnings array is still available     |
| Corpus persistence fails     | Raw content not saved        | Critical — retry or save to temp location          |

**Principle**: At every level, partial results are returned rather than throwing. The `queriesFailed` array tracks what didn't work.

---

## Deduplication

Results are deduplicated at the learning and URL level:

```typescript
return {
  learnings: [...new Set(results.flatMap((r) => r.learnings))],
  visitedUrls: [...new Set(results.flatMap((r) => r.visitedUrls))],
};
```

The corpus index (`corpus-index.jsonl`) enables cross-session deduplication — check if a URL was already scraped before re-scraping.

---

## Visualization

```
Topic: "mixture of experts scaling"
│
├─ Depth 1 (breadth=4)
│  ├─ Query 1: "MoE scaling laws" → 5 pages → 3 learnings
│  ├─ Query 2: "switch transformer efficiency" → 5 pages → 2 learnings
│  ├─ Query 3: "expert parallelism GPU" → 5 pages → 3 learnings
│  └─ Query 4: "MoE vs dense models" → 5 pages → 2 learnings
│     │
│     └─ Depth 2 (breadth=2, per follow-up from each Query)
│        ├─ Follow-up 1a: "MoE load balancing" → 5 pages → 2 learnings
│        ├─ Follow-up 1b: "expert dropout" → 5 pages → 1 learning
│        ├─ Follow-up 2a: "MoE inference cost" → 5 pages → 2 learnings
│        └─ ... (more follow-ups)
│
└─ Synthesize: 15+ learnings → Final Report
   └─ Corpus: 20-40 raw markdown files preserved
```
