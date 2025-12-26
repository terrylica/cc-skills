# /// script
# requires-python = ">=3.11"
# dependencies = ["pyyaml>=6.0"]
# ///
"""Comprehensive skill validator with interactive clarification.

Validates skills against skill-architecture standards:
- YAML frontmatter (name, description, allowed-tools)
- Description format (TRIGGERS, length, triggers)
- S1/S2/S3 conformance standards
- Link portability
- Bash compatibility

Usage:
    uv run validate_skill.py <path> [--fix] [--interactive]

Options:
    --fix          Show fix suggestions
    --interactive  Prompt for clarification on ambiguities (AskUserQuestion style)

Exit codes:
    0 = All validations passed
    1 = Violations found
    2 = Error (invalid path, no SKILL.md)
"""

import sys
import re
import json
from pathlib import Path
from dataclasses import dataclass, field

try:
    import yaml
except ImportError:
    print("Error: pyyaml required. Run: uv run validate_skill.py")
    sys.exit(2)


@dataclass
class ValidationResult:
    """Result of a single validation check."""
    check: str
    passed: bool
    message: str
    severity: str = "error"  # error, warning, info
    fix_suggestion: str | None = None
    needs_clarification: bool = False
    clarification_question: str | None = None
    clarification_options: list[str] | None = None


@dataclass
class SkillValidation:
    """Complete validation results for a skill."""
    skill_path: Path
    skill_name: str = ""
    results: list[ValidationResult] = field(default_factory=list)

    @property
    def passed(self) -> bool:
        return all(r.passed for r in self.results if r.severity == "error")

    @property
    def errors(self) -> list[ValidationResult]:
        return [r for r in self.results if not r.passed and r.severity == "error"]

    @property
    def warnings(self) -> list[ValidationResult]:
        return [r for r in self.results if not r.passed and r.severity == "warning"]

    @property
    def needs_clarification(self) -> list[ValidationResult]:
        return [r for r in self.results if r.needs_clarification]


def parse_yaml_frontmatter(content: str) -> tuple[dict | None, str]:
    """Extract YAML frontmatter from markdown content."""
    if not content.startswith("---"):
        return None, "No YAML frontmatter found (must start with ---)"

    parts = content.split("---", 2)
    if len(parts) < 3:
        return None, "Invalid YAML frontmatter (missing closing ---)"

    try:
        frontmatter = yaml.safe_load(parts[1])
        return frontmatter, ""
    except yaml.YAMLError as e:
        return None, f"Invalid YAML syntax: {e}"


