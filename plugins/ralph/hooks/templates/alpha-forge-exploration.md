---
name: alpha_forge_exploration
description: Alpha Forge RSSI loop - OOS robustness + time series forecasting with reinforcement learning
phase: exploration
adr: 2025-12-20-ralph-rssi-eternal-loop
---

**ALPHA FORGE RSSI** - Iteration {{ iteration }}

You are optimizing a **quantitative trading research platform**.
Core mission: **OOS robustness** and **time series forecasting excellence**.

---

## LEARNING FROM HISTORY (Reinforcement)

This iteration builds on accumulated knowledge:

- **{{ accumulated_patterns|length }} learned patterns** from past sessions
- **{{ disabled_checks|length }} disabled ineffective checks** (waste of time)
- **{{ effective_checks|length }} prioritized effective checks** (high value)
- **{{ web_insights|length }} web-sourced insights** (SOTA discoveries)
- **{{ feature_ideas|length }} accumulated feature ideas** (to explore)

{% if metrics_history %}

### Recent Metrics (Learn from these)

| Run | Sharpe | CAGR | MaxDD | WFE |
| --- | ------ | ---- | ----- | --- |

{% for m in metrics_history[-5:] %}
| {{ m.identifier if m.identifier else loop.index }} | {{ "%.3f"|format(m.primary_metric) if m.primary_metric else "N/A" }} | {{ m.secondary_metrics.cagr if m.secondary_metrics else "N/A" }} | {{ m.secondary_metrics.maxdd if m.secondary_metrics else "N/A" }} | {{ m.secondary_metrics.wfe if m.secondary_metrics else "N/A" }} |
{% endfor %}

**Key insight**: What changed between runs? What improved/degraded?
{% endif %}

**BEFORE this iteration, READ these persistent artifacts**:

1. `research_log.md` - What was tried? What worked?
2. `ROADMAP.md` - What's the current priority?
3. `outputs/runs/` - Latest experiment results

---

## ALWAYS REFER TO ROADMAP

Before ANY work, check `ROADMAP.md` for current priorities:

- What Phase are we in?
- What are the P0/P1 items?
- Does this work align with stated goals?

**If work doesn't align with ROADMAP, DON'T DO IT.**

---

## FORBIDDEN BUSYWORK (NEVER do these)

These are explicitly BLOCKED - skip immediately if discovered:

- Linting/style fixes (ruff, pylint, flake8, mypy errors)
- Unused imports, import sorting, formatting
- Docstrings, READMEs, comments, documentation gaps
- Type hints, annotations
- TODO/FIXME scanning
- Test coverage hunting
- Security scans (gitleaks, bandit)
- Dependency updates, version bumps
- Git hygiene, commit message fixes
- Refactoring for "readability" or "DRY"
- CI/CD workflow tweaks

**These provide ZERO value toward OOS robustness or forecasting.**

---

## HIGH-VALUE WORK (Focus on these)

### OOS Robustness (Primary Goal)

- Walk-forward optimization improvements
- WFE (Walk-Forward Efficiency) enhancements
- Overfitting detection and prevention
- Regime change detection
- Cross-validation strategies
- Generalization testing

### Time Series Forecasting

- Model architecture improvements (LSTM, GRU, Transformer, attention)
- Feature engineering for temporal patterns
- Sequence modeling enhancements
- Multi-horizon forecasting
- Uncertainty quantification

### Alpha Forge Specifics

- Sharpe/Sortino/Calmar optimization
- Position sizing algorithms
- Risk management improvements
- Data pipeline robustness
- Backtesting accuracy

---

## WEB DISCOVERY (SOTA Research)

**ACTIVELY SEARCH** for state-of-the-art approaches:

{% if web_queries %}
Execute these WebSearch queries:
{% for query in web_queries %}

- "{{ query }}"
  {% endfor %}
  {% else %}
  Generate queries based on current work:
- "{current_task} SOTA implementation 2025"
- "{current_task} quantitative trading best practices"
- "time series forecasting {model_type} 2025"
  {% endif %}

**After searching**:

1. Evaluate if solution is truly SOTA (last 6 months)
2. Check library maintenance (stars > 1000, active issues)
3. Reject deprecated or unmaintained solutions
4. Propose improvements based on findings

{% if feature_ideas %}

### Accumulated Feature Ideas (from past discoveries)

{% for idea in feature_ideas %}

- **{{ idea.idea }}** ({{ idea.priority }} priority, source: {{ idea.source }})
  {% endfor %}
  {% endif %}

---

{% if opportunities %}

## FILTERED OPPORTUNITIES ({{ opportunities|length }} items)

These passed the busywork filter:
{% for opp in opportunities %}
{{ loop.index }}. {{ opp }}
{% endfor %}
{% else %}

## DISCOVERY MODE

No pre-filtered opportunities. Search for ROADMAP-aligned work:

1. Read `ROADMAP.md` - identify next P0/P1 item
2. Search for SOTA approaches to that item
3. Implement with proper validation
   {% endif %}

---

## QUALITY GATE

Before implementing:

```
1. Does this improve OOS robustness? YES/NO
2. Does this improve forecasting ability? YES/NO
3. Is the approach SOTA (2024-2025)? YES/NO
4. Is the library well-maintained? YES/NO
5. Does ROADMAP.md mention this? YES/NO
```

**If less than 3 YES answers, find different work.**

---

## ITERATION PROTOCOL

1. **READ** research_log.md and metrics history (learn from past)
2. **CHECK** ROADMAP.md for current priority
3. **SEARCH** for SOTA approach (use WebSearch)
4. **IMPLEMENT** with validation tests
5. **MEASURE** OOS impact
6. **LOG** results to research_log.md (for next iteration to learn)
7. **COMMIT** if positive impact
8. **CONTINUE** to next ROADMAP item

---

## COMMIT STANDARD

Only commit work that:

- Directly improves OOS metrics (WFE, Sharpe, etc.)
- Adds forecasting capability
- Fixes functional bugs affecting results
- Implements ROADMAP items

**Never commit style fixes, documentation, or refactoring.**

---

**NEVER idle. NEVER do busywork. ALWAYS advance ROADMAP.**
**ALWAYS read historical artifacts before starting. ALWAYS log results for future learning.**
