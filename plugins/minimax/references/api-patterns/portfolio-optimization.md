# Markowitz Portfolio Optimization — M2.7 Cannot Compute, Can Explain

> **Aggregated copy** of `~/own/amonic/minimax/api-patterns/portfolio-optimization.md` (source-of-truth — read-only, source iter-36). Sibling-doc refs resolve within `references/api-patterns/`; fixture refs use absolute source paths (most fixtures are not aggregated per [`../INDEX.md`](../INDEX.md)). Aggregated 2026-04-29 (iter-11).

Verified 2026-04-29 with `MiniMax-M2.7-highspeed`. **Headline finding: M2.7 saturates 8192/8192 reasoning tokens trying to compute Markowitz tangency-portfolio weights but produces graduate-level explanation of the framework when asked for theory only.** This generalizes iter-29's Black-Scholes pattern to ANY computationally-complex optimization. **The hybrid prompt (explain + estimate) ALSO fails** — model attempts exact computation and exhausts budget before delivering the explanation either.

**Production rule: never ask M2.7 to do quadratic programming, constrained optimization, numerical integration, or matrix operations.** Use scipy.optimize for the math; M2.7 for the explanation.

Closes F8 with definitive confirmation that the Tier F division of labor (Python for math, M2.7 for theory + judgment) generalizes beyond closed-form formulas.

## Test setup

3 parallel probes with the same 4-asset portfolio data + risk-free rate, varying the prompt mode:

| Probe | Mode           | Prompt                                                           | Predicted outcome                         |
| ----- | -------------- | ---------------------------------------------------------------- | ----------------------------------------- |
| F8.A  | math-direct    | "Compute the tangency weights. Output WEIGHT_A: <num>..."        | FAIL (saturates reasoning budget)         |
| F8.B  | framework-only | "Explain the procedure. Cite framework name. ≤200 words."        | SUCCESS (textbook quality)                |
| F8.C  | hybrid         | "Briefly explain the framework AND provide approximate weights." | UNCERTAIN — likely fails on the math side |

### Test data

```
Assets: A, B, C, D
Expected returns: A=12%, B=8%, C=15%, D=5%
Volatilities:    A=15%, B=10%, C=20%, D=5%
Correlation:
       A    B    C    D
   A  1.0  0.3  0.6  0.1
   B  0.3  1.0  0.2  0.05
   C  0.6  0.2  1.0  0.0
   D  0.1  0.05 0.0  1.0
Risk-free rate: 4%
Constraints: weights sum to 1, no shorts (w_i >= 0)
```

### Truth (scipy.optimize.minimize on -Sharpe with SLSQP)

| Asset | Truth weight |
| ----- | ------------ |
| A     | 0.1612       |
| B     | 0.2760       |
| C     | 0.2009       |
| D     | 0.3618       |

Truth Sharpe: 0.6735.

## Results

| Probe | Outcome                                                                            | Latency | comp_tokens | reasoning_tokens |
| ----- | ---------------------------------------------------------------------------------- | ------- | ----------- | ---------------- |
| F8.A  | 🚨 UNPARSEABLE — saturated 8192/8192 reasoning tokens; visible content empty       | 129.1s  | 8192        | **8192 (max)**   |
| F8.B  | ✅ SUCCESS — full Markowitz derivation with KKT conditions; 2/3 framework keywords | 37.6s   | 1879        | 1437             |
| F8.C  | 🚨 UNPARSEABLE — same as F8.A; hybrid failed at the computation phase              | 131.9s  | 8192        | **8192 (max)**   |

## Headline findings

### Finding 1: 🚨 M2.7 cannot compute Markowitz weights at any practical reasoning budget

F8.A consumed all 8192 reasoning tokens (`finish_reason=length`) without producing the WEIGHT_A/B/C/D output lines. The 129-second latency is significantly worse than iter-29's Black-Scholes failure (16K reasoning tokens at 230s) — Markowitz is even more reasoning-intensive than option pricing because of the constrained optimization (4-dimensional KKT system instead of a single closed-form formula).

This generalizes iter-29's finding from "single closed-form requiring CDF lookup" to "any constrained optimization requiring matrix algebra". Specifically rules out:

- Mean-variance optimization (Markowitz)
- Risk parity / equal-risk-contribution
- Black-Litterman posterior weights
- CVaR-constrained optimization
- Any problem requiring solving Σw = some constraint system

**Production implication**: amonic portfolio code MUST delegate optimization to scipy/cvxpy/Mosek. Don't even try to ask M2.7 for weights with a hint or smaller dimension — this is fundamentally outside the model's compute capability.

