# Validating LaTeX/KaTeX Equations in Markdown for CI

## Overview

For a 200-line Markdown file with ~50 equations spanning inline (`$...$`), display (`$$...$$`), and fenced (` ```math `) blocks, the recommended CI-friendly approach is a Node.js script using KaTeX's `renderToString` in strict mode. This catches syntax errors at parse time without needing a browser or full LaTeX installation.

---

## Recommended Approach: KaTeX CLI Validation Script

### Why KaTeX?

- Pure JavaScript — no LaTeX distribution required
- Fast enough for CI (50 equations in < 1 second)
- Strict mode throws on unsupported or malformed syntax
- Matches what GitHub renders (GitHub uses KaTeX for math in Markdown)

### Setup

```bash
npm install katex
# or
bun add katex
```

### Validation Script (`validate-math.mjs`)

````js
import { readFileSync } from "fs";
import katex from "katex";

const file = process.argv[2];
if (!file) {
  console.error("Usage: node validate-math.mjs <file.md>");
  process.exit(1);
}

const content = readFileSync(file, "utf8");
const errors = [];

function validate(expr, mode, lineHint) {
  try {
    katex.renderToString(expr, {
      displayMode: mode === "display",
      throwOnError: true,
      strict: "error",
    });
  } catch (e) {
    errors.push({
      lineHint,
      mode,
      expr: expr.slice(0, 60),
      message: e.message,
    });
  }
}

// Extract fenced ```math blocks first, then remove them to avoid double-matching
let remaining = content;
const fencedRe = /^```math\n([\s\S]*?)^```/gm;
for (const m of content.matchAll(fencedRe)) {
  const lineHint = content.slice(0, m.index).split("\n").length;
  validate(m[1].trim(), "display", `line ~${lineHint} (fenced math block)`);
  remaining = remaining.replace(m[0], " ".repeat(m[0].length));
}

// Extract display blocks $$...$$
const displayRe = /\$\$([\s\S]*?)\$\$/g;
for (const m of remaining.matchAll(displayRe)) {
  const lineHint = remaining.slice(0, m.index).split("\n").length;
  validate(m[1].trim(), "display", `line ~${lineHint} (display $$)`);
}

// Remove display blocks before scanning for inline
remaining = remaining.replace(/\$\$([\s\S]*?)\$\$/g, (s) =>
  " ".repeat(s.length),
);

// Extract inline $...$
// Heuristic: $ not preceded/followed by space, and not empty
const inlineRe = /(?<!\$)\$(?!\$)([^$\n]+?)\$(?!\$)/g;
for (const m of remaining.matchAll(inlineRe)) {
  const lineHint = remaining.slice(0, m.index).split("\n").length;
  validate(m[1].trim(), "inline", `line ~${lineHint} (inline $)`);
}

if (errors.length === 0) {
  console.log(`✓ All equations valid (${file})`);
  process.exit(0);
} else {
  console.error(`✗ ${errors.length} equation error(s) in ${file}:\n`);
  for (const e of errors) {
    console.error(`  [${e.lineHint}] ${e.mode}: "${e.expr}"`);
    console.error(`    → ${e.message}\n`);
  }
  process.exit(1);
}
````

### Running It

```bash
node validate-math.mjs paper.md
# Exit 0 = all OK, Exit 1 = errors found with details
```

---

## CI Integration

### GitHub Actions

```yaml
# .github/workflows/validate-math.yml
name: Validate Math

on:
  push:
    paths: ["**/*.md"]
  pull_request:
    paths: ["**/*.md"]

jobs:
  math:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version: "20"
      - run: npm install katex
      - run: node validate-math.mjs paper.md
```

### Pre-commit Hook (local, runs before push)

```yaml
# .pre-commit-config.yaml
repos:
  - repo: local
    hooks:
      - id: validate-math
        name: Validate KaTeX equations
        language: node
        entry: node validate-math.mjs
        files: \.md$
        additional_dependencies: ["katex"]
```

Or a simple shell hook in `.git/hooks/pre-push`:

```bash
#!/bin/sh
node validate-math.mjs paper.md || exit 1
```

---

## Alternative Tools

| Tool                                           | Approach                 | Pros                                             | Cons                           |
| ---------------------------------------------- | ------------------------ | ------------------------------------------------ | ------------------------------ |
| **KaTeX** (above)                              | JS parse-time validation | Fast, no LaTeX install, matches GitHub           | Won't catch semantic errors    |
| **`pandoc --to pdf`**                          | Full LaTeX compile       | Catches everything                               | Requires TeX Live, slow (~30s) |
| **`unified` + `remark-math` + `rehype-katex`** | Unified pipeline         | Pluggable, integrates with existing MD pipelines | More setup                     |
| **`mathjax-node`**                             | MathJax render           | Mature, comprehensive support                    | Slower startup than KaTeX      |
| **`mlint` / `chktex`**                         | LaTeX linting            | Deep LaTeX checks                                | Overkill for Markdown math     |

### `unified` Pipeline Alternative

If you already use `remark` for processing Markdown:

```bash
npm install unified remark-parse remark-math rehype-katex remark-rehype
```

```js
import { unified } from "unified";
import remarkParse from "remark-parse";
import remarkMath from "remark-math";
import remarkRehype from "remark-rehype";
import rehypeKatex from "rehype-katex";
import { readFileSync } from "fs";

const content = readFileSync(process.argv[2], "utf8");

try {
  await unified()
    .use(remarkParse)
    .use(remarkMath)
    .use(remarkRehype)
    .use(rehypeKatex, { throwOnError: true, strict: "error" })
    .process(content);
  console.log("All equations valid");
} catch (e) {
  console.error(e.message);
  process.exit(1);
}
```

This approach also handles the ` ```math ` fenced blocks natively via `remark-math`.

---

## Handling the Three Block Types

| Syntax                | KaTeX mode           | Notes                                               |
| --------------------- | -------------------- | --------------------------------------------------- |
| `$...$`               | `displayMode: false` | Single-line only; watch out for currency symbols    |
| `$$...$$`             | `displayMode: true`  | Can span lines                                      |
| ` ```math\n...\n``` ` | `displayMode: true`  | GitHub-specific extension; `remark-math` handles it |

The script above handles all three. The key ordering: strip fenced blocks first, then `$$`, then `$` — prevents the `$` regex from matching inside already-processed blocks.

---

## Practical Tips

1. **Currency false positives**: If your Markdown has `$50` or `$USD`, the inline regex can misfire. Add a heuristic: skip matches where the content looks like a number (e.g., `/^\d/`).

2. **Multi-line inline**: The inline regex above uses `[^$\n]+` to avoid crossing line boundaries — important to prevent false matches across paragraphs.

3. **Exit codes**: The script exits `1` on any error, making it drop-in compatible with CI "fail fast" policies.

4. **Collecting all errors vs. fail-fast**: The script above collects all errors before exiting, giving you a full report rather than stopping at the first bad equation — more useful for a 50-equation file.

5. **KaTeX version pinning**: Pin your KaTeX version (`"katex": "0.16.x"`) to prevent a KaTeX upgrade from changing what parses as valid and breaking CI unexpectedly.
