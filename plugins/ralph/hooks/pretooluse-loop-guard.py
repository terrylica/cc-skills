#!/usr/bin/env python3
"""PreToolUse hook: Guard loop control files and prevent wasteful commands.

Features:
1. Prevents deletion of .claude/loop-enabled and other loop files
2. Blocks repetitive low-value commands (git status) when called too frequently

Protected files and deletion patterns are configurable via
.claude/ralph-config.json.

ADR: /docs/adr/2025-12-20-ralph-rssi-eternal-loop.md
"""

import json
import os
import re
import sys
import time
from pathlib import Path

from core.config_schema import ProtectionConfig, load_config

# Anti-idle: Block repetitive low-value commands
IDLE_COMMANDS = ["git status", "git status --short", "git status -s"]
IDLE_COOLDOWN_SECONDS = 30  # Minimum seconds between same idle command
IDLE_STATE_FILE = Path.home() / ".claude/automation/loop-orchestrator/state/idle-guard.json"

# Legacy constants (deprecated - use config instead)
PROTECTED_FILES = [
    ".claude/loop-enabled",
    ".claude/loop-start-timestamp",
    ".claude/loop-config.json",
]

DELETION_PATTERNS = [
    r"\brm\b",
    r"\bunlink\b",
    r"> /dev/null",
    r">\s*/dev/null",
    r"truncate\b",
]

RALPH_STOP_MARKER = "RALPH_STOP_SCRIPT"


def load_idle_state() -> dict:
    """Load idle command tracking state."""
    try:
        if IDLE_STATE_FILE.exists():
            return json.loads(IDLE_STATE_FILE.read_text())
    except (json.JSONDecodeError, OSError):
        pass
    return {"last_commands": {}}


def save_idle_state(state: dict) -> None:
    """Save idle command tracking state."""
    try:
        IDLE_STATE_FILE.parent.mkdir(parents=True, exist_ok=True)
        IDLE_STATE_FILE.write_text(json.dumps(state))
    except OSError:
        pass


def is_idle_command_too_frequent(command: str) -> tuple[bool, str]:
    """Check if an idle command is being called too frequently.

    Returns (is_blocked, reason).
    """
    # Normalize command for matching
    cmd_normalized = command.strip().lower()

    # Check if this is an idle command
    is_idle = any(idle_cmd in cmd_normalized for idle_cmd in IDLE_COMMANDS)
    if not is_idle:
        return False, ""

    state = load_idle_state()
    last_commands = state.get("last_commands", {})
    now = time.time()

    # Check if same command was called recently
    last_time = last_commands.get(cmd_normalized, 0)
    elapsed = now - last_time

    if elapsed < IDLE_COOLDOWN_SECONDS:
        return True, (
            f"[IDLE GUARD] Blocking repetitive '{command}' (called {elapsed:.0f}s ago, "
            f"cooldown is {IDLE_COOLDOWN_SECONDS}s). Do meaningful work instead."
        )

    # Update state with new timestamp
    last_commands[cmd_normalized] = now
    state["last_commands"] = last_commands
    save_idle_state(state)

    return False, ""


def get_protection_config() -> ProtectionConfig:
    """Get protection parameters from config."""
    project_dir = os.environ.get("CLAUDE_PROJECT_DIR", "")
    config = load_config(project_dir if project_dir else None)
    return config.protection


def is_official_stop_script(command: str) -> bool:
    """Check if command is the official /ralph:stop script."""
    cfg = get_protection_config()
    return cfg.stop_script_marker in command


def is_deletion_command(command: str) -> bool:
    """Check if command attempts to delete protected files."""
    cfg = get_protection_config()

    # Check for deletion patterns (from config)
    has_deletion_cmd = any(
        re.search(pattern, command) for pattern in cfg.deletion_patterns
    )

    if not has_deletion_cmd:
        return False

    # Check if any protected file is mentioned (from config)
    for protected_file in cfg.protected_files:
        # Check for full path or relative path
        if protected_file in command:
            return True
        # Check for just the filename
        filename = os.path.basename(protected_file)
        if filename in command:
            return True

    return False


def main():
    """Check Bash command and block if it deletes loop files."""
    # Read tool input from stdin
    try:
        tool_input = json.load(sys.stdin)
    except json.JSONDecodeError:
        # Can't parse input, allow the command
        print(json.dumps({"decision": "allow"}))
        return

    # Get the command being executed
    command = tool_input.get("command", "")

    if not command:
        print(json.dumps({"decision": "allow"}))
        return

    # Allow official /ralph:stop script to delete loop files
    if is_official_stop_script(command):
        print(json.dumps({"decision": "allow"}))
        return

    # Check for repetitive idle commands (git status spam)
    is_blocked, block_reason = is_idle_command_too_frequent(command)
    if is_blocked:
        print(json.dumps({"decision": "block", "reason": block_reason}))
        return

    # Check if this is a deletion attempt on protected files
    if is_deletion_command(command):
        result = {
            "decision": "block",
            "reason": (
                "[RALPH LOOP GUARD] Cannot delete loop control files. "
                "The Ralph autonomous loop is active. Only the user can stop it "
                "by running /ralph:stop or removing .claude/loop-enabled manually. "
                "Continue working on improvement opportunities instead."
            ),
        }
        print(json.dumps(result))
        return

    # Allow all other commands
    print(json.dumps({"decision": "allow"}))


if __name__ == "__main__":
    main()
