"""Validation phase functions for Ralph hook.

Implements the 3-round validation architecture:
- Round 1: Static analysis (parallel sub-agents)
- Round 2: Semantic verification (sequential)
- Round 3: Consistency audit (parallel)
"""
import json
import logging
import shutil
import subprocess

logger = logging.getLogger(__name__)

# Validation phase constants
VALIDATION_SCORE_THRESHOLD = 0.8
MAX_VALIDATION_ITERATIONS = 3
VALIDATION_IMPROVEMENT_THRESHOLD = 0.1


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

    Scoring:
    - Base 0.5 if no critical issues
    - +0.3 if no medium issues
    - +0.1 if doc alignment complete
    - +0.1 if test coverage gaps <= 2

    Args:
        state: Current loop state with validation_findings

    Returns:
        Score from 0.0 to 1.0
    """
    findings = state.get("validation_findings", {})
    score = 0.0

    # Check Round 1 findings
    round1 = findings.get("round1", {})
    critical_count = len(round1.get("critical", []))
    medium_count = len(round1.get("medium", []))

    if critical_count == 0:
        score += 0.5

    if medium_count == 0:
        score += 0.3

    # Check Round 3 findings
    round3 = findings.get("round3", {})
    doc_issues = len(round3.get("doc_issues", []))
    coverage_gaps = len(round3.get("coverage_gaps", []))

    if doc_issues == 0:
        score += 0.1

    if coverage_gaps <= 2:
        score += 0.1

    logger.info(
        f"Validation score: {score:.2f} "
        f"(critical={critical_count}, medium={medium_count}, "
        f"doc_issues={doc_issues}, coverage_gaps={coverage_gaps})"
    )
    return score


def check_validation_exhausted(state: dict) -> bool:
    """Determine if validation phase is complete.

    Exhaustion conditions (any of):
    1. Validation score >= 0.8 after completing all 3 rounds
    2. Max validation iterations reached (3)
    3. Improvement threshold not met (<10% new findings in last iteration)

    Args:
        state: Current loop state

    Returns:
        True if validation is exhausted, False otherwise
    """
    validation_round = state.get("validation_round", 0)
    validation_iteration = state.get("validation_iteration", 0)
    validation_score = state.get("validation_score", 0.0)

    # Must complete at least one full cycle (3 rounds)
    if validation_round < 3:
        return False

    # Check score threshold
    if validation_score >= VALIDATION_SCORE_THRESHOLD:
        logger.info(f"Validation exhausted: score {validation_score:.2f} >= {VALIDATION_SCORE_THRESHOLD}")
        return True

    # Check max iterations
    if validation_iteration >= MAX_VALIDATION_ITERATIONS:
        logger.info(f"Validation exhausted: max iterations ({MAX_VALIDATION_ITERATIONS}) reached")
        return True

    # Check improvement threshold
    current_findings = state.get("validation_findings", {})
    current_count = sum(
        len(current_findings.get(f"round{i}", {}).get(sev, []))
        for i in range(1, 4)
        for sev in ["critical", "medium", "low", "doc_issues", "coverage_gaps", "verified", "failed"]
    )
    previous_count = state.get("previous_finding_count", 0)

    if previous_count > 0:
        improvement = abs(current_count - previous_count) / previous_count
        if improvement < VALIDATION_IMPROVEMENT_THRESHOLD:
            logger.info(
                f"Validation exhausted: improvement {improvement:.2%} < {VALIDATION_IMPROVEMENT_THRESHOLD:.0%}"
            )
            return True

    return False
