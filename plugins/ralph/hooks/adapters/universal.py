# /// script
# requires-python = ">=3.11"
# dependencies = []
# ///
"""Universal adapter - fallback that preserves current Ralph behavior.

This adapter is used when no project-specific adapter matches. It defers
all completion decisions to Ralph's existing RSSI (Recursively Self-Improving
Super Intelligence) completion detection logic.
"""

import logging
from pathlib import Path

from core.protocols import (
    DEFAULT_CONFIDENCE,
    ConvergenceResult,
    MetricsEntry,
    ProjectAdapter,
)

logger = logging.getLogger(__name__)


class UniversalAdapter(ProjectAdapter):
    """Default adapter - preserves current Ralph behavior.

    This adapter:
    - Matches all projects (fallback)
    - Does not track metrics history
    - Defers all completion decisions to existing RSSI logic

    The universal adapter returns confidence=0.0 for all convergence checks,
    signaling that Ralph should use its existing completion detection
    (task completion markers, validation phases, iteration limits, etc.).
    """

    name = "universal"

    def detect(self, project_dir: Path) -> bool:
        """Always returns True as this is the fallback adapter.

        Args:
            project_dir: Path to project root (ignored)

        Returns:
            Always True
        """
        return True

    def get_metrics_history(
        self, project_dir: Path, start_time: str
    ) -> list[MetricsEntry]:
        """Universal adapter does not track metrics history.

        Args:
            project_dir: Path to project root (ignored)
            start_time: Start timestamp (ignored)

        Returns:
            Empty list - no metrics tracking for generic projects
        """
        return []

    def check_convergence(
        self, metrics_history: list[MetricsEntry]
    ) -> ConvergenceResult:
        """Defer to existing Ralph RSSI completion detection.

        The universal adapter always returns confidence=0.0 to signal
        that Ralph should use its existing completion logic rather than
        any adapter-specific convergence detection.

        Args:
            metrics_history: List of metrics (ignored for universal adapter)

        Returns:
            ConvergenceResult with should_continue=True, confidence=0.0
        """
        return ConvergenceResult(
            should_continue=True,
            reason="Universal adapter - using default Ralph completion detection",
            confidence=DEFAULT_CONFIDENCE,
        )

    def get_session_mode(self) -> str:
        """Return mode string for session file.

        Returns:
            'universal' mode identifier
        """
        return "universal"
