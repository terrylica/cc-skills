# Explore Agent Integration: Implementation Reference

## 1. Agent Output Format Specification

### Protocol Definition

Each Explore agent outputs **one constraint per line** in NDJSON format with this schema:

```python
# Agent Constraint Schema (canonical format)
{
    "agent_id": str,              # "env-scanner" | "config-discovery" | "integration-points"
    "constraint_id": str,         # Must be unique: "{agent_id}-{category}-{seq}"
                                  # Example: "agent-env-001", "agent-config-002"

    "severity": Literal[          # Ranked by impact on Ralph execution
        "critical",               # Block loop start, must fix before proceeding
        "high",                   # Escalate to user, recommend forbidding
        "medium",                 # Show in AUQ, optional action
        "low"                     # Informational only
    ],

    "category": str,              # Namespace for grouping
                                  # "dependency_conflict", "auth_missing", etc.

    "description": str,           # 60-char max, user-facing summary
                                  # Example: "Python 3.10 detected (3.11 required)"

    "source_file": str | None,    # Where discovered (e.g., "pyproject.toml", "runtime")
    "source_line": int,           # Line number in source_file (0 if N/A)

    "affected_scope": str,        # What Ralph function/phase this impacts
                                  # "python-runtime", "hook-registration", "auth-flow"

    "recommendation": str,        # Actionable fix (100 chars max)
                                  # Example: "Upgrade Python: brew install python@3.11"

    "resolution_steps": list[str], # Multi-step resolution guide (optional)
                                  # Max 3-5 steps, 40 chars each

    "tags": list[str],            # For filtering/learning ["runtime", "auth"]

    # Internal fields (added by aggregator)
    "_type": "constraint",        # For NDJSON parsing
    "confidence": float,          # 0.0-1.0 (1.0=scanner, 0.8=agent)
    "source": str,                # "scanner" | "{agent_id}" | "merged"
    "merged_with": list[str],     # If merged: other sources ["scanner"]
}
```

### Example Outputs

#### Agent 1: Environment Scanner

```json
{"agent_id":"env-scanner","constraint_id":"agent-env-001","severity":"high","category":"python_version","description":"Python 3.10 detected (3.11 required)","source_file":"runtime","source_line":0,"affected_scope":"python-runtime","recommendation":"Upgrade Python: brew install python@3.11 or pyenv local 3.11","resolution_steps":["python3 --version","brew install python@3.11","pyenv local 3.11"],"tags":["runtime","python","upgrade"],"_type":"constraint"}

{"agent_id":"env-scanner","constraint_id":"agent-env-002","severity":"medium","category":"uv_lock_state","description":"uv.lock out of date with pyproject.toml","source_file":"uv.lock","source_line":1,"affected_scope":"dependency-management","recommendation":"Regenerate lock file: uv lock --upgrade","resolution_steps":["cd /path/to/project","uv lock --upgrade","git add uv.lock"],"tags":["dependencies","uv","lock-file"],"_type":"constraint"}
```

#### Agent 2: Configuration Discovery

```json
{"agent_id":"config-discovery","constraint_id":"agent-config-001","severity":"medium","category":"missing_config","description":"Missing .claude/ralph-config.json (first run)","source_file":".claude/ralph-config.json","source_line":0,"affected_scope":"config-management","recommendation":"Will be created during /ralph:start setup","resolution_steps":[],"tags":["config","initialization"],"_type":"constraint"}

{"agent_id":"config-discovery","constraint_id":"agent-config-002","severity":"low","category":"hook_registration","description":"Non-Ralph hooks in ~/.claude/settings.json","source_file":"~/.claude/settings.json","source_line":0,"affected_scope":"hook-registration","recommendation":"Review for conflicts with Ralph PreToolUse hooks","tags":["hooks","compatibility"],"_type":"constraint"}
```

#### Agent 3: Integration Points

