#!/usr/bin/env python3
# /// script
# requires-python = ">=3.11"
# dependencies = ["pydantic>=2.10.0", "filelock>=3.20.0"]
# ///
"""Unified Ralph configuration schema - v3.0.0 (Pydantic migration).

ADR: Unified config-driven architecture for deterministic hook behavior.
All magic numbers externalized to a single JSON config file.

Config file location: .claude/ralph-config.json (per-project)
Fallback: ~/.claude/ralph-defaults.json (global defaults)

v3.0.0 Changes (2025-12-29):
- Migrated from dataclasses to Pydantic v2 for validation
- Added GuidanceConfig for forbidden/encouraged items
- Added ConstraintScanConfig for scanner results
- Added skip_constraint_scan flag
- Added filelock for atomic config read/write
"""

from enum import Enum
from pathlib import Path
from typing import Any
import json
import logging
import sys

from filelock import FileLock, Timeout
from pydantic import BaseModel, ConfigDict, Field, field_validator

logger = logging.getLogger(__name__)

# Lock timeout for config file operations
CONFIG_LOCK_TIMEOUT = 5  # seconds


class LoopState(str, Enum):
    """State machine for loop lifecycle.

    STOPPED → RUNNING → DRAINING → STOPPED

    - STOPPED: Loop disabled, default state
    - RUNNING: Loop actively executing iterations
    - DRAINING: Graceful shutdown, allow in-flight operations to complete
    """
    STOPPED = "stopped"
    RUNNING = "running"
    DRAINING = "draining"


class LoopDetectionConfig(BaseModel):
    """Configuration for loop/repetition detection.

    RSSI (Recursively Self-Improving Superintelligence) — Beyond AGI.
    Uses 0.99 threshold to only trigger on near-identical outputs,
    enabling the Intelligence Explosion: recursive self-improvement
    toward Artificial Superintelligence (ASI).
    """
    similarity_threshold: float = 0.99  # RSSI — Beyond AGI: Intelligence Explosion threshold
    window_size: int = 5  # Number of recent outputs to track

    model_config = ConfigDict(extra='ignore')


class CompletionConfig(BaseModel):
    """Configuration for task completion detection."""
    confidence_threshold: float = 0.7  # Minimum confidence to trigger completion

    # Confidence levels for different signals (higher = more certain)
    explicit_marker_confidence: float = 1.0  # [x] TASK_COMPLETE
    frontmatter_status_confidence: float = 0.95  # implementation-status: completed
    all_checkboxes_confidence: float = 0.9  # 100% checkbox coverage
    no_pending_items_confidence: float = 0.85  # Has [x] but no [ ]
    semantic_phrases_confidence: float = 0.7  # "task complete", etc.

    # Semantic completion phrases
    completion_phrases: list[str] = Field(default_factory=lambda: [
        "task complete",
        "all done",
        "finished",
        "implementation complete",
        "work complete",
    ])

    model_config = ConfigDict(extra='ignore')


class ValidationConfig(BaseModel):
    """Configuration for multi-round validation phase.

    5-Round Validation System:
    - Round 1: Critical Issues (ruff errors, imports, syntax)
    - Round 2: Verification (verify fixes, regression check)
    - Round 3: Documentation (docstrings, coverage gaps)
    - Round 4: Adversarial Probing (edge cases, math validation)
    - Round 5: Cross-Period Robustness (Bull/Bear/Sideways regime testing)
    """
    enabled: bool = True
    score_threshold: float = 0.8  # Score needed to consider validation complete
    max_rounds: int = 5  # 5-round validation (expanded from 3)
    improvement_threshold: float = 0.1  # 10% improvement required to continue

    # Score weights per round (must sum to 1.0)
    weight_round1_critical: float = 0.25  # Critical Issues
    weight_round2_verification: float = 0.20  # Verification
    weight_round3_documentation: float = 0.15  # Documentation
    weight_round4_adversarial: float = 0.20  # Adversarial Probing + Math Validation
    weight_round5_robustness: float = 0.20  # Cross-Period Robustness

    # POC mode timeout (seconds)
    timeout_poc: int = 30
    timeout_normal: int = 120

    # Round 4: Adversarial Probing settings
    edge_case_categories: list[str] = Field(default_factory=lambda: [
        "division_by_zero",
        "impossible_values",
        "extreme_values",
        "nan_inf_propagation",
    ])

    # Round 5: Cross-Period Robustness settings
    market_regimes: list[str] = Field(default_factory=lambda: [
        "bull",
        "bear",
        "sideways",
    ])

    model_config = ConfigDict(extra='ignore')


