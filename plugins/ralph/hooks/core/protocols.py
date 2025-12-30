# /// script
# requires-python = ">=3.11"
# dependencies = []
# ///
"""Protocol definitions for project adapters.

Defines the interface that all project-type adapters must implement
for Ralph's multi-repository extensibility.
"""

from dataclasses import dataclass, field
from pathlib import Path
from typing import Literal, Protocol, runtime_checkable

# Confidence levels for Ralph adapter interaction
DEFAULT_CONFIDENCE = 0.0  # No opinion, defer to Ralph
SUGGEST_CONFIDENCE = 0.5  # Suggest action, requires Ralph agreement
OVERRIDE_CONFIDENCE = 1.0  # High confidence signal (Ralph pivots to exploration)

# Decision reason codes for JSONL logging
# Most "completion" signals pivot to exploration, not stop
DecisionReason = Literal[
    # Time/iteration limits (safety guardrails)
    "max_time_reached",  # Line 670: runtime >= max_hours → allow_stop()
    "max_iterations_reached",  # Line 674: iteration >= max_iterations → allow_stop()
    # Ralph pivots (completion → exploration, not stop)
    "task_complete_pivot",  # Line 778: task complete → force_exploration
    "adapter_converged_pivot",  # Line 732: adapter converged → force_exploration
    "nofocus_converged_pivot",  # Line 753: no-focus mode converged → force_exploration
    # Loop detection
    "loop_detected",  # Line 690: near-identical outputs (99% threshold) → allow_stop()
    # Control signals (KEPT - user-initiated)
    "kill_switch",  # Line 413: .claude/STOP_LOOP file → hard_stop()
    "global_stop_signal",  # Line 386: ~/.claude/ralph-global-stop.json → hard_stop()
    "state_stopped",  # Line 396: State machine = STOPPED → allow_stop()
    "state_draining",  # Line 404: DRAINING → STOPPED transition → hard_stop()
    # Continuation
    "force_exploration",  # Line 661: Idle detection triggered → exploration mode
    "continuing",  # Line 812: Default continuation path
    # Default
    "unknown",  # Fallback for unmapped paths
]


@dataclass
class MetricsEntry:
    """Single metrics snapshot from a project run.

    Attributes:
        identifier: Run ID or iteration name (e.g., 'run_20251219_143500')
        timestamp: ISO format timestamp
        primary_metric: Main metric for convergence (e.g., Sharpe ratio)
        secondary_metrics: Additional metrics (cagr, maxdd, wfe, etc.)
    """

    identifier: str
    timestamp: str
    primary_metric: float
    secondary_metrics: dict[str, float | None] = field(default_factory=dict)


@dataclass
class ConvergenceResult:
    """Result of convergence check.

    Attributes:
        should_continue: True if loop should continue, False to stop
        reason: Human-readable explanation of decision
        confidence: Decision confidence level:
            - 0.0: No opinion, defer to Ralph
            - 0.5: Suggests stop, requires Ralph agreement
            - 1.0: Hard limit, overrides Ralph (e.g., budget exhausted)
        converged: True if research has explicitly converged (e.g., research_log.md
            shows "Status: CONVERGED"). Used to hard-block busywork.
    """

    should_continue: bool
    reason: str
    confidence: float = DEFAULT_CONFIDENCE
    converged: bool = False


@runtime_checkable
class ProjectAdapter(Protocol):
    """Interface that all project adapters must implement.

    Adapters provide project-specific logic for:
    - Detecting project type from directory structure
    - Reading metrics from existing outputs
    - Determining convergence based on project-specific signals

    Example:
        class MyProjectAdapter:
            name = "my-project"

            def detect(self, project_dir: Path) -> bool:
                return (project_dir / "my-project.yaml").exists()

            def get_metrics_history(self, project_dir: Path, start_time: str) -> list[MetricsEntry]:
                # Read project-specific metrics files
                ...

            def check_convergence(self, metrics_history: list[MetricsEntry]) -> ConvergenceResult:
                # Apply project-specific convergence logic
                ...

            def get_session_mode(self) -> str:
                return "my-project-research"
    """

    name: str  # Unique adapter name (e.g., "alpha-forge", "python-uv")

    def detect(self, project_dir: Path) -> bool:
        """Return True if this adapter handles this project type.

        Args:
            project_dir: Path to project root directory

        Returns:
            True if this adapter should handle the project
        """
        ...

    def get_metrics_history(
        self, project_dir: Path, start_time: str
    ) -> list[MetricsEntry]:
        """Return metrics entries created after start_time.

        Args:
            project_dir: Path to project root directory
            start_time: ISO format timestamp, only return runs after this time

        Returns:
            List of MetricsEntry objects, sorted by timestamp
        """
        ...

    def check_convergence(
        self, metrics_history: list[MetricsEntry], project_dir: Path | None = None
    ) -> ConvergenceResult:
        """Determine if loop should continue based on metrics.

        Args:
            metrics_history: List of metrics from completed runs
            project_dir: Optional project directory for additional checks

        Returns:
            ConvergenceResult with should_continue, reason, and confidence
        """
        ...

    def get_session_mode(self) -> str:
        """Return mode string for session file.

        Returns:
            Mode identifier (e.g., 'alpha-forge-research', 'universal')
        """
        ...
