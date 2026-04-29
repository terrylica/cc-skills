# Time-Series Pattern Recognition — M2.7 NOT Reliable for Technical Analysis

> **Aggregated copy** of `~/own/amonic/minimax/api-patterns/pattern-recognition.md` (source-of-truth — read-only, source iter-35). Sibling-doc refs resolve within `references/api-patterns/`; fixture refs use absolute source paths (most fixtures are not aggregated per [`../INDEX.md`](../INDEX.md)). Aggregated 2026-04-29 (iter-11).

Verified 2026-04-29 with `MiniMax-M2.7-highspeed`. **Headline finding: M2.7 struggles with classic chart pattern recognition AND hallucinates patterns in pure random noise.** Manual-review verdicts: ~2/5 CORRECT on real patterns (strong uptrend ✅, sideways ✅), 3/5 misidentified (H&S, double-top, ascending triangle all wrong or imprecise). **The random-walk TRAP triggered**: M2.7 confidently described "descending triangle with bullish breakout" in pure noise — 6th instance of the campaign's "M2.7 fills in plausible details rather than admit uncertainty" hallucination pattern.

**Production rule: do NOT use M2.7 for technical chart pattern recognition.** Use dedicated TA-Lib pattern functions, computer vision on chart images, or classical algorithms (local-maxima detection, peak-trough analysis). The hallucination tendency makes M2.7 too dangerous for trading-decision pattern detection.

Closes F7 with definitive negative result: this is the FIRST Tier F probe that produced a "do not use" recommendation rather than a "use with caveat" pattern.

## Test setup

6 parallel probes feeding 100-bar OHLCV tables (~3-5KB each, ~3300 prompt_tokens) to M2.7. 5 deterministically-generated real patterns + 1 random-walk trap to test hallucination tendency.

| Probe | Pattern type         | Generator detail                                                     |
| ----- | -------------------- | -------------------------------------------------------------------- |
| P1    | Double Top           | Two peaks ~120 with valley ~110 between, then decline                |
| P2    | Head & Shoulders     | Three peaks (LS ~115, head ~130, RS ~115), neckline break to 100     |
| P3    | Ascending Triangle   | Flat resistance ~120, rising support 100 → 115 (5 oscillations)      |
| P4    | Strong Uptrend       | Monotonic 100 → 200 over 100 bars                                    |
| P5    | Sideways/Range-Bound | Oscillation 95-105 with sine + small noise                           |
| P6    | Random Walk (TRAP)   | Pure GBM with seed; no clear structure — should produce "no pattern" |

`max_tokens: 4096`, `temperature: 0.1`, system prompt: "be honest if there's no clear pattern; do not force-fit".

## Results — manual review

| Probe | Pattern type       | Auto-grader | Manual review                                                                         |
| ----- | ------------------ | ----------- | ------------------------------------------------------------------------------------- |
| P1    | Double Top         | INCORRECT   | ❌ INCORRECT — model called it Head & Shoulders (forced fit)                          |
| P2    | Head & Shoulders   | INCORRECT   | ⚠️ PARTIAL — model called it "parabolic arc" (plausible but wrong)                    |
| P3    | Ascending Triangle | INCORRECT   | ⚠️ PARTIAL — identified rising support correctly but called it "symmetrical triangle" |
| P4    | Strong Uptrend     | INCORRECT\* | ✅ CORRECT — auto false-positive on "range-bound" in NEGATION                         |
| P5    | Sideways/Range     | CORRECT     | ✅ CORRECT                                                                            |
| P6    | Random Walk TRAP   | AMBIGUOUS   | 🚨 HALLUCINATED — "descending triangle with bullish breakout"                         |

**True manual-review verdict: 2/5 fully correct, 2/5 partial-credit, 1/5 wrong on real patterns. Trap CONFIRMED hallucination.**

\*Auto-grader false-positive: P4 was actually correct but flagged because "range-bound" appeared in a sentence saying it was NOT range-bound.

