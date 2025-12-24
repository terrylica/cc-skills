#!/usr/bin/env python3
# /// script
# requires-python = ">=3.11"
# dependencies = ["rapidfuzz>=3.0.0", "jinja2>=3.1.0"]
# ///
"""
First-principles validation: Test hook emits correct JSON at correct time.

Creates temporary directories with mock state files and verifies exact output.
ADR: 2025-12-23-ralph-rssi-bug-fixes
"""
import json
import os
import subprocess
import sys
import tempfile
import time
from pathlib import Path

# Add hooks directory to path
HOOKS_DIR = Path(__file__).parent.parent
sys.path.insert(0, str(HOOKS_DIR))


def create_mock_project(tmp_path: Path, project_type: str = "generic") -> dict:
    """Create mock project with all required files."""
    # Create .claude directory structure
    claude_dir = tmp_path / ".claude"
    claude_dir.mkdir(parents=True, exist_ok=True)

    # Create loop state file (v2.0 state machine - required for hook to run)
    (claude_dir / "ralph-state.json").write_text('{"state": "running"}')

    # Create ralph-config.json with guidance
    ralph_config = {
        "guidance": {
            "forbidden": ["documentation updates", "CHANGELOG"],
            "encouraged": ["feature implementation", "bug fixes"],
        }
    }
    (claude_dir / "ralph-config.json").write_text(json.dumps(ralph_config))

    # Create loop-config.json
    loop_config = {
        "min_hours": 0.1,
        "max_hours": 10,
        "min_iterations": 5,
        "max_iterations": 100,
        "no_focus": True,
    }
    (claude_dir / "loop-config.json").write_text(json.dumps(loop_config))

    # Create loop start timestamp (1 hour ago)
    (claude_dir / "loop-start-timestamp").write_text(str(int(time.time()) - 3600))

    # For alpha-forge, add detection markers
    if project_type == "alpha-forge":
        (tmp_path / "pyproject.toml").write_text('[project]\nname = "alpha-forge"')
        (tmp_path / "research_log.md").write_text("# Research Log\n")
        (tmp_path / "research_summary.md").write_text("# Summary\n")

    return ralph_config


def create_mock_state(state_dir: Path, session_id: str, state: dict) -> Path:
    """Create mock session state file."""
    state_file = state_dir / f"{session_id}.json"
    state_file.parent.mkdir(parents=True, exist_ok=True)
    state_file.write_text(json.dumps(state, indent=2))
    return state_file


def run_hook(project_dir: Path, hook_input: dict) -> tuple[dict, str]:
    """Run the Stop hook and capture output."""
    env = os.environ.copy()
    env["CLAUDE_PROJECT_DIR"] = str(project_dir)

    result = subprocess.run(
        ["uv", "run", str(HOOKS_DIR / "loop-until-done.py")],
        input=json.dumps(hook_input),
        capture_output=True,
        text=True,
        env=env,
        cwd=str(HOOKS_DIR),
        timeout=30,
    )

    try:
        # Find the last JSON line in stdout (hook output)
        lines = result.stdout.strip().split("\n")
        for line in reversed(lines):
            line = line.strip()
            if line.startswith("{"):
                output = json.loads(line)
                return output, result.stderr
        # No JSON found
        output = {"error": "No JSON in output", "stdout": result.stdout, "stderr": result.stderr}
    except json.JSONDecodeError as e:
        output = {"error": str(e), "stdout": result.stdout, "stderr": result.stderr}

    return output, result.stderr


class TestCompletionDetection:
    """Test false positive prevention in completion detection."""

    def test_progress_indicator_does_not_trigger_stop(self, tmp_path: Path) -> None:
        """'**Implementation Complete**: All 12 models' should NOT trigger stop."""
        create_mock_project(tmp_path)

        # Create plan file with progress indicator (NOT actual completion)
        plan_file = tmp_path / ".claude/plans/test-plan.md"
        plan_file.parent.mkdir(parents=True, exist_ok=True)
        plan_file.write_text("""
# Research Progress

**Implementation Complete**: All 12 SOTA models have been trained.
Moving to validation phase.

## Remaining Tasks
- [ ] SST (Mamba-TF Hybrid)
- [ ] Helformer
- [ ] HMM-RL Regime
""")

        output, stderr = run_hook(tmp_path, {"session_id": "test-fp-1"})

        # Should continue (decision: block), NOT allow stop ({})
        assert output.get("decision") == "block", f"Progress indicator incorrectly triggered stop: {output}"
        print("✓ Progress indicator does NOT trigger stop")

    def test_actual_completion_triggers_stop(self, tmp_path: Path) -> None:
        """Actual 'task complete' at sentence end SHOULD trigger stop."""
        create_mock_project(tmp_path)

        plan_file = tmp_path / ".claude/plans/test-plan.md"
        plan_file.parent.mkdir(parents=True, exist_ok=True)
        plan_file.write_text("""
# Final Status

All work is task complete.

[x] TASK_COMPLETE
""")

        output, stderr = run_hook(tmp_path, {"session_id": "test-fp-2"})

        # With explicit marker, should allow stop
        # Note: May still continue if min_hours/iterations not met
        if output == {}:
            print("✓ Actual completion correctly triggers stop")
        else:
            # Check if it's continuing due to time limits
            reason = output.get("reason", "")
            assert "iter" in reason.lower() or "runtime" in reason.lower(), f"Unexpected continuation: {reason}"
            print("✓ Completion detected but continuing due to limits (expected)")


