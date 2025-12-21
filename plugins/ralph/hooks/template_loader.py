"""Template loader for Ralph hook prompts.

Uses Jinja2 for template rendering with markdown files.
Templates are stored in the templates/ directory with YAML frontmatter.
"""
import re
from pathlib import Path
from typing import Any

# Jinja2 is optional - fall back to simple string replacement if not available
try:
    from jinja2 import Environment, FileSystemLoader, StrictUndefined, select_autoescape
    JINJA2_AVAILABLE = True
except ImportError:
    JINJA2_AVAILABLE = False

TEMPLATES_DIR = Path(__file__).parent / "templates"


def parse_frontmatter(content: str) -> tuple[dict[str, str], str]:
    """Extract YAML frontmatter and body from markdown content.

    Returns:
        (metadata, body) - metadata dict and remaining content
    """
    if not content.startswith("---"):
        return {}, content

    # Find closing ---
    end_match = re.search(r'\n---\n', content[3:])
    if not end_match:
        return {}, content

    frontmatter = content[4:end_match.start() + 3]
    body = content[end_match.end() + 4:]

    # Simple YAML parsing (key: value pairs only)
    metadata = {}
    for line in frontmatter.strip().split('\n'):
        if ':' in line:
            key, value = line.split(':', 1)
            metadata[key.strip()] = value.strip()

    return metadata, body.strip()


def _simple_render(template: str, context: dict[str, Any]) -> str:
    """Fallback renderer using simple {{ var }} replacement.

    Handles basic variable substitution only (no loops/conditionals).
    """
    result = template
    for key, value in context.items():
        placeholder = "{{ " + key + " }}"
        if isinstance(value, (list, dict)):
            value = str(value)
        result = result.replace(placeholder, str(value))

    # Also handle {%...%} blocks by removing them (best effort)
    result = re.sub(r'\{%.*?%\}', '', result, flags=re.DOTALL)

    return result