class LoopLimitsConfig(BaseModel):
    """Configuration for loop time/iteration limits.

    Note: min_hours/max_hours refer to CLI runtime (active time), not wall-clock.
    The cli_gap_threshold_seconds determines when gaps indicate CLI closure.
    """
    min_hours: float = 4.0
    max_hours: float = 9.0
    min_iterations: int = 50
    max_iterations: int = 99

    # POC mode overrides
    poc_min_hours: float = 0.083  # 5 minutes
    poc_max_hours: float = 0.167  # 10 minutes
    poc_min_iterations: int = 10
    poc_max_iterations: int = 20

    # CLI pause detection: gap > threshold = CLI was closed, don't count as runtime
    cli_gap_threshold_seconds: int = 300  # 5 minutes

    model_config = ConfigDict(extra='ignore')


class ProtectionConfig(BaseModel):
    """Configuration for file protection (PreToolUse guard)."""
    protected_files: list[str] = Field(default_factory=lambda: [
        ".claude/loop-enabled",
        ".claude/loop-start-timestamp",
        ".claude/ralph-config.json",
        ".claude/ralph-state.json",
    ])

    # Deletion patterns to detect
    deletion_patterns: list[str] = Field(default_factory=lambda: [
        r"\brm\b",
        r"\bunlink\b",
        r"> /dev/null",
        r">\s*/dev/null",
        r"truncate\b",
    ])

    # Bypass markers for official Ralph commands
    # Any command containing one of these markers bypasses deletion protection
    bypass_markers: list[str] = Field(default_factory=lambda: [
        "RALPH_STOP_SCRIPT",
        "RALPH_START_SCRIPT",
        "RALPH_ENCOURAGE_SCRIPT",
        "RALPH_FORBID_SCRIPT",
        "RALPH_AUDIT_SCRIPT",
        "RALPH_STATUS_SCRIPT",
        "RALPH_HOOKS_SCRIPT",
    ])

    # Legacy: single marker for backward compatibility
    stop_script_marker: str = "RALPH_STOP_SCRIPT"

    model_config = ConfigDict(extra='ignore')


class SubprocessTimeoutConfig(BaseModel):
    """Configuration for subprocess execution timeouts (seconds).

    Used by RSSI discovery to limit time spent on external tool calls.
    """
    ruff: int = 30  # Ruff linter timeout
    mypy: int = 60  # Mypy type checker timeout
    git: int = 10  # Git commands timeout
    grep: int = 30  # Grep/search commands timeout
    lychee: int = 30  # Link checker timeout

    model_config = ConfigDict(extra='ignore')


class GracefulShutdownConfig(BaseModel):
    """Configuration for DRAINING state behavior."""
    grace_period_seconds: int = 30  # Max time to wait in DRAINING state
    check_interval_seconds: float = 0.5  # How often to check for completion
    force_kill_on_timeout: bool = True  # Force cleanup after grace period

    model_config = ConfigDict(extra='ignore')


class GpuInfrastructureConfig(BaseModel):
    """Configuration for remote GPU infrastructure (Alpha Forge projects).

    This enables Ralph to suggest remote GPU execution for training-heavy tasks.
    Configure per-project in .claude/ralph-config.json.
    """
    available: bool = False  # Set to True to enable GPU suggestions
    host: str = ""  # SSH hostname (e.g., "littleblack")
    gpu: str = ""  # GPU description (e.g., "RTX 2080 Ti (11GB)")
    ssh_cmd: str = ""  # Full SSH command (e.g., "ssh kab@littleblack")

    model_config = ConfigDict(extra='ignore')


class GuidanceConfig(BaseModel):
    """User guidance for RSSI (forbidden/encouraged items).

    Populated by /ralph:start AUQ flow or manual /ralph:forbid /ralph:encourage.
    """
    forbidden: list[str] = Field(default_factory=list)
    encouraged: list[str] = Field(default_factory=list)
    timestamp: str = ""  # ISO 8601 timestamp of last update

    model_config = ConfigDict(extra='ignore')

    @field_validator('forbidden', 'encouraged', mode='before')
    @classmethod
    def ensure_list(cls, v: Any) -> list[str]:
        """Backwards compat: convert string to list if needed."""
        if v is None:
            return []
        if isinstance(v, str):
            return [v]
        if isinstance(v, list):
            return [str(item) for item in v]
        return []


