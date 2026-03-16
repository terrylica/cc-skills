# Why Your Matrix Equation Shows Raw LaTeX on GitHub

## The Problem

GitHub's standard Markdown renderer (GitHub Flavored Markdown, GFM) **does not render LaTeX math by default**. When you push a `.md` file to GitHub and view it in a repository, the `$$...$$` delimiters and the `\begin{pmatrix}` environment are displayed as plain text — exactly as you typed them.

GitHub added native math rendering support in 2022, but it only works under specific conditions.

---

## Root Cause

GitHub renders math via MathJax, but only when the file uses the correct syntax **and** is viewed in a context where math rendering is enabled. The most common issues are:

### 1. The `\\` line separator is being interpreted incorrectly

In standard Markdown, a backslash at the end of a line can be treated as a line continuation or escape character. The double backslash `\\` used in LaTeX to separate matrix rows may be consumed or mangled by the Markdown parser before MathJax ever sees it.

### 2. GitHub math rendering requires explicit opt-in (for some file types)

GitHub supports math in:

- Issue comments, pull request descriptions, and wikis (enabled by default)
- `.md` files rendered in the repository view — **but only since May 2022**, and behavior can vary

### 3. The math block may not be recognized

For GitHub's math rendering to activate, the `$$` block must be on its own line with no surrounding content on the same line, and there must be no extra blank lines between `$$` and the math content in some contexts.

---

## Fixes

### Fix 1: Use a blank line before and after the `$$` block

Ensure there is a blank line before the opening `$$` and after the closing `$$`:

```
(blank line)
$$
\begin{pmatrix}
a & b \\
c & d
\end{pmatrix}
$$
(blank line)
```

This is already what you have, so if it still doesn't render, see Fix 2.

### Fix 2: Escape the backslashes in the row separator

GitHub's Markdown parser sometimes consumes one backslash, so `\\` becomes `\`. Use `\\\\` instead of `\\` to survive the Markdown parsing step:

```markdown
$$
\begin{pmatrix}
a & b \\\\
c & d
\end{pmatrix}
$$
```

This is the most common fix for matrix environments on GitHub.

### Fix 3: Use inline `$` math with explicit HTML (for simple cases)

For simple expressions, you can avoid block math entirely and use inline math:

```markdown
The matrix is $\begin{pmatrix} a & b \\\\ c & d \end{pmatrix}$
```

### Fix 4: Convert to an image (most reliable for complex math)

For guaranteed rendering across all viewers, render the LaTeX to a PNG and embed it as an image:

1. Use a service like [codecogs.com](https://latex.codecogs.com/) or [quicklatex.com](https://quicklatex.com/) to generate a PNG.
2. Embed it: `![matrix equation](URL_to_image)`

Or use a local tool like `pdflatex` + `convert` (ImageMagick) to generate and commit the image.

### Fix 5: Use a Jekyll/GitHub Pages site with MathJax explicitly loaded

If your Markdown is part of a GitHub Pages site, add MathJax to your layout:

```html
<script src="https://cdn.jsdelivr.net/npm/mathjax@3/es5/tex-mml-chtml.js"></script>
```

Then your `$$...$$` blocks will render correctly.

---

## Recommended Fix (Quick)

**Change `\\` to `\\\\`** in your matrix row separators:

```markdown
$$
\begin{pmatrix}
a & b \\\\
c & d
\end{pmatrix}
$$
```

This is the single most effective fix for matrix/array environments in GitHub Markdown files.

---

## Summary Table

| Approach                   | Reliability        | Complexity |
| -------------------------- | ------------------ | ---------- |
| Use `\\\\` instead of `\\` | High               | Low        |
| Render to PNG image        | Highest            | Medium     |
| GitHub Pages + MathJax     | High               | Medium     |
| Raw `$$` block             | Low (inconsistent) | Low        |
