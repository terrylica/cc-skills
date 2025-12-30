# /// script
# requires-python = ">=3.11"
# dependencies = ["pydantic>=2.10.0", "filelock>=3.20.0"]
# ///
"""Unit tests for completion.py - Multi-signal completion detection."""

import sys
import tempfile
from pathlib import Path

# Add parent directory to path for imports
sys.path.insert(0, str(Path(__file__).parent.parent))

from completion import (
    check_task_complete_ralph,
    check_validation_complete,
    count_checkboxes,
    get_completion_config,
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
    """Test complete Ralph (RSSI) detection with multiple signals."""
    # Test 1: Explicit marker (confidence 1.0)
    explicit = "- [x] TASK_COMPLETE"
    temp_file = create_temp_file(explicit)
    try:
        complete, reason, conf = check_task_complete_ralph(temp_file)
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
        complete, reason, conf = check_task_complete_ralph(temp_file)
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
        complete, reason, conf = check_task_complete_ralph(temp_file)
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
        complete, reason, conf = check_task_complete_ralph(temp_file)
        assert complete is False
        assert conf == 0.0
        print(f"✓ Incomplete: {reason} (conf={conf})")
    finally:
        Path(temp_file).unlink()

    # Test 5: No file
    complete, reason, conf = check_task_complete_ralph(None)
    assert complete is False
    assert reason == "no file to check"
    print(f"✓ No file: {reason}")


def test_confidence_threshold():
    """Verify config-based confidence thresholds."""
    cfg = get_completion_config()
    # Semantic phrases should have reasonable confidence
    assert 0.5 <= cfg.semantic_phrases_confidence <= 1.0
    # Explicit markers should have highest confidence
    assert cfg.explicit_marker_confidence == 1.0
    print(f"✓ Semantic phrases confidence: {cfg.semantic_phrases_confidence}")
    print(f"✓ Explicit marker confidence: {cfg.explicit_marker_confidence}")


def test_validation_complete():
    """Test 5-round validation completion check."""
    # Test 1: All rounds pass (empty findings)
    empty_findings = {
        "round1": {"critical": [], "medium": [], "low": []},
        "round2": {"verified": ["fix1"], "failed": []},
        "round3": {"doc_issues": [], "coverage_gaps": []},
        "round4": {"edge_cases_tested": ["test1"], "edge_cases_failed": [], "probing_complete": True},
        "round5": {"regimes_tested": ["bull", "bear"], "regime_results": {}, "robustness_score": 0.75},
    }
    all_passed, summary, incomplete = check_validation_complete(empty_findings)
    assert all_passed is True, f"Expected all passed, got {incomplete}"
    assert summary == "All 5 validation rounds passed"
    print("✓ All rounds pass: correct")

    # Test 2: Round 1 fails (critical issues)
    round1_fail = {
        "round1": {"critical": ["error1"], "medium": [], "low": []},
        "round2": {"verified": [], "failed": []},
        "round3": {"doc_issues": [], "coverage_gaps": []},
        "round4": {"probing_complete": True, "edge_cases_failed": []},
        "round5": {"regimes_tested": ["bull"], "robustness_score": 0.5},
    }
    all_passed, summary, incomplete = check_validation_complete(round1_fail)
    assert all_passed is False
    assert summary == "4/5 rounds passed"
    print("✓ Round 1 fails: correct")

    # Test 3: Round 4 has BOTH issues (probing incomplete AND edge case failures)
    # This tests the bug fix: should count as 1 failed round, not 2
    round4_both_issues = {
        "round1": {"critical": [], "medium": [], "low": []},
        "round2": {"verified": [], "failed": []},
        "round3": {"doc_issues": [], "coverage_gaps": []},
        "round4": {"probing_complete": False, "edge_cases_failed": ["case1"]},  # BOTH issues
        "round5": {"regimes_tested": ["bull"], "robustness_score": 0.5},
    }
    all_passed, summary, incomplete = check_validation_complete(round4_both_issues)
    assert all_passed is False
    # Key test: should be 4/5 (only round 4 failed), NOT 3/5 (2 issues but 1 round)
    assert summary == "4/5 rounds passed", f"Expected '4/5 rounds passed', got '{summary}'"
    assert len(incomplete) == 2  # 2 issue descriptions
    print("✓ Round 4 both issues: correctly counts as 1 failed round")

    # Test 4: Multiple rounds fail
    multi_fail = {
        "round1": {"critical": ["err"], "medium": [], "low": []},
        "round2": {"verified": [], "failed": ["fix1"]},
        "round3": {"doc_issues": [], "coverage_gaps": []},
        "round4": {"probing_complete": True, "edge_cases_failed": []},
        "round5": {"regimes_tested": [], "robustness_score": 0.0},  # BOTH issues
    }
    all_passed, summary, incomplete = check_validation_complete(multi_fail)
    assert all_passed is False
    # Rounds 1, 2, 5 fail = 2/5 pass
    assert summary == "2/5 rounds passed", f"Expected '2/5 rounds passed', got '{summary}'"
    print("✓ Multiple rounds fail: correct")


if __name__ == "__main__":
    print("=" * 60)
    print("Running completion.py unit tests")
    print("=" * 60)

    test_explicit_marker()
    test_count_checkboxes()
    test_frontmatter_detection()
    test_multi_signal_detection()
    test_confidence_threshold()
    test_validation_complete()

    print("=" * 60)
    print("All completion tests passed!")
    print("=" * 60)
