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


def check_task_complete(plan_file: str | None) -> tuple[bool, str]:
    """Check for completion via frontmatter status OR checklist markers.

    Returns:
        (is_complete, reason) - reason describes how completion was detected
    """
    if not plan_file or not Path(plan_file).exists():
        return False, "no file to check"
    try:
        content = Path(plan_file).read_text()

        # Method 1: YAML frontmatter status field
        if has_frontmatter_value(content, "implementation-status", "completed"):
            return True, "implementation-status: completed"
        if has_frontmatter_value(content, "implementation-status", "complete"):
            return True, "implementation-status: complete"

        # Method 2: Checklist markers (flexible formats)
        for line in content.split('\n'):
            line_stripped = line.strip()
            # Support multiple checkbox formats
            if any([
                line_stripped in ('- [x] TASK_COMPLETE', '[x] TASK_COMPLETE'),
                line_stripped in ('* [x] TASK_COMPLETE', '[X] TASK_COMPLETE'),
                'TASK_COMPLETE' in line_stripped and ('[x]' in line_stripped.lower()),
            ]):
                return True, "checklist: TASK_COMPLETE"
    except OSError:
        pass
    return False, "not complete"


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


# ===== FILE DISCOVERY FUNCTIONS =====


def has_itp_structure(project_dir: str) -> bool:
    """Check if project follows ITP conventions (has docs/adr and docs/design)."""
    if not project_dir:
        return False
    adr_dir = Path(project_dir) / "docs/adr"
    design_dir = Path(project_dir) / "docs/design"
    return adr_dir.exists() and design_dir.exists()


def has_frontmatter_value(content: str, key: str, value: str) -> bool:
    """Check if markdown has YAML frontmatter with specific key: value (simple string matching)."""
    lines = content.split('\n')
    if not lines or lines[0].strip() != '---':
        return False

    for line in lines[1:]:
        if line.strip() == '---':
            break
        # Match: "key: value" or "key: 'value'" or 'key: "value"'
        if line.startswith(f"{key}:"):
            line_value = line.split(':', 1)[1].strip()
            # Remove quotes
            line_value = line_value.strip('"').strip("'")
            if line_value == value:
                return True
    return False


def discover_from_transcript(transcript_path: str) -> str | None:
    """Extract plan file path from Write/Edit/Read tool operations on .claude/plans/ files."""
    if not transcript_path or not Path(transcript_path).exists():
        return None
    try:
        lines = Path(transcript_path).read_text().strip().split('\n')
        # Search backwards (most recent first)
        for line in reversed(lines):
            if not line.strip():
                continue
            try:
                entry = json.loads(line)
                # Check message.content[] for tool_use blocks
                content = entry.get("message", {}).get("content", [])
                if not isinstance(content, list):
                    continue
                for block in content:
                    if not isinstance(block, dict):
                        continue
                    if block.get("type") != "tool_use":
                        continue
                    # Check for Write, Edit, or Read operations
                    if block.get("name") not in ("Write", "Edit", "Read"):
                        continue
                    file_path = block.get("input", {}).get("file_path", "")
                    # Match .claude/plans/ files
                    if "/.claude/plans/" in file_path and file_path.endswith(".md"):
                        return file_path
            except json.JSONDecodeError:
                continue
    except OSError:
        pass
    return None


def find_in_progress_spec(project_dir: str) -> list[str]:
    """Find ITP design specs with implementation-status: in_progress."""
    specs = []
    if not project_dir:
        return specs
    design_dir = Path(project_dir) / "docs/design"
    if not design_dir.exists():
        return specs

    for spec_path in design_dir.glob("*/spec.md"):
        try:
            content = spec_path.read_text()
            if has_frontmatter_value(content, "implementation-status", "in_progress"):
                specs.append(str(spec_path))
        except OSError:
            continue

    # Return sorted by mtime (newest first)
    if specs:
        specs.sort(key=lambda p: Path(p).stat().st_mtime, reverse=True)
    return specs


def find_accepted_adr(project_dir: str) -> list[str]:
    """Find ITP ADRs with status: accepted (not yet implemented)."""
    adrs = []
    if not project_dir:
        return adrs
    adr_dir = Path(project_dir) / "docs/adr"
    if not adr_dir.exists():
        return adrs

    for adr_path in adr_dir.glob("*.md"):
        try:
            content = adr_path.read_text()
            # Check for status: accepted but not status: implemented
            if has_frontmatter_value(content, "status", "accepted"):
                # Also check it's not implemented
                if not has_frontmatter_value(content, "status", "implemented"):
                    adrs.append(str(adr_path))
        except OSError:
            continue

    if adrs:
        adrs.sort(key=lambda p: Path(p).stat().st_mtime, reverse=True)
    return adrs