```json
{"agent_id":"integration-points","constraint_id":"agent-integ-001","severity":"medium","category":"auth_missing","description":"GitHub token not configured (git operations will fail)","source_file":"~/.config/gh/hosts.yml","source_line":0,"affected_scope":"git-operations","recommendation":"Authenticate: gh auth login","resolution_steps":["gh auth login","Select 'HTTPS' for protocol"],"tags":["auth","github","critical-path"],"_type":"constraint"}

{"agent_id":"integration-points","constraint_id":"agent-integ-002","severity":"low","category":"tool_missing","description":"lychee not in PATH (link checking will be skipped)","source_file":"$PATH","source_line":0,"affected_scope":"discovery","recommendation":"Install lychee: brew install lychee (optional)","tags":["discovery","optional"],"_type":"constraint"}
```

---

## 2. Aggregation Algorithm Implementation

### Core Aggregator Function

```python
#!/usr/bin/env python3
"""Aggregate constraint-scanner + agent findings into unified NDJSON.

Usage:
    python3 aggregate_constraints.py \
        --scanner-output .claude/ralph-constraint-scan.jsonl \
        --agent1-output .claude/.agent1-env.jsonl \
        --agent2-output .claude/.agent2-config.jsonl \
        --agent3-output .claude/.agent3-integration.jsonl \
        --output .claude/ralph-constraint-scan.jsonl
"""

from __future__ import annotations

import json
import sys
from pathlib import Path
from typing import Any
from dataclasses import dataclass, field


@dataclass
class AggregationStats:
    """Track aggregation results."""
    total_before: int = 0
    total_after: int = 0
    deduped: int = 0
    severity_counts: dict[str, int] = field(default_factory=lambda: {
        "critical": 0, "high": 0, "medium": 0, "low": 0
    })
    source_counts: dict[str, int] = field(default_factory=dict)


def severity_rank(severity: str) -> int:
    """Return sort rank for severity (lower = higher priority)."""
    return {"critical": 0, "high": 1, "medium": 2, "low": 3}.get(severity, 99)


def are_similar(c1: dict, c2: dict, threshold: float = 0.8) -> bool:
    """Check if two constraints are semantically similar.

    Similarity criteria:
    - Same category
    - Similar description (ignoring specific values)
    - Same source_file (if both set)
    """
    # Must have same category
    if c1.get("category") != c2.get("category"):
        return False

    # If both have source_file, must match
    if c1.get("source_file") and c2.get("source_file"):
        if c1["source_file"] != c2["source_file"]:
            return False

    # Description similarity (simple word overlap)
    desc1_words = set(c1.get("description", "").lower().split())
    desc2_words = set(c2.get("description", "").lower().split())

    if desc1_words and desc2_words:
        overlap = len(desc1_words & desc2_words) / max(len(desc1_words), len(desc2_words))
        return overlap >= threshold

    return False


def aggregate_constraints(
    scanner_output: Path,
    agent_outputs: list[Path],
    output_file: Path,
) -> AggregationStats:
    """Merge scanner + agent findings with deduplication.

    Returns: AggregationStats with counts and diagnostics
    """
    stats = AggregationStats()

    # Map constraint_id → constraint record
    constraints: dict[str, dict] = {}

    # Metadata from scanner (if exists)
    metadata = None

    # Busywork items (only from scanner, agents don't generate these)
    busywork_items: list[dict] = []

    # ===== PHASE 1: Load Scanner Results =====
    if scanner_output.exists():
        with open(scanner_output) as f:
            for line_num, line in enumerate(f, 1):
                if not line.strip():
                    continue

                try:
                    obj = json.loads(line)
                except json.JSONDecodeError as e:
                    print(f"[WARN] Scanner line {line_num}: Invalid JSON: {e}", file=sys.stderr)
                    continue

                obj_type = obj.get("_type")

                if obj_type == "metadata":
                    metadata = obj
                elif obj_type == "constraint":
                    constraint_id = obj.get("id")
                    if constraint_id:
                        constraints[constraint_id] = {
                            **obj,
                            "source": "scanner",
                            "confidence": 1.0,
                        }
                        stats.total_before += 1
                elif obj_type == "busywork":
                    busywork_items.append(obj)

    # ===== PHASE 2: Load Agent Results =====
    for agent_file in agent_outputs:
        if not agent_file.exists():
            continue

        with open(agent_file) as f:
            for line_num, line in enumerate(f, 1):
                if not line.strip():
                    continue

                try:
                    obj = json.loads(line)
                except json.JSONDecodeError as e:
                    print(f"[WARN] Agent {agent_file.name} line {line_num}: Invalid JSON: {e}", file=sys.stderr)
                    continue

                constraint_id = obj.get("constraint_id")
                if not constraint_id:
                    continue

                # Update stats
                agent_id = obj.get("agent_id", "unknown")
                stats.source_counts[agent_id] = stats.source_counts.get(agent_id, 0) + 1
                stats.total_before += 1

                # Check for exact ID match
                if constraint_id in constraints:
                    existing = constraints[constraint_id]

                    # Merge strategy: prefer higher severity
                    new_rank = severity_rank(obj["severity"])
                    old_rank = severity_rank(existing["severity"])

                    if new_rank < old_rank:
                        # New constraint has higher severity
                        merged = {
                            **obj,
                            "source": "merged",
                            "confidence": 0.9,
                            "merged_with": [existing.get("source", "unknown")],
                        }
                        constraints[constraint_id] = merged
                    else:
                        # Keep existing, note merge
                        existing["merged_with"] = existing.get("merged_with", [])
                        existing["merged_with"].append(agent_id)

                    stats.deduped += 1
                else:
                    # New constraint from agent
                    constraints[constraint_id] = {
                        **obj,
                        "source": agent_id,
                        "confidence": 0.8,  # Slightly lower than scanner
                    }

    # ===== PHASE 3: Sort and Write Output =====
    # Sort by severity (critical first), then by ID
    sorted_constraints = sorted(
        constraints.items(),
        key=lambda x: (severity_rank(x[1]["severity"]), x[0])
    )

    # Update metadata with aggregation info
    if metadata is None:
        metadata = {
            "_type": "metadata",
            "scan_timestamp": "2025-12-31T18:00:00Z",
            "project_dir": str(output_file.parent.parent),
            "worktree_type": "unknown",
            "error": None,
        }

    metadata["aggregation"] = {
        "total_before": stats.total_before,
        "total_after": len(constraints),
        "deduped": stats.deduped,
        "sources": list(stats.source_counts.keys()),
    }

    # Write output file
    with open(output_file, "w") as f:
        # Metadata line
        f.write(json.dumps(metadata, separators=(',', ':')) + '\n')

        # Constraint lines (sorted)
        for constraint_id, constraint in sorted_constraints:
            constraint["_type"] = "constraint"
            f.write(json.dumps(constraint, separators=(',', ':')) + '\n')
            stats.severity_counts[constraint["severity"]] += 1

        # Busywork lines
        for busywork in busywork_items:
            busywork["_type"] = "busywork"
            f.write(json.dumps(busywork, separators=(',', ':')) + '\n')

    stats.total_after = len(constraints)
    return stats


def main():
    """CLI entry point."""
    import argparse

    parser = argparse.ArgumentParser(description="Aggregate constraints from scanner + agents")
    parser.add_argument("--scanner-output", required=True, help="Scanner NDJSON file")
    parser.add_argument("--agent1-output", help="Agent 1 output (env-scanner)")
    parser.add_argument("--agent2-output", help="Agent 2 output (config-discovery)")
    parser.add_argument("--agent3-output", help="Agent 3 output (integration-points)")
    parser.add_argument("--output", required=True, help="Output NDJSON file")

    args = parser.parse_args()

    # Collect agent outputs
    agent_outputs = [
        Path(args.agent1_output) for args in [args] if args.agent1_output
    ] + [
        Path(args.agent2_output) for args in [args] if args.agent2_output
    ] + [
        Path(args.agent3_output) for args in [args] if args.agent3_output
    ]

    # Run aggregation
    stats = aggregate_constraints(
        Path(args.scanner_output),
        agent_outputs,
        Path(args.output),
    )

    # Print summary
    print("=== AGGREGATION SUMMARY ===")
    print(f"Total before: {stats.total_before}")
    print(f"Total after: {stats.total_after}")
    print(f"Deduped: {stats.deduped}")
    print(f"Severity: critical={stats.severity_counts['critical']} "
          f"high={stats.severity_counts['high']} "
          f"medium={stats.severity_counts['medium']} "
          f"low={stats.severity_counts['low']}")
    print(f"Sources: {stats.source_counts}")

    return 0


if __name__ == "__main__":
    sys.exit(main())
```