class ConstraintScanConfig(BaseModel):
    """Constraint scanner results from /ralph:start preflight scan.

    4-tier severity system:
    - CRITICAL: Block loop start, must be resolved
    - HIGH: Escalate to user via AUQ, recommend prohibiting
    - MEDIUM: Show in deep-dive, optional action
    - LOW: Log only, informational
    """
    scan_timestamp: str = ""  # ISO 8601 timestamp
    project_dir: str = ""
    worktree_type: str = ""  # "main" | "linked"
    constraints: list[dict] = Field(default_factory=list)
    builtin_busywork: list[dict] = Field(default_factory=list)

    model_config = ConfigDict(extra='ignore')


class RalphConfig(BaseModel):
    """Unified Ralph configuration - v3.0.0 (Pydantic migration).

    Central config for all Ralph hooks. Supports both project-level
    (.claude/ralph-config.json) and global (~/.claude/ralph-defaults.json).
    """
    # State (managed by hooks, not user-editable)
    state: LoopState = LoopState.STOPPED

    # Sub-configurations
    loop_detection: LoopDetectionConfig = Field(default_factory=LoopDetectionConfig)
    completion: CompletionConfig = Field(default_factory=CompletionConfig)
    validation: ValidationConfig = Field(default_factory=ValidationConfig)
    loop_limits: LoopLimitsConfig = Field(default_factory=LoopLimitsConfig)
    protection: ProtectionConfig = Field(default_factory=ProtectionConfig)
    graceful_shutdown: GracefulShutdownConfig = Field(default_factory=GracefulShutdownConfig)
    gpu_infrastructure: GpuInfrastructureConfig = Field(default_factory=GpuInfrastructureConfig)
    subprocess_timeouts: SubprocessTimeoutConfig = Field(default_factory=SubprocessTimeoutConfig)

    # NEW v3.0.0: User guidance from AUQ screening
    guidance: GuidanceConfig = Field(default_factory=GuidanceConfig)

    # NEW v3.0.0: Constraint scan results
    constraint_scan: ConstraintScanConfig | None = None

    # NEW v3.0.0: Skip constraint scan flag
    skip_constraint_scan: bool = False

    # Session-specific (set by /ralph:start)
    target_file: str | None = None
    task_prompt: str | None = None
    no_focus: bool = False
    poc_mode: bool = False
    production_mode: bool = False  # NEW v3.0.0: Track production mode for auditability

    # Metadata
    version: str = "3.0.0"

    model_config = ConfigDict(
        extra='ignore',  # Backwards compat: ignore unknown fields from older configs
        validate_assignment=True,
    )


def get_config_path(project_dir: str | None = None) -> Path:
    """Get path to config file, preferring project-level."""
    if project_dir:
        project_config = Path(project_dir) / ".claude/ralph-config.json"
        if project_config.exists():
            return project_config

    # Fall back to global defaults
    global_config = Path.home() / ".claude/ralph-defaults.json"
    if global_config.exists():
        return global_config

    # Return project path for creation (if project_dir provided)
    if project_dir:
        return Path(project_dir) / ".claude/ralph-config.json"

    return global_config


def get_lock_path(config_path: Path) -> Path:
    """Get lock file path for a config file."""
    return config_path.with_suffix('.json.lock')


def load_config(project_dir: str | None = None) -> RalphConfig:
    """Load configuration from JSON file with file locking.

    Uses filelock to prevent race conditions when multiple Claude Code
    instances access the same config file.
    """
    config_path = get_config_path(project_dir)
    lock_path = get_lock_path(config_path)

    if config_path.exists():
        try:
            lock = FileLock(str(lock_path), timeout=CONFIG_LOCK_TIMEOUT)
            with lock:
                data = json.loads(config_path.read_text())
                logger.info(f"Loaded config from {config_path}")
                return RalphConfig.model_validate(data)
        except Timeout:
            print(f"[ralph] Warning: Config file locked, using defaults", file=sys.stderr)
            logger.warning(f"Config file locked after {CONFIG_LOCK_TIMEOUT}s, using defaults")
        except (json.JSONDecodeError, ValueError) as e:
            print(f"[ralph] Warning: Failed to parse config {config_path}: {e}", file=sys.stderr)
            logger.warning(f"Failed to parse config {config_path}: {e}")

    return RalphConfig()