def find_newest_plan(plans_dir: Path) -> Path | None:
    """Find newest .md file in plans directory by modification time."""
    if not plans_dir.exists():
        return None
    candidates = []
    for md_file in plans_dir.glob("*.md"):
        # Skip agent conversation snapshots
        if "-agent-" in md_file.name:
            continue
        candidates.append(md_file)

    if candidates:
        return max(candidates, key=lambda p: p.stat().st_mtime)
    return None


def find_matching_global_plan(plans_dir: Path, project_dir: str) -> list[str]:
    """Find global plans that reference the current project."""
    if not plans_dir.exists() or not project_dir:
        return []
    project_name = Path(project_dir).name
    matches = []

    for md_file in plans_dir.glob("*.md"):
        if "-agent-" in md_file.name:
            continue
        try:
            content = md_file.read_text()
            # Check if plan mentions this project
            if project_name in content or project_dir in content:
                matches.append(str(md_file))
        except OSError:
            continue

    if matches:
        matches.sort(key=lambda p: Path(p).stat().st_mtime, reverse=True)
    return matches


def format_candidate_list(candidates: list[str], file_type: str) -> str:
    """Format candidates for inclusion in continuation prompt."""
    lines = [f"\n**MULTIPLE {file_type.upper()} FILES** - Please examine and choose:"]
    for i, path in enumerate(candidates[:5], 1):
        lines.append(f"  {i}. {path}")
    return "\n".join(lines)


def discover_target_file(
    transcript_path: str | None,
    project_dir: str
) -> tuple[str | None, str, list[str]]:
    """
    Discover task file with priority cascade.

    Returns:
        (path, discovery_method, candidates) - path is None if multiple candidates
    """
    # Priority 1: Transcript parsing (Write/Edit/Read to .claude/plans/)
    if transcript_path:
        path = discover_from_transcript(transcript_path)
        if path:
            logger.info(f"Discovered from transcript: {path}")
            return (path, "transcript", [])

    # Priority 2-3: ITP (only if structure exists)
    if project_dir and has_itp_structure(project_dir):
        # Priority 2: Design specs with implementation-status: in_progress
        specs = find_in_progress_spec(project_dir)
        if len(specs) == 1:
            logger.info(f"Discovered ITP spec: {specs[0]}")
            return (specs[0], "itp_spec", [])
        elif len(specs) > 1:
            logger.info(f"Multiple ITP specs found: {specs}")
            return (None, "itp_spec", specs)

        # Priority 3: ADRs with status: accepted
        adrs = find_accepted_adr(project_dir)
        if len(adrs) == 1:
            logger.info(f"Discovered ITP ADR: {adrs[0]}")
            return (adrs[0], "itp_adr", [])
        elif len(adrs) > 1:
            logger.info(f"Multiple ITP ADRs found: {adrs}")
            return (None, "itp_adr", adrs)

    # Priority 4: Local .claude/plans/
    if project_dir:
        local_plans = Path(project_dir) / ".claude/plans"
        local_newest = find_newest_plan(local_plans)
        if local_newest:
            logger.info(f"Discovered local plan: {local_newest}")
            return (str(local_newest), "local_plan", [])

    # Priority 5: Global plans (content match)
    global_plans = Path.home() / ".claude/plans"
    if project_dir:
        global_matches = find_matching_global_plan(global_plans, project_dir)
        if len(global_matches) == 1:
            logger.info(f"Discovered global plan (content match): {global_matches[0]}")
            return (global_matches[0], "global_plan", [])
        elif len(global_matches) > 1:
            logger.info(f"Multiple global plans found: {global_matches}")
            return (None, "global_plan", global_matches[:5])

    # Priority 6: Global plans (most recent fallback)
    global_newest = find_newest_plan(global_plans)
    if global_newest:
        logger.info(f"Discovered global plan (newest): {global_newest}")
        return (str(global_newest), "global_plan_mtime", [])

    logger.info("No target file discovered")
    return (None, "none", [])


