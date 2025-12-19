#!/usr/bin/env python3
# /// script
# requires-python = ">=3.11"
# dependencies = ["rapidfuzz>=3.0.0,<4.0.0"]
# ///
"""
Autonomous improvement engine Stop hook - FIXED SCHEMA VERSION.

Schema correction based on Claude Code docs:
- To ALLOW stop: return {} (empty object) - NOT {"continue": false}
- To CONTINUE (prevent stop): return {"decision": "block", "reason": "..."}
- To HARD STOP: return {"continue": false} - overrides everything

The previous version used {"continue": false} to "allow stop" but this actually
means "hard stop Claude entirely", which is why Claude showed "Stop hook
prevented continuation".

Conventions aligned with claude-agent-sdk-python:
- Hook output uses SDK-compatible JSON fields (continue, decision, reason)
- Time tracking uses project-level timestamp from /ralph:start invocation
- Logging uses duration_ms convention where applicable
"""
import json
import logging
import os
import subprocess
import sys
import time
from pathlib import Path

# Configure logging
logging.basicConfig(
    level=logging.DEBUG,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[logging.FileHandler(Path.home() / '.claude/automation/loop-orchestrator/state/loop-hook.log')]
)
logger = logging.getLogger(__name__)

STATE_DIR = Path.home() / ".claude/automation/loop-orchestrator/state"
CONFIG_FILE = STATE_DIR.parent / "config/loop_config.json"

# Loop detection constants
LOOP_THRESHOLD = 0.9
WINDOW_SIZE = 5


def get_elapsed_hours(session_id: str, project_dir: str) -> float:
    """Get elapsed time from loop start timestamp.

    Priority:
    1. Project-level .claude/loop-start-timestamp (created by /ralph:start)
    2. Session timestamp (fallback for backwards compatibility)
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
    timestamp_file = Path.home() / f".claude/automation/claude-orchestrator/state/session_timestamps/{session_id}.timestamp"
    if timestamp_file.exists():
        try:
            start_time = int(timestamp_file.read_text().strip())
            return (time.time() - start_time) / 3600
        except (ValueError, OSError):
            pass
    return 0.0


def check_task_complete(plan_file: str | None) -> bool:
    """Check for [x] TASK_COMPLETE marker."""
    if not plan_file or not Path(plan_file).exists():
        return False
    try:
        content = Path(plan_file).read_text()
        for line in content.split('\n'):
            line_stripped = line.strip()
            if line_stripped in ('- [x] TASK_COMPLETE', '[x] TASK_COMPLETE'):
                return True
    except OSError:
        pass
    return False


def detect_loop(current_output: str, recent_outputs: list[str]) -> bool:
    """Detect if agent is looping based on output similarity."""
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
    """Extract a markdown section by header."""
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


def build_continuation_prompt(
    session_id: str,
    plan_file: str | None,
    project_dir: str,
    elapsed: float,
    iteration: int,
    config: dict,
    task_complete: bool
) -> str:
    """Build context-rich continuation prompt."""
    parts = []
    remaining_hours = max(0, config["min_hours"] - elapsed)
    remaining_iters = max(0, config.get("min_iterations", 50) - iteration)
    mode = "EXPLORATION" if task_complete else "IMPLEMENTATION"
    parts.append(f"**{mode} MODE** | Iteration {iteration}/{config['max_iterations']} | {elapsed:.1f}h elapsed | {remaining_hours:.1f}h / {remaining_iters} iters remaining")

    if plan_file and Path(plan_file).exists():
        try:
            plan_content = Path(plan_file).read_text()
            if "## Current Focus" in plan_content:
                focus = extract_section(plan_content, "## Current Focus")
                if focus:
                    parts.append(f"\n**CURRENT FOCUS**:\n{focus[:500]}")
            dead_ends = []
            for line in plan_content.split('\n'):
                if 'dead end' in line.lower() or '❌' in line or 'AVOID:' in line:
                    dead_ends.append(line.strip())
            if dead_ends:
                parts.append(f"\n**AVOID (already tried, failed)**:\n" + "\n".join(dead_ends[:5]))
            if "## User Decisions" in plan_content:
                decisions = extract_section(plan_content, "## User Decisions")
                if decisions:
                    parts.append(f"\n**USER DECISIONS (must respect)**:\n{decisions[:500]}")
        except OSError:
            pass

    if project_dir:
        exploration_log = Path(project_dir) / ".claude/exploration_log.jsonl"
        if exploration_log.exists():
            try:
                lines = exploration_log.read_text().strip().split('\n')[-3:]
                recent = []
                for line in lines:
                    if line.strip():
                        entry = json.loads(line)
                        recent.append(f"- [{entry.get('action', 'unknown')}] {entry.get('target', '')} → {entry.get('outcome', '')}")
                if recent:
                    parts.append(f"\n**RECENT ACTIONS** (continue from here):\n" + "\n".join(recent))
            except (json.JSONDecodeError, KeyError, OSError):
                pass

    if project_dir:
        try:
            result = subprocess.run(
                ["git", "diff", "--stat", "HEAD~3", "--", "."],
                cwd=project_dir,
                capture_output=True,
                text=True,
                timeout=5
            )
            if result.returncode == 0 and result.stdout.strip():
                parts.append(f"\n**RECENT GIT CHANGES**:\n```\n{result.stdout[:300]}\n```")
        except (subprocess.TimeoutExpired, FileNotFoundError, OSError):
            pass

    if task_complete:
        parts.append("""
