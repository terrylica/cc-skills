"""Utility functions for Ralph hook.

Provides time tracking, loop detection, text extraction, and hook output helpers.
"""
import json
import logging
import os
import time
from pathlib import Path

from core.config_schema import load_config

logger = logging.getLogger(__name__)

# Legacy constants (deprecated - use config instead)
# Kept for backward compatibility with existing code
LOOP_THRESHOLD = 0.9
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


def get_elapsed_hours(session_id: str, project_dir: str) -> float:
    """Get elapsed time from loop start timestamp.

    Priority:
    1. Project-level .claude/loop-start-timestamp (created by /ralph:start)
    2. Session timestamp (fallback for backwards compatibility)

    Args:
        session_id: Claude session ID
        project_dir: Path to project root

    Returns:
        Elapsed hours since loop started
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


def allow_stop(reason: str | None = None) -> None:
    """Allow session to stop normally.

    Returns empty object per Claude Code docs.
    CORRECT: Empty object means "allow stop" - NOT {"continue": false}

    Args:
        reason: Optional reason for logging
    """
    if reason:
        logger.info(f"Allowing stop: {reason}")
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
    """Hard stop Claude entirely.

    Uses continue: false which overrides everything.
    Use sparingly - this terminates the session immediately.

    Args:
        reason: Reason for hard stop
    """
    logger.info(f"Hard stopping: {reason}")
    print(json.dumps({"continue": False, "stopReason": reason}))


def send_convergence_notification(
    reason: str,
    elapsed_hours: float,
    iteration: int,
    project_dir: str | None = None,
) -> None:
    """Send notification when Ralph loop converges/stops.

    Uses Pushover via CNS config. Called when allow_stop() is about to be invoked.
    Runs async to avoid blocking the hook.

    Args:
        reason: Reason for convergence/stop
        elapsed_hours: Total elapsed hours
        iteration: Final iteration number
        project_dir: Project directory for context
    """
    import subprocess
    import threading

    def _send():
        try:
            cns_config = Path.home() / ".claude/automation/cns/config/cns_config.json"
            if not cns_config.exists():
                logger.debug("CNS config not found, skipping notification")
                return

            config = json.loads(cns_config.read_text())
            pushover_user = config.get("pushover", {}).get("user_key", "")
            pushover_token = config.get("pushover", {}).get("app_token", "")

            if not pushover_user or not pushover_token:
                logger.debug("Pushover not configured, skipping notification")
                return

            # Build notification
            folder_name = Path(project_dir).name if project_dir else "unknown"
            hours_display = f"{elapsed_hours:.1f}h" if elapsed_hours >= 1 else f"{int(elapsed_hours * 60)}m"

            title = f"🎯 Ralph RSSI Converged"
            message = (
                f"📁 {folder_name}\n"
                f"⏱️ {hours_display} | 🔄 {iteration} iterations\n\n"
                f"{reason[:200]}"
            )

            # Send via curl (fire-and-forget)
            subprocess.run(
                [
                    "curl", "-s", "--connect-timeout", "3",
                    "-F", f"token={pushover_token}",
                    "-F", f"user={pushover_user}",
                    "-F", f"message={message}",
                    "-F", f"title={title}",
                    "-F", "sound=cosmic",
                    "https://api.pushover.net/1/messages.json"
                ],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                timeout=5,
            )
            logger.info("Ralph convergence notification sent")
        except Exception as e:
            logger.warning(f"Failed to send convergence notification: {e}")

    # Run async to avoid blocking
    threading.Thread(target=_send, daemon=True).start()