---

## 3. Agent 1: Environment Scanner

### Pseudo-Implementation

```python
#!/usr/bin/env python3
"""Agent 1: Environment/Dependency Scanner

Checks:
- Python version matches requirements
- uv.lock consistent with pyproject.toml
- Required dependencies for Ralph are installed
- Virtual environment state
"""

from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path


def run_command(cmd: list[str], timeout: int = 5) -> tuple[int, str, str]:
    """Execute command safely with timeout."""
    try:
        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=timeout,
        )
        return result.returncode, result.stdout, result.stderr
    except subprocess.TimeoutExpired:
        return 124, "", f"Command timed out after {timeout}s"
    except FileNotFoundError:
        return 127, "", f"Command not found: {cmd[0]}"


def emit_constraint(
    agent_id: str,
    seq: int,
    severity: str,
    category: str,
    description: str,
    source_file: str | None = None,
    source_line: int = 0,
    affected_scope: str = "",
    recommendation: str = "",
    resolution_steps: list[str] | None = None,
    tags: list[str] | None = None,
) -> None:
    """Output constraint in canonical NDJSON format."""
    constraint = {
        "agent_id": agent_id,
        "constraint_id": f"agent-{agent_id.split('-')[1]}-{seq:03d}",
        "severity": severity,
        "category": category,
        "description": description,
        "source_file": source_file or "runtime",
        "source_line": source_line,
        "affected_scope": affected_scope,
        "recommendation": recommendation,
        "resolution_steps": resolution_steps or [],
        "tags": tags or [],
    }
    print(json.dumps(constraint, separators=(',', ':')))


def check_python_version(project_dir: Path) -> None:
    """Check if Python version matches pyproject.toml requirement."""
    # Get current Python version
    code, stdout, stderr = run_command(
        ["python3", "-c", "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')"]
    )
    if code != 0:
        emit_constraint(
            agent_id="env-scanner",
            seq=1,
            severity="critical",
            category="python_missing",
            description="Python 3 not found in PATH",
            source_file=None,
            affected_scope="python-runtime",
            recommendation="Install Python 3.11+: brew install python@3.11",
            resolution_steps=["brew install python@3.11", "pyenv local 3.11"],
            tags=["runtime", "python", "critical"],
        )
        return

    current_version = stdout.strip()
    major, minor = map(int, current_version.split('.')[:2])

    # Check pyproject.toml for required version
    pyproject = project_dir / "pyproject.toml"
    if pyproject.exists():
        content = pyproject.read_text()
        # Simple regex for requires-python = ">=3.11"
        if "requires-python" in content:
            # Parse requirement
            if major < 3 or (major == 3 and minor < 11):
                emit_constraint(
                    agent_id="env-scanner",
                    seq=2,
                    severity="high",
                    category="python_version",
                    description=f"Python {current_version} detected (3.11+ required)",
                    source_file="pyproject.toml",
                    affected_scope="python-runtime",
                    recommendation="Upgrade Python: brew install python@3.11",
                    resolution_steps=[
                        "python3 --version",
                        "brew install python@3.11",
                        "pyenv local 3.11",
                    ],
                    tags=["runtime", "python", "upgrade"],
                )


def check_uv_lock_state(project_dir: Path) -> None:
    """Check if uv.lock is out of date with pyproject.toml."""
    uv_lock = project_dir / "uv.lock"
    pyproject = project_dir / "pyproject.toml"

    if not uv_lock.exists() or not pyproject.exists():
        return

    # Compare mtimes (simple heuristic)
    lock_mtime = uv_lock.stat().st_mtime
    project_mtime = pyproject.stat().st_mtime

    if project_mtime > lock_mtime:
        emit_constraint(
            agent_id="env-scanner",
            seq=3,
            severity="medium",
            category="uv_lock_state",
            description="uv.lock out of date with pyproject.toml",
            source_file="uv.lock",
            affected_scope="dependency-management",
            recommendation="Regenerate lock file: uv lock --upgrade",
            resolution_steps=[
                "cd " + str(project_dir),
                "uv lock --upgrade",
                "git add uv.lock",
            ],
            tags=["dependencies", "uv", "lock-file"],
        )


def main():
    """Main entry point."""
    project_dir = Path(sys.argv[1]) if len(sys.argv) > 1 else Path.cwd()

    # Run checks
    check_python_version(project_dir)
    check_uv_lock_state(project_dir)

    # Always succeed (no CRITICAL blockers at agent level)
    return 0


if __name__ == "__main__":
    sys.exit(main())
```

