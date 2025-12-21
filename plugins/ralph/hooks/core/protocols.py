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
from typing import Protocol, runtime_checkable

# Confidence levels for RSSI agreement
DEFAULT_CONFIDENCE = 0.0  # No opinion, defer to RSSI
SUGGEST_CONFIDENCE = 0.5  # Suggest stop, requires RSSI agreement
OVERRIDE_CONFIDENCE = 1.0  # Hard limit, override RSSI


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
            - 0.0: No opinion, defer to existing RSSI logic
            - 0.5: Suggests stop, requires RSSI agreement
            - 1.0: Hard limit, overrides RSSI (e.g., budget exhausted)
    """

    should_continue: bool
    reason: str
    confidence: float = DEFAULT_CONFIDENCE


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
