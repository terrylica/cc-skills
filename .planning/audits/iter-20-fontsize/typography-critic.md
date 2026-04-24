# Typography Critic: Floating Clock v3, iter-20

**Audit Date**: 2026-04-23  
**Font Pairing**: JetBrains Mono (user-chosen, PRIMARY/LOCAL) ↔ SF Mono 11pt Medium (SECONDARY/ACTIVE+NEXT)  
**Sizes Evaluated**: 10pt, 16pt, 24pt, 36pt, 48pt, 64pt

---

## Findings

### 1. Baseline Alignment — PROBLEMATIC

Across all sizes, the LOCAL (JetBrains) and SECONDARY (SF Mono 11pt) lines exhibit **consistent vertical misalignment**. The JetBrains baseline sits slightly _lower_ than the SF Mono line, creating visual tension especially pronounced at 10pt and 16pt where the size delta is minimal. This is driven by:

- **Cap height difference**: SF Mono 11pt medium has tighter, more uniform cap metrics; JetBrains carries slightly lower glyphs relative to ascenders.
- **x-height variance**: JetBrains x-height is marginally taller, pushing the baseline down visually.
- **Remedy**: Add explicit baseline alignment offset (approx 1–2pt downward nudge on SF Mono, or upward on JetBrains) to equalize optical baseline across the multi-line composition.

### 2. Optical Weight Balance — ACCEPTABLE TO GOOD

JetBrains Mono is perceptually heavier than SF Mono medium (confirmed in all sizes), but this is **visually appropriate** for a primary hierarchical element. The weight differential feels natural and intentional—LOCAL dominates without overwhelming.

- **At 10pt**: Weight advantage barely detectable; the two fonts feel siblings.
- **At 16–24pt**: Weight difference becomes subtly comfortable; JetBrains feels like the "main event."
- **At 36pt+**: JetBrains weight dominance is clean and commanding.

No intervention needed; the weight contrast is a feature, not a bug.

### 3. Ratio Integrity — NEEDS RATIONALIZATION

Current sizes (10, 16, 24, 36, 48, 64) do NOT follow a consistent typographic ratio:

| Size | Ratio to Previous |
| ---- | ----------------- |
| 10   | —                 |
| 16   | 1.60×             |
| 24   | 1.50×             |
| 36   | 1.50×             |
| 48   | 1.33×             |
| 64   | 1.33×             |

This creates **asymmetric visual jumps** and feels ad-hoc. Recommendation: **Snap to a harmonic ratio**.

**Proposed standard (1.333× / perfect 4:3 musical interval)**:

- 14pt, 18.7pt → 19pt, 25.3pt → 26pt, 33.8pt → 34pt, 45.3pt → 45pt, 60.4pt → 60pt

Or **1.414× ratio (√2, geometric progression)**:

- 12pt, 17pt, 24pt, 34pt, 48pt, 68pt

The 1.333× golden ratio (14→18.7→25→33→44→59) is musically satisfying and reduces cognitive friction. At 24pt (current default), use 26pt instead for cleaner ratios on both sides.

### 4. Character Width Consistency — STRONG MATCH

The monospaced digit alignment across all sizes is **excellent**. JetBrains and SF Mono both maintain strict proportional consistency:

- Numerals (0–9) scale linearly with font size.
- Colon separators maintain visual weight relative to digits.
- Even at 64pt, the digits feel related across families, not discordant.

**No issues here.** The monospaced nature of both families ensures numeric readability and rhythm.

---

## Summary & Recommendations

| Issue                 | Severity | Fix                                                                                                  |
| --------------------- | -------- | ---------------------------------------------------------------------------------------------------- |
| Baseline misalignment | Medium   | Add CSS/native offset to force same baseline; test with `vertical-align` or `line-height` adjustment |
| Ratio inconsistency   | Medium   | Adopt 1.333× ratio, snap sizes to [14, 19, 25, 34, 45, 60] or [12, 17, 24, 34, 48, 68]               |
| Weight imbalance      | Low      | None; feature is appropriate                                                                         |
| Digit consistency     | Low      | None; excellent                                                                                      |

### Specific Implementation Path

1. **Baseline fix**: Measure baseline delta in px at each size. Apply a `-1pt` to `+2pt` offset to SF Mono line via line-height or vertical translation.
2. **Ratio fix**: Update font-size allowlist to enforce harmonic progression. 24pt remains default; add 14pt/19pt for smaller contexts, 34pt/45pt for larger.
3. **Consider forced monospace family**: If baseline offset proves insufficient, override LOCAL to use `monospacedSystemFontOfSize(_:weight:)` for all sizes, forcing family consistency. Trade-off: loses user iTerm2 font choice, but guarantees optical alignment.

---

## Verdict

The floating-clock typography is **functionally sound** but has **aesthetic friction** in baseline alignment and visual hierarchy progression. Weight pairing is excellent. With baseline correction and ratio harmonization, this could shift from "good enough" to "polished."
