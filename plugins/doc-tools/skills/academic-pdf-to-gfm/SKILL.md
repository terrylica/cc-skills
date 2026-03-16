---
name: academic-pdf-to-gfm
description: Convert academic PDF papers to GitHub-renderable GFM markdown with inline figures and correctly formatted math equations. Use this skill when converting research papers, technical reports, or math-heavy PDFs for display on GitHub. Also use it when GFM math equations are broken or not rendering on GitHub, when someone asks about the $$-vs-```math decision, when equations look garbled on GitHub, when KaTeX validation is needed, or when investigating why LaTeX renders locally but not on GitHub. Covers PDF type detection (Word vs LaTeX vs scanned), tool selection (pymupdf4llm/pdftotext/marker-pdf), image extraction, GitHub math rendering rules ($$-vs-```math decision), KaTeX validation, and multi-agent adversarial equation verification.
allowed-tools: Read, Grep, Glob, Bash, Write, Edit
---

# Academic PDF → GitHub GFM Conversion

A battle-tested workflow for converting academic/research PDF papers into GitHub-renderable GFM markdown with inline figures, mathematically correct LaTeX, and validated output.

**Battle-tested on**: López de Prado (2026) "How to Use the Sharpe Ratio" — 51 pages, 82 equations, 8 figures.

## Quick Start (3 Steps)

```bash
# Step 1: Extract prose (best structure preservation)
uv run --python 3.13 --with pymupdf4llm python3 -c "
import pymupdf4llm
md = pymupdf4llm.to_markdown('paper.pdf')
open('paper-raw.md', 'w').write(md)
"

# Step 2: Extract images
uv run --python 3.13 --with pymupdf python3 references/extract-images.py paper.pdf

# Step 3: Validate math before pushing
node references/validate-math.mjs paper.md
```

---

## CRITICAL: Detect PDF Type First

**This determines the entire workflow.** Getting it wrong wastes hours.

### Type A — Word-Generated PDF (Most Modern Academic Papers)

**Signs**: Embedded fonts, copyable text, Unicode math chars when you copy-paste (∑, π, α, β, γ, →)

**Math encoding**: Math is Unicode text in PDF stream — NOT images, NOT glyph maps

**Consequence**: OCR tools like `marker-pdf` **cannot extract LaTeX** — they see text like "γ₄" not `\gamma_4`. They may return empty output or crash silently.

**Required approach**:

1. Use `pymupdf4llm` for prose extraction
2. **Manually transcribe all equations** from PDF screenshots — there is no shortcut
3. Read each formula visually, write LaTeX by hand

**How to confirm**: Run `marker-pdf` — if output is empty or has zero math content, it's Type A.

### Type B — LaTeX-Generated PDF

**Signs**: Computer Modern fonts, precise mathematical spacing, arxiv.org source available

**Math encoding**: Glyph-mapped — structure is partially extractable

**Approach**: `pymupdf4llm` or `pdftotext` for text. If arxiv source exists, extract directly from `.tex` (vastly preferred over PDF conversion).

### Type C — Scanned/Image PDF

**Signs**: All pages are raster images, zero copyable text

**Approach**: OCR pipeline — `marker-pdf` is best option, or `tesseract`

---

## Tool Comparison

| Tool          | Best For                        | Install                           | Key Limitation                                  |
| ------------- | ------------------------------- | --------------------------------- | ----------------------------------------------- |
| `pymupdf4llm` | Type A/B prose (best structure) | `uv run --with pymupdf4llm`       | Math as Unicode, not LaTeX                      |
| `pdftotext`   | Quick plain text                | `brew install poppler`            | Loses table structure                           |
| `markitdown`  | Alternative prose               | `uv run --with 'markitdown[pdf]'` | Slight over-spacing; same math limit            |
| `marker-pdf`  | Type C scanned only             | `pip install marker-pdf`          | **Fails silently on Type A** (Unicode text bug) |

**Never trust `marker-pdf` output on Type A/B PDFs** — the apparent "success" with empty math sections is the failure mode.

---

## Image Extraction

Save `references/extract-images.py`:

```python
import fitz, os, sys

doc = fitz.open(sys.argv[1])
os.makedirs("references/media", exist_ok=True)
saved = []
for page_num in range(len(doc)):
    for img_idx, img in enumerate(doc[page_num].get_images(full=True)):
        xref = img[0]
        base_image = doc.extract_image(xref)
        img_bytes = base_image["image"]
        if len(img_bytes) < 2048:   # skip icons/logos/watermarks/rules
            continue
        ext = base_image["ext"]
        fname = f"fig-p{page_num+1:02d}-{img_idx+1:02d}.{ext}"
        with open(f"references/media/{fname}", "wb") as f:
            f.write(img_bytes)
        saved.append((page_num+1, fname, base_image.get("width"), base_image.get("height")))
        print(f"Saved: {fname} ({len(img_bytes)//1024}KB, {base_image.get('width')}×{base_image.get('height')})")
doc.close()
print(f"\n{len(saved)} images saved to references/media/")
```

**Naming**: `fig-p{page:02d}-{idx:02d}.{ext}` — page number in name for easy location matching.

**Size filter**: Skip `< 2 KB` (captures icons, watermarks, horizontal rules). Review everything ≥ 2 KB — some are decorative but most are figures.

**Insert in markdown**:

```markdown
![Figure 1: Variance of Sharpe ratio estimates](./media/fig-p12-01.png)
```

Place immediately after the nearest section heading or the paragraph that references the figure.

---

## GitHub GFM Math Rendering Rules

### The `$$` vs ` ```math ``` ` Decision — Root Cause

**GitHub's Markdown pre-processor runs BEFORE the math renderer.** It treats `\\` as an escaped backslash and collapses it to `\`. This breaks LaTeX line breaks in display math.

**The rule is simple**:

| Equation type                                           | Use             | Reason                                     |
| ------------------------------------------------------- | --------------- | ------------------------------------------ |
| Single-line display                                     | `$$...$$`       | No `\\` → pre-processor safe               |
| Multi-line (contains `\\`, `\begin{aligned}`, matrices) | ` ```math ``` ` | Pre-processor does NOT process code fences |
| Inline                                                  | `$...$`         | Standard                                   |

````markdown
# BROKEN on GitHub — \\ stripped by pre-processor:

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

### Display Block Formatting Rules

- `$$` must be on its **own line** — not `$$formula$$` on one line
- **Blank line required** before AND after every `$$` block
- **Blank line required between consecutive** `$$` blocks
- These rules do NOT apply to `` ```math ``` `` blocks

### Supported/Unsupported LaTeX

See [references/github-math-support-table.md](./references/github-math-support-table.md) for the full table.

**Key things to avoid**:

| Command | Problem | Fix |
|---------|---------|-----|
| `\begin{align}` | ❌ Not supported by GitHub | Use `\begin{aligned}` |
| `\boxed{}` | ⚠️ Can cause raw LaTeX passthrough | Remove or use bold text |
| `\operatorname{}` | ⚠️ Active GitHub bug, inconsistent | Use `\text{}` or `\mathrm{}` |
| `\newcommand` | ❌ Was briefly available, then pulled | Expand all macros inline |
| `x^_y` | Superscript immediately before subscript | Write `x^{*}_{i}` with braces |

### Common Gotchas

- `\\[8pt]` vertical spacing inside `$$` → eaten by pre-processor → move to `` ```math ``` ``
- `\frac{1}{T}:\left(` → spurious colon after fraction → remove colon
- Pearson vs excess kurtosis: most finance formulas need Pearson (γ₄ = 3 for Gaussian), not excess. **Always document the kurtosis convention in the formula comment.**
- `\begin{pmatrix}` with `\\` → must use `` ```math ``` ``
- `\begin{cases}` with multiple rows → must use `` ```math ``` ``

---

## Validation Pipeline

### Step 1: Install KaTeX Validator

```bash
bun add -g katex   # Bun-first per project policy
# or: npm install -g katex
````

### Step 2: Run Before Every Push

```bash
# Validate only (exit 1 on errors)
node references/validate-math.mjs your-file.md

# Validate + auto-fix correctable issues
node references/validate-math.mjs your-file.md --fix
```

The script is at [references/validate-math.mjs](./references/validate-math.mjs). It runs two layers:

**Layer 1 — KaTeX syntax**: parse errors in `$`, `$$`, ` ```math ``` ` blocks
**Layer 2 — GFM structural** (issues KaTeX passes but GitHub breaks):

| Code | Severity | Issue                                                                   | Auto-fix             |
| ---- | -------- | ----------------------------------------------------------------------- | -------------------- |
| E1   | Error    | `$$` block with `\\` — GitHub pre-processor strips backslashes          | ✅ → ` ```math ``` ` |
| E2   | Error    | Consecutive `$$` blocks without blank line — orphaned delimiter cascade | ✅ add blank line    |
| W1   | Warning  | Bare `^*` in `$$` block — markdown italic pairing eats the `*`          | ✅ → `^{\ast}`       |
| W2   | Warning  | `\begin{align}` — not supported on GitHub                               | ✗ manual             |
| W3   | Warning  | `\boxed{}` — can cause raw LaTeX passthrough                            | ✗ manual             |
| W4   | Warning  | `\operatorname{}` — inconsistent GitHub support                         | ✗ manual             |

Exits code 1 on errors (CI-friendly). Warnings do not block CI but should be reviewed.

### Local Preview Tools

```bash
# GitHub-accurate hot-reload preview
bun add -g @hyrious/gfm
gfm your-file.md --serve