def validate_frontmatter(frontmatter: dict | None, error_msg: str) -> list[ValidationResult]:
    """Validate YAML frontmatter fields."""
    results = []

    if frontmatter is None:
        results.append(ValidationResult(
            check="yaml_frontmatter",
            passed=False,
            message=error_msg,
            severity="error",
            fix_suggestion="Add YAML frontmatter:\n---\nname: skill-name\ndescription: ...\n---"
        ))
        return results

    # Check 'name' field
    name = frontmatter.get("name")
    if not name:
        results.append(ValidationResult(
            check="yaml_name",
            passed=False,
            message="Missing 'name' field in frontmatter",
            severity="error",
            fix_suggestion="Add: name: your-skill-name"
        ))
    elif not re.match(r'^[a-z][a-z0-9-]*$', name):
        results.append(ValidationResult(
            check="yaml_name_format",
            passed=False,
            message=f"Invalid name format: '{name}' (must be lowercase-hyphen)",
            severity="error",
            fix_suggestion=f"Use: name: {name.lower().replace('_', '-').replace(' ', '-')}"
        ))
    else:
        results.append(ValidationResult(
            check="yaml_name",
            passed=True,
            message=f"Name valid: {name}"
        ))

    # Check 'description' field
    desc = frontmatter.get("description", "")
    if not desc:
        results.append(ValidationResult(
            check="yaml_description",
            passed=False,
            message="Missing 'description' field in frontmatter",
            severity="error",
            fix_suggestion="Add: description: What this skill does. TRIGGERS - keyword1, keyword2."
        ))
    else:
        # Check description length (S3 standard)
        if len(desc) > 200:
            results.append(ValidationResult(
                check="description_length",
                passed=False,
                message=f"Description too long: {len(desc)} chars (max 200)",
                severity="warning",
                fix_suggestion=f"Trim to under 200 chars. Current: {len(desc)}",
                needs_clarification=True,
                clarification_question="Description exceeds 200 chars. How should we handle this?",
                clarification_options=[
                    "Trim description (recommended)",
                    "Keep as-is (acceptable if skill is complex)",
                    "I'll manually edit"
                ]
            ))
        else:
            results.append(ValidationResult(
                check="description_length",
                passed=True,
                message=f"Description length OK: {len(desc)} chars"
            ))

        # Check for TRIGGERS keyword
        if "TRIGGERS" not in desc.upper():
            results.append(ValidationResult(
                check="description_triggers",
                passed=False,
                message="Description missing TRIGGERS keyword",
                severity="warning",
                fix_suggestion="Add 'TRIGGERS - keyword1, keyword2, keyword3' to description",
                needs_clarification=True,
                clarification_question="What keywords should trigger this skill?",
                clarification_options=[
                    "I'll provide trigger keywords",
                    "Infer from skill content",
                    "Skip (not recommended)"
                ]
            ))
        else:
            results.append(ValidationResult(
                check="description_triggers",
                passed=True,
                message="TRIGGERS keyword present"
            ))

    # Check 'allowed-tools' field
    allowed_tools = frontmatter.get("allowed-tools")
    if not allowed_tools:
        results.append(ValidationResult(
            check="allowed_tools",
            passed=False,
            message="Missing 'allowed-tools' security restriction",
            severity="warning",
            fix_suggestion="Add: allowed-tools: Read, Bash, Glob, Grep",
            needs_clarification=True,
            clarification_question="What tools does this skill need? (security best practice)",
            clarification_options=[
                "Read, Bash, Glob, Grep (standard)",
                "Read, Bash, Glob, Grep, Edit, Write (file modification)",
                "Read, Bash, Glob, Grep, AskUserQuestion (interactive)",
                "I'll specify custom tools"
            ]
        ))
    else:
        results.append(ValidationResult(
            check="allowed_tools",
            passed=True,
            message=f"allowed-tools defined: {allowed_tools}"
        ))

    return results


def validate_structure(skill_path: Path) -> list[ValidationResult]:
    """Validate skill directory structure."""
    results = []
    skill_md = skill_path / "SKILL.md"

    if not skill_md.exists():
        results.append(ValidationResult(
            check="skill_md_exists",
            passed=False,
            message="SKILL.md not found",
            severity="error"
        ))
        return results

    results.append(ValidationResult(
        check="skill_md_exists",
        passed=True,
        message="SKILL.md found"
    ))

    # Count lines (S1 standard)
    content = skill_md.read_text()
    line_count = len(content.splitlines())
    has_refs = (skill_path / "references").exists()

    if line_count > 200:
        if has_refs:
            results.append(ValidationResult(
                check="s1_line_count",
                passed=True,
                message=f"Line count: {line_count} (>200 but has references/)"
            ))
        else:
            results.append(ValidationResult(
                check="s1_line_count",
                passed=False,
                message=f"Line count: {line_count} (>200, no references/)",
                severity="warning",
                fix_suggestion="Either trim SKILL.md or add references/ for overflow content",
                needs_clarification=True,
                clarification_question=f"SKILL.md has {line_count} lines (recommended max 200). How to handle?",
                clarification_options=[
                    "Create references/ directory for detailed content (recommended)",
                    "Trim content",
                    "Keep as-is (acceptable for comprehensive skills)"
                ]
            ))
    else:
        results.append(ValidationResult(
            check="s1_line_count",
            passed=True,
            message=f"Line count OK: {line_count}"
        ))

    # S2: Progressive disclosure
    if line_count > 200 and has_refs:
        ref_count = len(list((skill_path / "references").glob("*.md")))
        results.append(ValidationResult(
            check="s2_progressive_disclosure",
            passed=True,
            message=f"Progressive disclosure: {ref_count} reference files"
        ))
    elif line_count <= 200:
        results.append(ValidationResult(
            check="s2_progressive_disclosure",
            passed=True,
            message="Progressive disclosure: N/A (under 200 lines)"
        ))

    return results


