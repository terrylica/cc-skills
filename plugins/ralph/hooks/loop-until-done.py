#!/usr/bin/env python3
# /// script
# requires-python = ">=3.11"
# dependencies = ["rapidfuzz>=3.0.0,<4.0.0", "jinja2>=3.1.0,<4.0.0"]
# ///
# ADR: Multi-Repository Adapter Architecture
# ADR: 2025-12-20-ralph-rssi-eternal-loop
# Adds project-specific convergence detection via adapter registry
# Enhanced with RSSI eternal loop (Levels 2-6)
"""
Autonomous improvement engine Stop hook - RSSI Enhanced.

Implements the Ralph Wiggum technique with RSSI (Recursively Self-Improving
Super Intelligence) capabilities:
- Multi-signal completion detection
- 3-round validation phase
- Discovery/exploration mode
- Sub-agent spawning instructions

Schema per Claude Code docs:
- To ALLOW stop: return {} (empty object)
- To CONTINUE (prevent stop): return {"decision": "block", "reason": "..."}
- To HARD STOP: return {"continue": false} - overrides everything
"""
import json
import logging
import os
import subprocess
import sys
from dataclasses import asdict
from pathlib import Path

# Import from modular components
from completion import check_task_complete_rssi
from core.config_schema import LoopState, load_state, save_state
from core.path_hash import build_state_file_path, load_session_state
from core.registry import AdapterRegistry
from discovery import (
    discover_target_file,
    format_candidate_list,
    get_rssi_exploration_context,
)
from template_loader import get_loader
from utils import (
    WINDOW_SIZE,
    allow_stop,
    continue_session,
    detect_loop,
    extract_section,
    get_elapsed_hours,
    hard_stop,
)
from validation import (
    VALIDATION_SCORE_THRESHOLD,
    check_validation_exhausted,
    compute_validation_score,
)


def render_slo_experts(
    adapter,
    project_dir: str,
    state: dict,
    config: dict,
    iteration: int,
) -> str:
    """Render SLO experts template for Alpha Forge projects.

    Uses the adapter's get_slo_context() method to build context
    for the alpha-forge-slo-experts.md template.

    Args:
        adapter: The active adapter (must have get_slo_context method)
        project_dir: Path to project directory
        state: Current loop state
        config: Loop configuration
        iteration: Current RSSI iteration

    Returns:
        Rendered SLO experts prompt, or empty string if not applicable
    """
    if not adapter or adapter.name != "alpha-forge":
        return ""

    if not hasattr(adapter, "get_slo_context"):
        return ""

    try:
        # Get SLO context from adapter
        slo_context = adapter.get_slo_context(
            project_dir=Path(project_dir),
            work_item=None,  # TODO: Pass current work item
            iteration=iteration,
        )

        # Render the SLO experts template
        loader = get_loader()
        return loader.render(
            "alpha-forge-slo-experts.md",
            **slo_context,
        )
    except (FileNotFoundError, Exception) as e:
        logger.warning(f"Failed to render SLO experts: {e}")
        return ""

# Configure logging
logging.basicConfig(
    level=logging.DEBUG,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[logging.FileHandler(Path.home() / '.claude/automation/loop-orchestrator/state/loop-hook.log')]
)
logger = logging.getLogger(__name__)

STATE_DIR = Path.home() / ".claude/automation/loop-orchestrator/state"
CONFIG_FILE = STATE_DIR.parent / "config/loop_config.json"


def build_validation_round_prompt(round_num: int, state: dict, config: dict) -> str:
    """Generate validation round instructions for Claude.

    Uses external markdown templates from templates/ directory.
    """
    loader = get_loader()
    return loader.render_validation_round(round_num, state, config)


