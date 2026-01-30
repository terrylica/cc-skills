"""
Ralph Hook Observability - Dual-channel status output.

Terminal: stderr (Claude ignores, users see immediately)
Claude: JSON with decision:block (Claude sees and can respond)

Usage:
    from observability import emit, flush_to_claude, reset_timer

    emit("Config", "Loaded ru-config.json: 3 forbidden, 2 encouraged")
    emit("Discovery", "Found spec.md via transcript parsing")

    # At decision time, flush accumulated messages
    messages = flush_to_claude()
    if messages:
        full_reason = f"{messages}\n\n{reason}"
"""

from __future__ import annotations

import sys
import time
from typing import Literal

# Module-level state
_start_time: float = time.time()
_pending_messages: list[str] = []


def reset_timer() -> None:
    """Reset the start time for timing calculations."""
    global _start_time
    _start_time = time.time()


def emit(
    operation: str,
    detail: str,
    target: Literal["terminal", "claude", "both"] = "both",
) -> None:
    """
    Emit status message to specified audience(s).

    Args:
        operation: Category name (e.g., "Config", "Discovery", "Analysis")
        detail: Specific message content
        target: Where to send the message
            - "terminal": stderr only (user sees, Claude ignores)
            - "claude": Accumulate for JSON output (Claude sees)
            - "both": Both channels (default)
    """
    elapsed = time.time() - _start_time
    msg = f"[ralph] [{elapsed:.2f}s] {operation}: {detail}"

    if target in ("terminal", "both"):
        print(msg, file=sys.stderr)

    # Note: Claude visibility requires decision:block in final JSON output
    # Store messages for batch emission at decision time
    if target in ("claude", "both"):
        _pending_messages.append(msg)


def flush_to_claude() -> str | None:
    """
    Return accumulated messages for Claude visibility.

    Call this when building the decision JSON to include observability
    messages in the reason field.

    Returns:
        Newline-joined messages, or None if no messages accumulated.
    """
    global _pending_messages
    if not _pending_messages:
        return None
    result = "\n".join(_pending_messages)
    _pending_messages = []
    return result


def get_pending_count() -> int:
    """Get count of pending messages (for testing)."""
    return len(_pending_messages)