# Offline binary (gh extension)
gh extension install thiagokokada/gh-gfm-preview
gh gfm-preview your-file.md
```

VS Code extensions:

- `shd101wyy.markdown-preview-enhanced` — closest to GitHub rendering
- `bierner.markdown-preview-github-styles` — GitHub CSS styling

---

## Multi-Agent Adversarial Equation Validation

For papers with 10+ equations, use this multi-agent pattern:

### Phase 1 — Parallel Extraction

- **Agent A**: Extract prose with pymupdf4llm, transcribe math from PDF screenshots
- **Agent B**: Extract and categorize all images

### Phase 2 — Parallel Validation

- **Agent C**: Validate equations against reference implementation (if code/repo exists)
- **Agent D**: Numerical spot-checks — compute paper's exhibit values, compare

### Phase 3 — Discrepancy Handling

- For each discrepancy: write `/tmp/paper-discrepancy/eq-{N}.md`
- Spawn resolver agents to search online for authoritative third-party sources
- **Authority rule**: Paper is tentatively more authoritative than code implementation; a third independent source breaks ties

### Phase 4 — Guarded Application

- Apply **only HIGH-confidence fixes** to the markdown
- For MEDIUM-confidence: spawn an independent audit agent before touching the file
- Document all discrepancies even if not fixed — future readers need to know

---

## Anti-Patterns

| Anti-pattern                                         | Why it fails                                        | Fix                                                                  |
| ---------------------------------------------------- | --------------------------------------------------- | -------------------------------------------------------------------- |
| `$$\begin{aligned}...\\...\end{aligned}$$`           | `\\` stripped by GH pre-processor                   | Use ` ```math ``` `                                                  |
| Trusting `marker-pdf` on Word PDFs                   | Returns no output or zero math (Unicode bug)        | Read as screenshots, transcribe manually                             |
| `\begin{align}` in display math                      | Not supported by GitHub                             | Replace with `\begin{aligned}`                                       |
| `\operatorname{Cov}`                                 | Active GH bug — sometimes renders raw               | Use `\text{Cov}` or `\mathrm{Cov}`                                   |
| KaTeX validation only, no ` ```math ``` ` conversion | KaTeX passes but GH pre-processor still breaks `\\` | Also convert ALL multi-line blocks                                   |
| `\boxed{}` for highlighting                          | Can cause raw LaTeX passthrough on GitHub           | Use bold text or a blockquote callout                                |
| Excess kurtosis in formulas expecting Pearson        | Silent ~50% underestimate in variance formulas      | Always document convention; use `scipy.stats.kurtosis(fisher=False)` |
| Consecutive `$$` blocks without blank lines          | GitHub collapses them into one broken block         | Add blank line between each block                                    |
| `$$formula$$` on one line (not own line)             | Treated as text, not display math                   | Put `$$` on its own line                                             |
| Running validation AFTER pushing                     | Bugs visible in public PR                           | Validate locally before every push                                   |

---

## References

| File                                                                      | Purpose                                |
| ------------------------------------------------------------------------- | -------------------------------------- |
| [validate-math.mjs](./references/validate-math.mjs)                       | KaTeX batch validator for GFM files    |
| [pdf-type-detection.md](./references/pdf-type-detection.md)               | Detailed guide to detecting PDF type   |
| [github-math-support-table.md](./references/github-math-support-table.md) | Full supported/unsupported LaTeX table |

---

## Related Skills

| Skill                                                                                                           | Relationship                                                     |
| --------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------- |
| [pandoc-pdf-generation](../pandoc-pdf-generation/SKILL.md)                                                      | Opposite direction: markdown → PDF                               |
| [documentation-standards](../documentation-standards/SKILL.md)                                                  | GFM formatting standards                                         |
| [quant-research:opendeviation-eval-metrics](../../../quant-research/skills/opendeviation-eval-metrics/SKILL.md) | Worked example: `references/how-to-use-the-sharpe-ratio-2026.md` |
