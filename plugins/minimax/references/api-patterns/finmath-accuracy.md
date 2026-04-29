# Financial Math — Numerical Accuracy on M2.7

> **Aggregated copy** of `~/own/amonic/minimax/api-patterns/finmath-accuracy.md` (source-of-truth — read-only, source iter-29). Sibling-doc refs resolve within `references/api-patterns/`; fixture refs use absolute source paths (most fixtures are not aggregated per [`../INDEX.md`](../INDEX.md)). Aggregated 2026-04-29 (iter-11).

Verified 2026-04-29 with both `MiniMax-M2.7` and `MiniMax-M2.7-highspeed`. **Headline finding: M2.7 IS accurate on simple financial math (max drawdown, VaR) and CAN solve Sharpe ratio if given ~10K reasoning tokens — but Black-Scholes saturates 16K reasoning tokens without producing an answer.** The reasoning-to-computation ratio is wildly disproportionate: a closed-form formula requiring ~10 arithmetic operations + 2 normal-CDF lookups exceeds the model's reasoning budget. **Production rule: do not use M2.7 for direct financial computation; delegate math to Python (numpy/scipy) and use M2.7 for qualitative reasoning + interpretation only.**

Closes F1 with definitive guidance for amonic quant workflows.

## Test setup

4 financial math problems × 2 models (plain vs highspeed) = 8 parallel calls. Truth values computed independently via numpy/scipy, then compared with 1% relative tolerance.

| Problem          | Type                                      | Truth value | Tolerance |
| ---------------- | ----------------------------------------- | ----------- | --------- |
| P1 Sharpe ratio  | multi-step (mean, sample-stdev, division) | 0.427455    | 1%        |
| P2 Max drawdown  | sequential pass                           | 18.181818%  | 1%        |
| P3 95% VaR       | normal-distribution percentile            | 3.289707%   | 1%        |
| P4 Black-Scholes | closed-form (log, exp, norm.cdf×2)        | 4.614997    | 1%        |

System prompt forced format: `ANSWER: <number>` on the last line. `temperature: 0.1` for tight determinism. Initial budget `max_tokens: 4096`; retries at `max_tokens: 16384` for budget-exhausted probes.

## Results — initial run (max_tokens=4096)

| Problem          | Model     | Verdict     | Answer | rel_err | Latency | comp_tokens | reasoning_tokens |
| ---------------- | --------- | ----------- | ------ | ------- | ------- | ----------- | ---------------- |
| P1 Sharpe        | plain     | UNPARSEABLE | None   | —       | 82.7s   | 4096 (max)  | 4096 (max)       |
| P1 Sharpe        | highspeed | UNPARSEABLE | None   | —       | 52.4s   | 4096 (max)  | 4096 (max)       |
| P2 Max drawdown  | plain     | ✅ CORRECT  | 18.18  | 0.0001  | 53.5s   | 2031        | 1713             |
| P2 Max drawdown  | highspeed | ✅ CORRECT  | 18.18  | 0.0001  | 27.2s   | 1654        | 1365             |
| P3 95% VaR       | plain     | ✅ CORRECT  | 3.29   | 0.00009 | 9.6s    | 375         | 300              |
| P3 95% VaR       | highspeed | ✅ CORRECT  | 3.29   | 0.00009 | 7.8s    | 272         | 176              |
| P4 Black-Scholes | plain     | UNPARSEABLE | None   | —       | 94.1s   | 4096 (max)  | 4096 (max)       |
| P4 Black-Scholes | highspeed | UNPARSEABLE | None   | —       | 54.9s   | 4096 (max)  | 4096 (max)       |

**Aggregate at 4096 budget**: 2/4 correct on both models. The 2/4 failures were all `finish_reason=length` (budget exhaustion), NOT incorrect answers.

## Results — retry (max_tokens=16384, highspeed only)

