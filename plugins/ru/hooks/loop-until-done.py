#!/usr/bin/env python3
# /// script
# requires-python = ">=3.11"
# dependencies = ["rapidfuzz>=3.0.0,<4.0.0", "jinja2>=3.1.0,<4.0.0", "pydantic>=2.10.0", "filelock>=3.20.0"]
# ///
# ADR: Multi-Repository Adapter Architecture
# ADR: 2025-12-20-ralph-rssi-eternal-loop
# Adds project-specific convergence detection via adapter registry
# Ralph eternal loop implementation (Levels 2-6)
"""
Ralph Universal Stop Hook - Autonomous improvement engine for ANY project.

Implements an eternal loop with recursive self-improvement behavior.
Works on any project type with universal fallback adapter.
Issue #12: https://github.com/terrylica/cc-skills/issues/12

Ralph Behavior:
- Task completion → pivot to exploration (not stop)
- Adapter convergence → pivot to exploration (not stop)
- Loop detection (99% threshold) → continue with exploration
- User-controlled stops → /ralph:stop, kill switch, max limits

All pivots emit to stderr.

Stopping Criteria (KEPT):
- hard_stop(): /ralph:stop, kill switch, DRAINING→STOPPED
- allow_stop(): max_hours, max_iterations, state=STOPPED

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
from datetime import datetime
from pathlib import Path

# Import from modular components
from completion import check_task_complete_ralph
from core.config_schema import LoopLimitsConfig, LoopState, load_config, load_state, save_state
from core.constants import (
    ADAPTER_CONFIDENCE_THRESHOLD,
    BACKOFF_BASE_INTERVAL,
    BACKOFF_JITTER,
    BACKOFF_MAX_INTERVAL,
    BACKOFF_MULTIPLIER,
    CONFIG_DIR,
    # Issue #12: Alpha-Forge specific constants removed
    # IMPROVEMENT_PLATEAU_THRESHOLD,
    ITERATIONS_WARNING_THRESHOLD,
    MAX_IDLE_BEFORE_EXPLORE,
    # MIN_METRICS_FOR_COMPARISON,
    STATE_DIR,
    TIME_WARNING_THRESHOLD_HOURS,
    # WFE_OVERFITTING_THRESHOLD,
)
from core.path_hash import build_state_file_path, get_path_hash, load_session_state
# Issue #12: Alpha-Forge specific detection removed for universal compatibility
# from core.project_detection import is_alpha_forge_project
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
from ralph_evolution import (
    get_learned_patterns,
    get_disabled_checks,
    get_prioritized_checks,
    suggest_capability_expansion,
)
from observability import emit, flush_to_claude, reset_timer


def _run_constraint_scanner(project_dir: Path | None) -> list[dict]:
    """Run constraint scanner and return discovered constraints.

    ADR: /docs/adr/2026-01-02-ralph-guidance-freshness-detection.md

    Returns list of constraint dicts with 'description', 'severity', 'type' keys.
    """
    import subprocess

    if not project_dir:
        return []

    ralph_cache = Path.home() / ".claude/plugins/cache/cc-skills/ralph"
    scanner_path: Path | None = None

    # Find scanner script (same pattern as start.md)
    if (ralph_cache / "local" / "scripts/constraint-scanner.py").exists():
        scanner_path = ralph_cache / "local" / "scripts/constraint-scanner.py"
    elif ralph_cache.exists():
        versions = sorted(
            [d for d in ralph_cache.iterdir() if d.is_dir() and d.name[0].isdigit()],
            reverse=True,
        )
        if versions:
            scanner_path = versions[0] / "scripts/constraint-scanner.py"

    if not scanner_path or not scanner_path.exists():
        return []

    # Find uv (same pattern as start.md discover_uv)
    uv_cmd = None
    for loc in [
        "uv",  # PATH
        str(Path.home() / ".local/bin/uv"),
        str(Path.home() / ".cargo/bin/uv"),
        "/opt/homebrew/bin/uv",
        "/usr/local/bin/uv",
        str(Path.home() / ".local/share/mise/shims/uv"),
    ]:
        import shutil
        if shutil.which(loc) or Path(loc).is_file():
            uv_cmd = loc
            break

    if not uv_cmd:
        return []

    try:
        result = subprocess.run(
            [uv_cmd, "run", "-q", str(scanner_path), "--project", str(project_dir)],
            capture_output=True,
            text=True,
            timeout=30,
            env={**os.environ, "UV_VERBOSITY": "0"},
        )
        if result.returncode == 0:
            data = json.loads(result.stdout)
            return data.get("constraints", [])
    except (subprocess.TimeoutExpired, json.JSONDecodeError, OSError) as e:
        emit("Constraint scan", f"Failed: {e}")
    return []


# Configure logging
logging.basicConfig(
    level=logging.DEBUG,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[logging.FileHandler(STATE_DIR / 'loop-hook.log')]
)
logger = logging.getLogger(__name__)

CONFIG_FILE = CONFIG_DIR / "loop_config.json"


# Issue #12: _build_web_queries removed - was Alpha-Forge specific
# Universal web queries are now hardcoded in build_continuation_prompt


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
    """Build continuation prompt using unified Ralph template.

    Single code path for all modes. User guidance (encourage/forbid) ALWAYS applies.

    Args:
        runtime_hours: CLI active time (used for limit enforcement)
        wall_hours: Calendar time since start (informational)
    """
    if state is None:
        state = {}

    # Detect adapter - uses registry with universal fallback
    # Issue #12: Removed Alpha-Forge specific detection
    adapter_name = state.get("adapter_name", "")

    # Force exploration if state says so
    force_exploration = state.get("force_exploration", False)

    # Determine effective task_complete (exploration if force_exploration or no_focus)
    effective_task_complete = task_complete or force_exploration or no_focus

    # ===== LOAD USER GUIDANCE (ALWAYS - this is the fix) =====
    # ADR: /docs/adr/2026-01-02-ralph-guidance-freshness-detection.md
    guidance = {}
    config_guidance = {}
    guidance_timestamp = ""

    if project_dir:
        ralph_config_file = Path(project_dir) / ".claude/ru-config.json"
        if ralph_config_file.exists():
            try:
                ralph_config = json.loads(ralph_config_file.read_text())
                config_guidance = ralph_config.get("guidance", {})
                guidance_timestamp = config_guidance.get("timestamp", "")
            except (json.JSONDecodeError, OSError) as e:
                print(f"[ralph] Warning: Failed to load ru-config.json: {e}", file=sys.stderr)
                emit("Config", f"Failed to load ru-config.json: {e}", target="terminal")

    # ===== ON-THE-FLY CONSTRAINT SCANNING =====
    # ADR: /docs/adr/2026-01-02-ralph-guidance-freshness-detection.md
    fresh_constraints = _run_constraint_scanner(Path(project_dir) if project_dir else None)
    emit("Constraint scan", f"Found {len(fresh_constraints)} constraints")

    # ===== FRESH-WINS MERGE LOGIC =====
    # Fresh scan results override stale config guidance
    fresh_forbidden = [c["description"] for c in fresh_constraints if c.get("severity") in ("critical", "high")]
    fresh_encouraged = [c["description"] for c in fresh_constraints if c.get("type") == "encouraged"]

    # Check if config guidance is stale (> 24h old or from previous session)
    config_forbidden = config_guidance.get("forbidden", [])
    config_encouraged = config_guidance.get("encouraged", [])

    if guidance_timestamp:
        # Check staleness - compare to session start
        session_start_file = Path(project_dir) / ".claude/loop-start-timestamp" if project_dir else None
        if session_start_file and session_start_file.exists():
            try:
                session_start = int(session_start_file.read_text().strip())
                from datetime import timezone
                guidance_dt = datetime.fromisoformat(guidance_timestamp.replace("Z", "+00:00"))
                guidance_epoch = int(guidance_dt.timestamp())
                if guidance_epoch < session_start:
                    emit("Guidance", "Clearing stale config guidance (from previous session)")
                    config_forbidden = []
                    config_encouraged = []
            except (ValueError, OSError) as e:
                emit("Guidance", f"Timestamp check failed: {e}")
    else:
        # No timestamp = legacy config, treat as stale
        if config_forbidden or config_encouraged:
            emit("Guidance", "Clearing legacy config guidance (missing timestamp)")
            config_forbidden = []
            config_encouraged = []

    # Merge: fresh + current-session config (deduplicated)
    final_forbidden = list(set(fresh_forbidden + config_forbidden))
    final_encouraged = list(set(fresh_encouraged + config_encouraged))

    guidance = {
        "forbidden": final_forbidden,
        "encouraged": final_encouraged,
    }

    # Emit config status
    if guidance.get("forbidden") or guidance.get("encouraged"):
        n_forbidden = len(guidance.get("forbidden", []))
        n_encouraged = len(guidance.get("encouraged", []))
        emit("Config", f"Guidance merged: {n_forbidden} forbidden, {n_encouraged} encouraged")
    else:
        emit("Config", "No guidance configured (using defaults)")

    # ===== BUILD UNIFIED RALPH CONTEXT =====
    adapter_conv = state.get("adapter_convergence", {})
    ralph_context = {
        # Core iteration tracking
        "iteration": iteration,
        "adapter_convergence": adapter_conv,
        "guidance": guidance,  # User guidance ALWAYS loaded
        "project_dir": project_dir or "",
        # Ralph (Recursively Self-Improving Superintelligence) evolution state
        "accumulated_patterns": list(get_learned_patterns().keys()),
        "disabled_checks": get_disabled_checks(),
        "effective_checks": get_prioritized_checks(),
        # Feature discovery
        "feature_ideas": state.get("feature_ideas", []),
        "web_insights": state.get("web_insights", []),
        # Capability expansion
        "missing_tools": suggest_capability_expansion(Path(project_dir)) if project_dir else [],
        # Issue #12: Universal quality gate (adapter-agnostic)
        "quality_gate": [],  # Adapters can provide their own quality gates
        # Issue #12: Universal web research queries
        "web_queries": [
            f"project improvement SOTA {datetime.now().year - 1}-{datetime.now().year}"
        ],
    }

    # Get metrics history from adapter (if available)
    metrics_history = adapter_conv.get("metrics_history", []) if adapter_conv else []

    # ===== BUILD HEADER =====
    time_to_max = max(0, config["max_hours"] - runtime_hours)
    iters_to_max = max(0, config["max_iterations"] - iteration)
    remaining_hours = max(0, config["min_hours"] - runtime_hours)
    remaining_iters = max(0, config.get("min_iterations", 50) - iteration)

    warning = ""
    if time_to_max < TIME_WARNING_THRESHOLD_HOURS or iters_to_max < ITERATIONS_WARNING_THRESHOLD:
        warning = " | **ENDING SOON**"

    mode = "EXPLORATION" if effective_task_complete else "IMPLEMENTATION"
    header = (
        f"**Ralph — {mode}** | "
        f"Iteration {iteration}/{config['max_iterations']} | "
        f"Runtime: {runtime_hours:.1f}h/{config['max_hours']}h | Wall: {wall_hours:.1f}h | "
        f"{remaining_hours:.1f}h / {remaining_iters} iters to min{warning}"
    )

    # Focus file context (only in focused mode)
    focus_suffix = ""
    if plan_file and not no_focus:
        if discovery_method:
            focus_suffix = f"\n\n**Focus file** (via {discovery_method}): {plan_file}"
        else:
            focus_suffix = f"\n\n**Focus file**: {plan_file}"

    # ===== RENDER UNIFIED TEMPLATE =====
    loader = get_loader()
    prompt = loader.render_unified(
        task_complete=effective_task_complete,
        ralph_context=ralph_context,
        adapter_name=adapter_name,
        metrics_history=metrics_history,
        opportunities=[],
    )

    # Todo sync instruction
    todo_suffix = ""
    if state:
        todo_items = generate_todo_items(state)
        todo_instruction = format_todo_instruction(todo_items)
        if todo_instruction:
            todo_suffix = f"\n\n{todo_instruction}"

    return f"{header}{focus_suffix}\n\n{prompt}{todo_suffix}"


def main():
    """Main entry point for the Stop hook."""
    try:
        hook_input = json.load(sys.stdin) if not sys.stdin.isatty() else {}
    except json.JSONDecodeError as e:
        print(f"[ralph] Warning: Failed to parse stdin JSON: {e}", file=sys.stderr)
        hook_input = {}

    session_id = hook_input.get("session_id", "unknown")
    stop_hook_active = hook_input.get("stop_hook_active", False)
    transcript_path = hook_input.get("transcript_path")

    # Reset observability timer at start of each hook invocation
    reset_timer()

    logger.info(f"Stop hook called: session={session_id}, stop_hook_active={stop_hook_active}")

    project_dir = os.environ.get("CLAUDE_PROJECT_DIR", "")

    # ===== RALPH-UNIVERSAL: NO PROJECT TYPE RESTRICTION =====
    # Unlike the original Ralph (Alpha-Forge only), ru works on ANY project.
    # The Alpha-Forge exclusivity guard has been surgically removed.
    # See: https://github.com/terrylica/cc-skills/issues/12

    # ===== EARLY EXIT CHECKS =====

    # Global stop signal (version-agnostic, v7.16.2+)
    # This file is created by /ralph:stop and checked by ALL hook versions
    # FIX(2026-01-02): Fresh signals always trigger hard_stop regardless of consumed_by
    # Root cause: worktree vs main repo project_dir mismatch caused consumed_by check to fail
    global_stop = Path.home() / ".claude/ralph-global-stop.json"
    if global_stop.exists():
        try:
            global_data = json.loads(global_stop.read_text())
            if global_data.get("state") == "stopped":
                # Check signal freshness first (< 5 min = fresh)
                from datetime import datetime, timezone
                ts_str = global_data.get("timestamp", "")
                is_fresh = False
                if ts_str:
                    try:
                        signal_time = datetime.fromisoformat(ts_str.replace("Z", "+00:00"))
                        age_seconds = (datetime.now(timezone.utc) - signal_time).total_seconds()
                        is_fresh = age_seconds < 300  # 5 minutes
                        if not is_fresh:
                            # Stale signal - clean up and continue
                            global_stop.unlink(missing_ok=True)
                            emit("Global stop", f"Cleaned up stale signal ({age_seconds:.0f}s old)")
                    except ValueError:
                        # Can't parse timestamp - treat as fresh to be safe
                        is_fresh = True
                else:
                    # No timestamp - treat as fresh (legacy format)
                    is_fresh = True

                # Fresh signal = hard stop (regardless of consumed_by)
                if is_fresh:
                    # Track consumption for debugging (but don't gate on it)
                    consumed_by = global_data.get("consumed_by", [])
                    if project_dir and project_dir not in consumed_by:
                        consumed_by.append(project_dir)
                        global_data["consumed_by"] = consumed_by
                        global_stop.write_text(json.dumps(global_data))
                    # Update project state if we have a project_dir
                    if project_dir:
                        save_state(project_dir, LoopState.STOPPED)
                    hard_stop("Loop stopped via global stop signal (~/.claude/ralph-global-stop.json)")
                    return
        except (json.JSONDecodeError, OSError) as e:
            print(f"[ralph] Warning: Failed to read global stop signal: {e}", file=sys.stderr)

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
        kill_switch.unlink(missing_ok=True)  # Safe: file may be deleted between check and unlink
        if project_dir:
            save_state(project_dir, LoopState.STOPPED)
        hard_stop("Loop stopped via kill switch (.claude/STOP_LOOP)")
        return

    # ===== LOAD STATE =====
    # Use path hash for session state isolation (git worktree support)
    path_hash = get_path_hash(project_dir)
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
    # Load state with inheritance fallback for cross-session continuity
    # When session_id changes (auto-compact, /clear, rate limits), inherits from
    # most recent same-project session. See path_hash.py for inheritance logic.
    state = load_session_state(
        state_file,
        default_state,
        state_dir=STATE_DIR,
        path_hash=path_hash,
    )
    emit("State", f"Loaded session state: iteration {state.get('iteration', 0)}, runtime {state.get('accumulated_runtime_seconds', 0):.0f}s")

    # Persist project_path for stop command discovery (v7.16.0)
    if not state.get("project_path") and project_dir:
        state["project_path"] = project_dir
        logger.info(f"Saved project_path for session discovery: {project_dir}")

    # Load config with defaults from LoopLimitsConfig
    defaults = LoopLimitsConfig()
    default_config = {
        "min_hours": defaults.min_hours,
        "max_hours": defaults.max_hours,
        "min_iterations": defaults.min_iterations,
        "max_iterations": defaults.max_iterations,
    }
    try:
        config = json.loads(CONFIG_FILE.read_text()) if CONFIG_FILE.exists() else default_config
    except (json.JSONDecodeError, OSError) as e:
        print(f"[ralph] Warning: Failed to load loop config: {e}", file=sys.stderr)
        config = default_config

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
        except (json.JSONDecodeError, OSError) as e:
            print(f"[ralph] Warning: Failed to load project config: {e}", file=sys.stderr)

    # ===== ADAPTER DISCOVERY =====
    # Auto-discover and select project-specific adapter
    adapters_dir = Path(__file__).parent / "adapters"
    AdapterRegistry.discover(adapters_dir)
    adapter = AdapterRegistry.get_adapter(Path(project_dir)) if project_dir else None

    if adapter:
        state["adapter_name"] = adapter.name
        logger.info(f"Using adapter: {adapter.name}")
        emit("Adapter", f"Selected adapter: {adapter.name}")
    else:
        emit("Adapter", "No project adapter (using defaults)")

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

    # Emit discovery result
    if plan_file:
        emit("Discovery", f"Found {plan_file} via {discovery_method}")
    elif no_focus:
        emit("Discovery", "No-focus mode active (autonomous exploration)")
    else:
        emit("Discovery", f"No target file found ({len(candidate_files)} candidates)")

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
        ralph_config_file = Path(project_dir) / ".claude/ru-config.json"
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
        except (json.JSONDecodeError, KeyError, IndexError, OSError, TypeError) as e:
            print(f"[ralph] Warning: Failed to parse transcript for output extraction: {e}", file=sys.stderr)

    # ===== IDLE MONITORING DETECTION (with Stamina exponential backoff) =====
    # Prevent wasteful token consumption from rapid idle iterations
    # Uses exponential backoff: require longer intervals as idle count increases
    import time
    import subprocess
    import random

    now = time.time()
    last_iteration_time = state.get("last_iteration_time", 0)
    idle_count = state.get("idle_iteration_count", 0)

    # Calculate required interval with exponential backoff + jitter
    # Formula: min(base * 2^idle_count + jitter, max_interval)
    required_interval = min(
        BACKOFF_BASE_INTERVAL * (BACKOFF_MULTIPLIER ** idle_count) + random.uniform(0, BACKOFF_JITTER),
        BACKOFF_MAX_INTERVAL
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
        except Exception as e:
            print(f"[ralph] Warning: Git diff check failed, assuming work done: {e}", file=sys.stderr)
            real_work_done = True  # Assume work done if can't check

    # Detect idle pattern: iteration faster than required backoff interval + no real work
    if time_since_last < required_interval and not real_work_done:
        idle_count += 1
        state["idle_iteration_count"] = idle_count
        next_required = min(BACKOFF_BASE_INTERVAL * (BACKOFF_MULTIPLIER ** idle_count), BACKOFF_MAX_INTERVAL)
        logger.info(
            f"Idle iteration {idle_count}/{MAX_IDLE_BEFORE_EXPLORE}: "
            f"interval={time_since_last:.1f}s < required={required_interval:.1f}s "
            f"(next required: {next_required:.1f}s)"
        )
        emit("Backoff", f"Idle iteration {idle_count}/{MAX_IDLE_BEFORE_EXPLORE} (next wait: {next_required:.0f}s)")

        if idle_count >= MAX_IDLE_BEFORE_EXPLORE:
            # Force exploration mode instead of allowing wasteful monitoring
            logger.info("Exponential backoff exhausted - forcing exploration mode")
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
    task_complete, completion_reason, completion_confidence = check_task_complete_ralph(plan_file)

    # Loop detection: only allow stop if we're NOT in a valid waiting state
    # Ralph uses 0.99 threshold (configurable) to reduce false positives
    loop_detected = detect_loop(current_output, recent_outputs)
    if loop_detected:
        emit("Analysis", "Loop detected: outputs 99%+ similar")
        # If task is complete, don't stop - transition to exploration instead
        if task_complete:
            logger.info("Loop detected but task complete - will transition to exploration")
            state["force_exploration"] = True
        else:
            # Task incomplete but agent is looping - this is stuck
            allow_stop("Loop detected: agent producing near-identical outputs")
            return
    state["last_completion_confidence"] = completion_confidence
    if task_complete:
        state["completion_signals"].append(completion_reason)

    # ===== ADAPTER CONVERGENCE CHECK =====
    # Project-specific convergence detection (requires Ralph agreement at confidence=0.5)
    adapter_should_stop = False
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
            emit(
                "Convergence",
                f"Adapter: continue={convergence.should_continue}, "
                f"confidence={convergence.confidence:.2f}"
            )

            # High confidence (1.0) = Ralph pivots to exploration (no stop)
            # Medium confidence (0.5) = requires Ralph agreement
            # Low confidence (0.0) = defer to Ralph
            if convergence.confidence >= 1.0:
                if not convergence.should_continue:
                    # Ralph: Pivot to exploration instead of stopping
                    logger.info("Ralph: Adapter converged at 1.0 confidence, pivoting to exploration")
                    print("\n[Ralph — Beyond AGI] Adapter converged → pivoting to new frontiers\n", file=sys.stderr)
                    state["force_exploration"] = True
                    # Don't return - fall through to continue_session()
                # If should_continue with high confidence, force continue below
            elif convergence.confidence >= ADAPTER_CONFIDENCE_THRESHOLD:
                adapter_should_stop = not convergence.should_continue
                adapter_confidence = convergence.confidence
        except Exception as e:
            logger.warning(f"Adapter convergence check failed: {e}")

    min_hours_met = runtime_hours >= config["min_hours"]
    min_iterations_met = iteration >= config.get("min_iterations", 50)

    # ===== NO-FOCUS MODE CONVERGENCE =====
    # In no_focus mode, there's no plan file so task_complete is always False.
    # Ralph: Pivot to exploration instead of stopping when adapter converges.
    if no_focus and min_hours_met and min_iterations_met:
        if adapter_should_stop and adapter_confidence >= ADAPTER_CONFIDENCE_THRESHOLD:
            # Ralph: Pivot to exploration instead of stopping
            logger.info("Ralph: No-focus mode converged, pivoting to exploration")
            print("\n[Ralph — Beyond AGI] Research converged → transcending to new domains\n", file=sys.stderr)
            state["force_exploration"] = True
            # Don't return - fall through to continue_session()
        # Also check for "idle loop" - no meaningful work for N consecutive iterations
        idle_iterations = state.get("idle_iterations", 0)
        if not adapter or adapter_confidence < ADAPTER_CONFIDENCE_THRESHOLD:
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

    # Ralph: Task completion triggers exploration pivot, not stop
    # Ralph always finds new work — beyond AGI
    if task_complete and min_hours_met and min_iterations_met:
        # Ralph: Pivot to exploration instead of stopping
        logger.info(f"Ralph: Task complete ({completion_reason}), pivoting to exploration")
        print("\n[Ralph — Beyond AGI] Task complete → recursive self-improvement continues\n", file=sys.stderr)
        state["force_exploration"] = True
        # Don't return - fall through to continue_session()

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
        print(f"[ralph] ERROR: Failed to save state: {e}", file=sys.stderr)
        logger.error(f"Failed to save state: {e}")

    continue_session(reason)


if __name__ == "__main__":
    main()
