# Reading a paper's PDF versus reading its source: the first ground-truth measurement

**Run 2026-07-31 on arXiv:2605.00501, "LambdaRankIC: Directly Optimizing Rank IC for Financial
Prediction" (Lin, Su, Yang). 55 display equations in the authors' LaTeX, 55 formula candidates
recovered from the rendered PDF by Unlimited-OCR.**

Every previous accuracy claim about OCR on this machine compared one model's output against
**another model's** output. That measures agreement, not correctness, and it is why a third reader
that never agrees is indistinguishable from one that is always wrong.

An arXiv e-print removes the ambiguity. `arxiv.org/e-print/<id>` serves the authors' own LaTeX — the
source the PDF was rendered _from_. It is not a second opinion. It is the answer key.

---

## The headline: similarity says 0.96, the TeX engine says 49 %

| Measure                                   | Authors' LaTeX | Unlimited-OCR reading the PDF |
| ----------------------------------------- | -------------- | ----------------------------- |
| Display equations                         | **55**         | 55 candidates                 |
| Mean best-match token overlap vs source   | —              | **0.958**                     |
| Exact match after aggressive normalisation | —             | 13 of 55                      |
| **Compiles under pdfTeX (TeX Live 2026)** | **54/55 (98 %)** | **27/55 (49 %)**            |
| Unbalanced braces                         | 0 of 55        | **21 of 55**                  |

The single source failure is `\NDCG`, a macro the authors define in a preamble the test harness
deliberately does not load. It is a harness artifact, not a defect in the source.

**A mean similarity of 0.958 and a fifty-percent compile rate describe the same data.** Similarity
answers "does this look like the formula". It cannot answer "can I use this", and those come apart
precisely where it matters: a dropped brace costs two percent of similarity and one hundred percent
of usability. **Fewer than half the formulas read off the PDF would compile.**

> **This table was published wrong once and is corrected here.** The first version reported 28
> ground-truth equations and an 80 % OCR compile rate. Both were artifacts of this project's own
> tooling, and both were caught by disagreement rather than by inspection — see "Three harness bugs"
> at the end. The honest figures are above.

---

## The defect that similarity cannot see: command–identifier fusion

Unlimited-OCR fuses a LaTeX command with the identifier that follows it, producing an undefined
control sequence. Measured over the raw model output for this paper:

| Emitted by the model | Should be             | Occurrences | Correctly-spaced form appears |
| -------------------- | --------------------- | ----------: | ----------------------------: |
| `\neqi`              | `\neq i`              |           5 |                         **0** |
| `\DeltaRankIC`       | `\Delta\text{RankIC}` |           2 |                         **0** |
| `\equivP`            | `\equiv P`            |           1 |                         **0** |
| `\logP`              | `\log P`              |           1 |                         **0** |

The correct form appears **zero** times, so this is systematic rather than occasional.

**It is not caused by `--collapse-math-spacing`.** That was the obvious suspect and it was tested
directly: fed `\sum_ {j \neq i} x`, `\equiv P`, `\log P` and `\Delta \text{RankIC}`, the function
returns every one unchanged. The fusion is in the model's own output.

Why it matters more than its frequency suggests: the result is fluent, plausible, scores 0.97
against the true formula, and does not compile. It is exactly the failure mode a human skim-reading
a markdown file will not catch.

The flagship formula of the paper, side by side:

```latex
source: \boxed{ \Delta\text{RankIC} \;=\; \frac{12\,|\hat{r}_j-\hat{r}_i||\tilde{y}_i-\tilde{y}_j|}{n\,(n^2-1)}. }
ocr   : \boxed {\DeltaRankIC = \frac {1 2 | \hat {r} _ {j} - \hat {r} _ {i} | | \tilde {y} _ {i} - \tilde {y} _ {j} |}}{n (n ^ {2} - 1)}}.}
```

Two independent faults in the paper's central result: `\Delta\text{RankIC}` fused into
`\DeltaRankIC`, and two surplus closing braces. Token overlap: 0.969.

`1 2` for `12` is a third, milder issue: `--collapse-math-spacing` rejoins letter runs but
deliberately not digit runs, because `1 5` can legitimately be two terms. TeX renders `1 2` and `12`
identically so it is harmless to a reader, but it defeats any exact-match comparison.

---

## What this says about when to OCR at all

**If the paper is on arXiv, do not OCR it.** The source is free, exact, carries the authors' own
`\label`s, and states which formulas are propositions rather than intermediate steps — structure no
vision model can recover because it is not in the rendering. The whole comparison above exists to
quantify a gap that is avoidable by not creating it.

OCR earns its place where no source exists: scanned documents, publisher PDFs with no preprint, and
the 88-of-103 HTML-table case this stack already documents. On this paper fewer than half its formulas compiled,
which is the cost of reading pixels when the source was one HTTP request away.

**Corollary for quantml stage 08.** Of its acquired papers, those with an arXiv identifier should be
re-acquired as e-print source rather than parsed from PDF. The acquisition report already records
`arxiv_identifier`, so the routing information is present.

---

## Reproducing this

```bash
curl -sSL -A "you@example.com" https://arxiv.org/e-print/2605.00501 -o eprint.tar.gz
mkdir src && tar xzf eprint.tar.gz -C src

# Ground truth: every display equation, with structure, rendered to MathML
cargo run --release --manifest-path tools/arxiv-latex-display-math-extractor/Cargo.toml -- src > equations.json

# Usability, not similarity
bun run tools/compile_each_formula_with_real_tex_engine.ts
```

### Three harness bugs, all of which produced a plausible wrong number

Kept because every one of them was caught by a DISAGREEMENT, not by reading the code, and because
each would have shipped as a finding.

1. **Shared output directory.** Every compile job ran concurrently against one `-output-directory`,
   clobbering each other's `.aux` files, and the harness reported **0 of 28 for the authors' own
   published LaTeX**. A published paper failing to compile is not a finding, it is a broken
   instrument.
2. **A swallowed TypeError.** The Bun shell chain called `.timeout()`, which does not exist on Bun
   1.3. Every job threw, and a bare `catch {}` recorded the throw as a failed compile. A `catch` that
   cannot distinguish "TeX rejected this" from "the harness is broken" hands you the second as the
   first. Now `.nothrow()` plus an explicit throw when no log file appears at all.
3. **Reused job directories across batches.** With the two batches sharing directory names, the
   second batch found the first batch's leftover `formula.pdf` and scored a pass for it. This is what
   produced the retracted **80 %**: the OCR score silently converged toward the source score. Caught
   because the OCR number moved from 44/55 to 54/55 when only the SOURCE input had changed — an
   impossible result, which is the only reason it was questioned. Directories are now namespaced by
   batch.

And one bug in the extractor rather than the harness, caught the same way: it reported **5**
equations for arXiv:2402.02592 where OCR reported **14**. The OCR was right. That paper writes five
of its display blocks with raw `\[ … \]` delimiters and the extractor only scanned
`\begin{env} … \end{env}`. On the paper measured here that gap hid **27 of 55** equations. An
extractor that silently returns a subset is worse than one that fails, because the number it returns
looks like an answer.