---

## 4. Bash Integration in start.md (Step 1.4.5)

### Updated bash script for /ralph:start

```bash
# Insert into start.md Step 1.4.5 (after constraint-scanner execution)

## Step 1.4.5: [NEW] Explore Agent Discovery (Parallel)

### Spawn Agents in Background

```bash
/usr/bin/env bash << 'EXPLORE_AGENTS_SCRIPT'
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
RALPH_CACHE="$HOME/.claude/plugins/cache/cc-skills/ralph"
AGENT_TIMEOUT=15  # Total timeout for all agents

# Determine script locations (prefer local, fallback to cache)
if [[ -d "$RALPH_CACHE/local" ]]; then
    SCRIPTS_DIR="$RALPH_CACHE/local/scripts"
else
    RALPH_VERSION=$(ls "$RALPH_CACHE" 2>/dev/null | grep -E '^[0-9]+\.[0-9]+\.[0-9]+$' | sort -V | tail -1)
    SCRIPTS_DIR="$RALPH_CACHE/$RALPH_VERSION/scripts"
fi

# Skip if scripts not found
if [[ ! -d "$SCRIPTS_DIR" ]]; then
    echo "Explore agents: SKIPPED (scripts not found)"
    exit 0
fi

# Discover UV
UV_CMD=""
if command -v uv &>/dev/null; then
    UV_CMD="uv"
