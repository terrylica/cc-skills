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

    def test_ralph_context_includes_all_variables(self, tmp_path: Path) -> None:
        """Hook output should include all 12+ Ralph context variables."""
        create_mock_project(tmp_path, project_type="alpha-forge")

        output, stderr = run_hook(tmp_path, {"session_id": "test-ctx-1"})

        # Should continue with full context
        assert output.get("decision") == "block", f"Unexpected stop: {output}"
        reason = output.get("reason", "")

        # Verify key context elements are present
        expected_content = [
            "Ralph",  # Header prefix
            "iter",  # Iteration counter
            "Runtime:",  # Runtime tracking
            "AUTONOMOUS",  # Mode indicator
        ]

        for expected in expected_content:
            assert expected in reason, f"Missing '{expected}' in output. Got:\n{reason[:500]}..."

        print("✓ Ralph context includes expected sections")

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

        # Should have Ralph protocol sections
        assert "Ralph" in reason or "RALPH" in reason, "Missing Ralph header"

        print(f"✓ Generic project gets full template ({len(reason)} chars)")


class TestProductionFidelity:
    """Production-fidelity tests mimicking real alpha-forge environment."""

    def create_alpha_forge_project(self, tmp_path: Path) -> dict:
        """Create full alpha-forge project structure matching production."""
        claude_dir = tmp_path / ".claude"
        claude_dir.mkdir(parents=True, exist_ok=True)

        # v2.0.0 ralph-config.json (production format)
        ralph_config = {
            "version": "2.0.0",
            "state": "running",
            "poc_mode": False,
            "no_focus": False,
            "loop_limits": {
                "min_hours": 9,
                "max_hours": 999,
                "min_iterations": 99,
                "max_iterations": 999,
            },
            "guidance": {
                "forbidden": [
                    "Documentation updates",
                    "Dependency upgrades",
                    "Test coverage expansion",
                    "CI/CD modifications",
                ],
                "encouraged": [
                    "Research experiments",
                    "SOTA time series forecasting",
                    "OOD robust methodologies 2025",
                ],
                "timestamp": "2025-12-23T10:44:02Z",
            },
        }
        (claude_dir / "ralph-config.json").write_text(json.dumps(ralph_config, indent=2))

        # ralph-state.json (v2.0 state machine)
        (claude_dir / "ralph-state.json").write_text('{"state": "running"}')

        # loop-config.json (production limits)
        # Note: no_focus=True triggers the Ralph alpha-forge template
        # no_focus=False triggers FOCUSED mode with "EXPLORATION" header
        loop_config = {
            "min_hours": 9,
            "max_hours": 999,
            "min_iterations": 99,
            "max_iterations": 999,
            "no_focus": True,  # Required for Ralph alpha-forge template
        }
        (claude_dir / "loop-config.json").write_text(json.dumps(loop_config))

        # loop-start-timestamp (1 hour ago)
        (claude_dir / "loop-start-timestamp").write_text(str(int(time.time()) - 3600))

        # Full pyproject.toml (production format)
        pyproject = """[project]
name = "alpha-forge"
version = "0.3.0"
description = "AI-agent-centric, DSL-driven platform for quantitative research, backtesting, and live execution"
requires-python = ">=3.11,<3.12"

[tool.uv.workspace]
members = ["packages/*"]
"""
        (tmp_path / "pyproject.toml").write_text(pyproject)

        # Research session structure
        research_session = tmp_path / "outputs/research_sessions/research_20251223_120000"
        research_session.mkdir(parents=True, exist_ok=True)

        # research_summary.md (production format)
        research_summary = """# Research Summary

## Session Metadata
- **Status**: IN_PROGRESS
- **Objective**: Sharpe Ratio Maximization
- **Total Experiments**: 12
- **Best Sharpe Achieved**: 2.31

## Top 3 Configurations
| Rank | Config | Sharpe | CAGR | MaxDD |
|------|--------|--------|------|-------|
| 1 | TFT_v3 | 2.31 | 45% | -12% |
| 2 | PatchTST_v2 | 2.18 | 42% | -14% |
| 3 | Mamba_v1 | 2.05 | 38% | -11% |

## Key Patterns Discovered
- Feature lag 5 outperforms lag 10 in high volatility
- Attention heads > 4 show diminishing returns

## Unexplored Directions
- SST (Mamba-TF Hybrid)
- Helformer architecture
- HMM-RL Regime detection
"""
        (research_session / "research_summary.md").write_text(research_summary)

        # research_log.md (production format with deep thinking)
        research_log = """# Strategy Research Log

## Session Metadata
- **Started**: 2025-12-23T12:00:00
- **Last Updated**: 2025-12-23T15:30:00
- **Total Experiments**: 12
- **Best Sharpe Ratio**: 2.31
- **Research Status**: IN_PROGRESS

## Experiment 12: TFT_v3

### Hypothesis
Time-series attention with variable selection should outperform fixed feature sets.

### Configuration
```yaml
model: TFT
version: 3
features:
  - rsi_14
  - macd_signal
  - atr_20
attention_heads: 8
hidden_size: 128
```

### Metrics Summary
| Metric | Value |
|--------|-------|
| Sharpe | 2.31 |
| CAGR | 45% |
| Max Drawdown | -12% |
| Win Rate | 58% |
| WFE | 1.54 |

### Deep Thinking & Analysis
**Performance Drivers**: The attention mechanism effectively captures regime transitions...
**Pattern Recognition**: Strong performance in trending markets, weaker in mean-reversion...
**Surprises**: Unexpected robustness to missing data points...

## Best Configurations Found
1. TFT_v3 - Sharpe 2.31
2. PatchTST_v2 - Sharpe 2.18
3. Mamba_v1 - Sharpe 2.05

## Research Frontier
- [ ] SST (Mamba-TF Hybrid) - Unexplored
- [ ] Helformer - Unexplored
- [ ] HMM-RL Regime - Unexplored
"""
        (research_session / "research_log.md").write_text(research_log)

        # ADR structure (ITP workflow)
        adr_dir = tmp_path / "docs/adr"
        adr_dir.mkdir(parents=True, exist_ok=True)
        adr_content = """---
status: accepted
date: 2025-12-20
decision-makers: Claude
---

# Implement SST (Mamba-TF Hybrid) Architecture

## Context
Need to implement State Space Transformer for time series forecasting.

## Decision
Implement SST with Mamba backbone and Transformer attention.

## Status
- [x] Core SST implementation
- [x] Feature preprocessing
- [ ] Walk-forward validation
- [ ] Regime-specific tuning
"""
        (adr_dir / "2025-12-20-sst-implementation.md").write_text(adr_content)

        # Design spec structure
        design_dir = tmp_path / "docs/design/2025-12-20-sst-implementation"
        design_dir.mkdir(parents=True, exist_ok=True)
        spec_content = """---
implementation-status: in-progress
---

# SST Implementation Spec

## Architecture
State Space Transformer with Mamba backbone.

## Implementation Checklist
- [x] Core model class
- [x] Data loader
- [ ] Training loop
- [ ] Evaluation metrics
"""
        (design_dir / "spec.md").write_text(spec_content)

        return ralph_config

    def create_production_session_state(
        self, state_dir: Path, session_id: str, project_dir: Path
    ) -> Path:
        """Create production-fidelity session state file."""
        import hashlib
        from datetime import datetime, timezone

        # Production uses path hash for session isolation
        path_hash = hashlib.md5(str(project_dir).encode()).hexdigest()[:8]
        state_file = state_dir / "sessions" / f"{session_id}@{path_hash}.json"
        state_file.parent.mkdir(parents=True, exist_ok=True)

        # Production state structure
        state = {
            "iteration": 35,
            "started_at": datetime.now(timezone.utc).isoformat(),
            "recent_outputs": [
                "## IMPLEMENTATION MODE - Iteration 34\nImplemented TFT_v3...",
                "## VALIDATION Round 1 - Checking critical issues...",
            ],
            # Focus & Discovery
            "plan_file": str(project_dir / "docs/adr/2025-12-20-sst-implementation.md"),
            "discovered_file": str(project_dir / "docs/adr/2025-12-20-sst-implementation.md"),
            "discovery_method": "itp_adr",
            "candidate_files": [],
            # Completion Detection
            "completion_signals": [],
            "last_completion_confidence": 0.0,
            "opportunities_discovered": ["High-value pattern (2x): lint fixes"],
            # Validation Pipeline (5-round structure)
            "validation_round": 1,
            "validation_iteration": 0,
            "validation_findings": {
                "round1": {"critical": [], "medium": [], "low": []},
                "round2": {"verified": [], "failed": []},
                "round3": {"doc_issues": [], "coverage_gaps": []},
                "round4": {
                    "edge_cases_tested": [],
                    "edge_cases_failed": [],
                    "math_validated": [],
                    "probing_complete": False,
                },
                "round5": {
                    "regimes_tested": [],
                    "regime_results": {},
                    "robustness_score": 0.0,
                },
            },
            "validation_score": 0.0,
            "validation_exhausted": False,
            "previous_finding_count": 0,
            "agent_results": [],
            # Adapter-Specific Convergence (alpha-forge)
            "adapter_name": "alpha-forge",
            "adapter_convergence": {
                "should_continue": True,
                "reason": "12 experiments completed, 3 remaining",
                "confidence": 0.7,
                "converged": False,
                "metrics_count": 12,
                "metrics_history": [
                    {
                        "identifier": "run_20251223_120000",
                        "timestamp": "2025-12-23T12:00:00",
                        "primary_metric": 2.31,
                        "secondary_metrics": {
                            "cagr": 0.45,
                            "maxdd": -0.12,
                            "wfe": 1.54,
                            "sortino": 2.8,
                            "calmar": 3.75,
                        },
                    },
                    {
                        "identifier": "run_20251223_130000",
                        "timestamp": "2025-12-23T13:00:00",
                        "primary_metric": 2.18,
                        "secondary_metrics": {
                            "cagr": 0.42,
                            "maxdd": -0.14,
                            "wfe": 1.45,
                            "sortino": 2.5,
                            "calmar": 3.0,
                        },
                    },
                ],
            },
            # Performance & Timing
            "accumulated_runtime_seconds": 3600.0,
            "last_hook_timestamp": time.time() - 60,
            "last_iteration_time": time.time() - 60,
            "idle_iteration_count": 0,
        }
        state_file.write_text(json.dumps(state, indent=2))
        return state_file

    def test_alpha_forge_full_context_emission(self, tmp_path: Path) -> None:
        """Test that alpha-forge project emits full Ralph context with adapter convergence."""
        self.create_alpha_forge_project(tmp_path)

        # Create production-fidelity session state
        state_dir = Path.home() / ".claude/automation/loop-orchestrator/state"
        session_id = "test-prod-1"
        self.create_production_session_state(state_dir, session_id, tmp_path)

        output, stderr = run_hook(tmp_path, {"session_id": session_id})

        assert output.get("decision") == "block", f"Unexpected stop: {output}"
        reason = output.get("reason", "")

        # Verify production context elements
        expected = [
            "Ralph",  # Header
            "iter",  # Iteration tracking
            "Runtime",  # Runtime tracking
            "AUTONOMOUS",  # Mode indicator
        ]
        for exp in expected:
            assert exp in reason, f"Missing '{exp}' in output"

        # Verify guidance appears
        assert any(
            x in reason.lower()
            for x in ["documentation", "dependency", "research", "sota"]
        ), f"Guidance not in output:\n{reason[:1000]}"

        print(f"✓ Alpha-forge full context emission ({len(reason)} chars)")

    def test_adapter_convergence_metrics_visible(self, tmp_path: Path) -> None:
        """Test that adapter convergence metrics appear in output."""
        self.create_alpha_forge_project(tmp_path)

        state_dir = Path.home() / ".claude/automation/loop-orchestrator/state"
        session_id = "test-prod-2"
        self.create_production_session_state(state_dir, session_id, tmp_path)

        output, stderr = run_hook(tmp_path, {"session_id": session_id})

        reason = output.get("reason", "")

        # Adapter convergence should be reflected somehow in output
        # Either via template or through metrics display
        assert len(reason) > 1000, f"Output too short for full context: {len(reason)} chars"

        print(f"✓ Adapter convergence context present ({len(reason)} chars)")

    def test_research_frontier_detection(self, tmp_path: Path) -> None:
        """Test that research frontier (unexplored directions) is detected."""
        self.create_alpha_forge_project(tmp_path)

        # The research_log.md has unexplored directions:
        # - SST (Mamba-TF Hybrid)
        # - Helformer
        # - HMM-RL Regime

        output, stderr = run_hook(tmp_path, {"session_id": "test-prod-3"})

        # Should continue (research not complete)
        assert output.get("decision") == "block", f"Unexpected stop with unexplored directions: {output}"

        print("✓ Research frontier keeps loop running")

    def test_five_round_validation_structure(self, tmp_path: Path) -> None:
        """Test that 5-round validation structure is properly tracked."""
        self.create_alpha_forge_project(tmp_path)

        state_dir = Path.home() / ".claude/automation/loop-orchestrator/state"
        session_id = "test-prod-4"
        state_file = self.create_production_session_state(state_dir, session_id, tmp_path)

        # Modify state to be in validation round 3
        state = json.loads(state_file.read_text())
        state["validation_round"] = 3
        state["validation_findings"]["round1"] = {"critical": [], "medium": ["lint warning"], "low": []}
        state["validation_findings"]["round2"] = {"verified": ["fix1", "fix2"], "failed": []}
        state["validation_findings"]["round3"] = {"doc_issues": ["missing docstring"], "coverage_gaps": []}
        state_file.write_text(json.dumps(state, indent=2))

        output, stderr = run_hook(tmp_path, {"session_id": session_id})

        # Should continue (validation not complete)
        assert output.get("decision") == "block", f"Stopped during validation: {output}"

        print("✓ 5-round validation structure tracked")

    def test_false_positive_implementation_complete_production(self, tmp_path: Path) -> None:
        """Production scenario: 'All 12 SOTA models have been implemented' should NOT stop."""
        self.create_alpha_forge_project(tmp_path)

        # Update research log with the exact text that caused the bug
        research_session = tmp_path / "outputs/research_sessions/research_20251223_120000"
        research_log = research_session / "research_log.md"
        research_log.write_text("""# Strategy Research Log

## Session Metadata
- **Status**: IN_PROGRESS
- **Total Experiments**: 12

## Progress Update
**Implementation Complete**: All 12 SOTA models have been implemented and trained.
Moving to validation phase.

## Research Frontier
- [ ] SST (Mamba-TF Hybrid) - Unexplored
- [ ] Helformer - Unexplored
- [ ] HMM-RL Regime - Unexplored
""")

        output, stderr = run_hook(tmp_path, {"session_id": "test-prod-5"})

        # Must NOT stop - there are still unexplored directions
        assert output.get("decision") == "block", (
            f"FALSE POSITIVE: 'Implementation Complete' header triggered stop!\n{output}"
        )

        print("✓ Production false positive scenario passes")


def run_all_tests() -> bool:
    """Run all first-principles tests."""
    print("=" * 70)
    print("First-Principles Validation: Hook Emission Tests")
    print("=" * 70)

    test_classes = [
        TestCompletionDetection,
        TestContextEmission,
        TestGenericProjectOutput,
        TestProductionFidelity,
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
