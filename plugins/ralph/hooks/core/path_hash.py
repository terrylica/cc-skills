# /// script
# requires-python = ">=3.11"
# dependencies = []
# ///
"""Path-based session state isolation.

Provides utilities for generating deterministic hashes from project paths,
enabling session state isolation across different projects/worktrees even
when using the same Claude session ID.

Session state files use the format: sessions/{session_id}@{path_hash}.json
"""

import hashlib
import json
import logging
import sys
from datetime import datetime, timezone
from pathlib import Path

logger = logging.getLogger(__name__)

# Fields that should be inherited across sessions (continuity counters)
INHERITED_FIELDS = ["iteration", "accumulated_runtime_seconds", "started_at", "adapter_convergence"]

# Fields that should be reset on inheritance (per-session state)
RESET_FIELDS = ["recent_outputs", "validation_round", "idle_iteration_count"]

# Hash length in characters (8 chars = 4.3 billion possible values)
HASH_LENGTH = 8


def log_inheritance(
    log_file: Path,
    child_session: str,
    parent_session: str,
    project_hash: str,
    parent_state: dict,
) -> str:
    """Append inheritance record to JSONL log for audit trail.

    Creates an infallible record of session inheritance with hash chain
    for verification. The parent_hash allows detecting if parent state
    was modified after inheritance.

    Args:
        log_file: Path to inheritance-log.jsonl
        child_session: New session ID (inheriting)
        parent_session: Previous session ID (being inherited from)
        project_hash: Project path hash for filtering
        parent_state: Parent state dict at inheritance time

    Returns:
        Parent state hash (sha256:XXXX format) for embedding in child state

    Example log entry:
        {"timestamp":"2025-12-25T10:00:00Z","child_session":"abc123",
         "parent_session":"xyz789","project_hash":"c7e0a029",
         "parent_hash":"sha256:1a2b3c4d...","inherited_fields":[...]}
    """
    # Compute hash of parent state at inheritance time
    parent_hash = hashlib.sha256(
        json.dumps(parent_state, sort_keys=True).encode()
    ).hexdigest()[:16]

    record = {
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "child_session": child_session,
        "parent_session": parent_session,
        "project_hash": project_hash,
        "parent_hash": f"sha256:{parent_hash}",
        "inherited_fields": INHERITED_FIELDS,
    }

    # Ensure parent directory exists
    log_file.parent.mkdir(parents=True, exist_ok=True)

    with log_file.open("a") as f:
        f.write(json.dumps(record) + "\n")

    logger.info(
        f"Inheritance logged: {child_session} ← {parent_session} "
        f"(project: {project_hash}, hash: sha256:{parent_hash[:8]}...)"
    )

    return f"sha256:{parent_hash}"


def get_path_hash(project_dir: str, length: int = HASH_LENGTH) -> str:
    """Generate deterministic hash from absolute project path.

    Used for session state isolation across worktrees/projects.
    Resolves symlinks before hashing to ensure consistent hashes
    for the same physical directory.

    Args:
        project_dir: Project directory path
        length: Hash length in characters (default 8)

    Returns:
        Hex hash (e.g., '4a7f2b9e'), or 'none' if path is empty/invalid

    Example:
        >>> get_path_hash("/Users/dev/alpha-forge")
        '4a7f2b9e'
        >>> get_path_hash("/Users/dev/alpha-forge/")  # Trailing slash normalized
        '4a7f2b9e'
        >>> get_path_hash("")  # Empty path
        'none'
    """
    if not project_dir:
        return "none"

    try:
        # Resolve symlinks and normalize path
        abs_path = Path(project_dir).resolve()
        hash_obj = hashlib.md5(str(abs_path).encode("utf-8"))
        return hash_obj.hexdigest()[:length]
    except (OSError, ValueError) as e:
        print(f"[ralph] Warning: Could not hash path '{project_dir}': {e}", file=sys.stderr)
        logger.warning(f"Could not hash path '{project_dir}': {e}")
        return "none"


def build_state_file_path(state_dir: Path, session_id: str, project_dir: str) -> Path:
    """Build session state file path with project isolation.

    Format: sessions/{session_id}@{path_hash}.json

    Args:
        state_dir: Base state directory (e.g., ~/.claude/automation/loop-orchestrator/state)
        session_id: Claude session ID
        project_dir: Project directory path

    Returns:
        Path to the session state file

    Example:
        >>> build_state_file_path(Path.home() / ".claude/state", "abc123", "/dev/project")
        PosixPath('/Users/dev/.claude/state/sessions/abc123@4a7f2b9e.json')
    """
    path_hash = get_path_hash(project_dir)
    return state_dir / f"sessions/{session_id}@{path_hash}.json"