**EXPLORATION MODE** - Task marked complete but minimum time/iterations not met.
Continue exploring: code quality, robustness, documentation, performance.""")
    else:
        parts.append("""
**IMPLEMENTATION MODE** - Continue working on the primary task.""")

    return "\n".join(parts)


def allow_stop(reason: str | None = None):
    """Allow session to stop normally. Returns empty object per Claude Code docs."""
    if reason:
        logger.info(f"Allowing stop: {reason}")
    # CORRECT: Empty object means "allow stop" - NOT {"continue": false}
    print(json.dumps({}))


def continue_session(reason: str):
    """Prevent stop and continue session. Uses decision: block per Claude Code docs."""
    logger.info(f"Continuing session: {reason[:100]}...")
    # CORRECT: decision=block means "prevent stop, keep session alive"
    print(json.dumps({"decision": "block", "reason": reason}))


def hard_stop(reason: str):
    """Hard stop Claude entirely. Uses continue: false which overrides everything."""
    logger.info(f"Hard stopping: {reason}")
    # continue=false means "hard stop" - use sparingly
    print(json.dumps({"continue": False, "stopReason": reason}))


def main():
    """Main entry point for the Stop hook."""
    try:
        hook_input = json.load(sys.stdin) if not sys.stdin.isatty() else {}
    except json.JSONDecodeError:
        hook_input = {}

    session_id = hook_input.get("session_id", "unknown")
    stop_hook_active = hook_input.get("stop_hook_active", False)
    transcript_path = hook_input.get("transcript_path")

    logger.info(f"Stop hook called: session={session_id}, stop_hook_active={stop_hook_active}")

    project_dir = os.environ.get("CLAUDE_PROJECT_DIR", "")

    # ===== EARLY EXIT CHECKS =====

    # Check #0: Loop mode not enabled → allow normal stop
    loop_enabled_file = Path(project_dir) / ".claude/loop-enabled" if project_dir else None
    if not loop_enabled_file or not loop_enabled_file.exists():
        allow_stop("Loop not enabled for this repo")
        return

    # Check #0.5: Kill switch → hard stop
    kill_switch = Path(project_dir) / ".claude/STOP_LOOP"
    if kill_switch.exists():
        kill_switch.unlink()
        loop_enabled_file.unlink(missing_ok=True)
        hard_stop("Loop stopped via kill switch (.claude/STOP_LOOP)")
        return

    # NOTE: We intentionally do NOT exit early when stop_hook_active=True
    # The stop_hook_active flag means "a hook blocked the previous stop" but
    # for Ralph loops, we WANT to block multiple times until minimums are met.
    # True infinite loop prevention is handled by max_iterations and max_hours.

    # ===== LOAD STATE =====
    state_file = STATE_DIR / f"sessions/{session_id}.json"
    try:
        state = json.loads(state_file.read_text()) if state_file.exists() else {
            "iteration": 0,
            "recent_outputs": [],
            "plan_file": None
        }
    except (json.JSONDecodeError, OSError):
        state = {"iteration": 0, "recent_outputs": [], "plan_file": None}

    # Load config
    try:
        config = json.loads(CONFIG_FILE.read_text()) if CONFIG_FILE.exists() else {
            "min_hours": 4, "max_hours": 9, "min_iterations": 50, "max_iterations": 99
        }
    except (json.JSONDecodeError, OSError):
        config = {"min_hours": 4, "max_hours": 9, "min_iterations": 50, "max_iterations": 99}

    # Environment variable overrides
    if os.environ.get("LOOP_MIN_HOURS"):
        config["min_hours"] = float(os.environ["LOOP_MIN_HOURS"])
    if os.environ.get("LOOP_MAX_HOURS"):
        config["max_hours"] = float(os.environ["LOOP_MAX_HOURS"])
    if os.environ.get("LOOP_MIN_ITERATIONS"):
        config["min_iterations"] = int(os.environ["LOOP_MIN_ITERATIONS"])
    if os.environ.get("LOOP_MAX_ITERATIONS"):
        config["max_iterations"] = int(os.environ["LOOP_MAX_ITERATIONS"])

    # Also check project-level config
    project_config = Path(project_dir) / ".claude/loop-config.json" if project_dir else None
    if project_config and project_config.exists():
        try:
            proj_cfg = json.loads(project_config.read_text())
            config.update(proj_cfg)
            logger.info(f"Loaded project config: {proj_cfg}")
        except (json.JSONDecodeError, OSError):
            pass

    elapsed = get_elapsed_hours(session_id, project_dir)
    iteration = state["iteration"] + 1
    recent_outputs: list[str] = state.get("recent_outputs", [])

    logger.info(f"Iteration {iteration}, elapsed {elapsed:.2f}h, config={config}")

    # Extract current output for loop detection
    current_output = ""
    if transcript_path and Path(transcript_path).exists():
        try:
            lines = Path(transcript_path).read_text().strip().split('\n')
            if lines:
                last_entry = json.loads(lines[-1])
                if last_entry.get("type") == "assistant":
                    # content is a list of content blocks, extract text from each
                    content = last_entry.get("message", {}).get("content", [])
                    if isinstance(content, list):
                        text_parts = []
                        for block in content:
                            if isinstance(block, dict) and block.get("type") == "text":
                                text_parts.append(block.get("text", ""))
                        current_output = " ".join(text_parts)[:1000]
                    elif isinstance(content, str):
                        current_output = content[:1000]
        except (json.JSONDecodeError, KeyError, IndexError, OSError, TypeError):
            pass

    # ===== COMPLETION CASCADE =====

    # Check #2: Max time → allow stop
    if elapsed >= config["max_hours"]:
        allow_stop(f"Maximum runtime ({config['max_hours']}h) reached")
        return

    # Check #3: Max iterations → allow stop
    if iteration >= config["max_iterations"]:
        allow_stop(f"Maximum iterations ({config['max_iterations']}) reached")
        return

    # Check #4: Loop detected → allow stop
    if detect_loop(current_output, recent_outputs):
        allow_stop("Loop detected: agent producing repetitive outputs (>90% similar)")
        return

    # Check #5: Task complete + minimums met → allow stop
    task_complete = check_task_complete(state.get("plan_file"))
    min_hours_met = elapsed >= config["min_hours"]
    min_iterations_met = iteration >= config.get("min_iterations", 50)

    if task_complete and min_hours_met and min_iterations_met:
        allow_stop("Task complete and all minimum requirements met")
        return

    # ===== CONTINUE SESSION =====
    reason = build_continuation_prompt(
        session_id=session_id,
        plan_file=state.get("plan_file"),
        project_dir=project_dir,
        elapsed=elapsed,
        iteration=iteration,
        config=config,
        task_complete=task_complete
    )

    # Update state
    if current_output:
        recent_outputs.append(current_output)
        if len(recent_outputs) > WINDOW_SIZE:
            recent_outputs = recent_outputs[-WINDOW_SIZE:]

    state["iteration"] = iteration
    state["recent_outputs"] = recent_outputs

    # Save state
    try:
        state_file.parent.mkdir(parents=True, exist_ok=True)
        state_file.write_text(json.dumps(state, indent=2))
    except OSError as e:
        logger.error(f"Failed to save state: {e}")

    # CONTINUE the session
    continue_session(reason)


if __name__ == "__main__":
    main()