elif [[ -x "$HOME/.local/bin/uv" ]]; then
    UV_CMD="$HOME/.local/bin/uv"
else
    echo "Explore agents: SKIPPED (uv not found)"
    exit 0
fi

echo "Spawning Explore agents (timeout: ${AGENT_TIMEOUT}s)..."

# Create temp directory for agent outputs
AGENT_DIR="$PROJECT_DIR/.claude/.agent-temp"
mkdir -p "$AGENT_DIR"
trap "rm -rf '$AGENT_DIR'" EXIT

# Start Agent 1: Environment Scanner (background)
echo "  Agent 1: Environment Scanner..."
$UV_CMD run -q "$SCRIPTS_DIR/agent_env_scanner.py" "$PROJECT_DIR" \
    > "$AGENT_DIR/agent1.jsonl" 2>"$AGENT_DIR/agent1.err" &
PID1=$!

# Start Agent 2: Configuration Discovery (background)
echo "  Agent 2: Configuration Discovery..."
$UV_CMD run -q "$SCRIPTS_DIR/agent_config_discovery.py" "$PROJECT_DIR" \
    > "$AGENT_DIR/agent2.jsonl" 2>"$AGENT_DIR/agent2.err" &
PID2=$!

# Start Agent 3: Integration Points (background)
echo "  Agent 3: Integration Points..."
$UV_CMD run -q "$SCRIPTS_DIR/agent_integration_points.py" "$PROJECT_DIR" \
    > "$AGENT_DIR/agent3.jsonl" 2>"$AGENT_DIR/agent3.err" &
