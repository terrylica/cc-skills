"""Alpha Forge SLO Work Policy Engine.

ADR: /docs/adr/2025-12-20-ralph-rssi-eternal-loop.md

Priority classification and escalation triggers for SLO-aligned work.
Determines which work items are P0/P1/P2 and when to escalate to experts.

Priority levels:
- P0: ROADMAP.md items (current phase)
- P1: Feature development (new plugins, DSL, CLI)
- P2: Architecture improvements
- BLOCKED: Style/linter work (soft-skipped via alpha_forge_filter)

Escalation triggers:
- New architectural patterns
- Cross-package changes
- >200 lines without approval
- Work not in ROADMAP.md
"""

from __future__ import annotations

import re
from dataclasses import dataclass, field
from enum import Enum
from pathlib import Path


class Priority(Enum):
    """Work item priority levels."""

    P0 = 0  # ROADMAP items (highest)
    P1 = 1  # Feature development
    P2 = 2  # Architecture improvements
    BLOCKED = 99  # Busywork (soft-skip)


class EscalationReason(Enum):
    """Reasons to escalate to expert consultation."""

    NEW_PATTERN = "new_architectural_pattern"
    CROSS_PACKAGE = "cross_package_changes"
    LARGE_CHANGE = "over_200_lines"
    OFF_ROADMAP = "work_not_in_roadmap"
    DESIGN_REQUIRED = "design_review_required"


@dataclass
class WorkItem:
    """A unit of work parsed from ROADMAP.md or discovered."""

    title: str
    priority: Priority
    source: str  # "roadmap", "discovered", "expert"
    phase: str | None = None  # e.g., "2.0", "3.1"
    section: str | None = None  # e.g., "Developer Experience (P0)"
    completed: bool = False
    raw_text: str = ""


@dataclass
class EscalationCheck:
    """Result of checking if work needs escalation."""

    should_escalate: bool
    reasons: list[EscalationReason] = field(default_factory=list)
    message: str = ""


# Patterns that indicate feature work (P1)
FEATURE_PATTERNS: list[str] = [
    r"new plugin",
    r"add plugin",
    r"create plugin",
    r"new feature",
    r"implement feature",
    r"new command",
    r"add command",
    r"cli enhancement",
    r"dsl enhancement",
]

# Patterns that indicate architecture work (P2)
ARCHITECTURE_PATTERNS: list[str] = [
    r"refactor",
    r"restructure",
    r"migrate",
    r"redesign",
    r"architecture",
    r"infrastructure",
    r"foundation",
]

# Patterns that indicate blocked work (filter via alpha_forge_filter)
BLOCKED_PATTERNS: list[str] = [
    r"fix ruff",
    r"fix lint",
    r"type annotation",
    r"docstring",
    r"import sort",
    r"format",
    r"style",
]

# Cross-package indicators (trigger escalation)
CROSS_PACKAGE_PATHS: list[str] = [
    "alpha-forge-core",
    "alpha-forge-shared",
    "alpha-forge-middlefreq",
    "packages/",
]


def classify_priority(item_text: str, is_from_roadmap: bool = False) -> Priority:
    """Classify a work item's priority.

    Args:
        item_text: Description of the work item
        is_from_roadmap: Whether this came from ROADMAP.md

    Returns:
        Priority level for the item
    """
    text_lower = item_text.lower()

    # Check for blocked patterns first
    for pattern in BLOCKED_PATTERNS:
        if re.search(pattern, text_lower):
            return Priority.BLOCKED

    # ROADMAP items are P0
    if is_from_roadmap:
        return Priority.P0

    # Check for feature patterns (P1)
    for pattern in FEATURE_PATTERNS:
        if re.search(pattern, text_lower):
            return Priority.P1

    # Check for architecture patterns (P2)
    for pattern in ARCHITECTURE_PATTERNS:
        if re.search(pattern, text_lower):
            return Priority.P2

    # Default to P1 for unknown work
    return Priority.P1


def check_escalation(
    work_item: WorkItem,
    changed_files: list[Path] | None = None,
    lines_changed: int = 0,
    roadmap_items: list[WorkItem] | None = None,
) -> EscalationCheck:
    """Check if work requires escalation to expert consultation.

    Args:
        work_item: The work item being evaluated
        changed_files: List of files that would be changed
        lines_changed: Number of lines changed so far
        roadmap_items: List of items from ROADMAP.md

    Returns:
        EscalationCheck with escalation status and reasons
    """
    reasons: list[EscalationReason] = []
    messages: list[str] = []

    # Check for large changes (>200 lines)
    if lines_changed > 200:
        reasons.append(EscalationReason.LARGE_CHANGE)
        messages.append(f"Change exceeds 200 lines ({lines_changed})")

    # Check for cross-package changes
    if changed_files:
        for file_path in changed_files:
            path_str = str(file_path)
            for cross_pkg in CROSS_PACKAGE_PATHS:
                if cross_pkg in path_str:
                    reasons.append(EscalationReason.CROSS_PACKAGE)
                    messages.append(f"Cross-package change: {file_path}")
                    break
            if EscalationReason.CROSS_PACKAGE in reasons:
                break

    # Check if work is not in ROADMAP
    if roadmap_items is not None and work_item.source != "roadmap":
        # Look for similar items in roadmap
        title_lower = work_item.title.lower()
        found_match = False
        for roadmap_item in roadmap_items:
            if title_lower in roadmap_item.title.lower():
                found_match = True
                break
        if not found_match:
            reasons.append(EscalationReason.OFF_ROADMAP)
            messages.append("Work not found in ROADMAP.md")

    # Check for architectural patterns
    title_lower = work_item.title.lower()
    arch_keywords = ["architecture", "design", "pattern", "restructure", "migrate"]
    if any(kw in title_lower for kw in arch_keywords):
        reasons.append(EscalationReason.NEW_PATTERN)
        messages.append("Potential new architectural pattern")

    return EscalationCheck(
        should_escalate=len(reasons) > 0,
        reasons=reasons,
        message="; ".join(messages) if messages else "No escalation needed",
    )


def sort_by_priority(items: list[WorkItem]) -> list[WorkItem]:
    """Sort work items by priority (P0 first, BLOCKED last).

    Args:
        items: List of work items

    Returns:
        Sorted list with highest priority first
    """
    return sorted(items, key=lambda x: x.priority.value)


def get_next_work_item(
    items: list[WorkItem],
    *,
    skip_blocked: bool = True,
    skip_completed: bool = True,
) -> WorkItem | None:
    """Get the next work item to work on.

    Args:
        items: List of work items
        skip_blocked: Whether to skip BLOCKED items
        skip_completed: Whether to skip completed items

    Returns:
        Next work item or None if all done
    """
    sorted_items = sort_by_priority(items)

    for item in sorted_items:
        if skip_completed and item.completed:
            continue
        if skip_blocked and item.priority == Priority.BLOCKED:
            continue
        return item

    return None


def format_priority_summary(items: list[WorkItem]) -> str:
    """Format a summary of items by priority.

    Args:
        items: List of work items

    Returns:
        Formatted summary string
    """
    counts: dict[str, int] = {p.name: 0 for p in Priority}

    for item in items:
        counts[item.priority.name] += 1

    parts = []
    for priority in Priority:
        if counts[priority.name] > 0:
            parts.append(f"{priority.name}: {counts[priority.name]}")

    return ", ".join(parts) if parts else "No items"
