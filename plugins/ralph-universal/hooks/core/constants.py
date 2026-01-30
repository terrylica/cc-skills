"""Semantic constants for Ralph autonomous loop engine.

This module centralizes magic numbers used throughout the Ralph hooks,
making them self-documenting and easy to tune.

ADR: Extracted from PLR2004 audit (v7.16.3)
"""

from pathlib import Path

# =============================================================================
# PATHS
# =============================================================================
# Central state directory for Ralph loop orchestrator
STATE_DIR = Path.home() / ".claude/automation/loop-orchestrator/state"
CONFIG_DIR = STATE_DIR.parent / "config"

# Ensure directories exist (required before any FileHandler can write logs)
STATE_DIR.mkdir(parents=True, exist_ok=True)
CONFIG_DIR.mkdir(parents=True, exist_ok=True)

# =============================================================================
# CONFIDENCE THRESHOLDS
# =============================================================================
# Minimum confidence level for adapter to influence stop decisions
ADAPTER_CONFIDENCE_THRESHOLD = 0.5

# Ralph (Recursively Self-Improving Superintelligence) completion confidence levels
RALPH_CONFIDENCE_LOW = 0.3    # Low confidence - needs more signals
RALPH_CONFIDENCE_MED = 0.5    # Medium confidence - can influence decisions
RALPH_CONFIDENCE_HIGH = 0.7   # High confidence - strong signal

# =============================================================================
# PERFORMANCE THRESHOLDS (Trading Strategy Metrics)
# =============================================================================
# Walk-Forward Efficiency thresholds
WFE_OVERFITTING_THRESHOLD = 0.5      # Below this suggests overfitting
WFE_SEVERE_OVERFITTING = 0.1         # Severe overfitting indicator
WFE_UNUSUALLY_HIGH = 0.95            # Suspiciously high, verify calculation

# Sharpe Ratio bounds
SHARPE_SUSPICIOUS_HIGH = 5.0         # Above this is likely overfitting
SHARPE_STRATEGY_FLAW = -3.0          # Below this suggests fundamental flaw
SHARPE_MAX_REASONABLE = 10.0         # Maximum reasonable Sharpe ratio

# Improvement thresholds
IMPROVEMENT_PLATEAU_THRESHOLD = 0.05  # Less than 5% improvement = plateau

# =============================================================================
# LOOP CONTROL
# =============================================================================
# Warning thresholds for approaching limits
TIME_WARNING_THRESHOLD_HOURS = 1.0   # Show warning when < 1 hour remaining
ITERATIONS_WARNING_THRESHOLD = 5     # Show warning when < 5 iterations remaining

# Retry/window limits
RECENT_OUTPUTS_WINDOW = 5            # Number of recent outputs to track for loop detection
MIN_METRICS_FOR_COMPARISON = 2       # Minimum metrics history for trend analysis

# Exponential backoff parameters (idle detection)
BACKOFF_BASE_INTERVAL = 30           # Initial minimum interval (seconds)
BACKOFF_MULTIPLIER = 2               # Double required interval each idle iteration
BACKOFF_MAX_INTERVAL = 300           # Cap at 5 minutes (300 seconds)
BACKOFF_JITTER = 5                   # Random jitter to prevent thundering herd
MAX_IDLE_BEFORE_EXPLORE = 1          # Zero tolerance: force exploration on first idle

# Gap detection for CLI pause tracking
CLI_GAP_THRESHOLD = 300              # 5 minutes gap = CLI was closed

# =============================================================================
# RALPH DISCOVERY
# =============================================================================
# Maximum concurrent sub-agents for Ralph exploration
RALPH_MAX_SUB_AGENTS = 3

# Maximum web search results to process
WEB_SEARCH_MAX_RESULTS = 100

# Structural analysis limits
MIN_PY_FILES_FOR_README = 3          # Min Python files in dir to suggest README
SAMPLE_FILES_LIMIT = 5               # Number of files to sample for docstring check

# =============================================================================
# RALPH META (Effectiveness Tracking)
# =============================================================================
# Minimum samples before evaluating check effectiveness
MIN_SAMPLES_FOR_EVALUATION = 5
MIN_SAMPLES_FOR_DISABLING = 10

# Effectiveness thresholds for checks
LOW_EFFECTIVENESS_THRESHOLD = 0.2        # Consider disabling below this
VERY_LOW_EFFECTIVENESS_THRESHOLD = 0.1   # Disable check below this
HIGH_EFFECTIVENESS_THRESHOLD = 0.7       # Consider expanding above this

# Default coverage threshold for pytest
DEFAULT_COVERAGE_THRESHOLD = 80

# Discovery effectiveness warning
DISCOVERY_LOW_EFFECTIVENESS = 0.3        # Below this suggests poor targeting

# Capability expansion threshold
CAPABILITY_EXPANSION_THRESHOLD = 0.5     # Expand capabilities above this

# =============================================================================
# RETURNS VALIDATION
# =============================================================================
# Extreme returns threshold (10x = 1000% gain/loss)
RETURNS_EXTREME_THRESHOLD = 10.0

# =============================================================================
# VALIDATION ROUNDS (5-Round Validation System)
# =============================================================================
ROUND_CRITICAL_ISSUES = 1      # Round 1: Critical issues check
ROUND_VERIFICATION = 2         # Round 2: Fix verification
ROUND_DOCUMENTATION = 3        # Round 3: Documentation check
ROUND_ADVERSARIAL = 4          # Round 4: Adversarial probing
ROUND_ROBUSTNESS = 5           # Round 5: Cross-period robustness

# =============================================================================
# QUALITY GATES
# =============================================================================
# Minimum GitHub stars for solution adoption
MIN_STARS_FOR_ADOPTION = 100

# Maximum priority value (P0=0, P1=1, P2=2)
MAX_PRIORITY_VALUE = 2

# =============================================================================
# TODO SYNC
# =============================================================================
# Truncation limits for todo content display
TODO_CONTENT_MAX_LENGTH = 30

# Priority level thresholds (lower = higher priority)
TODO_PRIORITY_URGENT = 2
TODO_PRIORITY_HIGH = 3
TODO_PRIORITY_NORMAL = 4
TODO_PRIORITY_LOW = 5

# =============================================================================
# WORK POLICY
# =============================================================================
# Maximum output length before truncation warning
OUTPUT_LENGTH_WARNING = 200
