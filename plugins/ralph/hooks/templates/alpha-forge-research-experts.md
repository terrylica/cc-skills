---
name: alpha_forge_research_experts
description: Spawn 5 parallel research experts for Alpha Forge strategy optimization
phase: exploration
adapter: alpha-forge
---

## Alpha Forge Research Experts

**Research Phase**: {{ research_phase | upper }}
**Iteration**: {{ iteration }}
**Best Sharpe**: {{ best_sharpe }}

{% if research_phase == "exploration" %}
**Mode**: Fast exploration - up to 3 changes per iteration allowed
{% else %}
**Mode**: Attribution - exactly 1 change per iteration for clear cause-effect
{% endif %}

---

### Expert Subagent Spawning

Use the Task tool to spawn ALL 5 experts **in parallel** (single message, multiple tool calls):

**1. Risk Analyst** (Priority 5 - HIGHEST):

```
Task(
    subagent_type="risk-analyst",
    prompt="Analyze Alpha Forge strategy for overfitting risks, walk-forward efficiency, and drawdown concerns. Review metrics_history: {{ metrics_history }}. Focus on: (1) Train vs test performance gaps, (2) WFE scores and interpretation, (3) Maximum drawdown sustainability, (4) Parameter sensitivity. Return structured recommendations."
)
```

**2. Data Specialist** (Priority 4):

```
Task(
    subagent_type="data-specialist",
    prompt="Analyze Alpha Forge data pipeline for quality issues, universe selection, and gap handling. Check: (1) Data gaps or missing bars, (2) Universe appropriateness for strategy, (3) Lookahead bias risks, (4) Feature warmup adequacy. Return structured recommendations."
)
```

**3. Domain Expert** (Priority 3):

```
Task(
    subagent_type="domain-expert",
    prompt="Analyze Alpha Forge strategy from market microstructure perspective. Evaluate: (1) Execution feasibility at target AUM, (2) Liquidity constraints, (3) Market regime sensitivity, (4) Transaction cost assumptions. Return structured recommendations."
)
```

**4. Model Expert** (Priority 2):

```
Task(
    subagent_type="model-expert",
    prompt="Analyze Alpha Forge ML model architecture and training dynamics. Review: (1) Architecture choices (BiLSTM, Transformer), (2) Loss function alignment with objectives, (3) Training stability and convergence, (4) Hyperparameter sensitivity. Return structured recommendations."
)
```

**5. Feature Expert** (Priority 1 - LOWEST):

```
Task(
    subagent_type="feature-expert",
    prompt="Analyze Alpha Forge feature engineering for signal quality. Evaluate: (1) Information Coefficient (IC) of features, (2) Feature redundancy and correlation, (3) Cross-sectional vs time-series feature mix, (4) Feature selection methodology. Return structured recommendations."
)
```

---

### Conflict Resolution Protocol

When experts disagree, follow **priority order** (higher priority wins):

| Priority    | Expert          | Focus Area                   |
| ----------- | --------------- | ---------------------------- |
| 5 (highest) | risk-analyst    | Overfitting, WFE, drawdown   |
| 4           | data-specialist | Data quality, universe, gaps |
| 3           | domain-expert   | Execution, liquidity, regime |
| 2           | model-expert    | Architecture, loss, training |
| 1 (lowest)  | feature-expert  | IC/IR, indicators, selection |

**Example**: If feature-expert suggests adding 10 new features but risk-analyst warns of overfitting risk, follow risk-analyst's guidance.

---

### IMMUTABLE Parameters

The following parameters **MUST NOT** be modified mid-session (iterations become incomparable):

```yaml
# Data configuration
data.date_range          # Backtesting date bounds
data.universe            # Asset universe definition
data.timeframe           # Bar interval (1h, 4h, etc.)

# Split configuration
splits.train/valid/test  # Date boundaries for splits

# Backtest configuration
backtest.fee_bps         # Transaction fee assumption
backtest.slip_bps        # Slippage assumption

# Position configuration
position.clip_range      # Position size limits
position.normalize       # Normalization method
position.long_only       # Long-only constraint

# Label configuration
labels.horizons          # Forward return horizons
labels.weights           # Multi-horizon weights

# Execution configuration
execution_mode           # batch vs event mode
```

If an expert recommends changing an immutable parameter, record it as a **deferred recommendation**.

---

### Deferred Recommendations Format

For immutable parameter changes experts want but cannot apply mid-session:

```yaml
deferred_recommendations:
  - parameter: backtest.params.fee_bps
    current_value: 2.0
    suggested_value: 5.0
    rationale: "Conservative estimate for larger position sizes"
    priority: high
    expert: domain-expert
```

Collect these for the next research session with fresh baseline.

---

### Expert Output Schema

All experts MUST return structured output:

```yaml
recommendations:
  add: [] # New elements to add (features, params, etc.)
  modify: [] # Existing elements to change
  remove: [] # Elements to remove

deferred_recommendations: [] # For immutable params (see format above)

plugin_requests: [] # New plugins needed (collect, don't implement)

confidence: high | medium | low

key_insight: "One sentence summary of most important finding"
```

---

### Synthesis Protocol

After all 5 experts complete:

1. **Collect** all recommendations from expert outputs
2. **Resolve conflicts** using priority order
3. **Filter** by phase limits:
   {% if research_phase == "exploration" %}
   - Select up to **3 highest-priority changes** for this iteration
     {% else %}
   - Select exactly **1 highest-priority change** for attribution clarity
     {% endif %}
4. **Generate** next experiment YAML with selected changes
5. **Document** rationale for selected changes in research log

---

{% if metrics_history %}

### Current Metrics Context

| Run | Sharpe | CAGR | MaxDD | WFE |
| --- | ------ | ---- | ----- | --- |

{% for m in metrics_history[-5:] %}
| {{ m.identifier }} | {{ "%.3f"|format(m.primary_metric) }} | {{ m.secondary_metrics.cagr|default("N/A") }} | {{ m.secondary_metrics.maxdd|default("N/A") }} | {{ m.secondary_metrics.wfe|default("N/A") }} |
{% endfor %}
{% endif %}