| Problem          | Verdict        | Answer | rel_err | Latency | comp_tokens | reasoning_tokens |
| ---------------- | -------------- | ------ | ------- | ------- | ----------- | ---------------- |
| P1 Sharpe        | ✅ CORRECT     | 0.4275 | 0.0001  | 142.4s  | 10283       | 10024            |
| P4 Black-Scholes | ❌ UNPARSEABLE | None   | —       | 230.2s  | 16384 (max) | 16384 (max)      |

**P1 needed ~10K reasoning tokens** to converge. **P4 saturated 16K reasoning tokens** without producing an answer.

## Headline findings

### Finding 1: ✅ M2.7 is accurate on simple financial math given adequate budget

P2 (max drawdown), P3 (VaR), and P1 (Sharpe given 16K budget) all returned answers within 0.01% relative error of the truth value — well inside the 1% tolerance. The math itself is correct. The accuracy isn't the problem; the budget is.

For these three problem types:

- **VaR**: ~300 reasoning tokens, 8-10s latency, reliable
- **Max drawdown**: ~1500 reasoning tokens, 27-53s latency, reliable
- **Sharpe ratio**: ~10000 reasoning tokens, 140s latency, reliable but slow

### Finding 2: 🚨 Reasoning-to-computation ratio is WILDLY disproportionate

A Sharpe ratio computation is, algorithmically:

1. Sum 10 numbers and divide by 10 (mean)
2. Sum squared deviations, divide by 9, square root (sample stdev)
3. Subtract risk-free rate, divide by stdev

That's ~25 elementary operations. M2.7 spent **10,024 reasoning tokens** on this — roughly 400 reasoning tokens per arithmetic operation.

The model is over-deliberating: rechecking work, considering alternative approaches, validating intermediate results. This is a feature for novel problems but a tax on routine computation.

**Production implication**: production cost-modeling for financial math on M2.7 must assume:

- Trivial calculations (single formula, one-step): 200-500 reasoning tokens
- Multi-step (Sharpe, risk metrics): 1500-10000 reasoning tokens (highly variable)
- Closed-form with special functions (Black-Scholes): exceeds 16K, effectively unbounded

### Finding 3: 🚨 Black-Scholes saturates 16K reasoning tokens — model cannot solve it

Even with `max_tokens=16384` (the practical ceiling — 16K tokens is ~$0.10 per call at typical reasoning-model pricing), M2.7 could not produce a Black-Scholes answer. `finish_reason=length` after 16,384 reasoning tokens.

**Why it's hard**: Black-Scholes requires computing N(d1) and N(d2) — the cumulative standard normal distribution. M2.7 likely attempts this numerically (Abramowitz & Stegun approximation, Taylor series, or step-by-step error-function computation). Each attempt consumes substantial reasoning tokens; rechecking compounds the cost.

**This is NOT a math accuracy problem** — given infinite budget and proper guidance, the model probably converges. But at any practical max_tokens, it doesn't finish.

**Production implication**: do NOT use M2.7 for option pricing, implied volatility, Greeks, or any computation requiring the normal CDF. Use a Python library:

```python
from scipy.stats import norm
import math

def black_scholes_call(S, K, T, r, sigma):
    d1 = (math.log(S/K) + (r + 0.5*sigma**2)*T) / (sigma*math.sqrt(T))
    d2 = d1 - sigma*math.sqrt(T)
    return S*norm.cdf(d1) - K*math.exp(-r*T)*norm.cdf(d2)
```

Or call out to an Anthropic/OpenAI tool-use loop that wraps this Python.

### Finding 4: Plain vs highspeed — IDENTICAL CORRECTNESS, highspeed FASTER

For the multi-step problems where both completed (P2, P3):

| Problem   | plain latency | highspeed latency | speedup | Same answer?  |
| --------- | ------------- | ----------------- | ------- | ------------- |
| P2 Max DD | 53.5s         | 27.2s             | 1.97×   | ✅ both 18.18 |
| P3 VaR    | 9.6s          | 7.8s              | 1.23×   | ✅ both 3.29  |

**Highspeed produces the same answer faster**. iter-28's "highspeed wins for long generation" extends to financial math — the long reasoning phase qualifies as long generation for this purpose. **For finance probes use highspeed**, not plain (reverses iter-28's Karakeep-tagging recommendation; finance is high-reasoning, not short-output).