def build_continuation_prompt(
    session_id: str,
    plan_file: str | None,
    project_dir: str,
    elapsed: float,
    iteration: int,
    config: dict,
    task_complete: bool,
    discovery_method: str = "",
    candidate_files: list[str] | None = None
) -> str:
    """Build context-rich continuation prompt."""
    parts = []
    remaining_hours = max(0, config["min_hours"] - elapsed)
    remaining_iters = max(0, config.get("min_iterations", 50) - iteration)
    mode = "EXPLORATION" if task_complete else "IMPLEMENTATION"
    parts.append(f"**{mode} MODE** | Iteration {iteration}/{config['max_iterations']} | {elapsed:.1f}h elapsed | {remaining_hours:.1f}h / {remaining_iters} iters remaining")

    # Add task_prompt from config if present (user's original intent)
    task_prompt = config.get("task_prompt", "")
    if task_prompt:
        parts.append(f"\n**TASK**: {task_prompt}")

    # Add discovery method and focus file
    if plan_file and discovery_method:
        parts.append(f"\n**Focus file** (via {discovery_method}): {plan_file}")
    elif plan_file:
        parts.append(f"\n**Focus file**: {plan_file}")

    # Add candidate files if multiple were found (nudge for user choice)
    if candidate_files and len(candidate_files) > 1:
        parts.append(format_candidate_list(candidate_files, discovery_method.replace("_", " ")))

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
                parts.append("\n**AVOID (already tried, failed)**:\n" + "\n".join(dead_ends[:5]))
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
                    parts.append("\n**RECENT ACTIONS** (continue from here):\n" + "\n".join(recent))
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
            "plan_file": None,
            "discovered_file": None,
            "discovery_method": "",
            "candidate_files": []
        }
    except (json.JSONDecodeError, OSError):
        state = {
            "iteration": 0,
            "recent_outputs": [],
            "plan_file": None,
            "discovered_file": None,
            "discovery_method": "",
            "candidate_files": []
        }

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

    # Also check project-level config (primary source for target_file and task_prompt)
    project_config_path = Path(project_dir) / ".claude/loop-config.json" if project_dir else None
    if project_config_path and project_config_path.exists():
        try:
            proj_cfg = json.loads(project_config_path.read_text())
            config.update(proj_cfg)
            logger.info(f"Loaded project config: {proj_cfg}")
        except (json.JSONDecodeError, OSError):
            pass

    # ===== FILE DISCOVERY =====
    # Priority 0: User-provided target_file from -f flag (in config)
    # If not set, run discovery cascade and persist result

    discovery_method = state.get("discovery_method", "")
    candidate_files: list[str] = state.get("candidate_files", [])

    if config.get("target_file"):
        # User explicitly provided file via -f flag
        plan_file = config["target_file"]
        discovery_method = "explicit (-f flag)"
        candidate_files = []
        logger.info(f"Using explicit target file: {plan_file}")
    elif config.get("discovered_file"):
        # Reuse previously discovered file from config (persisted across sessions)
        plan_file = config["discovered_file"]
        discovery_method = config.get("discovery_method", "previous session")
        logger.info(f"Reusing discovered file from config: {plan_file}")
    elif state.get("discovered_file"):
        # Reuse from state (current session)
        plan_file = state["discovered_file"]
        discovery_method = state.get("discovery_method", "previous iteration")
        logger.info(f"Reusing discovered file from state: {plan_file}")
    else:
        # Run discovery cascade
        plan_file, discovery_method, candidate_files = discover_target_file(
            transcript_path, project_dir
        )

        # Persist discovery to BOTH config (across sessions) and state (current session)
        if plan_file and project_config_path:
            try:
                # Read existing config, add discovered_file
                existing_config = {}
                if project_config_path.exists():
                    existing_config = json.loads(project_config_path.read_text())
                existing_config["discovered_file"] = plan_file
                existing_config["discovery_method"] = discovery_method
                project_config_path.write_text(json.dumps(existing_config, indent=2))
                logger.info(f"Persisted discovery to config: {plan_file}")
            except OSError as e:
                logger.error(f"Failed to persist discovery to config: {e}")

    # Update state with discovery results
    state["discovered_file"] = plan_file
    state["discovery_method"] = discovery_method
    state["candidate_files"] = candidate_files
    # Keep plan_file for backwards compatibility
    state["plan_file"] = plan_file

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
    task_complete, completion_reason = check_task_complete(plan_file)
    min_hours_met = elapsed >= config["min_hours"]
    min_iterations_met = iteration >= config.get("min_iterations", 50)

    if task_complete and min_hours_met and min_iterations_met:
        allow_stop(f"Task complete ({completion_reason}) and all minimum requirements met")
        return

    # ===== CONTINUE SESSION =====
    reason = build_continuation_prompt(
        session_id=session_id,
        plan_file=plan_file,
        project_dir=project_dir,
        elapsed=elapsed,
        iteration=iteration,
        config=config,
        task_complete=task_complete,
        discovery_method=discovery_method,
        candidate_files=candidate_files
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
