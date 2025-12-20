# /// script
# requires-python = ">=3.11"
# dependencies = []
# ///
"""Unit tests for completion.py - Multi-signal completion detection."""

import sys
import tempfile
from pathlib import Path

# Add parent directory to path for imports
sys.path.insert(0, str(Path(__file__).parent.parent))

from completion import (
    COMPLETION_CONFIDENCE_THRESHOLD,
    check_task_complete_rssi,
    count_checkboxes,
    has_explicit_completion_marker,
    has_frontmatter_value,
)


def test_explicit_marker():
    """Test explicit TASK_COMPLETE marker detection."""
    content_with_marker = """
# My Task

- [x] Step 1
- [x] Step 2
- [x] TASK_COMPLETE
"""
    content_without = """
# My Task

- [x] Step 1
- [ ] Step 2
"""
    assert has_explicit_completion_marker(content_with_marker) is True
    assert has_explicit_completion_marker(content_without) is False
    print("✓ test_explicit_marker passed")


def test_count_checkboxes():
    """Test checkbox counting."""
    content = """
- [x] Done 1
- [x] Done 2
- [ ] Not done
- [X] Done 3 (uppercase)
"""
    total, checked = count_checkboxes(content)
    assert total == 4, f"Expected 4 total, got {total}"
    assert checked == 3, f"Expected 3 checked, got {checked}"
    print("✓ test_count_checkboxes passed")


def test_frontmatter_detection():
    """Test YAML frontmatter parsing."""
    content_with_status = """---
title: My Task
implementation-status: completed
---

# Task content
"""
    content_in_progress = """---
implementation-status: in_progress
---

# Still working
"""
    assert has_frontmatter_value(content_with_status, "implementation-status", "completed") is True
    assert has_frontmatter_value(content_in_progress, "implementation-status", "completed") is False
    print("✓ test_frontmatter_detection passed")


def create_temp_file(content: str) -> str:
    """Create a temporary file with given content and return its path."""
    with tempfile.NamedTemporaryFile(mode="w", suffix=".md", delete=False) as f:
        f.write(content)
        return f.name


def test_multi_signal_detection():
    """Test complete RSSI detection with multiple signals."""
    # Test 1: Explicit marker (confidence 1.0)
    explicit = "- [x] TASK_COMPLETE"
    temp_file = create_temp_file(explicit)
    try:
        complete, reason, conf = check_task_complete_rssi(temp_file)
        assert complete is True
        assert conf == 1.0
        assert reason == "explicit_marker"
        print(f"✓ Explicit marker: {reason} (conf={conf})")
    finally:
        Path(temp_file).unlink()

    # Test 2: All checkboxes checked (confidence 0.9)
    all_checked = """
- [x] Step 1
- [x] Step 2
- [x] Step 3
"""
    temp_file = create_temp_file(all_checked)
    try:
        complete, reason, conf = check_task_complete_rssi(temp_file)
        assert complete is True
        assert conf == 0.9
        assert reason == "all_checkboxes_checked"
        print(f"✓ All checkboxes: {reason} (conf={conf})")
    finally:
        Path(temp_file).unlink()

    # Test 3: Semantic phrase (confidence 0.7)
    semantic = "The task is now complete and all done."
    temp_file = create_temp_file(semantic)
    try:
        complete, reason, conf = check_task_complete_rssi(temp_file)
        assert complete is True
        assert conf == 0.7
        assert reason == "semantic_phrase"
        print(f"✓ Semantic phrase: {reason} (conf={conf})")
    finally:
        Path(temp_file).unlink()

    # Test 4: Incomplete (unchecked items)
    incomplete = """
- [x] Step 1
- [ ] Step 2
"""
    temp_file = create_temp_file(incomplete)
    try:
        complete, reason, conf = check_task_complete_rssi(temp_file)
        assert complete is False
        assert conf == 0.0
        print(f"✓ Incomplete: {reason} (conf={conf})")
    finally:
        Path(temp_file).unlink()

    # Test 5: No file
    complete, reason, conf = check_task_complete_rssi(None)
    assert complete is False
    assert reason == "no file to check"
    print(f"✓ No file: {reason}")


def test_confidence_threshold():
    """Verify threshold constant."""
    assert COMPLETION_CONFIDENCE_THRESHOLD == 0.7
    print(f"✓ Confidence threshold: {COMPLETION_CONFIDENCE_THRESHOLD}")


if __name__ == "__main__":
    print("=" * 60)
    print("Running completion.py unit tests")
    print("=" * 60)

    test_explicit_marker()
    test_count_checkboxes()
    test_frontmatter_detection()
    test_multi_signal_detection()
    test_confidence_threshold()

    print("=" * 60)
    print("All completion tests passed!")
    print("=" * 60)
