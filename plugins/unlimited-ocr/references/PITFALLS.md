# Unlimited-OCR — pitfalls, each one paid for

Every entry below was hit while building this plugin. Measurements and hardware in
[`EMPIRICAL.md`](EMPIRICAL.md).

---

## 1. TWO of the three documented prompt modes are broken on MLX

### 1a. `document parsing.` produces infinite garbage

**What happens.** `<image>document parsing.` — verbatim from the project README — decodes
`parsing.parsing.parsing.parsing…` until `max_tokens`. 2,048 tokens of it, at 242 tok/s, taking
47 seconds to produce nothing.

**What works.** `Free OCR.`, from the MLX model card, on the same image, same weights, same seed:
correct output with layout boxes in 2.4 s.

**Not fixed by the obvious remedies.** Adding `repetition_penalty=1.05` does not stop it. Applying
the chat template does not stop it. The prompt is the variable.

### 1b. `Multi page parsing.` HALLUCINATES on a single image

Given one image containing three formulas and nothing else, this prompt deterministically prepends
the word **`industrydocuments`** — text that appears nowhere in the source. Reproduced on
consecutive runs; `Free OCR.` on the same image never does it.

It is a prompt designed for a multi-image forward pass. This CLI sends one image per call by
design (see §3), so the mode has no correct use here at all.

**Defence in this plugin.** `--prompt-mode` defaults to `free-ocr`. Both `document-parsing` and
`multi-page` are **refused with exit 2**, each with its measured reason printed, unless
`--allow-withheld-prompt-mode` is passed. They are kept in the enum rather than deleted so the
failures stay nameable and reproducible — a mode that silently disappears teaches the next person
nothing, and they will reach for the upstream README and hit the same wall.

**Why this is dangerous in general.** The upstream CUDA path defends against degenerate decoding
with an n-gram blocker (`no_repeat_ngram_size=35, ngram_window=128`). `mlx-vlm` has **no equivalent
logit processor**, so the MLX path has no structural defence at all — only prompt choice. Any script
that hardcodes the README's prompt on Apple Silicon will silently emit garbage.

---

## 2. It will not tell you what is in a chart

Fed a 1080×1504 image of nine matplotlib panels, it returned **nine `chart` bounding boxes and zero
characters** — not the panel titles, not the axis labels, not the legends, all of which were
legible.

This is correct for a layout parser and catastrophic if you assumed it was an image captioner. Any
pipeline that swaps a general vision model out for this one on chart-heavy input will lose all chart
content and report success, because the model returns valid, well-formed, empty regions.

**Use the shape of the failure.** `unlimited_ocr.py segment` crops each detected region so a
chart-reading model can take them one at a time. Localisation is the thing this model is good at.

---

## 3. Single-pass multi-image LOSES CONTENT on MLX — measured, not suspected

The 4090 probe sent a five-page synthetic PDF through the model's own multi-image entry point and
got **four** pages back, with no error. That raised a hypothesis: the n-gram repetition blocker
spanning the whole generation, suppressing legitimately repeated content across pages.

**The hypothesis is refuted, and the truth is worse.** Measured on the MLX backend, 2026-07-30 —
each page carries one unmistakable unique marker, and the count is how many markers survive:

| Pages share boilerplate? | Pages | Markers recovered, ONE forward pass | Markers recovered, ONE CALL PER PAGE |
| ------------------------ | ----- | ----------------------------------- | ------------------------------------ |
| identical                | 3     | 1                                   | **3**                                |
| identical                | 5     | 4                                   | **5**                                |
| identical                | 10    | **0**                               | **10**                               |
| varied                   | 3     | 1                                   | **3**                                |
| varied                   | 5     | **0**                               | **5**                                |
| varied                   | 10    | **0**                               | **10**                               |

Two things fall out of that table.

**Content similarity is NOT the mechanism.** Pages with completely different text fare no better
than identical ones — 1, 0, 0 against 1, 4, 0. Had repetition suppression been the cause, the varied
condition would have survived. It did not, so the explanation is something about multi-image
handling itself, not about what the pages contain.

**Per-page is perfect in every condition — 3 of 3, 5 of 5, 10 of 10, six times out of six.** That is
not a marginal preference; it is the difference between a complete transcription and, at ten pages,
nothing recoverable at all.

