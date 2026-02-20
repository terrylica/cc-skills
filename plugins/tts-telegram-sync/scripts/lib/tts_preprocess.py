#!/usr/bin/env python3
"""
tts_preprocess.py — Intelligent text preprocessing for Kokoro TTS
# ADR: docs/adr/2026-02-19-tts-text-preprocessing.md

Solves the hard-wrap problem: text copied from terminals, AI chat output,
or PDF viewers has line breaks inserted at column width (~80-120 chars),
mid-sentence. These create unnatural pauses or cut-off speech in TTS.

Algorithm:
  1. Split into paragraph blocks on blank lines (preserved as real breaks)
  2. Within each block, heuristically join soft-wrapped lines
  3. Strip markdown noise (headers, bold, italic, code ticks)
  4. Replace symbols with TTS-friendly equivalents (∴ → "Therefore", etc.)

Soft-wrap detection heuristics (join if ANY match):
  - Next line starts with lowercase letter          → definite continuation
  - Next line starts with ","  ";"  "-"             → punctuation continuation
  - Current line is long (>60 chars) and next line is
    not a list item or heading                      → probable word-wrap

Keep break if ANY match:
  - Blank line (paragraph separator)
  - Next line starts with a list marker (-, *, •, 1., a.)
  - Next line has leading indentation (code/structure)
  - Current line ends with sentence punctuation (.!?) AND
    next line starts uppercase AND current line is short (<60 chars)
  - Both lines are very short (<35 chars)           → headers / labels

Usage:
  python tts_preprocess.py                  # reads stdin, writes stdout
  python tts_preprocess.py "text here"      # inline text arg
  echo "text" | python tts_preprocess.py   # pipe
"""

import re
import sys


# ---------------------------------------------------------------------------
# Symbol / markdown substitution table (order matters — regex applied top-down)
# ---------------------------------------------------------------------------
_SUBSTITUTIONS: list[tuple[str | re.Pattern, str]] = [
    # Markdown structural noise
    (re.compile(r'^∴\s*.*', re.MULTILINE), ''),          # "∴ Thinking…" blocks
    (re.compile(r'^#{1,6}\s+', re.MULTILINE), ''),        # ATX headings
    (re.compile(r'^[-*_]{3,}\s*$', re.MULTILINE), ''),    # horizontal rules
    (re.compile(r'^>\s+', re.MULTILINE), ''),             # blockquotes
    # Inline formatting (must come before raw-symbol replacements)
    (re.compile(r'\*\*([^*\n]+)\*\*'), r'\1'),            # **bold**
    (re.compile(r'\*([^*\n]+)\*'), r'\1'),                # *italic*
    (re.compile(r'__([^_\n]+)__'), r'\1'),                # __bold__
    (re.compile(r'_([^_\n]+)_'), r'\1'),                  # _italic_
    (re.compile(r'`{3}[^\n]*\n', re.MULTILINE), ''),      # code fence open
    (re.compile(r'`{3}', re.MULTILINE), ''),              # code fence close
    (re.compile(r'`([^`\n]+)`'), r'\1'),                  # `inline code`
    # Markdown links: [text](url) → text
    (re.compile(r'\[([^\]]+)\]\([^)]+\)'), r'\1'),
    # Unicode symbols → TTS-readable words
    ('∴', 'Therefore,'),
    ('∵', 'Because,'),
    ('⇒', 'implies'),
    ('→', 'leads to'),
    ('←', 'comes from'),
    ('↔', 'is equivalent to'),
    ('≡', 'is equivalent to'),
    ('≈', 'approximately'),
    ('≠', 'is not equal to'),
    ('≤', 'is at most'),
    ('≥', 'is at least'),
    ('∈', 'in'),
    ('∉', 'not in'),
    ('∩', 'intersect'),
    ('∪', 'union'),
    ('∞', 'infinity'),
    ('✓', 'yes'),
    ('✗', 'no'),
    ('✘', 'no'),
    ('•', '-'),
    ('…', '...'),
    # Numbered list noise: "  4. Item" → "Item" (strip leading number+dot)
    # We keep the text; Kokoro reads "4." as "four period" otherwise
    (re.compile(r'^\s{0,4}\d{1,2}\.\s+', re.MULTILINE), ''),
    # Lettered list: "  a. Item" → "Item"
    (re.compile(r'^\s{0,4}[a-z]\.\s+', re.MULTILINE), ''),
    # Dash/bullet list markers at line start — keep a space for prosody
    (re.compile(r'^\s*[-*•]\s+', re.MULTILINE), ' '),
    # Box chars from tables/diagrams → skip
    (re.compile(r'[│├└─┌┐┘╔╗╚╝║═╠╣╦╩╬]'), ' '),
    # Multiple spaces → single (only mid-line, preserve leading indentation for _INDENTED check)
    (re.compile(r'(?<=\S)[ \t]{2,}'), ' '),
]

