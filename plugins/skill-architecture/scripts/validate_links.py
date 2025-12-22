#!/usr/bin/env python3
# /// script
# requires-python = ">=3.11"
# dependencies = []
# ///
"""
Skill Link & Bash Compatibility Validator
==========================================

Validates markdown links and bash code blocks in Claude Code skills.

**Link Validation**:
Absolute repo paths like `/skills/foo/SKILL.md` break when plugins are
installed outside the original repository structure. Skills MUST use
relative paths (`./`, `../`) that work in any installation location.

**Bash Validation**:
Claude Code's Bash tool on macOS runs through zsh. Bash-specific syntax
fails without heredoc wrappers. All bash code blocks MUST use:
  /usr/bin/env bash << 'NAME_EOF'

Usage:
    uv run validate_links.py <skill-path>
    uv run validate_links.py ~/.claude/skills/my-skill/
    uv run validate_links.py .  # Current directory

Exit Codes:
    0 = All validations passed
    1 = Violations found (links or bash issues)
    2 = Error (invalid path, no markdown files)
"""

import re
import sys
from dataclasses import dataclass
from pathlib import Path


@dataclass
class LinkViolation:
    """Represents a link portability violation."""
    file_path: Path
    line_number: int
    link_text: str
    link_url: str


@dataclass
class BashViolation:
    """Represents a bash compatibility violation."""
    file_path: Path
    line_number: int
    issue: str
    severity: str  # 'error' or 'warning'


# Regex patterns for link validation
MARKDOWN_LINK_PATTERN = re.compile(r'\[([^\]]+)\]\(([^)]+)\)')
ABSOLUTE_REPO_PATH_PATTERN = re.compile(r'^/(?!/)(?!https?:)(?!#)')
CODE_BLOCK_PATTERN = re.compile(r'```[\s\S]*?```')

# Regex patterns for bash validation
BASH_CODE_BLOCK_PATTERN = re.compile(r'```bash\n(.*?)```', re.DOTALL)
HEREDOC_WRAPPER_PATTERN = re.compile(r'^/usr/bin/env\s+bash\s*<<\s*[\'"]?\w+[\'"]?', re.MULTILINE)
INLINE_SUBSTITUTION = re.compile(r'\$\([^)]+\)')  # $(command)
ASSOCIATIVE_ARRAY = re.compile(r'declare\s+-A')
PERL_REGEX = re.compile(r'grep\s+[^|]*-[a-zA-Z]*P')
BASH_CONDITIONALS = re.compile(r'\[\[.*\]\]')


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


def validate_bash_blocks(file_path: Path) -> list[BashViolation]:
    """Check bash code blocks for portability issues."""
    violations = []

    try:
        content = file_path.read_text(encoding='utf-8')
    except Exception as e:
        print(f"Warning: Could not read {file_path}: {e}", file=sys.stderr)
        return violations

    for match in BASH_CODE_BLOCK_PATTERN.finditer(content):
        block = match.group(1)
        # Calculate line number from content position
        start_line = content[:match.start()].count('\n') + 1

        # Check for heredoc wrapper
        has_heredoc = bool(HEREDOC_WRAPPER_PATTERN.search(block))

        # Check if block contains bash-specific patterns that need heredoc
        has_substitution = bool(INLINE_SUBSTITUTION.search(block))
        has_conditionals = bool(BASH_CONDITIONALS.search(block))
        has_associative = bool(ASSOCIATIVE_ARRAY.search(block))
        has_perl_regex = bool(PERL_REGEX.search(block))

        # Needs heredoc if it has bash-specific patterns
        needs_heredoc = has_substitution or has_conditionals or has_associative

        if needs_heredoc and not has_heredoc:
            violations.append(BashViolation(
                file_path=file_path,
                line_number=start_line,
                issue='Bash block without /usr/bin/env bash heredoc wrapper',
                severity='error'
            ))

        # Check for prohibited patterns
        # Skip blocks that are documentation examples (contain "WRONG" markers)
        is_doc_example = '# ❌ WRONG' in block or '❌ WRONG' in block

        # declare -A is OK inside heredoc wrapper (that's the whole point of the wrapper)
        # Only flag if NOT wrapped AND not a doc example
        if has_associative and not has_heredoc and not is_doc_example:
            violations.append(BashViolation(
                file_path=file_path,
                line_number=start_line,
                issue='declare -A not portable (use parallel indexed arrays or wrap in heredoc)',
                severity='error'
            ))

        if has_perl_regex and not is_doc_example:
            violations.append(BashViolation(
                file_path=file_path,
                line_number=start_line,
                issue='grep -P not portable (use grep -E + awk)',
                severity='warning'
            ))

    return violations


