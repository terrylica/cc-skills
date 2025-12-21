#!/usr/bin/env python3
"""Ralph Eternal Loop Harness - SDK-based fail-safe for autonomous loops.

This harness wraps Claude Code using the Claude Agent SDK Python to provide
bulletproof loop continuation. It intercepts ALL stop attempts and decides
programmatically whether to allow them.

Architecture:
    ┌─────────────────────────────────────────────────────────────┐
    │                  eternal_loop_harness.py                    │
    │  ┌─────────────┐    ┌──────────────┐    ┌───────────────┐  │
    │  │ ClaudeSDK   │───▶│  Stop Hook   │───▶│ Decision      │  │
    │  │ Client      │    │  Callback    │    │ Engine        │  │
    │  └─────────────┘    └──────────────┘    └───────────────┘  │
    │         │                  │                    │          │
    │         ▼                  ▼                    ▼          │
    │  ┌─────────────────────────────────────────────────────┐   │
    │  │           decision: "block" + reason               │   │
    │  │           (Claude CANNOT stop without approval)     │   │
    │  └─────────────────────────────────────────────────────┘   │
    └─────────────────────────────────────────────────────────────┘

Usage:
    # Start eternal loop for a project
    uv run python eternal_loop_harness.py /path/to/project "Implement feature X"

    # With POC mode (shorter timeouts for testing)
    uv run python eternal_loop_harness.py --poc /path/to/project "Quick test"

References:
    - Claude Agent SDK: https://docs.claude.com/en/docs/claude-code/sdk/sdk-python
    - Stop Hooks: https://docs.claude.com/en/docs/claude-code/hooks
    - Ralph Wiggum: https://paddo.dev/blog/ralph-wiggum-autonomous-loops/
"""

import argparse
import asyncio
import json
import logging
import os
import sys
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Any

# Add parent directory to path for imports
sys.path.insert(0, str(Path(__file__).parent.parent / "hooks"))

from claude_agent_sdk import ClaudeAgentOptions, ClaudeSDKClient
from claude_agent_sdk.types import (
    AssistantMessage,
    HookContext,
    HookInput,
    HookJSONOutput,
    HookMatcher,
    ResultMessage,
    TextBlock,
)

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
    handlers=[
        logging.StreamHandler(),
        logging.FileHandler("/tmp/ralph_eternal_loop.log"),
    ],
)
logger = logging.getLogger("ralph.eternal")


@dataclass
class LoopConfig:
    """Configuration for the eternal loop."""

    min_hours: float = 4.0
    max_hours: float = 9.0
    min_iterations: int = 50
    max_iterations: int = 99
    project_dir: Path = Path(".")
    task_prompt: str = ""
    poc_mode: bool = False

    def __post_init__(self) -> None:
        if self.poc_mode:
            self.min_hours = 0.083  # 5 minutes
            self.max_hours = 0.167  # 10 minutes
            self.min_iterations = 10
            self.max_iterations = 20


class EternalLoopState:
    """Tracks state across loop iterations."""

    def __init__(self, config: LoopConfig) -> None:
        self.config = config
        self.iteration = 0
        self.start_time = time.time()
        self.recent_outputs: list[str] = []
        self.stop_attempts = 0
        self.blocked_stops = 0

    def elapsed_hours(self) -> float:
        return (time.time() - self.start_time) / 3600

    def should_allow_stop(self) -> tuple[bool, str]:
        """Decide whether to allow Claude to stop.

        Returns:
            Tuple of (should_allow, reason)
        """
        elapsed = self.elapsed_hours()

        # Check kill switch
        kill_switch = self.config.project_dir / ".claude/STOP_LOOP"
        if kill_switch.exists():
            kill_switch.unlink()
            return True, "Kill switch activated (.claude/STOP_LOOP)"

        # Check loop-enabled marker
        loop_enabled = self.config.project_dir / ".claude/loop-enabled"
        if not loop_enabled.exists():
            return True, "Loop not enabled (missing .claude/loop-enabled)"

        # Check maximum limits (hard stop)
        if elapsed >= self.config.max_hours:
            return True, f"Maximum time reached ({self.config.max_hours}h)"

        if self.iteration >= self.config.max_iterations:
            return True, f"Maximum iterations reached ({self.config.max_iterations})"

        # Check minimum thresholds (must continue)
        if elapsed < self.config.min_hours:
            return False, (
                f"Minimum time not reached: {elapsed:.2f}h / {self.config.min_hours}h. "
                "Continue working on the task."
            )

        if self.iteration < self.config.min_iterations:
            return False, (
                f"Minimum iterations not reached: {self.iteration} / {self.config.min_iterations}. "
                "Continue working on the task."
            )

        # Between min and max thresholds - evaluate task completion
        # For now, default to continuing (can add RSSI logic here)
        return False, (
            f"Thresholds met but task not verified complete. "
            f"Iteration {self.iteration}, elapsed {elapsed:.2f}h. "
            "Continue unless explicitly blocked by user."
        )

    def record_stop_attempt(self, allowed: bool) -> None:
        """Record a stop attempt for metrics."""
        self.stop_attempts += 1
        if not allowed:
            self.blocked_stops += 1
        logger.info(
            f"Stop attempt #{self.stop_attempts}: {'ALLOWED' if allowed else 'BLOCKED'} "
            f"(blocked {self.blocked_stops}/{self.stop_attempts} total)"
        )


