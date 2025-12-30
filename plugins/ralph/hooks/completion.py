"""Completion detection functions for Ralph hook.

Provides multi-signal completion detection (RSSI-grade) that works
with any file format (ADRs, specs, plans) without requiring explicit markers.
"""
import logging
import os
import re
from pathlib import Path

from core.config_schema import CompletionConfig, load_config

logger = logging.getLogger(__name__)


def get_corresponding_spec(adr_path: Path) -> Path | None:
    """Find the design spec corresponding to an ADR.

    ITP workflow convention:
    - ADR: docs/adr/YYYY-MM-DD-slug.md
    - Spec: docs/design/YYYY-MM-DD-slug/spec.md

    Args:
        adr_path: Path to ADR file

    Returns:
        Path to spec.md if found, None otherwise
    """
    # Check if this looks like an ADR path
    if "/adr/" not in str(adr_path) or not adr_path.name.endswith(".md"):
        return None

    # Extract the slug (filename without .md)
    slug = adr_path.stem  # e.g., "2025-12-20-ralph-itp-workflow-test"

    # Look for spec in docs/design/{slug}/spec.md
    project_root = adr_path.parent.parent.parent  # docs/adr/file.md -> project root
    spec_path = project_root / "docs" / "design" / slug / "spec.md"

    if spec_path.exists():
        logger.debug(f"Found corresponding spec: {spec_path}")
        return spec_path

    return None


def check_spec_completion(plan_file: str | None) -> tuple[bool, str]:
    """Check if the corresponding spec shows completion.

    For ADR files, also checks the design spec's implementation-status.

    Args:
        plan_file: Path to the plan/ADR file

    Returns:
        (is_complete, reason)
    """
    if not plan_file:
        return False, "no file"

    plan_path = Path(plan_file)
    spec_path = get_corresponding_spec(plan_path)

    if not spec_path:
        return False, "no corresponding spec"

    try:
        content = spec_path.read_text()
        if has_frontmatter_value(content, "implementation-status", "completed"):
            return True, f"spec implementation-status: completed ({spec_path.name})"
        if has_frontmatter_value(content, "implementation-status", "complete"):
            return True, f"spec implementation-status: complete ({spec_path.name})"
    except OSError as e:
        logger.warning(f"Could not read spec: {e}")

    return False, "spec not complete"

def get_completion_config() -> CompletionConfig:
    """Get completion detection parameters from config."""
    project_dir = os.environ.get("CLAUDE_PROJECT_DIR", "")
    config = load_config(project_dir if project_dir else None)
    return config.completion


def has_frontmatter_value(content: str, key: str, value: str) -> bool:
    """Check if markdown has YAML frontmatter with specific key: value.

    Args:
        content: Markdown file content
        key: Frontmatter key to check
        value: Expected value

    Returns:
        True if frontmatter contains key: value
    """
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


def has_explicit_completion_marker(content: str) -> bool:
    """Check for explicit TASK_COMPLETE markers in content.

    Supports multiple checkbox formats:
    - [x] TASK_COMPLETE
    - [X] TASK_COMPLETE
    - - [x] TASK_COMPLETE
    - * [x] TASK_COMPLETE
    """
    for line in content.split('\n'):
        line_stripped = line.strip()
        if any([
            line_stripped in ('- [x] TASK_COMPLETE', '[x] TASK_COMPLETE'),
            line_stripped in ('* [x] TASK_COMPLETE', '[X] TASK_COMPLETE'),
            'TASK_COMPLETE' in line_stripped and '[x]' in line_stripped.lower(),
        ]):
            return True
    return False


def count_checkboxes(content: str) -> tuple[int, int]:
    """Count total and checked checkboxes in content.

    Args:
        content: Markdown file content

    Returns:
        (total, checked) - number of checkboxes found and how many are checked
    """
    total = 0
    checked = 0
    for line in content.split('\n'):
        line_stripped = line.strip()
        # Match unchecked: - [ ] or * [ ]
        if line_stripped.startswith('- [ ]') or line_stripped.startswith('* [ ]'):
            total += 1
        # Match checked: - [x] or * [x] or - [X] or * [X]
        elif (line_stripped.startswith('- [x]') or line_stripped.startswith('* [x]') or
              line_stripped.startswith('- [X]') or line_stripped.startswith('* [X]')):
            total += 1
            checked += 1
    return total, checked


