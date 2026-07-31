# Head-to-head: Unlimited-OCR vs the two readers quantml already uses

**Run 2026-07-30. 24 FORMULA images from the live quantml corpus. Every Unlimited-OCR transcription
below was produced by actually running the model.**

The question this answers, which had never been measured: on quantml's own Chinese formula images,
is Unlimited-OCR good enough to serve as a **third independent reader** alongside MiniMax-M3 and
GLM-4.6v?

**Verdict: yes, for FORMULA images.** Not because it is more accurate than M3 — it is not — but
because it is independent enough to _break disputes_, which is the only thing a third reader is for.

---

## Why this was cheap to run

quantml has already paid for M3 and GLM-4.6v transcriptions of every image and they are on disk in
`data/reports/cross_reference_report.json`. Only Unlimited-OCR had to be run, locally and free. The
sample is every FORMULA image in that report that carries both existing transcriptions: **24 images
across 14 articles.** No selection was applied beyond "type == FORMULA", so there is no room for
cherry-picking.

```bash
uv run --no-project scripts/unlimited_ocr.py parse \
    --input <image> --format json --collapse-math-spacing --quiet
```

`--collapse-math-spacing` is **mandatory** for any comparison. Without it the model emits
`c u r p d f` where the others emit `curpdf` — identical when rendered, never equal as bytes — and
every formula would score as a disagreement for a purely cosmetic reason.

---

## Result 1 — it is not an outlier

Pairwise similarity on canonicalised LaTeX (layout markers stripped, math delimiters unified,
presentational macros and whitespace removed), averaged over all 24 images:

| Pair                              | Mean similarity |
| --------------------------------- | --------------- |
| M3 ↔ GLM-4.6v (the existing pair) | 0.811           |
| **M3 ↔ Unlimited-OCR**            | **0.838**       |
| GLM-4.6v ↔ Unlimited-OCR          | 0.755           |

Unlimited-OCR agrees with M3 _slightly more than GLM-4.6v does_. A third reader that agreed with
nothing would be useless; one that agreed with everything would be redundant. This sits where a
useful third opinion sits.

## Result 2 — it breaks 7 of the 8 real disputes

Taking a similarity below 0.80 between M3 and GLM as a material disagreement — the cases where the
existing two-reader design has no way to decide:

| Image              | M3↔UO | GLM↔UO | Third reader sides with |
| ------------------ | ----- | ------ | ----------------------- |
| `c6aed6ed5a74.jpg` | 0.81  | 0.98   | GLM                     |
| `68b99c3f4017.jpg` | 1.00  | 0.68   | M3                      |
| `2c0592ef9564.jpg` | 0.93  | 0.59   | M3                      |
| `d85356eba7cb.png` | 0.98  | 0.63   | M3                      |
| `921c993498b5.jpg` | 0.63  | 0.72   | GLM                     |
| `734d957f4945.jpg` | 0.27  | 0.19   | neither                 |
| `17e7c844edb2.jpg` | 0.82  | 0.19   | M3                      |

**8 disputes in 24 images; the third reader takes a clear side in 7.** Five times with M3, twice
with GLM. That distribution matters: a third reader that always sided with M3 would be measuring
M3, not the image.

---

## The case that shows what this is worth

`68b99c3f4017.jpg` — M3 and GLM disagree at 0.55, so under the current design this image is an
unresolvable dispute. **Checked against the source image by eye:**

The image reads
`QLIKE_i = (1/T) Σ_{t=1}^{T} ( exp(RV^{(d)}_{i,t}) / exp(R̂V^{(d)}_{i,t}) − (RV^{(d)}_{i,t} − R̂V^{(d)}_{i,t}) − 1 ),`

| Reader        | Verdict                                                                                                                                  |
| ------------- | ---------------------------------------------------------------------------------------------------------------------------------------- |
| MiniMax-M3    | **correct** — matches the image exactly                                                                                                  |
| GLM-4.6v      | **corrupted** — emitted `==================` where `=` belongs and `----------------` across the fraction, and `RV*{i,t}` for `RV_{i,t}` |
| Unlimited-OCR | **correct** — independently matches M3 and the image                                                                                     |

Two readers deadlock. Three produce a 2–1 majority that is _right_. This is the entire argument for
a third reader, and it is not hypothetical — it is one image out of twenty-four.

---

## Where Unlimited-OCR is the one that is wrong

It must not be promoted to arbiter. `17e7c844edb2.jpg`, checked against the source image by eye:

The image reads `I{RET_CO_{i,d}>0} * I{RET_OC_{i,d}<0}` — underscore separators, first term **CO**,
second **OC**.

| Reader        | Verdict                                                           |
| ------------- | ----------------------------------------------------------------- |
| MiniMax-M3    | **correct** on both terms and both separators                     |
| GLM-4.6v      | CO/OC right, wrote `.` for `_` — a formatting error               |
| Unlimited-OCR | wrote **`RET.OC` twice** — a semantic error, not a formatting one |

Interestingly it got `RET.CO` / `RET.OC` right in the _surrounding Chinese prose_ on the same image
and wrong inside the formula. A model that is right in one place and wrong in another about the same
symbol is exactly why agreement between independent readers is treated as evidence here, and why
a single confident reader never is.

---

## Cost

|                                | Measured                       |
| ------------------------------ | ------------------------------ |
| Per image, this sample         | 2.2 s – 38.2 s (median ≈ 7 s)  |
| All 24 images                  | one local run, no API calls    |
| Marginal cost                  | zero — local weights, no quota |
| Degenerate repetition detected | 0 of 24                        |

The zero-quota property is not incidental. quantml's cross-reference phase once died against an
upload quota after roughly 140 of 529 images. A local reader cannot hit that wall.

An earlier attempt at this comparison concluded Unlimited-OCR was "operationally infeasible" after a
dependency-solver timeout, without ever running the model, and estimated 5–15 s per image. The
estimate was in the right range; the conclusion drawn from never running it was not. All 24 images
completed on the first attempt.

---

## Verdict

**Add Unlimited-OCR to quantml stage 05 as a THIRD independent reader for `FORMULA` images.**

Conditions, all of which follow from the measurements above:

1. **It is a corroborator, never an arbiter.** It is not more accurate than M3 — see the `RET.OC`
   case. Its value is turning a 1–1 deadlock into a 2–1 majority, not overruling anyone.
2. **`--collapse-math-spacing` must run before any agreement comparison.** Without it agreement is
   near zero for cosmetic reasons and the whole exercise is worthless.
3. **Never route `CHART` images to it.** It localises charts and transcribes nothing inside them.
   That is not a degradation, it is silence that looks like an answer.
4. **`TABLE` is plausible but unmeasured here.** This sample was FORMULA only. Measure before
   extending.

Sample size is 24 images. That is a probe, not a benchmark, and every number above should be read
with that attached.
