---
description: Start eternal loop using SDK harness (bulletproof stop prevention)
allowed-tools: Read, Bash
argument-hint: "[--poc] [<task description>...]"
---

# Ralph SDK Harness

Start an **SDK-controlled eternal loop** that provides bulletproof stop prevention using the Claude Agent SDK Python.

## Why Use This?

The SDK harness is more robust than the standard `/ralph:start` because:

| Feature              | Standard Hook            | SDK Harness            |
| -------------------- | ------------------------ | ---------------------- |
| Stop interception    | Shell script             | Python callback        |
| Error handling       | Exit codes               | Try/catch              |
| State management     | File-based               | In-memory + file       |
| Recursion prevention | `stop_hook_active` check | Same + programmatic    |
| Debugging            | Log files                | Rich logging + metrics |

## Usage

```bash
# From within Claude Code - delegates to external harness
/ralph:harness implement the new feature

# With POC mode for testing
/ralph:harness --poc quick test run
```

## How It Works

The harness:

1. Creates a `ClaudeSDKClient` with a programmatic Stop hook
2. Every stop attempt triggers the Python callback
3. Callback evaluates: kill switch, time limits, iteration counts
4. Returns `{"decision": "block", "reason": "..."}` to force continuation
5. Claude literally CANNOT stop without the harness's approval

## Step 1: Check Prerequisites

```bash
# Verify Claude Agent SDK is installed
uv pip show claude-agent-sdk || echo "SDK not installed"
```

## Step 2: Launch Harness

**IMPORTANT**: This launches a NEW Claude session controlled by the SDK harness.
The harness runs OUTSIDE of Claude Code and controls it programmatically.

```bash
# Use /usr/bin/env bash for macOS zsh compatibility (see ADR: shell-command-portability-zsh)
/usr/bin/env bash << 'RALPH_HARNESS_SCRIPT'
cd "${CLAUDE_PROJECT_DIR}"

# Parse arguments
ARGS="${ARGUMENTS:-}"
POC_FLAG=""
TASK=""

if [[ "$ARGS" == *"--poc"* ]]; then
    POC_FLAG="--poc"
    ARGS="${ARGS//--poc/}"
fi
TASK=$(echo "$ARGS" | xargs)

# Launch the harness (runs in foreground, Ctrl+C to stop)
HARNESS_PATH="$HOME/.claude/plugins/marketplaces/cc-skills/plugins/ralph/sdk/eternal_loop_harness.py"

if [[ -f "$HARNESS_PATH" ]]; then
    echo "Launching SDK Harness..."
    echo "Project: $(pwd)"
    echo "Mode: ${POC_FLAG:-production}"
    echo "Task: ${TASK:-discover from focus files}"
    echo ""
    echo "Press Ctrl+C to stop the harness"
    echo "Or create .claude/STOP_LOOP to graceful stop"
    echo ""

    uv run python "$HARNESS_PATH" $POC_FLAG "$(pwd)" $TASK
else
    echo "ERROR: Harness not found at $HARNESS_PATH"
    echo "Run: /plugin install cc-skills"
    exit 1
fi
RALPH_HARNESS_SCRIPT
```

## When to Use

| Scenario                    | Recommended                       |
| --------------------------- | --------------------------------- |
| Normal autonomous work      | `/ralph:start` (hook-based)       |
| Critical long-running tasks | `/ralph:harness` (SDK-based)      |
| Debugging stop issues       | `/ralph:harness` (better logging) |
| Maximum reliability needed  | `/ralph:harness`                  |

## Logs

The harness logs to:

- Console (stdout)
- `/tmp/ralph_eternal_loop.log`

## References

- [Claude Agent SDK Python](https://docs.claude.com/en/docs/claude-code/sdk/sdk-python)
- [Stop Hooks Reference](https://docs.claude.com/en/docs/claude-code/hooks)
- [Ralph Wiggum Blog Post](https://paddo.dev/blog/ralph-wiggum-autonomous-loops/)