# Global state (shared across hook callbacks)
_loop_state: EternalLoopState | None = None


async def eternal_stop_hook(
    input_data: HookInput, tool_use_id: str | None, context: HookContext
) -> HookJSONOutput:
    """The eternal stop hook - blocks all stops unless conditions are met.

    This hook intercepts EVERY stop attempt from Claude and decides whether
    to allow it based on:
    1. Kill switch (.claude/STOP_LOOP file)
    2. Maximum time/iteration limits
    3. Minimum time/iteration thresholds
    4. Task completion status

    The key innovation: Claude literally CANNOT stop without this hook's approval.
    """
    global _loop_state

    if _loop_state is None:
        logger.error("Loop state not initialized!")
        return {}  # Allow stop on error

    # Check if we're already in a stop hook to prevent recursion
    stop_hook_active = input_data.get("stop_hook_active", False)
    if stop_hook_active:
        logger.warning("Stop hook already active - allowing stop to prevent recursion")
        return {}

    # Increment iteration counter
    _loop_state.iteration += 1

    # Decide whether to allow stop
    should_allow, reason = _loop_state.should_allow_stop()
    _loop_state.record_stop_attempt(should_allow)

    if should_allow:
        logger.info(f"ALLOWING STOP: {reason}")
        return {"stopReason": reason}
    else:
        logger.info(f"BLOCKING STOP: {reason}")
        # Build continuation prompt
        continuation_prompt = build_continuation_prompt(_loop_state, reason)
        return {
            "decision": "block",
            "reason": continuation_prompt,
        }


def build_continuation_prompt(state: EternalLoopState, reason: str) -> str:
    """Build the prompt that keeps Claude working."""
    elapsed = state.elapsed_hours()
    iteration = state.iteration
    config = state.config

    prompt = f"""## AUTONOMOUS LOOP CONTINUATION

**Status**: Iteration {iteration}/{config.max_iterations}, Elapsed {elapsed:.2f}h/{config.max_hours}h

**Why you cannot stop**: {reason}

---

## AUTONOMOUS MODE

**CRITICAL**: You are running in AUTONOMOUS LOOP MODE.

- DO NOT use AskUserQuestion
- DO NOT ask "what should I work on next?"
- DO NOT call /ralph:stop
- DO NOT stop the session on your own
- Make decisions autonomously and continue working

---

## YOUR TASK

{config.task_prompt if config.task_prompt else "Continue working on the current task. Check ROADMAP.md or .claude/plans/ for priorities."}

---

## PROTOCOL

1. Read focus files to understand current state
2. Identify the highest priority incomplete item
3. Implement it autonomously
4. Commit changes with descriptive message
5. Loop continues automatically

**Every 3rd iteration**: Use WebSearch to find SOTA techniques relevant to your task.

**NEVER idle. ALWAYS make progress. ALWAYS commit improvements.**
"""
    return prompt


