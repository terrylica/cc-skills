"""Utility functions for Ralph hook.

Provides time tracking, loop detection, text extraction, and hook output helpers.
"""
import json
import logging
import os
import sys
import time
from datetime import datetime
from pathlib import Path

from core.config_schema import load_config
from core.constants import CLI_GAP_THRESHOLD

logger = logging.getLogger(__name__)

# Window size for loop detection (used by detect_loop)
WINDOW_SIZE = 5


def get_loop_detection_config() -> tuple[float, int]:
    """Get loop detection parameters from config.

    Returns:
        Tuple of (similarity_threshold, window_size)
    """
    project_dir = os.environ.get("CLAUDE_PROJECT_DIR", "")
    config = load_config(project_dir if project_dir else None)
    return (
        config.loop_detection.similarity_threshold,
        config.loop_detection.window_size,
    )


def get_wall_clock_hours(session_id: str, project_dir: str) -> float:
    """Get wall-clock elapsed time from loop start timestamp.

    This returns the total calendar time since /ralph:start, including any
    periods when Claude Code CLI was closed. For CLI runtime tracking, use
    get_runtime_hours() instead.

    Priority:
    1. Project-level .claude/loop-start-timestamp (created by /ralph:start)
    2. Session timestamp (fallback for backwards compatibility)

    Args:
        session_id: Claude session ID
        project_dir: Path to project root

    Returns:
        Wall-clock elapsed hours since loop started
    """
    # Priority 1: Project-level loop start timestamp
    if project_dir:
        loop_timestamp = Path(project_dir) / ".claude/loop-start-timestamp"
        if loop_timestamp.exists():
            try:
                start_time = int(loop_timestamp.read_text().strip())
                return (time.time() - start_time) / 3600
            except (ValueError, OSError):
                pass

    # Priority 2: Session timestamp (fallback)
    timestamp_file = (
        Path.home() /
        f".claude/automation/claude-orchestrator/state/session_timestamps/{session_id}.timestamp"
    )
    if timestamp_file.exists():
        try:
            start_time = int(timestamp_file.read_text().strip())
            return (time.time() - start_time) / 3600
        except (ValueError, OSError):
            pass
    return 0.0


def update_runtime(state: dict, current_time: float, gap_threshold: int = CLI_GAP_THRESHOLD) -> float:
    """Update accumulated runtime based on gap detection.

    Tracks CLI active time by detecting gaps between hook calls.
    If gap > threshold, CLI was closed - don't count that time.
    If gap <= threshold, CLI was active - add to runtime.

    Args:
        state: Session state dict (will be mutated with new values)
        current_time: Current Unix timestamp (time.time())
        gap_threshold: Seconds before gap indicates CLI closure (default CLI_GAP_THRESHOLD)

    Returns:
        Updated accumulated runtime in seconds
    """
    last_hook = state.get("last_hook_timestamp", 0.0)
    accumulated = state.get("accumulated_runtime_seconds", 0.0)

    if last_hook > 0:
        gap = current_time - last_hook
        if gap < gap_threshold:
            # Normal iteration - CLI was active, add to runtime
            accumulated += gap
        else:
            # CLI was closed - don't add gap time
            logger.info(f"CLI pause detected: {gap:.0f}s gap > {gap_threshold}s threshold, not counting")

    # Update state with new values
    state["last_hook_timestamp"] = current_time
    state["accumulated_runtime_seconds"] = accumulated

    return accumulated


def get_runtime_hours(state: dict) -> float:
    """Get accumulated CLI runtime in hours.

    This returns the total time Claude Code CLI was actually running,
    excluding periods when the CLI was closed.

    Args:
        state: Session state dict containing accumulated_runtime_seconds

    Returns:
        Accumulated runtime in hours
    """
    return state.get("accumulated_runtime_seconds", 0.0) / 3600


