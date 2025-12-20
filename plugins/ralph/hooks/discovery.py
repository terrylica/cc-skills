"""File discovery and work opportunity scanning for Ralph hook.

Provides the file discovery cascade and work opportunity scanning
for the RSSI autonomous exploration mode.
"""
import json
import logging
import subprocess
from pathlib import Path

from completion import has_frontmatter_value
from validation import ensure_validation_tool

logger = logging.getLogger(__name__)

# Work opportunity scanning constants
LYCHEE_TIMEOUT = 30
MAX_OPPORTUNITIES = 5


def has_itp_structure(project_dir: str) -> bool:
    """Check if project follows ITP conventions (has docs/adr and docs/design).

    Args:
        project_dir: Path to project root

    Returns:
        True if project has ITP directory structure
    """
    if not project_dir:
        return False
    adr_dir = Path(project_dir) / "docs/adr"
    design_dir = Path(project_dir) / "docs/design"
    return adr_dir.exists() and design_dir.exists()


def discover_from_transcript(transcript_path: str) -> str | None:
    """Extract plan file path from Write/Edit/Read tool operations on .claude/plans/ files.

    Searches the transcript backwards (most recent first) for tool operations
    on plan files.

    Args:
        transcript_path: Path to the Claude transcript JSONL file

    Returns:
        Path to discovered plan file, or None
    """
    if not transcript_path or not Path(transcript_path).exists():
        return None
    try:
        lines = Path(transcript_path).read_text().strip().split('\n')
        # Search backwards (most recent first)
        for line in reversed(lines):
            if not line.strip():
                continue
            try:
                entry = json.loads(line)
                # Check message.content[] for tool_use blocks
                content = entry.get("message", {}).get("content", [])
                if not isinstance(content, list):
                    continue
                for block in content:
                    if not isinstance(block, dict):
                        continue
                    if block.get("type") != "tool_use":
                        continue
                    # Check for Write, Edit, or Read operations
                    if block.get("name") not in ("Write", "Edit", "Read"):
                        continue
                    file_path = block.get("input", {}).get("file_path", "")
                    # Match .claude/plans/ files
                    if "/.claude/plans/" in file_path and file_path.endswith(".md"):
                        return file_path
            except json.JSONDecodeError:
                continue
    except OSError:
        pass
    return None


def find_in_progress_spec(project_dir: str) -> list[str]:
    """Find ITP design specs with implementation-status: in_progress.

    Args:
        project_dir: Path to project root

    Returns:
        List of spec file paths, sorted by mtime (newest first)
    """
    specs = []
    if not project_dir:
        return specs
    design_dir = Path(project_dir) / "docs/design"
    if not design_dir.exists():
        return specs

    for spec_path in design_dir.glob("*/spec.md"):
        try:
            content = spec_path.read_text()
            if has_frontmatter_value(content, "implementation-status", "in_progress"):
                specs.append(str(spec_path))
        except OSError:
            continue

    # Return sorted by mtime (newest first)
    if specs:
        specs.sort(key=lambda p: Path(p).stat().st_mtime, reverse=True)
    return specs


def find_accepted_adr(project_dir: str) -> list[str]:
    """Find ITP ADRs with status: accepted (not yet implemented).

    Args:
        project_dir: Path to project root

    Returns:
        List of ADR file paths, sorted by mtime (newest first)
    """
    adrs = []
    if not project_dir:
        return adrs
    adr_dir = Path(project_dir) / "docs/adr"
    if not adr_dir.exists():
        return adrs

    for adr_path in adr_dir.glob("*.md"):
        try:
            content = adr_path.read_text()
            # Check for status: accepted but not status: implemented
            if has_frontmatter_value(content, "status", "accepted"):
                # Also check it's not implemented
                if not has_frontmatter_value(content, "status", "implemented"):
                    adrs.append(str(adr_path))
        except OSError:
            continue

    if adrs:
        adrs.sort(key=lambda p: Path(p).stat().st_mtime, reverse=True)
    return adrs


def find_newest_plan(plans_dir: Path) -> Path | None:
    """Find newest .md file in plans directory by modification time.

    Args:
        plans_dir: Path to plans directory

    Returns:
        Path to newest plan file, or None
    """
    if not plans_dir.exists():
        return None
    candidates = []
    for md_file in plans_dir.glob("*.md"):
        # Skip agent conversation snapshots
        if "-agent-" in md_file.name:
            continue
        candidates.append(md_file)

    if candidates:
        return max(candidates, key=lambda p: p.stat().st_mtime)
    return None


def find_matching_global_plan(plans_dir: Path, project_dir: str) -> list[str]:
    """Find global plans that reference the current project.

    Args:
        plans_dir: Path to global plans directory
        project_dir: Path to current project

    Returns:
        List of matching plan file paths
    """
    if not plans_dir.exists() or not project_dir:
        return []
    project_name = Path(project_dir).name
    matches = []

    for md_file in plans_dir.glob("*.md"):
        if "-agent-" in md_file.name:
            continue
        try:
            content = md_file.read_text()
            # Check if plan mentions this project
            if project_name in content or project_dir in content:
                matches.append(str(md_file))
        except OSError:
            continue

    if matches:
        matches.sort(key=lambda p: Path(p).stat().st_mtime, reverse=True)
    return matches