def validate_links(skill_path: Path) -> list[ValidationResult]:
    """Validate markdown links use appropriate path formats.

    Link conventions for marketplace plugins:
    - Skill-internal files (references/, scripts/): Use ./  or ../ relative paths
    - Repo files NOT part of skill (ADRs, design specs): Use /docs/... repo-relative
    - External resources: Use https://... URLs
    """
    results = []

    # Check all markdown files
    md_files = list(skill_path.glob("**/*.md"))
    if not md_files:
        return results

    # Allowed repo-relative paths (files not part of skill bundle)
    allowed_repo_paths = ["/docs/"]

    bad_absolute_links = 0
    bad_github_urls = 0

    for md_file in md_files:
        content = md_file.read_text()

        # Remove code blocks before checking (links in examples are OK)
        content_no_code = re.sub(r'```.*?```', '', content, flags=re.DOTALL)
        # Remove inline code (backticks) - also examples
        content_no_code = re.sub(r'`[^`]+`', '', content_no_code)

        # Find all absolute links (starting with /)
        absolute_links = re.findall(r'\[[^\]]+\]\((/[^)]+)\)', content_no_code)
        for link in absolute_links:
            # Allow /docs/ paths (ADRs, design specs, etc.)
            if not any(link.startswith(allowed) for allowed in allowed_repo_paths):
                bad_absolute_links += 1

        # Find GitHub URLs pointing to this repo (should use relative or /docs/ instead)
        github_repo_urls = re.findall(
            r'\[[^\]]+\]\((https://github\.com/terrylica/cc-skills/blob/[^)]+)\)',
            content_no_code
        )
        bad_github_urls += len(github_repo_urls)

    errors = []

    if bad_absolute_links > 0:
        errors.append(f"{bad_absolute_links} absolute paths not in /docs/")

    if bad_github_urls > 0:
        errors.append(f"{bad_github_urls} GitHub URLs to this repo (use relative or /docs/)")

    if errors:
        results.append(ValidationResult(
            check="link_portability",
            passed=False,
            message=f"Found {', '.join(errors)}",
            severity="error",
            fix_suggestion="Skill files: use ./ or ../ | Repo docs: use /docs/... | External: use https://..."
        ))
    else:
        results.append(ValidationResult(
            check="link_portability",
            passed=True,
            message="All links use appropriate path formats"
        ))

    return results


def validate_bash_blocks(skill_path: Path) -> list[ValidationResult]:
    """Validate bash blocks have heredoc wrappers."""
    results = []

    # Check all markdown files
    md_files = list(skill_path.glob("**/*.md"))

    unwrapped_blocks = 0
    # Patterns that require heredoc wrapper for zsh compatibility
    # Use line-start anchors (^\s*) for keywords to avoid false positives in comments
    bash_specific_patterns = [
        (r'\$\(', 0),                    # Command substitution $(...)
        (r'\[\[', 0),                    # Bash conditional [[ ]]
        (r'^\s*declare\s', re.MULTILINE),  # Declare at line start
        (r'^\s*local\s', re.MULTILINE),    # Local at line start
        (r'^\s*function\s', re.MULTILINE), # Function at line start
    ]

    for md_file in md_files:
        content = md_file.read_text()

        # Find bash code blocks
        blocks = re.findall(r'```bash\n(.*?)```', content, re.DOTALL)

        for block in blocks:
            # Check if block has bash-specific syntax
            has_bash_syntax = any(
                re.search(pattern, block, flags) if flags else re.search(pattern, block)
                for pattern, flags in bash_specific_patterns
            )
            has_heredoc = '/usr/bin/env bash' in block

            if has_bash_syntax and not has_heredoc:
                unwrapped_blocks += 1

    if unwrapped_blocks > 0:
        results.append(ValidationResult(
            check="bash_compatibility",
            passed=False,
            message=f"Found {unwrapped_blocks} bash blocks without heredoc wrapper",
            severity="error",
            fix_suggestion="Wrap with: /usr/bin/env bash << 'EOF'\n...\nEOF"
        ))
    else:
        results.append(ValidationResult(
            check="bash_compatibility",
            passed=True,
            message="All bash blocks are zsh-compatible"
        ))

    return results


