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

## 3. Single-pass multi-page is deliberately not exposed

A five-page synthetic PDF whose pages were near-identical (same boilerplate, only a page number
differing) came back with **four pages**. Page 5 was absent, and a stray `<|/det|>` fragment leaked
into page 3's text.

The same three near-duplicate pages parsed **one call per page** all retained their unique markers.

**The n-gram hypothesis is refuted for this CLI, on a technicality that matters.** The CLI loops
over images and issues **one call per image**, so the repetition blocker is scoped per image and can
never span pages. Cross-page suppression is not possible here by construction. The mechanism behind
the 4090 observation, which used the model's own multi-image entry point, remains unexplained.

**The design decision that follows.** This CLI does not expose single-pass multi-page at all. The
model's headline capability — dozens of pages in one forward pass with a constant KV cache — is
deliberately unused, because:

- a page vanished with no error in the one multi-page run that was measured, and an undetectable
  loss is the worst possible failure mode for an archive;
- the prompt that mode requires hallucinates on a single image (§1b);
- per-page calls make every page independently verifiable, and let the loop detector see each page
  on its own rather than averaged across a long generation.

The cost is throughput, which is not the scarce resource here.

---

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

## 7. Model loading writes to stdout and corrupts `--format json`

`mlx-vlm`'s loader prints half a dozen tokenizer lines (`Add pad token = …`, `Added chat tokens`) to
**stdout**. In JSON mode they land in front of the document and every downstream `json.load` dies
with `Expecting value: line 1 column 1 (char 0)`.

Fixed here by wrapping the load in `contextlib.redirect_stdout(sys.stderr)`. If you invoke the
libraries directly rather than through this CLI, you must do the same. A machine-readable mode
corrupted by its own progress logging is not machine-readable.

---

## 8. A PEP 723 header makes `ty` ignore the repository's config

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

## 9. `find_spec` RAISES for a submodule whose parent is missing

`importlib.util.find_spec` returns `None` for an absent top-level module but **raises
`ModuleNotFoundError` for a submodule whose parent package is absent**. So
`find_spec("mlx.core")` on a Mac that has never installed mlx does not answer "no" — it throws.

Uncaught, `doctor` crashed with a traceback on precisely the machine it exists to serve: a Mac where
the backend is not yet installed. Found by a test that drove the real command with no backend
present, not by reading the code.

The probe now catches `ModuleNotFoundError` and `ValueError` per module and records it as missing.

---

## 10. Hosted alternatives are thinner than they look

- **Baidu Cloud** does publish this model as a hosted OCR API. Account creation on the international
  platform accepts international phone numbers, but identity verification is required for most
  services and the documentation is Chinese-first. It is not a drop-in for a North-American user.
- **The HuggingFace Space** is a demo. It is not sized for batch work.
- **No mainstream Western inference provider carries this model** at the time of writing — it is not
  on OpenRouter, Replicate, Together, or Fal.

Self-hosting on hardware you already own is not a fallback here; it is the primary path.
