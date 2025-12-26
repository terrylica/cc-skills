#!/usr/bin/env -S uv run
# /// script
# requires-python = ">=3.11"
# dependencies = [
#     "python-ulid>=2.7.0",
# ]
# ///
"""
ULID Generator

Generates ULID (Universally Unique Lexicographically Sortable Identifier).
Used for correlation IDs in event tracking.

ADR: /docs/adr/2025-12-11-link-checker-plugin-extraction.md
Source: Adapted from claude-orchestrator/runtime/lib/ulid_gen.py
"""

from __future__ import annotations

import sys

from ulid import ULID


def generate() -> str:
    """
    Generate ULID.

    Returns:
        26-character ULID string (e.g., 01JEGQXV8KHTNF3YD8G7ZC9XYK)
    """
    return str(ULID())


def main() -> int:
    """CLI entry point."""
    print(generate())
    return 0


if __name__ == "__main__":
    sys.exit(main())
