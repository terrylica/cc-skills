"""Template loader for Ralph hook prompts.

Uses Jinja2 for template rendering with markdown files.
Templates are stored in the templates/ directory with YAML frontmatter.
"""
import re
from pathlib import Path
from typing import Any

# Jinja2 is optional - fall back to simple string replacement if not available
try:
    from jinja2 import Environment, FileSystemLoader, select_autoescape
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
                lstrip_blocks=True
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

    def render_validation_round(self, round_num: int, state: dict, config: dict) -> str:
        """Render a validation round prompt.

        Args:
            round_num: Round number (1, 2, or 3)
            state: Current loop state
            config: Loop configuration

        Returns:
            Rendered prompt string
        """
        timeout = config.get("validation_timeout_poc", 30) if config.get("poc_mode") else config.get("validation_timeout_normal", 120)

        if round_num == 1:
            return self.render("validation-round-1.md", timeout=timeout)

        elif round_num == 2:
            round1_findings = state.get("validation_findings", {}).get("round1", {})
            critical = round1_findings.get("critical", [])
            medium = round1_findings.get("medium", [])

            import json
            return self.render(
                "validation-round-2.md",
                critical_count=len(critical),
                medium_count=len(medium),
                critical_issues=json.dumps(critical[:5], indent=2) if critical else "None",
                medium_issues=json.dumps(medium[:5], indent=2) if medium else "None"
            )

        elif round_num == 3:
            return self.render("validation-round-3.md", timeout=timeout)

        return ""

    def render_exploration(self, opportunities: list[str] | None = None) -> str:
        """Render the exploration mode prompt.

        Args:
            opportunities: List of discovered work opportunities

        Returns:
            Rendered prompt string
        """
        return self.render("exploration-mode.md", opportunities=opportunities or [])

    def render_status_header(
        self,
        mode: str,
        iteration: int,
        max_iterations: int,
        elapsed: float,
        remaining_hours: float,
        remaining_iters: int
    ) -> str:
        """Render the status header line.

        Returns:
            Formatted status line
        """
        return self.render(
            "status-header.md",
            mode=mode,
            iteration=iteration,
            max_iterations=max_iterations,
            elapsed=f"{elapsed:.1f}",
            remaining_hours=f"{remaining_hours:.1f}",
            remaining_iters=remaining_iters
        )


# Global instance for convenience
_loader: TemplateLoader | None = None


def get_loader() -> TemplateLoader:
    """Get the global template loader instance."""
    global _loader
    if _loader is None:
        _loader = TemplateLoader()
    return _loader
