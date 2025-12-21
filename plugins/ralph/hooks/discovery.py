"""File discovery and work opportunity scanning for Ralph hook.

ADR: 2025-12-20-ralph-rssi-eternal-loop

Provides the file discovery cascade and RSSI work opportunity scanning
for the RSSI autonomous exploration mode.
"""
import json
import logging
import re
from pathlib import Path

from completion import has_frontmatter_value

# RSSI modules
from rssi_discovery import rssi_scan_opportunities
from rssi_evolution import (
    get_disabled_checks,
    get_prioritized_checks,
    suggest_capability_expansion,
)
from rssi_history import get_recent_commits_for_analysis, mine_session_history
from rssi_knowledge import RSSIKnowledge
from rssi_meta import (
    analyze_discovery_effectiveness,
    get_meta_suggestions,
    improve_discovery_mechanism,
)
from rssi_web_discovery import get_quality_gate_instructions, web_search_for_ideas

logger = logging.getLogger(__name__)

# Work opportunity scanning constants
LYCHEE_TIMEOUT = 30
MAX_OPPORTUNITIES = 5

# Pattern to match plan mode system-reminder
# Claude injects: "You should create your plan at /path/to/plan.md"
PLAN_MODE_PATTERN = re.compile(r'create your plan at ([^\s"]+\.md)')


def discover_plan_mode_file(transcript_path: str) -> str | None:
    """Extract plan file from plan mode system-reminder.

    Plan mode injects: "You should create your plan at /path/to/plan.md"
    This takes priority over tool operations since it's the system-assigned file.

    Args:
        transcript_path: Path to the Claude transcript JSONL file

    Returns:
        Path to discovered plan file, or None. Returns the most recent match,
        filtering out placeholder patterns from code examples.
    """
    if not transcript_path or not Path(transcript_path).exists():
        return None

    try:
        content = Path(transcript_path).read_text()
        matches = PLAN_MODE_PATTERN.findall(content)

        # Filter out placeholder patterns from code examples
        real_files = [
            m for m in matches
            if not m.startswith("/path/")
            and "XXXX" not in m
            and m.startswith("/")  # Must be absolute path
        ]

        if real_files:
            logger.debug(f"Plan mode matches: {len(real_files)} real files found")
            return real_files[-1]  # Last match = current plan
    except OSError as e:
        logger.warning(f"Failed to read transcript for plan mode detection: {e}")
    return None


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
    0. Plan mode system-reminder (system-assigned plan file)
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
    # Priority 0: Plan mode system-assigned file (takes precedence)
    if transcript_path:
        plan_mode_file = discover_plan_mode_file(transcript_path)
        if plan_mode_file:
            logger.info(f"Discovered from plan mode: {plan_mode_file}")
            return (plan_mode_file, "plan_mode", [])

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
    """RSSI-grade opportunity scanning - orchestrates all RSSI levels.

    ADR: 2025-12-20-ralph-rssi-eternal-loop

    RSSI Levels:
    - Level 2: Dynamic Discovery (rssi_scan_opportunities)
    - Level 3: History Mining (mine_session_history)
    - Level 4: Self-Modification (improve_discovery_mechanism)
    - Level 5: Meta-RSSI (analyze_discovery_effectiveness)
    - Level 6: Web Discovery (web_search_for_ideas)

    NEVER returns empty - always finds something to improve.

    Args:
        project_dir: Path to project root

    Returns:
        List of opportunity descriptions. NEVER empty.
    """
    if not project_dir:
        # Even with no project, provide meta-opportunities
        return ["Set up a project directory for RSSI scanning"]

    project_path = Path(project_dir)
    opportunities: list[str] = []

    # Load accumulated knowledge
    knowledge = RSSIKnowledge.load()
    knowledge.increment_iteration()

    # Level 2: Dynamic Discovery
    disabled = get_disabled_checks()
    prioritized = get_prioritized_checks()
    level2_opportunities = rssi_scan_opportunities(
        project_path,
        disabled_checks=disabled,
        prioritized_checks=prioritized,
    )
    opportunities.extend(level2_opportunities)

    # Level 3: History Mining
    history_patterns = mine_session_history()
    knowledge.add_patterns(history_patterns)
    if history_patterns:
        opportunities.extend(history_patterns[:2])  # Top 2 patterns

    # Add commit-based suggestions
    commit_suggestions = get_recent_commits_for_analysis(project_path)
    opportunities.extend(commit_suggestions)

    # Level 4: Self-Modification
    improvements = improve_discovery_mechanism(project_path)
    knowledge.apply_improvements(improvements)
    # Log improvements but don't add to opportunities (internal)

    # Level 5: Meta-RSSI
    meta_analysis = analyze_discovery_effectiveness()
    knowledge.evolve(meta_analysis)
    meta_suggestions = get_meta_suggestions()
    if meta_suggestions:
        opportunities.extend(meta_suggestions[:2])  # Top 2 meta-suggestions

    # Check if we should suggest capability expansion
    capability_suggestions = suggest_capability_expansion(project_path)
    if capability_suggestions:
        opportunities.extend(capability_suggestions[:2])

    # Persist accumulated knowledge
    knowledge.persist()

    # SLO FILTER: Apply busywork filter for Alpha Forge projects
    # This catches opportunities added AFTER rssi_scan_opportunities()
    # (commit suggestions, meta suggestions, capability expansion, fallback)
    opportunities = _apply_alpha_forge_filter(opportunities, project_path)

    # GUARANTEE: Never return empty (RSSI Tier 7 fallback)
    # For Alpha Forge: Use value-aligned fallbacks, not busywork
    if not opportunities:
        if _is_alpha_forge_project(project_path):
            opportunities = [
                "Check ROADMAP.md for next P0/P1 item",
                "Search for SOTA approach to current ROADMAP priority",
                "Review research_log.md for unexplored directions",
            ]
        else:
            opportunities = [
                "Review recent git commits for documentation gaps",
                "Analyze test coverage for recently changed files",
                "Search for SOTA improvements in project domain",
            ]

    return opportunities