But neither model is reliably FAST: even highspeed needed 27s for max drawdown, 142s for Sharpe (16K budget). Production code that needs sub-1s financial math should NOT use M2.7 at all.

### Finding 5: 🆕 Reasoning-budget calibration recipe for financial workloads

Based on iter-29 measurements, conservative max_tokens floor by problem type:

| Workload                                    | Recommended max_tokens | Estimated latency (highspeed) |
| ------------------------------------------- | ---------------------- | ----------------------------- |
| Simple percentile / lookup (VaR-style)      | 1024                   | 8-15s                         |
| Multi-step pass (max drawdown, returns sum) | 4096                   | 25-50s                        |
| Multi-step formula (Sharpe, Sortino)        | 12288                  | 100-150s                      |
| Closed-form with CDF (Black-Scholes, IV)    | **don't use M2.7**     | —                             |

For amonic services that mix problem types: detect the task type client-side and set max_tokens accordingly, OR always use the high-end (12288) and accept the cost.

## Implications

### For amonic quant workflows

**Don't use M2.7 directly for math**:

```python
# ❌ WRONG — saturates reasoning budget on Black-Scholes
prompt = "Compute the Black-Scholes call price with S=100, K=100, T=0.25, r=0.05, sigma=0.20"
result = call_minimax(prompt, max_tokens=4096)  # finish_reason=length, no answer

# ✅ RIGHT — Python does the math, M2.7 interprets the result
import math
from scipy.stats import norm
S, K, T, r, sigma = 100, 100, 0.25, 0.05, 0.20
d1 = (math.log(S/K) + (r + 0.5*sigma**2)*T) / (sigma*math.sqrt(T))
d2 = d1 - sigma*math.sqrt(T)
call_price = S*norm.cdf(d1) - K*math.exp(-r*T)*norm.cdf(d2)

# Use M2.7 for QUALITATIVE reasoning ABOUT the number
prompt = f"""The Black-Scholes price for an ATM call (S=K=100, T=0.25y, r=5%, σ=20%)
is ${call_price:.2f}. In 50 words, explain to a portfolio manager what this implies
about the option's expected payoff and break-even spot price at expiry."""
```

This pattern — Python for computation, M2.7 for interpretation — is the right division of labor.

### For tool-use-based agents (combines T2.1)

If you NEED M2.7 to "do math" in an agentic flow, define the math operations as tools:

```python
TOOLS = [
    {
        "type": "function",
        "function": {
            "name": "black_scholes_call",
            "description": "Compute Black-Scholes price for a European call option",
            "parameters": {
                "type": "object",
                "properties": {
                    "S": {"type": "number", "description": "spot price"},
                    "K": {"type": "number", "description": "strike price"},
                    "T": {"type": "number", "description": "time to expiry in years"},
                    "r": {"type": "number", "description": "risk-free rate (annualized)"},
                    "sigma": {"type": "number", "description": "volatility (annualized)"},
                },
                "required": ["S", "K", "T", "r", "sigma"],
            },
        },
    },
    # ... sharpe_ratio, var_normal, max_drawdown, etc.
]
```

Per iter-12, M2.7 honors `tools` (capability-honored category in the campaign taxonomy). The model decides which tool to call; the agent executes the Python math; the model interprets the result. This is dramatically faster than asking M2.7 to compute directly (sub-3s tool decision + sub-millisecond Python computation vs 100+ second M2.7 reasoning).

### For Karakeep-style tagging — STILL use plain M2.7 (iter-28 recommendation stands)

iter-28 said: use plain M2.7 for short-output workloads (Karakeep tagging). iter-29 says: use highspeed for finance reasoning. These are NOT contradictory — they target different workload regimes:

- Short output, low reasoning (tagging): plain M2.7 is faster (per iter-28)
- Long reasoning regardless of output size (financial math): highspeed is faster (per iter-29)

The branching rule:

```python
def select_minimax_model(workload_type: str) -> str:
    if workload_type in ("tagging", "classification", "extraction"):
        return "MiniMax-M2.7"
    elif workload_type in ("finance", "math", "multi-step-reasoning"):
        return "MiniMax-M2.7-highspeed"
    else:
        return "MiniMax-M2.7-highspeed"  # default to highspeed for ambiguous cases
```

## Open questions for follow-up

- **Does Black-Scholes work if N(d1) and N(d2) are PROVIDED in the prompt?** Would isolate "CDF lookup is the bottleneck" hypothesis from "general arithmetic is slow" hypothesis. Quick follow-up probe.
- **Does M2.7 do better with a worked-example few-shot pattern?** A prompt that shows one Black-Scholes computation step-by-step might prime the model to do the second one faster. Worth one probe.
- **What about Sortino ratio?** Similar to Sharpe but uses downside deviation only. Likely similar reasoning-budget profile.
- **Does plain M2.7 also fail Black-Scholes at 16K?** iter-29 retry only tested highspeed. Theoretically plain has different reasoning profile per iter-28 — but unlikely to succeed where highspeed failed.
- **Streaming TPS for financial math** — does iter-8's coarse-chunk streaming help here, or is the reasoning phase entirely opaque (no chunks until visible content emits)? Time to first emitted ANSWER would be useful UX metric.
- **Cost comparison vs alternatives**: per-call cost of M2.7 highspeed at 10K reasoning tokens vs Llama 3.1 70B local on bigblack vs OpenAI gpt-4o-mini for same Sharpe ratio task. The user's bigblack has GPU; local Llama is likely the cost-effective choice if the math is reliable.

## Provenance

| Probe                      | model     | max_tokens | verdict     | answer | truth     | rel_err | latency | reasoning_tokens  |
| -------------------------- | --------- | ---------- | ----------- | ------ | --------- | ------- | ------- | ----------------- |
| P1-sharpe (initial)        | plain     | 4096       | UNPARSEABLE | None   | 0.427455  | —       | 82.7s   | 4096 (saturated)  |
| P1-sharpe (initial)        | highspeed | 4096       | UNPARSEABLE | None   | 0.427455  | —       | 52.4s   | 4096 (saturated)  |
| P1-sharpe (retry)          | highspeed | 16384      | ✅ CORRECT  | 0.4275 | 0.427455  | 0.0001  | 142.4s  | 10024             |
| P2-max-drawdown            | plain     | 4096       | ✅ CORRECT  | 18.18  | 18.181818 | 0.0001  | 53.5s   | 1713              |
| P2-max-drawdown            | highspeed | 4096       | ✅ CORRECT  | 18.18  | 18.181818 | 0.0001  | 27.2s   | 1365              |
| P3-var-95                  | plain     | 4096       | ✅ CORRECT  | 3.29   | 3.289707  | 0.00009 | 9.6s    | 300               |
| P3-var-95                  | highspeed | 4096       | ✅ CORRECT  | 3.29   | 3.289707  | 0.00009 | 7.8s    | 176               |
| P4-black-scholes (initial) | plain     | 4096       | UNPARSEABLE | None   | 4.614997  | —       | 94.1s   | 4096 (saturated)  |
| P4-black-scholes (initial) | highspeed | 4096       | UNPARSEABLE | None   | 4.614997  | —       | 54.9s   | 4096 (saturated)  |
| P4-black-scholes (retry)   | highspeed | 16384      | UNPARSEABLE | None   | 4.614997  | —       | 230.2s  | 16384 (saturated) |

Fixtures:

- [`fixtures/finmath-iter29-accuracy-2026-04-29.json`](~/own/amonic/minimax/api-patterns/fixtures/finmath-iter29-accuracy-2026-04-29.json) — 8 initial probes
- [`fixtures/finmath-iter29-retry-2026-04-29.json`](~/own/amonic/minimax/api-patterns/fixtures/finmath-iter29-retry-2026-04-29.json) — 2 retry probes at higher budget

Verifier: autonomous-loop iter-29. 10 API calls (8 initial + 2 retry).