async def run_eternal_loop(config: LoopConfig) -> None:
    """Run the eternal loop harness."""
    global _loop_state

    # Initialize state
    _loop_state = EternalLoopState(config)

    # Create loop-enabled marker
    loop_marker = config.project_dir / ".claude/loop-enabled"
    loop_marker.parent.mkdir(parents=True, exist_ok=True)
    loop_marker.touch()

    # Write start timestamp
    timestamp_file = config.project_dir / ".claude/loop-start-timestamp"
    timestamp_file.write_text(str(int(time.time())))

    # Write config
    config_file = config.project_dir / ".claude/ralph-config.json"
    config_data = {
        "version": "2.0.0",
        "state": "running",
        "poc_mode": config.poc_mode,
        "loop_limits": {
            "min_hours": config.min_hours,
            "max_hours": config.max_hours,
            "min_iterations": config.min_iterations,
            "max_iterations": config.max_iterations,
        },
        "harness": "sdk",  # Indicates SDK-based harness is in control
    }
    if config.task_prompt:
        config_data["task_prompt"] = config.task_prompt
    config_file.write_text(json.dumps(config_data, indent=2))

    logger.info("=" * 60)
    logger.info("  RALPH ETERNAL LOOP HARNESS (SDK)")
    logger.info("=" * 60)
    logger.info(f"Project: {config.project_dir}")
    logger.info(f"Mode: {'POC' if config.poc_mode else 'PRODUCTION'}")
    logger.info(f"Limits: {config.min_hours}h-{config.max_hours}h, {config.min_iterations}-{config.max_iterations} iters")
    logger.info(f"Task: {config.task_prompt or '(discover from focus files)'}")
    logger.info("=" * 60)

    # Configure SDK with Stop hook
    options = ClaudeAgentOptions(
        cwd=config.project_dir,
        permission_mode="bypassPermissions",  # Full autonomy
        hooks={
            "Stop": [
                HookMatcher(
                    matcher=None,  # Match all stop events
                    hooks=[eternal_stop_hook],
                    timeout=30.0,
                ),
            ],
        },
    )

    # Build initial prompt
    initial_prompt = f"""# Eternal Loop Session Started

You are now in an AUTONOMOUS ETERNAL LOOP managed by the Ralph SDK Harness.

## Configuration
- Mode: {'POC (5-10 min, 10-20 iters)' if config.poc_mode else 'Production (4-9h, 50-99 iters)'}
- Project: {config.project_dir}

## Your Task
{config.task_prompt if config.task_prompt else '''
Discover and work on the highest priority task:
1. Check .claude/plans/ for active plans
2. Check ROADMAP.md for P0/P1 priorities
3. Check docs/adr/ for accepted ADRs needing implementation
'''}

## Rules
- You CANNOT stop until minimum thresholds are met
- The harness will block ALL premature stop attempts
- Make autonomous decisions - do NOT ask the user
- Commit frequently with descriptive messages

**BEGIN WORKING NOW.**
"""

    try:
        async with ClaudeSDKClient(options=options) as client:
            await client.query(initial_prompt)

            async for msg in client.receive_messages():
                if isinstance(msg, AssistantMessage):
                    for block in msg.content:
                        if isinstance(block, TextBlock):
                            # Log Claude's output
                            logger.debug(f"Claude: {block.text[:200]}...")
                elif isinstance(msg, ResultMessage):
                    logger.info(
                        f"Session ended: {msg.result}, "
                        f"cost=${msg.total_cost_usd:.4f}, "
                        f"turns={msg.num_turns}"
                    )
                    break

    except KeyboardInterrupt:
        logger.info("Interrupted by user")
    except Exception as e:
        logger.exception(f"Error in eternal loop: {e}")
    finally:
        # Cleanup
        _loop_state = None
        logger.info(
            f"Loop ended: {_loop_state.iteration if _loop_state else '?'} iterations, "
            f"{_loop_state.elapsed_hours() if _loop_state else '?'}h"
        )


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Ralph Eternal Loop Harness - SDK-based autonomous loop"
    )
    parser.add_argument(
        "project_dir",
        type=Path,
        help="Project directory to work in",
    )
    parser.add_argument(
        "task",
        nargs="*",
        help="Task description (optional)",
    )
    parser.add_argument(
        "--poc",
        action="store_true",
        help="Use POC mode (5-10 min, 10-20 iterations)",
    )
    parser.add_argument(
        "--min-hours",
        type=float,
        help="Override minimum hours",
    )
    parser.add_argument(
        "--max-hours",
        type=float,
        help="Override maximum hours",
    )

    args = parser.parse_args()

    config = LoopConfig(
        project_dir=args.project_dir.resolve(),
        task_prompt=" ".join(args.task) if args.task else "",
        poc_mode=args.poc,
    )

    if args.min_hours:
        config.min_hours = args.min_hours
    if args.max_hours:
        config.max_hours = args.max_hours

    asyncio.run(run_eternal_loop(config))


if __name__ == "__main__":
    main()
