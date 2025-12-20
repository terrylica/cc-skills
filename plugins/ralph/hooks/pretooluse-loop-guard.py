#!/usr/bin/env python3
"""PreToolUse hook: Guard loop control files from deletion.

Prevents Claude from bypassing the Stop hook by directly running
Bash commands that delete .claude/loop-enabled or other loop files.

Protected files and deletion patterns are configurable via
.claude/ralph-config.json.

ADR: /docs/adr/2025-12-20-ralph-rssi-eternal-loop.md
"""

import json
import os
import re
import sys

from core.config_schema import ProtectionConfig, load_config

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
