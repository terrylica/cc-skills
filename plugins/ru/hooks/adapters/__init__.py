# /// script
# requires-python = ">=3.11"
# dependencies = []
# ///
# Issue #12: https://github.com/terrylica/cc-skills/issues/12
"""Project-type adapters for Ralph Universal.

Each adapter provides project-specific logic for:
- Detecting project type from directory structure
- Reading metrics from existing outputs
- Determining convergence based on project-specific signals

Ralph Universal includes:
- AlphaForgeAdapter: For Alpha-Forge ML research projects (metrics-based convergence)
- UniversalAdapter: Fallback for ANY project (time/iteration-based completion)

To add a new adapter:
1. Create a new .py file in this directory
2. Implement a class with the ProjectAdapter protocol
3. The registry will auto-discover it on next Ralph start
"""

from adapters.alpha_forge import AlphaForgeAdapter
from adapters.universal import UniversalAdapter

__all__ = ["AlphaForgeAdapter", "UniversalAdapter"]
