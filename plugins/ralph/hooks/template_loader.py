"""Template loader for Ralph hook prompts.

Uses Jinja2 for template rendering with markdown files.
Templates are stored in the templates/ directory with YAML frontmatter.
"""
import re
from pathlib import Path
from typing import Any

from observability import emit

# Jinja2 is REQUIRED for ralph templates (declared in PEP 723 script metadata)
# The templates use advanced features (for loops, filters, nested access) that
# cannot be reasonably implemented in a fallback renderer.
try:
    from jinja2 import Environment, FileSystemLoader, StrictUndefined, select_autoescape
    JINJA2_AVAILABLE = True
except ImportError:
    JINJA2_AVAILABLE = False
    import warnings
    warnings.warn(
        "Jinja2 not available. Ralph templates require Jinja2 for proper rendering. "
        "Run via 'uv run' to auto-install dependencies, or: pip install jinja2>=3.1.0",
        RuntimeWarning,
        stacklevel=2
    )

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


def _resolve_path(context: dict[str, Any], path: str) -> Any:
    """Resolve a dotted path like 'gpu_infrastructure.host' from context.

    Args:
        context: Template context dict
        path: Dotted path string (e.g., 'foo.bar.baz')

    Returns:
        Resolved value or None if path doesn't exist
    """
    parts = path.split(".")
    value = context
    for part in parts:
        if isinstance(value, dict) and part in value:
            value = value[part]
        else:
            return None
    return value


