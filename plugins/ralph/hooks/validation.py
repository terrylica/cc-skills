"""Validation phase functions for Ralph hook.

Implements the 3-round validation architecture:
- Round 1: Static analysis (parallel sub-agents)
- Round 2: Semantic verification (sequential)
- Round 3: Consistency audit (parallel)
"""
import json
import logging
import os
import shutil
import subprocess

from core.config_schema import ValidationConfig, load_config

logger = logging.getLogger(__name__)

# Legacy constants (deprecated - use config instead)
VALIDATION_SCORE_THRESHOLD = 0.8
MAX_VALIDATION_ITERATIONS = 3
VALIDATION_IMPROVEMENT_THRESHOLD = 0.1


def get_validation_config() -> ValidationConfig:
    """Get validation phase parameters from config."""
    project_dir = os.environ.get("CLAUDE_PROJECT_DIR", "")
    config = load_config(project_dir if project_dir else None)
    return config.validation


def ensure_validation_tool(tool_name: str) -> bool:
    """Attempt to ensure tool is available, installing via mise if needed.

    Priority:
    1. Check if tool already exists in PATH
    2. Try mise install if mise is available
    3. Return False if not available (caller should use Claude-only fallback)

    Args:
        tool_name: Name of the tool to check/install (e.g., 'lychee', 'gitleaks')

    Returns:
        True if tool is available, False otherwise
    """
    # Check if already available
    if shutil.which(tool_name):
        return True

    # Try mise install
    if shutil.which("mise"):
        try:
            result = subprocess.run(
                ["mise", "install", tool_name],
                capture_output=True,
                timeout=60
            )
            if result.returncode == 0 and shutil.which(tool_name):
                logger.info(f"Installed {tool_name} via mise")
                return True
        except (subprocess.TimeoutExpired, OSError) as e:
            logger.warning(f"Failed to install {tool_name} via mise: {e}")

    # Tool not available, will use Claude-only fallback
    logger.info(f"{tool_name} not available, using Claude-only analysis")
    return False


def aggregate_agent_results(agent_outputs: list[str]) -> dict:
    """Parse sub-agent JSON outputs into structured findings.

    Expected agent output format:
    {
        "findings": [
            {"severity": "critical|medium|low", "file": "...", "line": N, "code": "...", "message": "..."}
        ],
        "tool_used": "ruff|lychee|gitleaks|claude-analysis",
        "success": true
    }

    Args:
        agent_outputs: List of raw output strings from sub-agents

    Returns:
        Aggregated findings dict with critical/medium/low arrays
    """
    aggregated = {
        "critical": [],
        "medium": [],
        "low": [],
        "tools_used": [],
        "parse_errors": 0
    }

    for output in agent_outputs:
        if not output or not output.strip():
            continue
        try:
            # Try to extract JSON from output (may have surrounding text)
            json_start = output.find('{')
            json_end = output.rfind('}') + 1
            if json_start >= 0 and json_end > json_start:
                data = json.loads(output[json_start:json_end])
                if "findings" in data:
                    for finding in data["findings"]:
                        severity = finding.get("severity", "low").lower()
                        if severity in aggregated:
                            aggregated[severity].append(finding)
                if "tool_used" in data:
                    aggregated["tools_used"].append(data["tool_used"])
        except json.JSONDecodeError:
            aggregated["parse_errors"] += 1
            logger.warning(f"Failed to parse agent output as JSON: {output[:100]}...")

    return aggregated


def compute_validation_score(state: dict) -> float:
    """Calculate 0.0-1.0 validation score from aggregated findings.

    Scoring weights are configurable via .claude/ralph-config.json:
    - weight_no_critical_issues (default 0.5)
    - weight_no_medium_issues (default 0.3)
    - weight_no_doc_issues (default 0.1)
    - weight_low_coverage_gaps (default 0.1)

    Args:
        state: Current loop state with validation_findings

    Returns:
        Score from 0.0 to 1.0
    """
    cfg = get_validation_config()
    findings = state.get("validation_findings", {})
    score = 0.0

    # Check Round 1 findings
    round1 = findings.get("round1", {})
    critical_count = len(round1.get("critical", []))
    medium_count = len(round1.get("medium", []))

    if critical_count == 0:
        score += cfg.weight_no_critical_issues

    if medium_count == 0:
        score += cfg.weight_no_medium_issues

    # Check Round 3 findings
    round3 = findings.get("round3", {})
    doc_issues = len(round3.get("doc_issues", []))
    coverage_gaps = len(round3.get("coverage_gaps", []))

    if doc_issues == 0:
        score += cfg.weight_no_doc_issues

    if coverage_gaps <= 2:
        score += cfg.weight_low_coverage_gaps

    logger.info(
        f"Validation score: {score:.2f} "
        f"(critical={critical_count}, medium={medium_count}, "
        f"doc_issues={doc_issues}, coverage_gaps={coverage_gaps})"
    )
    return score


def check_validation_exhausted(state: dict) -> bool:
    """Determine if validation phase is complete.

    Exhaustion conditions (configurable via .claude/ralph-config.json):
    1. Validation score >= score_threshold after completing all 3 rounds
    2. Max validation iterations reached
    3. Improvement threshold not met

    Args:
        state: Current loop state

    Returns:
        True if validation is exhausted, False otherwise
    """
    cfg = get_validation_config()
    validation_round = state.get("validation_round", 0)
    validation_iteration = state.get("validation_iteration", 0)
    validation_score = state.get("validation_score", 0.0)

    # Must complete at least one full cycle (3 rounds)
    if validation_round < 3:
        return False

    # Check score threshold (configurable)
    if validation_score >= cfg.score_threshold:
        logger.info(f"Validation exhausted: score {validation_score:.2f} >= {cfg.score_threshold}")
        return True

    # Check max iterations (configurable)
    if validation_iteration >= cfg.max_iterations:
        logger.info(f"Validation exhausted: max iterations ({cfg.max_iterations}) reached")
        return True

    # Check improvement threshold (configurable)
    current_findings = state.get("validation_findings", {})
    current_count = sum(
        len(current_findings.get(f"round{i}", {}).get(sev, []))
        for i in range(1, 4)
        for sev in ["critical", "medium", "low", "doc_issues", "coverage_gaps", "verified", "failed"]
    )
    previous_count = state.get("previous_finding_count", 0)

    if previous_count > 0:
        improvement = abs(current_count - previous_count) / previous_count
        if improvement < cfg.improvement_threshold:
            logger.info(
                f"Validation exhausted: improvement {improvement:.2%} < {cfg.improvement_threshold:.0%}"
            )
            return True

    return False
