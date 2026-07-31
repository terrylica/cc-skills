# unlimited-ocr — plugin hub

Local document parsing with [`baidu/Unlimited-OCR`](https://github.com/baidu/Unlimited-OCR) (MIT):
markdown, LaTeX, and per-block layout bounding boxes, on hardware you already own. No API key, no
per-image cost, no upload quota, nothing leaves the machine.

This file is the hub. Facts live in exactly one place:

| Topic                                       | Where                                                                                          |
| ------------------------------------------- | ---------------------------------------------------------------------------------------------- |
| How to parse a document, flags, backends    | [`skills/unlimited-ocr-parse-document/SKILL.md`](skills/unlimited-ocr-parse-document/SKILL.md) |
| How to split a composite figure into panels | [`skills/unlimited-ocr-segment-figure/SKILL.md`](skills/unlimited-ocr-segment-figure/SKILL.md) |
| How to batch parse a folder with resume     | [`skills/unlimited-ocr-batch-folder/SKILL.md`](skills/unlimited-ocr-batch-folder/SKILL.md)     |
| Every measurement, with hardware and date   | [`references/EMPIRICAL.md`](references/EMPIRICAL.md)                                           |
| Every trap, with the evidence that found it | [`references/PITFALLS.md`](references/PITFALLS.md)                                             |
| Why this plugin is Python                   | [`python-allowlist.toml`](python-allowlist.toml)                                               |
| The CLI contract, machine-readable          | `uv run --no-project scripts/unlimited_ocr.py spec`                                            |

> **Self-Evolving Plugin**: improves through use. Everything asserted here was measured on
> 2026-07-30 on the two machines named in `references/EMPIRICAL.md`. If a number drifts or a
> behaviour changes, fix the file that owns that fact — do not add a second copy elsewhere.

---

## What this model is, in one paragraph

A 3B-total / **500M-activated** MoE document parser. It inherits DeepSeek-OCR's DeepEncoder (16×
visual token compression) and replaces every decoder attention layer with **Reference Sliding Window
Attention**, which holds the KV cache CONSTANT while decoding. That is why it can transcribe many
pages in one forward pass without the usual slow-down, and why it runs comfortably in ~5 GB on a
laptop. It is a **layout parser and text transcriber** — not an image captioner.

---

## The verdict

**Adopt it for text, mathematics, tables and layout. Do not adopt it for charts.**

It is genuinely excellent at what it does: on the QuantML corpus it transcribed a piecewise
definition into correct LaTeX in 2.4 s on a laptop, faithfully reproducing even a typo the original
author had made. It is competitive with the 2026 field on OmniDocBench v1.6 at a fraction of the
size, and it is MIT-licensed and runs offline.

It also **returns nothing at all for a chart** — nine perfect bounding boxes and zero characters on
a nine-panel figure. Any plan that treats it as a general vision-model replacement will silently
lose chart content.

**Both machines here can run it**, which was not obvious at the outset:

|        | Apple Silicon (MLX)                  | RTX 4090 (transformers)                       |
| ------ | ------------------------------------ | --------------------------------------------- |
| Status | **primary** — no SSH, no shared host | bulk / batch work                             |
| Speed  | 2.4 s per image, 5.2 GB peak         | 3.7 s per image, 8.3 GB VRAM                  |
| Setup  | `uv run` reads the PEP 723 header    | `uv` venv; **not** Docker, **not** SGLang+fa3 |

---

## Where it fits the work already on this machine

Ranked by expected value, with the reasoning that produced the ranking.

### 1. Academic PDFs (quantml stage 08/09, `doc-tools:academic-pdf-to-gfm`)

The clearest win. quantml already holds a hard-won finding that **a PDF text layer cannot yield
formulas** — mathematics is stored as positioned glyph runs — which is why it renders pages and
transcribes them with a vision model. This model does exactly that job, natively, locally, for free,
and returns page structure with it. Measured at 11 s/page on dense academic pages at 300 DPI.

### 2. Figure segmentation, as a NEW capability

Nothing in the current pipeline can split a nine-panel figure into nine images. This model can, and
the crops are accurate. Handing a chart-describing model one panel at a time instead of a collage is
a straightforward quality improvement that does not replace anything.

### 3. quantml stage 05 — NO, and the reason is the gate, not the model

**Measured on 127 images from the live corpus — 24 FORMULA and 103 TABLE, every transcription
produced by actually running the model. Full evidence:**
[`references/QUANTML-STAGE-05-THIRD-READER-HEAD-TO-HEAD.md`](references/QUANTML-STAGE-05-THIRD-READER-HEAD-TO-HEAD.md).

Agreement is decided by `findDiscrepancy()` — exact match
after normalisation, then a per-type Jaccard threshold. Extracted verbatim by script and run over
both samples:

| Pair                            | FORMULA (24) | TABLE (103) |
| ------------------------------- | ------------ | ----------- |
| M3 ↔ GLM-4.6v (existing pair)   | 5            | 30          |
| **M3 ↔ Unlimited-OCR**          | **0**        | **1**       |
| GLM-4.6v ↔ Unlimited-OCR        | **0**        | **0**       |
| deadlocks a third reader breaks | **0 of 19**  | **0 of 73** |

**FORMULA has no fix.** Three progressively aggressive bridges — strip layout markers, unwrap
single-token braces — all land on 0 of 24. The differences run into the LaTeX itself, not a
serialization skin over it.

**TABLE has a fix that exposes something worse.** Unlimited-OCR emits HTML `<table>` (88 of 103)
where both incumbents emit pipe-markdown, so nothing about the reading is being compared. Bridging
HTML → pipe-markdown lifts agreement to 25/103 (M3) and 62/103 (GLM) and breaks 42 of the 73
deadlocks — but **40 of those 42 side with GLM and 2 with M3**, while row counts are balanced
(26 closer to GLM, 21 closer to M3, 43 tied). The skew is the gate: Jaccard over a union of word
sets is size-sensitive, and Unlimited-OCR's mean output (2913 chars) simply cannot clear the 0.75
threshold against M3's (858) however correct both are. Its vote would be decided by how verbose the
other reader was.

**This reverses an earlier YES, and corrects a first attempt at reversing it.** The YES came from a
similarity ratio (0.838 vs 0.811, and it does break 7 of 8 disputes by that measure); the first
reversal used stage **09**'s `normalizeLatexForSemanticComparison`, which is not stage 05's gate at
all. Right answer, wrong function. Find the test the target system actually applies before scoring
against it.

Three defects in quantml surfaced by this, all now recorded there: `findDiscrepancy` was untested
and unexported despite deciding what enters the corpus as corroborated (fixed — extracted to
`pipeline/shared/transcription_agreement_gate.ts` with 26 tests); its Jaccard is size-sensitive in a
way the thresholds do not account for (trap 18, deliberately not fixed); and `status: "aligned"`
conflates first-try independent agreement with agreement reached after each model was shown the
other's answer — 99 of the 179 so labelled are genuine (trap 20).

### 4. TASC archive (~7,200 articles) — ASSESSED, AND THE ANSWER IS NO

Ranked last deliberately: it was the largest volume on the machine and it is **not a candidate**.

Fifty documents sampled uniformly across all nine decades (1982–2022) returned **hundreds to
thousands of characters per page** from a plain PyMuPDF text-layer read. The corpus is entirely
born-digital; there are no scanned page images to OCR. Its existing extraction already measures
**97.9 % word recall** against an independent vision benchmark, with 99.9 % agreement against a
second extractor.

Running OCR over it could only lose accuracy. **Do not pursue this.** An honest negative saves the
effort, and recording it stops the idea being re-proposed every time someone notices the corpus is
big.

---

## Quick start

```bash
S=~/eon/cc-skills/plugins/unlimited-ocr/scripts/unlimited_ocr.py

uv run --no-project $S doctor                              # what can this machine run?
uv run --no-project $S parse --input page.png              # markdown on stdout
uv run --no-project $S parse --input paper.pdf --output ./out
uv run --no-project $S segment --input figure.png --output ./panels
```

Nothing to install. `uv run` materialises the script's own dependencies from its PEP 723 header.

---

## The five things most likely to bite you

1. **Two of the three documented prompt modes are broken.** `document parsing.` decodes infinite
   garbage; `Multi page parsing.` hallucinates `industrydocuments` onto a single image. Use
   `Free OCR.` — the CLI default, and it refuses both of the others with the measured reason.
2. **Charts come back empty.** By design. Segment them instead.
3. **This CLI never sends more than one image per forward pass.** Measured: single-pass multi-image
   recovered 1 of 3, 4 of 5 and 0 of 10 pages; one call per page recovered 100 % in every
   condition. The model's headline multi-page capability is deliberately unused.
4. **The MODEL writes tables as HTML `<table>`, never pipe-markdown** — measured at 88 of 103 real
   tables, the other 15 as prose. The CLI converts them for you: `--table-format` defaults to
   `pipe`. Pass `--table-format html` to keep the model's own serialization.
5. **It fuses a LaTeX command with the identifier after it** — `\neqi` where `\neq i` belongs,
   measured 4 times on one paper with the correct form appearing ZERO times. Fluent, plausible,
   scores 0.97 token overlap against the true formula, and does not compile. Only 49 % of its
   recovered formulas compiled under pdfTeX on a paper where 98 % of the authors' source did.

Full list, with evidence: [`references/PITFALLS.md`](references/PITFALLS.md).