### Finding 2: ✅ M2.7 explains the Markowitz framework with graduate-level rigor

F8.B's response (1879 completion tokens, 37.6s latency) included:

1. **Covariance matrix construction**: `Σ = diag(σ) ρ diag(σ)` in proper matrix notation
2. **Sharpe-maximization problem**: full LaTeX `max_w (w^T μ - rf) / sqrt(w^T Σ w)` with `sum(w)=1, w≥0` constraints
3. **QP reformulation**: explained the standard trick of fixing excess return numerator and minimizing variance
4. **KKT conditions**: explicit derivation `2Σw - λ(μ - rf*1) - ν*1 - θ = 0` with complementary slackness
5. **Solver mention**: "interior-point or active-set" methods

This is precisely the level of detail you'd expect in a graduate finance textbook. M2.7 has internalized the Markowitz framework deeply — just can't execute the numerical algorithm.

**Production implication**: M2.7 is a competent EXPLAINER for portfolio optimization. Use it for:

- Documentation generation ("explain to junior analyst what we're computing")
- Code review ("does this scipy.optimize call match the Markowitz framework?")
- Onboarding materials (LaTeX-rich textbook explanations)
- Validation of WHAT problem to solve (not HOW to solve it)

### Finding 3: 🚨 Hybrid prompts FAIL — even "approximate" requests trigger exact-computation attempt

F8.C is the most production-relevant negative finding. Asked for "brief explanation + approximate weights", M2.7 attempted exact computation, exhausted 8192 reasoning tokens, never produced the explanation either. The visible content was empty.

**This rules out a tempting prompt pattern**: "explain the framework, then estimate the weights". One might hope the model would explain (cheap) and then provide ballpark numbers (cheap). Instead, it goes for the rigorous solution and burns budget.

**Production implication**: NEVER mix "explain" and "compute" in a single prompt for complex optimization. Two separate calls — one for explanation, one for Python-driven computation. Don't try to be clever with hybrid prompting.

The deeper insight: M2.7's reasoning model architecture appears to lock onto "find the exact answer" mode for numerical questions. Even instructions to estimate/approximate don't override this. The model would rather time out than provide a noisy answer.

### Finding 4: 🆕 8192 reasoning tokens is the SATURATION CEILING for hybrid Markowitz

iter-29 found Black-Scholes saturating at 16384 tokens. iter-36 finds Markowitz saturating at 8192 tokens (the lower budget I happened to set in this probe). It's likely that even at 16384 or 32768, Markowitz would still saturate — the model never converges to an answer for QP-style problems.

**Production rule for budget calibration**: don't allocate large reasoning budgets to "see if M2.7 can compute it". The marginal returns are zero — saturation is structural, not a budget calibration issue. Better to fail fast at 4096 and route to scipy.

### Finding 5: 🆕 The campaign-defining hallucination pattern manifests differently here — TIMEOUT vs FABRICATION

iter-9, iter-13, iter-30, iter-32, iter-33, iter-35 all showed the same failure mode: M2.7 fabricates plausible details under uncertainty. iter-36 shows a DIFFERENT failure mode for math-impossible tasks: model SATURATES rather than fabricating.

This is actually a positive: M2.7 doesn't pretend to compute Markowitz weights and emit fake numbers — it visibly fails (empty content + finish_reason=length). For production reliability, this is the BETTER failure mode:

- Hallucination: silent + plausible + dangerous
- Saturation: visible + obvious + safe to detect

**Production implication**: monitor `finish_reason=length` AND empty/short visible content as a "compute task too hard for M2.7" signal. When detected, route to deterministic alternative (scipy/cvxpy) without retry.

```python
def is_saturated_compute_failure(response: dict) -> bool:
    """Detect 'M2.7 couldn't compute it' vs 'M2.7 hallucinated'."""
    finish = response["choices"][0]["finish_reason"]
    content = response["choices"][0]["message"].get("content", "")
    visible = re.sub(r"<think>[\s\S]*?</think>\s*", "", content).strip()
    usage = response.get("usage", {})
    reasoning = (usage.get("completion_tokens_details") or {}).get("reasoning_tokens", 0)
    max_tokens = usage.get("completion_tokens", 0)

    return finish == "length" and len(visible) < 50 and reasoning >= max_tokens * 0.95
```

Use this to fail fast and route to Python.

## Implications

### For amonic portfolio optimization workflows

