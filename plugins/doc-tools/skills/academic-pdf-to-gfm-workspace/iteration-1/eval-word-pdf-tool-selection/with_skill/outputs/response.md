# Converting Your Finance PDF to GitHub Markdown

## Step 1: Identify Your PDF Type (Critical)

The symptom you described — "when I copy text from it, the math symbols come through as Unicode (∑, π, σ, etc.)" — is the definitive diagnostic signal. Your paper is a **Type A: Word-Generated PDF**.

This matters enormously because it determines the entire workflow. In Word-generated PDFs, math formulas are stored as Unicode text characters directly in the PDF stream. They are not images, and they are not glyph-mapped LaTeX structures. The characters you see when you copy-paste (∑, π, σ) are literally what the PDF contains — there is no underlying LaTeX to recover.

## Step 2: Which Extraction Tool to Use

**Use `pymupdf4llm`** for prose extraction. Run it like this:

```bash
uv run --python 3.13 --with pymupdf4llm python3 -c "
import pymupdf4llm
md = pymupdf4llm.to_markdown('your-paper.pdf')
open('paper-raw.md', 'w').write(md)
"
```

This will correctly extract all the prose, section headings, and table structure. It is the best tool for structure preservation on Word-generated PDFs.

**Do not use `marker-pdf`.** This is the most important warning for your situation. `marker-pdf` is designed for scanned/image PDFs (Type C). On a Word-generated PDF like yours, it will either produce empty output or silently return zero math content. It sees the Unicode text characters and cannot reconstruct LaTeX from them. The apparent "success" with missing math sections is the failure mode — you might not notice until you're looking at a markdown file with no equations.

Tool summary for your paper type:

| Tool          | Verdict                | Reason                                         |
| ------------- | ---------------------- | ---------------------------------------------- |
| `pymupdf4llm` | **Use this**           | Best structure preservation on Word PDFs       |
| `pdftotext`   | Acceptable fallback    | Quick but loses table structure                |
| `markitdown`  | Acceptable alternative | Slight over-spacing; same math limitation      |
| `marker-pdf`  | **Do not use**         | Fails silently on Word PDFs (Unicode text bug) |

## Step 3: How to Handle the 25 Math Formulas

There is no automated shortcut here. For a Word-generated PDF, **you must manually transcribe all equations**.

The workflow is:

1. Run `pymupdf4llm` to get the prose as markdown (this part is automated and works well).
2. For each of the 25 equations, take a screenshot of the formula from the PDF and write the LaTeX by hand, reading the formula visually.
3. Insert the LaTeX into the markdown at the correct location.

This is not a tooling limitation that can be worked around — the information simply does not exist in the PDF in a form any tool can extract. The Unicode characters (∑, π, σ) tell you what symbol to render, but not the full structure: subscripts, superscripts, fractions, limits, and groupings are either absent or ambiguous in the PDF stream.

## Step 4: Formatting Equations for GitHub

GitHub has specific rendering rules that trip up most people. The key decision is `$$` vs. the code fence ` ```math ` block.

**The root cause**: GitHub's Markdown pre-processor runs before the math renderer and treats `\\` as an escaped backslash, collapsing it to `\`. This breaks LaTeX line breaks.

**The rule**:

| Equation type                                           | Use             | Reason                              |
| ------------------------------------------------------- | --------------- | ----------------------------------- |
| Single-line display                                     | `$$...$$`       | No `\\` present, pre-processor safe |
| Multi-line (contains `\\`, `\begin{aligned}`, matrices) | ` ```math ``` ` | Pre-processor skips code fences     |
| Inline                                                  | `$...$`         | Standard                            |

For a portfolio optimization paper with ~25 equations, you will almost certainly have multi-line equations (portfolio variance, covariance matrices, optimization constraints). Those **must** use the code fence form, not `$$`.

Example of what breaks vs. what works:

````markdown
# BROKEN on GitHub — \\ stripped by pre-processor:

$$
\begin{aligned}
\sigma^2_p &= \mathbf{w}^\top \Sigma \mathbf{w} \\
\mu_p &= \mathbf{w}^\top \mu
\end{aligned}
$$

# CORRECT on GitHub:

```math
\begin{aligned}
\sigma^2_p &= \mathbf{w}^\top \Sigma \mathbf{w} \\
\mu_p &= \mathbf{w}^\top \mu
\end{aligned}
```
````

Additional formatting rules for `$$` blocks (not needed for ` ```math `):

- `$$` must be on its own line — not `$$formula$$` on a single line
- Blank line required before AND after every `$$` block
- Blank line required between consecutive `$$` blocks

## Step 5: Things to Avoid in Finance Equations

A few GitHub-specific pitfalls that are especially common in finance papers:

| Command                     | Problem                                   | Fix                                |
| --------------------------- | ----------------------------------------- | ---------------------------------- |
| `\begin{align}`             | Not supported by GitHub                   | Use `\begin{aligned}`              |
| `\operatorname{Cov}`        | Active GitHub bug, inconsistent rendering | Use `\text{Cov}` or `\mathrm{Cov}` |
| `\boxed{}`                  | Can cause raw LaTeX passthrough           | Remove or use bold text            |
| `\newcommand`               | Was briefly available, then pulled        | Expand all macros inline           |
| `\begin{pmatrix}` with `\\` | Needs code fence                          | Use ` ```math ` block              |

Also: if your paper has portfolio variance or moment formulas involving kurtosis, document which kurtosis convention is used (Pearson γ₄ = 3 for Gaussian, or excess κ = 0). This is a silent semantic error that won't cause rendering failures but will produce wrong numerical results if someone implements from your markdown.

## Step 6: Validate Before Pushing

Install KaTeX and run the validator before pushing to GitHub:

```bash
bun add -g katex
node references/validate-math.mjs paper.md
```

The validator extracts all `$...$`, `$$...$$`, and ` ```math ` blocks and validates each with KaTeX, reporting line numbers for any errors.

**Important caveat**: KaTeX validation catches parse errors, but GitHub may still break `\\` inside `$$` blocks even when KaTeX passes. Run the ` ```math ` conversion for ALL multi-line blocks regardless of KaTeX result. These are two separate checks — KaTeX correctness and GitHub pre-processor safety.

## Summary

Your paper is a Word-generated PDF. The correct approach is:

1. **Prose**: `pymupdf4llm` (automated, works well)
2. **Equations**: Manual transcription from PDF screenshots — all 25 of them (no shortcut exists)
3. **Single-line display math**: `$$...$$`
4. **Multi-line math** (very likely for portfolio optimization): ` ```math ` code fences
5. **Validate**: KaTeX before pushing, then verify rendering on GitHub

The manual equation transcription is the unavoidable cost of working with a Word-generated PDF. For 25 equations it is a reasonable afternoon's work, and the result will be a correctly rendered, permanent GitHub document.