**This is why the CLI sends one image per forward pass and offers no way to do otherwise.** The
model's headline capability — dozens of pages in a single pass with a constant KV cache — does not
survive contact with the MLX path as invoked here. The CUDA/transformers path did better in the one
run measured (four of five pages) but was still lossy, so this is not purely an MLX defect.

The cost of per-page is throughput, which is not the scarce resource. The cost of single-pass is
silent, unrecoverable data loss, which is the worst failure an archive can have.

## 4. "Unlimited" is not unlimited, and the paper says so

> "Our model cannot achieve truly unlimited parsing under a finite context length (e.g., 32K), as it
> is also constrained by the prefill length." — paper §7

R-SWA holds the **decode-side** KV cache constant. The **prefill** still grows with every page, so
there is a real page ceiling at 32K context. Quality also decays measurably with page count: edit
distance roughly triples from 2 pages to 40+ (0.0362 → 0.1069) and Distinct-20 falls to 96.08 %,
which is repetition beginning to show.

---

## 5. The headline benchmark margin is v1.5-only

Unlimited-OCR scores **93.23 on OmniDocBench v1.5, +6.22 over the next model**. On **v1.6 it scores
93.92 against Qianfan-OCR's 93.90** — a 0.02-point tie — and its table score drops below a 1B model's.

Both numbers are in the same table in the same paper. Quoting the first without the second turns a
"competitive with the 2026 field at a fraction of the size" story into a "dominates everything"
story, and only one of those is true.

---

## 6. `--pad-pixels 0` clips the axis labels off every chart crop

The model's boxes bound the **plotted area**, not the figure with its furniture. Cropping exactly on
the box removed the x-axis tick labels from all nine panels of the test figure — the units and the
date range, i.e. most of what a downstream describer needs.

Default is 12 px. Raise it for figures with outboard captions.

---

## 7. Non-ASCII is DESTROYED unless the byte-level-BPE surface form is decoded

The MLX path hands back the tokenizer's surface form rather than decoded text. Every byte of a
multi-byte UTF-8 character arrives as its own stand-in, so `8月` becomes `8æľĪ` and
`反向日内逆转的频率` becomes `åıįåĲĳæĹ¥åĨħéĢĨè½¬çļĦé¢ĳçİĩ`. On a Chinese corpus that is not
degradation, it is total loss.

**It hid for a long time because ASCII is a fixed point of the encoding.** The first test images
were formula-only or English; LaTeX and English prose survive untouched, so the output looked
perfect. This file previously recorded a stray `âľī` as an isolated mojibake of `✉` in an English
paper — that was the same defect all along, merely rare enough in English to look like a one-off.

`decode_byte_level_bpe_surface_form` reverses the standard alphabet. Anyone calling mlx-vlm
directly rather than through this CLI must do the same, or their Chinese output is worthless.

**The lesson generalises: a test corpus that shares an alphabet with the failure mode cannot see
it.** Test on the script you actually care about.

---

## 8. Model loading writes to stdout and corrupts `--format json`

`mlx-vlm`'s loader prints half a dozen tokenizer lines (`Add pad token = …`, `Added chat tokens`) to
**stdout**. In JSON mode they land in front of the document and every downstream `json.load` dies
with `Expecting value: line 1 column 1 (char 0)`.

Fixed here by wrapping the load in `contextlib.redirect_stdout(sys.stderr)`. If you invoke the
libraries directly rather than through this CLI, you must do the same. A machine-readable mode
corrupted by its own progress logging is not machine-readable.

---

## 9. A PEP 723 header makes `ty` ignore the repository's config

Discovered while getting this plugin's type check clean, and reproduced in isolation:

```
same file, no PEP 723 header  + repo ty.toml [[overrides]]  ->  All checks passed
same file, WITH PEP 723 header + the identical override      ->  Found 1 diagnostic
```

A PEP 723 header makes `ty` (0.0.64) treat the script as **its own project root**, so a
repository-level `ty.toml` no longer applies to it. Putting a `ty.toml` next to the script does not
help either.

**Resolution used here:** none of the suppressions — the optional heavy backends (`mlx_vlm`,
`torch`, `transformers`, `fitz`, `PIL`) are imported through `importlib.import_module` instead. That
is honest about what they are (runtime-selected, optional, not repository dependencies), needs no
config override at all, and is the "fix the error" branch of the code-correctness hook's own
hierarchy rather than the "suppress it" branch.

---

## 10. `find_spec` RAISES for a submodule whose parent is missing

