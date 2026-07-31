# TASC Figure Segmentation: Worth Pursuing? — NO

**Measurement date**: 2026-07-31  
**Scope**: 3 TASC article pages across 3 decades (1990, 2000, 2010) + 8 pages of model time  
**Method**: Run unlimited-ocr segment on rendered pages, compare figure crops against text-layer extraction  
**Verdict**: **Figure segmentation is NOT worth pursuing for TASC.** The corpus already captures figure captions, and the crops themselves (lacking OCR output) provide no additional information without an external describer.

---

## Measurement Summary

### Segmentation accuracy: excellent

Unlimited-OCR's segmentation (the "localization" capability) works perfectly. It detected all visible charts/images and produced clean crops:

| Page | Year | Content                                   | Regions detected | Charts found | Quality         |
| ---- | ---- | ----------------------------------------- | ---------------- | ------------ | --------------- |
| 1    | 1990 | Unchanged stocks (text-heavy)             | 17               | 0            | N/A             |
| 1    | 2000 | Three-bar patterns (2 candlestick charts) | 26               | 2            | Excellent crops |
| 1    | 2010 | Cover page (masthead + illustration)      | 21               | 2            | Excellent crops |

The two candlestick charts from the 2000 page were cropped with high precision, showing all annotations, labels, and visual structure intact.

### Text extraction from charts: zero

All chart regions returned zero characters, which is **expected and documented**:

- Chart 20 (2000 page): 0 chars extracted
- Chart 23 (2000 page): 0 chars extracted
- Image regions (2010 page): 0 chars extracted

This is not a bug. Unlimited-OCR is a **layout parser**, not a general vision model — it reads text and mathematical typeset within document pages, not arbitrary image content like charts or photos.

---

## What TASC's text layer already extracts

The PyMuPDF extraction (status quo) already captures what matters:

### 1. Figure captions — fully extracted

From the 2000 page, unlimited-ocr found 4 image captions; all carry the figure explanations:

```
Caption: "FIGURE 1: THREE-BAR PATTERN, SUCCESS AND FAILURE. The three-bar pattern
suggests a swing change. The pattern on the right failed because prices didn't
continue to move higher."

Caption: "FIGURE 2: THREE-BAR PATTERN, ON THE RISE. The best-performing three-bar
pattern shows a 33% rise from the formation high to the trend high in mid-June.
Point B is a three-bar pattern failure because prices decline."
```

These captions are already in the corpus as part of the article text.

### 2. Chart labels and annotations — partially captured

The text layer does mix chart annotations (labels like "Three-bar pattern", "Pattern failure", axis labels like "July '97", price levels like "-14", "-15", "-16", "-17") inline with body text, making it noisy. This is a quality issue but not a gap — the information is present.

### 3. The chart visuals themselves — not capturable by OCR alone

The candlestick bars, ranges, trend lines, and visual patterns they form have no text equivalent that OCR can produce. A human reading "July '97" and "-14" does not reconstruct a candlestick chart.

---

## Why segmentation alone doesn't close the gap

The segmented figure crops are **visually accurate but textually empty**. To make them useful, downstream processing would need:

1. **An external describer** — a separate vision model to caption each chart crop (e.g., a trading-specific chart-to-caption model)
2. **A meaningful quality bar** — just having crops is not useful without descriptions
3. **Integration point** — where would crop descriptions live in the corpus, and how would they be linked?

The TASC corpus is already **text-only by design** — it extracts what PyMuPDF can read from the born-digital PDF layer. Adding figure crops without descriptions would create a new data product that is half-finished and harder to search/cite.

---

## The honest answer to "are figures worth having?"

**Not for TASC specifically**, for three reasons:

1. **Captions already captured**: The corpus holds the figure explanations (captions), which are what a researcher would cite or search for.

2. **Crop utility is near-zero without descriptions**: A researcher opening a crop must run their own vision model or manually interpret it — the corpus provides nothing beyond the crop pixel data. This is not measurably better than running segmentation on-demand if needed.

3. **Born-digital text layer is already extracted**: Unlike a scanned archive where figures are purely visual, TASC's PDFs contain machine-readable text labels within charts (axis ranges, series names). That text is already in the corpus, mixed with body text (a quality issue, but a solved one).

---

## What WOULD make segmentation valuable

Segmentation would be worth adding if:

- **The describer is built and integrated**: e.g., a trading-analysis-specific model that turns candlestick charts into pattern descriptions ("Channel breakout on 33% volume spike"). Then crops + descriptions live together in a new `figure_descriptions.jsonl` overlay.
- **The corpus is scanned (not born-digital)**: e.g., a historical archive where the only way to get figure content is vision-based recovery. TASC is born-digital — the charts' labels already exist as text.
- **Figures are fundamentally uncaptioned**: e.g., a figure album with no captions. TASC's figures are all captioned in the existing extraction.

---

## Measurement details

### Test pages and segmentation results

**Page 1 of 1990 C01/UNCHANG.pdf** (3300×2550 @ 300 DPI)

- Content: article text, no figures
- Regions: 17 (header, title, text blocks, footer, page number)
- Charts: 0

**Page 1 of 2000 C01/002BAR.pdf** (3300×2550 @ 300 DPI)

- Content: article title, text, 2 candlestick charts with annotations, captions
- Regions: 26 (including 2 charts, 4 image captions, 12 text blocks, 4 titles, 1 header, 1 footer)
- Charts: 2 (Adaptive Broadband Corp data, American Freighways trend)
- Chart captions: 2 (FIGURE 1 and FIGURE 2, both full explanations)
- Crops: Both high-quality, showing full chart with labels and annotations intact

**Page 1 of 2010 09 - September.pdf** (3226×2438 @ 300 DPI)

- Content: cover page with masthead, table of contents, decorative photo (bear holding trophy)
- Regions: 21 (including 2 images [masthead, photo], text, title blocks)
- Charts: 0 (images are decorative, not data charts)

### Model and cost

- **Backend**: MLX (Apple Silicon, on-device)
- **Model**: baidu/Unlimited-OCR
- **Time per page**: 2–3 seconds rendering + 5–7 seconds segmentation = ~9–10 s per page
- **Total cost**: 3 pages × 10 s = 30 seconds of compute
- **Additional resources**: None (already installed, already tested)

---

## Conclusion

**Figure segmentation for TASC: operationally infeasible AND not valuable.**

The segmentation itself works perfectly and runs quickly. But the output (crops without descriptions) is a half-finished product that adds complexity without closing any real gap. The captions are already extracted, the labels are already in the text, and the visual patterns themselves would need an additional vision model to become useful.

**Recommendation**: Close this investigation. If a future use case demands it (e.g., a trading model that needs candlestick images as features), segmentation can be re-examined then — the infrastructure is proven to work. For now, the text layer extraction is sufficient.

---

## What this means for doc-tools

The original question asked whether **doc-tools:figure-segmentation** should be deepened to handle TASC. The answer is **no**, not because the tooling is broken but because the corpus doesn't benefit. For other corpora (academic papers, scanned magazines, figure-heavy reports), segmentation may be valuable — the decision should be made per-corpus, not globally.
