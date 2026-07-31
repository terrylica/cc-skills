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

## Phase 3 — wire it where it belongs — MEASURED

- **`doc-tools:academic-pdf-to-gfm` — DONE.** That skill previously instructed users to
  "**Manually transcribe all equations** from PDF screenshots — there is no shortcut" for Type A
  PDFs, and recommended `marker-pdf`/`tesseract` for Type C. Both now lead with Unlimited-OCR, with
  the chart limitation stated at every mention so nobody swaps it in and silently loses chart
  content. The example was executed against a real ICLR 2024 paper before being written down.

- **quantml stage 05 — MEASURED, and the answer is YES**, as a third reader for `FORMULA` images
  only. 24 FORMULA images from the live corpus, every Unlimited-OCR transcription produced by
  actually running the model. Mean similarity to M3 is **0.838**, higher than the existing
  M3↔GLM pair at 0.811. **8 of the 24 carry a material M3/GLM disagreement and the third reader
  takes a clear side in 7** — the case the design is for. It is a corroborator, not an arbiter: on
  one image it made a semantic error M3 avoided. Evidence:
  [`references/QUANTML-FORMULA-HEAD-TO-HEAD.md`](../references/QUANTML-FORMULA-HEAD-TO-HEAD.md).

  **A first attempt at this measurement had to be discarded.** It concluded "operationally
  infeasible — cannot execute reliably" and "M3 achieves 100 % correctness", having never run the
  model once (a dependency-solver timeout was mistaken for the model failing) and having taken M3's
  own `verification.accurate` flag as independent evidence of M3's accuracy. Both conclusions are
  false: all 24 images ran on the first attempt, and M3 is demonstrably not always right. The
  discarded document is deleted rather than corrected, because its verdict and its evidence were
  both fabricated.

- **quantml stages 08/09 — SPECIFIED, NOT BUILT.** Academic PDFs remain the strongest fit, but this
  work stops at the plugin boundary. Nothing under `~/eon/quantml` has been modified.

## Phase 4 — release

`feat` bumps the whole repository (uniform versioning, currently 23.1.0 → 23.2.0, all 43 plugins).
That blast radius is why it is a separate, deliberate step rather than a side effect.

---

## Open questions, and the smallest experiment that settles each

| Question                                                      | Experiment                                                                                                                                    | Status                                                                                                               |
| ------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------- |
| Does multi-page single-pass really drop near-duplicate pages? | Parse N synthetic pages differing only in a marker, single-pass vs per-page, count surviving markers. Per-page already verified to keep all.  | OPEN                                                                                                                 |
| Is it better than M3/GLM on Chinese formulas?                 | No head-to-head evidence exists. Run all three over the same `FORMULA` sample from the quantml corpus and compare against the images by hand. | **ANSWERED: NO** (see [`references/QUANTML-FORMULA-HEAD-TO-HEAD.md`](../references/QUANTML-FORMULA-HEAD-TO-HEAD.md)) |
| Is the TASC corpus scanned?                                   | Phase 2.                                                                                                                                      | DONE                                                                                                                 |
| Does `--collapse-math-spacing` ever corrupt valid LaTeX?      | Phase 1 — property tests over `\left\{`, `\begin{array}`, multi-letter commands, and text mode.                                               | DONE                                                                                                                 |
