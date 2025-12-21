# /// script
# requires-python = ">=3.11"
# dependencies = []
# ///
"""Alpha Forge adapter for trading strategy research.

Provides metrics collection and display for Alpha Forge strategy research.
Reads experiment outputs from outputs/runs/ without modifying the repository.

SLO Enhancement: Adds methods for SLO enforcement:
- get_prioritized_work() - Returns ROADMAP items sorted by priority
- filter_opportunities() - Applies work policy blocklist
- check_escalation() - Returns (should_escalate, reason)
- get_slo_context() - Returns context for template rendering

IMPORTANT: This adapter does NOT influence stopping decisions.
All stopping is handled by Ralph's native RSSI scheme:
- Task completion markers
- Time limits (min/max hours)
- Iteration limits (min/max iterations)
- Validation phase exhaustion
- Loop detection
"""

from __future__ import annotations

import json
import logging
import sys
from datetime import datetime
from pathlib import Path

from core.protocols import (
    DEFAULT_CONFIDENCE,
    ConvergenceResult,
    MetricsEntry,
    ProjectAdapter,
)

# Add hooks directory to path for SLO module imports
HOOKS_DIR = Path(__file__).parent.parent
if str(HOOKS_DIR) not in sys.path:
    sys.path.insert(0, str(HOOKS_DIR))

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

        Detection strategy (any match returns True):
        1. Root pyproject.toml contains 'alpha-forge' or 'alpha_forge'
        2. Monorepo: packages/*/pyproject.toml contains 'alpha-forge'
        3. Characteristic directory: packages/alpha-forge-core/ exists
        4. Experiment outputs: outputs/runs/ directory exists
        5. Parent directories contain alpha-forge markers (subdirectory detection)

        Args:
            project_dir: Path to project root (may be a subdirectory)

        Returns:
            True if Alpha Forge project detected
        """
        # Strategy 1: Root pyproject.toml
        pyproject = project_dir / "pyproject.toml"
        if pyproject.exists():
            try:
                content = pyproject.read_text()
                if "alpha-forge" in content or "alpha_forge" in content:
                    return True
            except OSError:
                pass

        # Strategy 2: Monorepo package detection
        packages_dir = project_dir / "packages"
        if packages_dir.is_dir():
            for pkg_pyproject in packages_dir.glob("*/pyproject.toml"):
                try:
                    content = pkg_pyproject.read_text()
                    if "alpha-forge" in content or "alpha_forge" in content:
                        logger.debug(f"Detected alpha-forge via {pkg_pyproject}")
                        return True
                except OSError:
                    continue

        # Strategy 3: Characteristic directory marker
        if (project_dir / "packages" / "alpha-forge-core").is_dir():
            logger.debug("Detected alpha-forge via packages/alpha-forge-core/")
            return True

        # Strategy 4: Experiment outputs directory (unique to alpha-forge)
        if (project_dir / "outputs" / "runs").is_dir():
            logger.debug("Detected alpha-forge via outputs/runs/")
            return True

        # Strategy 5: Check parent directories (when CWD is a subdirectory)
        current = project_dir
        for _ in range(5):  # Limit traversal depth
            parent = current.parent
            if parent == current:  # Reached filesystem root
                break
            # Check parent's pyproject.toml
            parent_pyproject = parent / "pyproject.toml"
            if parent_pyproject.exists():
                try:
                    content = parent_pyproject.read_text()
                    if "alpha-forge" in content or "alpha_forge" in content:
                        logger.debug(f"Detected alpha-forge via parent: {parent}")
                        return True
                except OSError:
                    pass
            # Check for alpha-forge packages in parent
            parent_packages = parent / "packages"
            if parent_packages.is_dir():
                if (parent_packages / "alpha-forge-core").is_dir():
                    logger.debug(f"Detected alpha-forge via parent packages: {parent}")
                    return True
            # Check for outputs/runs in parent
            if (parent / "outputs" / "runs").is_dir():
                logger.debug(f"Detected alpha-forge via parent outputs: {parent}")
                return True
            current = parent

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
        self, metrics_history: list[MetricsEntry], project_dir: Path | None = None
    ) -> ConvergenceResult:
        """Provide metrics status - NEVER stops the loop.

        Alpha Forge uses eternal RSSI loop. This adapter:
        - Provides metrics for display
        - NEVER signals completion (returns 0.0 confidence)
        - Busywork filtering is handled by alpha_forge_filter.py

        The loop continues forever, but only ROADMAP-aligned work is allowed.

        Args:
            metrics_history: List of metrics from completed runs
            project_dir: Path to project root (unused - no stopping)

        Returns:
            ConvergenceResult with DEFAULT_CONFIDENCE (never stops)
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

    # ========== SLO ENFORCEMENT METHODS ==========

    def get_prioritized_work(self, project_dir: Path) -> list:
        """Get ROADMAP items sorted by priority.

        Uses roadmap_parser to extract work items from ROADMAP.md.

        Args:
            project_dir: Path to Alpha Forge project root

        Returns:
            List of WorkItem objects sorted by priority (P0 first)
        """
        try:
            from roadmap_parser import parse_roadmap

            return parse_roadmap(project_dir)
        except ImportError:
            logger.warning("roadmap_parser not available")
            return []

    def filter_opportunities(self, opportunities: list[str]) -> list[str]:
        """Filter opportunities using work policy blocklist.

        Removes busywork opportunities (linter fixes, annotations, etc.)

        Args:
            opportunities: Raw list of opportunity descriptions

        Returns:
            Filtered list with busywork removed
        """
        try:
            from alpha_forge_filter import get_allowed_opportunities

            return get_allowed_opportunities(opportunities)
        except ImportError:
            logger.warning("alpha_forge_filter not available")
            return opportunities

    def check_escalation(
        self,
        work_item,
        *,
        changed_files: list[Path] | None = None,
        lines_changed: int = 0,
        project_dir: Path | None = None,
    ) -> tuple[bool, str]:
        """Check if work requires escalation to expert consultation.

        Args:
            work_item: WorkItem being evaluated
            changed_files: List of files that would be changed
            lines_changed: Number of lines changed so far
            project_dir: Path to project root

        Returns:
            Tuple of (should_escalate, reason)
        """
        try:
            from work_policy import check_escalation

            roadmap_items = []
            if project_dir:
                roadmap_items = self.get_prioritized_work(project_dir)

            result = check_escalation(
                work_item,
                changed_files=changed_files,
                lines_changed=lines_changed,
                roadmap_items=roadmap_items,
            )
            return result.should_escalate, result.message
        except ImportError:
            logger.warning("work_policy not available")
            return False, "work_policy module not available"

    def get_slo_context(
        self,
        project_dir: Path,
        work_item=None,
        iteration: int = 0,
    ) -> dict:
        """Get SLO context for template rendering.

        Provides all context needed for alpha-forge-slo-experts.md template.

        Args:
            project_dir: Path to Alpha Forge project root
            work_item: Current work item (optional)
            iteration: Current RSSI iteration number

        Returns:
            Dict with context for template rendering
        """
        context = {
            "iteration": iteration,
            "current_phase": None,
            "work_item": None,
            "priority": "P1",
            "lines_changed": 0,
            "cross_package": False,
            "roadmap_items_completed": 0,
            "features_added": 0,
            "busywork_skipped": 0,
            "checkpoints_passed": 0,
            "checkpoints_failed": 0,
        }

        # Get current phase from roadmap
        try:
            from roadmap_parser import get_current_phase

            context["current_phase"] = get_current_phase(project_dir)
        except ImportError:
            pass

        # Get metrics from value tracker
        try:
            from value_metrics import load_metrics

            metrics = load_metrics(project_dir)
            if metrics:
                context["roadmap_items_completed"] = metrics.roadmap_items_completed
                context["features_added"] = metrics.features_added
                context["busywork_skipped"] = metrics.busywork_skipped
                context["checkpoints_passed"] = metrics.checkpoints_passed
                context["checkpoints_failed"] = metrics.checkpoints_failed
        except ImportError:
            pass

        # Add work item context
        if work_item:
            context["work_item"] = work_item.title
            context["priority"] = work_item.priority.name

        return context
