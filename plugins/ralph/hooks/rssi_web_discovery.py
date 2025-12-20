"""
RSSI Level 6: Web Discovery

ADR: 2025-12-20-ralph-rssi-eternal-loop

Search for ideas aligned with repo theme using web search.
Generates queries for Claude to execute, proposes big features.
Includes SOTA quality gate verification.
"""

from __future__ import annotations

import json
from datetime import datetime
from pathlib import Path

# Quality gate thresholds
MAX_DAYS_SINCE_LAST_COMMIT = 180  # 6 months


def analyze_repo_theme(project_dir: Path) -> dict:
    """
    Understand the repo's theme, domain, and positioning.

    Analyzes:
    - README content
    - Package description
    - Keywords/tags
    - Directory structure

    Args:
        project_dir: Project directory to analyze.

    Returns:
        Dict with domain, keywords, technologies, and description.
    """
    theme: dict = {
        "domain": None,
        "keywords": [],
        "technologies": [],
        "description": None,
    }

    # Parse README
    readme = project_dir / "README.md"
    if readme.exists():
        try:
            content = readme.read_text()[:2000]
            # Get first non-empty line that looks like a title
            for line in content.split("\n"):
                stripped = line.strip().lstrip("#").strip()
                if stripped:
                    theme["description"] = stripped
                    break
        except OSError:
            pass

    # Parse package.json
    pkg = project_dir / "package.json"
    if pkg.exists():
        try:
            data = json.loads(pkg.read_text())
            theme["keywords"].extend(data.get("keywords", []))
            theme["description"] = theme["description"] or data.get("description")
            if "dependencies" in data:
                theme["technologies"].extend(list(data["dependencies"].keys())[:5])
        except (json.JSONDecodeError, OSError):
            pass

    # Parse pyproject.toml for keywords
    pyproject = project_dir / "pyproject.toml"
    if pyproject.exists():
        try:
            content = pyproject.read_text()
            theme["technologies"].append("python")
            # Simple keyword extraction
            if "fastapi" in content.lower():
                theme["technologies"].append("fastapi")
            if "django" in content.lower():
                theme["technologies"].append("django")
            if "click" in content.lower() or "typer" in content.lower():
                theme["technologies"].append("cli")
        except OSError:
            pass

    # Infer from structure
    if (project_dir / "plugins").exists():
        theme["domain"] = "plugin-system"
        theme["keywords"].append("extensibility")

    if list(project_dir.glob("**/hooks/*.py")):
        theme["keywords"].append("hooks")
        theme["keywords"].append("automation")

    if (project_dir / ".claude-plugin").exists():
        theme["keywords"].append("claude-code")
        theme["keywords"].append("ai-assistant")

    # Deduplicate
    theme["keywords"] = list(set(theme["keywords"]))
    theme["technologies"] = list(set(theme["technologies"]))

    return theme


def generate_web_search_queries(theme: dict) -> list[str]:
    """
    Generate search queries based on repo theme.

    Focuses on:
    - Big features in the domain
    - Best practices
    - Trending improvements
    - Competitive analysis

    Args:
        theme: Theme dict from analyze_repo_theme().

    Returns:
        List of search query strings (max 5).
    """
    queries: list[str] = []
    current_year = datetime.now().year

    domain = theme.get("domain") or ""
    keywords = theme.get("keywords") or []
    description = theme.get("description") or ""

    if "claude" in description.lower() or "ai" in keywords or "claude-code" in keywords:
        queries.append(f"Claude Code CLI best practices {current_year}")
        queries.append(f"AI coding assistant features trending {current_year}")

    if "plugin" in keywords or "plugin-system" in domain:
        queries.append("plugin architecture best practices")
        queries.append("marketplace plugin discovery patterns")

    if "hooks" in keywords:
        queries.append("git hooks automation best practices")
        queries.append("pre-commit hook patterns")

    if "automation" in keywords:
        queries.append(f"developer automation trending features {current_year}")
        queries.append("CI/CD automation innovations")

    if "cli" in (theme.get("technologies") or []):
        queries.append(f"CLI tool best practices Python {current_year}")

    # Generic improvement queries based on description
    if description:
        queries.append(f"{description[:50]} feature ideas")
        queries.append(f"{description[:50]} improvements roadmap")

    # Deduplicate and limit
    seen: set[str] = set()
    unique_queries: list[str] = []
    for q in queries:
        if q not in seen:
            seen.add(q)
            unique_queries.append(q)

    return unique_queries[:5]