def detect_loop(
    current_output: str,
    recent_outputs: list[str],
    threshold: float | None = None,
) -> bool:
    """Detect if agent is looping based on output similarity.

    Uses RapidFuzz for fuzzy string matching. If any recent output
    is >= threshold similar to current output, considers it a loop.

    Args:
        current_output: Current assistant output
        recent_outputs: List of recent outputs (up to window_size from config)
        threshold: Optional override for similarity threshold (default from config)

    Returns:
        True if loop detected, False otherwise
    """
    if not current_output:
        return False

    # Get threshold from config if not provided
    if threshold is None:
        config_threshold, _ = get_loop_detection_config()
        threshold = config_threshold

    try:
        from rapidfuzz import fuzz
        for prev_output in recent_outputs:
            ratio = fuzz.ratio(current_output, prev_output) / 100.0
            if ratio >= threshold:
                logger.info(f"Loop detected: {ratio:.2%} similarity (threshold: {threshold})")
                return True
        return False
    except ImportError:
        logger.warning("RapidFuzz not installed, skipping loop detection")
        return False


def extract_section(content: str, header: str) -> str:
    """Extract a markdown section by header.

    Extracts content from the specified header until the next header
    of equal or higher level.

    Args:
        content: Markdown content
        header: Header to extract (e.g., "## Current Focus")

    Returns:
        Section content (without the header line)
    """
    lines = content.split('\n')
    in_section = False
    section_lines = []
    header_level = header.count('#')
    for line in lines:
        if line.strip().startswith(header):
            in_section = True
            continue
        if in_section:
            if line.strip().startswith('#') and line.strip().count('#') <= header_level:
                break
            section_lines.append(line)
    return '\n'.join(section_lines).strip()


def _write_stop_cache(reason: str, decision: str, stop_type: str = "normal") -> None:
    """Write stop reason to cache file for observability.

    Best-effort: failures logged but don't block stop.

    Args:
        reason: Why the session stopped
        decision: The hook decision ("stop" or "hard_stop")
        stop_type: Type of stop ("normal" or "hard")
    """
    try:
        stop_cache = Path.home() / ".claude" / "ralph-stop-reason.json"
        stop_cache.parent.mkdir(parents=True, exist_ok=True)

        # Get session context for correlation
        project_dir = os.environ.get("CLAUDE_PROJECT_DIR", "")
        session_id = os.environ.get("CLAUDE_SESSION_ID", "unknown")

        stop_cache.write_text(json.dumps({
            "timestamp": datetime.now().isoformat(),
            "reason": reason,
            "decision": decision,
            "type": stop_type,
            "session_id": session_id,
            "project_dir": project_dir,
        }))
    except OSError as e:
        logger.warning(f"Failed to write stop cache: {e}")


def allow_stop(reason: str | None = None) -> None:
    """Allow session to stop with visible notification.

    Returns empty object per Claude Code docs.
    CORRECT: Empty object means "allow stop" - NOT {"continue": false}

    Args:
        reason: Optional reason for stopping (will be logged, cached, and shown to user)
    """
    if reason:
        logger.info(f"Allowing stop: {reason}")
        _write_stop_cache(reason, "stop", "normal")
        print(f"\n[RALPH] Session stopped: {reason}\n", file=sys.stderr)
    print(json.dumps({}))


def continue_session(reason: str) -> None:
    """Prevent stop and continue session.

    Uses decision: block per Claude Code docs.
    CORRECT: decision=block means "prevent stop, keep session alive"

    Args:
        reason: Reason/context to provide to Claude
    """
    logger.info(f"Continuing session: {reason[:100]}...")
    print(json.dumps({"decision": "block", "reason": reason}))


def hard_stop(reason: str) -> None:
    """Hard stop Claude entirely with visibility.

    Uses continue: false which overrides everything.
    Use sparingly - this terminates the session immediately.

    Args:
        reason: Reason for hard stop (will be logged, cached, and shown to user)
    """
    logger.info(f"Hard stopping: {reason}")
    _write_stop_cache(reason, "hard_stop", "hard")
    print(f"\n[RALPH] HARD STOP: {reason}\n", file=sys.stderr)
    print(json.dumps({"continue": False, "stopReason": reason}))
