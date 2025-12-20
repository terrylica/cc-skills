# /// script
# requires-python = ">=3.11"
# dependencies = ["rapidfuzz>=3.0.0,<4.0.0", "jinja2>=3.1.0,<4.0.0"]
# ///
"""Integration tests for loop-until-done.py - Full hook simulation."""

import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent))

from completion import check_task_complete_rssi
from discovery import discover_target_file, scan_work_opportunities
from template_loader import get_loader
from utils import detect_loop
from validation import compute_validation_score, check_validation_exhausted


def create_test_plan(tmp_dir: Path, content: str) -> Path:
    """Create a temporary plan file."""
    plans_dir = tmp_dir / ".claude" / "plans"
    plans_dir.mkdir(parents=True, exist_ok=True)
    plan_file = plans_dir / "test-plan.md"
    plan_file.write_text(content)
    return plan_file


def test_full_workflow_incomplete():
    """Test workflow with incomplete task - should continue."""
    with tempfile.TemporaryDirectory() as tmp:
        tmp_dir = Path(tmp)

        # Create incomplete plan
        plan_content = """---
implementation-status: in_progress
---

# Test Task

- [x] Step 1
- [ ] Step 2
- [ ] Step 3
"""
        plan_file = create_test_plan(tmp_dir, plan_content)

        # Check completion
        complete, reason, confidence = check_task_complete_rssi(str(plan_file))
        assert complete is False, "Incomplete task should not be complete"
        print(f"✓ Incomplete task: complete={complete}, reason={reason}")


def test_full_workflow_complete_needs_validation():
    """Test workflow with complete task - should enter validation."""
    with tempfile.TemporaryDirectory() as tmp:
        tmp_dir = Path(tmp)

        plan_content = """---
implementation-status: in_progress
---

# Test Task

- [x] Step 1
- [x] Step 2
- [x] Step 3
"""
        plan_file = create_test_plan(tmp_dir, plan_content)

        # Check completion
        complete, reason, confidence = check_task_complete_rssi(str(plan_file))
        assert complete is True, "All checked should be complete"
        assert confidence == 0.9
        print(f"✓ Complete task: reason={reason}, confidence={confidence}")

        # State should indicate validation needed
        state = {
            "validation_round": 0,
            "validation_iteration": 0,
            "validation_score": 0.0,
            "validation_exhausted": False,
        }
        assert check_validation_exhausted(state) is False
        print("✓ Validation not exhausted - should enter validation phase")

        # Render validation round 1 prompt
        loader = get_loader()
        prompt = loader.render_validation_round(
            1,
            {"validation_findings": {"round1": {"critical": [], "medium": [], "low": []}}},
            {},
        )
        assert "VALIDATION ROUND 1" in prompt
        assert "Linter Agent" in prompt
        print("✓ Validation round 1 prompt generated")


def test_full_workflow_validation_exhausted():
    """Test workflow after validation complete - should enter exploration."""
    state = {
        "validation_round": 3,
        "validation_iteration": 1,
        "validation_score": 0.85,
        "validation_exhausted": False,
        "validation_findings": {
            "round1": {"critical": [], "medium": [], "low": []},
            "round2": {"verified": [], "failed": []},
            "round3": {"doc_issues": [], "coverage_gaps": []},
        },
    }

    # Check exhaustion
    exhausted = check_validation_exhausted(state)
    assert exhausted is True
    print(f"✓ Validation exhausted: score={state['validation_score']}")

    # Render exploration prompt
    loader = get_loader()
    opportunities = ["Fix 2 broken links", "Add README to src/utils/"]
    prompt = loader.render_exploration(opportunities)
    assert "DISCOVERY MODE" in prompt
    assert "Fix 2 broken links" in prompt
    print("✓ Exploration prompt with opportunities generated")


def test_file_discovery_cascade():
    """Test file discovery with various sources."""
    with tempfile.TemporaryDirectory() as tmp:
        tmp_dir = Path(tmp)

        # Create a plan file
        plans_dir = tmp_dir / ".claude" / "plans"
        plans_dir.mkdir(parents=True, exist_ok=True)
        plan_file = plans_dir / "my-task.md"
        plan_file.write_text("# My Task\n\n- [ ] Do something")

        # Test discovery - signature: discover_target_file(transcript_path, project_dir)
        discovered, method, candidates = discover_target_file(
            transcript_path=None,
            project_dir=str(tmp_dir),
        )

        assert discovered is not None
        assert "my-task.md" in discovered
        print(f"✓ Discovered: {discovered} via {method}")


