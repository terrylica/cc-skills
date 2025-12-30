"""Alpha Forge SLO Value Metrics Tracker.

ADR: /docs/adr/2025-12-20-ralph-rssi-eternal-loop.md

Tracks meaningful work per session and integrates with alpha-forge's
existing research_sessions/ tracking system.

Metrics tracked per session:
- ROADMAP items completed
- Features added
- Meaningful code lines
- Busywork opportunities skipped

Outputs:
1. TodoWrite: Live todo list updates
2. research_log.md: Append iteration narratives
3. .claude/ralph-metrics.json: JSON metrics for programmatic access
"""

from __future__ import annotations

import json
from dataclasses import dataclass, field
from datetime import datetime
from pathlib import Path

from work_policy import Priority, WorkItem


@dataclass
class IterationMetrics:
    """Metrics for a single Ralph iteration."""

    iteration: int
    timestamp: str
    work_item: str | None = None
    priority: str = "P1"
    lines_changed: int = 0
    files_changed: int = 0
    slo_aligned: bool = True
    skipped_busywork: int = 0
    expert_consultations: int = 0
    checkpoint_result: str = "PASS"  # PASS, FAIL, SKIP


@dataclass
class SessionMetrics:
    """Cumulative metrics for the entire Ralph session."""

    session_id: str
    start_time: str
    iterations: list[IterationMetrics] = field(default_factory=list)
    roadmap_items_completed: int = 0
    features_added: int = 0
    total_lines_changed: int = 0
    total_files_changed: int = 0
    busywork_skipped: int = 0
    checkpoints_passed: int = 0
    checkpoints_failed: int = 0
    current_phase: str | None = None

    def to_dict(self) -> dict:
        """Convert to dictionary for JSON serialization."""
        return {
            "session_id": self.session_id,
            "start_time": self.start_time,
            "last_updated": datetime.now().isoformat(),
            "summary": {
                "iterations": len(self.iterations),
                "roadmap_items_completed": self.roadmap_items_completed,
                "features_added": self.features_added,
                "total_lines_changed": self.total_lines_changed,
                "total_files_changed": self.total_files_changed,
                "busywork_skipped": self.busywork_skipped,
                "checkpoints_passed": self.checkpoints_passed,
                "checkpoints_failed": self.checkpoints_failed,
                "current_phase": self.current_phase,
            },
            "iterations": [
                {
                    "iteration": i.iteration,
                    "timestamp": i.timestamp,
                    "work_item": i.work_item,
                    "priority": i.priority,
                    "lines_changed": i.lines_changed,
                    "files_changed": i.files_changed,
                    "slo_aligned": i.slo_aligned,
                    "checkpoint_result": i.checkpoint_result,
                }
                for i in self.iterations
            ],
        }


