"""Utility functions for Ralph hook.

Provides time tracking, loop detection, text extraction, and hook output helpers.
"""
import json
import logging
import time
from pathlib import Path

logger = logging.getLogger(__name__)

# Loop detection constants
LOOP_THRESHOLD = 0.9
WINDOW_SIZE = 5


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


def detect_loop(current_output: str, recent_outputs: list[str]) -> bool:
    """Detect if agent is looping based on output similarity.

    Uses RapidFuzz for fuzzy string matching. If any recent output
    is >= 90% similar to current output, considers it a loop.

    Args:
        current_output: Current assistant output
        recent_outputs: List of recent outputs (up to WINDOW_SIZE)

    Returns:
        True if loop detected, False otherwise
    """
    if not current_output:
        return False
    try:
        from rapidfuzz import fuzz
        for prev_output in recent_outputs:
            ratio = fuzz.ratio(current_output, prev_output) / 100.0
            if ratio >= LOOP_THRESHOLD:
                logger.info(f"Loop detected: {ratio:.2%} similarity")
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