def save_config(config: RalphConfig, project_dir: str | None = None) -> Path:
    """Save configuration to JSON file with atomic file locking.

    Uses filelock to prevent race conditions during concurrent writes.
    """
    if project_dir:
        config_path = Path(project_dir) / ".claude/ralph-config.json"
    else:
        config_path = Path.home() / ".claude/ralph-defaults.json"

    lock_path = get_lock_path(config_path)

    try:
        lock = FileLock(str(lock_path), timeout=CONFIG_LOCK_TIMEOUT)
        with lock:
            config_path.parent.mkdir(parents=True, exist_ok=True)
            config_path.write_text(config.model_dump_json(indent=2))
            logger.info(f"Saved config to {config_path}")
    except Timeout:
        print(f"[ralph] Error: Could not acquire lock for config save", file=sys.stderr)
        logger.error(f"Config file lock timeout after {CONFIG_LOCK_TIMEOUT}s")
        raise

    return config_path


def get_state_path(project_dir: str) -> Path:
    """Get path to state file (loop state machine)."""
    return Path(project_dir) / ".claude/ralph-state.json"


def load_state(project_dir: str) -> LoopState:
    """Load current loop state from state file with file locking."""
    state_path = get_state_path(project_dir)
    lock_path = state_path.with_suffix('.json.lock')

    if state_path.exists():
        try:
            lock = FileLock(str(lock_path), timeout=CONFIG_LOCK_TIMEOUT)
            with lock:
                data = json.loads(state_path.read_text())
                return LoopState(data.get("state", "stopped"))
        except Timeout:
            print(f"[ralph] Warning: State file locked, assuming STOPPED", file=sys.stderr)
            logger.warning(f"State file locked after {CONFIG_LOCK_TIMEOUT}s, assuming STOPPED")
        except json.JSONDecodeError as e:
            print(f"[ralph] Warning: State file corrupted ({e}), assuming STOPPED", file=sys.stderr)
            logger.warning(f"State file corrupted: {e}, assuming STOPPED")
        except ValueError as e:
            print(f"[ralph] Warning: Invalid state value ({e}), assuming STOPPED", file=sys.stderr)
            logger.warning(f"Invalid state value: {e}, assuming STOPPED")

    return LoopState.STOPPED


def save_state(project_dir: str, state: LoopState) -> None:
    """Save current loop state to state file with atomic file locking."""
    state_path = get_state_path(project_dir)
    lock_path = state_path.with_suffix('.json.lock')

    try:
        lock = FileLock(str(lock_path), timeout=CONFIG_LOCK_TIMEOUT)
        with lock:
            state_path.parent.mkdir(parents=True, exist_ok=True)
            state_path.write_text(json.dumps({
                "state": state.value,
            }))
            logger.info(f"State transition: {state.value}")
    except Timeout:
        print(f"[ralph] Error: Could not acquire lock for state save", file=sys.stderr)
        logger.error(f"State file lock timeout after {CONFIG_LOCK_TIMEOUT}s")
        raise


def transition_state(project_dir: str, from_state: LoopState, to_state: LoopState) -> bool:
    """Attempt state transition, returning success.

    Valid transitions:
    - STOPPED → RUNNING (via /ralph:start)
    - RUNNING → DRAINING (via /ralph:stop or error)
    - DRAINING → STOPPED (after grace period)
    """
    valid_transitions = {
        (LoopState.STOPPED, LoopState.RUNNING),
        (LoopState.RUNNING, LoopState.DRAINING),
        (LoopState.DRAINING, LoopState.STOPPED),
        # Allow direct stop in edge cases
        (LoopState.RUNNING, LoopState.STOPPED),
    }

    current = load_state(project_dir)

    if current != from_state:
        logger.warning(f"State mismatch: expected {from_state.value}, got {current.value}")
        return False

    if (from_state, to_state) not in valid_transitions:
        logger.error(f"Invalid transition: {from_state.value} → {to_state.value}")
        return False

    save_state(project_dir, to_state)
    return True


# Export default config for documentation
DEFAULT_CONFIG = RalphConfig()


# Backwards compatibility: dataclass-like functions for existing code
def dataclass_to_dict(obj: Any) -> dict:
    """Convert Pydantic model to dict (backwards compat wrapper)."""
    if isinstance(obj, BaseModel):
        return obj.model_dump()
    elif isinstance(obj, Enum):
        return obj.value
    elif isinstance(obj, list):
        return [dataclass_to_dict(item) for item in obj]
    elif isinstance(obj, dict):
        return {k: dataclass_to_dict(v) for k, v in obj.items()}
    return obj


def dict_to_dataclass(cls, data: dict):
    """Convert dict to Pydantic model (backwards compat wrapper)."""
    if hasattr(cls, 'model_validate'):
        return cls.model_validate(data)
    return data
