# /// script
# requires-python = ">=3.11"
# dependencies = []
# ///
"""Core configuration for Ralph Universal PreToolUse hook.

ADR: /docs/adr/2025-12-20-ralph-rssi-eternal-loop.md
Issue #12: https://github.com/terrylica/cc-skills/issues/12
"""

from core.config_schema import ProtectionConfig, load_config

__all__ = [
    "ProtectionConfig",
    "load_config",
]
