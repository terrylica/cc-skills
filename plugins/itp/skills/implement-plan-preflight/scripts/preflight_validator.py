# /// script
# requires-python = ">=3.11"
# dependencies = []
# ///
"""
Preflight Validator - Verify ADR and Design Spec artifacts exist.

ADR: implement-plan-preflight skill

Usage:
    uv run preflight_validator.py <adr-id>

Example:
    uv run preflight_validator.py 2025-12-01-clickhouse-aws-ohlcv-ingestion
"""

import os
import re
import sys
from pathlib import Path

# ADR: 2025-12-08-mise-env-centralized-config
# Configuration via environment variables with defaults for backward compatibility
ADR_DIR = os.environ.get("ADR_DIR", "docs/adr")
DESIGN_DIR = os.environ.get("DESIGN_DIR", "docs/design")
DESIGN_SPEC_FILENAME = os.environ.get("DESIGN_SPEC_FILENAME", "spec.md")


def validate_adr_frontmatter(adr_path: Path) -> list[str]:
    """Validate ADR has required YAML frontmatter fields."""
    errors = []
    required_fields = [
        "status",
        "date",
        "decision-maker",
        "consulted",
        "research-method",
        "clarification-iterations",
        "perspectives",
    ]

    content = adr_path.read_text()

    # Check for frontmatter
    if not content.startswith("---"):
        errors.append("ADR missing YAML frontmatter (must start with ---)")
        return errors

    # Extract frontmatter
    parts = content.split("---", 2)
    if len(parts) < 3:
        errors.append("ADR frontmatter not properly closed (missing closing ---)")
        return errors

    frontmatter = parts[1]

    for field in required_fields:
        if f"{field}:" not in frontmatter:
            errors.append(f"ADR missing required frontmatter field: {field}")

    return errors


def validate_adr_sections(adr_path: Path) -> list[str]:
    """Validate ADR has required sections."""
    errors = []
    required_sections = [
        "Context and Problem Statement",
        "Research Summary",
        "Decision Log",
        "Considered Options",
        "Decision Outcome",
        "Synthesis",
        "Consequences",
        "Architecture",
    ]

    content = adr_path.read_text()

    for section in required_sections:
        if f"## {section}" not in content:
            errors.append(f"ADR missing required section: ## {section}")

    # Check for Design Spec link
    if "**Design Spec**:" not in content:
        errors.append("ADR missing Design Spec link in header")

    return errors


def validate_spec_backlink(spec_path: Path, adr_id: str) -> list[str]:
    """Validate design spec has ADR backlink."""
    errors = []
    content = spec_path.read_text()

    if "**ADR**:" not in content:
        errors.append("Design spec missing ADR backlink in header")

    if adr_id not in content:
        errors.append(f"Design spec ADR link doesn't reference {adr_id}")

    return errors


def validate_spec_frontmatter(spec_path: Path) -> list[str]:
    """Validate design spec has required YAML frontmatter fields."""
    errors = []
    required_fields = [
        "adr",
        "source",
        "implementation-status",
        "phase",
        "last-updated",
    ]

    content = spec_path.read_text()

    # Check for frontmatter
    if not content.startswith("---"):
        errors.append("Spec missing YAML frontmatter (must start with ---)")
        return errors

    # Extract frontmatter
    parts = content.split("---", 2)
    if len(parts) < 3:
        errors.append("Spec frontmatter not properly closed (missing closing ---)")
        return errors

    frontmatter = parts[1]

    for field in required_fields:
        if f"{field}:" not in frontmatter:
            errors.append(f"Spec missing required frontmatter field: {field}")

    # Validate implementation-status value
    valid_statuses = ["in_progress", "blocked", "completed", "abandoned"]
    if "implementation-status:" in frontmatter:
        status_match = re.search(r"implementation-status:\s*(\S+)", frontmatter)
        if status_match:
            status = status_match.group(1)
            if status not in valid_statuses:
                errors.append(
                    f"Spec has invalid implementation-status: {status} "
                    f"(expected: {', '.join(valid_statuses)})"
                )

    # Validate phase value
    valid_phases = ["preflight", "phase-1", "phase-2", "phase-3"]
    if "phase:" in frontmatter:
        phase_match = re.search(r"phase:\s*(\S+)", frontmatter)
        if phase_match:
            phase = phase_match.group(1)
            if phase not in valid_phases:
                errors.append(
                    f"Spec has invalid phase: {phase} "
                    f"(expected: {', '.join(valid_phases)})"
                )

    return errors


def main():
    if len(sys.argv) != 2:
        print("Usage: uv run preflight_validator.py <adr-id>")
        print("Example: uv run preflight_validator.py 2025-12-01-my-feature")
        sys.exit(1)

    adr_id = sys.argv[1]

    # Validate ADR ID format
    if not re.match(r"^\d{4}-\d{2}-\d{2}-[\w-]+$", adr_id):
        print(f"Invalid ADR ID format: {adr_id}")
        print("Expected format: YYYY-MM-DD-slug")
        sys.exit(1)

    adr_path = Path(f"{ADR_DIR}/{adr_id}.md")
    spec_path = Path(f"{DESIGN_DIR}/{adr_id}/{DESIGN_SPEC_FILENAME}")

    all_errors = []

    # Check file existence
    print(f"Validating preflight artifacts for: {adr_id}")
    print("-" * 50)

    if not adr_path.exists():
        all_errors.append(f"ADR file not found: {adr_path}")
    else:
        print(f"[OK] ADR file exists: {adr_path}")
        all_errors.extend(validate_adr_frontmatter(adr_path))
        all_errors.extend(validate_adr_sections(adr_path))

    if not spec_path.exists():
        all_errors.append(f"Design spec not found: {spec_path}")
    else:
        print(f"[OK] Design spec exists: {spec_path}")
        all_errors.extend(validate_spec_frontmatter(spec_path))
        all_errors.extend(validate_spec_backlink(spec_path, adr_id))

    # Report results
    print("-" * 50)

    if all_errors:
        print(f"\n[FAIL] Preflight validation failed with {len(all_errors)} error(s):\n")
        for error in all_errors:
            print(f"  - {error}")
        sys.exit(1)
    else:
        print("\n[PASS] Preflight validation successful!")
        print("All artifacts exist and are properly formatted.")
        sys.exit(0)


if __name__ == "__main__":
    main()