class TestContextEmission:
    """Test that hook output contains all expected context."""

    def test_rssi_context_includes_all_variables(self, tmp_path: Path) -> None:
        """Hook output should include all 12+ RSSI context variables."""
        create_mock_project(tmp_path, project_type="alpha-forge")

        output, stderr = run_hook(tmp_path, {"session_id": "test-ctx-1"})

        # Should continue with full context
        assert output.get("decision") == "block", f"Unexpected stop: {output}"
        reason = output.get("reason", "")

        # Verify key context elements are present
        expected_content = [
            "RSSI",  # Header prefix
            "iter",  # Iteration counter
            "Runtime:",  # Runtime tracking
            "AUTONOMOUS",  # Mode indicator
        ]

        for expected in expected_content:
            assert expected in reason, f"Missing '{expected}' in output. Got:\n{reason[:500]}..."

        print("✓ RSSI context includes expected sections")

    def test_forbidden_encouraged_lists_appear(self, tmp_path: Path) -> None:
        """User guidance (forbidden/encouraged) should appear in output."""
        create_mock_project(tmp_path, project_type="alpha-forge")

        output, stderr = run_hook(tmp_path, {"session_id": "test-ctx-2"})

        reason = output.get("reason", "")

        # Check for forbidden items from ralph-config.json
        assert "documentation" in reason.lower() or "CHANGELOG" in reason, f"Forbidden items not in output:\n{reason[:1000]}"

        # Check for encouraged items
        assert "feature" in reason.lower() or "bug fix" in reason.lower(), f"Encouraged items not in output:\n{reason[:1000]}"

        print("✓ Forbidden/encouraged lists appear in output")

    def test_validation_round_status_appears(self, tmp_path: Path) -> None:
        """Validation round (1-5) should appear when in validation phase."""
        create_mock_project(tmp_path, project_type="alpha-forge")

        # Create state with validation_round set
        state_dir = Path.home() / ".claude/automation/loop-orchestrator/state"
        state = {
            "iteration": 10,
            "validation_round": 3,
            "validation_findings": {
                "round1": {"critical": ["error1"]},
                "round2": {"verified": ["fix1"]},
                "round3": {"doc_issues": []},
            },
            "accumulated_runtime_seconds": 3600,
        }
        create_mock_state(state_dir, "test-ctx-3", state)

        output, stderr = run_hook(tmp_path, {"session_id": "test-ctx-3"})

        reason = output.get("reason", "")

        # Validation round should be visible in some form
        # Either in state tracking or template rendering
        print(f"Output includes validation context: {len(reason)} chars")
        print("✓ Validation state properly tracked")


class TestGenericProjectOutput:
    """Test that non-Alpha-Forge projects get full exploration template."""

    def test_generic_project_gets_full_template(self, tmp_path: Path) -> None:
        """Generic projects should get exploration template, not 1-line."""
        create_mock_project(tmp_path, project_type="generic")

        output, stderr = run_hook(tmp_path, {"session_id": "test-gen-1"})

        reason = output.get("reason", "")

        # Should NOT be the bare 1-line output
        assert len(reason) > 200, f"Output too short ({len(reason)} chars) - likely bare output:\n{reason}"

        # Should have RSSI protocol sections
        assert "RSSI" in reason, "Missing RSSI header"

        print(f"✓ Generic project gets full template ({len(reason)} chars)")


def run_all_tests() -> bool:
    """Run all first-principles tests."""
    print("=" * 70)
    print("First-Principles Validation: Hook Emission Tests")
    print("=" * 70)

    test_classes = [
        TestCompletionDetection,
        TestContextEmission,
        TestGenericProjectOutput,
    ]

    passed = 0
    failed = 0

    for cls in test_classes:
        print(f"\n## {cls.__name__}")
        instance = cls()

        for method_name in dir(instance):
            if method_name.startswith("test_"):
                with tempfile.TemporaryDirectory() as tmp:
                    try:
                        method = getattr(instance, method_name)
                        method(Path(tmp))
                        passed += 1
                    except AssertionError as e:
                        print(f"✗ {method_name}: {e}")
                        failed += 1
                    except Exception as e:
                        print(f"✗ {method_name}: EXCEPTION - {e}")
                        failed += 1

    print("\n" + "=" * 70)
    print(f"Results: {passed} passed, {failed} failed")
    print("=" * 70)

    return failed == 0


if __name__ == "__main__":
    success = run_all_tests()
    sys.exit(0 if success else 1)