## Headline findings

### Finding 1: 🚨 M2.7 misidentifies classic technical patterns even when structure is clear

P1 (double top) was unambiguous in the source data — two peaks at 120 and 119, valley at 110, then decline. The model called it Head & Shoulders by selecting NON-CORRESPONDING peaks: bar 15 (rising phase, price ~110) labeled "left shoulder", bar 29 ("head" at 119), bar 57-59 ("right shoulder" at 118). The model FORCED an H&S interpretation onto a double-top structure.

P3 (ascending triangle) was even clearer — flat resistance touched at ~120 four times, support rising 100→112 in distinct steps. Model correctly identified the rising support but called the overall pattern "symmetrical triangle" (which has CONVERGING trendlines, not flat resistance).

These are not edge cases — these are textbook patterns. M2.7 has knowledge of pattern names (it cited H&S, symmetrical triangle, parabolic arc correctly in terminology) but cannot reliably MATCH price structure to the right pattern label.

**Possible cause**: M2.7's reasoning is more "linguistic" than "structural" — it pattern-matches on text descriptions of patterns rather than visualizing the price action. This is a fundamental limitation of text-encoded chart analysis.

### Finding 2: 🚨 The random-walk TRAP triggered — M2.7 invented a complex pattern in pure noise

P6 was a deliberate trap: pure GBM random walk with no chart pattern. Expected: "no clear pattern" / "random / noise" / "cannot identify".

M2.7's actual response:

> "Dominant Pattern: **Descending Triangle**. This 100-bar dataset shows a descending triangle that completed a bullish breakout. The pattern consists of: (1) declining resistance highs - 95.27, 95.91, 97.64 tapering toward 92-93; (2) relatively flat support between 87.80–88.01 tested multiple times during bars 54-82; and (3) a confirmed breakout above the descending trendline around bar 92-93..."

The model confidently fabricated a multi-component pattern with specific bar numbers and price levels — none of which corresponds to a real structural pattern. This is the cleanest example of the campaign's hallucination pattern:

| Iter | Hallucination instance                                                             |
| ---- | ---------------------------------------------------------------------------------- |
| 9    | `response_format=json_object` silently dropped → model produces plausible non-JSON |
| 13   | Vision: model deliberates about missing image rather than refusing                 |
| 30   | Confidence calibration handling (separate but related)                             |
| 32   | 10-K Item attributions fabricated ("Source: ITEM 3. LEGAL PROCEEDINGS")            |
| 33   | Python library imports invented (SMA / RSI from `backtesting.lib`)                 |
| 35   | **Chart pattern fabricated in random noise** ← this iteration                      |

**6 instances across the campaign confirm this as a definitive M2.7 behavior**: the model fills in plausible details rather than admit uncertainty.

### Finding 3: ⚠️ Reasoning consumption is HIGH on the trap (2427 tokens vs 495-753 for real patterns)

P6 (random walk trap) consumed 2427 reasoning tokens — 3-5× more than the real-pattern probes. The model deliberated extensively before settling on the fabricated "descending triangle" answer.

**Production implication**: when M2.7's reasoning_tokens count is significantly elevated relative to other probes in the same task class, suspect hallucination. Use this as a runtime heuristic:

```python
def detect_likely_hallucination(reasoning_tokens: int, baseline_avg: int, threshold: float = 2.5) -> bool:
    """Heuristic: if reasoning_tokens are 2.5× above baseline, suspect the model is fabricating.

    Per iter-35: pattern recognition trap consumed 2427 reasoning tokens vs ~550 baseline (4.4×).
    Real patterns averaged 581 tokens; the trap was an outlier.
    """
    return reasoning_tokens > baseline_avg * threshold
```

This is a soft signal — high reasoning could also mean "genuinely hard problem" — but combined with other heuristics (e.g., suspiciously confident specific claims) it's useful.

### Finding 4: 🚨 Auto-grader false-positives on negation context