def format_candidate_list(candidates: list[str], file_type: str) -> str:
    """Format candidates for inclusion in continuation prompt.

    Args:
        candidates: List of file paths
        file_type: Type description for display

    Returns:
        Formatted string for prompt
    """
    lines = [f"\n**MULTIPLE {file_type.upper()} FILES** - Please examine and choose:"]
    for i, path in enumerate(candidates[:5], 1):
        lines.append(f"  {i}. {path}")
    return "\n".join(lines)


def discover_target_file(
    transcript_path: str | None,
    project_dir: str
) -> tuple[str | None, str, list[str]]:
    """Discover task file with priority cascade.

    Priority order:
    1. Transcript parsing (Write/Edit/Read to .claude/plans/)
    2. ITP design specs with implementation-status: in_progress
    3. ITP ADRs with status: accepted
    4. Local .claude/plans/ (newest)
    5. Global plans (content match)
    6. Global plans (most recent fallback)

    Args:
        transcript_path: Path to Claude transcript file
        project_dir: Path to project root

    Returns:
        (path, discovery_method, candidates) - path is None if multiple candidates
    """
    # Priority 1: Transcript parsing (Write/Edit/Read to .claude/plans/)
    if transcript_path:
        path = discover_from_transcript(transcript_path)
        if path:
            logger.info(f"Discovered from transcript: {path}")
            return (path, "transcript", [])

    # Priority 2-3: ITP (only if structure exists)
    if project_dir and has_itp_structure(project_dir):
        # Priority 2: Design specs with implementation-status: in_progress
        specs = find_in_progress_spec(project_dir)
        if len(specs) == 1:
            logger.info(f"Discovered ITP spec: {specs[0]}")
            return (specs[0], "itp_spec", [])
        elif len(specs) > 1:
            logger.info(f"Multiple ITP specs found: {specs}")
            return (None, "itp_spec", specs)

        # Priority 3: ADRs with status: accepted
        adrs = find_accepted_adr(project_dir)
        if len(adrs) == 1:
            logger.info(f"Discovered ITP ADR: {adrs[0]}")
            return (adrs[0], "itp_adr", [])
        elif len(adrs) > 1:
            logger.info(f"Multiple ITP ADRs found: {adrs}")
            return (None, "itp_adr", adrs)

    # Priority 4: Local .claude/plans/
    if project_dir:
        local_plans = Path(project_dir) / ".claude/plans"
        local_newest = find_newest_plan(local_plans)
        if local_newest:
            logger.info(f"Discovered local plan: {local_newest}")
            return (str(local_newest), "local_plan", [])

    # Priority 5: Global plans (content match)
    global_plans = Path.home() / ".claude/plans"
    if project_dir:
        global_matches = find_matching_global_plan(global_plans, project_dir)
        if len(global_matches) == 1:
            logger.info(f"Discovered global plan (content match): {global_matches[0]}")
            return (global_matches[0], "global_plan", [])
        elif len(global_matches) > 1:
            logger.info(f"Multiple global plans found: {global_matches}")
            return (None, "global_plan", global_matches[:5])

    # Priority 6: Global plans (most recent fallback)
    global_newest = find_newest_plan(global_plans)
    if global_newest:
        logger.info(f"Discovered global plan (newest): {global_newest}")
        return (str(global_newest), "global_plan_mtime", [])

    logger.info("No target file discovered")
    return (None, "none", [])


def scan_work_opportunities(project_dir: str) -> list[str]:
    """Dynamically discover improvement opportunities in the project.

    Checks:
    1. Broken links (via lychee if available)
    2. Directories with Python files but no README
    3. ADR gaps (features without ADRs)

    Args:
        project_dir: Path to project root

    Returns:
        List of opportunity descriptions (max 5)
    """
    if not project_dir:
        return []

    opportunities: list[str] = []
    project_path = Path(project_dir)

    # Check 1: Broken links (if lychee available)
    if ensure_validation_tool("lychee"):
        try:
            result = subprocess.run(
                ["lychee", "--no-progress", "-q", "--format", "json", "."],
                cwd=project_dir,
                capture_output=True,
                timeout=LYCHEE_TIMEOUT
            )
            if result.returncode != 0 and result.stdout:
                try:
                    data = json.loads(result.stdout)
                    broken = data.get("fail", [])
                    if broken:
                        opportunities.append(f"Fix {len(broken)} broken links")
                except json.JSONDecodeError:
                    pass
        except (subprocess.TimeoutExpired, OSError) as e:
            logger.warning(f"Lychee check failed: {e}")

    # Check 2: Directories with multiple Python files but no README
    checked_dirs: set[Path] = set()
    for py_file in project_path.rglob("*.py"):
        parent = py_file.parent
        if parent in checked_dirs:
            continue
        checked_dirs.add(parent)

        # Skip common non-source directories
        if any(skip in parent.parts for skip in ["__pycache__", ".git", "node_modules", ".venv", "venv"]):
            continue

        readme = parent / "README.md"
        if not readme.exists():
            py_files = list(parent.glob("*.py"))
            if len(py_files) > 3:
                rel_path = parent.relative_to(project_path) if parent != project_path else Path(".")
                opportunities.append(f"Add README to {rel_path}")

    # Check 3: Look for ADR gaps (if ITP structure exists)
    adr_dir = project_path / "docs/adr"
    if adr_dir.exists():
        # Count ADRs
        adr_count = len(list(adr_dir.glob("*.md")))
        # Check for common features that might need ADRs
        if (project_path / "plugins").exists() and adr_count < 3:
            opportunities.append("Consider adding ADRs for plugin architecture decisions")

    # Cap at MAX_OPPORTUNITIES to avoid overwhelming
    return opportunities[:MAX_OPPORTUNITIES]