def generate_quality_search_queries(opportunity: str) -> list[str]:
    """
    Generate searches to find SOTA solutions for an opportunity.

    Args:
        opportunity: The improvement opportunity to research.

    Returns:
        List of SOTA-focused search queries.
    """
    current_year = datetime.now().year
    prev_year = current_year - 1

    return [
        f"{opportunity} SOTA implementation {prev_year} {current_year}",
        f"{opportunity} best practices Python {current_year}",
        f"{opportunity} production-grade library comparison",
        f"github.com {opportunity} stars:>1000 pushed:>{prev_year}-01-01",
    ]


def web_search_for_ideas(project_dir: Path) -> list[str]:
    """
    Generate prompts for Claude to execute WebSearch.

    Returns list of actionable suggestions.

    NOTE: This function generates prompts for Claude to execute.
    The actual WebSearch tool call happens in the template.

    Args:
        project_dir: Project directory to analyze.

    Returns:
        List of suggestions including search queries to execute.
    """
    theme = analyze_repo_theme(project_dir)
    queries = generate_web_search_queries(theme)

    suggestions: list[str] = []
    suggestions.append("**WEB DISCOVERY ACTIVE** - Search for feature ideas:")

    for query in queries:
        suggestions.append(f'- WebSearch: "{query}"')

    suggestions.append("")
    suggestions.append("After searching, propose 2-3 BIG FEATURES that would:")
    suggestions.append("1. Align with the repo's positioning")
    suggestions.append("2. Differentiate from competitors")
    suggestions.append("3. Provide significant user value")

    return suggestions


def get_sota_alternatives() -> dict[str, str]:
    """
    Return mapping of legacy patterns to SOTA alternatives.

    Returns:
        Dict mapping legacy tool/pattern to recommended SOTA alternative.
    """
    return {
        # Python CLI
        "argparse": "typer or click",
        "optparse": "typer or click",
        # HTTP
        "urllib": "httpx or requests",
        "urllib2": "httpx or requests",
        "urllib3": "httpx (for async) or requests",
        # Testing
        "unittest": "pytest",
        "nose": "pytest",
        # Config
        "configparser": "pydantic-settings or dynaconf",
        "raw dict config": "pydantic BaseSettings",
        # Logging
        "print debugging": "structlog or loguru",
        "logging.basicConfig": "structlog",
        # String matching
        "SequenceMatcher": "rapidfuzz or thefuzz",
        "difflib": "rapidfuzz for fuzzy matching",
        # Data validation
        "manual validation": "pydantic",
        "jsonschema": "pydantic for Python objects",
        # Async
        "threading for IO": "asyncio with httpx/aiofiles",
        "multiprocessing for IO": "asyncio",
    }


def evaluate_solution_quality(solution: dict) -> dict:
    """
    Evaluate whether a proposed solution meets quality standards.

    Args:
        solution: Dict with package info (name, last_commit_days, stars, etc.)

    Returns:
        Dict with is_sota, is_well_maintained, recommendation, alternatives.
    """
    result = {
        "is_sota": True,
        "is_well_maintained": True,
        "recommendation": "acceptable",
        "alternatives": [],
    }

    # Check if it's a known legacy pattern
    sota_alternatives = get_sota_alternatives()
    package_name = solution.get("name", "").lower()

    for legacy, modern in sota_alternatives.items():
        if legacy.lower() in package_name:
            result["is_sota"] = False
            result["alternatives"].append(modern)
            result["recommendation"] = f"Consider using {modern} instead"
            break

    # Check maintenance status
    last_commit_days = solution.get("last_commit_days", 0)
    if last_commit_days > MAX_DAYS_SINCE_LAST_COMMIT:
        result["is_well_maintained"] = False
        result["recommendation"] = (
            f"Package not updated in {last_commit_days} days. "
            f"Consider alternatives."
        )

    # Check stars (optional quality signal)
    stars = solution.get("stars", 0)
    if stars < 100 and not result["is_sota"]:
        result["recommendation"] += " Low community adoption."

    return result


def get_quality_gate_instructions() -> list[str]:
    """
    Return quality gate instructions for the exploration template.

    Returns:
        List of instruction strings for SOTA verification.
    """
    return [
        "**QUALITY GATE** - Before implementing any solution:",
        "",
        "1. **Is it SOTA?**",
        '   - Search: "{problem} SOTA implementation 2025"',
        "   - Verify: Using modern patterns, not legacy approaches",
        "",
        "2. **Is the OSS well-maintained?**",
        "   - Check GitHub: stars, last commit, open issues",
        "   - Verify: Last release within 6 months",
        "   - Verify: Active maintainer responses",
        "",
        "3. **Reject if**:",
        "   - OSS last updated > 6 months ago",
        "   - Using deprecated/legacy patterns",
        "   - Better SOTA alternative exists",
        "",
        "**Example quality checks**:",
        "- Is argparse SOTA? → No, use typer or click",
        "- Is requests SOTA? → Yes, but consider httpx for async",
        "- Is unittest SOTA? → No, use pytest",
    ]