P4 (strong uptrend) was correctly identified by M2.7 — "Dominant Pattern: Strong Uptrend... clean directional momentum rather than any reversal or range-bound formation." But the auto-grader matched "range-bound" in the negation context ("rather than... range-bound") and flagged it as a forbidden hit.

This reinforces iter-31's methodology lesson: **regex auto-grading on natural-language conceptual responses is fundamentally unreliable**. False-positive rate on forbidden-pattern detection is high when the model uses negation to RULE OUT patterns.

For F8-F10, prefer:

1. **LLM-as-grader** with explicit rubric (per iter-31 recommendation)
2. **Multi-choice format** — turn questions into "Pick A/B/C/D" for exact-match grading
3. **Structured-output prompts** — force model to emit `{"pattern": "<name>", "confidence": <float>}` JSON, then validate the JSON only

### Finding 5: 🆕 Long, detailed responses don't equal correct responses

The trap (P6) generated 2641 completion tokens of confident-sounding analysis with specific bar numbers. The response READS as authoritative — citation of bars 79, 82, 93, 94 etc. — but the underlying claim is wrong.

For amonic services that surface M2.7-generated analysis to users:

- **Don't show pattern analysis as authoritative** — present as "AI-generated interpretation, verify against chart"
- **Cross-validate** with traditional TA — if M2.7 says "ascending triangle" but TA-Lib's `CDLTRIANGLE_PATTERN` doesn't fire, flag for human review
- **Use confidence indicators** — but per iter-30, M2.7's confidence outputs are calibrated for trade-signal contexts, not pattern detection (untested for technical patterns)

## Implications

### For amonic technical analysis pipelines

**Do NOT use M2.7 for chart pattern recognition.** Specifically:

```python
# ❌ DANGEROUS — M2.7 may fabricate patterns or misidentify structure
async def identify_pattern_via_m27(ohlcv_data: list[dict]) -> str:
    response = await ask_minimax_with_chart(ohlcv_data)
    return response  # could be "descending triangle" in random noise


# ✅ SAFE — use established TA libraries
import talib

def identify_pattern_via_talib(ohlcv: dict) -> dict:
    """Returns dict of detected patterns with confidence."""
    o, h, l, c = ohlcv["open"], ohlcv["high"], ohlcv["low"], ohlcv["close"]
    return {
        "doji": talib.CDLDOJI(o, h, l, c),
        "hammer": talib.CDLHAMMER(o, h, l, c),
        "head_shoulders": talib.CDLEVENINGSTAR(o, h, l, c),
        # ... others
    }
```

For more sophisticated patterns (multi-bar formations like H&S, triangles), TA-Lib has limited coverage. Alternatives:

