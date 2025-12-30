#!/usr/bin/env python3
# /// script
# requires-python = ">=3.11"
# dependencies = ["pydantic>=2.10.0", "filelock>=3.20.0"]
# ///
"""PreToolUse hook: Guard loop control files from deletion.

Prevents Claude from bypassing the Stop hook by directly running
Bash commands that delete .claude/loop-enabled or other loop files.

NOTE: Idle command detection (git status spam) is handled by the Stop hook
using stamina-style exponential backoff in loop-until-done.py.

Protected files and deletion patterns are configurable via
.claude/ralph-config.json.

ADR: /docs/adr/2025-12-20-ralph-rssi-eternal-loop.md
ADR: /docs/adr/2025-12-17-posttooluse-hook-visibility.md (output format)
"""

import json
import os
import re
import sys

from core.config_schema import ProtectionConfig, load_config

def get_protection_config() -> ProtectionConfig:
    """Get protection parameters from config."""
    project_dir = os.environ.get("CLAUDE_PROJECT_DIR", "")
    config = load_config(project_dir if project_dir else None)
    return config.protection


def is_official_ralph_command(command: str) -> bool:
    """Check if command is an official Ralph command with bypass marker.

    Any command containing a registered bypass marker (e.g., RALPH_STOP_SCRIPT,
    RALPH_ENCOURAGE_SCRIPT) is allowed to operate on protected files.
    """
    cfg = get_protection_config()
    # Check new bypass_markers list first
    for marker in cfg.bypass_markers:
        if marker in command:
            return True
    # Fallback to legacy single marker for backward compatibility
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
    # ===== ALPHA-FORGE ONLY GUARD =====
    # Ralph is dedicated to alpha-forge ML research workflows only.
    # Skip all processing for non-alpha-forge projects (zero overhead).
    project_dir = os.environ.get("CLAUDE_PROJECT_DIR", "")
    if project_dir:
        from core.project_detection import is_alpha_forge_project
        if not is_alpha_forge_project(project_dir):
            # Silent pass-through: allow command, no Ralph processing
            # Using modern permissionDecision format (not deprecated decision:allow)
            print(json.dumps({
                "hookSpecificOutput": {
                    "hookEventName": "PreToolUse",
                    "permissionDecision": "allow"
                }
            }))
            return

    # Read tool input from stdin
    try:
        tool_input = json.load(sys.stdin)
    except json.JSONDecodeError as e:
        # Can't parse input, allow the command but warn
        print(f"[ralph] Warning: Failed to parse tool input: {e}", file=sys.stderr)
        print(json.dumps({
            "hookSpecificOutput": {
                "hookEventName": "PreToolUse",
                "permissionDecision": "allow"
            }
        }))
        return

    # Get the command being executed
    command = tool_input.get("command", "")

    # Helper for allow response (modern format)
    def allow_command():
        print(json.dumps({
            "hookSpecificOutput": {
                "hookEventName": "PreToolUse",
                "permissionDecision": "allow"
            }
        }))

    if not command:
        allow_command()
        return

    # Allow official Ralph commands to operate on protected files
    if is_official_ralph_command(command):
        allow_command()
        return

    # Check if this is a deletion attempt on protected files
    if is_deletion_command(command):
        # Using modern permissionDecision format (not deprecated decision:block)
        result = {
            "hookSpecificOutput": {
                "hookEventName": "PreToolUse",
                "permissionDecision": "deny",
                "permissionDecisionReason": (
                    "[RALPH LOOP GUARD] Cannot delete loop control files. "
                    "The Ralph autonomous loop is active. Only the user can stop it "
                    "by running /ralph:stop or removing .claude/loop-enabled manually. "
                    "Continue working on improvement opportunities instead."
                ),
            }
        }
        print(json.dumps(result))
        return

    # Allow all other commands
    allow_command()


if __name__ == "__main__":
    main()
