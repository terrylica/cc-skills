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
from discovery import (
    discover_plan_mode_file,
    discover_target_file,
    scan_work_opportunities,
)
from template_loader import get_loader
from utils import detect_loop
from validation import check_validation_exhausted, compute_validation_score


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


def test_plan_mode_discovery():
    """Test plan mode file discovery from transcript."""
    import json

    with tempfile.TemporaryDirectory() as tmp:
        tmp_dir = Path(tmp)

        # Create a mock transcript with plan mode system-reminder
        transcript_file = tmp_dir / "transcript.jsonl"
        transcript_content = [
            {
                "type": "user",
                "message": {
                    "role": "user",
                    "content": "You should create your plan at /Users/test/.claude/plans/my-plan.md using the Write tool."
                }
            },
            {
                "type": "assistant",
                "message": {"role": "assistant", "content": [{"type": "text", "text": "Working..."}]}
            }
        ]
        with open(transcript_file, "w") as f:
            for entry in transcript_content:
                f.write(json.dumps(entry) + "\n")

        # Test discovery
        discovered = discover_plan_mode_file(str(transcript_file))
        assert discovered == "/Users/test/.claude/plans/my-plan.md"
        print(f"✓ Plan mode discovery: {discovered}")


def test_plan_mode_discovery_filters_placeholders():
    """Test that placeholder patterns are filtered out."""
    import json

    with tempfile.TemporaryDirectory() as tmp:
        tmp_dir = Path(tmp)

        # Create transcript with placeholder AND real plan file
        transcript_file = tmp_dir / "transcript.jsonl"
        transcript_content = [
            # Placeholder from code example - should be filtered
            {
                "type": "user",
                "message": {"content": "create your plan at /path/to/plan.md example"}
            },
            # Real plan file - should be found
            {
                "type": "user",
                "message": {"content": "create your plan at /Users/real/.claude/plans/actual-plan.md"}
            },
        ]
        with open(transcript_file, "w") as f:
            for entry in transcript_content:
                f.write(json.dumps(entry) + "\n")

        discovered = discover_plan_mode_file(str(transcript_file))
        assert discovered == "/Users/real/.claude/plans/actual-plan.md"
        assert "/path/to" not in str(discovered)
        print(f"✓ Placeholder filtered, found: {discovered}")


def test_plan_mode_discovery_priority():
    """Test that plan mode takes priority over transcript tool operations."""
    import json

    with tempfile.TemporaryDirectory() as tmp:
        tmp_dir = Path(tmp)

        # Create transcript with both plan mode reminder AND tool operations
        transcript_file = tmp_dir / "transcript.jsonl"
        transcript_content = [
            # Old tool operation (should be ignored when plan mode present)
            {
                "type": "assistant",
                "message": {
                    "content": [{
                        "type": "tool_use",
                        "name": "Write",
                        "input": {"file_path": "/Users/old/.claude/plans/old-plan.md"}
                    }]
                }
            },
            # Plan mode system-reminder (should take priority)
            {
                "type": "user",
                "message": {"content": "create your plan at /Users/new/.claude/plans/new-plan.md"}
            },
        ]
        with open(transcript_file, "w") as f:
            for entry in transcript_content:
                f.write(json.dumps(entry) + "\n")

        # Test discover_target_file uses plan_mode as Priority 0
        discovered, method, _ = discover_target_file(
            transcript_path=str(transcript_file),
            project_dir=str(tmp_dir),
        )
        assert discovered == "/Users/new/.claude/plans/new-plan.md"
        assert method == "plan_mode"
        print(f"✓ Plan mode priority: {discovered} via {method}")


def test_no_focus_mode():
    """Test that no_focus config skips file discovery."""
    print("\n--- No-Focus Mode Test ---")

    # Simulate the config check that happens in loop-until-done.py
    config = {"no_focus": True, "min_hours": 4, "max_hours": 9}

    no_focus = config.get("no_focus", False)
    if no_focus:
        plan_file = None
        discovery_method = "no_focus"
    else:
        plan_file = "/some/discovered/file.md"
        discovery_method = "transcript"

    assert no_focus is True
    assert plan_file is None
    assert discovery_method == "no_focus"
    print("✓ No-focus mode: file discovery skipped")

    # Test with no_focus=False (default)
    config_normal = {"min_hours": 4, "max_hours": 9}
    no_focus_normal = config_normal.get("no_focus", False)
    assert no_focus_normal is False
    print("✓ Normal mode: file discovery enabled")


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
    test_plan_mode_discovery()
    test_plan_mode_discovery_filters_placeholders()
    test_plan_mode_discovery_priority()
    test_no_focus_mode()

    print("=" * 60)
    print("All integration tests passed!")
    print("=" * 60)