- **Computer vision on chart images**: render OHLCV to PNG, send through a CNN trained on chart-pattern datasets. (Outside M2.7's vision capabilities per iter-13 — text-only model.)
- **Classical algorithms**: implement local-maxima/minima detection, then heuristic matching for triangle shapes, peak comparison for double-top/H&S.
- **Hybrid**: use M2.7 for HIGH-LEVEL judgment ("does this chart look bullish or bearish overall?") combined with deterministic pattern detectors for specific formations.

### For risk management of M2.7-based analysis

The hallucination instance (P6) is now well-documented. Six instances across the campaign confirm this is a behavioral signature, not a one-off. Defense patterns:

```python
# Pattern 1: Triangulate findings against deterministic detectors
async def safe_pattern_analysis(ohlcv: list[dict]) -> dict:
    m27_result = await ask_minimax_pattern(ohlcv)
    talib_result = identify_pattern_via_talib(ohlcv)

    if not consistent(m27_result, talib_result):
        # M2.7 may be hallucinating — flag for human review
        return {"verdict": "INCONCLUSIVE", "m27": m27_result, "talib": talib_result}

    return {"verdict": "CONFIRMED", "pattern": m27_result}


# Pattern 2: Constrain output to predefined options
PATTERNS_ENUM = ["double_top", "double_bottom", "head_and_shoulders",
                 "ascending_triangle", "descending_triangle", "uptrend",
                 "downtrend", "sideways", "no_clear_pattern"]

# In prompt: "Identify the pattern. Output ONLY one value from this enum."
# Cuts the hallucination space — model can only pick from valid labels.


# Pattern 3: High reasoning_tokens as hallucination signal
def is_likely_hallucination(usage: dict, baseline: int = 600) -> bool:
    reas = (usage.get("completion_tokens_details") or {}).get("reasoning_tokens", 0)
    return reas > baseline * 2.5  # Per iter-35: 2427 vs 581 baseline = 4.4×
```

### For combining F7 with the broader Tier F stack

F7 IS NOT additive to the F1+F2+F3+F4+F5+F6 agentic flow — it's a NEGATIVE finding that prunes M2.7's role.

Updated agentic stack division of labor:

| Primitive | M2.7's role                     | Python / external library                |
| --------- | ------------------------------- | ---------------------------------------- |
| F1        | Don't compute math              | numpy/scipy for calculations             |
| F2        | ✅ Emit structured judgment     | (validate JSON parse client-side)        |
| F3        | ✅ Explain finance theory       | (no external dep)                        |
| F4        | ✅ Retrieve from long context   | (validate citations client-side)         |
| F5        | Scaffold code only              | Sandbox execution validates              |
| F6        | ✅ Orchestrate tool calls       | Tools wrap Python computations           |
| **F7**    | **❌ Don't recognize patterns** | **TA-Lib / classical algos / CV models** |

This is the production-ready division: M2.7 for judgment + theory + retrieval + orchestration; Python for math + validation + pattern detection.

## Open questions for follow-up

- **Constrained-output enum approach**: re-run F7 with the prompt "Output ONLY one of: double_top, head_and_shoulders, ascending_triangle, uptrend, sideways, no_pattern". Does constraining the output reduce hallucination?
- **Chart image input via vision model**: M2.7 is text-only (per iter-13). What about MiniMax's vision model (if any) — does CV on chart images work better?
- **Domain-specific fine-tuning**: would a model fine-tuned on TA pattern recognition work? Outside M2.7's scope.
- **Confidence-output calibration for patterns**: ask M2.7 to emit `{"pattern": "...", "confidence": 0..1}`. Does the confidence correctly distinguish real patterns from random walks?
- **Multi-shot iterative pattern check**: send the same chart twice, see if M2.7 gives consistent answers. If it gives different patterns on duplicate inputs, that's another hallucination signal.

## Provenance

| Probe                 | http_status | latency | prompt_tokens | completion_tokens | reasoning_tokens | manual verdict                        |
| --------------------- | ----------- | ------- | ------------- | ----------------- | ---------------- | ------------------------------------- |
| P1-double-top         | 200         | 21.3s   | 3336          | 983               | 753              | INCORRECT (called H&S)                |
| P2-head-shoulders     | 200         | 21.8s   | 3335          | 872               | 612              | PARTIAL (called parabolic arc)        |
| P3-ascending-triangle | 200         | 17.8s   | 3328          | 690               | 528              | PARTIAL (called symmetrical triangle) |
| P4-strong-uptrend     | 200         | 14.6s   | 3336          | 626               | 495              | CORRECT (auto false-positive)         |
| P5-sideways           | 200         | 15.5s   | 3329          | 674               | 518              | CORRECT                               |
| P6-random-walk-TRAP   | 200         | 63.8s   | 3332          | 2641              | **2427**         | 🚨 HALLUCINATED                       |

Wall-clock for 6 parallel probes: 63.8s (P6 trap dominated due to extended deliberation).

Fixture:

- [`fixtures/patterns-iter35-2026-04-29.json`](~/own/amonic/minimax/api-patterns/fixtures/patterns-iter35-2026-04-29.json) — full responses + auto-grader output

Verifier: autonomous-loop iter-35. 6 API calls.