def build_continuation_prompt(
    session_id: str,
    plan_file: str | None,
    project_dir: str,
    elapsed: float,
    iteration: int,
    config: dict,
    task_complete: bool,
    discovery_method: str = "",
    candidate_files: list[str] | None = None,
    state: dict | None = None,
    no_focus: bool = False,
) -> str:
    """Build context-rich continuation prompt with RSSI modes.

    Mode progression:
    1. IMPLEMENTATION - Working on checklist items (task_complete=False)
    2. VALIDATION - Multi-round validation after task complete
    3. EXPLORATION - Discovery and self-improvement (always in no_focus mode)
    """
    if state is None:
        state = {}

    parts = []
    remaining_hours = max(0, config["min_hours"] - elapsed)
    remaining_iters = max(0, config.get("min_iterations", 50) - iteration)

    # Determine current mode based on RSSI state
    validation_exhausted = state.get("validation_exhausted", False)
    validation_round = state.get("validation_round", 0)
    enable_validation = config.get("enable_validation_phase", True)

    # In no_focus mode, ALWAYS use exploration (RSSI eternal loop)
    if no_focus:
        mode = "EXPLORATION"
    elif not task_complete:
        mode = "IMPLEMENTATION"
    elif enable_validation and not validation_exhausted:
        mode = f"VALIDATION (Round {validation_round}/3)"
    else:
        mode = "EXPLORATION"

    parts.append(
        f"**{mode}** | Iteration {iteration}/{config['max_iterations']} | "
        f"{elapsed:.1f}h elapsed | {remaining_hours:.1f}h / {remaining_iters} iters remaining"
    )

    # Add task_prompt from config if present
    task_prompt = config.get("task_prompt", "")
    if task_prompt:
        parts.append(f"\n**TASK**: {task_prompt}")

    # Add discovery method and focus file
    if plan_file and discovery_method:
        parts.append(f"\n**Focus file** (via {discovery_method}): {plan_file}")
    elif plan_file:
        parts.append(f"\n**Focus file**: {plan_file}")

    # Add candidate files if multiple were found
    if candidate_files and len(candidate_files) > 1:
        parts.append(format_candidate_list(candidate_files, discovery_method.replace("_", " ")))

    # Extract context from plan file
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

    # Add exploration log context
    if project_dir:
        exploration_log = Path(project_dir) / ".claude/exploration_log.jsonl"
        if exploration_log.exists():
            try:
                lines = exploration_log.read_text().strip().split('\n')[-3:]
                recent = []
                for line in lines:
                    if line.strip():
                        entry = json.loads(line)
                        recent.append(
                            f"- [{entry.get('action', 'unknown')}] "
                            f"{entry.get('target', '')} → {entry.get('outcome', '')}"
                        )
                if recent:
                    parts.append("\n**RECENT ACTIONS** (continue from here):\n" + "\n".join(recent))
            except (json.JSONDecodeError, KeyError, OSError):
                pass

    # Add git context
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

    # Adapter-specific status (only shown if adapter has opinion)
    loader = get_loader()
    adapter_name = state.get("adapter_name", "")
    adapter_convergence = state.get("adapter_convergence")
    if adapter_name and adapter_convergence:
        adapter_status = loader.render_adapter_status(
            adapter_name=adapter_name,
            adapter_convergence=adapter_convergence,
            metrics_history=adapter_convergence.get("metrics_history")
        )
        if adapter_status:
            parts.append(adapter_status)

    # Mode-specific prompts (loaded from templates/)
    # In no_focus mode, ALWAYS use exploration (RSSI eternal loop)

    if no_focus:
        # RSSI Eternal Loop: Get full exploration context with all levels
        rssi_context = get_rssi_exploration_context(project_dir) if project_dir else {}
        opportunities = rssi_context.get("opportunities", [])
        state["opportunities_discovered"] = opportunities
        state["rssi_iteration"] = rssi_context.get("iteration", 0)

        # Render exploration template with full RSSI context
        parts.append(loader.render_exploration(
            opportunities=opportunities,
            rssi_context=rssi_context,
        ))

        # SLO experts for Alpha Forge in no_focus mode
        adapter_name = state.get("adapter_name", "")
        if adapter_name == "alpha-forge" and project_dir:
            slo_prompt = render_slo_experts(
                adapter=AdapterRegistry.get_adapter(Path(project_dir)),
                project_dir=project_dir,
                state=state,
                config=config,
                iteration=iteration,
            )
            if slo_prompt:
                parts.append(slo_prompt)

    elif not task_complete:
        parts.append(loader.render("implementation-mode.md"))

    elif enable_validation and not validation_exhausted:
        validation_round = state.get("validation_round", 0)
        if validation_round == 0:
            state["validation_round"] = 1
            validation_round = 1

        parts.append(build_validation_round_prompt(validation_round, state, config))

        validation_score = state.get("validation_score", 0.0)
        if validation_score > 0:
            parts.append(
                f"\n**Current validation score**: {validation_score:.2f} "
                f"(need >= {VALIDATION_SCORE_THRESHOLD})"
            )

    else:
        # RSSI Eternal Loop: Get full exploration context with all levels
        rssi_context = get_rssi_exploration_context(project_dir) if project_dir else {}
        opportunities = rssi_context.get("opportunities", [])
        state["opportunities_discovered"] = opportunities
        state["rssi_iteration"] = rssi_context.get("iteration", 0)

        # Render exploration template with full RSSI context
        parts.append(loader.render_exploration(
            opportunities=opportunities,
            rssi_context=rssi_context,
        ))

        # SLO experts for Alpha Forge (enhanced version of research experts)
        # Uses 6 experts with adaptive model selection
        if adapter_name == "alpha-forge":
            slo_prompt = render_slo_experts(
                adapter=AdapterRegistry.get_adapter(Path(project_dir)) if project_dir else None,
                project_dir=project_dir,
                state=state,
                config=config,
                iteration=iteration,
            )
            if slo_prompt:
                parts.append(slo_prompt)
        # Research experts for other adapter-specific strategy optimization
        elif adapter_name and adapter_convergence:
            expert_prompt = loader.render_research_experts(
                adapter_name=adapter_name,
                state=state,
                config=config,
                metrics_history=adapter_convergence.get("metrics_history"),
            )
            if expert_prompt:
                parts.append(expert_prompt)

    return "\n".join(parts)


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

    # Check state machine first (new v2.0 architecture)
    if project_dir:
        current_state = load_state(project_dir)
        if current_state == LoopState.STOPPED:
            allow_stop("Loop state is STOPPED")
            return
        if current_state == LoopState.DRAINING:
            # Complete the transition: DRAINING → STOPPED
            save_state(project_dir, LoopState.STOPPED)
            # Clean up kill switch if present
            kill_switch = Path(project_dir) / ".claude/STOP_LOOP"
            kill_switch.unlink(missing_ok=True)
            hard_stop("Loop stopped via state transition (DRAINING → STOPPED)")
            return

    # Legacy check: loop-enabled file (backward compatibility)
    loop_enabled_file = Path(project_dir) / ".claude/loop-enabled" if project_dir else None
    if not loop_enabled_file or not loop_enabled_file.exists():
        allow_stop("Loop not enabled for this repo")
        return

    # Legacy check: kill switch file
    kill_switch = Path(project_dir) / ".claude/STOP_LOOP"
    if kill_switch.exists():
        kill_switch.unlink()
        loop_enabled_file.unlink(missing_ok=True)
        # Also update state machine
        if project_dir:
            save_state(project_dir, LoopState.STOPPED)
        hard_stop("Loop stopped via kill switch (.claude/STOP_LOOP)")
        return

    # ===== LOAD STATE =====
    # Use path hash for session state isolation (git worktree support)
    state_file = build_state_file_path(STATE_DIR, session_id, project_dir)
    default_state = {
        "iteration": 0,
        "started_at": "",  # ISO timestamp for adapter metrics filtering
        "recent_outputs": [],
        "plan_file": None,
        "discovered_file": None,
        "discovery_method": "",
        "candidate_files": [],
        "completion_signals": [],
        "last_completion_confidence": 0.0,
        "opportunities_discovered": [],
        "validation_round": 0,
        "validation_iteration": 0,
        "validation_findings": {
            "round1": {"critical": [], "medium": [], "low": []},
            "round2": {"verified": [], "failed": []},
            "round3": {"doc_issues": [], "coverage_gaps": []}
        },
        "validation_score": 0.0,
        "validation_exhausted": False,
        "previous_finding_count": 0,
        "agent_results": [],
        "adapter_name": "",  # Active adapter for this session
        "adapter_convergence": None,  # Last adapter convergence result
    }
    state = load_session_state(state_file, default_state)

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

    # Project-level config
    project_config_path = Path(project_dir) / ".claude/loop-config.json" if project_dir else None
    if project_config_path and project_config_path.exists():
        try:
            proj_cfg = json.loads(project_config_path.read_text())
            config.update(proj_cfg)
            logger.info(f"Loaded project config: {proj_cfg}")
        except (json.JSONDecodeError, OSError):
            pass

    # ===== ADAPTER DISCOVERY =====
    # Auto-discover and select project-specific adapter
    adapters_dir = Path(__file__).parent / "adapters"
    AdapterRegistry.discover(adapters_dir)
    adapter = AdapterRegistry.get_adapter(Path(project_dir)) if project_dir else None

    if adapter:
        state["adapter_name"] = adapter.name
        logger.info(f"Using adapter: {adapter.name}")

    # Set started_at on first iteration (for adapter metrics filtering)
    if not state.get("started_at"):
        from datetime import datetime, timezone
        state["started_at"] = datetime.now(timezone.utc).isoformat()
        logger.info(f"Session started at: {state['started_at']}")

    # ===== FILE DISCOVERY =====
    discovery_method = state.get("discovery_method", "")
    candidate_files: list[str] = state.get("candidate_files", [])

    # Check for no_focus mode (100% autonomous, no plan tracking)
    no_focus = config.get("no_focus", False)
    if no_focus:
        plan_file = None
        discovery_method = "no_focus"
        candidate_files = []
        logger.info("No-focus mode: skipping file discovery")
    elif config.get("target_file"):
        plan_file = config["target_file"]
        discovery_method = "explicit (-f flag)"
        candidate_files = []
        logger.info(f"Using explicit target file: {plan_file}")
    elif config.get("discovered_file"):
        plan_file = config["discovered_file"]
        discovery_method = config.get("discovery_method", "previous session")
        logger.info(f"Reusing discovered file from config: {plan_file}")
    elif state.get("discovered_file"):
        plan_file = state["discovered_file"]
        discovery_method = state.get("discovery_method", "previous iteration")
        logger.info(f"Reusing discovered file from state: {plan_file}")
    else:
        plan_file, discovery_method, candidate_files = discover_target_file(
            transcript_path, project_dir
        )
        if plan_file and project_config_path:
            try:
                existing_config = {}
                if project_config_path.exists():
                    existing_config = json.loads(project_config_path.read_text())
                existing_config["discovered_file"] = plan_file
                existing_config["discovery_method"] = discovery_method
                project_config_path.write_text(json.dumps(existing_config, indent=2))
                logger.info(f"Persisted discovery to config: {plan_file}")
            except OSError as e:
                logger.error(f"Failed to persist discovery to config: {e}")

    state["discovered_file"] = plan_file
    state["discovery_method"] = discovery_method
    state["candidate_files"] = candidate_files
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

    if elapsed >= config["max_hours"]:
        allow_stop(f"Maximum runtime ({config['max_hours']}h) reached")
        return

    if iteration >= config["max_iterations"]:
        allow_stop(f"Maximum iterations ({config['max_iterations']}) reached")
        return

    if detect_loop(current_output, recent_outputs):
        allow_stop("Loop detected: agent producing repetitive outputs (>90% similar)")
        return

    task_complete, completion_reason, completion_confidence = check_task_complete_rssi(plan_file)
    state["last_completion_confidence"] = completion_confidence
    if task_complete:
        state["completion_signals"].append(completion_reason)

    # ===== ADAPTER CONVERGENCE CHECK =====
    # Project-specific convergence detection (requires RSSI agreement at confidence=0.5)
    adapter_should_stop = False
    adapter_reason = ""
    adapter_confidence = 0.0

    if adapter and project_dir:
        try:
            metrics = adapter.get_metrics_history(
                Path(project_dir), state.get("started_at", "")
            )
            convergence = adapter.check_convergence(metrics, Path(project_dir))
            state["adapter_convergence"] = {
                "should_continue": convergence.should_continue,
                "reason": convergence.reason,
                "confidence": convergence.confidence,
                "metrics_count": len(metrics),
                "metrics_history": [asdict(m) for m in metrics[-10:]],  # Store last 10
            }
            logger.info(
                f"Adapter convergence: continue={convergence.should_continue}, "
                f"confidence={convergence.confidence:.2f}, reason={convergence.reason}"
            )

            # High confidence (1.0) = adapter overrides RSSI
            # Medium confidence (0.5) = requires RSSI agreement
            # Low confidence (0.0) = defer to RSSI
            if convergence.confidence >= 1.0:
                if not convergence.should_continue:
                    allow_stop(f"Adapter override: {convergence.reason}")
                    return
                # If should_continue with high confidence, force continue below
            elif convergence.confidence >= 0.5:
                adapter_should_stop = not convergence.should_continue
                adapter_reason = convergence.reason
                adapter_confidence = convergence.confidence
        except Exception as e:
            logger.warning(f"Adapter convergence check failed: {e}")

    min_hours_met = elapsed >= config["min_hours"]
    min_iterations_met = iteration >= config.get("min_iterations", 50)

    enable_validation = config.get("enable_validation_phase", True)
    if task_complete and enable_validation:
        state["validation_score"] = compute_validation_score(state)
        if check_validation_exhausted(state):
            state["validation_exhausted"] = True

    validation_exhausted = state.get("validation_exhausted", False)

    # Combined decision: RSSI + Adapter must agree at confidence=0.5
    if task_complete and min_hours_met and min_iterations_met:
        if not enable_validation or validation_exhausted:
            # Check if adapter also suggests stopping
            if adapter_should_stop and adapter_confidence >= 0.5:
                allow_stop(
                    f"Converged: RSSI ({completion_reason}) + Adapter ({adapter_reason})"
                )
                return
            # RSSI says complete but adapter doesn't agree - continue
            if adapter and adapter_confidence >= 0.5 and not adapter_should_stop:
                logger.info("RSSI complete but adapter wants to continue - continuing")
            else:
                allow_stop(
                    f"Task complete ({completion_reason}, confidence={completion_confidence:.2f}) "
                    "and all requirements met"
                )
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
        candidate_files=candidate_files,
        state=state,
        no_focus=no_focus,
    )

    if current_output:
        recent_outputs.append(current_output)
        if len(recent_outputs) > WINDOW_SIZE:
            recent_outputs = recent_outputs[-WINDOW_SIZE:]

    state["iteration"] = iteration
    state["recent_outputs"] = recent_outputs

    try:
        state_file.parent.mkdir(parents=True, exist_ok=True)
        state_file.write_text(json.dumps(state, indent=2))
    except OSError as e:
        logger.error(f"Failed to save state: {e}")

    continue_session(reason)


if __name__ == "__main__":
    main()
