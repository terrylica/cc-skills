# PDF to GitHub Markdown: Tool Selection and Math Handling

## Recommended Extraction Tool: `marker`

For a 40-page finance paper with ~25 equations, **`marker`** (by VikParuchuri) is the best extraction tool for your use case.

Install it with:

```bash
pip install marker-pdf
marker_single your-paper.pdf output/ --output_format markdown
```

### Why `marker` over the alternatives

| Tool                 | Math handling               | Layout    | Speed      | Notes                          |
| -------------------- | --------------------------- | --------- | ---------- | ------------------------------ |
| **marker**           | Converts to LaTeX (`$...$`) | Good      | Moderate   | Best overall for academic PDFs |
| `pdfplumber`         | Raw text / Unicode symbols  | Poor      | Fast       | Tables OK, math terrible       |
| `pymupdf` (fitz)     | Raw text / Unicode symbols  | OK        | Fast       | No math conversion             |
| `pdfminer.six`       | Raw text / Unicode symbols  | Poor      | Slow       | Legacy, avoid                  |
| Adobe Acrobat export | Unicode passthrough         | Good      | N/A        | Same problem as copy-paste     |
| Mathpix              | LaTeX output                | Excellent | Slow/API   | Best math, costs money         |
| `nougat` (Meta)      | LaTeX output                | Excellent | Slow (GPU) | Best quality, heavy dependency |

`marker` uses a vision-based pipeline under the hood that recognizes equation structure and outputs LaTeX math delimiters rather than raw Unicode. For a 40-page paper on a modern laptop it typically finishes in under 2 minutes without a GPU.

---

## Handling Math Formulas in GitHub Markdown

GitHub Flavored Markdown (GFM) has supported LaTeX math rendering since May 2022. Use standard delimiters:

- **Inline math**: `$\sigma$`, `$\pi$`, `$\sum_{i=1}^{n}$`
- **Display (block) math**: `$$` on its own line, equation, `$$` on its own line

Example for a portfolio optimization equation:

```markdown
The minimum variance portfolio solves:

$$
\min_{\mathbf{w}} \; \mathbf{w}^\top \Sigma \mathbf{w}
\quad \text{subject to} \quad \mathbf{w}^\top \mathbf{1} = 1
$$

where $\Sigma$ is the $n \times n$ covariance matrix and $\mathbf{w}$ is the weight vector.
```

This renders correctly on github.com, in GitHub wikis, and in VS Code preview.

---

## Practical Workflow

### Step 1: Extract with marker

```bash
pip install marker-pdf
marker_single paper.pdf output_dir/ --output_format markdown
```

This produces `output_dir/paper.md`. marker will convert most display equations to `$$...$$` blocks and inline math to `$...$`.

### Step 2: Audit the math

marker is not perfect. After extraction, scan for remaining Unicode math symbols that slipped through:

```bash
grep -n '[∑∏∫∂∇αβγδεζηθλμνξπρστφψω]' output_dir/paper.md
```

For each flagged line, manually replace with proper LaTeX. Common substitutions for finance papers:

| Unicode | LaTeX         |
| ------- | ------------- |
| `∑`     | `\sum`        |
| `∏`     | `\prod`       |
| `σ`     | `\sigma`      |
| `μ`     | `\mu`         |
| `π`     | `\pi`         |
| `α`     | `\alpha`      |
| `β`     | `\beta`       |
| `λ`     | `\lambda`     |
| `ε`     | `\varepsilon` |
| `∈`     | `\in`         |
| `≤`     | `\leq`        |
| `≥`     | `\geq`        |

### Step 3: Fix common marker artifacts

marker occasionally produces these issues in academic papers:

1. **Equation labels detached from equations** — check that `(1)`, `(2)` tags are on the same line or in an aligned block.
2. **Fractions rendered as stacked text** — look for patterns like `a` on one line, `---` on the next, `b` below; replace with `\frac{a}{b}`.
3. **Matrix/vector notation** — bold symbols from the PDF often lose their weight; restore `\mathbf{w}` or `\boldsymbol{\mu}` by hand.
4. **Subscripts/superscripts in running text** — `R_i`, `w_t^2` need to be wrapped in `$...$` if they landed in plain text.

### Step 4: Validate rendering locally before pushing

```bash
# Option A: VS Code — open the .md file, Ctrl+Shift+V
# Option B: grip (GitHub-accurate local preview)
pip install grip
grip paper.md
# Open http://localhost:6419 in browser
```

### Step 5: Commit and push

```bash
git add paper.md
git commit -m "Add extracted paper as markdown"
git push
```

---

## Alternative: Mathpix for High-Equation-Density Papers

If the paper has complex multi-line derivations, aligned equation systems, or matrix expressions that marker handles poorly, consider **Mathpix Snip** or the **Mathpix PDF API**. It is the gold standard for math extraction but requires an account (free tier: 50 pages/month).

```bash
pip install mathpix-markdown-it
# Or use the web app: snip.mathpix.com — drag-and-drop the PDF
```

Mathpix outputs `%% Mathpix` flavored markdown which uses the same `$`/`$$` delimiters and is directly compatible with GitHub rendering.

---

## Summary

For your specific case (40-page SSRN paper, ~25 equations, Unicode math already visible in copy-paste):

1. Use **`marker`** for extraction — it handles academic layout well and outputs LaTeX math.
2. Do a **grep pass** for stray Unicode math symbols and fix them manually.
3. Use **`$...$`** for inline and **`$$...$$`** for display equations — GitHub renders both natively.
4. Preview locally with `grip` before committing.

The whole process for a 40-page paper should take about 30–45 minutes including manual cleanup of the equations.
