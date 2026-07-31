# Unlimited-OCR — measured, on this hardware

Every number here was produced by running the model, on the machines named, on the dates named.
Nothing in this file is transcribed from the upstream README or the model card. Where a claim comes
from the paper rather than a run, it says so.

**Verified 2026-07-30.** Re-verify before changing any documented fact.

---

## The model

|            |                                                                                                                                                                |
| ---------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Repository | [`baidu/Unlimited-OCR`](https://github.com/baidu/Unlimited-OCR), MIT, created 2026-06-18                                                                       |
| Paper      | [arXiv 2606.23050](https://arxiv.org/abs/2606.23050), "Unlimited OCR Works"                                                                                    |
| Parameters | **3B total, 500M activated** (MoE: 64 routed experts, 6 active, 2 shared, 12 decoder layers) — paper §3.2                                                      |
| Encoder    | DeepEncoder from DeepSeek-OCR: SAM-ViT → CLIP-ViT with 16× token compression — paper §3.3                                                                      |
| Decoder    | all attention replaced by **Reference Sliding Window Attention (R-SWA)**, giving a CONSTANT KV cache — paper §3.4; `sliding_window_size: 128` in `config.json` |
| Weights    | 6.67 GB bf16 (`model-00001-of-000001.safetensors`)                                                                                                             |

The constant KV cache is the whole point: the paper's Table 4 shows throughput holding at
~7,850 TPS out to 6,144 output tokens, where DeepSeek-OCR decays from 7,229 to 5,823.

---

## Runtime A — Apple Silicon via MLX (this Mac)

**Host:** MacBook M3 Max, 36 GB unified memory, macOS darwin 24.6.0 arm64.

```bash
uv venv --python 3.14 && uv pip install mlx-vlm     # mlx-vlm 0.6.8, mlx 0.32.0, Python 3.14.6
```

`unlimited_ocr` is a **first-class model module in mlx-vlm** — `mlx_vlm/models/unlimited_ocr/`,
exporting `Model`, `SAMEncoder`, `MlpProjector`, `UnlimitedOCRProcessor` and `RingSlidingKVCache`
(the R-SWA implementation). It is not a DeepSeek-OCR shim.

**Model:** `mlx-community/Unlimited-OCR-mxfp8` — MXFP8, **3.66 GB**, last modified 2026-07-28.
(The older `sahilchachra/unlimited-ocr-mxfp8-mlx` pack has more downloads but its `config.json`
declares `model_type: deepseekocr`, which routes to the shim and is reported to produce repetitive
garbage on mlx-vlm 0.6+. The `mlx-community` pack fixes exactly that.)

| Measurement                       | Value                                                            |
| --------------------------------- | ---------------------------------------------------------------- |
| Single formula image, cold prompt | **2.4 s**                                                        |
| Same image, warm                  | 0.8 s                                                            |
| Peak memory                       | **5.166 GB**                                                     |
| Generation throughput             | 242 tok/s (prompt 246 tok/s)                                     |
| Quantisation fidelity             | output **byte-identical** to the CUDA bf16 run on the same image |

That last row is the important one: MXFP8 quantisation did not change the transcription at all on
the test image.

---

## Runtime B — NVIDIA via transformers (`bigblack` / el02)

**Host:** Ubuntu 24.04, kernel 6.17, 61 GB RAM, **RTX 4090, 24,564 MiB, driver 570.211.01,
compute capability 8.9 (Ada)**, CUDA toolkit 12.0.

| Measurement                                 | Value                                       |
| ------------------------------------------- | ------------------------------------------- |
| Model load                                  | 55.3 s                                      |
| VRAM after load                             | 6,916 MiB                                   |
| VRAM peak during inference                  | **8,318 MiB** (66 % of the card still free) |
| Single image                                | 3.73 s (2.75 s on re-run)                   |
| Multi-page, 5 synthetic pages               | 7.38 s total → 1.48 s/page                  |
| Multi-page, 5 dense academic pages @300 DPI | 55.26 s total → 11.05 s/page                |
| Determinism                                 | re-run produced **byte-identical** output   |
| GPU released cleanly afterwards             | yes — back to 34 MiB idle                   |

### Two things about this host that will waste your afternoon

1. **`--attention-backend fa3` does not work here.** The upstream README's SGLang command specifies
   FlashAttention-3, which requires Hopper (SM 9.0). This card is Ada (SM 8.9). The **transformers**
   path needs no backend flag and produced every number above.
2. **Docker was deliberately purged from this host on 2026-07-29.** The published
   `vllm/vllm-openai:unlimited-ocr` images are therefore not an option, and reinstalling Docker to
   use them would undo a deliberate decision. Use a `uv` venv.

---

## The output contract

```
<|det|>equation [249, 82, 699, 202]<|/det|>\[
c u r p d f = t r i a n g (l o w, h i g h, v o l)
\]
```

- **`[x0, y0, x1, y1]`, normalised to 0–1000 on BOTH axes.** Established by a box with `y1 = 909`
  emitted for a 795 × 211 image — 909 cannot be a pixel coordinate there. Converting back:
  `y 121–192 px` correctly lands on the bottom third, where that equation sits.
- **Categories observed:** `equation`, `title`, `text`, `chart`, `header`, `page_footnote`,
  `page_number`, `image`. Not documented upstream; this is what has actually appeared across the
  test set, not a closed set. Treat an unseen value as valid.
- **Display math in `\[ … \]`, inline in `\( … \)`.** Piecewise functions come back as real
  `\left\{ \begin{array}{l} … \end{array} \right.`.
- **Multi-page output separates pages with `<PAGE>`.**

### Mathematics is character-spaced

`curpdf` is emitted as `c u r p d f`. Every letter is its own math atom. In LaTeX math mode the two
render identically, so this is **not an error** — but it is not byte-identical to any other model's
output, which silently destroys cross-model agreement scoring. `--collapse-math-spacing` repairs it:

```
before: c u r p d f = t r i a n g (l o w, h i g h, v o l)
after:  curpdf = triang (low, high, vol)
```

### The MLX path returns the tokenizer's SURFACE FORM, not decoded text

**This was recorded wrongly in an earlier version of this file, which claimed "ordinary CJK and
Latin text was unaffected across every test". That claim was false — it had simply never been
tested on CJK.** The early test images were formula-only or English, where the surface form and
the decoded text coincide.

mlx-vlm returns byte-level-BPE surface characters, so every BYTE of a multi-byte UTF-8 character
arrives as its own stand-in character. On a Chinese corpus this is not degradation, it is total
loss:

```
8æľĪ                          ->  8月
åıįåĲĳæĹ¥åĨħéĢĨè½¬çļĦé¢ĳçİĩ  ->  反向日内逆转的频率
æĺŁæľŁåħŃ                     ->  星期六
âĳł                           ->  ①
```

The stray `âľī` previously filed here as an isolated mojibake of `✉` was never isolated — it was
the same defect, visible in English only because English is mostly ASCII.

`decode_byte_level_bpe_surface_form` reverses the standard GPT-2 byte-level-BPE alphabet and
recovers all of it. ASCII, and therefore all LaTeX, passes through byte-for-byte. Applying it to
already-decoded text is a no-op, so it is safe on either form. Eight tests pin the behaviour.

### It transcribes the source faithfully, including the source's mistakes

The test image's second line reads `decat = turnover_rate * Coeff` while its third line uses
`decay`. The model returned `decat`. That looked like an OCR error and was checked against the
source image: **the image itself says `decat`** — the typo is the original author's. The model
copied what was there instead of correcting it, which is the right behaviour for OCR.

---

## Benchmarks (from the paper — vendor-reported)

OmniDocBench, higher Overall is better:

| Model             | Size     | v1.5 Overall | v1.6 Overall |
| ----------------- | -------- | ------------ | ------------ |
| GPT-4o            | –        | 75.02        | –            |
| olmOCR            | 7B       | 81.79        | –            |
| Nanonets-OCR-s    | 3B       | 85.59        | –            |
| Gemini-2.5 Pro    | –        | 88.03        | –            |
| dots.ocr          | 3B       | 88.41        | 90.77        |
| Qwen3-VL          | 235B     | 89.15        | –            |
| DeepSeek-OCR 2    | 3B-A0.5B | 89.17        | 90.25        |
| FireRed-OCR       | 2B       | –            | 93.26        |
| Logics-Parsing-v2 | 4B       | –            | 93.33        |
| Qianfan-OCR       | 4B       | –            | 93.90        |
| **Unlimited-OCR** | 3B-A0.5B | **93.23**    | **93.92**    |

**Read the two columns differently.** On v1.5 the margin is genuinely large — +6.22 over the next
model, at 3B-A0.5B, beating a 235B model and Gemini-2.5 Pro. On **v1.6, which contains the 2026
field, the lead is 0.02 points over Qianfan-OCR — a tie**, and its Table TEDS (90.16) falls below
HunyuanOCR-1B's 91.01. Any claim of a decisive win is a v1.5 claim. Quoting the +6.22 without
saying which benchmark it came from would be misleading.

All of these are the authors' own numbers for their own model. Treat accordingly.

### Long-horizon degradation (paper, Table 3)

| Pages in one pass | 2       | 5       | 10      | 15      | 20      | 40+         |
| ----------------- | ------- | ------- | ------- | ------- | ------- | ----------- |
| Edit distance ↓   | 0.0362  | 0.0452  | 0.0526  | 0.0787  | 0.0572  | **0.1069**  |
| Distinct-20 ↑     | 99.76 % | 99.78 % | 97.49 % | 99.92 % | 98.73 % | **96.08 %** |

Quality **does** decay with page count — edit distance roughly triples from 2 pages to 40+, and
Distinct-20 falling to 96.08 % means measurable repetition creeping in. The non-monotonicity at
15 vs 20 pages suggests their evaluation is noisy at this granularity.

### The paper says the name is aspirational

> "Our model cannot achieve truly unlimited parsing under a finite context length (e.g., 32K), as it
> is also constrained by the prefill length." — §7, Limitation and Future Work

Pages accumulate in the prefill even though the decode-side KV cache stays constant. A 128K-context
version is stated as future work.

---

## Throughput on real corpus images (MLX, this Mac)

Two batches from the live quantml corpus, run through `scripts/unlimited_ocr.py parse` one image per
invocation — process start, model load, and inference each time, so these are end-to-end wall clock
per image and not a warm-loop steady state.

| Batch                 | n   | Median | Min   | Max    | Degenerate repetition | Empty output |
| --------------------- | --- | ------ | ----- | ------ | --------------------- | ------------ |
| `FORMULA` images      | 24  | ≈ 7 s  | 2.2 s | 38.2 s | 0                     | 0            |
| `TABLE` images        | 103 | 4.8 s  | 1.5 s | 39.4 s | 4                     | 1            |

The 4 degenerate-repetition detections out of 103 are the guard in `parse` firing on real input, not
a synthetic case — roughly 4 %, on tables, with the default `free-ocr` prompt. Budget for it.

Full analysis of what those transcriptions were worth:
[`QUANTML-STAGE-05-THIRD-READER-HEAD-TO-HEAD.md`](QUANTML-STAGE-05-THIRD-READER-HEAD-TO-HEAD.md).

## Reproducing all of this

```bash
S=~/eon/cc-skills/plugins/unlimited-ocr/scripts/unlimited_ocr.py
uv run --no-project $S doctor                                        # backend availability
uv run --no-project $S parse --input <image> --format json --quiet   # timings + boxes
uv run --no-project $S segment --input <figure> --output ./panels    # segmentation
```

The image used for the single-image numbers is a formula crop from the QuantML corpus:
`~/eon/quantml/data/articles/研报复现 _ 基于筹码分布的选股策略__2247485327/images/0b18dd5d5836.jpg`
(795 × 211, dark background). The nine-panel figure is `3bcde391d475.jpg` (1080 × 1504) in the same
directory.
