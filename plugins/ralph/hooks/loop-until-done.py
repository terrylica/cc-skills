#!/usr/bin/env python3
# /// script
# requires-python = ">=3.11"
# dependencies = ["rapidfuzz>=3.0.0,<4.0.0"]
# ///
"""
Autonomous improvement engine Stop hook.

CORRECTED Completion cascade (stop_hook_active FIRST):
0.  Loop not enabled → ALLOW STOP (skip all loop logic)
0.5 Kill switch file exists → ALLOW STOP + remove files
1.  stop_hook_active → STOP (hook recursion prevention - MUST BE FIRST)
2.  Max time (9h) → STOP
3.  Max iterations (99) → STOP
4.  Loop detected (RapidFuzz 90% similarity) → STOP
5.  TASK_COMPLETE + min time (4h) + min iterations (50) → STOP
6.  TASK_COMPLETE + under min → EXPLORE MODE
7.  Not complete → CONTINUE

Loop Detection (State-of-the-Art):
- Uses RapidFuzz library for fuzzy string matching (Levenshtein-based)
- 90% similarity threshold (balanced: catches loops, avoids false positives)
- 5-output sliding window (same as ralph-orchestrator)
- Graceful degradation if library not installed
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

# Loop detection constants (same as ralph-orchestrator)
LOOP_THRESHOLD = 0.9  # 90% similarity
WINDOW_SIZE = 5       # 5 previous outputs


def get_elapsed_hours(session_id: str) -> float:
    """Get elapsed time from session-start-tracker.sh timestamps."""
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
    """Detect if agent is looping based on output similarity.

    Uses RapidFuzz for fast fuzzy string matching (Levenshtein-based).
    If current output is >90% similar to any recent output, loop detected.

    This is the same approach used by ralph-orchestrator's SafetyGuard.
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
        # Graceful degradation: skip loop detection if rapidfuzz not installed
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
            # Stop at next header of same or higher level
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
    """Build context-rich, intelligent continuation prompt.

    This is the "Ralph Wiggum" injection - what Claude sees when asked to continue.
    Must be:
    - Plan-aware: Use plan file as "genius memory"
    - Context-aware: Know what was just done
    - Momentum-preserving: Continue where it left off
    - Dead-end avoiding: Don't repeat failed approaches
    - User-decision respecting: Honor explicit user choices
    """
    parts = []

    # 1. STATUS HEADER
    remaining_hours = max(0, config["min_hours"] - elapsed)
    remaining_iters = max(0, config.get("min_iterations", 50) - iteration)
    mode = "EXPLORATION" if task_complete else "IMPLEMENTATION"
    parts.append(f"**{mode} MODE** | Iteration {iteration}/{config['max_iterations']} | {elapsed:.1f}h elapsed | {remaining_hours:.1f}h / {remaining_iters} iters remaining")

    # 2. PLAN INTELLIGENCE ("Genius Memory")
    if plan_file and Path(plan_file).exists():
        try:
            plan_content = Path(plan_file).read_text()

            # Extract current focus (what we should be working on)
            if "## Current Focus" in plan_content:
                focus = extract_section(plan_content, "## Current Focus")
                if focus:
                    parts.append(f"\n**CURRENT FOCUS**:\n{focus[:500]}")

            # Extract dead ends to avoid (don't repeat failures)
            dead_ends = []
            for line in plan_content.split('\n'):
                if 'dead end' in line.lower() or '❌' in line or 'AVOID:' in line:
                    dead_ends.append(line.strip())
            if dead_ends:
                parts.append(f"\n**AVOID (already tried, failed)**:\n" + "\n".join(dead_ends[:5]))

            # Extract user decisions to respect
            if "## User Decisions" in plan_content:
                decisions = extract_section(plan_content, "## User Decisions")
                if decisions:
                    parts.append(f"\n**USER DECISIONS (must respect)**:\n{decisions[:500]}")
        except OSError:
            pass

    # 3. RECENT EXPLORATION LOG (momentum preservation)
    if project_dir:
        exploration_log = Path(project_dir) / ".claude/exploration_log.jsonl"
        if exploration_log.exists():
            try:
                lines = exploration_log.read_text().strip().split('\n')[-3:]  # Last 3 entries
                recent = []
                for line in lines:
                    if line.strip():
                        entry = json.loads(line)
                        recent.append(f"- [{entry.get('action', 'unknown')}] {entry.get('target', '')} → {entry.get('outcome', '')}")
                if recent:
                    parts.append(f"\n**RECENT ACTIONS** (continue from here):\n" + "\n".join(recent))
            except (json.JSONDecodeError, KeyError, OSError):
                pass

    # 4. GIT CONTEXT (what changed recently)
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

    # 5. ROLE AND EXPLORATION GUIDANCE
    if task_complete:
        parts.append("""
**EXPLORATION MODE** - Task marked complete but minimum time/iterations not met.

Act as **PM + Architect + Sr Engineer**. Systematically explore:

1. **CODE QUALITY**: Refactoring, error handling, test coverage, type safety
2. **ROBUSTNESS**: Edge cases, input validation, error recovery
3. **DOCUMENTATION**: Docstrings, README updates, inline comments
4. **PERFORMANCE**: Optimization opportunities, caching, lazy loading

**CRITICAL RULES**:
- Make decisions autonomously (no AskUserQuestion)
- Log every decision to `.claude/exploration_log.jsonl` with format:
  `{"timestamp": "...", "action": "...", "target": "...", "rationale": "...", "outcome": "..."}`
- Run `semantic-release` on significant milestones for backtrackability
- When truly done exploring, add `[x] TASK_COMPLETE` to plan file""")
    else:
        parts.append("""
**IMPLEMENTATION MODE** - Original task not yet complete.

Continue working on the primary task. Focus on:
- Completing the core functionality first
- Following the plan's implementation steps
- Testing as you go

When primary task is done, add `[x] TASK_COMPLETE` to plan file to enter exploration mode.""")

    return "\n".join(parts)


