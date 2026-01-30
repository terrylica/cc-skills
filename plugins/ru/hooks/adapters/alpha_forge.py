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
All stopping is handled by Ralph's native eternal loop scheme:
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

from core.project_detection import is_alpha_forge_project
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

    Stopping: Handled ENTIRELY by Ralph's native eternal loop scheme.
    This adapter always returns DEFAULT_CONFIDENCE (0.0) to defer to Ralph.
    """

    name = "alpha-forge"

    def detect(self, project_dir: Path) -> bool:
        """Check if this is an Alpha Forge repository.

        Uses consolidated detection from core.project_detection module.

        Args:
            project_dir: Path to project root (may be a subdirectory)

        Returns:
            True if Alpha Forge project detected
        """
        return is_alpha_forge_project(project_dir)

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

    def _check_research_converged(self, project_dir: Path) -> bool:
        """Check if latest research session shows CONVERGED status.

        Parses the most recent research_log.md in outputs/research_sessions/
        and looks for "Status: CONVERGED" or "CONVERGED" in the header.

        Args:
            project_dir: Path to Alpha Forge project root

        Returns:
            True if research is explicitly marked as CONVERGED
        """
        sessions_dir = project_dir / "outputs" / "research_sessions"
        if not sessions_dir.exists():
            return False

        # Find most recent research_log.md by directory name (timestamp-based)
        session_dirs = sorted(
            [d for d in sessions_dir.iterdir() if d.is_dir() and d.name.startswith("research_")],
            reverse=True,
        )
        if not session_dirs:
            return False

        latest_log = session_dirs[0] / "research_log.md"
        if not latest_log.exists():
            return False

        try:
            content = latest_log.read_text()
            # Check header (first 30 lines) for CONVERGED status
            header_lines = content.split("\n")[:30]
            header_text = "\n".join(header_lines)
            return "Status: CONVERGED" in header_text or "CONVERGED" in header_text
        except OSError:
            return False

    def check_convergence(
        self, metrics_history: list[MetricsEntry], project_dir: Path | None = None
    ) -> ConvergenceResult:
        """Provide metrics status and detect explicit CONVERGED state.

        Alpha Forge uses Ralph's eternal loop. This adapter:
        - Provides metrics for display
        - Detects explicit CONVERGED status in research_log.md
        - When CONVERGED, sets converged=True to hard-block busywork
        - Still defers stopping decisions to Ralph (confidence=0.0)

        Args:
            metrics_history: List of metrics from completed runs
            project_dir: Path to project root for CONVERGED detection

        Returns:
            ConvergenceResult with converged=True if research is CONVERGED
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

        # Check for explicit CONVERGED status in research_log.md
        is_converged = False
        if project_dir:
            is_converged = self._check_research_converged(project_dir)

        if is_converged:
            logger.info("Research CONVERGED detected - busywork will be hard-blocked")
            return ConvergenceResult(
                should_continue=True,  # Still defer stopping to Ralph
                reason=f"CONVERGED: Sharpe={best_sharpe:.3f}{wfe_info}. Only /research allowed.",
                confidence=DEFAULT_CONFIDENCE,  # Don't influence stopping
                converged=True,  # Signal to hard-block busywork
            )

        # Build informational status (for display only)
        return ConvergenceResult(
            should_continue=True,  # Always continue - let Ralph decide stopping
            reason=f"Experiments: {n}, best Sharpe={best_sharpe:.3f} (run {best_idx + 1}), {runs_since_best} since best{wfe_info}",
            confidence=DEFAULT_CONFIDENCE,  # Never influence Ralph stopping
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

    def filter_opportunities(
        self,
        opportunities: list[str],
        guidance: dict | None = None,
    ) -> list[str]:
        """Filter opportunities using work policy blocklist.

        Removes busywork opportunities (linter fixes, annotations, etc.)
        and user-forbidden items.

        Args:
            opportunities: Raw list of opportunity descriptions
            guidance: User-provided guidance dict with 'forbidden' and 'encouraged' lists

        Returns:
            Filtered list with busywork and user-forbidden items removed
        """
        try:
            from alpha_forge_filter import get_allowed_opportunities

            # Extract user guidance lists
            custom_forbidden = guidance.get("forbidden") if guidance else None
            custom_encouraged = guidance.get("encouraged") if guidance else None

            return get_allowed_opportunities(
                opportunities,
                custom_forbidden=custom_forbidden,
                custom_encouraged=custom_encouraged,
            )
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
            iteration: Current Ralph iteration number

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