PID3=$!

# Wait for agents with timeout
START_TIME=$(date +%s)
AGENT_EXIT=0
wait_with_timeout() {
    local pids="$1"
    local timeout="$2"
    local elapsed=0

    for i in $(seq 1 $timeout); do
        local any_running=false
        for pid in $pids; do
            if kill -0 "$pid" 2>/dev/null; then
                any_running=true
                break
            fi
        done

        if [[ "$any_running" == "false" ]]; then
            return 0
        fi
        sleep 1
    done

    # Timeout reached, kill remaining
    for pid in $pids; do
        kill -TERM "$pid" 2>/dev/null || true
    done
    return 124
}

wait_with_timeout "$PID1 $PID2 $PID3" $AGENT_TIMEOUT
AGENT_EXIT=$?

# Check individual agent completions
for i in 1 2 3; do
    AGENT_FILE="$AGENT_DIR/agent$i.jsonl"
    if [[ -f "$AGENT_FILE" && -s "$AGENT_FILE" ]]; then
        CONSTRAINT_COUNT=$(wc -l < "$AGENT_FILE")
        echo "  Agent $i complete: $CONSTRAINT_COUNT constraint(s)"
    elif [[ -f "$AGENT_DIR/agent$i.err" ]]; then
        ERROR_MSG=$(cat "$AGENT_DIR/agent$i.err" | head -1)
        echo "  Agent $i error: $ERROR_MSG"
    else
        echo "  Agent $i timeout (killed after ${AGENT_TIMEOUT}s)"
    fi
done

# Aggregate all findings
echo "Aggregating constraints..."
$UV_CMD run -q "$SCRIPTS_DIR/aggregate_constraints.py" \
    --scanner-output "$PROJECT_DIR/.claude/ralph-constraint-scan.jsonl" \
    --agent1-output "$AGENT_DIR/agent1.jsonl" \
    --agent2-output "$AGENT_DIR/agent2.jsonl" \
    --agent3-output "$AGENT_DIR/agent3.jsonl" \
    --output "$PROJECT_DIR/.claude/ralph-constraint-scan.jsonl"

if [[ $? -eq 0 ]]; then
    FINAL_COUNT=$(grep -c '"_type":"constraint"' "$PROJECT_DIR/.claude/ralph-constraint-scan.jsonl" 2>/dev/null || echo "0")
    echo "Aggregation complete: $FINAL_COUNT total constraints"
else
    echo "Aggregation failed, using scanner results only"
fi

EXPLORE_AGENTS_SCRIPT
```

---

## 5. Configuration Updates (config_schema.py)

### New Classes to Add

```python
# In /plugins/ralph/hooks/core/config_schema.py

class AgentConfig(BaseModel):
    """Configuration for a single Explore agent."""
    agent_id: str  # "env-scanner", "config-discovery", "integration-points"
    enabled: bool = True
    timeout_seconds: int = 15
    selection_rate: float = 0.0  # Populated by learning phase (0.0-1.0)

    model_config = ConfigDict(extra='ignore')


class ConstraintDiscoveryConfig(BaseModel):
    """Configuration for constraint discovery phase (v3.2.0+).

    Controls how Explore agents are executed and merged with scanner results.
    """
    enabled_agents: list[str] = Field(default_factory=lambda: [
        "env-scanner",
        "config-discovery",
        "integration-points"
    ])
    timeout_seconds: int = 15  # Total timeout for all agents
    skip_timeout_agents: bool = False  # If True, continue even if agent timeouts
    aggregate_similar: bool = True  # Merge similar constraints
    min_confidence_threshold: float = 0.6  # Minimum confidence to include
    agents: list[AgentConfig] = Field(default_factory=list)

    model_config = ConfigDict(extra='ignore')


