# /// script
# requires-python = ">=3.11"
# dependencies = []
# ///
"""Alpha Forge adapter for trading strategy research.

Provides metrics collection and display for Alpha Forge strategy research.
Reads experiment outputs from outputs/runs/ without modifying the repository.

IMPORTANT: This adapter does NOT influence stopping decisions.
All stopping is handled by Ralph's native RSSI scheme:
- Task completion markers
- Time limits (min/max hours)
- Iteration limits (min/max iterations)
- Validation phase exhaustion
- Loop detection
"""

import json
import logging
from datetime import datetime
from pathlib import Path

from core.protocols import (
    DEFAULT_CONFIDENCE,
    ConvergenceResult,
    MetricsEntry,
    ProjectAdapter,
)

logger = logging.getLogger(__name__)


class AlphaForgeAdapter(ProjectAdapter):
    """Adapter for Alpha Forge trading strategy research.

    Purpose: Metrics collection and display ONLY.
    - Reads experiment results from outputs/runs/run_YYYYMMDD_HHMMSS/summary.json
    - Provides Best Sharpe, experiment count, WFE for status display
    - Determines research phase (exploration vs attribution) based on Sharpe

    Stopping: Handled ENTIRELY by Ralph's native RSSI scheme.
    This adapter always returns DEFAULT_CONFIDENCE (0.0) to defer to RSSI.
    """

    name = "alpha-forge"

    def detect(self, project_dir: Path) -> bool:
        """Check if this is an Alpha Forge repository.

        Detection based on pyproject.toml containing 'alpha-forge' or 'alpha_forge'.

        Args:
            project_dir: Path to project root

        Returns:
            True if Alpha Forge project detected
        """
        pyproject = project_dir / "pyproject.toml"
        if not pyproject.exists():
            return False

        try:
            content = pyproject.read_text()
            return "alpha-forge" in content or "alpha_forge" in content
        except OSError as e:
            logger.warning(f"Could not read pyproject.toml: {e}")
            return False

    def get_metrics_history(
        self, project_dir: Path, start_time: str
    ) -> list[MetricsEntry]:
        """Scan outputs/runs/ for runs after start_time.

        Missing summary.json files are logged and skipped (user decision).

        Args:
            project_dir: Path to Alpha Forge project root
            start_time: ISO format timestamp, only return runs after this time

        Returns:
            List of MetricsEntry objects from valid runs, sorted by timestamp
        """
        runs_dir = project_dir / "outputs" / "runs"
        if not runs_dir.exists():
            logger.debug(f"No runs directory found: {runs_dir}")
            return []

        try:
            start_dt = datetime.fromisoformat(start_time.replace("Z", "+00:00"))
        except ValueError:
            logger.warning(f"Invalid start_time format: {start_time}")
            start_dt = datetime.min

        entries = []

        for run_dir in sorted(runs_dir.glob("run_*")):
            entry = self._parse_run_directory(run_dir, start_dt)
            if entry is not None:
                entries.append(entry)

        logger.debug(f"Found {len(entries)} runs after {start_time}")
        return entries

    def _parse_run_directory(
        self, run_dir: Path, start_dt: datetime
    ) -> MetricsEntry | None:
        """Parse a single run directory into a MetricsEntry.

        Args:
            run_dir: Path to run directory (e.g., outputs/runs/run_20251219_143500)
            start_dt: Only return entry if run timestamp is after this

        Returns:
            MetricsEntry if valid run after start_dt, None otherwise
        """
        # Parse timestamp from directory name
        try:
            ts_str = run_dir.name.replace("run_", "")
            run_ts = datetime.strptime(ts_str, "%Y%m%d_%H%M%S")
        except ValueError:
            logger.debug(f"Skipping {run_dir.name}: invalid timestamp format")
            return None

        # Filter by start time
        if run_ts <= start_dt.replace(tzinfo=None):
            return None

        # Read summary.json
        summary_file = run_dir / "summary.json"
        if not summary_file.exists():
            # User decision: Skip and log warning
            logger.warning(f"Skipping {run_dir.name}: missing summary.json")
            return None

        try:
            summary = json.loads(summary_file.read_text())
            return MetricsEntry(
                identifier=run_dir.name,
                timestamp=run_ts.isoformat(),
                primary_metric=summary.get("sharpe", 0.0),
                secondary_metrics={
                    "cagr": summary.get("cagr"),
                    "maxdd": summary.get("maxdd"),
                    "wfe": summary.get("wfe"),
                    "sortino": summary.get("sortino"),
                    "calmar": summary.get("calmar"),
                },
            )
        except (json.JSONDecodeError, OSError) as e:
            logger.warning(f"Skipping {run_dir.name}: {e}")
            return None

    def check_convergence(
        self, metrics_history: list[MetricsEntry]
    ) -> ConvergenceResult:
        """Provide metrics status for display only.

        IMPORTANT: This adapter does NOT influence stopping decisions.
        All stopping is handled by Ralph's native RSSI scheme:
        - Task completion markers
        - Time limits (min/max hours)
        - Iteration limits (min/max iterations)
        - Validation phase exhaustion
        - Loop detection

        This method provides informational status for display purposes only,
        always returning DEFAULT_CONFIDENCE (0.0) to defer to RSSI.

        Args:
            metrics_history: List of metrics from completed runs

        Returns:
            ConvergenceResult with DEFAULT_CONFIDENCE (never influences stopping)
        """
        n = len(metrics_history)

        if n == 0:
            return ConvergenceResult(
                should_continue=True,
                reason="No experiments yet",
                confidence=DEFAULT_CONFIDENCE,
            )

        # Compute metrics for display
        sharpes = [m.primary_metric for m in metrics_history]
        best_sharpe = max(sharpes)
        best_idx = sharpes.index(best_sharpe)
        runs_since_best = n - 1 - best_idx

        # Check WFE if available
        latest = metrics_history[-1]
        wfe = latest.secondary_metrics.get("wfe")
        wfe_info = f", WFE={wfe:.2f}" if wfe is not None else ""

        # Build informational status (for display only)
        return ConvergenceResult(
            should_continue=True,  # Always continue - let RSSI decide stopping
            reason=f"Experiments: {n}, best Sharpe={best_sharpe:.3f} (run {best_idx + 1}), {runs_since_best} since best{wfe_info}",
            confidence=DEFAULT_CONFIDENCE,  # Never influence RSSI stopping
        )

    def get_session_mode(self) -> str:
        """Return mode string for session file.

        Returns:
            'alpha-forge-research' mode identifier
        """
        return "alpha-forge-research"

    def get_research_phase(self, metrics_history: list[MetricsEntry]) -> str:
        """Determine research phase based on best Sharpe achieved.

        Phase determination (adapter-specific, not in protocol):
        - exploration: Sharpe < 1.0, allows up to 3 changes per iteration
        - attribution: Sharpe >= 1.0, restricts to 1 change for attribution

        Args:
            metrics_history: List of metrics from completed runs

        Returns:
            'exploration' or 'attribution' phase string
        """
        if not metrics_history:
            return "exploration"
        best_sharpe = max(m.primary_metric for m in metrics_history)
        return "attribution" if best_sharpe >= 1.0 else "exploration"