class TemplateLoader:
    """Load and render markdown templates with Jinja2."""

    def __init__(self, templates_dir: Path | None = None):
        self.templates_dir = templates_dir or TEMPLATES_DIR
        self._env = None
        self._cache: dict[str, tuple[dict, str]] = {}

    @property
    def env(self):
        """Lazy-load Jinja2 environment."""
        if self._env is None and JINJA2_AVAILABLE:
            self._env = Environment(
                loader=FileSystemLoader(str(self.templates_dir)),
                autoescape=select_autoescape(['html', 'xml']),
                trim_blocks=True,
                lstrip_blocks=True,
                undefined=StrictUndefined,  # Catch template variable typos
            )
        return self._env

    def load(self, template_name: str) -> tuple[dict[str, str], str]:
        """Load a template file and parse frontmatter.

        Args:
            template_name: Template filename (e.g., 'validation-round-1.md')

        Returns:
            (metadata, template_body)
        """
        if template_name in self._cache:
            return self._cache[template_name]

        template_path = self.templates_dir / template_name
        if not template_path.exists():
            raise FileNotFoundError(f"Template not found: {template_path}")

        content = template_path.read_text()
        metadata, body = parse_frontmatter(content)

        self._cache[template_name] = (metadata, body)
        return metadata, body

    def render(self, template_name: str, **context) -> str:
        """Render a template with the given context.

        Args:
            template_name: Template filename
            **context: Variables to pass to the template

        Returns:
            Rendered template string
        """
        metadata, body = self.load(template_name)

        if JINJA2_AVAILABLE and self.env:
            template = self.env.from_string(body)
            return template.render(**context)
        else:
            # Fallback to simple replacement
            return _simple_render(body, context)

    def render_exploration(
        self,
        opportunities: list[str] | None = None,
        rssi_context: dict | None = None,
        adapter_name: str | None = None,
        metrics_history: list | None = None,
    ) -> str:
        """Render the exploration mode prompt with full RSSI context.

        ADR: 2025-12-20-ralph-rssi-eternal-loop

        Uses adapter-specific templates when available (e.g., alpha-forge-exploration.md
        for Alpha Forge projects) to provide domain-specific guidance.

        Args:
            opportunities: List of discovered work opportunities
            rssi_context: Full RSSI context dict with keys:
                - iteration: int - current RSSI loop iteration
                - accumulated_patterns: list[str] - learned patterns
                - disabled_checks: list[str] - ineffective checks disabled
                - effective_checks: list[str] - prioritized by effectiveness
                - web_insights: list[str] - domain insights from web
                - feature_ideas: list[dict] - big feature proposals
                - web_queries: list[str] - search queries to execute
                - missing_tools: list[str] - capability expansion suggestions
                - quality_gate: list[str] - SOTA quality gate instructions
            adapter_name: Name of the active adapter (e.g., "alpha-forge")
            metrics_history: Project-specific metrics history (for Alpha Forge)

        Returns:
            Rendered prompt string
        """
        ctx = rssi_context or {}

        # Common context variables
        common_ctx = {
            "opportunities": opportunities or [],
            "iteration": ctx.get("iteration", 0),
            "accumulated_patterns": ctx.get("accumulated_patterns", []),
            "disabled_checks": ctx.get("disabled_checks", []),
            "effective_checks": ctx.get("effective_checks", []),
            "web_insights": ctx.get("web_insights", []),
            "feature_ideas": ctx.get("feature_ideas", []),
            "web_queries": ctx.get("web_queries", []),
            "missing_tools": ctx.get("missing_tools", []),
            "quality_gate": ctx.get("quality_gate", []),
            "overall_effectiveness": ctx.get("overall_effectiveness", 0.0),
        }

        # Alpha Forge: ONLY use alpha-forge-exploration.md (no fallback)
        if adapter_name == "alpha-forge":
            return self.render(
                "alpha-forge-exploration.md",
                **common_ctx,
                metrics_history=metrics_history or [],
            )

        # All other projects: use generic template
        return self.render("exploration-mode.md", **common_ctx)

    def render_adapter_status(
        self,
        adapter_name: str,
        adapter_convergence: dict | None,
        metrics_history: list | None = None
    ) -> str:
        """Render adapter-specific status for project-aware convergence.

        Uses alpha-forge-convergence.md template for Alpha Forge projects,
        or a generic format for other adapters.

        Args:
            adapter_name: Name of the active adapter
            adapter_convergence: Convergence result dict with keys:
                - should_continue: bool
                - reason: str
                - confidence: float
                - metrics_count: int
            metrics_history: Optional list of metrics entries

        Returns:
            Rendered adapter status string
        """
        if adapter_convergence is None:
            return ""

        # Only show adapter status if confidence > 0 (has opinion)
        if adapter_convergence.get("confidence", 0) == 0:
            return ""

        # Use specialized template for Alpha Forge
        if adapter_name == "alpha-forge":
            try:
                return self.render(
                    "alpha-forge-convergence.md",
                    adapter_name=adapter_name,
                    metrics_count=adapter_convergence.get("metrics_count", 0),
                    best_sharpe=self._extract_best_sharpe(metrics_history),
                    convergence_reason=adapter_convergence.get("reason", ""),
                    convergence_confidence=adapter_convergence.get("confidence", 0),
                    should_continue=adapter_convergence.get("should_continue", True),
                    metrics_history=metrics_history or []
                )
            except FileNotFoundError:
                pass  # Fall through to generic format

        # Generic adapter status format
        confidence = adapter_convergence.get("confidence", 0)
        reason = adapter_convergence.get("reason", "")
        should_continue = adapter_convergence.get("should_continue", True)
        metrics_count = adapter_convergence.get("metrics_count", 0)

        status = "CONTINUE" if should_continue else "STOP"
        confidence_label = "override" if confidence >= 1.0 else "suggest"

        return (
            f"\n**Adapter [{adapter_name}]**: {status} ({confidence_label})\n"
            f"Metrics: {metrics_count} | Reason: {reason}"
        )

    def _extract_best_sharpe(self, metrics_history: list | None) -> float:
        """Extract best Sharpe ratio from metrics history."""
        if not metrics_history:
            return 0.0

        try:
            sharpes = []
            for m in metrics_history:
                if hasattr(m, "primary_metric"):
                    sharpes.append(m.primary_metric)
                elif isinstance(m, dict):
                    sharpes.append(m.get("primary_metric", 0))
            return max(sharpes) if sharpes else 0.0
        except (TypeError, ValueError):
            return 0.0

    def _compute_research_phase(self, metrics_history: list | None) -> str:
        """Compute research phase from metrics history.

        Phase determination (Alpha Forge specific):
        - exploration: Best Sharpe < 1.0, allows up to 3 changes per iteration
        - attribution: Best Sharpe >= 1.0, restricts to 1 change for attribution

        Args:
            metrics_history: List of metrics entries

        Returns:
            'exploration' or 'attribution' phase string
        """
        best_sharpe = self._extract_best_sharpe(metrics_history)
        return "attribution" if best_sharpe >= 1.0 else "exploration"

    def render_research_experts(
        self,
        adapter_name: str,
        state: dict,
        config: dict,
        metrics_history: list | None = None,
        research_phase: str | None = None
    ) -> str:
        """Render research experts template based on adapter type.

        Spawns 5 parallel expert subagents for strategy research:
        - risk-analyst, data-specialist, domain-expert, model-expert, feature-expert

        Only Alpha Forge adapter supports research experts currently.

        Args:
            adapter_name: Name of the active adapter
            state: Current loop state
            config: Loop configuration
            metrics_history: List of metrics entries (serialized dicts)
            research_phase: 'exploration' or 'attribution' phase (auto-computed if None)

        Returns:
            Rendered research experts prompt, or empty string if not supported
        """
        if adapter_name == "alpha-forge":
            # Auto-compute research phase from metrics if not provided
            if research_phase is None:
                research_phase = self._compute_research_phase(metrics_history)

            try:
                return self.render(
                    "alpha-forge-research-experts.md",
                    state=state,
                    config=config,
                    metrics_history=metrics_history or [],
                    research_phase=research_phase,
                    best_sharpe=self._extract_best_sharpe(metrics_history),
                    iteration=state.get("iteration", 0),
                )
            except FileNotFoundError:
                pass  # Fall through to empty return

        return ""  # No research experts for unknown adapters


# Global instance for convenience
_loader: TemplateLoader | None = None


def get_loader() -> TemplateLoader:
    """Get the global template loader instance."""
    global _loader
    if _loader is None:
        _loader = TemplateLoader()
    return _loader