def check_task_complete_ralph(plan_file: str | None) -> tuple[bool, str, float]:
    """Ralph (Recursively Self-Improving Superintelligence) completion detection using multiple signals.

    Analyzes the plan file using 5 different signals to detect completion,
    returning the highest confidence match. Confidence levels are configurable
    via .claude/ralph-config.json.

    Signals:
    1. Explicit marker ([x] TASK_COMPLETE) - configurable confidence
    2. Frontmatter status (implementation-status: completed) - configurable
    3. All checkboxes checked - configurable
    4. No pending items (has [x] but no [ ]) - configurable
    5. Semantic phrases ("task complete", "all done") - configurable

    Args:
        plan_file: Path to the plan/task file

    Returns:
        (is_complete, reason, confidence) - confidence is 0.0-1.0
    """
    if not plan_file or not Path(plan_file).exists():
        return False, "no file to check", 0.0

    try:
        content = Path(plan_file).read_text()
    except OSError:
        return False, "file read error", 0.0

    # Load configurable confidence levels
    cfg = get_completion_config()

    signals: list[tuple[str, float]] = []

    # Signal 1: Explicit markers (high confidence)
    if has_explicit_completion_marker(content):
        signals.append(("explicit_marker", cfg.explicit_marker_confidence))

    # Signal 2: YAML frontmatter status fields
    if has_frontmatter_value(content, "implementation-status", "completed"):
        signals.append(("frontmatter_completed", cfg.frontmatter_status_confidence))
    if has_frontmatter_value(content, "implementation-status", "complete"):
        signals.append(("frontmatter_complete", cfg.frontmatter_status_confidence))
    if has_frontmatter_value(content, "status", "implemented"):
        signals.append(("adr_implemented", cfg.frontmatter_status_confidence))

    # Signal 2b: Corresponding spec completion (for ADR files)
    # If focus file is an ADR, check the design spec's implementation-status
    spec_complete, spec_reason = check_spec_completion(plan_file)
    if spec_complete:
        signals.append((spec_reason, cfg.frontmatter_status_confidence))

    # Signal 3: Checklist analysis - all items checked
    total, checked = count_checkboxes(content)
    if total > 0 and checked == total:
        signals.append(("all_checkboxes_checked", cfg.all_checkboxes_confidence))

    # Signal 4: Semantic completion phrases (from config)
    # Use word-boundary matching to prevent false positives like
    # "**Implementation Complete**: All 12 models" matching "implementation complete"
    content_lower = content.lower()
    phrase_pattern = r"\b(" + "|".join(re.escape(p) for p in cfg.completion_phrases) + r")\b"
    if re.search(phrase_pattern, content_lower):
        signals.append(("semantic_phrase", cfg.semantic_phrases_confidence))

    # Signal 5: No unchecked items remain (but has checked items)
    if "[ ]" not in content and "[x]" in content.lower():
        signals.append(("no_pending_items", cfg.no_pending_items_confidence))

    # Return highest confidence signal
    if signals:
        best = max(signals, key=lambda x: x[1])
        logger.info(f"Completion detected via {best[0]} with confidence {best[1]}")
        return True, best[0], best[1]

    return False, "not_complete", 0.0