`importlib.util.find_spec` returns `None` for an absent top-level module but **raises
`ModuleNotFoundError` for a submodule whose parent package is absent**. So
`find_spec("mlx.core")` on a Mac that has never installed mlx does not answer "no" — it throws.

Uncaught, `doctor` crashed with a traceback on precisely the machine it exists to serve: a Mac where
the backend is not yet installed. Found by a test that drove the real command with no backend
present, not by reading the code.

The probe now catches `ModuleNotFoundError` and `ValueError` per module and records it as missing.

---

## 11. Hosted alternatives are thinner than they look

- **Baidu Cloud** does publish this model as a hosted OCR API. Account creation on the international
  platform accepts international phone numbers, but identity verification is required for most
  services and the documentation is Chinese-first. It is not a drop-in for a North-American user.
- **The HuggingFace Space** is a demo. It is not sized for batch work.
- **No mainstream Western inference provider carries this model** at the time of writing — it is not
  on OpenRouter, Replicate, Together, or Fal.

Self-hosting on hardware you already own is not a fallback here; it is the primary path.

---

## 12. It serializes tables as HTML, not as pipe-markdown

Measured over 103 TABLE images from the quantml corpus: Unlimited-OCR emitted an HTML `<table>` for
**88** of them and prose for the other 15. Zero pipe-markdown. The two vision models quantml already
runs (MiniMax-M3, GLM-4.6v) emitted pipe-markdown for 205 of the same 206 readings.

A `--table-format pipe` flag (the default) converts HTML `<table>` markup to pipe-markdown before
output. Pass `--table-format html` to keep raw HTML.

This matters far more than a formatting preference:

- Any pipeline that **compares** this model's output against another reader's can now compare
  markdown-to-markdown instead of HTML-to-markdown. A ~15-line HTML-`<tr>`/`<td>`-to-pipe
  renderer took agreement from 1/103 to 62/103 in
  [`QUANTML-STAGE-05-THIRD-READER-HEAD-TO-HEAD.md`](QUANTML-STAGE-05-THIRD-READER-HEAD-TO-HEAD.md).
- Any pipeline that **concatenates** its output into a markdown document gets pipe-markdown tables
  by default, which render correctly. Use `--table-format html` to get raw HTML if your downstream
  expects it.

Its HTML is also considerably more verbose: mean output length across those 103 images was 2913
characters against M3's 858 and GLM's 1374, for a median row count (12) that sits between the two
(9 and 13). The extra characters are markup, not content — which is exactly why any similarity or
overlap metric applied to the raw output is measuring the markup.

---

## 13. It fuses a LaTeX command with the identifier that follows it

Measured 2026-07-31 against ground truth — the authors' own LaTeX for arXiv:2605.00501, obtained
from the e-print source and compared with the model's reading of the same paper's PDF:

| Model emitted  | Should be             | Occurrences | Correctly-spaced form appears |
| -------------- | --------------------- | ----------: | ----------------------------: |
| `\neqi`        | `\neq i`              |           5 |                         **0** |
| `\DeltaRankIC` | `\Delta\text{RankIC}` |           2 |                         **0** |
| `\equivP`      | `\equiv P`            |           1 |                         **0** |
| `\logP`        | `\log P`              |           1 |                         **0** |

The correct form appears **zero** times, so this is systematic rather than occasional.

**It is NOT `--collapse-math-spacing`.** That was the obvious suspect and it was tested directly:
given `\sum_ {j \neq i} x`, `P \equiv P (...)`, `\log P` and `\Delta \text{RankIC}`, the function
returns each unchanged. The fusion is in the model's own output.

Why this matters more than four occurrences suggests: the result is fluent, plausible, scores 0.97
token overlap against the true formula, and **does not compile**. Across that paper, 27 of 55
recovered formulas compiled under pdfTeX — 49 % — against 54 of 55 for the source. A reader skimming
the markdown will not catch it; only a TeX engine will.

**If you need formulas you will actually run, check them with a TeX engine, and prefer the source
when one exists.** For arXiv papers it always does — see the `arxiv-source-first` plugin, and
[`../../arxiv-source-first/references/OCR-VERSUS-AUTHOR-LATEX-GROUND-TRUTH.md`](../../arxiv-source-first/references/OCR-VERSUS-AUTHOR-LATEX-GROUND-TRUTH.md)
for the full comparison.
