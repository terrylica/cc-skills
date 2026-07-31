# unlimited-ocr — plugin hub

Local document parsing with [`baidu/Unlimited-OCR`](https://github.com/baidu/Unlimited-OCR) (MIT):
markdown, LaTeX, and per-block layout bounding boxes, on hardware you already own. No API key, no
per-image cost, no upload quota, nothing leaves the machine.

This file is the hub. Facts live in exactly one place:

| Topic                                       | Where                                                                                          |
| ------------------------------------------- | ---------------------------------------------------------------------------------------------- |
| How to parse a document, flags, backends    | [`skills/unlimited-ocr-parse-document/SKILL.md`](skills/unlimited-ocr-parse-document/SKILL.md) |
| How to split a composite figure into panels | [`skills/unlimited-ocr-segment-figure/SKILL.md`](skills/unlimited-ocr-segment-figure/SKILL.md) |
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

### 3. quantml stage 05 — as a THIRD reader, never as a replacement

This needs stating carefully, because the obvious move is wrong.

quantml deliberately runs **two independent vision models** (MiniMax-M3 and GLM-4.6v) and treats
their agreement as evidence of correctness. Agreement is ~22 %; that is not a quality score, it is
two systems with different failure modes converging. Swapping one out for a third model does not
improve that design — it just changes whose blind spots you inherit.

What Unlimited-OCR can legitimately do there:

- **Add a third independent reader for FORMULA and TABLE images**, which is exactly where corroboration
  is most valuable and where this model is strongest. Three readers turn a 2-way disagreement into a
  majority.
- **It cannot read CHART images at all**, so it must never be routed to them.
- **Its LaTeX will disagree with everything by default.** It emits `c u r p d f` where the others
  emit `curpdf`. The two render identically, but a byte comparison scores every formula as a
  disagreement. `--collapse-math-spacing` exists for precisely this and would have to run before
  any agreement check.

Being free and local matters here for a concrete reason: the cross-reference phase once died against
an upload quota after ~140 of 529 images. A local reader has no quota.

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

## The three things most likely to bite you

1. **Two of the three documented prompt modes are broken.** `document parsing.` decodes infinite
   garbage; `Multi page parsing.` hallucinates `industrydocuments` onto a single image. Use
   `Free OCR.` — the CLI default, and it refuses both of the others with the measured reason.
2. **Charts come back empty.** By design. Segment them instead.
3. **This CLI never sends more than one image per forward pass.** The model's headline multi-page
   mode is deliberately unused: a five-page run returned four pages with no error.

Full list, with evidence: [`references/PITFALLS.md`](references/PITFALLS.md).