def main():
    """Main entry point for the Stop hook."""
    # CORRECT: Read hook input from stdin, not environment variable
    try:
        hook_input = json.load(sys.stdin) if not sys.stdin.isatty() else {}
    except json.JSONDecodeError:
        hook_input = {}

    session_id = hook_input.get("session_id", "unknown")
    stop_hook_active = hook_input.get("stop_hook_active", False)
    transcript_path = hook_input.get("transcript_path")

    logger.info(f"Stop hook called: session={session_id}, stop_hook_active={stop_hook_active}")

    # Use CLAUDE_PROJECT_DIR env var (available in ALL hooks, per research)
    project_dir = os.environ.get("CLAUDE_PROJECT_DIR", "")

    # ===== EARLY EXIT CHECKS (before loading state) =====

    # Check #0: Loop mode not enabled for this repo → skip entirely
    loop_enabled_file = Path(project_dir) / ".claude/loop-enabled" if project_dir else None
    if not loop_enabled_file or not loop_enabled_file.exists():
        # Loop not enabled - allow normal stop behavior
        logger.info("Loop not enabled for this repo, allowing stop")
        print(json.dumps({"decision": "allow"}))
        return

    # Check #0.5: Kill switch file exists → stop immediately
    kill_switch = Path(project_dir) / ".claude/STOP_LOOP"
    if kill_switch.exists():
        kill_switch.unlink()  # Remove kill switch file
        loop_enabled_file.unlink(missing_ok=True)  # Disable loop
        logger.info("Kill switch activated, stopping loop")
        print(json.dumps({
            "decision": "allow",
            "systemMessage": "Loop stopped via kill switch (.claude/STOP_LOOP)"
        }))
        return

    # ===== COMPLETION CASCADE (CORRECTED Priority Order) =====

    # 1. stop_hook_active → STOP (MUST BE FIRST per hooks lifecycle research)
    if stop_hook_active:
        logger.info("stop_hook_active=True, allowing stop to prevent recursion")
        print(json.dumps({"decision": "allow"}))
        return

    # Load state (only after passing early exits)
    state_file = STATE_DIR / f"sessions/{session_id}.json"
    try:
        state = json.loads(state_file.read_text()) if state_file.exists() else {
            "iteration": 0,
            "recent_outputs": [],  # Sliding window for loop detection
            "plan_file": None
        }
    except (json.JSONDecodeError, OSError):
        state = {"iteration": 0, "recent_outputs": [], "plan_file": None}

    # Load config (with environment variable overrides for POC testing)
    try:
        config = json.loads(CONFIG_FILE.read_text()) if CONFIG_FILE.exists() else {
            "min_hours": 4,
            "max_hours": 9,
            "min_iterations": 50,
            "max_iterations": 99
        }
    except (json.JSONDecodeError, OSError):
        config = {"min_hours": 4, "max_hours": 9, "min_iterations": 50, "max_iterations": 99}

    # Environment variable overrides for quick POC testing
    if os.environ.get("LOOP_MIN_HOURS"):
        config["min_hours"] = float(os.environ["LOOP_MIN_HOURS"])
    if os.environ.get("LOOP_MAX_HOURS"):
        config["max_hours"] = float(os.environ["LOOP_MAX_HOURS"])
    if os.environ.get("LOOP_MIN_ITERATIONS"):
        config["min_iterations"] = int(os.environ["LOOP_MIN_ITERATIONS"])
    if os.environ.get("LOOP_MAX_ITERATIONS"):
        config["max_iterations"] = int(os.environ["LOOP_MAX_ITERATIONS"])

    elapsed = get_elapsed_hours(session_id)
    iteration = state["iteration"] + 1
    recent_outputs: list[str] = state.get("recent_outputs", [])

    logger.info(f"Iteration {iteration}, elapsed {elapsed:.2f}h, config={config}")

    # Extract current output from transcript for loop detection
    current_output = ""
    if transcript_path and Path(transcript_path).exists():
        try:
            lines = Path(transcript_path).read_text().strip().split('\n')
            if lines:
                last_entry = json.loads(lines[-1])
                if last_entry.get("type") == "assistant":
                    current_output = last_entry.get("message", {}).get("content", "")[:1000]  # Limit for comparison
        except (json.JSONDecodeError, KeyError, IndexError, OSError):
            pass

    # 2. Max time (9h) → STOP
    if elapsed >= config["max_hours"]:
        logger.info(f"Max hours ({config['max_hours']}h) reached, stopping")
        print(json.dumps({"decision": "allow", "systemMessage": f"Maximum runtime ({config['max_hours']}h) reached."}))
        return

    # 3. Max iterations (99) → STOP
    if iteration >= config["max_iterations"]:
        logger.info(f"Max iterations ({config['max_iterations']}) reached, stopping")
        print(json.dumps({"decision": "allow", "systemMessage": f"Maximum iterations ({config['max_iterations']}) reached."}))
        return

    # 4. Loop detected (RapidFuzz 90% similarity) → STOP
    if detect_loop(current_output, recent_outputs):
        print(json.dumps({
            "decision": "allow",
            "systemMessage": "Loop detected: agent producing repetitive outputs (>90% similar). Stopping to prevent infinite loop."
        }))
        return

    # 5. TASK_COMPLETE + min time (4h) met + min iterations (50) met → STOP
    task_complete = check_task_complete(state.get("plan_file"))
    min_hours_met = elapsed >= config["min_hours"]
    min_iterations_met = iteration >= config.get("min_iterations", 50)

    if task_complete and min_hours_met and min_iterations_met:
        logger.info("Task complete and all minimums met, stopping")
        print(json.dumps({"decision": "allow", "systemMessage": "Task complete. All minimum requirements met."}))
        return

    # ===== BUILD CONTEXT-RICH CONTINUATION PROMPT =====

    reason = build_continuation_prompt(
        session_id=session_id,
        plan_file=state.get("plan_file"),
        project_dir=project_dir,
        elapsed=elapsed,
        iteration=iteration,
        config=config,
        task_complete=task_complete
    )

    # Update state (maintain sliding window)
    if current_output:
        recent_outputs.append(current_output)
        if len(recent_outputs) > WINDOW_SIZE:
            recent_outputs = recent_outputs[-WINDOW_SIZE:]  # Keep last 5

    state["iteration"] = iteration
    state["recent_outputs"] = recent_outputs

    # Save state
    try:
        state_file.parent.mkdir(parents=True, exist_ok=True)
        state_file.write_text(json.dumps(state, indent=2))
    except OSError as e:
        logger.error(f"Failed to save state: {e}")

    logger.info(f"Continuing loop: iteration={iteration}, task_complete={task_complete}")
    print(json.dumps({"decision": "block", "reason": reason}))


if __name__ == "__main__":
    main()
