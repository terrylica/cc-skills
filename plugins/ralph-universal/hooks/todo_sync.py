"""TodoWrite synchronization for Ralph autonomous loop.

Generates TodoWrite-compatible payloads from Ralph session state,
enabling users to see loop progress in Claude Code's todo list.

JSON state remains the single source of truth (authoritative data).
TodoWrite is a mirror for user visibility only.
"""

from typing import Any

from core.constants import (
    ROUND_ADVERSARIAL,
    ROUND_DOCUMENTATION,
    ROUND_ROBUSTNESS,
    ROUND_VERIFICATION,
    TODO_CONTENT_MAX_LENGTH,
)


def generate_todo_items(state: dict) -> list[dict[str, Any]]:
    """Generate TodoWrite-compatible items from Ralph session state.

    Args:
        state: Ralph session state dict with iteration, validation_round, etc.

    Returns:
        List of todo items ready for TodoWrite, each with:
        - content: Imperative form (e.g., "Complete validation round 1")
        - status: pending, in_progress, or completed
        - activeForm: Present continuous form (e.g., "Completing round 1")
    """
    items: list[dict[str, Any]] = []
    iteration = state.get("iteration", 0)
    validation_round = state.get("validation_round", 0)
    validation_findings = state.get("validation_findings", {})

    # Current iteration (always in_progress during loop)
    current_work = state.get("current_work_item", "autonomous improvement")
    items.append({
        "content": f"Ralph Iteration {iteration}: {current_work}",
        "status": "in_progress",
        "activeForm": f"Executing iteration {iteration}",
    })

    # Validation rounds (5-round system)
    round_names = [
        ("Round 1: Critical Issues", "Checking critical issues"),
        ("Round 2: Verification", "Verifying fixes"),
        ("Round 3: Documentation", "Checking documentation"),
        ("Round 4: Adversarial Probing", "Running adversarial tests"),
        ("Round 5: Cross-Period Robustness", "Testing regime robustness"),
    ]

    for i, (name, active_form) in enumerate(round_names, 1):
        round_key = f"round{i}"
        round_data = validation_findings.get(round_key, {})

        # Determine round status
        if validation_round > i:
            # Past rounds are completed
            status = "completed"
        elif validation_round == i:
            # Current round is in progress
            status = "in_progress"
        else:
            # Future rounds are pending
            status = "pending"

        # Check if round has issues (affects display)
        has_issues = _round_has_issues(i, round_data)
        if has_issues and status == "completed":
            # Round completed but has issues to report
            name = f"{name} (issues found)"

        items.append({
            "content": f"Validation {name}",
            "status": status,
            "activeForm": active_form,
        })

    return items


def _round_has_issues(round_num: int, round_data: dict) -> bool:
    """Check if a validation round has any issues.

    Args:
        round_num: Round number (1-5)
        round_data: Data for this round from validation_findings

    Returns:
        True if round has issues, False otherwise
    """
    if round_num == 1:
        return bool(round_data.get("critical", []))
    elif round_num == ROUND_VERIFICATION:
        return bool(round_data.get("failed", []))
    elif round_num == ROUND_DOCUMENTATION:
        return bool(round_data.get("doc_issues", []) or round_data.get("coverage_gaps", []))
    elif round_num == ROUND_ADVERSARIAL:
        return bool(round_data.get("edge_cases_failed", []))
    elif round_num == ROUND_ROBUSTNESS:
        return round_data.get("robustness_score", 0.0) <= 0.0
    return False


def format_todo_instruction(items: list[dict[str, Any]]) -> str:
    """Format todo items as a prompt instruction for Claude.

    Generates a compact instruction that Claude can follow to update
    the todo list with current Ralph state.

    Args:
        items: List of todo items from generate_todo_items()

    Returns:
        Formatted instruction string for the continuation prompt
    """
    if not items:
        return ""

    lines = ["**TODO SYNC**: Update your todo list to reflect Ralph state:"]

    for item in items:
        status_icon = {
            "completed": "✓",
            "in_progress": "→",
            "pending": "○",
        }.get(item["status"], "○")

        lines.append(f"  {status_icon} [{item['status']}] {item['content']}")

    lines.append("")
    lines.append("Use TodoWrite to sync these items (JSON state is authoritative).")

    return "\n".join(lines)


def get_compact_status(state: dict) -> str:
    """Get a compact one-line status for display.

    Args:
        state: Ralph session state dict

    Returns:
        Compact status string like "Iter 15 | V:1/5 | Working on feature X"
    """
    iteration = state.get("iteration", 0)
    validation_round = state.get("validation_round", 0)
    current_work = state.get("current_work_item", "autonomous")

    # Truncate work item if too long
    if len(current_work) > TODO_CONTENT_MAX_LENGTH:
        current_work = current_work[:TODO_CONTENT_MAX_LENGTH - 3] + "..."

    if validation_round > 0:
        return f"Iter {iteration} | Validation {validation_round}/5 | {current_work}"
    else:
        return f"Iter {iteration} | {current_work}"
