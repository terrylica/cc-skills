# /// script
# requires-python = ">=3.11"
# dependencies = []
# ///
"""Unit tests for multi-repository adapter architecture.

Tests adapter registry, path hash, and project-specific adapters.
"""

import json
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent))

from adapters.alpha_forge import AlphaForgeAdapter
# UniversalAdapter not yet implemented - tests skipped
# from adapters.universal import UniversalAdapter
from core.path_hash import build_state_file_path, get_path_hash, load_session_state
from core.protocols import (
    DEFAULT_CONFIDENCE,
    OVERRIDE_CONFIDENCE,
    SUGGEST_CONFIDENCE,
    MetricsEntry,
)
from core.registry import AdapterRegistry

# ===== PATH HASH TESTS =====


def test_path_hash_deterministic():
    """Same path always produces same hash."""
    path1 = "/Users/test/eon/alpha-forge"
    path2 = "/Users/test/eon/alpha-forge"

    hash1 = get_path_hash(path1)
    hash2 = get_path_hash(path2)

    assert hash1 == hash2, f"Hashes differ: {hash1} != {hash2}"
    assert len(hash1) == 8, f"Expected 8 char hash, got {len(hash1)}"
    print(f"✓ Path hash is deterministic: {hash1}")


def test_path_hash_different_paths():
    """Different paths produce different hashes."""
    main_repo = "/Users/test/eon/alpha-forge"
    worktree = "/Users/test/eon/alpha-forge-worktrees/feature-x"

    hash_main = get_path_hash(main_repo)
    hash_worktree = get_path_hash(worktree)

    assert hash_main != hash_worktree, "Worktree should have different hash"
    print(f"✓ Different paths have different hashes: {hash_main} vs {hash_worktree}")


def test_path_hash_empty_path():
    """Empty path returns 'none'."""
    assert get_path_hash("") == "none"
    assert get_path_hash(None) == "none"  # type: ignore[arg-type]
    print("✓ Empty path returns 'none'")


def test_build_state_file_path():
    """State file path includes session ID and path hash."""
    state_dir = Path("/tmp/state")
    session_id = "abc123"
    project_dir = "/Users/test/eon/alpha-forge"

    state_file = build_state_file_path(state_dir, session_id, project_dir)

    assert "sessions" in str(state_file)
    assert session_id in str(state_file)
    assert "@" in state_file.name, "Should contain @ separator"
    print(f"✓ State file path: {state_file}")


def test_load_session_state_new_session():
    """New session returns default state."""
    with tempfile.TemporaryDirectory() as tmp:
        state_file = Path(tmp) / "sessions" / "test@abc123.json"
        default = {"iteration": 0, "started_at": ""}

        state = load_session_state(state_file, default)

        assert state == default
        print("✓ New session returns default state")


def test_load_session_state_existing():
    """Existing session loads saved state."""
    with tempfile.TemporaryDirectory() as tmp:
        state_dir = Path(tmp) / "sessions"
        state_dir.mkdir(parents=True)
        state_file = state_dir / "test@abc123.json"

        saved_state = {"iteration": 5, "started_at": "2025-01-01T00:00:00Z"}
        state_file.write_text(json.dumps(saved_state))

        default = {"iteration": 0, "started_at": ""}
        state = load_session_state(state_file, default)

        assert state["iteration"] == 5
        assert state["started_at"] == "2025-01-01T00:00:00Z"
        print("✓ Existing session loads saved state")


# ===== UNIVERSAL ADAPTER TESTS =====
# Note: UniversalAdapter tests commented out - adapter not yet implemented.
# The adapter concept exists in the protocol but the implementation was not created.
# These tests will be re-enabled when UniversalAdapter is implemented.


# def test_universal_adapter_always_matches():
#     """Universal adapter matches all projects."""
#     adapter = UniversalAdapter()
#
#     with tempfile.TemporaryDirectory() as tmp:
#         assert adapter.detect(Path(tmp)) is True
#         print("✓ Universal adapter matches all projects")
#
#
# def test_universal_adapter_defers_to_ralph():
#     """Universal adapter returns confidence=0.0 (defer to Ralph)."""
#     adapter = UniversalAdapter()
#
#     result = adapter.check_convergence([])
#
#     assert result.should_continue is True
#     assert result.confidence == DEFAULT_CONFIDENCE
#     print(f"✓ Universal adapter defers to Ralph: {result.reason}")
#
#
# def test_universal_adapter_no_metrics():
#     """Universal adapter returns empty metrics."""
#     adapter = UniversalAdapter()
#
#     with tempfile.TemporaryDirectory() as tmp:
#         metrics = adapter.get_metrics_history(Path(tmp), "2025-01-01T00:00:00Z")
#         assert metrics == []
#         print("✓ Universal adapter returns empty metrics")


# ===== ALPHA FORGE ADAPTER TESTS =====