# Update RalphConfig class to include:
class RalphConfig(BaseModel):
    # ... existing fields ...

    # NEW v3.2.0: Constraint discovery configuration
    constraint_discovery: ConstraintDiscoveryConfig = Field(
        default_factory=ConstraintDiscoveryConfig
    )

    # existing constraint_scan field (unchanged)
    constraint_scan: ConstraintScanConfig | None = None
```

---

## 6. Learning Behavior Tracking

### Global Agent Statistics

```python
# New file: ~/.claude/ralph-agent-config.json

{
  "version": "3.2.0",
  "enabled_agents": ["env-scanner", "config-discovery", "integration-points"],
  "timeout_seconds": 15,

  "agent_statistics": {
    "env-scanner": {
      "enabled": true,
      "total_runs": 5,
      "total_constraints_found": 12,
      "user_selected_count": 3,
      "selection_rate": 0.25,
      "avg_runtime_seconds": 4.2,
      "timeout_count": 0,
      "error_count": 0,
      "last_run": "2025-12-31T18:00:00Z"
    },

    "config-discovery": {
      "enabled": true,
      "total_runs": 5,
      "total_constraints_found": 8,
      "user_selected_count": 1,
      "selection_rate": 0.125,
      "avg_runtime_seconds": 2.1,
      "timeout_count": 0,
      "error_count": 0,
      "last_run": "2025-12-31T18:00:00Z"
    },

    "integration-points": {
      "enabled": true,
      "total_runs": 5,
      "total_constraints_found": 6,
      "user_selected_count": 2,
      "selection_rate": 0.33,
      "avg_runtime_seconds": 3.8,
      "timeout_count": 1,
      "error_count": 0,
      "last_run": "2025-12-31T18:00:00Z"
    }
  },

  "optimization_config": {
    "mode": "adaptive",
    "min_selection_rate": 0.15,
    "auto_disable_threshold": 0.1,
    "next_optimization_check": "2026-01-31T00:00:00Z"
  }
}
```

---

## 7. AUQ Option Builder (Python Helper)

### Helper to generate AUQ options from NDJSON

```python
#!/usr/bin/env python3
"""Convert constraint NDJSON to AUQ option format.

Reads .claude/ralph-constraint-scan.jsonl and outputs YAML-like
AUQ option structure for embedding in start.md.
"""

from __future__ import annotations

import json
import sys
from pathlib import Path


def constraints_to_auq_options(scan_file: Path) -> dict:
    """Parse NDJSON constraints and generate AUQ options.

    Returns:
        {
            "constraints": [
                {
                    "label": "Hardcoded path: /Users/terryli",
                    "description": "(HIGH) pyproject.toml:15 [scanner] - Use env var",
                    "id": "hardcoded-001"
                },
                ...
            ],
            "severity_counts": {
                "critical": 1,
                "high": 4,
                "medium": 3,
                "low": 2
            }
        }
    """
    constraints = []
    severity_counts = {"critical": 0, "high": 0, "medium": 0, "low": 0}

    if not scan_file.exists():
        return {"constraints": [], "severity_counts": severity_counts}

    with open(scan_file) as f:
        for line in f:
            if not line.strip():
                continue

            try:
                obj = json.loads(line)
            except json.JSONDecodeError:
                continue

            if obj.get("_type") != "constraint":
                continue

            severity = obj.get("severity", "low")
            severity_counts[severity] += 1

            # Build label (truncate to 60 chars)
            label = obj.get("description", "Unknown constraint")
            if len(label) > 60:
                label = label[:57] + "..."

            # Build description (includes severity, file, source, recommendation)
            source = obj.get("source", "unknown")
            file_info = obj.get("source_file", "")
            line_num = obj.get("source_line", 0)
            recommendation = obj.get("recommendation", "")

            desc_parts = [f"({severity.upper()})"]
            if file_info:
                desc_parts.append(f"{file_info}:{line_num}")
            if source != "scanner":
                desc_parts.append(f"[{source}]")
            if recommendation:
                desc_parts.append(f"- {recommendation}")

            description = " ".join(desc_parts)

            constraints.append({
                "label": label,
                "description": description,
                "id": obj.get("id", "unknown"),
                "constraint_id": obj.get("id"),
                "severity": severity,
            })

    return {
        "constraints": constraints,
        "severity_counts": severity_counts,
    }


