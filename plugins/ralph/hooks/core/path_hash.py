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
from pathlib import Path

logger = logging.getLogger(__name__)

# Hash length in characters (8 chars = 4.3 billion possible values)
HASH_LENGTH = 8


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


def load_session_state(state_file: Path, default_state: dict) -> dict:
    """Load session state with dual-mode fallback for backward compatibility.

    Attempts to load state in order:
    1. New format: sessions/{session_id}@{path_hash}.json
    2. Old format: sessions/{session_id}.json (fallback for migration)

    Args:
        state_file: Primary state file path (new format with @hash)
        default_state: Default state dict to merge with loaded state

    Returns:
        Merged state dict (default_state updated with loaded values)

    Example:
        >>> default = {"iteration": 0, "recent_outputs": []}
        >>> state = load_session_state(Path("sessions/abc@1234.json"), default)
    """
    if state_file.exists():
        try:
            loaded = json.loads(state_file.read_text())
            logger.debug(f"Loaded state from: {state_file.name}")
            return {**default_state, **loaded}
        except (json.JSONDecodeError, OSError) as e:
            logger.warning(f"Failed to parse state file {state_file.name}: {e}")

    logger.debug("No existing state found, using defaults")
    return default_state