def _simple_render(template: str, context: dict[str, Any]) -> str:
    """Fallback renderer using simple {{ var }} replacement.

    Handles basic variable substitution including nested dict access
    (e.g., {{ gpu_infrastructure.host }}). Does not support loops/conditionals.
    """
    result = template

    # Handle nested access patterns like {{ foo.bar.baz }}
    var_pattern = re.compile(r'\{\{\s*([a-zA-Z_][a-zA-Z0-9_\.]*)\s*\}\}')
    for match in var_pattern.finditer(template):
        path = match.group(1)
        value = _resolve_path(context, path)
        if value is not None:
            if isinstance(value, (list, dict)):
                value = str(value)
            result = result.replace(match.group(0), str(value))

    # Handle {% if var %} ... {% endif %} blocks (basic support)
    # Remove blocks where condition is falsy
    if_pattern = re.compile(
        r'\{%\s*if\s+([a-zA-Z_][a-zA-Z0-9_\.]*)\s+and\s+([a-zA-Z_][a-zA-Z0-9_\.]*)\s*%\}'
        r'(.*?)'
        r'\{%\s*endif\s*%\}',
        re.DOTALL
    )
    for match in if_pattern.finditer(result):
        cond1 = _resolve_path(context, match.group(1))
        cond2 = _resolve_path(context, match.group(2))
        if cond1 and cond2:
            # Keep the content, remove the tags
            result = result.replace(match.group(0), match.group(3))
        else:
            # Remove the entire block
            result = result.replace(match.group(0), "")

    # Handle simpler {% if var %} ... {% endif %} blocks
    simple_if_pattern = re.compile(
        r'\{%\s*if\s+([a-zA-Z_][a-zA-Z0-9_\.]*)\s*%\}'
        r'(.*?)'
        r'\{%\s*endif\s*%\}',
        re.DOTALL
    )
    for match in simple_if_pattern.finditer(result):
        cond = _resolve_path(context, match.group(1))
        if cond:
            result = result.replace(match.group(0), match.group(2))
        else:
            result = result.replace(match.group(0), "")

    # Remove any remaining {%...%} blocks (best effort)
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

        Raises:
            RuntimeError: If template uses advanced Jinja2 features but Jinja2 unavailable
        """
        metadata, body = self.load(template_name)

        if JINJA2_AVAILABLE and self.env:
            template = self.env.from_string(body)
            return template.render(**context)
        else:
            # Check if template uses features the fallback can't handle
            unsupported = []
            if re.search(r'\{%\s*for\s+', body):
                unsupported.append("for loops")
            if re.search(r'\|(?:length|format|default|upper|lower)', body):
                unsupported.append("filters (|length, |format, |default)")
            if re.search(r'\[-?\d+:?\]', body):
                unsupported.append("list slicing")

            if unsupported:
                raise RuntimeError(
                    f"Template '{template_name}' uses Jinja2 features not supported by fallback: "
                    f"{', '.join(unsupported)}. "
                    f"Install Jinja2: pip install jinja2>=3.1.0, or run via 'uv run'."
                )

            # Fallback to simple replacement (only for basic templates)
            return _simple_render(body, context)

    def render_exploration(
        self,
        opportunities: list[str] | None = None,
        rssi_context: dict | None = None,
        adapter_name: str | None = None,
        metrics_history: list | None = None,
    ) -> str:
        """Render exploration mode prompt. DEPRECATED: Use render_unified() instead.

        This method is kept for backward compatibility. It delegates to
        render_unified(task_complete=True) which uses the unified rssi-unified.md
        template.

        Args:
            opportunities: List of discovered work opportunities
            rssi_context: Full RSSI context dict
            adapter_name: Name of the active adapter (e.g., "alpha-forge")
            metrics_history: Project-specific metrics history

        Returns:
            Rendered prompt string
        """
        # Delegate to unified template with task_complete=True (exploration phase)
        return self.render_unified(
            task_complete=True,
            rssi_context=rssi_context,
            adapter_name=adapter_name,
            metrics_history=metrics_history,
            opportunities=opportunities,
        )

    def render_unified(
        self,
        task_complete: bool = False,
        rssi_context: dict | None = None,
        adapter_name: str | None = None,
        metrics_history: list | None = None,
        opportunities: list[str] | None = None,
    ) -> str:
        """Render the unified RSSI template for all phases.

        This is the single entry point for all Ralph prompts, replacing the
        separate implementation-mode.md and exploration-mode.md templates.
        User guidance (encourage/forbid) applies to ALL phases.

        ADR: 2025-12-20-ralph-rssi-eternal-loop

        Args:
            task_complete: True = exploration phase, False = implementation phase
            rssi_context: Full RSSI context dict with keys:
                - iteration: int - current RSSI loop iteration
                - guidance: dict - user guidance with forbidden/encouraged lists
                - accumulated_patterns: list[str] - learned patterns
                - disabled_checks: list[str] - ineffective checks disabled
                - effective_checks: list[str] - prioritized by effectiveness
                - web_insights: list[str] - domain insights from web
                - feature_ideas: list[dict] - big feature proposals
                - web_queries: list[str] - search queries to execute
                - gpu_infrastructure: dict - GPU config if available
            adapter_name: Name of the active adapter (e.g., "alpha-forge")
            metrics_history: Project-specific metrics history (for Alpha Forge)
            opportunities: List of discovered work opportunities

        Returns:
            Rendered prompt string
        """
        ctx = rssi_context or {}

        # Check if research is converged (from adapter_convergence in rssi_context)
        adapter_conv = ctx.get("adapter_convergence", {})
        research_converged = adapter_conv.get("converged", False) if adapter_conv else False

        # Extract user guidance - ALWAYS applies regardless of phase
        guidance = ctx.get("guidance", {})
        forbidden_items = guidance.get("forbidden", []) if guidance else []
        encouraged_items = guidance.get("encouraged", []) if guidance else []

        # Emit template rendering status
        phase = "EXPLORATION" if task_complete else "IMPLEMENTATION"
        emit(
            "Template",
            f"Rendering rssi-unified.md ({phase}): "
            f"{len(forbidden_items)} forbidden, {len(encouraged_items)} encouraged"
        )

        # Unified context for all phases
        context = {
            # Phase flag - the key difference
            "task_complete": task_complete,
            # User guidance - ALWAYS applies
            "forbidden_items": forbidden_items,
            "encouraged_items": encouraged_items,
            # Opportunities
            "opportunities": opportunities or [],
            # RSSI context
            "iteration": ctx.get("iteration", 0),
            "project_dir": ctx.get("project_dir", ""),
            "accumulated_patterns": ctx.get("accumulated_patterns", []),
            "disabled_checks": ctx.get("disabled_checks", []),
            "effective_checks": ctx.get("effective_checks", []),
            "web_insights": ctx.get("web_insights", []),
            "feature_ideas": ctx.get("feature_ideas", []),
            "web_queries": ctx.get("web_queries", []),
            "missing_tools": ctx.get("missing_tools", []),
            "quality_gate": ctx.get("quality_gate", []),
            "overall_effectiveness": ctx.get("overall_effectiveness", 0.0),
            "gpu_infrastructure": ctx.get("gpu_infrastructure", {}),
            # Adapter-specific
            "adapter_name": adapter_name or "",
            "metrics_history": metrics_history or [],
            "research_converged": research_converged,
        }

        return self.render("rssi-unified.md", **context)


# Global instance for convenience
_loader: TemplateLoader | None = None


def get_loader() -> TemplateLoader:
    """Get the global template loader instance."""
    global _loader
    if _loader is None:
        _loader = TemplateLoader()
    return _loader