def test_alpha_forge_adapter_detection():
    """Alpha Forge adapter detects project by pyproject.toml."""
    adapter = AlphaForgeAdapter()

    with tempfile.TemporaryDirectory() as tmp:
        project_dir = Path(tmp)

        # Without pyproject.toml
        assert adapter.detect(project_dir) is False

        # With pyproject.toml but no alpha-forge
        pyproject = project_dir / "pyproject.toml"
        pyproject.write_text('[project]\nname = "other"')
        assert adapter.detect(project_dir) is False

        # With alpha-forge in pyproject.toml
        pyproject.write_text('[project]\nname = "alpha-forge"')
        assert adapter.detect(project_dir) is True

        print("✓ Alpha Forge adapter detects project correctly")


def test_alpha_forge_metrics_display():
    """Alpha Forge provides informational metrics without influencing stopping.

    The adapter now always returns should_continue=True with DEFAULT_CONFIDENCE,
    deferring all stopping decisions to Ralph.
    """
    adapter = AlphaForgeAdapter()

    # 0 runs - informational only
    result = adapter.check_convergence([])
    assert result.should_continue is True
    assert result.confidence == DEFAULT_CONFIDENCE
    assert "No experiments" in result.reason

    # With runs - provides stats but still defers to Ralph
    metrics = [
        MetricsEntry("run_1", "2025-01-01T00:00:00", 0.5),
        MetricsEntry("run_2", "2025-01-01T01:00:00", 0.6),
    ]
    result = adapter.check_convergence(metrics)
    assert result.should_continue is True
    assert result.confidence == DEFAULT_CONFIDENCE
    assert "Experiments: 2" in result.reason

    print("✓ Alpha Forge provides metrics display without influencing stopping")


def test_alpha_forge_many_experiments():
    """Alpha Forge displays stats for many experiments without stopping.

    The adapter defers all stopping decisions to Ralph, including hard limits.
    """
    adapter = AlphaForgeAdapter()

    # Create 99 dummy metrics
    metrics = [
        MetricsEntry(f"run_{i}", f"2025-01-01T{i:02d}:00:00", 0.5 + i * 0.001)
        for i in range(99)
    ]

    result = adapter.check_convergence(metrics)

    # Always defers to Ralph
    assert result.should_continue is True
    assert result.confidence == DEFAULT_CONFIDENCE
    assert "99" in result.reason
    print("✓ Alpha Forge displays stats for many experiments")


def test_alpha_forge_wfe_display():
    """Alpha Forge displays WFE metric without influencing stopping.

    WFE is shown for informational purposes only.
    """
    adapter = AlphaForgeAdapter()

    metrics = [
        MetricsEntry("run_1", "2025-01-01T00:00:00", 0.5),
        MetricsEntry("run_2", "2025-01-01T01:00:00", 0.6),
        MetricsEntry("run_3", "2025-01-01T02:00:00", 0.7),
        MetricsEntry(
            "run_4",
            "2025-01-01T03:00:00",
            0.8,
            secondary_metrics={"wfe": 0.55},
        ),
    ]

    result = adapter.check_convergence(metrics)

    # Always defers to Ralph
    assert result.should_continue is True
    assert result.confidence == DEFAULT_CONFIDENCE
    assert "WFE" in result.reason
    print("✓ Alpha Forge displays WFE metric")


def test_alpha_forge_tracks_best_run():
    """Alpha Forge tracks best Sharpe and runs since best.

    The adapter provides informational stats but does not influence stopping.
    """
    adapter = AlphaForgeAdapter()

    # Best sharpe at run_1, then 5 worse runs
    metrics = [
        MetricsEntry("run_1", "2025-01-01T00:00:00", 1.0),  # Best
        MetricsEntry("run_2", "2025-01-01T01:00:00", 0.8),
        MetricsEntry("run_3", "2025-01-01T02:00:00", 0.7),
        MetricsEntry("run_4", "2025-01-01T03:00:00", 0.6),
        MetricsEntry("run_5", "2025-01-01T04:00:00", 0.5),
        MetricsEntry("run_6", "2025-01-01T05:00:00", 0.4),  # 5 runs since best
    ]

    result = adapter.check_convergence(metrics)

    # Always defers to Ralph
    assert result.should_continue is True
    assert result.confidence == DEFAULT_CONFIDENCE
    assert "best Sharpe=1.000" in result.reason
    assert "5 since best" in result.reason
    print("✓ Alpha Forge tracks best run and runs since best")


