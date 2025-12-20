"""
RSSI Knowledge: State Persistence for Eternal Loop

ADR: 2025-12-20-ralph-rssi-eternal-loop

Accumulates knowledge across eternal loop iterations.
Persists to JSON for cross-session learning.
"""

from __future__ import annotations

import json
from dataclasses import dataclass, field
from datetime import datetime
from pathlib import Path

KNOWLEDGE_FILE = Path.home() / ".claude/automation/loop-orchestrator/state/rssi-knowledge.json"


@dataclass
class RSSIKnowledge:
    """Accumulated knowledge across eternal loop iterations."""

    # Level 3: Learned patterns
    commit_patterns: dict[str, int] = field(default_factory=dict)  # pattern -> frequency
    effective_checks: list[str] = field(default_factory=list)  # ordered by effectiveness

    # Level 4: Evolution state
    disabled_checks: list[str] = field(default_factory=list)  # checks that proved ineffective
    proposed_checks: list[dict] = field(default_factory=list)  # new checks to try
    learned_conventions: dict = field(default_factory=dict)  # project-specific patterns

    # Level 5: Meta-learnings
    overall_effectiveness: float = 0.0  # how well is discovery working
    improvement_history: list[dict] = field(default_factory=list)  # what meta-changes were made

    # Level 6: Web knowledge
    domain_insights: list[str] = field(default_factory=list)  # learned from web searches
    sota_standards: dict = field(default_factory=dict)  # current SOTA for this domain
    feature_ideas: list[dict] = field(default_factory=list)  # big features to consider

    # Loop tracking
    iteration_count: int = 0
    last_updated: str = ""

    def persist(self) -> None:
        """Save to ~/.claude/automation/loop-orchestrator/state/rssi-knowledge.json."""
        self.last_updated = datetime.now().isoformat()
        KNOWLEDGE_FILE.parent.mkdir(parents=True, exist_ok=True)

        data = {
            "commit_patterns": self.commit_patterns,
            "effective_checks": self.effective_checks,
            "disabled_checks": self.disabled_checks,
            "proposed_checks": self.proposed_checks,
            "learned_conventions": self.learned_conventions,
            "overall_effectiveness": self.overall_effectiveness,
            "improvement_history": self.improvement_history,
            "domain_insights": self.domain_insights,
            "sota_standards": self.sota_standards,
            "feature_ideas": self.feature_ideas,
            "iteration_count": self.iteration_count,
            "last_updated": self.last_updated,
        }

        KNOWLEDGE_FILE.write_text(json.dumps(data, indent=2))

    @classmethod
    def load(cls) -> RSSIKnowledge:
        """Load accumulated knowledge from previous sessions."""
        if not KNOWLEDGE_FILE.exists():
            return cls()

        try:
            data = json.loads(KNOWLEDGE_FILE.read_text())
            return cls(
                commit_patterns=data.get("commit_patterns", {}),
                effective_checks=data.get("effective_checks", []),
                disabled_checks=data.get("disabled_checks", []),
                proposed_checks=data.get("proposed_checks", []),
                learned_conventions=data.get("learned_conventions", {}),
                overall_effectiveness=data.get("overall_effectiveness", 0.0),
                improvement_history=data.get("improvement_history", []),
                domain_insights=data.get("domain_insights", []),
                sota_standards=data.get("sota_standards", {}),
                feature_ideas=data.get("feature_ideas", []),
                iteration_count=data.get("iteration_count", 0),
                last_updated=data.get("last_updated", ""),
            )
        except (json.JSONDecodeError, OSError):
            return cls()

    def add_patterns(self, patterns: list[str]) -> None:
        """
        Add learned patterns from history mining.

        Args:
            patterns: List of pattern strings to add.
        """
        for pattern in patterns:
            # Extract pattern name if formatted as "High-value pattern (Nx): name"
            if ":" in pattern:
                name = pattern.split(":")[-1].strip()
            else:
                name = pattern

            self.commit_patterns[name] = self.commit_patterns.get(name, 0) + 1

    def apply_improvements(self, improvements: list[str]) -> None:
        """
        Record improvements made to discovery mechanism.

        Args:
            improvements: List of improvement descriptions.
        """
        for improvement in improvements:
            self.improvement_history.append({
                "description": improvement,
                "timestamp": datetime.now().isoformat(),
                "iteration": self.iteration_count,
            })

    def evolve(self, meta_analysis: dict) -> None:
        """
        Apply meta-analysis results to evolve knowledge.

        Args:
            meta_analysis: Dict with effectiveness metrics and recommendations.
        """
        if "overall_effectiveness" in meta_analysis:
            self.overall_effectiveness = meta_analysis["overall_effectiveness"]

        # Record recommendations as insights
        for rec in meta_analysis.get("recommendations", []):
            if rec not in self.domain_insights:
                self.domain_insights.append(rec)

    def add_feature_idea(self, idea: str, source: str, priority: str = "medium") -> None:
        """
        Add a big feature idea from web discovery.

        Args:
            idea: Feature idea description.
            source: Where the idea came from (e.g., search query).
            priority: Priority level (low, medium, high).
        """
        self.feature_ideas.append({
            "idea": idea,
            "source": source,
            "priority": priority,
            "added_at": datetime.now().isoformat(),
            "status": "proposed",
        })

    def add_sota_standard(self, domain: str, standard: str) -> None:
        """
        Record a SOTA standard for a domain.

        Args:
            domain: Domain area (e.g., "cli", "http", "testing").
            standard: The SOTA approach (e.g., "typer", "httpx", "pytest").
        """
        self.sota_standards[domain] = {
            "standard": standard,
            "recorded_at": datetime.now().isoformat(),
        }

    def increment_iteration(self) -> int:
        """
        Increment and return the iteration count.

        Returns:
            The new iteration count.
        """
        self.iteration_count += 1
        return self.iteration_count

    def get_summary(self) -> dict:
        """
        Get a summary of accumulated knowledge for template rendering.

        Returns:
            Dict with counts and key metrics.
        """
        return {
            "iteration": self.iteration_count,
            "pattern_count": len(self.commit_patterns),
            "effective_check_count": len(self.effective_checks),
            "disabled_check_count": len(self.disabled_checks),
            "insight_count": len(self.domain_insights),
            "feature_idea_count": len(self.feature_ideas),
            "overall_effectiveness": self.overall_effectiveness,
            "last_updated": self.last_updated,
        }
