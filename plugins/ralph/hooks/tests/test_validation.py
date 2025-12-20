# /// script
# requires-python = ">=3.11"
# dependencies = []
# ///
"""Unit tests for validation.py - 3-round validation phase."""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent))

from validation import (
    compute_validation_score,
    check_validation_exhausted,
    aggregate_agent_results,
    VALIDATION_SCORE_THRESHOLD,
    MAX_VALIDATION_ITERATIONS,
)


def test_compute_score_perfect():
    """Test perfect validation score (no issues)."""
    state = {
        "validation_findings": {
            "round1": {"critical": [], "medium": [], "low": []},
            "round2": {"verified": [], "failed": []},
            "round3": {"doc_issues": [], "coverage_gaps": []},
        }
    }
    score = compute_validation_score(state)
    assert score == 1.0, f"Expected 1.0, got {score}"
    print(f"✓ Perfect score: {score}")


def test_compute_score_with_issues():
    """Test score with various issues."""
    # Critical issues = 0.5 base only
    state_critical = {
        "validation_findings": {
            "round1": {"critical": ["issue1"], "medium": [], "low": []},
            "round2": {"verified": [], "failed": []},
            "round3": {"doc_issues": [], "coverage_gaps": []},
        }
    }
    score = compute_validation_score(state_critical)
    assert score < 0.8, f"Critical issues should fail threshold, got {score}"
    print(f"✓ Score with critical: {score}")

    # Medium issues only
    state_medium = {
        "validation_findings": {
            "round1": {"critical": [], "medium": ["m1", "m2"], "low": []},
            "round2": {"verified": [], "failed": []},
            "round3": {"doc_issues": [], "coverage_gaps": []},
        }
    }
    score = compute_validation_score(state_medium)
    assert 0.5 <= score < 1.0, f"Medium issues should reduce score, got {score}"
    print(f"✓ Score with medium: {score}")


def test_exhaustion_detection():
    """Test validation exhaustion conditions."""
    # Not exhausted - score too low
    state_low_score = {
        "validation_round": 3,
        "validation_iteration": 1,
        "validation_score": 0.5,
        "validation_exhausted": False,
    }
    assert check_validation_exhausted(state_low_score) is False
    print("✓ Low score not exhausted")

    # Exhausted - score meets threshold
    state_good_score = {
        "validation_round": 3,
        "validation_iteration": 1,
        "validation_score": 0.85,
        "validation_exhausted": False,
    }
    assert check_validation_exhausted(state_good_score) is True
    print("✓ Good score is exhausted")

    # Exhausted - max iterations reached
    state_max_iter = {
        "validation_round": 3,
        "validation_iteration": MAX_VALIDATION_ITERATIONS,
        "validation_score": 0.6,
        "validation_exhausted": False,
    }
    assert check_validation_exhausted(state_max_iter) is True
    print("✓ Max iterations is exhausted")


def test_aggregate_agent_results():
    """Test parsing agent JSON outputs."""
    outputs = [
        '{"findings": [{"severity": "critical", "file": "test.py", "line": 10, "code": "BLE001", "message": "Blind except"}], "success": true}',
        '{"findings": [{"severity": "medium", "file": "readme.md", "line": 5, "message": "Broken link"}], "success": true}',
        "invalid json that should be skipped",
    ]
    result = aggregate_agent_results(outputs)

    assert "critical" in result
    assert "medium" in result
    assert len(result["critical"]) == 1
    assert len(result["medium"]) == 1
    print(f"✓ Aggregated: {len(result['critical'])} critical, {len(result['medium'])} medium")


def test_constants():
    """Verify validation constants."""
    assert VALIDATION_SCORE_THRESHOLD == 0.8
    assert MAX_VALIDATION_ITERATIONS == 3
    print(f"✓ Score threshold: {VALIDATION_SCORE_THRESHOLD}")
    print(f"✓ Max iterations: {MAX_VALIDATION_ITERATIONS}")


if __name__ == "__main__":
    print("=" * 60)
    print("Running validation.py unit tests")
    print("=" * 60)

    test_compute_score_perfect()
    test_compute_score_with_issues()
    test_exhaustion_detection()
    test_aggregate_agent_results()
    test_constants()

    print("=" * 60)
    print("All validation tests passed!")
    print("=" * 60)