def main():
    """CLI entry point."""
    project_dir = Path(sys.argv[1]) if len(sys.argv) > 1 else Path.cwd()
    scan_file = project_dir / ".claude/ralph-constraint-scan.jsonl"

    result = constraints_to_auq_options(scan_file)

    # Output as JSON (for embedding in start.md)
    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    sys.exit(main())
```

---

## 8. Example Complete Flow

### User Runs /ralph:start

```
$ /ralph:start --production

Running constraint-scanner...
  Found 8 constraints (3 HIGH)
  Saved to .claude/ralph-constraint-scan.jsonl

Spawning Explore agents (timeout: 15s)...
  Agent 1: Environment Scanner...
  Agent 2: Configuration Discovery...
  Agent 3: Integration Points...

  Agent 2 complete: 1 constraint(s)        [2s elapsed]
  Agent 1 complete: 2 constraint(s)        [5s elapsed]
  Agent 3 timeout (killed after 15s)       [15s elapsed]

Aggregating constraints...
  Input: 8 (scanner) + 2 (agent1) + 1 (agent2) + 0 (agent3-timeout) = 11
  Deduped: 0
  Output: 11 total constraints

Aggregation complete: 11 total constraints
  Severity: critical=1 high=5 medium=3 low=2
  Sources: scanner=8 env-scanner=2 config-discovery=1

======================================
Confirm loop configuration:
======================================

Use AskUserQuestion:
  question: "Select loop configuration preset:"
  options:
    - label: "Production Mode (Recommended)"
    - label: "POC Mode (Fast)"
    - label: "Custom"

[User selects: Production Mode]

======================================
What should Ralph avoid? (1 critical, 5 high detected)
======================================

Use AskUserQuestion:
  question: "What should Ralph avoid? (1 critical, 5 high detected)"
  multiSelect: true
  options:
    # Constraint-derived (4 from constraints, 3 filtered)
    - label: "Hardcoded path: /Users/terryli/..."
      description: "(HIGH) pyproject.toml:15 [scanner] - Use env var"
    - label: "Python 3.10 detected (3.11 required)"
      description: "(HIGH) runtime [env-scanner] - Upgrade Python"
    - label: "uv.lock out of date"
      description: "(MEDIUM) uv.lock [env-scanner] - Regenerate lock"
    - label: "Missing Doppler auth"
      description: "(MEDIUM) .doppler [config-discovery] - Run doppler auth"

    # Static fallbacks
    - label: "Documentation updates"
      description: "README, CHANGELOG, docstrings, comments"
    ... (9 more static options)

[User selects: 4 constraints + "Documentation updates"]

======================================
Add custom forbidden items? (comma-separated)
======================================

[User enters: "Refactor database schema, API breaking changes"]

======================================
What should Ralph prioritize? (Select all that apply)
======================================

[User selects: "Bug fixes", "Performance improvements"]

======================================
Add custom encouraged items? (comma-separated)
======================================

[User enters: "Feature engineering"]

======================================
Saving configuration...
======================================

✓ Guidance saved to .claude/ralph-config.json
✓ Learned behavior saved (3 constraints acknowledged)

Ralph Loop: PRODUCTION MODE
Time limits: 4h minimum / 9h maximum
Iterations: 50 minimum / 99 maximum
Adapter: alpha-forge
State: RUNNING
Config: .claude/ralph-config.json

To stop: /ralph:stop
Kill switch: touch .claude/STOP_LOOP
```

---

## References

- Protocol: Canonical constraint JSON schema (Section 1)
- Implementation: Aggregator algorithm (Section 2)
- Agent specs: Environment, Config, Integration (Sections 3+)
- Config: Pydantic models for v3.2.0 (Section 5)
- Learning: Global statistics tracking (Section 6)

