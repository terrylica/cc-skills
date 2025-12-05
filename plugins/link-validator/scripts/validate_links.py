#!/usr/bin/env python3
# /// script
# requires-python = ">=3.11"
# dependencies = []
# ///
"""
Skill Link Validator
====================

Validates markdown links in Claude Code skills for portability.

**Problem**: Absolute repo paths like `/skills/foo/SKILL.md` break when
plugins are installed outside the original repository structure.

**Solution**: Skills MUST use relative paths (`./`, `../`) that work in
any installation location.

Usage:
    uv run validate_links.py <skill-path>
    uv run validate_links.py ~/.claude/skills/my-skill/
    uv run validate_links.py .  # Current directory

Exit Codes:
    0 = All links valid (relative paths)
    1 = Violations found (absolute repo paths)
    2 = Error (invalid path, no markdown files)
"""

import re
import sys
from pathlib import Path
from dataclasses import dataclass


@dataclass
class LinkViolation:
    """Represents a link portability violation."""
    file_path: Path
    line_number: int
    link_text: str
    link_url: str


# Regex patterns
MARKDOWN_LINK_PATTERN = re.compile(r'\[([^\]]+)\]\(([^)]+)\)')
ABSOLUTE_REPO_PATH_PATTERN = re.compile(r'^/(?!/)(?!https?:)(?!#)')
CODE_BLOCK_PATTERN = re.compile(r'```[\s\S]*?```')


def is_absolute_repo_path(url: str) -> bool:
    """Check if URL is an absolute repository path (violation)."""
    url = url.strip()
    if not url:
        return False
    return bool(ABSOLUTE_REPO_PATH_PATTERN.match(url))


def scan_file(file_path: Path) -> list[LinkViolation]:
    """Scan a single markdown file for violations."""
    violations = []

    try:
        content = file_path.read_text(encoding='utf-8')
    except Exception as e:
        print(f"Warning: Could not read {file_path}: {e}", file=sys.stderr)
        return violations

    # Track if we're inside a code block
    in_code_block = False

    for line_num, line in enumerate(content.split('\n'), start=1):
        # Toggle code block state
        if line.strip().startswith('```'):
            in_code_block = not in_code_block
            continue

        # Skip lines in code blocks
        if in_code_block:
            continue

        # Skip inline code by removing backtick content
        scannable_line = re.sub(r'`[^`]+`', '', line)

        for match in MARKDOWN_LINK_PATTERN.finditer(scannable_line):
            link_text = match.group(1)
            link_url = match.group(2)

            if is_absolute_repo_path(link_url):
                violations.append(LinkViolation(
                    file_path=file_path,
                    line_number=line_num,
                    link_text=link_text,
                    link_url=link_url,
                ))

    return violations


def scan_skill(skill_path: Path) -> list[LinkViolation]:
    """Scan all markdown files in a skill directory."""
    all_violations = []

    # Find all markdown files
    md_files = list(skill_path.glob("**/*.md"))

    if not md_files:
        return all_violations

    for md_file in md_files:
        # Skip node_modules if present
        if 'node_modules' in md_file.parts:
            continue
        violations = scan_file(md_file)
        all_violations.extend(violations)

    return all_violations


def suggest_fix(violation: LinkViolation, skill_path: Path) -> str:
    """Suggest a relative path fix for a violation."""
    # Get the file's location relative to skill root
    try:
        rel_file = violation.file_path.relative_to(skill_path)
    except ValueError:
        return "(cannot determine relative path)"

    # Calculate depth from skill root
    depth = len(rel_file.parts) - 1  # -1 for the file itself

    # The absolute path starts with /skills/ typically
    abs_url = violation.link_url

    # Common patterns
    if abs_url.startswith('/skills/'):
        # Link to another skill
        target_skill = abs_url.split('/')[2]  # /skills/<name>/...
        rest = '/'.join(abs_url.split('/')[3:])

        if depth == 0:
            # From SKILL.md at root
            return f"../{target_skill}/{rest}" if rest else f"../{target_skill}/SKILL.md"
        else:
            # From references/ or scripts/
            prefix = '../' * (depth + 1)
            return f"{prefix}{target_skill}/{rest}" if rest else f"{prefix}{target_skill}/SKILL.md"

    return "(review manually)"


def report_results(violations: list[LinkViolation], skill_path: Path) -> None:
    """Print validation results."""
    if not violations:
        print(f"✅ Link validation passed: {skill_path}")
        print("   All markdown links use relative paths (plugin-portable)")
        return

    print(f"❌ Link validation FAILED: {skill_path}")
    print(f"   Found {len(violations)} absolute repo-path violation(s)")
    print()

    # Group by file
    by_file: dict[Path, list[LinkViolation]] = {}
    for v in violations:
        by_file.setdefault(v.file_path, []).append(v)

    for file_path, file_violations in sorted(by_file.items()):
        try:
            rel_path = file_path.relative_to(skill_path)
        except ValueError:
            rel_path = file_path

        print(f"📄 {rel_path}")
        for v in file_violations:
            print(f"   Line {v.line_number}: [{v.link_text}]({v.link_url})")
            suggested = suggest_fix(v, skill_path)
            print(f"   → Suggested: {suggested}")
        print()

    print("Why this matters:")
    print("  Skills install to ~/.claude/skills/<name>/ - absolute paths break.")
    print("  Use relative paths: ./references/foo.md, ../sibling/SKILL.md")
    print()


def main() -> int:
    """Main entry point."""
    if len(sys.argv) < 2:
        print("Usage: uv run validate_links.py <skill-path>", file=sys.stderr)
        print("       uv run validate_links.py ~/.claude/skills/my-skill/", file=sys.stderr)
        return 2

    skill_path = Path(sys.argv[1]).resolve()

    if not skill_path.exists():
        print(f"Error: Path does not exist: {skill_path}", file=sys.stderr)
        return 2

    if not skill_path.is_dir():
        print(f"Error: Path is not a directory: {skill_path}", file=sys.stderr)
        return 2

    # Check for SKILL.md (indicates this is a skill directory)
    if not (skill_path / "SKILL.md").exists():
        # Maybe it's a plugin with multiple skills?
        skills_dir = skill_path / "skills"
        if skills_dir.exists():
            print(f"Scanning plugin directory: {skill_path}")
            all_violations = []
            for sub_skill in skills_dir.iterdir():
                if sub_skill.is_dir() and (sub_skill / "SKILL.md").exists():
                    violations = scan_skill(sub_skill)
                    all_violations.extend(violations)
            report_results(all_violations, skill_path)
            return 1 if all_violations else 0

        print(f"Warning: No SKILL.md found in {skill_path}", file=sys.stderr)
        print("         Scanning all markdown files anyway...", file=sys.stderr)

    violations = scan_skill(skill_path)
    report_results(violations, skill_path)

    return 1 if violations else 0


if __name__ == "__main__":
    sys.exit(main())
