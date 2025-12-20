# /// script
# requires-python = ">=3.11"
# dependencies = []
# ///
"""Core adapter infrastructure for Ralph multi-repository support."""

from core.protocols import MetricsEntry, ConvergenceResult, ProjectAdapter
from core.registry import AdapterRegistry
from core.path_hash import get_path_hash, build_state_file_path, load_session_state

__all__ = [
    "MetricsEntry",
    "ConvergenceResult",
    "ProjectAdapter",
    "AdapterRegistry",
    "get_path_hash",
    "build_state_file_path",
    "load_session_state",
]