def test_work_opportunity_scanning():
    """Test work opportunity detection."""
    with tempfile.TemporaryDirectory() as tmp:
        tmp_dir = Path(tmp)

        # Create some Python files without README
        src_dir = tmp_dir / "src"
        src_dir.mkdir()
        for i in range(5):
            (src_dir / f"module{i}.py").write_text(f"# Module {i}")

        # Scan for opportunities
        opportunities = scan_work_opportunities(str(tmp_dir))

        # Should find missing README opportunity
        readme_opp = [o for o in opportunities if "README" in o]
        assert len(readme_opp) > 0, "Should detect missing README"
        print(f"✓ Found opportunities: {opportunities}")


def test_loop_detection_integration():
    """Test loop detection with realistic outputs."""
    # Simulated Claude outputs that are too similar
    # detect_loop(current_output, recent_outputs) -> bool
    stuck_recent = [
        "I'll continue working on the validation phase. Let me check the linter results.",
        "I'll continue working on the validation phase. Let me check the linter results.",
        "I'll continue working on the validation phase. Let me check the linter results.",
        "I'll continue working on the validation phase. Let me check the linter results.",
    ]
    stuck_current = "I'll continue working on the validation phase. Let me check the linter results."
    is_loop = detect_loop(stuck_current, stuck_recent)
    assert is_loop is True
    print("✓ Loop detected in stuck outputs")

    # Productive outputs with variation
    productive_recent = [
        "Starting validation round 1 with linter agent.",
        "Linter found 3 issues. Fixing BLE001 in utils.py.",
        "Fixed utils.py. Now checking for broken links.",
        "All links valid. Starting round 2 semantic verification.",
    ]
    productive_current = "Round 2 complete. No regressions found. Moving to round 3."
    is_loop = detect_loop(productive_current, productive_recent)
    assert is_loop is False
    print("✓ No loop in productive outputs")


def test_mode_transitions():
    """Test the full mode transition sequence."""
    print("\n--- Mode Transition Sequence ---")

    with tempfile.TemporaryDirectory() as tmp:
        tmp_dir = Path(tmp)

        # Mode 1: IMPLEMENTATION (task incomplete)
        incomplete_plan = create_test_plan(tmp_dir, "- [ ] Step 1\n- [ ] Step 2")
        complete, _, _ = check_task_complete_rssi(str(incomplete_plan))
        mode = "IMPLEMENTATION" if not complete else "VALIDATION"
        assert mode == "IMPLEMENTATION"
        print(f"1. {mode} - Task incomplete")

        # Mode 2: Task complete -> VALIDATION
        complete_plan = create_test_plan(tmp_dir, "- [x] Step 1\n- [x] Step 2")
        complete, _, _ = check_task_complete_rssi(str(complete_plan))
        state = {
            "validation_exhausted": False,
            "validation_round": 0,
            "validation_iteration": 0,
            "validation_score": 0.0,
        }
        mode = "VALIDATION" if complete and not state["validation_exhausted"] else "OTHER"
        assert mode == "VALIDATION"
        print(f"2. {mode} - Task complete, validation pending")

        # Mode 3: Validation done -> EXPLORATION
        state["validation_exhausted"] = True
        state["validation_score"] = 0.85
        min_hours_met = False
        mode = "EXPLORATION" if state["validation_exhausted"] and not min_hours_met else "OTHER"
        assert mode == "EXPLORATION"
        print(f"3. {mode} - Validation exhausted, min hours not met")

        # Mode 4: All conditions met -> ALLOW STOP
        min_hours_met = True
        mode = "ALLOW_STOP" if state["validation_exhausted"] and min_hours_met else "OTHER"
        assert mode == "ALLOW_STOP"
        print(f"4. {mode} - All conditions met")


def test_validation_score_computation():
    """Test validation score calculation."""
    # Perfect state - no issues
    perfect_state = {
        "validation_findings": {
            "round1": {"critical": [], "medium": [], "low": []},
            "round2": {"verified": [], "failed": []},
            "round3": {"doc_issues": [], "coverage_gaps": []},
        }
    }
    score = compute_validation_score(perfect_state)
    assert score == 1.0
    print(f"✓ Perfect score: {score}")

    # State with critical issues
    critical_state = {
        "validation_findings": {
            "round1": {"critical": ["issue1"], "medium": [], "low": []},
            "round2": {"verified": [], "failed": []},
            "round3": {"doc_issues": [], "coverage_gaps": []},
        }
    }
    score = compute_validation_score(critical_state)
    assert score < 0.8  # Should fail threshold
    print(f"✓ Score with critical issues: {score}")


if __name__ == "__main__":
    print("=" * 60)
    print("Running integration tests")
    print("=" * 60)

    test_full_workflow_incomplete()
    test_full_workflow_complete_needs_validation()
    test_full_workflow_validation_exhausted()
    test_file_discovery_cascade()
    test_work_opportunity_scanning()
    test_loop_detection_integration()
    test_mode_transitions()
    test_validation_score_computation()

    print("=" * 60)
    print("All integration tests passed!")
    print("=" * 60)
