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
import sys
from dataclasses import asdict
from pathlib import Path

# Import from modular components
from completion import check_task_complete_rssi
from core.config_schema import LoopState, load_config, load_state, save_state
from core.path_hash import build_state_file_path, load_session_state
from core.project_detection import is_alpha_forge_project
from core.registry import AdapterRegistry
from discovery import (
    discover_target_file,
)
from todo_sync import format_todo_instruction, generate_todo_items
from template_loader import get_loader
from utils import (
    WINDOW_SIZE,
    allow_stop,
    continue_session,
    detect_loop,
    get_runtime_hours,
    get_wall_clock_hours,
    hard_stop,
    update_runtime,
)
from rssi_evolution import (
    get_learned_patterns,
    get_disabled_checks,
    get_prioritized_checks,
    suggest_capability_expansion,
)


def _detect_alpha_forge_simple(project_dir: str) -> str:
    """Detect alpha-forge project using consolidated detection.

    Returns "alpha-forge" if detected, empty string otherwise.
    """
    if is_alpha_forge_project(project_dir):
        return "alpha-forge"
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


def _build_web_queries(state: dict, adapter_conv: dict | None) -> list[str]:
    """Build dynamic WebSearch queries based on current bottlenecks.

    Analyzes metrics history to suggest relevant search queries.

    Args:
        state: Session state dict
        adapter_conv: Adapter convergence dict (may be None)

    Returns:
        List of up to 3 search queries
    """
    queries: list[str] = []

    if not adapter_conv:
        return ["project improvement SOTA 2024"]

    metrics = adapter_conv.get("metrics_history", [])
    if metrics:
        latest = metrics[-1] if isinstance(metrics[-1], dict) else {}
        # Check for overfitting (WFE < 0.5)
        wfe = latest.get("wfe", 1.0) if isinstance(latest, dict) else getattr(latest, "wfe", 1.0)
        if wfe < 0.5:
            queries.append("overfitting prevention walk-forward validation ML")

        # Check for plateau (< 5% improvement)
        if len(metrics) >= 2:
            prev = metrics[-2]
            prev_sharpe = prev.get("primary_metric", 0) if isinstance(prev, dict) else 0
            curr_sharpe = latest.get("primary_metric", 0) if isinstance(latest, dict) else 0
            if prev_sharpe > 0 and curr_sharpe > 0:
                delta = (curr_sharpe - prev_sharpe) / prev_sharpe
                if delta < 0.05:
                    queries.append("transformer time series forecasting improvement 2024")

    if not queries:
        queries.append("ML trading strategy SOTA 2024")

    return queries[:3]


