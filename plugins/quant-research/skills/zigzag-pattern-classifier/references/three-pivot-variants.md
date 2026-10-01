# UP–DOWN–UP Variants: 9 Complete Classification

Exhaustive analysis of all 9 possible three-pivot UP–DOWN–UP ZigZag patterns: L0→H1→L2→H3.

## Overview

With confirmed non-repainting pivots following the pattern UP–DOWN–UP, exactly **9 mutually exclusive, collectively exhaustive variants** exist. See [notation-definitions.md](notation-definitions.md) for [pivot notation](notation-definitions.md#pivot-notation) (L₀, H₁, L₂, H₃) and [price level relationships](notation-definitions.md#price-level-relationships) (HL, EL, LL, HH, EH, LH).

They differ along two independent dimensions:

1. **L2 vs L0**: {HL (higher), EL (equal), LL (lower)}
2. **H3 vs H1**: {HH (higher), EH (equal), LH (lower)}

This yields 3×3=9 combinations, all mathematically feasible and market-relevant.

## Constraint Structure

All 9 variants satisfy these mandatory inequalities:

- L0 < H1 (first uptrend)
- L2 < H1 (second low is below first high)
- H3 > L2 (second uptrend)

No variant is forbidden by these constraints.

## Classification Matrix

| Variant | Relative L2  | Relative H3  | Name                        | Market Regime           |
| ------- | ------------ | ------------ | --------------------------- | ----------------------- |
| 1       | L2 > L0 (HL) | H3 > H1 (HH) | **Continuation impulse**    | Bull trend continuation |
| 2       | L2 > L0 (HL) | H3 ≈ L1 (EH) | **Double-top test**         | Range, bullish bias     |
| 3       | L2 > L0 (HL) | H3 < H1 (LH) | **Triangle compression**    | Neutral consolidation   |
| 4       | L2 ≈ L0 (EL) | H3 > H1 (HH) | **Range break up**          | Bullish transition      |
| 5       | L2 ≈ L0 (EL) | H3 ≈ H1 (EH) | **Rectangle**               | Balanced range          |
| 6       | L2 ≈ L0 (EL) | H3 < H1 (LH) | **Lower-high at flat base** | Range, bearish bias     |
| 7       | L2 < L0 (LL) | H3 > H1 (HH) | **V-reversal, spring**      | Bullish reversal        |
| 8       | L2 < L0 (LL) | H3 ≈ H1 (EH) | **Undercut then stall**     | Volatile range          |
| 9       | L2 < L0 (LL) | H3 < H1 (LH) | **Rally failure**           | Bear trend continuation |

## ASCII Visualizations

All pivots marked with •. Levels scale: top→bottom = high→low price.

### 1) HL+HH — Continuation Impulse

**Market regime**: Bull trend continuation
**Interpretation**: Fresh swing high; series likely extends further up.

```
Levels │ L0 │ H1 │ L2 │ H3 │
HH     │    │    │    │ •  │
H1/EH  │    │ •  │    │    │
LH/HL  │    │    │ •  │    │
L0/EL  │ •  │    │    │    │
LL     │    │    │    │    │
```

---

### 2) HL+EH — Double-Top Test from HL

**Market regime**: Range, bullish bias
**Interpretation**: Second high retests first high; breakout pending above H1.

```
Levels │ L0 │ H1 │ L2 │ H3 │
HH     │    │    │    │    │
H1/EH  │    │ •  │    │ •  │
LH/HL  │    │    │ •  │    │
L0/EL  │ •  │    │    │    │
LL     │    │    │    │    │
```

---

### 3) HL+LH — Triangle Compression

**Market regime**: Neutral consolidation
**Interpretation**: Highs declining, lows holding; range compression may precede directional break.

```
Levels │ L0 │ H1 │ L2 │ H3 │
HH     │    │    │    │    │
H1/EH  │    │ •  │    │    │
LH/HL  │    │    │ •  │ •  │
L0/EL  │ •  │    │    │    │
LL     │    │    │    │    │
```

---

### 4) EL+HH — Range Break Up

**Market regime**: Bullish transition
**Interpretation**: Lows flat; highs new; bullish breakout confirmed.

```
Levels │ L0 │ H1 │ L2 │ H3 │
HH     │    │    │    │ •  │
H1/EH  │    │ •  │    │    │
LH/HL  │    │    │    │    │
L0/EL  │ •  │    │ •  │    │
LL     │    │    │    │    │
```

---

### 5) EL+EH — Rectangle

**Market regime**: Balanced range
**Interpretation**: Both highs and lows equal; perfect box pattern; breakout imminent.

```
Levels │ L0 │ H1 │ L2 │ H3 │
HH     │    │    │    │    │
H1/EH  │    │ •  │    │ •  │
LH/HL  │    │    │    │    │
L0/EL  │ •  │    │ •  │    │
LL     │    │    │    │    │
```

---

### 6) EL+LH — Lower-High at Flat Base

**Market regime**: Range, bearish bias
**Interpretation**: Lows flat; highs failing; bearish setup for downside extension.

```
Levels │ L0 │ H1 │ L2 │ H3 │
HH     │    │    │    │    │
H1/EH  │    │ •  │    │    │
LH/HL  │    │    │    │ •  │
L0/EL  │ •  │    │ •  │    │
LL     │    │    │    │    │
```

---

### 7) LL+HH — V-Reversal, Spring

**Market regime**: Bullish reversal
**Interpretation**: Deep undercut followed by surge; classic reversal pattern; reversal likely confirmed.

```
Levels │ L0 │ H1 │ L2 │ H3 │
HH     │    │    │    │ •  │
H1/EH  │    │ •  │    │    │
LH/HL  │    │    │    │    │
L0/EL  │ •  │    │    │    │
LL     │    │    │ •  │    │
```

---

### 8) LL+EH — Undercut Then Stall

**Market regime**: Volatile range
**Interpretation**: Strong dip tested; recovery stalls at prior high; uncertain trend.

```
Levels │ L0 │ H1 │ L2 │ H3 │
HH     │    │    │    │    │
H1/EH  │    │ •  │    │ •  │
LH/HL  │    │    │    │    │
L0/EL  │ •  │    │    │    │
LL     │    │    │ •  │    │
```

---

### 9) LL+LH — Rally Failure

**Market regime**: Bear trend continuation
**Interpretation**: Lows break lower; highs decline; downtrend reinforced.

```
Levels │ L0 │ H1 │ L2 │ H3 │
HH     │    │    │    │    │
H1/EH  │    │ •  │    │    │
LH/HL  │    │    │    │ •  │
L0/EL  │ •  │    │    │    │
LL     │    │    │ •  │    │
```

---

## Pattern Performance Notes

Each variant's market regime is defined in the [Classification Matrix](#classification-matrix) above (lines 27-37). The 9 variants naturally group into:

- **Bullish** (4): HL+HH (continuation), EL+HH (breakout), HL+EH (retest), LL+HH (reversal)
- **Neutral** (3): HL+LH (triangle), EL+EH (rectangle), LL+EH (volatile range)
- **Bearish** (2): EL+LH (lower-high), LL+LH (rally failure)

For detailed trading rules (entry signals, stop loss, targets), see [two-pivot-variants.md Market Regime Mapping](two-pivot-variants.md#market-regime-mapping) which extends these concepts to FD-binned granularity

## Implementation Notes

### Equality Classification

Use your **tolerance band ε** to classify EH and EL:

- **EH**: |H3 - H1| ≤ ε
- **EL**: |L2 - L0| ≤ ε

See [epsilon-tolerance.md](epsilon-tolerance-detail.md) for complete ε formula and defaults.

### Granular Sub-Classification

If you want finer discrimination within each variant, apply Freedman–Diaconis binning or add a third independent relation: **H₃ vs L₀**.

#### 27-Way Extension

Adding H₃ vs L₀ as a third dimension yields 3×3×3=27 sub-variants:

- **L₂ vs L₀**: {HL, EL, LL}
- **H₃ vs H₁**: {HH, EH, LH}
- **H₃ vs L₀**: {Above, Equal, Below}

**Example: HL + LH + H₃>L₀**

Pattern: L₂>L₀, H₃<H₁, H₃>L₀

```
Variant: HL + LH + H₃>L₀

Levels          │  L₀ │  H₁ │  L₂ │  H₃ │
────────────────┼─────┼─────┼─────┼─────┤
Above H₁        │     │     │     │     │
= H₁            │     │  •  │     │     │
Between H₁ & L₀ │     │     │  •  │  •  │
= L₀            │  •  │     │     │     │
Below L₀        │     │     │     │     │
```

**Interpretations for HL + LH:**

- **H₃ > L₀**: Triangle above initial support (most common)
- **H₃ ≈ L₀**: Triangle retracing to initial low (reversal risk)
- **H₃ < L₀**: Impossible (violates L₀<L₂<H₃<H₁ constraint for HL+LH)

**Note**: Some combinations are mathematically impossible due to constraints. Analysts often use "reclaims L₀" vs "fails to reclaim L₀" as a simpler binary distinction.

---

### HL+LH Granular Sub-Variants (Third-Band Breakdown)

For **HL+LH — Triangle Compression**, segmenting L₂ and H₃ into lower/mid/upper thirds of [L₀, H₁] reveals buyer-seller balance dynamics.

**Band Structure:**

- **Lower third**: [L₀, L₀ + ⅓(H₁−L₀)]
- **Mid third**: [L₀ + ⅓(H₁−L₀), L₀ + ⅔(H₁−L₀)]
- **Upper third**: [L₀ + ⅔(H₁−L₀), H₁]
- **Near H₁**: Within ε-band of H₁

#### 1) Shallow HL + Weak Bounce (H₃ near L₂)

**Pattern**: L₂ in lower third, H₃ in mid third
**Interpretation**: Compression with fading momentum; sellers gaining control

```
Levels   │ L₀ │ H₁ │ L₂ │ H₃ │
= H₁     │    │ •  │    │    │
Near H₁  │    │    │    │    │
Upper    │    │    │    │    │
Mid      │    │    │    │ •  │
Lower    │    │    │ •  │    │
= L₀     │ •  │    │    │    │
```

---

#### 2) Shallow HL + Mid Bounce

**Pattern**: L₂ in lower third, H₃ in upper third
**Interpretation**: Tightening triangle with mild bullish bias; consolidation before breakout

```
Levels   │ L₀ │ H₁ │ L₂ │ H₃ │
= H₁     │    │ •  │    │    │
Near H₁  │    │    │    │    │
Upper    │    │    │    │ •  │
Mid      │    │    │    │    │
Lower    │    │    │ •  │    │
= L₀     │ •  │    │    │    │
```

---

#### 3) Shallow HL + Strong Test (H₃ near H₁)

**Pattern**: L₂ in lower third, H₃ near H₁
**Interpretation**: Breakout pressure building; buyers testing resistance strongly

```
Levels   │ L₀ │ H₁ │ L₂ │ H₃ │
= H₁     │    │ •  │    │    │
Near H₁  │    │    │    │ •  │
Upper    │    │    │    │    │
Mid      │    │    │    │    │
Lower    │    │    │ •  │    │
= L₀     │ •  │    │    │    │
```

---

#### 4) Deep HL + Weak Bounce (L₂ high, H₃ just above)

**Pattern**: L₂ in upper third, H₃ near H₁
**Interpretation**: Deep pullback with weak recovery; triangle apex forming

```
Levels   │ L₀ │ H₁ │ L₂ │ H₃ │
= H₁     │    │ •  │    │    │
Near H₁  │    │    │    │ •  │
Upper    │    │    │ •  │    │
Mid      │    │    │    │    │
Lower    │    │    │    │    │
= L₀     │ •  │    │    │    │
```

---

#### 5) Deep HL + Mid Bounce

**Pattern**: L₂ in upper third, H₃ in upper third
**Interpretation**: Continuation drift; both L₂ and H₃ drifting higher in tight range

```
Levels   │ L₀ │ H₁ │ L₂ │ H₃ │
= H₁     │    │ •  │    │    │
Near H₁  │    │    │    │    │
Upper    │    │    │ •  │ •  │
Mid      │    │    │    │    │
Lower    │    │    │    │    │
= L₀     │ •  │    │    │    │
```

---

#### 6) Deep HL + Strong Test

**Pattern**: L₂ in upper third, H₃ near H₁
**Interpretation**: Extreme compression; apex reached; breakout imminent

```
Levels   │ L₀ │ H₁ │ L₂ │ H₃ │
= H₁     │    │ •  │    │    │
Near H₁  │    │    │    │ •  │
Upper    │    │    │ •  │    │
Mid      │    │    │    │    │
Lower    │    │    │    │    │
= L₀     │ •  │    │    │    │
```

---

**Implementation Note**: Use your ε-band for "Near H₁" edge detection. Thirds can be replaced with Freedman–Diaconis bins on real data for more precise demarcation.

### Market Regime Assignment

Each variant receives a regime label for downstream analysis:

- **Trend Continuation**: HL+HH, LL+LH
- **Range Consolidation**: HL+LH, EL+EH, EL+EH, LL+EH
- **Bullish Transition**: EL+HH, HL+EH
- **Bearish Transition**: EL+LH
- **Reversal**: LL+HH

## Temporal Dependencies

Consider tracking:

- **Duration up** (L0→H1 time): Fast impulse vs gradual accumulation
- **Duration down** (H1→L2 time): Quick pullback vs lengthy consolidation
- **Duration final up** (L2→H3 time): Weak bounce vs strong recovery

These temporal features enhance pattern prediction when combined with the 9-variant classification.

## Next Steps

1. **Implement**: Compute all 9 variants on rolling EURUSD data
2. **Backtest**: Analyze returns per variant across multiple timeframes
3. **Granularize**: Apply FD binning for sub-variant analysis (see [two-pivot-variants.md](two-pivot-variants.md))
4. **Extend**: Combine with volatility, spreads, and trend context
5. **Model**: Use 9-variant labels as features for ML regime classifiers

---

**Reference**: Mathematically complete; no variants missing.
**Constraints**: All patterns satisfy L0 < H1, L2 < H1, H3 > L2.
