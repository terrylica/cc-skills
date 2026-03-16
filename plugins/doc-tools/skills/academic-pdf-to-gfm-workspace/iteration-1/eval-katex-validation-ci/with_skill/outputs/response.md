# Validating Math Equations in GFM Markdown Before Pushing to GitHub

Here is the complete CI-friendly approach for validating all three equation formats in your 200-line file.

## Step 1: Install KaTeX (Bun-first)

```bash
bun add -g katex
```

Or with npm if you prefer:

```bash
npm install -g katex
```

## Step 2: Save the Validator Script

Save this as `validate-math.mjs` (e.g., in a `scripts/` or `references/` directory alongside your markdown):

````js
#!/usr/bin/env node
// validate-math.mjs — KaTeX batch validator for GFM files
// Usage: node validate-math.mjs your-file.md
// Exits 1 if any math block fails KaTeX parsing (CI-friendly)
//
// Checks: $...$, $$...$$, and ```math...``` blocks
// Reports: line number + equation snippet for each error

import { readFileSync } from "fs";
import katex from "katex";

const filePath = process.argv[2];
if (!filePath) {
  console.error("Usage: node validate-math.mjs <file.md>");
  process.exit(2);
}

const src = readFileSync(filePath, "utf8");

// Match all three block types:
//   1. ```math\n...\n```  (fenced)
//   2. $$\n...\n$$       (display, multi-line)
//   3. $...$             (inline, single-line)
const blocks = [
  ...src.matchAll(
    /```math\n([\s\S]+?)```|\$\$\n?([\s\S]+?)\n?\$\$|\$([^\$\n]+?)\$/g,
  ),
];

let errors = 0;
let checked = 0;

for (const match of blocks) {
  const [full, fence, display, inline] = match;
  const eq = (fence || display || inline).trim();
  if (!eq) continue;

  checked++;
  const lineNo = src.slice(0, match.index).split("\n").length;

  try {
    katex.renderToString(eq, {
      throwOnError: true,
      displayMode: !inline,
      strict: false,
    });
  } catch (e) {
    console.error(`Line ~${lineNo}: ${e.message}`);
    console.error(`  EQ: ${eq.slice(0, 100).replace(/\n/g, " ")}`);
    console.error("");
    errors++;
  }
}

if (errors === 0) {
  console.log(`✓ ${checked} equations checked — no errors.`);
} else {
  console.log(`\n${checked} equations checked, ${errors} error(s).`);
}

process.exit(errors > 0 ? 1 : 0);
````

## Step 3: Run Before Every Push

```bash
node validate-math.mjs your-file.md
```

The script handles all three formats in your file:

| Format            | Example               | Handled? |
| ----------------- | --------------------- | -------- |
| Inline            | `$E = mc^2$`          | Yes      |
| Display block     | `$$\n...\n$$`         | Yes      |
| Fenced code block | ` ```math\n...\n``` ` | Yes      |

On success you get:

```
✓ 50 equations checked — no errors.
```

On failure you get per-error output like:

```
Line ~47: KaTeX parse error: Expected '}', got 'EOF' at position 12: \frac{1}{T
  EQ: \frac{1}{T

2 equations checked, 1 error(s).
```

Exit code is `1` when any equation fails, `0` when all pass — this is what makes it CI-friendly.

## Step 4: Wire It Into CI

### GitHub Actions (add to your workflow YAML)

```yaml
- name: Validate math equations
  run: |
    bun add -g katex
    node scripts/validate-math.mjs your-file.md
```

### Pre-push git hook (local enforcement)

```bash
# .git/hooks/pre-push  (make executable: chmod +x .git/hooks/pre-push)
#!/bin/sh
node scripts/validate-math.mjs your-file.md || exit 1
```

## Critical Limitation: KaTeX Passes ≠ GitHub Renders Correctly

KaTeX validates LaTeX syntax, but GitHub's markdown pre-processor runs **before** the math renderer and strips `\\` (double-backslash line breaks). This means:

**A KaTeX-passing equation can still break on GitHub.**

The rule is:

| Equation type                                  | Use             | Why                             |
| ---------------------------------------------- | --------------- | ------------------------------- |
| Single-line display                            | `$$...$$`       | No `\\` — pre-processor safe    |
| Multi-line (`\\`, `\begin{aligned}`, matrices) | ` ```math ``` ` | Pre-processor skips code fences |
| Inline                                         | `$...$`         | Standard                        |

So after KaTeX validation passes, also check: **any `$$` block containing `\\` must be converted to a ` ```math ``` ` block.** Example:

````markdown
# BROKEN on GitHub (KaTeX passes, but \\ gets stripped):

$$
\begin{aligned}
a &= b + c \\
d &= e + f
\end{aligned}
$$

# CORRECT on GitHub:

```math
\begin{aligned}
a &= b + c \\
d &= e + f
\end{aligned}
```
````

````

You already have some ` ```math ` blocks — keep them. Convert any remaining `$$` blocks that contain `\\` or `\begin{aligned}` to ` ```math ` as well.

## Additional Display Block Formatting Rules

GitHub has strict rules for `$$` blocks that KaTeX does not check:

- `$$` must be on its **own line** — `$$formula$$` on one line is treated as text, not display math.
- A **blank line** is required before AND after every `$$` block.
- A **blank line** is required between consecutive `$$` blocks (otherwise GitHub merges them into one broken block).

These rules do **not** apply to ` ```math ``` ` blocks.

## Commands to Avoid (GitHub-Specific Incompatibilities)

| Command | Problem | Fix |
|---------|---------|-----|
| `\begin{align}` | Not supported by GitHub | Use `\begin{aligned}` |
| `\boxed{}` | Can cause raw LaTeX passthrough | Remove or use bold text |
| `\operatorname{}` | Active GitHub bug, inconsistent rendering | Use `\text{}` or `\mathrm{}` |
| `\newcommand` | Pulled from GitHub — never works | Expand all macros inline |

## Summary Checklist

- [ ] `bun add -g katex` installed
- [ ] `node validate-math.mjs your-file.md` exits `0`
- [ ] All `$$` blocks containing `\\` converted to ` ```math ``` `
- [ ] All `$$` are on their own line (not `$$formula$$`)
- [ ] Blank lines before/after every `$$` block
- [ ] No `\begin{align}` (use `\begin{aligned}`)
- [ ] Validator wired into CI or pre-push hook
````
