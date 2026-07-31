# Head-to-head: Unlimited-OCR as a third reader in quantml stage 05

**Run 2026-07-30/31. 24 FORMULA images and 103 TABLE images from the live quantml corpus. Every
Unlimited-OCR transcription below was produced by actually running the model — 127 images, no
sampling beyond "this type, and both existing transcriptions on record".**

quantml stage 05 runs two independent vision models (MiniMax-M3 and GLM-4.6v) and treats their
agreement as evidence. The question, never previously measured: would a third independent reader
resolve the cases where those two deadlock?

## Verdict: NO for both image types

|                                 | FORMULA (n=24) | TABLE (n=103) |
| ------------------------------- | -------------- | ------------- |
| M3 ↔ GLM-4.6v agree (existing)  | 5              | 30            |
| **M3 ↔ Unlimited-OCR agree**    | **0**          | **1**         |
| GLM-4.6v ↔ Unlimited-OCR agree  | **0**          | **0**         |
| deadlocks a third reader breaks | **0 of 19**    | **0 of 73**   |

Agreement here is not a similarity score of my choosing. It is
`findDiscrepancy(a, b, type) === null` — quantml stage 05's own gate, extracted **verbatim by
script** from `pipeline/05-ocr/cross_reference.ts`, with the only edits being `export` and widening
one parameter's type. (quantml has since moved it to `pipeline/shared/transcription_agreement_gate.ts`
and put it under test, as a direct result of this audit.) Measuring against anything else is measuring the wrong thing, which is a
mistake this document made twice before getting it right (see "Three wrong measurements", below).

---

## FORMULA — the ceiling is also zero

Unlimited-OCR's LaTeX is cosmetically different from both incumbents in ways the gate does not
absorb:

```
M3 : QLIKE_i     = \frac{1}{T}  \sum_{t=1}^T   (\frac{\exp(RV_{i,t}^{(d)})}{...
UO : QLIKE _ {i} = \frac {1}{T} \sum_ {t = 1} ^ {T} (\frac {\exp (RV _ {i , t} ^ {(d)})}{...
```

The FORMULA branch of the gate already strips **all** whitespace and `\left`/`\right` before
comparing, so spacing is not the obstacle. Three progressively more aggressive bridges were built
and measured, to establish the ceiling rather than assert one:

| Bridge applied to Unlimited-OCR output                  | M3 ↔ UO | GLM ↔ UO |
| ------------------------------------------------------- | ------- | -------- |
| none                                                    | 0 / 24  | 0 / 24   |
| strip `<\|det\|>` layout markers                        | 0 / 24  | 0 / 24   |
| + unwrap single-token braces (`{i}` → `i`) on all three | 0 / 24  | 0 / 24   |

**Zero at every level.** The differences are not a serialization skin over identical content; they
run into the LaTeX itself. There is no bridge to build here.

### It still reads well — which is the point worth keeping

On a pairwise _similarity ratio_ over canonicalised LaTeX, Unlimited-OCR tracks M3 better than
GLM-4.6v does:

| Pair                              | Mean similarity |
| --------------------------------- | --------------- |
| M3 ↔ GLM-4.6v (the existing pair) | 0.811           |
| **M3 ↔ Unlimited-OCR**            | **0.838**       |
| GLM-4.6v ↔ Unlimited-OCR          | 0.755           |

And on `68b99c3f4017.jpg`, verified by eye against the source image: GLM emitted visibly corrupted
LaTeX (`==================` where `=` belongs, `RV*{i,t}` for `RV_{i,t}`), M3 was exactly right, and
Unlimited-OCR independently matched M3. A human looking at three outputs would resolve that image
instantly. **The gate would not** — it sees three mutually disagreeing strings. That gap between
"a reader a person could use" and "a reader this mechanism can use" is the entire finding.

It must also never be promoted to arbiter. On `17e7c844edb2.jpg` the image reads
`I{RET_CO_{i,d}>0} * I{RET_OC_{i,d}<0}`; Unlimited-OCR wrote **`RET.OC` twice** — a semantic error,
not a formatting one — while getting the same symbols right in the surrounding Chinese prose on the
same image.

---

## TABLE — a bridge exists, and what it reveals kills the idea anyway

The raw numbers look like FORMULA (1 of 103), but for a completely different and shallower reason:

| Reader        | Serialization emitted           |
| ------------- | ------------------------------- |
| MiniMax-M3    | pipe-markdown 102, prose 1      |
| GLM-4.6v      | pipe-markdown 103               |
| Unlimited-OCR | **HTML `<table>` 88**, prose 15 |

Two readers speak pipe-markdown and the third speaks HTML. Nothing about the reading is being
compared. So the bridge was built — an HTML-table-to-pipe-markdown renderer — and measured:

| Unlimited-OCR output                  | M3 ↔ UO  | GLM ↔ UO | Deadlocks broken |
| ------------------------------------- | -------- | -------- | ---------------- |
| raw HTML from the model               | 1 / 103  | 0 / 103  | 0 of 73          |
| **after HTML → pipe-markdown bridge** | 25 / 103 | 62 / 103 | **42 of 73**     |

42 of 73 deadlocks broken looks like a working third reader. It is not, and the reason is in the
split:

**Of the 42 deadlocks it breaks, 40 side with GLM-4.6v and 2 with M3.**

A third reader that picks the same incumbent 95 % of the time is measuring that incumbent, not the
image. To find out which, row counts were compared directly — an image-level property the gate never
sees:

