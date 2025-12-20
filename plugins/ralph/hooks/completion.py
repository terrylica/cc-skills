"""Completion detection functions for Ralph hook.

Provides multi-signal completion detection (RSSI-grade) that works
with any file format (ADRs, specs, plans) without requiring explicit markers.
"""
import logging
from pathlib import Path

logger = logging.getLogger(__name__)

# Completion detection constants
COMPLETION_CONFIDENCE_THRESHOLD = 0.7
COMPLETION_PHRASES = [
    "task complete", "all done", "finished",
    "implementation complete", "work complete"
]


def has_frontmatter_value(content: str, key: str, value: str) -> bool:
    """Check if markdown has YAML frontmatter with specific key: value.

    Args:
        content: Markdown file content
        key: Frontmatter key to check
        value: Expected value

    Returns:
        True if frontmatter contains key: value
    """
    lines = content.split('\n')
    if not lines or lines[0].strip() != '---':
        return False

    for line in lines[1:]:
        if line.strip() == '---':
            break
        # Match: "key: value" or "key: 'value'" or 'key: "value"'
        if line.startswith(f"{key}:"):
            line_value = line.split(':', 1)[1].strip()
            # Remove quotes
            line_value = line_value.strip('"').strip("'")
            if line_value == value:
                return True
    return False


def has_explicit_completion_marker(content: str) -> bool:
    """Check for explicit TASK_COMPLETE markers in content.

    Supports multiple checkbox formats:
    - [x] TASK_COMPLETE
    - [X] TASK_COMPLETE
    - - [x] TASK_COMPLETE
    - * [x] TASK_COMPLETE
    """
    for line in content.split('\n'):
        line_stripped = line.strip()
        if any([
            line_stripped in ('- [x] TASK_COMPLETE', '[x] TASK_COMPLETE'),
            line_stripped in ('* [x] TASK_COMPLETE', '[X] TASK_COMPLETE'),
            'TASK_COMPLETE' in line_stripped and '[x]' in line_stripped.lower(),
        ]):
            return True
    return False


def count_checkboxes(content: str) -> tuple[int, int]:
    """Count total and checked checkboxes in content.

    Args:
        content: Markdown file content

    Returns:
        (total, checked) - number of checkboxes found and how many are checked
    """
    total = 0
    checked = 0
    for line in content.split('\n'):
        line_stripped = line.strip()
        # Match unchecked: - [ ] or * [ ]
        if line_stripped.startswith('- [ ]') or line_stripped.startswith('* [ ]'):
            total += 1
        # Match checked: - [x] or * [x] or - [X] or * [X]
        elif (line_stripped.startswith('- [x]') or line_stripped.startswith('* [x]') or
              line_stripped.startswith('- [X]') or line_stripped.startswith('* [X]')):
            total += 1
            checked += 1
    return total, checked


def check_task_complete(plan_file: str | None) -> tuple[bool, str]:
    """Check for completion via frontmatter status OR checklist markers.

    Legacy function - use check_task_complete_rssi for multi-signal detection.

    Returns:
        (is_complete, reason) - reason describes how completion was detected
    """
    if not plan_file or not Path(plan_file).exists():
        return False, "no file to check"
    try:
        content = Path(plan_file).read_text()

        # Method 1: YAML frontmatter status field
        if has_frontmatter_value(content, "implementation-status", "completed"):
            return True, "implementation-status: completed"
        if has_frontmatter_value(content, "implementation-status", "complete"):
            return True, "implementation-status: complete"

        # Method 2: Checklist markers (flexible formats)
        for line in content.split('\n'):
            line_stripped = line.strip()
            if any([
                line_stripped in ('- [x] TASK_COMPLETE', '[x] TASK_COMPLETE'),
                line_stripped in ('* [x] TASK_COMPLETE', '[X] TASK_COMPLETE'),
                'TASK_COMPLETE' in line_stripped and ('[x]' in line_stripped.lower()),
            ]):
                return True, "checklist: TASK_COMPLETE"
    except OSError:
        pass
    return False, "not complete"


def check_task_complete_rssi(plan_file: str | None) -> tuple[bool, str, float]:
    """RSSI-grade completion detection using multiple signals.

    Analyzes the plan file using 5 different signals to detect completion,
    returning the highest confidence match.

    Signals:
    1. Explicit marker ([x] TASK_COMPLETE) - confidence 1.0
    2. Frontmatter status (implementation-status: completed) - confidence 0.95
    3. All checkboxes checked - confidence 0.9
    4. No pending items (has [x] but no [ ]) - confidence 0.85
    5. Semantic phrases ("task complete", "all done") - confidence 0.7

    Args:
        plan_file: Path to the plan/task file

    Returns:
        (is_complete, reason, confidence) - confidence is 0.0-1.0
    """
    if not plan_file or not Path(plan_file).exists():
        return False, "no file to check", 0.0

    try:
        content = Path(plan_file).read_text()
    except OSError:
        return False, "file read error", 0.0

    signals: list[tuple[str, float]] = []

    # Signal 1: Explicit markers (high confidence)
    if has_explicit_completion_marker(content):
        signals.append(("explicit_marker", 1.0))

    # Signal 2: YAML frontmatter status fields
    if has_frontmatter_value(content, "implementation-status", "completed"):
        signals.append(("frontmatter_completed", 0.95))
    if has_frontmatter_value(content, "implementation-status", "complete"):
        signals.append(("frontmatter_complete", 0.95))
    if has_frontmatter_value(content, "status", "implemented"):
        signals.append(("adr_implemented", 0.95))

    # Signal 3: Checklist analysis - all items checked
    total, checked = count_checkboxes(content)
    if total > 0 and checked == total:
        signals.append(("all_checkboxes_checked", 0.9))

    # Signal 4: Semantic completion phrases
    content_lower = content.lower()
    if any(phrase in content_lower for phrase in COMPLETION_PHRASES):
        signals.append(("semantic_phrase", 0.7))

    # Signal 5: No unchecked items remain (but has checked items)
    if "[ ]" not in content and "[x]" in content.lower():
        signals.append(("no_pending_items", 0.85))

    # Return highest confidence signal
    if signals:
        best = max(signals, key=lambda x: x[1])
        logger.info(f"Completion detected via {best[0]} with confidence {best[1]}")
        return True, best[0], best[1]

    return False, "not_complete", 0.0