def _is_alpha_forge_project(project_dir: Path) -> bool:
    """Check if this is an Alpha Forge project (delegated to rssi_discovery)."""
    try:
        from rssi_discovery import _is_alpha_forge_project as check_alpha_forge
        return check_alpha_forge(project_dir)
    except ImportError:
        return False


def _apply_alpha_forge_filter(opportunities: list[str], project_dir: Path) -> list[str]:
    """Apply busywork filter for Alpha Forge projects."""
    if not _is_alpha_forge_project(project_dir):
        return opportunities

    try:
        from alpha_forge_filter import get_allowed_opportunities
        filtered = get_allowed_opportunities(opportunities)
        skipped = len(opportunities) - len(filtered)
        if skipped > 0:
            logger.debug(f"Alpha Forge SLO filter: removed {skipped} busywork items")
        return filtered
    except ImportError:
        logger.warning("alpha_forge_filter not available")
        return opportunities


def get_rssi_exploration_context(project_dir: str) -> dict:
    """Get full RSSI context for exploration mode template.

    Provides all data needed for the exploration-mode.md template.

    Args:
        project_dir: Path to project root

    Returns:
        Dict with opportunities, web_queries, missing_tools, quality_gate, etc.
    """
    project_path = Path(project_dir) if project_dir else None
    knowledge = RSSIKnowledge.load()

    context = {
        "opportunities": scan_work_opportunities(project_dir),
        "iteration": knowledge.iteration_count,
        "accumulated_patterns": list(knowledge.commit_patterns.keys()),
        "disabled_checks": knowledge.disabled_checks,
        "effective_checks": knowledge.effective_checks,
        "web_insights": knowledge.domain_insights,
        "feature_ideas": knowledge.feature_ideas,
        "overall_effectiveness": knowledge.overall_effectiveness,
        "web_queries": [],
        "missing_tools": [],
        "quality_gate": get_quality_gate_instructions(),
    }

    if project_path:
        # Level 6: Web Discovery queries
        web_suggestions = web_search_for_ideas(project_path)
        context["web_queries"] = [
            s.replace('- WebSearch: "', "").rstrip('"')
            for s in web_suggestions
            if s.startswith("- WebSearch:")
        ]

        # Capability expansion suggestions
        context["missing_tools"] = suggest_capability_expansion(project_path)

    return context
