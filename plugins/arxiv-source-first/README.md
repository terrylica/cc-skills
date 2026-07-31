# arxiv-source-first

Read an arXiv paper from the authors' own LaTeX instead of OCR-ing its PDF.

`arxiv.org/e-print/<id>` serves the source the PDF was rendered *from*. It carries the exact
formulas, their `\label`s, and which of them are stated propositions rather than steps inside a
proof — structure that does not survive into a rendering, so no vision model can recover it.

## What is here

| Path | What it does |
| --- | --- |
| `skills/arxiv-source-first-paper-ingest/` | The workflow: fetch the e-print, extract, verify |
| `.../tools/arxiv-latex-display-math-extractor/` | Rust. Every display equation with its label, environment, enclosing proposition, and MathML |
| `.../tools/latex-math-validity-oracle/` | Rust. Does this string parse as mathematics, and are its braces balanced |
| `.../tools/compile_each_formula_with_real_tex_engine.ts` | Bun. The authoritative test: does it compile under pdfTeX |
| `references/OCR-VERSUS-AUTHOR-LATEX-GROUND-TRUTH.md` | The measurement that motivates all of it |

## The measurement, in one table

Same paper, same formulas, two routes — arXiv:2605.00501:

| | Authors' LaTeX | Unlimited-OCR on the PDF |
| --- | --- | --- |
| Mean token overlap vs source | — | 0.958 |
| Exact after normalisation | — | 13 of 55 |
| **Compiles under pdfTeX** | **54/55 — 98 %** | **27/55 — 49 %** |
| Unbalanced braces | 0 of 55 | 21 of 55 |

The lone source failure is an author-defined macro the minimal test preamble does not load.

A mean similarity of 0.958 and a fifty-percent compile rate describe the same data. Similarity
answers "does this look like the formula"; it cannot answer "can I use this".

## When to OCR instead

When there is no source: scanned documents, publisher PDFs with no preprint, withdrawn or
PDF-only arXiv submissions. Then use the `unlimited-ocr` plugin — and check the formulas with a TeX
engine, because that plugin's section 13 documents a silent fusion defect this comparison found.