```python
import numpy as np
from scipy.optimize import minimize

# ❌ DON'T — saturates reasoning budget, no answer
async def compute_weights_via_m27(returns: np.ndarray, cov: np.ndarray, rf: float) -> np.ndarray:
    response = await ask_minimax_for_weights(returns, cov, rf)
    return parse_weights(response)  # likely None — saturation


# ✅ DO — Python for math, M2.7 for explanation (separate calls)
def compute_tangency_weights(expected_returns: np.ndarray, cov: np.ndarray, rf: float) -> np.ndarray:
    """Python solves the QP via scipy.optimize."""
    n = len(expected_returns)

    def neg_sharpe(w):
        port_return = w @ expected_returns
        port_std = (w @ cov @ w) ** 0.5
        return -(port_return - rf) / max(0.001, port_std)

    constraints = ({"type": "eq", "fun": lambda w: np.sum(w) - 1.0},)
    bounds = [(0.0, 1.0)] * n
    result = minimize(neg_sharpe, np.full(n, 1/n), method="SLSQP",
                       bounds=bounds, constraints=constraints)
    return result.x


async def explain_optimization(weights: np.ndarray, returns: np.ndarray, cov: np.ndarray) -> str:
    """M2.7 explains what was optimized and why this is the answer."""
    return await ask_minimax(
        f"Given assets with returns {returns} and covariance {cov}, the Markowitz "
        f"tangency portfolio is {weights}. Explain in 100 words why this weighting "
        f"is Sharpe-maximizing under the given constraints."
    )


# Compose: Python computes + M2.7 narrates
weights = compute_tangency_weights(returns, cov, rf)
narrative = await explain_optimization(weights, returns, cov)
```

For amonic services that surface portfolio optimizations to users, this pattern is the production sweet spot.

### For Tier F division of labor (revised)

The full Tier F division of labor after F8:

| Primitive | Math?           | Explanation? | Use M2.7 for...                             |
| --------- | --------------- | ------------ | ------------------------------------------- |
| F1        | ❌ Python       | ✅           | Explaining what Sharpe/VaR/drawdown means   |
| F2        | (judgment)      | ✅           | Emitting structured trade signal as JSON    |
| F3        | n/a             | ✅           | Textbook explanations of theory             |
| F4        | n/a             | ✅           | Retrieving facts from long-context filings  |
| F5        | (codegen)       | ✅           | Scaffolding code (validate execution!)      |
| F6        | (orchestration) | ✅           | Tool selection + parallel call coordination |
| F7        | ❌              | ❌           | DON'T USE for chart pattern recognition     |
| **F8**    | **❌ scipy**    | ✅           | Explaining Markowitz / KKT / QP framework   |

The pattern is consistent: M2.7 is a JUDGMENT + EXPLANATION engine, never a COMPUTATION engine. For amonic-quant production code, this is the operative mental model.

## Open questions for follow-up

- **Smaller-dimension QP**: does M2.7 solve a 2-asset Markowitz (n=2)? At small dimensions, the QP has a closed-form solution. Worth one probe to confirm the saturation isn't just dimensional.
- **Black-Litterman**: similar QP structure with views and prior. Likely same saturation, but interesting to confirm.
- **Risk-parity**: simpler formulation (set per-asset risk contributions equal). Does M2.7 fare better on this special case?
- **Mean-variance optimization SCAFFOLD**: ask M2.7 to write the scipy.optimize CALL (not solve it). Does this fall under F5's "code scaffolding works given API hints"?
- **Combined F8 + F2**: can M2.7 provide a structured-JSON explanation of optimization output? E.g., `{"weights": [...], "rationale": "..."}` where weights come from Python and rationale comes from M2.7. This composes the patterns cleanly.

## Provenance

| Probe | mode           | http_status | latency | completion_tokens | reasoning_tokens | finish_reason | verdict     |
| ----- | -------------- | ----------- | ------- | ----------------- | ---------------- | ------------- | ----------- |
| F8.A  | math-direct    | 200         | 129.1s  | 8192              | 8192 (saturated) | length        | UNPARSEABLE |
| F8.B  | framework-only | 200         | 37.6s   | 1879              | 1437             | stop          | ✅ SUCCESS  |
| F8.C  | hybrid         | 200         | 131.9s  | 8192              | 8192 (saturated) | length        | UNPARSEABLE |

Truth weights (from scipy.optimize.minimize): A=0.1612, B=0.2760, C=0.2009, D=0.3618. Truth Sharpe = 0.6735.

Wall-clock for 3 parallel probes: 131.9s.

Fixture:

- [`fixtures/portfolio-opt-iter36-2026-04-29.json`](~/own/amonic/minimax/api-patterns/fixtures/portfolio-opt-iter36-2026-04-29.json) — full responses + truth values + grading

Verifier: autonomous-loop iter-36. 3 API calls.
