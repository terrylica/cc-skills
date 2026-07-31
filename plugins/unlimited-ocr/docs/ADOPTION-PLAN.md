# Unlimited-OCR adoption plan

**Status as of 2026-07-31.** The plugin exists and is committed (`feat(unlimited-ocr): local
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

**Delivered: `tests/test_pure_functions.py`, 87 tests, ~0.2 s, no GPU/network/weights.** Verified by
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

**REOPENED 2026-07-31, on one narrow ground only.** The drop verdict answered "is there text to
recover?", and the answer is still no. It never asked whether TASC's FIGURES were segmented — they
were not, and figure segmentation is the one capability nothing else in this stack has. That is a
different question from OCR and is tracked as its own experiment below. The OCR verdict stands.

## Phase 3 — wire it where it belongs — MEASURED

- **`doc-tools:academic-pdf-to-gfm` — DONE.** That skill previously instructed users to
  "**Manually transcribe all equations** from PDF screenshots — there is no shortcut" for Type A
  PDFs, and recommended `marker-pdf`/`tesseract` for Type C. Both now lead with Unlimited-OCR, with
  the chart limitation stated at every mention so nobody swaps it in and silently loses chart
  content. The example was executed against a real ICLR 2024 paper before being written down.

- **quantml stage 05 — MEASURED, and the answer is NO.** 127 images, model actually run: 24 FORMULA
  and 103 TABLE. Scored against `findDiscrepancy()` — stage 05's own agreement gate, extracted
  verbatim by script rather than approximated. Unlimited-OCR agrees with M3 on **0 of 24** formulas
  and **1 of 103** tables, and breaks **none** of the 19 formula or 73 table deadlocks. FORMULA has
  no fix: three progressively aggressive bridges all land on zero. TABLE has one — the model emits
  HTML `<table>` where both incumbents emit pipe-markdown, and bridging that lifts it to 42 of 73
  deadlocks broken — but **40 of those 42 side with GLM and 2 with M3** while row counts are
  balanced, because the gate's Jaccard is size-sensitive and Unlimited-OCR is 3.4× more verbose than
  M3. Its vote would be decided by the other reader's verbosity. Two earlier verdicts in this plan
  were wrong: a YES from a similarity ratio, then a NO scored against stage **09**'s normalizer
  rather than stage 05's gate. Evidence, including both corrections:
  [`references/QUANTML-STAGE-05-THIRD-READER-HEAD-TO-HEAD.md`](../references/QUANTML-STAGE-05-THIRD-READER-HEAD-TO-HEAD.md).

- **`--table-format`, defaulting to pipe-markdown — DONE.** The model emits HTML `<table>` for 88 of
  103 real tables and never pipe-markdown, so any markdown assembled from its output embedded raw
  HTML and any comparison against another reader measured markup. Shipped with the converter that
  the stage 05 measurement needed, hardened against six reviewer-found defects.

- **quantml stages 08/09 and a no-gate audit reader — IN PROGRESS.** Stage 08 is parsing rather than
  voting, so no agreement gate applies and it remains the strongest fit. Stage 09 is being measured
  the same way stage 05 was, against its OWN gate, before anything is wired. The audit reader needs
  no gate at all and is the use the stage 05 verdict explicitly left open.

## Phase 4 — release

Uniform versioning: any `feat` bumps the whole repository and all 43 plugins together. That blast
radius is why releasing is a separate, deliberate step rather than a side effect.

- **23.2.0 — SHIPPED 2026-07-31.** Carried the plugin, the stage 05 verdict and its reversal.
  One lesson recorded there: semantic-release renders `feat` and `fix` bodies into the notes and
  DROPS `docs` bodies, so the retracted stage 05 verdict was published while its retraction was not.
  Both the GitHub release and the changelog were annotated by hand. A correction that must appear in
  generated notes has to ship as `fix`.
- **23.3.0 — PENDING.** `--table-format` is a `feat`, so the bump is already MINOR.

---

## Open questions, and the smallest experiment that settles each

| Question                                                      | Experiment                                                                                                                                    | Status                                                                                                               |
| ------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------- |
| ~~Does multi-page single-pass drop near-duplicate pages?~~ | **ANSWERED 2026-07-30.** It loses content regardless of similarity: single-pass recovered 1/3, 4/5, 0/10 (identical) and 1/3, 0/5, 0/10 (varied); per-page recovered 100 % in all six. See PITFALLS § 3. | DONE                                                                                                                 |
| Can it serve as a third reader in quantml stage 05?           | Run it over every `FORMULA` and `TABLE` image in the corpus that already carries both existing transcriptions, and score with stage 05's own `findDiscrepancy()` gate. | **ANSWERED: NO** — 0/24 formulas, 1/103 tables, 0 deadlocks broken (see [`references/QUANTML-STAGE-05-THIRD-READER-HEAD-TO-HEAD.md`](../references/QUANTML-STAGE-05-THIRD-READER-HEAD-TO-HEAD.md)) |
| Is the TASC corpus scanned?                                   | Phase 2.                                                                                                                                      | DONE                                                                                                                 |
| Does `--collapse-math-spacing` ever corrupt valid LaTeX?      | Phase 1 — property tests over `\left\{`, `\begin{array}`, multi-letter commands, and text mode.                                               | DONE                                                                                                                 |
| Can it serve as a third reader in quantml stage **09**?       | Render all 198 math regions at 300 DPI from their stored bounding boxes, run the model per region, and score with stage 09's OWN gate (`normalizeLatexForSemanticComparison` + exact match) — not a similarity ratio. | IN FLIGHT |
| Does segmenting TASC figures recover anything the text layer cannot? | Sample real TASC pages, segment, and compare against what the born-digital text layer already yields. If nothing, the drop verdict stands unchanged. | OPEN |
| Does it disagree usefully with the settled quantml corpus?    | Transcribe corpus images and report disagreements for a human. No gate, no writeback — so none of the stage 05 agreement problems apply. | OPEN |
