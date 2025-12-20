---
name: alpha_forge_convergence
description: Alpha Forge strategy research convergence status
phase: adapter
adapter: alpha-forge
---

## Alpha Forge Research Status

**Adapter**: {{ adapter_name }}
**Experiments Run**: {{ metrics_count }}
**Best Sharpe**: {{ best_sharpe }}

### Convergence Check

{{ convergence_reason }}

{% if convergence_confidence >= 0.5 %}
**Recommendation**: {{ "STOP - Convergence detected" if not should_continue else "CONTINUE - Still exploring" }}
{% endif %}

{% if metrics_history %}

### Recent Experiments (Last 5)

| Run | Sharpe | CAGR | MaxDD | WFE |
| --- | ------ | ---- | ----- | --- |

{% for m in metrics_history[-5:] %}
| {{ m.identifier }} | {{ "%.3f"|format(m.primary_metric) }} | {{ m.secondary_metrics.cagr|default("N/A") }} | {{ m.secondary_metrics.maxdd|default("N/A") }} | {{ m.secondary_metrics.wfe|default("N/A") }} |
{% endfor %}
{% endif %}