def test_alpha_forge_metrics_history():
    """Alpha Forge reads metrics from outputs/runs/."""
    adapter = AlphaForgeAdapter()

    with tempfile.TemporaryDirectory() as tmp:
        project_dir = Path(tmp)
        runs_dir = project_dir / "outputs" / "runs"
        runs_dir.mkdir(parents=True)

        # Create a run directory with summary
        run_dir = runs_dir / "run_20251220_120000"
        run_dir.mkdir()
        summary = {
            "sharpe": 1.5,
            "cagr": 0.25,
            "maxdd": -0.15,
            "wfe": 0.45,
        }
        (run_dir / "summary.json").write_text(json.dumps(summary))

        # Create older run (before start_time)
        old_run = runs_dir / "run_20251201_120000"
        old_run.mkdir()
        (old_run / "summary.json").write_text(json.dumps({"sharpe": 0.5}))

        # Get metrics after start time
        metrics = adapter.get_metrics_history(
            project_dir, "2025-12-15T00:00:00Z"
        )

        assert len(metrics) == 1
        assert metrics[0].primary_metric == 1.5
        assert metrics[0].secondary_metrics["wfe"] == 0.45
        print("✓ Alpha Forge reads metrics from outputs/runs/")


# ===== REGISTRY TESTS =====


def test_registry_auto_discovery():
    """Registry discovers adapters from adapters/ directory."""
    adapters_dir = Path(__file__).parent.parent / "adapters"

    AdapterRegistry.discover(adapters_dir)

    # Should have alpha_forge adapter (Ralph is Alpha Forge exclusive, no universal fallback)
    adapters = AdapterRegistry._adapters
    assert len(adapters) >= 1, "Should discover at least one adapter"
    # Note: UniversalAdapter not implemented - registry returns None for non-Alpha Forge
    print(f"✓ Registry discovered {len(adapters)} adapters")


def test_registry_selects_alpha_forge():
    """Registry selects Alpha Forge adapter for matching project."""
    adapters_dir = Path(__file__).parent.parent / "adapters"
    AdapterRegistry.discover(adapters_dir)

    with tempfile.TemporaryDirectory() as tmp:
        project_dir = Path(tmp)
        pyproject = project_dir / "pyproject.toml"
        pyproject.write_text('[project]\nname = "alpha-forge"')

        adapter = AdapterRegistry.get_adapter(project_dir)

        assert adapter.name == "alpha-forge"
        print("✓ Registry selects Alpha Forge for matching project")


def test_registry_returns_none_for_non_alpha_forge():
    """Registry returns None for non-matching projects (Alpha Forge exclusive)."""
    adapters_dir = Path(__file__).parent.parent / "adapters"
    AdapterRegistry.discover(adapters_dir)

    with tempfile.TemporaryDirectory() as tmp:
        project_dir = Path(tmp)
        # No pyproject.toml - not an Alpha Forge project

        adapter = AdapterRegistry.get_adapter(project_dir)

        assert adapter is None, "Should return None for non-Alpha Forge projects"
        print("✓ Registry returns None for non-Alpha Forge projects")


# ===== CONFIDENCE CONSTANTS TESTS =====


def test_confidence_constants():
    """Verify confidence level constants."""
    assert DEFAULT_CONFIDENCE == 0.0
    assert SUGGEST_CONFIDENCE == 0.5
    assert OVERRIDE_CONFIDENCE == 1.0
    print("✓ Confidence constants are correct")


# ===== RUN ALL TESTS =====


def run_all_tests():
    """Run all adapter tests."""
    print("\n" + "=" * 60)
    print("ADAPTER SYSTEM TESTS")
    print("=" * 60 + "\n")

    tests = [
        # Path hash tests
        test_path_hash_deterministic,
        test_path_hash_different_paths,
        test_path_hash_empty_path,
        test_build_state_file_path,
        test_load_session_state_new_session,
        test_load_session_state_existing,
        # test_load_session_state_fallback - removed (migration fallback removed in Phase 0B)
        # Universal adapter tests - skipped (UniversalAdapter not yet implemented)
        # test_universal_adapter_always_matches,
        # test_universal_adapter_defers_to_ralph,
        # test_universal_adapter_no_metrics,
        # Alpha Forge adapter tests
        test_alpha_forge_adapter_detection,
        test_alpha_forge_metrics_display,
        test_alpha_forge_many_experiments,
        test_alpha_forge_wfe_display,
        test_alpha_forge_tracks_best_run,
        test_alpha_forge_metrics_history,
        # Registry tests
        test_registry_auto_discovery,
        test_registry_selects_alpha_forge,
        test_registry_returns_none_for_non_alpha_forge,
        # Confidence constants
        test_confidence_constants,
    ]

    passed = 0
    failed = 0

    for test in tests:
        try:
            test()
            passed += 1
        except Exception as e:
            print(f"✗ {test.__name__}: {e}")
            failed += 1

    print("\n" + "=" * 60)
    print(f"RESULTS: {passed} passed, {failed} failed")
    print("=" * 60 + "\n")

    return failed == 0


if __name__ == "__main__":
    success = run_all_tests()
    sys.exit(0 if success else 1)
