"""Alpha Forge ROADMAP.md Parser.

ADR: /docs/adr/2025-12-20-ralph-rssi-eternal-loop.md

Parses alpha-forge's ROADMAP.md structure to extract prioritized work items.

ROADMAP.md Structure (verified):
- ### Phase N: Title (In Progress|Complete)
- #### N.M Subsection Title [🆕|**Status**]
- Priority markers: (P0), (P1), (P2)
- Status: ✅ (complete), 🆕 (current), In Progress, Planned

Priority order:
1. 🆕 items (current priority)
2. **Status**: In progress
3. P0 items within current phase
4. P1 items within current phase
5. P2 items within current phase
6. Next phase items

Fallback cascade (if ROADMAP.md not found):
1. TODO.md
2. .claude/plans/*.md
"""

from __future__ import annotations

import re
from dataclasses import dataclass
from pathlib import Path

from core.constants import MAX_PRIORITY_VALUE
from work_policy import Priority, WorkItem


@dataclass
class Phase:
    """A phase from ROADMAP.md."""

    number: str  # e.g., "2", "3"
    title: str  # e.g., "Integration & Management"
    status: str  # "In Progress", "Complete", "Planned"
    subsections: list[Subsection]


@dataclass
class Subsection:
    """A subsection within a phase."""

    number: str  # e.g., "2.0", "2.1"
    title: str  # e.g., "Capability System Polish"
    is_current: bool  # Has 🆕 marker
    is_in_progress: bool  # Has **Status**: In progress
    priority_items: list[WorkItem]


def parse_roadmap(project_dir: Path) -> list[WorkItem]:
    """Parse ROADMAP.md into prioritized work items.

    Uses fallback cascade if ROADMAP.md not found:
    1. TODO.md
    2. .claude/plans/*.md

    Args:
        project_dir: Path to project root

    Returns:
        List of WorkItem sorted by priority
    """
    # Try ROADMAP.md first
    roadmap_path = project_dir / "ROADMAP.md"
    if roadmap_path.exists():
        return _parse_roadmap_file(roadmap_path)

    # Fallback 1: TODO.md
    todo_path = project_dir / "TODO.md"
    if todo_path.exists():
        return _parse_todo_file(todo_path)

    # Fallback 2: .claude/plans/*.md
    plans_dir = project_dir / ".claude" / "plans"
    if plans_dir.exists():
        plan_files = sorted(plans_dir.glob("*.md"), reverse=True)
        if plan_files:
            return _parse_plan_file(plan_files[0])

    return []


def _parse_roadmap_file(roadmap_path: Path) -> list[WorkItem]:
    """Parse alpha-forge ROADMAP.md format.

    Expected structure:
    ### Phase N: Title (Status)
    #### N.M Subsection Title 🆕
    **Priority** (P0):
    - Item 1
    - Item 2
    """
    content = roadmap_path.read_text()
    items: list[WorkItem] = []

    # Phase pattern: ### Phase N: Title (Status)
    phase_pattern = r"^### Phase (\d+): (.+?)(?:\s*\(([^)]+)\))?\s*$"

    # Subsection pattern: #### N.M Title [🆕]
    subsection_pattern = r"^#### (\d+\.\d+) (.+?)(?:\s*(🆕))?\s*$"

    # Priority section pattern: **Title** (P0):
    priority_pattern = r"\*\*([^*]+)\*\*\s*\(P(\d)\):"

    # Status pattern: **Status**: Value
    status_pattern = r"\*\*Status\*\*:\s*(.+)"

    current_phase: str | None = None
    current_subsection: str | None = None
    current_priority: Priority = Priority.P1
    is_current_section = False
    is_in_progress = False

    for line in content.split("\n"):
        # Check for phase header
        phase_match = re.match(phase_pattern, line)
        if phase_match:
            current_phase = phase_match.group(1)
            phase_status = phase_match.group(3) or ""
            # Skip complete phases
            if "complete" in phase_status.lower():
                current_phase = None
            continue

        # Skip if no active phase
        if current_phase is None:
            continue

        # Check for subsection header
        subsection_match = re.match(subsection_pattern, line)
        if subsection_match:
            current_subsection = subsection_match.group(1)
            is_current_section = subsection_match.group(3) == "🆕"
            is_in_progress = False
            current_priority = Priority.P0 if is_current_section else Priority.P1
            continue

        # Check for status line
        status_match = re.search(status_pattern, line)
        if status_match:
            status_val = status_match.group(1).lower()
            is_in_progress = "in progress" in status_val or "next" in status_val
            continue

        # Check for priority section header
        priority_match = re.search(priority_pattern, line)
        if priority_match:
            p_num = int(priority_match.group(2))
            current_priority = Priority(p_num) if p_num <= MAX_PRIORITY_VALUE else Priority.P2
            continue

        # Check for list items (potential work items)
        if line.strip().startswith("- "):
            item_text = line.strip()[2:].strip()

            # Skip completed items (✅ or [x])
            if "✅" in item_text or item_text.startswith("[x]"):
                continue

            # Skip items that are just status markers
            if item_text.startswith("**Status**"):
                continue

            # Boost priority for current section
            item_priority = current_priority
            if is_current_section or is_in_progress:
                item_priority = Priority.P0

            items.append(
                WorkItem(
                    title=item_text,
                    priority=item_priority,
                    source="roadmap",
                    phase=current_subsection or current_phase,
                    section=current_subsection,
                    raw_text=line,
                )
            )

    # Sort by priority
    return sorted(items, key=lambda x: x.priority.value)