def build_continuation_prompt(
    session_id: str,
    plan_file: str | None,
    project_dir: str,
    runtime_hours: float,
    wall_hours: float,
    iteration: int,
    config: dict,
    task_complete: bool,
    discovery_method: str = "",
    candidate_files: list[str] | None = None,
    state: dict | None = None,
    no_focus: bool = False,
) -> str:
    """Build continuation prompt - minimal for no_focus, detailed for focused mode.

    Args:
        runtime_hours: CLI active time (used for limit enforcement)
        wall_hours: Calendar time since start (informational)
    """
    if state is None:
        state = {}

    # Detect adapter early
    adapter_name = state.get("adapter_name", "")
    if not adapter_name and project_dir:
        adapter_name = _detect_alpha_forge_simple(project_dir)

    # ===== NO_FOCUS MODE or FORCE_EXPLORATION: Minimal but actionable =====
    force_exploration = state.get("force_exploration", False)
    if no_focus or force_exploration:
        # Calculate remaining for header (show limits for visibility)
        time_to_max = max(0, config["max_hours"] - runtime_hours)
        iters_to_max = max(0, config["max_iterations"] - iteration)

        # Warning suffix if approaching limits
        warning = ""
        if time_to_max < 1.0 or iters_to_max < 5:
            warning = " | **ENDING SOON**"

        if adapter_name == "alpha-forge":
            # Use full template with CONVERGED detection for proper busywork blocking
            loader = get_loader()

            # Load user guidance from ralph-config.json (natural language lists)
            guidance = {}
            if project_dir:
                ralph_config_file = Path(project_dir) / ".claude/ralph-config.json"
                if ralph_config_file.exists():
                    try:
                        ralph_config = json.loads(ralph_config_file.read_text())
                        guidance = ralph_config.get("guidance", {})
                    except (json.JSONDecodeError, OSError):
                        pass  # Graceful fallback to empty guidance

            # Build complete RSSI context with all template variables
            adapter_conv = state.get("adapter_convergence", {})
            rssi_context = {
                # Core iteration tracking
                "iteration": iteration,
                "adapter_convergence": adapter_conv,
                "guidance": guidance,  # User-provided forbidden/encouraged lists
                # RSSI evolution state (Level 4: Self-Modification)
                "accumulated_patterns": list(get_learned_patterns().keys()),
                "disabled_checks": get_disabled_checks(),
                "effective_checks": get_prioritized_checks(),
                # Validation state (5-round system)
                "validation_round": state.get("validation_round", 0),
                "validation_findings": state.get("validation_findings", {}),
                # Feature discovery
                "feature_ideas": state.get("feature_ideas", []),
                "web_insights": state.get("web_insights", []),
                # Capability expansion
                "missing_tools": suggest_capability_expansion(Path(project_dir)) if project_dir else [],
                # Quality gate
                "quality_gate": [
                    "- Verify implementation matches SOTA paper/source",
                    "- Run backtest on validation period",
                    "- Check for data leakage",
                    "- Ensure WFE > 0.5 before committing",
                ],
                # Web research
                "web_queries": _build_web_queries(state, adapter_conv),
                # Research convergence
                "research_converged": adapter_conv.get("converged", False) if adapter_conv else False,
                # GPU infrastructure for remote training (littleblack server)
                "gpu_infrastructure": {
                    "available": True,
                    "host": "littleblack",
                    "gpu": "RTX 2080 Ti (11GB)",
                    "ssh_cmd": "ssh kab@littleblack",
                },
            }
            metrics_history = adapter_conv.get("metrics_history", []) if adapter_conv else []
            prefix = "**RSSI→EXPLORE**" if force_exploration else "**RSSI**"
            prompt = loader.render_exploration(
                opportunities=[],
                rssi_context=rssi_context,
                adapter_name=adapter_name,
                metrics_history=metrics_history,
            )
            header = (
                f"{prefix} iter {iteration}/{config['max_iterations']} | "
                f"Runtime: {runtime_hours:.1f}h/{config['max_hours']}h | "
                f"Wall: {wall_hours:.1f}h{warning}"
            )
            # Add todo sync for no_focus mode
            todo_suffix = ""
            if state:
                todo_items = generate_todo_items(state)
                todo_instruction = format_todo_instruction(todo_items)
                if todo_instruction:
                    todo_suffix = f"\n\n{todo_instruction}"
            return f"{header}\n\n{prompt}{todo_suffix}"
        else:
            # Generic exploration mode for all non-Alpha-Forge projects
            # Uses exploration template with RSSI protocol for any project type
            loader = get_loader()
            rssi_context = {
                "iteration": iteration,
                "accumulated_patterns": list(get_learned_patterns().keys()),
                "disabled_checks": get_disabled_checks(),
                "effective_checks": get_prioritized_checks(),
                "web_insights": state.get("web_insights", []) if state else [],
                "feature_ideas": state.get("feature_ideas", []) if state else [],
                "web_queries": ["project improvement SOTA 2024"],
                "missing_tools": suggest_capability_expansion(Path(project_dir)) if project_dir else [],
                "quality_gate": [],
            }

            prompt = loader.render_exploration(
                opportunities=[],
                rssi_context=rssi_context,
                adapter_name=None,
                metrics_history=[],
            )

            header = (
                f"**RSSI** iter {iteration}/{config['max_iterations']} | "
                f"Runtime: {runtime_hours:.1f}h/{config['max_hours']}h | "
                f"Wall: {wall_hours:.1f}h{warning}"
            )

            todo_suffix = ""
            if state:
                todo_items = generate_todo_items(state)
                todo_instruction = format_todo_instruction(todo_items)
                if todo_instruction:
                    todo_suffix = f"\n\n{todo_instruction}"

            return f"{header}\n\n{prompt}{todo_suffix}"

    # ===== FOCUSED MODE: Full context for implementation/exploration =====
    parts = []
    remaining_hours = max(0, config["min_hours"] - runtime_hours)
    remaining_iters = max(0, config.get("min_iterations", 50) - iteration)
    time_to_max = max(0, config["max_hours"] - runtime_hours)
    iters_to_max = config["max_iterations"] - iteration

    mode = "IMPLEMENTATION" if not task_complete else "EXPLORATION"

    # Warning suffix when approaching limits
    warning_suffix = ""
    if time_to_max < 1.0 or iters_to_max < 5:
        warning_suffix = (
            f"\n**WARNING**: Approaching limits "
            f"({time_to_max:.1f}h / {iters_to_max} iters to max)"
        )

    parts.append(
        f"**{mode}** | Iteration {iteration}/{config['max_iterations']} | "
        f"Runtime: {runtime_hours:.1f}h/{config['max_hours']}h | Wall: {wall_hours:.1f}h | "
        f"{remaining_hours:.1f}h / {remaining_iters} iters to min"
        f"{warning_suffix}"
    )

    # Focus file context (only in focused mode)
    if plan_file and discovery_method:
        parts.append(f"\n**Focus file** (via {discovery_method}): {plan_file}")
    elif plan_file:
        parts.append(f"\n**Focus file**: {plan_file}")

    # Mode-specific prompts
    loader = get_loader()

    if not task_complete:
        parts.append(loader.render("implementation-mode.md"))
    else:
        # Exploration mode - Alpha Forge exclusive
        parts.append("\n**ACTION**: WebSearch SOTA → implement → /research → validate → repeat")

    # Todo sync instruction (mirrors state to Claude's visible todo list)
    if state:
        todo_items = generate_todo_items(state)
        todo_instruction = format_todo_instruction(todo_items)
        if todo_instruction:
            parts.append(f"\n{todo_instruction}")

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
        logger.info(f"State check: project={project_dir}, state={current_state.value}")
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

    # Emergency kill switch file (user can create .claude/STOP_LOOP to force stop)
    kill_switch = Path(project_dir) / ".claude/STOP_LOOP" if project_dir else None
    if kill_switch and kill_switch.exists():
        kill_switch.unlink()
        if project_dir:
            save_state(project_dir, LoopState.STOPPED)
        hard_stop("Loop stopped via kill switch (.claude/STOP_LOOP)")
        return

    # ===== LOAD STATE =====
    # Use path hash for session state isolation (git worktree support)
    state_file = build_state_file_path(STATE_DIR, session_id, project_dir)
    default_state = {
        "iteration": 0,
        "project_path": "",  # Original project directory for reverse lookup (stop fix)
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
            # Round 1: Critical Issues (ruff errors, imports, syntax)
            "round1": {"critical": [], "medium": [], "low": []},
            # Round 2: Verification (verify fixes, regression check)
            "round2": {"verified": [], "failed": []},
            # Round 3: Documentation (docstrings, coverage gaps)
            "round3": {"doc_issues": [], "coverage_gaps": []},
            # Round 4: Adversarial Probing (edge cases, math validation)
            "round4": {"edge_cases_tested": [], "edge_cases_failed": [], "math_validated": [], "probing_complete": False},
            # Round 5: Cross-Period Robustness (Bull/Bear/Sideways)
            "round5": {"regimes_tested": [], "regime_results": {}, "robustness_score": 0.0},
        },
        "validation_score": 0.0,
        "validation_exhausted": False,
        "previous_finding_count": 0,
        "agent_results": [],
        "adapter_name": "",  # Active adapter for this session
        "adapter_convergence": None,  # Last adapter convergence result
        # Runtime tracking (v7.9.0): CLI active time vs wall-clock
        "accumulated_runtime_seconds": 0.0,  # Total CLI runtime (excludes pauses)
        "last_hook_timestamp": 0.0,  # For gap detection between hook calls
    }
    state = load_session_state(state_file, default_state)

    # Persist project_path for stop command discovery (v7.16.0)
    if not state.get("project_path") and project_dir:
        state["project_path"] = project_dir
        logger.info(f"Saved project_path for session discovery: {project_dir}")

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

    # ===== RUNTIME TRACKING (v7.9.0) =====
    # Track CLI active time (runtime) vs calendar time (wall-clock)
    # Runtime excludes periods when CLI was closed; used for all limit enforcement
    import time as time_module
    ralph_config = load_config(project_dir if project_dir else None)
    gap_threshold = ralph_config.loop_limits.cli_gap_threshold_seconds
    update_runtime(state, time_module.time(), gap_threshold)
    runtime_hours = get_runtime_hours(state)
    wall_hours = get_wall_clock_hours(session_id, project_dir)

    # ===== FORCE VALIDATION CHECK (for /ralph:audit-now) =====
    # Check if user triggered immediate validation via /ralph:audit-now
    if project_dir:
        ralph_config_file = Path(project_dir) / ".claude/ralph-config.json"
        if ralph_config_file.exists():
            try:
                ralph_config_raw = json.loads(ralph_config_file.read_text())
                force_validation = ralph_config_raw.get("force_validation", {})
                if force_validation.get("enabled"):
                    round_num = force_validation.get("round") or 1
                    state["validation_round"] = round_num
                    logger.info(f"Force validation enabled via /ralph:audit-now, entering round {round_num}")
                    # Clear the flag to prevent repeated triggering
                    ralph_config_raw["force_validation"]["enabled"] = False
                    ralph_config_file.write_text(json.dumps(ralph_config_raw, indent=2))
            except (json.JSONDecodeError, OSError) as e:
                logger.warning(f"Failed to check force_validation flag: {e}")

    iteration = state["iteration"] + 1
    recent_outputs: list[str] = state.get("recent_outputs", [])

    logger.info(
        f"Iteration {iteration}, runtime {runtime_hours:.2f}h, "
        f"wall {wall_hours:.2f}h, config={config}"
    )

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

    # ===== IDLE MONITORING DETECTION (with Stamina exponential backoff) =====
    # Prevent wasteful token consumption from rapid idle iterations
    # Uses exponential backoff: require longer intervals as idle count increases
    import time
    import subprocess
    import random

    now = time.time()
    last_iteration_time = state.get("last_iteration_time", 0)
    idle_count = state.get("idle_iteration_count", 0)

    # Exponential backoff parameters (stamina-style defaults)
    BASE_INTERVAL = 30  # Initial minimum interval (seconds)
    BACKOFF_MULTIPLIER = 2  # Double the required interval each idle iteration
    MAX_INTERVAL = 300  # Cap at 5 minutes
    JITTER = 5  # Random jitter to prevent thundering herd
    MAX_IDLE_BEFORE_EXPLORE = 1  # Zero tolerance: force exploration immediately on first idle

    # Calculate required interval with exponential backoff + jitter
    # Formula: min(base * 2^idle_count + jitter, max_interval)
    required_interval = min(
        BASE_INTERVAL * (BACKOFF_MULTIPLIER ** idle_count) + random.uniform(0, JITTER),
        MAX_INTERVAL
    )

    time_since_last = now - last_iteration_time if last_iteration_time > 0 else 999
    state["last_iteration_time"] = now

    # Check if any real files changed (not just .claude/* config files)
    real_work_done = False
    if project_dir:
        try:
            result = subprocess.run(
                ["git", "diff", "--name-only", "HEAD~1", "--", "."],
                cwd=project_dir, capture_output=True, text=True, timeout=5
            )
            changed_files = [f for f in result.stdout.strip().split('\n')
                           if f and not f.startswith('.claude/')]
            real_work_done = len(changed_files) > 0
        except Exception:
            real_work_done = True  # Assume work done if can't check

    # Detect idle pattern: iteration faster than required backoff interval + no real work
    if time_since_last < required_interval and not real_work_done:
        idle_count += 1
        state["idle_iteration_count"] = idle_count
        next_required = min(BASE_INTERVAL * (BACKOFF_MULTIPLIER ** idle_count), MAX_INTERVAL)
        logger.info(
            f"Idle iteration {idle_count}/{MAX_IDLE_BEFORE_EXPLORE}: "
            f"interval={time_since_last:.1f}s < required={required_interval:.1f}s "
            f"(next required: {next_required:.1f}s)"
        )

        if idle_count >= MAX_IDLE_BEFORE_EXPLORE:
            # Force exploration mode instead of allowing wasteful monitoring
            logger.info(f"Exponential backoff exhausted - forcing exploration mode")
            state["force_exploration"] = True
            state["idle_iteration_count"] = 0  # Reset counter
    else:
        if idle_count > 0:
            logger.info(f"Real work detected - resetting idle counter from {idle_count}")
        state["idle_iteration_count"] = 0  # Reset if real work done

    # ===== COMPLETION CASCADE =====

    if runtime_hours >= config["max_hours"]:
        allow_stop(f"Maximum runtime ({config['max_hours']}h) reached")
        return

    if iteration >= config["max_iterations"]:
        allow_stop(f"Maximum iterations ({config['max_iterations']}) reached")
        return

    # Check task_complete FIRST (before loop detection)
    task_complete, completion_reason, completion_confidence = check_task_complete_rssi(plan_file)

    # Loop detection: only allow stop if we're NOT in a valid waiting state
    if detect_loop(current_output, recent_outputs):
        # If task is complete, don't stop - transition to exploration instead
        if task_complete:
            logger.info("Loop detected but task complete - will transition to exploration")
            state["force_exploration"] = True
        else:
            # Task incomplete but agent is looping - this is stuck
            allow_stop("Loop detected: agent producing repetitive outputs (>90% similar)")
            return
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
                "converged": convergence.converged,  # For hard-blocking busywork
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

    min_hours_met = runtime_hours >= config["min_hours"]
    min_iterations_met = iteration >= config.get("min_iterations", 50)

    # ===== NO-FOCUS MODE CONVERGENCE =====
    # In no_focus mode, there's no plan file so task_complete is always False.
    # Instead, rely on adapter convergence to decide when to stop.
    if no_focus and min_hours_met and min_iterations_met:
        if adapter_should_stop and adapter_confidence >= 0.5:
            allow_stop(
                f"No-focus mode converged: Adapter ({adapter_reason}, "
                f"confidence={adapter_confidence:.2f})"
            )
            return
        # Also check for "idle loop" - no meaningful work for N consecutive iterations
        idle_iterations = state.get("idle_iterations", 0)
        if not adapter or adapter_confidence < 0.5:
            # No adapter guidance - check for idle state
            # If loop output contains "Work Item: None" repeatedly, increment idle counter
            if "Work Item: None" in current_output or "no SLO-aligned work" in current_output.lower():
                idle_iterations += 1
                state["idle_iterations"] = idle_iterations
                logger.info(f"Idle iteration detected: {idle_iterations}/1 - zero tolerance")
                if idle_iterations >= 1:
                    # Zero tolerance: force exploration immediately instead of allowing idle
                    state["force_exploration"] = True
                    state["idle_iterations"] = 0
                    logger.info("Zero idle tolerance - forcing exploration mode")
            else:
                state["idle_iterations"] = 0  # Reset if work is found

    # Combined decision: RSSI + Adapter must agree at confidence=0.5
    if task_complete and min_hours_met and min_iterations_met:
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
        runtime_hours=runtime_hours,
        wall_hours=wall_hours,
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