def validate_skill(skill_path: Path) -> SkillValidation:
    """Run all validations on a skill."""
    validation = SkillValidation(skill_path=skill_path)

    skill_md = skill_path / "SKILL.md"
    if not skill_md.exists():
        validation.results.append(ValidationResult(
            check="skill_exists",
            passed=False,
            message=f"SKILL.md not found at {skill_path}",
            severity="error"
        ))
        return validation

    content = skill_md.read_text()
    frontmatter, error = parse_yaml_frontmatter(content)

    if frontmatter:
        validation.skill_name = frontmatter.get("name", "unknown")

    # Run all validations
    validation.results.extend(validate_frontmatter(frontmatter, error))
    validation.results.extend(validate_structure(skill_path))
    validation.results.extend(validate_links(skill_path))
    validation.results.extend(validate_bash_blocks(skill_path))

    return validation


def print_results(validation: SkillValidation, show_fix: bool = False):
    """Print validation results."""
    print(f"\n{'=' * 60}")
    print(f"Skill: {validation.skill_name or validation.skill_path}")
    print(f"{'=' * 60}\n")

    # Group by status
    passed = [r for r in validation.results if r.passed]
    errors = validation.errors
    warnings = validation.warnings

    if passed:
        print("✅ PASSED:")
        for r in passed:
            print(f"   {r.check}: {r.message}")
        print()

    if warnings:
        print("⚠️  WARNINGS:")
        for r in warnings:
            print(f"   {r.check}: {r.message}")
            if show_fix and r.fix_suggestion:
                print(f"      Fix: {r.fix_suggestion}")
        print()

    if errors:
        print("❌ ERRORS:")
        for r in errors:
            print(f"   {r.check}: {r.message}")
            if show_fix and r.fix_suggestion:
                print(f"      Fix: {r.fix_suggestion}")
        print()

    # Summary
    total = len(validation.results)
    passed_count = len(passed)
    print(f"Summary: {passed_count}/{total} checks passed")

    if validation.passed:
        print("✅ Skill validation PASSED")
    else:
        print("❌ Skill validation FAILED")

    # Show clarification needs
    clarifications = validation.needs_clarification
    if clarifications:
        print(f"\n📋 {len(clarifications)} items need clarification:")
        for r in clarifications:
            print(f"\n   Question: {r.clarification_question}")
            if r.clarification_options:
                for i, opt in enumerate(r.clarification_options, 1):
                    print(f"      {i}. {opt}")


def print_interactive_questions(validation: SkillValidation):
    """Print AskUserQuestion-style JSON for clarifications."""
    clarifications = validation.needs_clarification

    if not clarifications:
        return

    print("\n" + "=" * 60)
    print("INTERACTIVE CLARIFICATION (AskUserQuestion format)")
    print("=" * 60)

    questions = []
    for r in clarifications:
        if r.clarification_question and r.clarification_options:
            questions.append({
                "question": r.clarification_question,
                "header": r.check.replace("_", " ").title()[:12],
                "options": [
                    {"label": opt.split(" (")[0], "description": opt}
                    for opt in r.clarification_options
                ],
                "multiSelect": False
            })

    print("\nAskUserQuestion tool call:")
    print(json.dumps({"questions": questions}, indent=2))


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(2)

    path = Path(sys.argv[1]).resolve()
    show_fix = "--fix" in sys.argv
    interactive = "--interactive" in sys.argv

    if not path.exists():
        print(f"Error: Path not found: {path}")
        sys.exit(2)

    # Determine skill path
    if path.is_file() and path.name == "SKILL.md":
        skill_path = path.parent
    elif (path / "SKILL.md").exists():
        skill_path = path
    elif (path / "skills").exists():
        # Plugin directory - validate all skills
        skills = list(path.glob("skills/*/SKILL.md"))
        if not skills:
            print(f"No skills found in {path}/skills/")
            sys.exit(2)

        all_passed = True
        for skill_md in skills:
            validation = validate_skill(skill_md.parent)
            print_results(validation, show_fix)
            if interactive:
                print_interactive_questions(validation)
            if not validation.passed:
                all_passed = False

        sys.exit(0 if all_passed else 1)
    else:
        print(f"Error: No SKILL.md found at {path}")
        sys.exit(2)

    validation = validate_skill(skill_path)
    print_results(validation, show_fix)

    if interactive:
        print_interactive_questions(validation)

    sys.exit(0 if validation.passed else 1)


if __name__ == "__main__":
    main()
