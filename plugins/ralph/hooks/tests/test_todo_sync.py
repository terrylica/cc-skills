# /// script
# requires-python = ">=3.11"
# dependencies = []
# ///
"""Unit tests for todo_sync.py - TodoWrite synchronization."""

import sys
from pathlib import Path

# Add parent directory to path for imports
sys.path.insert(0, str(Path(__file__).parent.parent))

from todo_sync import (
    format_todo_instruction,
    generate_todo_items,
    get_compact_status,
)


def test_generate_todo_items_basic():
    """Test basic todo item generation."""
    state = {
        "iteration": 5,
        "validation_round": 0,
        "validation_findings": {},
    }
    items = generate_todo_items(state)

    # Should have 1 iteration item + 5 validation round items
    assert len(items) == 6, f"Expected 6 items, got {len(items)}"

    # First item should be current iteration
    assert items[0]["status"] == "in_progress"
    assert "Iteration 5" in items[0]["content"]
    print("✓ Basic todo generation works")


def test_generate_todo_items_with_validation():
    """Test todo generation during validation phase."""
    state = {
        "iteration": 10,
        "validation_round": 3,  # Currently on round 3
        "validation_findings": {
            "round1": {"critical": [], "medium": [], "low": []},
            "round2": {"verified": ["fix1"], "failed": []},
            "round3": {"doc_issues": [], "coverage_gaps": []},
            "round4": {"probing_complete": False, "edge_cases_failed": []},
            "round5": {"regimes_tested": [], "robustness_score": 0.0},
        },
    }
    items = generate_todo_items(state)

    # Check validation round statuses
    # Round 1 and 2 should be completed (before current round 3)
    round1_item = next(i for i in items if "Round 1" in i["content"])
    round2_item = next(i for i in items if "Round 2" in i["content"])
    round3_item = next(i for i in items if "Round 3" in i["content"])
    round4_item = next(i for i in items if "Round 4" in i["content"])
    round5_item = next(i for i in items if "Round 5" in i["content"])

    assert round1_item["status"] == "completed"
    assert round2_item["status"] == "completed"
    assert round3_item["status"] == "in_progress"  # Current round
    assert round4_item["status"] == "pending"
    assert round5_item["status"] == "pending"
    print("✓ Validation round statuses correct")


def test_generate_todo_items_with_issues():
    """Test todo generation when rounds have issues."""
    state = {
        "iteration": 15,
        "validation_round": 2,
        "validation_findings": {
            "round1": {"critical": ["error1", "error2"], "medium": [], "low": []},
            "round2": {"verified": [], "failed": []},
        },
    }
    items = generate_todo_items(state)

    # Round 1 should show issues found
    round1_item = next(i for i in items if "Round 1" in i["content"])
    assert "issues found" in round1_item["content"]
    print("✓ Issues detection works")


def test_format_todo_instruction():
    """Test formatting todo items as prompt instruction."""
    items = [
        {"content": "Task 1", "status": "completed", "activeForm": "Doing task 1"},
        {"content": "Task 2", "status": "in_progress", "activeForm": "Doing task 2"},
        {"content": "Task 3", "status": "pending", "activeForm": "Doing task 3"},
    ]
    instruction = format_todo_instruction(items)

    assert "TODO SYNC" in instruction
    assert "✓" in instruction  # Completed icon
    assert "→" in instruction  # In progress icon
    assert "○" in instruction  # Pending icon
    assert "[completed]" in instruction
    assert "[in_progress]" in instruction
    assert "[pending]" in instruction
    print("✓ Todo instruction formatting works")


def test_format_todo_instruction_empty():
    """Test formatting with empty items."""
    instruction = format_todo_instruction([])
    assert instruction == ""
    print("✓ Empty items returns empty string")


def test_get_compact_status():
    """Test compact status generation."""
    state = {
        "iteration": 25,
        "validation_round": 0,
        "current_work_item": "Improving Sharpe ratio",
    }
    status = get_compact_status(state)
    assert "Iter 25" in status
    assert "Sharpe ratio" in status
    print("✓ Compact status without validation works")


def test_get_compact_status_with_validation():
    """Test compact status during validation."""
    state = {
        "iteration": 30,
        "validation_round": 4,
        "current_work_item": "Edge case testing",
    }
    status = get_compact_status(state)
    assert "Iter 30" in status
    assert "Validation 4/5" in status
    print("✓ Compact status with validation works")


def test_get_compact_status_truncation():
    """Test that long work items are truncated."""
    state = {
        "iteration": 1,
        "validation_round": 0,
        "current_work_item": "This is a very long work item description that should be truncated",
    }
    status = get_compact_status(state)
    assert "..." in status
    assert len(status) < 100  # Reasonable length
    print("✓ Long work items truncated correctly")


if __name__ == "__main__":
    print("=" * 60)
    print("Running todo_sync.py unit tests")
    print("=" * 60)

    test_generate_todo_items_basic()
    test_generate_todo_items_with_validation()
    test_generate_todo_items_with_issues()
    test_format_todo_instruction()
    test_format_todo_instruction_empty()
    test_get_compact_status()
    test_get_compact_status_with_validation()
    test_get_compact_status_truncation()

    print("=" * 60)
    print("All todo_sync tests passed!")
    print("=" * 60)