# Sentence-ending punctuation (for keep-break heuristic)
_SENTENCE_END = re.compile(r'[.!?:]\s*$')
# List-item start: -, *, •, 1., a. (must be at start of stripped line)
_LIST_START = re.compile(r'^(\s{0,4}[-*•]|\s{0,4}\d{1,2}\.\s|\s{0,4}[a-z]\.\s)')
# Leading indentation (code blocks, deeply nested structure)
_INDENTED = re.compile(r'^\s{4,}')
# Very short line threshold (probable header or label)
_SHORT_LINE = 35
# Long line threshold — heuristic for soft-wrap detection
_LONG_LINE = 62


def _apply_substitutions(text: str) -> str:
    for pattern, replacement in _SUBSTITUTIONS:
        if isinstance(pattern, str):
            text = text.replace(pattern, replacement)
        else:
            text = pattern.sub(replacement, text)
    return text


def _should_join(current: str, nxt: str) -> bool:
    """Return True if `nxt` should be joined onto `current` with a space."""
    c = current.rstrip()
    n = nxt.strip()

    if not n:
        return False  # blank line → paragraph break (caller handles)

    # Preserve list items, indented blocks, headings
    if _LIST_START.match(n):
        return False
    if _INDENTED.match(nxt):
        return False
    if n.startswith('#'):
        return False

    # Clear continuation: next starts with lowercase
    if n and n[0].islower():
        return True

    # Continuation punctuation at start of next line
    if n and n[0] in (',', ';', ')'):
        return True

    # Both lines are very short → intentional structure (e.g., step labels)
    if len(c) < _SHORT_LINE and len(n) < _SHORT_LINE:
        return False

    # Current line ends with sentence-ending punctuation AND next starts uppercase
    # AND current line is not long → real paragraph/sentence break
    if _SENTENCE_END.search(c) and n and n[0].isupper() and len(c) < _LONG_LINE:
        return False

    # Current line is "long" (near terminal wrap width) → likely soft-wrapped
    if len(c) >= _LONG_LINE:
        return True

    return False


def _reflow_block(lines: list[str]) -> str:
    """Join soft-wrapped lines within a single paragraph block."""
    if not lines:
        return ''

    result = lines[0].rstrip()
    for i in range(1, len(lines)):
        nxt = lines[i]
        if _should_join(result, nxt):
            # Avoid double-space if result already ends with space
            result = result.rstrip() + ' ' + nxt.strip()
        else:
            result = result + '\n' + nxt.rstrip()
    return result


def preprocess(text: str) -> str:
    """Full TTS preprocessing pipeline."""
    # 1. Apply symbol / markdown substitutions
    text = _apply_substitutions(text)

    # 2. Split into paragraph blocks (one or more blank lines = separator)
    #    We preserve blank lines as paragraph separators in output.
    raw_blocks = re.split(r'\n\s*\n', text)

    processed_blocks: list[str] = []
    for block in raw_blocks:
        lines = block.split('\n')
        reflowed = _reflow_block([ln for ln in lines])
        if reflowed.strip():
            processed_blocks.append(reflowed.strip())

    # 3. Rejoin with double-newline paragraph separators
    result = '\n\n'.join(processed_blocks)

    # 4. Final cleanup: collapse 3+ newlines, trailing whitespace
    result = re.sub(r'\n{3,}', '\n\n', result)
    result = re.sub(r'[ \t]+\n', '\n', result)

    return result.strip()


def main() -> None:
    if len(sys.argv) > 1:
        # Inline text passed as argument (from shell: --text "...")
        text = ' '.join(sys.argv[1:])
    elif not sys.stdin.isatty():
        text = sys.stdin.read()
    else:
        print(__doc__)
        sys.exit(0)

    print(preprocess(text), end='')


if __name__ == '__main__':
    main()
