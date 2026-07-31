# Unlimited-OCR adoption plan

**Status as of 2026-07-30.** The plugin exists and is committed (`feat(unlimited-ocr): local
document parsing on MLX and CUDA`). This file tracks what remains: proving the code, and deciding
where the model actually earns its place in the work already on this machine.

Facts are not restated here. Measurements live in
[`../references/EMPIRICAL.md`](../references/EMPIRICAL.md), traps in
[`../references/PITFALLS.md`](../references/PITFALLS.md), integration reasoning in
[`../CLAUDE.md`](../CLAUDE.md). This file holds only what is TEMPORAL: what is done, what is next,
and what would settle each open question.

---

## What is already settled

| Question                                | Answer                                                       | Evidence                              |
| --------------------------------------- | ------------------------------------------------------------ | ------------------------------------- |
| Does it run on the Mac?                 | Yes — MLX, 2.4 s/image, 5.17 GB peak                         | `references/EMPIRICAL.md` § Runtime A |
| Does it run on the 4090?                | Yes — transformers, not SGLang (Ada SM 8.9 cannot use `fa3`) | § Runtime B                           |
| Is the documented invocation correct?   | **No.** `document parsing.` loops forever on MLX             | `PITFALLS.md` § 1                     |
| Can it replace the quantml OCR readers? | **No.** It returns nothing for charts                        | `PITFALLS.md` § 2                     |
| Is the headline benchmark margin real?  | Only on OmniDocBench v1.5; v1.6 is a tie                     | `EMPIRICAL.md` § Benchmarks           |

---

## Phase 1 — prove the code (no model required) — DONE

The CLI's load-bearing logic is pure and deterministic: math-spacing repair, bounding-box
normalisation, detection-marker stripping, degenerate-repetition detection, page-range selection,
and the output-stem derivation that had a real collision bug. **None of it is under test.**

Every one of these encodes a finding that cost real measurement to obtain. A regression in
`collapse_math_character_spacing` would silently reintroduce the cross-model-agreement failure it
was written to prevent, and nothing would fail.

**Delivered: `tests/test_pure_functions.py`, 58 tests, 0.19 s, no GPU/network/weights.** Verified by
independent mutation testing rather than by inspection — six mutations applied to production, all
six caught. Two real defects were found in the process: the withheld-prompt gate could be disabled
without any test noticing, and `find_spec` raised instead of answering on a Mac without mlx, so
`doctor` crashed on the machine it exists to help. Both fixed and covered.

Run with: `cd plugins/unlimited-ocr && uv run --with pytest --with pymupdf --no-project -m pytest tests/ -q`

## Phase 2 — settle the largest unknown: is the TASC corpus even a candidate? — DONE, VERDICT: DROP

~7,200 articles is more volume than everything else combined, and the entire question is whether
those PDFs are **born-digital or scanned**. If they carry a real text layer, OCR adds nothing and
this line of work should be dropped rather than pursued.

**Answered: the corpus is 100 % born-digital and OCR would make it worse.** Fifty documents sampled
uniformly across all nine decades returned hundreds to thousands of characters per page from a plain
text-layer read. Existing extraction already measures 97.9 % word recall against an independent
vision benchmark. There is nothing to OCR. Recorded in the hub so the idea is not re-proposed.

## Phase 3 — wire it where it belongs

Only after phases 1 and 2, and only where the evidence supports it.

- **quantml stages 08/09** — academic PDFs. The strongest fit: quantml already renders pages and
  transcribes them with a vision model because a PDF text layer cannot yield formulas.
- **quantml stage 05** — a THIRD reader for `FORMULA` and `TABLE` images only. Never a replacement
  for either existing reader, never routed to `CHART`. Requires `--collapse-math-spacing` upstream
  of any agreement check, or every formula scores as a disagreement.
- **`doc-tools:academic-pdf-to-gfm`** — should point at this plugin as the local option.

## Phase 4 — release

`feat` bumps the whole repository (uniform versioning, currently 23.1.0 → 23.2.0, all 43 plugins).
That blast radius is why it is a separate, deliberate step rather than a side effect.

---

## Open questions, and the smallest experiment that settles each

| Question                                                      | Experiment                                                                                                                                    |
| ------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------- |
| Does multi-page single-pass really drop near-duplicate pages? | Parse N synthetic pages differing only in a marker, single-pass vs per-page, count surviving markers. Per-page already verified to keep all.  |
| Is it better than M3/GLM on Chinese formulas?                 | No head-to-head evidence exists. Run all three over the same `FORMULA` sample from the quantml corpus and compare against the images by hand. |
| Is the TASC corpus scanned?                                   | Phase 2.                                                                                                                                      |
| Does `--collapse-math-spacing` ever corrupt valid LaTeX?      | Phase 1 — property tests over `\left\{`, `\begin{array}`, multi-letter commands, and text mode.                                               |