def _parse_todo_file(todo_path: Path) -> list[WorkItem]:
    """Parse simple TODO.md format.

    Expected: List of - [ ] items or - items
    """
    content = todo_path.read_text()
    items: list[WorkItem] = []

    for line in content.split("\n"):
        line = line.strip()

        # Skip completed items
        if line.startswith("- [x]"):
            continue

        # Unchecked checkbox items
        if line.startswith("- [ ]"):
            item_text = line[5:].strip()
            items.append(
                WorkItem(
                    title=item_text,
                    priority=Priority.P1,
                    source="todo",
                    raw_text=line,
                )
            )
        # Plain list items
        elif line.startswith("- "):
            item_text = line[2:].strip()
            items.append(
                WorkItem(
                    title=item_text,
                    priority=Priority.P1,
                    source="todo",
                    raw_text=line,
                )
            )

    return items


def _parse_plan_file(plan_path: Path) -> list[WorkItem]:
    """Parse .claude/plans/*.md format.

    Expected: Checkbox items or numbered lists
    """
    content = plan_path.read_text()
    items: list[WorkItem] = []

    for line in content.split("\n"):
        line = line.strip()

        # Skip completed items
        if line.startswith("- [x]") or "✅" in line:
            continue

        # Unchecked checkbox items
        if line.startswith("- [ ]"):
            item_text = line[5:].strip()
            items.append(
                WorkItem(
                    title=item_text,
                    priority=Priority.P0,  # Plan items are P0
                    source="plan",
                    raw_text=line,
                )
            )
        # Numbered items (1. Item)
        elif re.match(r"^\d+\.\s+", line):
            item_text = re.sub(r"^\d+\.\s+", "", line)
            items.append(
                WorkItem(
                    title=item_text,
                    priority=Priority.P0,
                    source="plan",
                    raw_text=line,
                )
            )

    return items


def get_current_phase(project_dir: Path) -> str | None:
    """Get the current active phase from ROADMAP.md.

    Args:
        project_dir: Path to project root

    Returns:
        Phase string (e.g., "2.0") or None
    """
    items = parse_roadmap(project_dir)
    if items:
        # Return the phase of the first P0 item
        p0_items = [i for i in items if i.priority == Priority.P0]
        if p0_items:
            return p0_items[0].phase
    return None


def get_phase_progress(project_dir: Path) -> dict[str, int]:
    """Get completion progress for current phase.

    Args:
        project_dir: Path to project root

    Returns:
        Dict with 'total', 'completed', 'remaining' counts
    """
    roadmap_path = project_dir / "ROADMAP.md"
    if not roadmap_path.exists():
        return {"total": 0, "completed": 0, "remaining": 0}

    content = roadmap_path.read_text()

    # Count checkboxes in current phase section
    total = content.count("- [ ]") + content.count("- [x]")
    completed = content.count("- [x]") + content.count("✅")

    return {
        "total": total,
        "completed": completed,
        "remaining": total - completed,
    }
