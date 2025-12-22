#!/usr/bin/env python3
# /// script
# requires-python = ">=3.11"
# dependencies = []
# ///
"""
Bash Block Fixer
================

Adds heredoc wrappers to bash code blocks that need them for zsh compatibility.

Usage:
    uv run fix_bash_blocks.py <path>        # Fix files in path
    uv run fix_bash_blocks.py <path> --dry  # Preview changes only

This script:
1. Finds bash code blocks without /usr/bin/env bash heredoc wrappers
2. Only wraps blocks that contain bash-specific syntax ($(), [[, etc.)
3. Generates descriptive EOF markers based on context
"""

import re
import sys
from pathlib import Path

# Patterns
BASH_BLOCK_PATTERN = re.compile(r'(```bash\n)(.*?)(```)', re.DOTALL)
HEREDOC_WRAPPER = re.compile(r'^/usr/bin/env\s+bash\s*<<\s*[\'"]?\w+[\'"]?', re.MULTILINE)
NEEDS_WRAPPER_PATTERNS = [
    re.compile(r'\$\([^)]+\)'),        # $(command)
    re.compile(r'\[\[.*\]\]'),          # [[ conditionals ]]
    re.compile(r'declare\s+-'),         # declare -A, declare -a
    re.compile(r'\$\{[^}]+\}'),         # ${var} expansions
    re.compile(r'if\s+\[\['),           # if [[
    re.compile(r'for\s+\w+\s+in'),      # for x in
    re.compile(r'while\s+\[\['),        # while [[
]


def needs_wrapper(block: str) -> bool:
    """Check if bash block needs heredoc wrapper."""
    # Already has wrapper
    if HEREDOC_WRAPPER.search(block):
        return False

    # Check for bash-specific patterns
    for pattern in NEEDS_WRAPPER_PATTERNS:
        if pattern.search(block):
            return True

    return False


def generate_eof_marker(block: str, filepath: str) -> str:
    """Generate descriptive EOF marker based on content."""
    block_lower = block.lower()

    # Try to infer purpose from content
    if 'preflight' in block_lower or 'check' in block_lower:
        return 'PREFLIGHT_EOF'
    if 'setup' in block_lower or 'install' in block_lower:
        return 'SETUP_EOF'
    if 'validate' in block_lower or 'verify' in block_lower:
        return 'VALIDATE_EOF'
    if 'config' in block_lower:
        return 'CONFIG_EOF'
    if 'detect' in block_lower:
        return 'DETECT_EOF'
    if 'git ' in block_lower:
        return 'GIT_EOF'
    if 'doppler' in block_lower:
        return 'DOPPLER_EOF'
    if 'mise' in block_lower:
        return 'MISE_EOF'

    # Fall back to file-based marker
    stem = Path(filepath).stem.upper().replace('-', '_')
    return f'{stem}_SCRIPT_EOF'


def wrap_block(block: str, eof_marker: str) -> str:
    """Wrap bash block with heredoc."""
    # Ensure block ends with newline
    if not block.endswith('\n'):
        block += '\n'

    return f"/usr/bin/env bash << '{eof_marker}'\n{block}{eof_marker}\n"


def fix_file(filepath: Path, dry_run: bool = False) -> int:
    """Fix bash blocks in a single file. Returns count of fixes."""
    try:
        content = filepath.read_text(encoding='utf-8')
    except Exception as e:
        print(f"Error reading {filepath}: {e}", file=sys.stderr)
        return 0

    fixes = 0
    eof_counter = {}  # Track unique EOF markers

    def replace_block(match: re.Match) -> str:
        nonlocal fixes
        prefix = match.group(1)  # ```bash\n
        block = match.group(2)   # content
        suffix = match.group(3)  # ```

        if not needs_wrapper(block):
            return match.group(0)

        # Generate unique EOF marker
        base_marker = generate_eof_marker(block, str(filepath))
        eof_counter[base_marker] = eof_counter.get(base_marker, 0) + 1
        if eof_counter[base_marker] > 1:
            marker = f"{base_marker}_{eof_counter[base_marker]}"
        else:
            marker = base_marker

        wrapped = wrap_block(block, marker)
        fixes += 1
        return f"{prefix}{wrapped}{suffix}"

    new_content = BASH_BLOCK_PATTERN.sub(replace_block, content)

    if fixes > 0:
        if dry_run:
            print(f"Would fix {fixes} block(s) in {filepath}")
        else:
            filepath.write_text(new_content, encoding='utf-8')
            print(f"Fixed {fixes} block(s) in {filepath}")

    return fixes


def main() -> int:
    if len(sys.argv) < 2:
        print("Usage: uv run fix_bash_blocks.py <path> [--dry]", file=sys.stderr)
        return 2

    path = Path(sys.argv[1]).resolve()
    dry_run = '--dry' in sys.argv

    if not path.exists():
        print(f"Error: Path does not exist: {path}", file=sys.stderr)
        return 2

    total_fixes = 0

    if path.is_file():
        total_fixes = fix_file(path, dry_run)
    else:
        for md_file in path.glob("**/*.md"):
            if 'node_modules' in md_file.parts:
                continue
            total_fixes += fix_file(md_file, dry_run)

    action = "Would fix" if dry_run else "Fixed"
    print(f"\n{action} {total_fixes} total bash block(s)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
