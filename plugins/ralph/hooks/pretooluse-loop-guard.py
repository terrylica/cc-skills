#!/usr/bin/env python3
"""PreToolUse hook: Guard loop control files from deletion.

Prevents Claude from bypassing the Stop hook by directly running
Bash commands that delete .claude/loop-enabled or other loop files.

ADR: /docs/adr/2025-12-20-ralph-rssi-eternal-loop.md
"""

import json
import os
import re
import sys

# Protected files that cannot be deleted via Bash
PROTECTED_FILES = [
    ".claude/loop-enabled",
    ".claude/loop-start-timestamp",
    ".claude/loop-config.json",
]

# Patterns that indicate deletion attempts
DELETION_PATTERNS = [
    r"\brm\b",           # rm command
    r"\bunlink\b",       # unlink command
    r"> /dev/null",      # Redirect to null (truncate)
    r">\s*/dev/null",    # Redirect with space
    r"truncate\b",       # truncate command
]

# Official /ralph:stop script marker - allow this to delete loop files
RALPH_STOP_MARKER = "RALPH_STOP_SCRIPT"


def is_official_stop_script(command: str) -> bool:
    """Check if command is the official /ralph:stop script."""
    return RALPH_STOP_MARKER in command


def is_deletion_command(command: str) -> bool:
    """Check if command attempts to delete protected files."""
    # Check for deletion patterns
    has_deletion_cmd = any(
        re.search(pattern, command) for pattern in DELETION_PATTERNS
    )

    if not has_deletion_cmd:
        return False

    # Check if any protected file is mentioned
    for protected_file in PROTECTED_FILES:
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
