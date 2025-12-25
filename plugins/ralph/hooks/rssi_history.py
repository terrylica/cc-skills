"""
RSSI Level 3: History Mining

ADR: 2025-12-20-ralph-rssi-eternal-loop

Analyzes past sessions to find high-value improvement patterns.
Learns from what exploration items led to actual commits.
"""

from __future__ import annotations

import json
import subprocess
from pathlib import Path

from core.constants import STATE_DIR

# History analysis constants
DEFAULT_COMMIT_DAYS = 7
MAX_COMMITS_TO_ANALYZE = 20
GIT_TIMEOUT_SECONDS = 10
MAX_SUGGESTIONS = 3
COMMIT_LINE_TRUNCATE_LENGTH = 60
DEFAULT_SESSION_LIMIT = 10
MIN_PATTERN_FREQUENCY = 2
MAX_PATTERNS_TO_RETURN = 5


def mine_session_history() -> list[str]:
    """
    Analyze past sessions to find high-value improvement patterns.

    Strategy:
    1. Find sessions that led to actual commits
    2. Extract what exploration items were being worked on
    3. Prioritize patterns that consistently led to value

    Returns:
        List of learned patterns (e.g., "High-value pattern (3x): lint fixes")
    """
    learnings: list[str] = []
    commit_patterns: dict[str, int] = {}

    sessions_dir = STATE_DIR / "sessions"
    if not sessions_dir.exists():
        return learnings

    try:
        for session_file in sessions_dir.glob("*.json"):
            try:
                data = json.loads(session_file.read_text())
                recent_outputs = data.get("recent_outputs", [])

                for i, output in enumerate(recent_outputs):
                    if "git commit" in output or "committed" in output.lower():
                        # Look at what was happening before the commit
                        context = recent_outputs[max(0, i - 3) : i]
                        pattern = _extract_work_pattern(context)
                        if pattern:
                            commit_patterns[pattern] = commit_patterns.get(pattern, 0) + 1
            except (json.JSONDecodeError, OSError):
                continue
    except OSError:
        return learnings

    # Convert high-frequency patterns to suggestions
    sorted_patterns = sorted(commit_patterns.items(), key=lambda x: -x[1])
    for pattern, count in sorted_patterns[:MAX_PATTERNS_TO_RETURN]:
        if count >= MIN_PATTERN_FREQUENCY:  # Pattern appeared in multiple sessions
            learnings.append(f"High-value pattern ({count}x): {pattern}")

    return learnings


def _extract_work_pattern(context: list[str]) -> str | None:
    """
    Extract the type of work from context lines.

    Args:
        context: List of recent output lines before a commit.

    Returns:
        Pattern name if detected, None otherwise.
    """
    keywords = {
        "ruff": "lint fixes",
        "mypy": "type fixes",
        "test": "test improvements",
        "docs": "documentation",
        "readme": "README updates",
        "todo": "TODO cleanup",
        "refactor": "refactoring",
        "fix": "bug fixes",
        "feat": "feature additions",
        "chore": "maintenance tasks",
    }

    combined = " ".join(context).lower()
    for keyword, pattern in keywords.items():
        if keyword in combined:
            return pattern
    return None


def get_recent_commits_for_analysis(project_dir: Path, days: int = DEFAULT_COMMIT_DAYS) -> list[str]:
    """
    Get recent commits to analyze for follow-up opportunities.

    Args:
        project_dir: Project directory.
        days: How many days back to look.

    Returns:
        List of follow-up suggestions based on commit types.
    """
    suggestions: list[str] = []

    try:
        result = subprocess.run(
            ["git", "log", f"--since={days} days ago", "--oneline", f"-{MAX_COMMITS_TO_ANALYZE}"],
            cwd=project_dir,
            capture_output=True,
            text=True,
            timeout=GIT_TIMEOUT_SECONDS,
        )

        for line in result.stdout.strip().split("\n"):
            if not line:
                continue

            line_lower = line.lower()

            # Suggest documentation review for substantial commits
            if any(word in line_lower for word in ["feat", "add", "implement"]):
                suggestions.append(f"Verify docs for: {line[:COMMIT_LINE_TRUNCATE_LENGTH]}")

            # Suggest test review for bug fixes
            if any(word in line_lower for word in ["fix", "bug", "patch"]):
                suggestions.append(f"Verify test coverage for: {line[:COMMIT_LINE_TRUNCATE_LENGTH]}")

    except (subprocess.TimeoutExpired, OSError):
        pass

    return suggestions[:MAX_SUGGESTIONS]


def get_session_output_patterns(limit: int = 10) -> dict[str, int]:
    """
    Analyze recent session outputs for recurring patterns.

    Args:
        limit: Maximum number of sessions to analyze.

    Returns:
        Dict mapping pattern to frequency count.
    """
    patterns: dict[str, int] = {}

    sessions_dir = STATE_DIR / "sessions"
    if not sessions_dir.exists():
        return patterns

    try:
        session_files = sorted(sessions_dir.glob("*.json"), key=lambda p: p.stat().st_mtime, reverse=True)

        for session_file in session_files[:limit]:
            try:
                data = json.loads(session_file.read_text())
                recent_outputs = data.get("recent_outputs", [])

                for output in recent_outputs:
                    pattern = _extract_work_pattern([output])
                    if pattern:
                        patterns[pattern] = patterns.get(pattern, 0) + 1
            except (json.JSONDecodeError, OSError):
                continue
    except OSError:
        pass

    return patterns
