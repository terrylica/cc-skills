# /// script
# requires-python = ">=3.11"
# dependencies = []
# ///
"""Core adapter infrastructure for Ralph multi-repository support."""

from core.path_hash import build_state_file_path, get_path_hash, load_session_state
from core.protocols import ConvergenceResult, MetricsEntry, ProjectAdapter
from core.registry import AdapterRegistry

__all__ = [
    "MetricsEntry",
    "ConvergenceResult",
    "ProjectAdapter",
    "AdapterRegistry",
    "get_path_hash",
    "build_state_file_path",
    "load_session_state",
]
