"""Detect mathematical code requiring validation.

Part of Ralph's 5-Round Validation System (Round 4: Adversarial Probing).
Identifies mathematical operations in code that require first-principles validation.
"""

import re
from pathlib import Path

# Patterns that indicate mathematical code requiring validation
MATH_PATTERNS: dict[str, str] = {
    "numpy_operations": r"\bnp\.(mean|std|var|sum|dot|sqrt|log|exp|divide)\b",
    "division_operations": r"[^/]/[^/]",  # Single slash (not //)
    "ratio_calculations": r"\b(ratio|rate|percentage|proportion)\b",
    "statistical_functions": r"\b(correlation|covariance|sharpe|sortino|calmar|wfe)\b",
    "financial_metrics": r"\b(drawdown|cagr|returns|volatility|beta|alpha)\b",
    "aggregations": r"\.(mean|std|sum|max|min|median)\(",
}

# Severity levels for different patterns
PATTERN_SEVERITY: dict[str, str] = {
    "division_operations": "HIGH",
    "financial_metrics": "HIGH",
    "statistical_functions": "HIGH",
    "numpy_operations": "MEDIUM",
    "ratio_calculations": "MEDIUM",
    "aggregations": "MEDIUM",
}


def detect_math_code(file_path: Path, content: str) -> list[dict]:
    """Detect mathematical operations in code.

    Scans code content for patterns indicating mathematical operations
    that require validation per Round 4 (Adversarial Probing) of the
    5-Round Validation System.

    Args:
        file_path: Path to the file being analyzed
        content: Source code content to analyze

    Returns:
        List of findings, each containing:
        - pattern: Name of the matched pattern
        - line: Line number (1-indexed)
        - matched: List of matched strings
        - severity: HIGH or MEDIUM
        - file: String path to the file
    """
    findings: list[dict] = []

    for line_num, line in enumerate(content.splitlines(), 1):
        for pattern_name, regex in MATH_PATTERNS.items():
            matches = re.findall(regex, line, re.IGNORECASE)
            if matches:
                findings.append({
                    "pattern": pattern_name,
                    "line": line_num,
                    "matched": matches,
                    "severity": PATTERN_SEVERITY.get(pattern_name, "MEDIUM"),
                    "file": str(file_path),
                })

    return findings


def detect_math_in_files(files: list[Path]) -> dict[str, list[dict]]:
    """Detect mathematical code in multiple files.

    Args:
        files: List of file paths to analyze

    Returns:
        Dict mapping file paths to their findings
    """
    results: dict[str, list[dict]] = {}

    for file_path in files:
        if not file_path.exists():
            continue
        if not file_path.suffix == ".py":
            continue

        try:
            content = file_path.read_text()
            findings = detect_math_code(file_path, content)
            if findings:
                results[str(file_path)] = findings
        except OSError:
            continue

    return results


def summarize_findings(findings: list[dict]) -> dict:
    """Summarize math detection findings.

    Args:
        findings: List of findings from detect_math_code()

    Returns:
        Summary dict with counts by severity and pattern
    """
    summary = {
        "total": len(findings),
        "high_severity": sum(1 for f in findings if f["severity"] == "HIGH"),
        "medium_severity": sum(1 for f in findings if f["severity"] == "MEDIUM"),
        "by_pattern": {},
    }

    for finding in findings:
        pattern = finding["pattern"]
        summary["by_pattern"][pattern] = summary["by_pattern"].get(pattern, 0) + 1

    return summary
