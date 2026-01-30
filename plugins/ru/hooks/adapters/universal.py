# /// script
# requires-python = ">=3.11"
# dependencies = []
# ///
# Issue #12: https://github.com/terrylica/cc-skills/issues/12
"""Universal adapter for any project type.

Provides basic completion detection using time/iteration limits.
Works on ANY project - no special metrics or detection criteria.
"""

import logging
from pathlib import Path

from core.protocols import ConvergenceResult, ProjectAdapter

logger = logging.getLogger(__name__)


class UniversalAdapter(ProjectAdapter):
    """Universal adapter that works on any project.

    Unlike project-specific adapters, this adapter:
    - Matches ANY project (detect always returns True)
    - Uses time/iteration limits for completion (no metrics-based convergence)
    - Provides generic exploration opportunities
    """

    name = "universal"

    @staticmethod
    def detect(project_dir: Path) -> bool:
        """Always returns True - works on any project.

        Args:
            project_dir: Path to project root directory

        Returns:
            True (always matches)
        """
        return True

    def get_metrics_history(self, project_dir: Path, max_results: int = 10) -> list[dict]:
        """Return empty metrics history (no project-specific metrics).

        Args:
            project_dir: Path to project root
            max_results: Maximum results to return

        Returns:
            Empty list (no metrics for universal adapter)
        """
        return []

    def check_convergence(
        self,
        project_dir: Path,
        iteration: int,
        runtime_hours: float,
        config: dict,
    ) -> ConvergenceResult:
        """Check completion using time/iteration limits only.

        The universal adapter doesn't use metrics-based convergence.
        It relies on the loop's time and iteration limits.

        Args:
            project_dir: Path to project root
            iteration: Current iteration number
            runtime_hours: Hours elapsed since loop start
            config: Loop configuration dict

        Returns:
            ConvergenceResult indicating whether to continue
        """
        # Get limits from config
        loop_limits = config.get("loop_limits", {})
        max_hours = loop_limits.get("max_hours", 9)
        max_iterations = loop_limits.get("max_iterations", 99)
        min_hours = loop_limits.get("min_hours", 0)
        min_iterations = loop_limits.get("min_iterations", 0)

        # Check if minimum thresholds met
        min_met = iteration >= min_iterations and runtime_hours >= min_hours

        # Check if maximum limits exceeded
        if iteration >= max_iterations:
            return ConvergenceResult(
                should_continue=False,
                confidence=1.0,
                reason=f"Maximum iterations reached ({iteration}/{max_iterations})",
                metrics={
                    "iteration": iteration,
                    "runtime_hours": runtime_hours,
                    "limit_type": "iteration",
                },
            )

        if runtime_hours >= max_hours:
            return ConvergenceResult(
                should_continue=False,
                confidence=1.0,
                reason=f"Maximum time reached ({runtime_hours:.1f}h/{max_hours}h)",
                metrics={
                    "iteration": iteration,
                    "runtime_hours": runtime_hours,
                    "limit_type": "time",
                },
            )

        # Continue until limits reached
        return ConvergenceResult(
            should_continue=True,
            confidence=0.5,
            reason=f"Iteration {iteration}, {runtime_hours:.1f}h elapsed (limits: {max_iterations} iters, {max_hours}h)",
            metrics={
                "iteration": iteration,
                "runtime_hours": runtime_hours,
                "min_met": min_met,
            },
        )

    def get_session_mode(self, project_dir: Path) -> str:
        """Return universal mode identifier.

        Returns:
            'universal' mode identifier
        """
        return "universal"

    def get_roadmap_context(self, project_dir: Path) -> dict:
        """Return empty roadmap context (no project-specific roadmap).

        Args:
            project_dir: Path to project root

        Returns:
            Empty dict
        """
        return {}