class ValueMetricsTracker:
    """Tracks SLO value metrics for Alpha Forge projects."""

    def __init__(self, project_dir: Path, session_id: str | None = None):
        """Initialize tracker.

        Args:
            project_dir: Path to project root
            session_id: Optional session ID (auto-generated if not provided)
        """
        self.project_dir = project_dir
        self.session_id = session_id or datetime.now().strftime("slo_%Y%m%d_%H%M%S")
        self.metrics_file = project_dir / ".claude" / "ralph-metrics.json"
        self.session = self._load_or_create_session()

    def _load_or_create_session(self) -> SessionMetrics:
        """Load existing session or create new one."""
        if self.metrics_file.exists():
            try:
                data = json.loads(self.metrics_file.read_text())
                if data.get("session_id") == self.session_id:
                    # Resume existing session
                    session = SessionMetrics(
                        session_id=data["session_id"],
                        start_time=data["start_time"],
                        roadmap_items_completed=data["summary"]["roadmap_items_completed"],
                        features_added=data["summary"]["features_added"],
                        total_lines_changed=data["summary"]["total_lines_changed"],
                        total_files_changed=data["summary"]["total_files_changed"],
                        busywork_skipped=data["summary"]["busywork_skipped"],
                        checkpoints_passed=data["summary"]["checkpoints_passed"],
                        checkpoints_failed=data["summary"]["checkpoints_failed"],
                        current_phase=data["summary"].get("current_phase"),
                    )
                    return session
            except (json.JSONDecodeError, KeyError):
                pass

        # Create new session
        return SessionMetrics(
            session_id=self.session_id,
            start_time=datetime.now().isoformat(),
        )

    def record_iteration(
        self,
        work_item: WorkItem | None,
        *,
        lines_changed: int = 0,
        files_changed: int = 0,
        skipped_busywork: int = 0,
        slo_aligned: bool = True,
        checkpoint_result: str = "PASS",
    ) -> IterationMetrics:
        """Record metrics for a single iteration.

        Args:
            work_item: Work item that was processed
            lines_changed: Lines of code changed
            files_changed: Number of files changed
            skipped_busywork: Number of busywork opportunities skipped
            slo_aligned: Whether work was SLO-aligned
            checkpoint_result: PASS, FAIL, or SKIP

        Returns:
            The recorded IterationMetrics
        """
        iteration_num = len(self.session.iterations) + 1

        metrics = IterationMetrics(
            iteration=iteration_num,
            timestamp=datetime.now().isoformat(),
            work_item=work_item.title if work_item else None,
            priority=work_item.priority.name if work_item else "UNKNOWN",
            lines_changed=lines_changed,
            files_changed=files_changed,
            slo_aligned=slo_aligned,
            skipped_busywork=skipped_busywork,
            checkpoint_result=checkpoint_result,
        )

        self.session.iterations.append(metrics)

        # Update cumulative metrics
        self.session.total_lines_changed += lines_changed
        self.session.total_files_changed += files_changed
        self.session.busywork_skipped += skipped_busywork

        if checkpoint_result == "PASS":
            self.session.checkpoints_passed += 1
            if work_item and work_item.source == "roadmap":
                self.session.roadmap_items_completed += 1
            if work_item and work_item.priority == Priority.P1:
                self.session.features_added += 1
        elif checkpoint_result == "FAIL":
            self.session.checkpoints_failed += 1

        # Persist to file
        self._save()

        return metrics

    def update_phase(self, phase: str) -> None:
        """Update current ROADMAP phase.

        Args:
            phase: Phase identifier (e.g., "2.0")
        """
        self.session.current_phase = phase
        self._save()

    def _save(self) -> None:
        """Save metrics to JSON file."""
        self.metrics_file.parent.mkdir(parents=True, exist_ok=True)
        self.metrics_file.write_text(
            json.dumps(self.session.to_dict(), indent=2)
        )

    def get_summary(self) -> dict:
        """Get summary metrics for display.

        Returns:
            Summary dict with key metrics
        """
        return self.session.to_dict()["summary"]

    def format_research_log_entry(self, iteration: IterationMetrics) -> str:
        """Format an iteration as a research_log.md entry.

        Args:
            iteration: The iteration metrics

        Returns:
            Markdown-formatted log entry
        """
        status_emoji = "✅" if iteration.checkpoint_result == "PASS" else "❌"

        return f"""
## Iteration {iteration.iteration}: {iteration.timestamp}

### Work Item
- **Task**: {iteration.work_item or "N/A"}
- **Priority**: {iteration.priority}
- **SLO Aligned**: {"Yes" if iteration.slo_aligned else "No"}

### Changes
- Lines changed: {iteration.lines_changed}
- Files changed: {iteration.files_changed}
- Busywork skipped: {iteration.skipped_busywork}

### Checkpoint Result
{status_emoji} **{iteration.checkpoint_result}**

---
"""

    def append_to_research_log(self, iteration: IterationMetrics) -> None:
        """Append iteration to alpha-forge research_log.md.

        Args:
            iteration: The iteration to log
        """
        # Find active research session
        sessions_dir = self.project_dir / "outputs" / "research_sessions"
        if not sessions_dir.exists():
            return

        # Get most recent session directory
        session_dirs = sorted(sessions_dir.glob("session_*"), reverse=True)
        if not session_dirs:
            return

        log_file = session_dirs[0] / "research_log.md"
        entry = self.format_research_log_entry(iteration)

        # Append to log
        with log_file.open("a") as f:
            f.write(entry)


def load_metrics(project_dir: Path) -> SessionMetrics | None:
    """Load existing metrics from file.

    Args:
        project_dir: Path to project root

    Returns:
        SessionMetrics if file exists, None otherwise
    """
    metrics_file = project_dir / ".claude" / "ralph-metrics.json"
    if not metrics_file.exists():
        return None

    try:
        data = json.loads(metrics_file.read_text())
        return SessionMetrics(
            session_id=data["session_id"],
            start_time=data["start_time"],
            roadmap_items_completed=data["summary"]["roadmap_items_completed"],
            features_added=data["summary"]["features_added"],
            total_lines_changed=data["summary"]["total_lines_changed"],
            total_files_changed=data["summary"]["total_files_changed"],
            busywork_skipped=data["summary"]["busywork_skipped"],
            checkpoints_passed=data["summary"]["checkpoints_passed"],
            checkpoints_failed=data["summary"]["checkpoints_failed"],
            current_phase=data["summary"].get("current_phase"),
        )
    except (json.JSONDecodeError, KeyError):
        return None
