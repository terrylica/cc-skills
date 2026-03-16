# Why Your Matrix Equation Shows Raw LaTeX on GitHub

## Root Cause

GitHub's Markdown pre-processor runs **before** the math renderer. When it encounters `$$` blocks, it processes the content as Markdown text first — and `\\` (the LaTeX line-break command used inside `\begin{pmatrix}`) gets treated as an escaped backslash and collapsed to a single `\`.

Your equation uses `\begin{pmatrix}` which requires `\\` to separate matrix rows. Inside a `$$` block, GitHub strips those `\\` sequences before the math renderer ever sees the equation, leaving malformed LaTeX that cannot be rendered.

## The Fix: Use a `\`\`\`math\`\`\``Fence Instead of`$$`

GitHub does **not** pre-process the content inside code fences. The math renderer receives the raw LaTeX intact, including `\\`.

**Broken (what you wrote):**

```markdown
$$
\begin{pmatrix}
a & b \\
c & d
\end{pmatrix}
$$
```

**Fixed:**

````markdown
```math
\begin{pmatrix}
a & b \\
c & d
\end{pmatrix}
```
````

## The Rule to Memorize

| Equation type                                                              | Use             | Reason                           |
| -------------------------------------------------------------------------- | --------------- | -------------------------------- |
| Single-line display (no `\\`)                                              | `$$...$$`       | No `\\` → pre-processor safe     |
| Multi-line (contains `\\`, `\begin{pmatrix}`, `\begin{aligned}`, matrices) | ` ```math ``` ` | Code fences bypass pre-processor |
| Inline                                                                     | `$...$`         | Standard                         |

## Other Cases That Require `\`\`\`math\`\`\``

Any equation containing `\\` must use the code-fence form. This includes:

- `\begin{pmatrix}`, `\begin{bmatrix}`, `\begin{vmatrix}` — all matrix environments
- `\begin{aligned}` with multiple rows
- `\begin{cases}` with multiple cases
- Any `\\[8pt]` vertical spacing tricks

## Validate Before You Push Next Time

Install the KaTeX validator:

```bash
bun add -g katex
```

Then run it against your file before committing:

```bash
node references/validate-math.mjs your-file.md
```

**Important caveat**: KaTeX validates parse correctness but does **not** simulate GitHub's pre-processor. An equation can pass KaTeX and still break on GitHub if it contains `\\` inside a `$$` block. The `\`\`\`math\`\`\`` conversion is required regardless of KaTeX results for all multi-line blocks.

## Local Preview

To see exactly how GitHub will render your markdown before pushing:

```bash
bun add -g @hyrious/gfm
gfm your-file.md --serve
```

This gives a GitHub-accurate hot-reload preview at `localhost`.
