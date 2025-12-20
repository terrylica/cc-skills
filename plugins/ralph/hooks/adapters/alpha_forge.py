# /// script
# requires-python = ">=3.11"
# dependencies = []
# ///
"""Alpha Forge adapter for trading strategy research.

Provides convergence detection based on expert-synthesis workflow signals,
not naive iteration counting. Reads existing outputs from outputs/runs/
without modifying the Alpha Forge repository.

Convergence Signals (any ONE triggers):
1. Robustness thresholds pass (WFE > 0.5)
2. Diminishing returns (<3% improvement over last 5 experiments)
3. Best config unchanged for 5+ consecutive runs
4. Hard budget limit (99 experiments)
"""

import json
import logging
from datetime import datetime
from pathlib import Path

from core.protocols import (
    OVERRIDE_CONFIDENCE,
    SUGGEST_CONFIDENCE,
    DEFAULT_CONFIDENCE,
    ConvergenceResult,
    MetricsEntry,
    ProjectAdapter,
)

logger = logging.getLogger(__name__)

# Convergence thresholds (from ADR-2025-12-12 expert-synthesis workflow)
ROBUSTNESS_WFE_THRESHOLD = 0.5
DIMINISHING_RETURNS_THRESHOLD = 0.03  # 3%
PATIENCE_RUNS = 5
HARD_LIMIT = 99
WARMUP_RUNS = 3


class AlphaForgeAdapter(ProjectAdapter):
    """Adapter for Alpha Forge trading strategy research.

    Convergence Detection Strategy:
    - NOT iteration counting (Alpha Forge runs independent backtests)
    - Based on expert-synthesis signals from strategy-researcher workflow
    - Requires BOTH adapter AND RSSI to agree before stopping (confidence=0.5)

    Reads metrics from: outputs/runs/run_YYYYMMDD_HHMMSS/summary.json
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
        """Expert-synthesis convergence detection.

        Returns confidence=0.5 to signal: 'requires RSSI agreement'
        (User decision: Require both adapter AND RSSI to agree)

        Convergence Signals:
        1. WARMUP: Need baseline data (<3 runs)
        2. HARD LIMIT: Budget exhausted (99 experiments)
        3. ROBUSTNESS: WFE threshold passed
        4. DIMINISHING RETURNS: <3% improvement over last 5 runs
        5. BEST UNCHANGED: Best config unchanged for 5+ runs

        Args:
            metrics_history: List of metrics from completed runs

        Returns:
            ConvergenceResult with appropriate confidence level
        """
        n = len(metrics_history)

        # 1. WARMUP: Need baseline data
        if n < WARMUP_RUNS:
            return ConvergenceResult(
                should_continue=True,
                reason=f"Warmup phase - {n}/{WARMUP_RUNS} baseline runs",
                confidence=DEFAULT_CONFIDENCE,  # Don't influence RSSI
            )

        # 2. HARD LIMIT: Budget exhausted
        if n >= HARD_LIMIT:
            return ConvergenceResult(
                should_continue=False,
                reason=f"Budget exhausted ({HARD_LIMIT} experiments)",
                confidence=OVERRIDE_CONFIDENCE,  # Override RSSI
            )

        # 3. ROBUSTNESS: Check if WFE available and passes
        latest = metrics_history[-1]
        wfe = latest.secondary_metrics.get("wfe")
        if wfe is not None and wfe >= ROBUSTNESS_WFE_THRESHOLD:
            return ConvergenceResult(
                should_continue=False,
                reason=f"Robustness achieved: WFE={wfe:.2f} >= {ROBUSTNESS_WFE_THRESHOLD}",
                confidence=SUGGEST_CONFIDENCE,  # Requires RSSI agreement
            )

        # 4. DIMINISHING RETURNS: <3% improvement over last 5 runs
        if n >= PATIENCE_RUNS:
            diminishing = self._check_diminishing_returns(metrics_history)
            if diminishing is not None:
                return diminishing

        # 5. BEST CONFIG UNCHANGED: Patience exhausted
        sharpes = [m.primary_metric for m in metrics_history]
        best_sharpe = max(sharpes)
        best_idx = sharpes.index(best_sharpe)
        runs_since_best = n - 1 - best_idx

        if runs_since_best >= PATIENCE_RUNS:
            return ConvergenceResult(
                should_continue=False,
                reason=f"Best config unchanged for {runs_since_best} runs (patience={PATIENCE_RUNS})",
                confidence=SUGGEST_CONFIDENCE,  # Requires RSSI agreement
            )

        # DEFAULT: Continue exploration
        return ConvergenceResult(
            should_continue=True,
            reason=f"Exploring: {n} runs, best Sharpe={best_sharpe:.3f}",
            confidence=DEFAULT_CONFIDENCE,  # Don't influence RSSI
        )

    def _check_diminishing_returns(
        self, metrics_history: list[MetricsEntry]
    ) -> ConvergenceResult | None:
        """Check for diminishing returns in recent experiments.

        Args:
            metrics_history: List of metrics (must have >= PATIENCE_RUNS entries)

        Returns:
            ConvergenceResult if diminishing returns detected, None otherwise
        """
        recent = metrics_history[-PATIENCE_RUNS:]
        improvements = []

        for i in range(1, len(recent)):
            prev = recent[i - 1].primary_metric
            curr = recent[i].primary_metric
            if prev > 0:
                improvements.append((curr - prev) / prev)

        if not improvements:
            return None

        avg_improvement = sum(improvements) / len(improvements)
        if abs(avg_improvement) < DIMINISHING_RETURNS_THRESHOLD:
            return ConvergenceResult(
                should_continue=False,
                reason=f"Diminishing returns: {avg_improvement:.1%} avg improvement < {DIMINISHING_RETURNS_THRESHOLD:.0%} threshold",
                confidence=SUGGEST_CONFIDENCE,  # Requires RSSI agreement
            )

        return None

    def get_session_mode(self) -> str:
        """Return mode string for session file.

        Returns:
            'alpha-forge-research' mode identifier
        """
        return "alpha-forge-research"