| Structural comparison (90 images where all three parse)  | Result                      |
| -------------------------------------------------------- | --------------------------- |
| Unlimited-OCR row count closer to GLM's / to M3's / tied | 26 / 21 / 43 — **balanced** |
| Median rows: M3 / GLM / Unlimited-OCR                    | 9 / 13 / 12                 |
| Mean output length: M3 / GLM / Unlimited-OCR             | 858 / 1374 / 2913 chars     |

The transcriptions are balanced; the votes are 40-to-2. So the skew is not the model preferring
GLM's reading — it is the **gate**. `computeSimilarity` is Jaccard over the union of both word sets,
which is inherently size-sensitive: a 2913-character output intersected with an 858-character one
cannot exceed a Jaccard of roughly `858/2913` no matter how correct both are, while the same output
against a 1374-character one clears the 0.75 TABLE threshold easily.

**Unlimited-OCR's vote is decided by how verbose the other reader was.** That is not a third
opinion, and shipping it would have injected a systematic bias in favour of the more verbose
incumbent into a corpus whose whole premise is that agreement between independent readers is
evidence.

---

## Three defects this measurement found in quantml

None is caused by Unlimited-OCR; all three were surfaced by pointing a third reader at the gate.

1. **`findDiscrepancy` had no tests and was not exported.** It is the single most
   correctness-critical decision in stage 05 — it decides what enters the corpus as corroborated —
   and it lived as a private function inside a ~700-line stage script with zero direct coverage.
   Every measurement in this document had to extract it by script to exercise it at all.
   **Fixed in quantml `57cdcf6`/`a3c57c6`**: moved to `pipeline/shared/transcription_agreement_gate.ts`,
   exported, and covered by 26 characterization tests that pin these numbers.
2. **Jaccard word-overlap is size-sensitive, and the thresholds do not account for it.** Two
   correct transcriptions of the same table can fail the 0.75 gate purely because one is three
   times longer. The existing M3/GLM pair agrees on only 30 of 103 tables, and this is part of why.
   Recorded in quantml as trap 18, deliberately not fixed — the thresholds were chosen empirically
   and loosening them to admit a new reader is the mistake this whole document argues against.

A third defect turned up only because the gate was being replayed over quantml's own report:
`status: "aligned"` is written both for genuine first-try independent agreement and for agreement
reached **inside** the convergence loop, after each model has been shown what the other said. Of the
179 records quantml calls `aligned_first_try`, **99 are**; the other 80 came out of the loop. Corpus
content is unaffected — both statuses carry the same provenance tier — but that tier is documented
as "two _independent_ models produced text that agreed", which is not what happened for the 198
records that agreed inside the loop. quantml trap 20.

---

## Cost of the measurement

|                                | FORMULA (24)                   | TABLE (103)  |
| ------------------------------ | ------------------------------ | ------------ |
| Per image                      | 2.2 – 38.2 s                   | 1.5 – 39.4 s |
| Median                         | ≈ 7 s                          | 4.8 s        |
| Degenerate repetition detected | 0 of 24                        | 4 of 103     |
| Empty output                   | 0                              | 1            |
| Marginal cost                  | zero — local weights, no quota | zero         |

`--collapse-math-spacing` is mandatory for any of this: without it the model emits `c u r p d f`
where the others emit `curpdf`, and every formula scores as a disagreement for a purely cosmetic
reason.

The zero-quota property is real and remains attractive — quantml's cross-reference phase once died
against an upload quota after roughly 140 of 529 images, and a local reader cannot hit that wall.
It is simply not enough on its own.

---

## Three wrong measurements before the right one

Kept deliberately. Each was wrong in a different way, and the pattern is the lesson.

| Pass | What it measured                                            | Verdict | Why it was wrong                                                                                                                                                                                                                                                                                                         |
| ---- | ----------------------------------------------------------- | ------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| 1    | nothing — the model was never run                           | NO      | A dependency-solver timeout was read as the model failing; runtime was estimated, not measured; M3's own `verification.accurate` flag was cited as evidence of M3's accuracy, which is circular. A 473-line document titled "head-to-head" containing zero Unlimited-OCR transcriptions was deleted rather than patched. |
| 2    | a similarity ratio of my own choosing                       | YES     | The ratio is a fine description of the data and is **not** the test quantml applies. 0.838 mean similarity and 0 gate agreements are both true of the same 24 images.                                                                                                                                                    |
| 3    | `normalizeLatexForSemanticComparison` + exact match         | NO      | Right answer, still the wrong function: that normalizer belongs to **stage 09** formula promotion, not stage 05. Being right by accident is not being right.                                                                                                                                                             |
| 4    | `findDiscrepancy` — stage 05's own gate, extracted verbatim | **NO**  | —                                                                                                                                                                                                                                                                                                                        |

Pass 2 is the expensive one to learn from. It ran the model correctly on real data, produced numbers
that were accurate, and reached a conclusion that would have shipped a reader casting zero votes.
**The failure was choosing a metric instead of finding the one the target system already uses.**

---

## What this does not rule out

- **quantml stages 08/09 (academic PDFs)** — parsing, not voting. No agreement gate is involved, so
  none of the above applies. Still the strongest fit; see
  [`../docs/ADOPTION-PLAN.md`](../docs/ADOPTION-PLAN.md).
- **Figure segmentation** — a capability nothing else in this stack has.
- **A one-off audit reader.** Running it over the corpus and reporting where it disagrees with the
  settled text is useful _to a human_, and needs no gate at all. That is a different product from a
  voter, and the HTML-to-pipe bridge measured here would be reusable for it.