def load_session_state(
    state_file: Path,
    default_state: dict,
    state_dir: Path | None = None,
    path_hash: str | None = None,
) -> dict:
    """Load session state with inheritance fallback for cross-session continuity.

    When a new session starts (state_file doesn't exist), automatically inherits
    from the most recent session for the same project (same path_hash). This
    ensures continuity across Claude Code auto-compacting, /clear, and rate limits.

    Inheritance is logged to an append-only JSONL file with hash chain for
    verification. See log_inheritance() for audit trail details.

    Args:
        state_file: Primary state file path (format: sessions/{session_id}@{path_hash}.json)
        default_state: Default state dict to merge with loaded state
        state_dir: Base state directory for finding previous sessions (optional)
        path_hash: Project path hash for filtering candidates (optional)

    Returns:
        Merged state dict with inheritance metadata if inherited

    Inheritance behavior:
        - Inherited: iteration, accumulated_runtime_seconds, started_at, adapter_convergence
        - Reset: recent_outputs, validation_round, idle_iteration_count

    Example:
        >>> default = {"iteration": 0, "recent_outputs": []}
        >>> state = load_session_state(
        ...     Path("sessions/abc@1234.json"),
        ...     default,
        ...     state_dir=Path("~/.claude/ralph-state"),
        ...     path_hash="1234abcd"
        ... )
        >>> state.get("_inheritance")  # Present if inherited
        {"parent_session": "xyz@1234.json", "parent_hash": "sha256:...", ...}
    """
    # Primary: Load from current session's state file
    if state_file.exists():
        try:
            loaded = json.loads(state_file.read_text())
            logger.debug(f"Loaded state from: {state_file.name}")
            return {**default_state, **loaded}
        except (json.JSONDecodeError, OSError) as e:
            logger.warning(f"Failed to parse state file {state_file.name}: {e}")

    # Fallback: Inherit from most recent same-project session
    if state_dir and path_hash:
        sessions_dir = state_dir / "sessions"
        if sessions_dir.exists():
            # Find all state files for this project (same path_hash)
            candidates = sorted(
                sessions_dir.glob(f"*@{path_hash}.json"),
                key=lambda p: p.stat().st_mtime,
                reverse=True,
            )

            # Exclude current session file from candidates
            candidates = [c for c in candidates if c.name != state_file.name]

            if candidates:
                parent_file = candidates[0]
                try:
                    parent_state = json.loads(parent_file.read_text())

                    # Log inheritance with hash chain for audit
                    log_file = sessions_dir / "inheritance-log.jsonl"
                    child_session = state_file.stem.split("@")[0]
                    parent_session = parent_file.stem

                    parent_hash = log_inheritance(
                        log_file=log_file,
                        child_session=child_session,
                        parent_session=parent_session,
                        project_hash=path_hash,
                        parent_state=parent_state,
                    )

                    # Build inherited state
                    inherited = {**default_state, **parent_state}

                    # Add inheritance metadata for verification
                    inherited["_inheritance"] = {
                        "parent_session": parent_file.name,
                        "parent_hash": parent_hash,
                        "inherited_at": datetime.now(timezone.utc).isoformat(),
                        "inherited_fields": INHERITED_FIELDS,
                    }

                    # Reset per-session state (fresh start)
                    for field in RESET_FIELDS:
                        if field in inherited:
                            if isinstance(inherited[field], list):
                                inherited[field] = []
                            elif isinstance(inherited[field], int):
                                inherited[field] = 0
                            else:
                                inherited.pop(field, None)

                    logger.info(
                        f"Session state inherited from {parent_file.name} "
                        f"(iteration={inherited.get('iteration', 0)}, "
                        f"runtime={inherited.get('accumulated_runtime_seconds', 0):.1f}s)"
                    )

                    return inherited

                except (json.JSONDecodeError, OSError) as e:
                    logger.warning(f"Failed to inherit from {parent_file.name}: {e}")

    logger.debug("No existing state found, using defaults")
    return default_state.copy()
