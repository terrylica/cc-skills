# Stage 09: can Unlimited-OCR transcribe math regions from academic PDFs?

**Run 2026-07-31. All 198 math regions in quantml's stage 09 report that carry both existing
transcriptions, rendered from their stored bounding boxes at 300 DPI and put through the model one
region per process. 13 minutes of local compute, no API calls.**

quantml stage 09 sends each math region to two paid vision models and promotes a formula only when
they agree. The question: can a free local reader take one of those slots, or add a third opinion?

## Verdict: NO as a voter — and the reason is new

|                                             | Value         |
| ------------------------------------------- | ------------- |
| Regions measured                            | 198           |
| **Unlimited-OCR returned NOTHING**          | **92 (46 %)** |
| Regions it answered                         | 106           |
| Agreement with M3 under stage 09's own gate | **0**         |
| Agreement with GLM-4.6v under that gate     | **0**         |
| Deadlocks it would break (of 147)           | **0**         |

The gate is `normalizeLatexForSemanticComparison(a, b).normalized_agreement` from
`pipeline/shared/latex_semantic_normalizer.ts` — stage 09's own test, not a similarity score chosen
for this document. On the same 106 regions the existing pair agrees 20 times, so the gate is not
simply impossible to pass.

---

## Why: it needs a page, not a fragment

This is the finding worth carrying elsewhere, and it was not visible in any earlier measurement.

**Crop WIDTH predicts whether the model answers at all. Height barely moves.**

| Outcome          |   n | Median crop width | Median crop height |
| ---------------- | --: | ----------------: | -----------------: |
| Returned text    | 106 |        **772 px** |              98 px |
| Returned NOTHING |  92 |        **181 px** |              78 px |

A 181-pixel-wide crop at 300 DPI is about 0.6 inches — an inline math fragment lifted out of a
paragraph. Unlimited-OCR is a document layout parser: it locates regions and transcribes what it
finds inside them. Handed something that is already a single region with no surrounding document, it
frequently finds no document structure and returns nothing at all. It is not failing to read the
formula; it is declining to treat the input as a page.

**Consequence for anything built on this model: feed it the page and let it do the localisation.**
Pre-cropping to the region of interest — the obvious thing to do, and what this measurement did —
is actively counterproductive. That is the opposite of the usual advice for vision models and is
why it is recorded here.

---

## The 0 is real, and bridges do not move it

Because the earlier stage 05 TABLE measurement turned out to be measuring a serialization mismatch
rather than a reading difference, the same check was run here before concluding. Scored on the 106
answered regions:

| Applied to Unlimited-OCR's output   | Gate: M3 | Gate: GLM | + no whitespace | + unwrap single-token braces |
| ----------------------------------- | -------: | --------: | --------------: | ---------------------------: |
| raw                                 |        0 |         0 |               2 |                  M3 2, GLM 2 |
| strip `<\|det\|>` layout markers    |        0 |         0 |               4 |                  M3 4, GLM 5 |
| + unwrap `\[ \]` and `$` delimiters |        0 |         0 |               4 |                  M3 4, GLM 5 |
| **control — M3 vs GLM, same 106**   |   **20** |         — |               — |                       **24** |

Under the real gate the answer is 0 at every level of bridging. Even at the most permissive ceiling
— strip markers, delete all whitespace, unwrap braces, none of which stage 09 does — it reaches 4 or
5 of 106 where the incumbent pair reaches 24.

The first pass of this measurement scored 0 of 198 while leaving `<|det|>` markers in the output,
which guarantees zero string agreement on its own. That was a methodology error in this document,
caught by inspecting samples rather than by trusting the number. Stripping them changes the bridged
figures and changes the gate figure not at all.

---

## What it costs and what else it did

| Measure                         | Value                         |
| ------------------------------- | ----------------------------- |
| Median runtime per region       | 1.6 s                         |
| Range                           | 1.3 s – 40.7 s                |
| Total for 198 regions           | 13 minutes, local, zero quota |
| Degenerate repetition suspected | 11 of 198 (5.6 %)             |
| Outright failures               | 0                             |

The 11 repetition cases matter here more than the rate suggests. One region returned prose that had
nothing to do with the image at all — _"In this case, we have a specific number of elements in the
list, which is not possible to be empty. The elements are not possible to be empty, but they can be
empty or empty"_ — against an image containing a policy-gradient expression. On a narrow crop the
model does not only return nothing; it sometimes returns fluent, confident, unrelated text. Any
pipeline consuming this output needs the repetition guard wired in, and the guard is what caught it.

---

## Two defects in quantml's stage 09 report, found while measuring

Neither is caused by Unlimited-OCR.

1. **The stored report does not match its own code.** `math_region_vision_transcriptions_cross_model.json`
   records `raw_string_agreement_count: 37` and `normalized_semantic_agreement_count: 43`. Re-running
   the current normalizer over the same 198 pairs gives **43 and 51**. The report is not reproducible
   from the code that produced it — the same family of defect as trap 20, in a different stage.
2. **One paper is listed twice**, contributing 49 regions on each entry. 98 of the 231 "math regions
   located" are one paper counted double.

A third, smaller: the normalizer preserves whitespace inside commands, so `\arg\max` and `\arg \max`
score as disagreement. Ignoring whitespace entirely lifts the existing pair from 51 to 57 of 198 —
six regions, free, and it moves nothing else.

---

## What this does not rule out

- **Stage 08 whole-page parsing.** Everything above argues the model wants a page. Stage 08 has 7
  acquired PDFs whose formulas the PyMuPDF text layer cannot express, and parsing involves no
  agreement gate at all.
- **A no-gate audit reader**, for the same reason: disagreement reported to a human needs no vote.