def check_validation_complete(validation_findings: dict) -> tuple[bool, str, list[str]]:
    """Check if all 5 validation rounds have passed.

    5-Round Validation System:
    - Round 1: Critical Issues (no critical issues remaining)
    - Round 2: Verification (all fixes verified, no failures)
    - Round 3: Documentation (no doc issues, no coverage gaps)
    - Round 4: Adversarial Probing (probing complete, no edge case failures)
    - Round 5: Cross-Period Robustness (all regimes tested, score > 0)

    Args:
        validation_findings: Dict with round1-round5 data from session state

    Returns:
        Tuple of (all_passed, summary, incomplete_rounds)
    """
    incomplete_rounds: list[str] = []
    failed_round_numbers: set[int] = set()

    # Round 1: Critical Issues
    round1 = validation_findings.get("round1", {})
    if round1.get("critical", []):
        incomplete_rounds.append("Round 1: Critical issues remain")
        failed_round_numbers.add(1)

    # Round 2: Verification
    round2 = validation_findings.get("round2", {})
    if round2.get("failed", []):
        incomplete_rounds.append("Round 2: Verification failures")
        failed_round_numbers.add(2)

    # Round 3: Documentation
    round3 = validation_findings.get("round3", {})
    if round3.get("doc_issues", []) or round3.get("coverage_gaps", []):
        incomplete_rounds.append("Round 3: Documentation/coverage gaps")
        failed_round_numbers.add(3)

    # Round 4: Adversarial Probing (can have multiple issues)
    round4 = validation_findings.get("round4", {})
    if not round4.get("probing_complete", False):
        incomplete_rounds.append("Round 4: Adversarial probing incomplete")
        failed_round_numbers.add(4)
    if round4.get("edge_cases_failed", []):
        incomplete_rounds.append("Round 4: Edge case failures")
        failed_round_numbers.add(4)

    # Round 5: Cross-Period Robustness (can have multiple issues)
    round5 = validation_findings.get("round5", {})
    if not round5.get("regimes_tested", []):
        incomplete_rounds.append("Round 5: No regimes tested")
        failed_round_numbers.add(5)
    if round5.get("robustness_score", 0.0) <= 0.0:
        incomplete_rounds.append("Round 5: Robustness score is 0")
        failed_round_numbers.add(5)

    all_passed = len(failed_round_numbers) == 0
    passed_count = 5 - len(failed_round_numbers)

    if all_passed:
        summary = "All 5 validation rounds passed"
    else:
        summary = f"{passed_count}/5 rounds passed"

    return all_passed, summary, incomplete_rounds


def get_validation_round_status(validation_findings: dict) -> dict[str, str]:
    """Get status of each validation round for display.

    Args:
        validation_findings: Dict with round1-round5 data from session state

    Returns:
        Dict mapping round names to status strings
    """
    status = {}

    # Round 1
    round1 = validation_findings.get("round1", {})
    critical = len(round1.get("critical", []))
    medium = len(round1.get("medium", []))
    low = len(round1.get("low", []))
    if critical == 0 and medium == 0:
        status["Round 1: Critical Issues"] = "✓ Passed"
    else:
        status["Round 1: Critical Issues"] = f"✗ {critical} critical, {medium} medium, {low} low"

    # Round 2
    round2 = validation_findings.get("round2", {})
    verified = len(round2.get("verified", []))
    failed = len(round2.get("failed", []))
    if failed == 0 and verified > 0:
        status["Round 2: Verification"] = f"✓ {verified} verified"
    elif failed > 0:
        status["Round 2: Verification"] = f"✗ {failed} failed"
    else:
        status["Round 2: Verification"] = "○ Not started"

    # Round 3
    round3 = validation_findings.get("round3", {})
    doc_issues = len(round3.get("doc_issues", []))
    coverage_gaps = len(round3.get("coverage_gaps", []))
    if doc_issues == 0 and coverage_gaps == 0:
        status["Round 3: Documentation"] = "✓ Passed"
    else:
        status["Round 3: Documentation"] = f"✗ {doc_issues} doc issues, {coverage_gaps} gaps"

    # Round 4
    round4 = validation_findings.get("round4", {})
    probing_complete = round4.get("probing_complete", False)
    edge_cases_failed = len(round4.get("edge_cases_failed", []))
    math_validated = len(round4.get("math_validated", []))
    if probing_complete and edge_cases_failed == 0:
        status["Round 4: Adversarial"] = f"✓ {math_validated} math validated"
    elif edge_cases_failed > 0:
        status["Round 4: Adversarial"] = f"✗ {edge_cases_failed} edge cases failed"
    else:
        status["Round 4: Adversarial"] = "○ Not started"

    # Round 5
    round5 = validation_findings.get("round5", {})
    regimes_tested = round5.get("regimes_tested", [])
    robustness_score = round5.get("robustness_score", 0.0)
    if regimes_tested and robustness_score > 0:
        status["Round 5: Robustness"] = f"✓ Score: {robustness_score:.2f}"
    elif regimes_tested:
        status["Round 5: Robustness"] = f"✗ Score: {robustness_score:.2f}"
    else:
        status["Round 5: Robustness"] = "○ Not started"

    return status