def scan_skill(skill_path: Path) -> tuple[list[LinkViolation], list[BashViolation]]:
    """Scan all markdown files in a skill directory."""
    link_violations = []
    bash_violations = []

    # Find all markdown files
    md_files = list(skill_path.glob("**/*.md"))

    if not md_files:
        return link_violations, bash_violations

    for md_file in md_files:
        # Skip node_modules if present
        if 'node_modules' in md_file.parts:
            continue
        link_violations.extend(scan_file(md_file))
        bash_violations.extend(validate_bash_blocks(md_file))

    return link_violations, bash_violations


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


def report_results(
    link_violations: list[LinkViolation],
    bash_violations: list[BashViolation],
    skill_path: Path
) -> None:
    """Print validation results."""
    has_link_issues = bool(link_violations)
    has_bash_issues = bool(bash_violations)

    if not has_link_issues and not has_bash_issues:
        print(f"✅ Validation passed: {skill_path}")
        print("   All markdown links use relative paths (plugin-portable)")
        print("   All bash code blocks are zsh-compatible")
        return

    # Report link violations
    if has_link_issues:
        print(f"❌ Link validation FAILED: {skill_path}")
        print(f"   Found {len(link_violations)} absolute repo-path violation(s)")
        print()

        # Group by file
        by_file: dict[Path, list[LinkViolation]] = {}
        for v in link_violations:
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

    # Report bash violations
    if has_bash_issues:
        errors = [v for v in bash_violations if v.severity == 'error']
        warnings = [v for v in bash_violations if v.severity == 'warning']

        if errors:
            print(f"❌ Bash compatibility FAILED: {skill_path}")
            print(f"   Found {len(errors)} error(s), {len(warnings)} warning(s)")
        else:
            print(f"⚠️  Bash compatibility warnings: {skill_path}")
            print(f"   Found {len(warnings)} warning(s)")
        print()

        # Group by file
        by_file_bash: dict[Path, list[BashViolation]] = {}
        for v in bash_violations:
            by_file_bash.setdefault(v.file_path, []).append(v)

        for file_path, file_violations in sorted(by_file_bash.items()):
            try:
                rel_path = file_path.relative_to(skill_path)
            except ValueError:
                rel_path = file_path

            print(f"📄 {rel_path}")
            for v in file_violations:
                icon = "❌" if v.severity == 'error' else "⚠️"
                print(f"   {icon} Line {v.line_number}: {v.issue}")
            print()

        print("Why this matters:")
        print("  Claude Code's Bash tool runs through zsh on macOS.")
        print("  Bash-specific syntax fails without heredoc wrapper.")
        print("  Use: /usr/bin/env bash << 'NAME_EOF'")
        print("  See: plugins/skill-architecture/references/bash-compatibility.md")
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
            all_link_violations: list[LinkViolation] = []
            all_bash_violations: list[BashViolation] = []
            for sub_skill in skills_dir.iterdir():
                if sub_skill.is_dir() and (sub_skill / "SKILL.md").exists():
                    link_v, bash_v = scan_skill(sub_skill)
                    all_link_violations.extend(link_v)
                    all_bash_violations.extend(bash_v)
            report_results(all_link_violations, all_bash_violations, skill_path)
            # Return 1 only for errors, not warnings
            has_errors = bool(all_link_violations) or any(
                v.severity == 'error' for v in all_bash_violations
            )
            return 1 if has_errors else 0

        print(f"Warning: No SKILL.md found in {skill_path}", file=sys.stderr)
        print("         Scanning all markdown files anyway...", file=sys.stderr)

    link_violations, bash_violations = scan_skill(skill_path)
    report_results(link_violations, bash_violations, skill_path)

    # Return 1 only for errors, not warnings
    has_errors = bool(link_violations) or any(
        v.severity == 'error' for v in bash_violations
    )
    return 1 if has_errors else 0


if __name__ == "__main__":
    sys.exit(main())
