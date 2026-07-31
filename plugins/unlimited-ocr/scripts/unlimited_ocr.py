#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.12"
# dependencies = [
#   "pillow>=10.0.0",
#   "pymupdf>=1.24.0",
#   "mlx-vlm>=0.6.0; sys_platform == 'darwin' and platform_machine == 'arm64'",
# ]
# ///
# FILE-SIZE-OK
"""
unlimited_ocr.py — one CLI for baidu/Unlimited-OCR document parsing, on either local backend.

WHAT THIS WRAPS. Unlimited-OCR (Baidu, MIT, arXiv 2606.23050) is a 3B-total / 500M-activated MoE
document parser built on DeepSeek-OCR's DeepEncoder, with the decoder's attention replaced by
Reference Sliding Window Attention so the KV cache stays CONSTANT while decoding. That is the whole
point of the model: many pages in one forward pass without the usual slow-down.

WHY A WRAPPER EXISTS AT ALL. Three things measured on this hardware make the naive invocation
produce either garbage or nothing, and none of them are obvious from the upstream README:

  1. THE README'S OWN PROMPT LOOPS FOREVER on the MLX backend. `document parsing.` — the prompt the
     upstream README documents — decodes `parsing.parsing.parsing…` until max_tokens on Apple
     Silicon. `Free OCR.` on the same image, same weights, same seed returns perfect output in
     ~2 s. This CLI therefore defaults to a prompt that works and REFUSES the known-bad one unless
     you force it. See references/PITFALLS.md § 1.
  2. MATH COMES BACK CHARACTER-SPACED. A variable named `curpdf` is emitted as `c u r p d f`.
     In LaTeX math mode that renders identically, so it is not an error — but it is not
     byte-identical either, which silently destroys any cross-model agreement check.
     `--collapse-math-spacing` repairs it.
  3. CHARTS COME BACK EMPTY. The model localises a chart and transcribes NOTHING inside it. On a
     nine-panel matplotlib figure it emitted nine perfect `chart` bounding boxes and zero
     characters. That is correct behaviour for a layout parser and a total surprise if you expected
     an image captioner. `segment` turns that limitation into a feature.

ONE IMAGE PER FORWARD PASS, DELIBERATELY. The model's headline capability is parsing dozens of
pages in a single pass, and this CLI does not use it. A five-page single-pass run on the RTX 4090
returned FOUR pages — one silently absent, no error — and the prompt that mode requires
hallucinates on any single image. For archive work, where a dropped page is unrecoverable and
undetectable, per-page calls are the safe construction: each page is independently verifiable and
the loop detector sees each one on its own. The cost is throughput, which is not the scarce
resource here.

Every number above was measured, not read. Provenance: references/EMPIRICAL.md.

SUBCOMMANDS
  parse     image / PDF / directory  ->  markdown (+ optional JSON with bounding boxes)
  segment   image + its layout boxes ->  cropped sub-images, one per detected region
  doctor    report which backends this machine can actually run, and why not
  spec      emit the machine-readable CLI contract as JSON (the SSoT for agents)

@module plugins/unlimited-ocr/scripts/unlimited_ocr
"""

from __future__ import annotations

import argparse
import contextlib
import importlib.util
import json
import os
import re
import sys
import tempfile
import time
from dataclasses import dataclass, asdict, field
from pathlib import Path
from typing import Any, Iterable

# ─────────────────────────────────────────────────────────────── constants

SCRIPT_VERSION = "1.0.0"

DEFAULT_MLX_MODEL_IDENTIFIER = "mlx-community/Unlimited-OCR-mxfp8"
DEFAULT_CUDA_MODEL_IDENTIFIER = "baidu/Unlimited-OCR"

#: Prompts the model actually accepts, mapped to a stable CLI-facing name.
#:
#: `free-ocr` is the DEFAULT because it is the only one empirically verified to terminate on the
#: MLX backend. `document-parsing` is retained ONLY so the failure is nameable and reproducible —
#: it is refused unless --allow-known-looping-prompt is passed.
PROMPT_MODES: dict[str, str] = {
    "free-ocr": "Free OCR.",
    "multi-page": "Multi page parsing.",
    "document-parsing": "document parsing.",
}

#: Prompt modes withheld unless explicitly forced, each mapped to the failure MEASURED for it.
#:
#: They are kept in PROMPT_MODES rather than deleted so the failures stay nameable and
#: reproducible — a mode that silently disappears teaches the next person nothing, and they will
#: reach for the upstream README and hit the same wall.
PROMPT_MODES_WITHHELD_BY_DEFAULT: dict[str, str] = {
    "document-parsing": (
        "decodes degenerate repetition ('parsing.parsing.parsing…') until max_tokens on the MLX "
        "backend. This is the prompt the upstream README documents. A repetition penalty does not "
        "stop it and neither does the chat template — only the prompt choice does."
    ),
    "multi-page": (
        "HALLUCINATES on a single image: deterministically prepends the word 'industrydocuments', "
        "which appears nowhere in the source, on every run. It is designed for a multi-image "
        "forward pass that this CLI deliberately does not perform (see the module docstring), so "
        "on the one-image-per-call path it has no correct use."
    ),
}

#: Rendering DPI for PDF pages.
#:
#: 300 IS A CORRECTNESS SETTING, NOT A QUALITY KNOB. Vision models transcribing mathematics at
#: 150 DPI hallucinate silently — they return confident, well-formed, WRONG LaTeX rather than
#: failing. This default is deliberately not lowered to save time.
DEFAULT_PDF_RENDER_DPI = 300

#: Repetition penalty applied on the MLX path.
#:
#: The reference CUDA implementation defends against degenerate loops with an n-gram blocker
#: (no_repeat_ngram_size=35). mlx-vlm has no equivalent logit processor, so a scalar repetition
#: penalty is the available substitute. It is NOT equivalent and does not prevent the
#: `document parsing.` loop — only the prompt choice does.
DEFAULT_REPETITION_PENALTY = 1.05

DEFAULT_MAX_TOKENS = 8192

#: Pixels added to every side of a crop by `segment`.
#:
#: NOT zero, deliberately. The model's boxes bound the plotted area, so a pixel-exact crop of a
#: chart loses the axis tick labels immediately below it — measured on a nine-panel figure where
#: all nine crops were clipped. Those labels carry the units and the date range, which is most of
#: what makes a chart interpretable downstream.
DEFAULT_SEGMENT_PADDING_PIXELS = 12

#: `<|det|>CATEGORY [x0, y0, x1, y1]<|/det|>` — the layout marker the model emits before each block.
#: Coordinates are normalised to 0-1000 in BOTH axes, independent of the image's real aspect ratio.
DETECTION_MARKER_PATTERN = re.compile(
    r"<\|det\|>\s*(?P<category>[^\s\[<]+)\s*(?:\[(?P<bbox>[^\]]*)\])?\s*<\|/det\|>"
)

#: The normalised coordinate ceiling the model emits against.
DETECTION_COORDINATE_SPACE = 1000

#: Reverse of the GPT-2 byte-level-BPE alphabet: surface character -> the byte it stands for.
#:
#: Built once at import. See `decode_byte_level_bpe_surface_form` for why this is needed at all.
BYTE_LEVEL_BPE_SURFACE_CHARACTER_TO_BYTE: dict[str, int] = {}

IMAGE_SUFFIXES = {".png", ".jpg", ".jpeg", ".webp", ".gif", ".bmp", ".tif", ".tiff"}


# ─────────────────────────────────────────────────────────────── data shapes


@dataclass
class DetectedRegion:
    """One layout block the model localised, in both normalised and pixel coordinates."""

    category: str
    normalized_bbox: tuple[int, int, int, int] | None
    pixel_bbox: tuple[int, int, int, int] | None
    text: str

    def to_json(self) -> dict[str, Any]:
        return {
            "category": self.category,
            "normalized_bbox": list(self.normalized_bbox) if self.normalized_bbox else None,
            "pixel_bbox": list(self.pixel_bbox) if self.pixel_bbox else None,
            "text": self.text,
        }


@dataclass
class ParseResult:
    """Everything one parsed input produced, including what it cost."""

    source_path: str
    backend: str
    model_identifier: str
    prompt_mode: str
    raw_text: str
    markdown: str
    regions: list[DetectedRegion] = field(default_factory=list)
    elapsed_seconds: float = 0.0
    page_count: int = 1
    degenerate_repetition_suspected: bool = False

    def to_json(self) -> dict[str, Any]:
        payload = asdict(self)
        payload["regions"] = [r.to_json() for r in self.regions]
        return payload


# ─────────────────────────────────────────────────────────────── text repair


def _build_byte_level_bpe_surface_alphabet() -> dict[int, str]:
    """
    The GPT-2 byte-level-BPE alphabet: byte value -> the printable character standing in for it.

    Bytes that are already printable ASCII map to themselves; every other byte is displaced into a
    private range so that any byte sequence is representable as printable text. This is the standard
    construction shared by GPT-2, RoBERTa, DeepSeek and this model's tokenizer.
    """
    printable_bytes = (
        list(range(ord("!"), ord("~") + 1))
        + list(range(ord("\u00a1"), ord("\u00ac") + 1))
        + list(range(ord("\u00ae"), ord("\u00ff") + 1))
    )
    surface_codepoints = printable_bytes[:]
    displaced = 0
    for byte_value in range(2**8):
        if byte_value not in printable_bytes:
            printable_bytes.append(byte_value)
            surface_codepoints.append(2**8 + displaced)
            displaced += 1
    return {b: chr(c) for b, c in zip(printable_bytes, surface_codepoints)}


BYTE_LEVEL_BPE_SURFACE_CHARACTER_TO_BYTE.update(
    {surface: byte for byte, surface in _build_byte_level_bpe_surface_alphabet().items()}
)


def decode_byte_level_bpe_surface_form(text: str) -> str:
    """
    Recover real UTF-8 from the byte-level-BPE surface form mlx-vlm returns.

    WITHOUT THIS, EVERY NON-ASCII CHARACTER IS DESTROYED. The MLX path hands back the tokenizer's
    surface form rather than decoded text, so each BYTE of a multi-byte UTF-8 character arrives as
    its own stand-in character. Chinese is the obvious casualty and it is total:

        8æľĪ                          ->  8月
        åıįåĲĳæĹ¥åĨħéĢĨè½¬çļĦé¢ĳçİĩ  ->  反向日内逆转的频率
        âĳł                           ->  ①

    That is not cosmetic on a Chinese corpus — it is the difference between a transcription and
    nothing. It went unnoticed at first because the early test images were formula-only or English,
    where the surface form and the decoded text coincide.

    An earlier version replaced only `Ġ` with a space and `Ċ` with a newline. Those two are the
    same phenomenon: `Ġ` is the surface form of byte 0x20 and `Ċ` of byte 0x0A. Patching the two
    most visible symptoms left every other byte mangled, and it also explains the stray `âľī`
    previously recorded as an isolated mojibake of `✉` — it was never isolated.

    Characters absent from the alphabet are passed through as themselves, so text that has ALREADY
    been decoded survives unchanged and the function is safe to apply to either form.
    """
    recovered_bytes = bytearray()
    for character in text:
        byte_value = BYTE_LEVEL_BPE_SURFACE_CHARACTER_TO_BYTE.get(character)
        if byte_value is None:
            recovered_bytes.extend(character.encode("utf-8"))
        else:
            recovered_bytes.append(byte_value)
    return recovered_bytes.decode("utf-8", errors="replace")


def collapse_math_character_spacing(text: str) -> str:
    """
    Rejoin `c u r p d f` into `curpdf` inside math, leaving everything else untouched.

    WHY THIS IS NOT COSMETIC. The model emits each letter of a multi-letter identifier as its own
    math atom. LaTeX renders `c u r p d f` and `curpdf` identically, so the output is not WRONG —
    but it is not byte-identical to what any other model produces, and a pipeline that treats
    agreement between two independent transcribers as evidence of correctness will score every
    single formula as a disagreement. Collapsing the spacing is what makes this model usable as a
    corroborating reader rather than a permanent dissenter.

    Deliberately conservative: only single spaces BETWEEN TWO ASCII LETTERS are removed, and only
    inside `\\[...\\]`, `\\(...\\)` or `$...$`. A space next to a digit, an operator, a brace or a
    backslash command is load-bearing and is preserved.
    """
    letter_gap = re.compile(r"(?<=[A-Za-z]) (?=[A-Za-z])")

    def repair(match: re.Match[str]) -> str:
        # ONE PASS IS SUFFICIENT, and this was verified rather than assumed. Both lookarounds are
        # ZERO-WIDTH, so consecutive gaps in a run like "c u r p d f" are non-overlapping matches
        # and `sub` closes all of them in a single scan. An earlier version looped until the string
        # stopped changing, justified by a comment claiming one pass "only closes alternate gaps".
        # That claim was false, and a mutation test proved the loop unreachable-by-effect: removing
        # it changed no output anywhere in the suite.
        return match.group("open") + letter_gap.sub("", match.group("body")) + match.group("close")

    for opener, closer in ((r"\\\[", r"\\\]"), (r"\\\(", r"\\\)"), (r"\$", r"\$")):
        pattern = re.compile(
            rf"(?P<open>{opener})(?P<body>.*?)(?P<close>{closer})", re.DOTALL
        )
        text = pattern.sub(repair, text)
    return text


def strip_detection_markers(text: str) -> str:
    """
    Remove `<|det|>…<|/det|>` markers, keeping block structure as blank-line-separated paragraphs.

    Mirrors the post-processing the upstream README specifies for OmniDocBench scoring, including
    dropping `image` blocks, which carry a box and no transcribable content.
    """
    blocks: list[list[str]] = []
    current: list[str] | None = None

    for raw_line in text.splitlines():
        line = raw_line.rstrip()
        if not line:
            continue
        match = DETECTION_MARKER_PATTERN.match(line)
        if match:
            category = match.group("category").strip()
            remainder = line[match.end():].strip()
            if category == "image":
                continue
            if current is not None:
                blocks.append(current)
            current = [remainder] if remainder else []
            continue
        if current is None:
            current = []
        current.append(line)

    if current is not None:
        blocks.append(current)
    return "\n\n".join("\n".join(b) for b in blocks).strip()


def convert_html_tables_to_pipe_markdown(text: str) -> str:
    """
    Convert HTML <table> markup to pipe-markdown, leaving non-table content untouched.

    MEASURED FACT (PITFALLS.md § 12, 2026-07-30): Unlimited-OCR emits HTML <table> for 88 of 103
    TABLE images, while other readers (M3, GLM-4.6v) emit pipe-markdown. Raw HTML in markdown breaks
    agreement metrics and embeds raw markup in concatenated output. This function bridges that gap.

    Transformation rules:
    - Each <table>...</table> block becomes a pipe-markdown table with header separator (|---|)
    - Cell content is extracted by stripping inner HTML tags
    - HTML entities (&nbsp;, &lt;, etc.) are decoded to their character equivalents
    - Pipes (|) in cell text are escaped with backslash to prevent table corruption
    - <th> elements trigger a header separator row; no separator if all <td>
    - Multiple tables in one output are all converted independently
    - Malformed or unterminated <table> elements are skipped with a warning to stderr
    - Non-table content (text before, between, after tables) passes through untouched
    - Empty tables (no <tr> or empty rows) are skipped

    Header detection: if ANY row contains <th>, that row becomes a header. The next row becomes
    the separator (|---|---|...). If NO <th> in entire table, there is no separator line.
    """
    # HTML entity decoding map: named entities and common numeric equivalents.
    # Includes both named entities (e.g., &nbsp;) and their numeric forms (&#160;, &#x00A0;).
    # Measured on 103 TABLE images from quantml corpus; numeric entities (&#160;) were found
    # in live model output and must be decoded to match agreement baselines.
    entity_decode_map = {
        "&nbsp;": " ",
        "&#160;": " ",   # numeric form of &nbsp;
        "&#xa0;": " ",   # hex form of &nbsp; (lowercase)
        "&#xA0;": " ",   # hex form of &nbsp; (uppercase)
        "&lt;": "<",
        "&#60;": "<",
        "&gt;": ">",
        "&#62;": ">",
        "&amp;": "&",
        "&#38;": "&",
        "&quot;": '"',
        "&#34;": '"',
        "&#39;": "'",
        "&apos;": "'",
        "&mdash;": "—",
        "&#8212;": "—",
        "&ndash;": "–",
        "&#8211;": "–",
        "&ldquo;": """,
        "&#8220;": """,
        "&rdquo;": """,
        "&#8221;": """,
        "&lsquo;": "'",
        "&#8216;": "'",
        "&rsquo;": "'",
        "&#8217;": "'",
        "&times;": "×",
        "&#215;": "×",
        "&divide;": "÷",
        "&#247;": "÷",
        "&plusmn;": "±",
        "&#177;": "±",
        "&deg;": "°",
        "&#176;": "°",
    }

    def decode_html_entities_in_cell(cell_text: str) -> str:
        """
        Decode HTML entities: named (&nbsp;), numeric (&#160;), and hex (&#x00A0;) forms.
        Preserve already-decoded text (replaces only when entity form is present).
        """
        result = cell_text

        # First, decode named entities from the map
        for entity, char in entity_decode_map.items():
            result = result.replace(entity, char)

        # Then decode numeric entities: &#NNNNN; (decimal) -> chr(NNNNN)
        def decode_numeric_entity(match: re.Match[str]) -> str:
            entity_str = match.group(1)
            try:
                code_point = int(entity_str)
                return chr(code_point)
            except (ValueError, OverflowError):
                return match.group(0)  # Return unchanged if conversion fails

        result = re.sub(r"&#(\d+);", decode_numeric_entity, result)

        # Then decode hex entities: &#xNNNN; or &#xNNNN; (case-insensitive) -> chr(0xNNNN)
        def decode_hex_entity(match: re.Match[str]) -> str:
            hex_str = match.group(1)
            try:
                code_point = int(hex_str, 16)
                return chr(code_point)
            except (ValueError, OverflowError):
                return match.group(0)  # Return unchanged if conversion fails

        result = re.sub(r"&#x([0-9a-fA-F]+);", decode_hex_entity, result)

        return result

    def escape_pipe_in_cell(cell_text: str) -> str:
        """
        Escape literal pipe characters so they do not corrupt the table.
        Only escape pipes that are not already preceded by a backslash (to avoid double-escaping).
        """
        # Replace unescaped pipes: pipes NOT preceded by backslash
        # Use negative lookbehind: (?<!\\) = "not preceded by backslash"
        return re.sub(r"(?<!\\)\|", r"\|", cell_text)

    def extract_cell_text(cell_html: str) -> str:
        """
        Extract plain text from cell HTML: strip dangerous tag content, strip all inner tags,
        decode entities, collapse whitespace.

        Removes entire <script>, <style>, <object>, <embed> elements to prevent embedding
        code or markup. Other tags (b, i, span, etc.) have their delimiters removed but are
        safe because they don't contain executable content. Nested tags like <b><i>text</i></b>
        are handled: all angle-bracket content is removed.
        """
        # Strip dangerous tags entirely: <script>...</script>, <style>...</style>, etc.
        # These must be removed completely, not just their delimiters.
        text = re.sub(r"<(script|style|object|embed)[^>]*>.*?</\1>", "", cell_html, flags=re.DOTALL | re.IGNORECASE)
        # Strip remaining inner tags (everything in angle brackets)
        text = re.sub(r"<[^>]+>", "", text)
        # Decode HTML entities
        text = decode_html_entities_in_cell(text)
        # Collapse whitespace: leading/trailing and internal sequences
        text = " ".join(text.split())
        return text

    def convert_one_table(table_html: str) -> str | None:
        """
        Convert one <table> block to pipe-markdown, or return None if unrecoverable.

        Returns the markdown table (one or more lines) or None if the table is empty/malformed.

        NOTE: This function handles only flat (non-nested) tables. Nested tables are not supported
        because pipe-markdown has no column-spanning mechanism. If nested tables are detected,
        the function will attempt to extract the innermost table's content, which may lose outer
        table structure.
        """
        # Extract <tr> elements
        rows_match = re.findall(r"<tr[^>]*>(.*?)</tr>", table_html, re.DOTALL | re.IGNORECASE)
        if not rows_match:
            return None  # No rows found

        rows: list[list[str]] = []
        has_header = False

        for row_html in rows_match:
            # Extract <th> and <td> cells. <th> tags signal a header row.
            cells_th = re.findall(r"<th[^>]*>(.*?)</th>", row_html, re.DOTALL | re.IGNORECASE)
            cells_td = re.findall(r"<td[^>]*>(.*?)</td>", row_html, re.DOTALL | re.IGNORECASE)

            if cells_th:
                has_header = True
                cells = cells_th
            elif cells_td:
                cells = cells_td
            else:
                continue  # Row with no cells; skip it

            # Extract text from each cell
            cell_texts = [extract_cell_text(cell) for cell in cells]

            # Escape pipes in cell text
            cell_texts = [escape_pipe_in_cell(text) for text in cell_texts]

            # Skip empty rows (all cells blank after extraction)
            if not any(cell_texts):
                continue

            rows.append(cell_texts)

        if not rows:
            return None  # No extractable rows

        # Determine column count from the first row
        col_count = len(rows[0])
        if col_count == 0:
            return None

        # Build markdown table
        lines: list[str] = []

        # If we detected a header, the first row is the header
        if has_header and len(rows) > 0:
            header_row = rows[0]
            # Pad short rows to column count
            header_row = (header_row + [""] * col_count)[:col_count]
            lines.append("| " + " | ".join(header_row) + " |")
            # Add separator row
            lines.append("| " + " | ".join(["---"] * col_count) + " |")
            # Add data rows (starting from the second row)
            for data_row in rows[1:]:
                # Warn if row is longer than expected
                if len(data_row) > col_count:
                    print(
                        f"[unlimited-ocr] warning: row has {len(data_row)} cells, "
                        f"truncating to {col_count} to match table width",
                        file=sys.stderr,
                    )
                data_row = (data_row + [""] * col_count)[:col_count]
                lines.append("| " + " | ".join(data_row) + " |")
        else:
            # No header detected; all rows are data rows
            for data_row in rows:
                # Warn if row is longer than expected
                if len(data_row) > col_count:
                    print(
                        f"[unlimited-ocr] warning: row has {len(data_row)} cells, "
                        f"truncating to {col_count} to match table width",
                        file=sys.stderr,
                    )
                data_row = (data_row + [""] * col_count)[:col_count]
                lines.append("| " + " | ".join(data_row) + " |")

        return "\n".join(lines) if lines else None

    # Main: find all <table> blocks and convert them
    # For nested tables: simple non-greedy matching fails because <table>...<table>...</table>
    # stops at the FIRST </table>, leaving stray HTML. This function finds each <table> and
    # walks forward to its MATCHING </table> by counting nesting depth.

    def find_balanced_table_blocks(text: str) -> list[tuple[int, int]]:
        """
        Find all <table>...</table> blocks by matching balanced opening/closing tags.
        Returns list of (start_pos, end_pos) tuples where start includes '<table', end after '</table>'.
        """
        blocks = []
        pos = 0

        while pos < len(text):
            # Find next <table opening tag
            table_open_match = re.search(r"<table[^>]*>", text[pos:], re.IGNORECASE)
            if not table_open_match:
                break

            table_start = pos + table_open_match.start()
            search_start = pos + table_open_match.end()

            # Count nesting depth: increment on <table>, decrement on </table>
            depth = 1
            search_pos = search_start
            found_close = False

            while search_pos < len(text) and depth > 0:
                # Find the next <table or </table> tag (whichever comes first)
                table_open = re.search(r"<table[^>]*>", text[search_pos:], re.IGNORECASE)
                table_close = re.search(r"</table>", text[search_pos:], re.IGNORECASE)

                # Determine which tag comes first
                if table_close is None:
                    # No more closing tags; this table is unclosed
                    break

                if table_open is None or table_open.start() >= table_close.start():
                    # No opening tag, or closing tag comes first
                    close_pos = search_pos + table_close.end()
                    depth -= 1
                    if depth == 0:
                        blocks.append((table_start, close_pos))
                        pos = close_pos
                        found_close = True
                    search_pos = close_pos
                else:
                    # Opening tag comes before closing tag
                    depth += 1
                    search_pos += table_open.end()

            # If we didn't find a matching close tag, skip past this opening and continue
            if not found_close:
                pos = search_start

        return blocks

    matched_blocks = find_balanced_table_blocks(text)
    result = text

    # Process blocks in reverse order so position shifts don't affect earlier blocks
    for table_start, table_end in reversed(matched_blocks):
        table_html = text[table_start:table_end]
        converted = convert_one_table(table_html)
        if converted is None:
            # Malformed or empty table; skip it with a note to stderr
            print(
                f"[unlimited-ocr] warning: skipped malformed or empty <table>",
                file=sys.stderr,
            )
            result = result[:table_start] + result[table_end:]
        else:
            result = result[:table_start] + converted + result[table_end:]

    return result


def parse_detected_regions(
    text: str, image_size: tuple[int, int] | None
) -> list[DetectedRegion]:
    """Pull every layout block out of the raw output, with pixel boxes when the size is known."""
    regions: list[DetectedRegion] = []
    matches = list(DETECTION_MARKER_PATTERN.finditer(text))

    for index, match in enumerate(matches):
        end_of_block = matches[index + 1].start() if index + 1 < len(matches) else len(text)
        body = text[match.end():end_of_block].strip()

        normalized: tuple[int, int, int, int] | None = None
        raw_bbox = match.group("bbox")
        if raw_bbox:
            numbers = [int(n) for n in re.findall(r"-?\d+", raw_bbox)]
            if len(numbers) >= 4:
                normalized = (numbers[0], numbers[1], numbers[2], numbers[3])

        pixel: tuple[int, int, int, int] | None = None
        if normalized and image_size:
            width, height = image_size
            pixel = (
                round(normalized[0] / DETECTION_COORDINATE_SPACE * width),
                round(normalized[1] / DETECTION_COORDINATE_SPACE * height),
                round(normalized[2] / DETECTION_COORDINATE_SPACE * width),
                round(normalized[3] / DETECTION_COORDINATE_SPACE * height),
            )

        regions.append(
            DetectedRegion(
                category=match.group("category").strip(),
                normalized_bbox=normalized,
                pixel_bbox=pixel,
                text=body,
            )
        )
    return regions


def looks_like_degenerate_repetition(text: str, minimum_length: int = 400) -> bool:
    """
    Flag the failure mode that has no error code: the model decoding one phrase until it runs out.

    Detected structurally rather than by matching a known bad string, so a NEW loop is caught too.
    A short output is never flagged — a two-line formula legitimately repeats very little.
    """
    if len(text) < minimum_length:
        return False
    tail = text[-minimum_length:]
    for span in (8, 12, 20, 35):
        if len(tail) < span * 4:
            continue
        chunk = tail[-span:]
        if chunk.strip() and tail.count(chunk) >= 4:
            return True
    return False


# ─────────────────────────────────────────────────────────────── backends


def detect_available_backends() -> dict[str, dict[str, Any]]:
    """Report what this machine can run, and for anything it cannot, exactly why."""
    report: dict[str, dict[str, Any]] = {}

    mlx: dict[str, Any] = {"available": False, "reason": None, "details": {}}
    if sys.platform != "darwin":
        mlx["reason"] = "MLX requires macOS on Apple Silicon"
    else:
        # Probed with find_spec rather than a bare import, so availability is answered without
        # importing anything, and no unused-import suppression is needed.
        #
        # THE try/except IS LOAD-BEARING, NOT DEFENSIVE PADDING. `find_spec` returns None for a
        # missing TOP-LEVEL module but RAISES ModuleNotFoundError for a submodule whose parent is
        # absent — so `find_spec("mlx.core")` on a Mac without mlx installed raises rather than
        # answering. Uncaught, `doctor` crashed with a traceback on exactly the machine it exists
        # to help: a Mac where the backend is not yet installed. Caught by a test that drove the
        # real command with no backend present.
        missing = []
        for module_name in ("mlx.core", "mlx_vlm", "mlx_vlm.models.unlimited_ocr"):
            try:
                if importlib.util.find_spec(module_name) is None:
                    missing.append(module_name)
            except (ModuleNotFoundError, ValueError):
                missing.append(module_name)
        if missing:
            mlx["reason"] = f"missing module(s): {', '.join(missing)}"
        else:
            mlx_vlm = importlib.import_module("mlx_vlm")

            mlx["available"] = True
            mlx["details"] = {
                "mlx_vlm_version": getattr(mlx_vlm, "__version__", "unknown"),
                # A first-class module, not a DeepSeek-OCR shim. The distinction matters: the
                # shim path is what produces repetitive garbage on mlx-vlm 0.6+.
                "native_unlimited_ocr_module": True,
            }
    report["mlx"] = mlx

    cuda: dict[str, Any] = {"available": False, "reason": None, "details": {}}
    try:
        torch = importlib.import_module("torch")

        if torch.cuda.is_available():
            capability = torch.cuda.get_device_capability(0)
            cuda["available"] = True
            cuda["details"] = {
                "device_name": torch.cuda.get_device_name(0),
                "compute_capability": f"{capability[0]}.{capability[1]}",
                "flash_attention_3_supported": capability[0] >= 9,
                "torch_version": torch.__version__,
            }
            if capability[0] < 9:
                cuda["details"]["attention_backend_note"] = (
                    "compute capability < 9.0 (not Hopper): the upstream README's "
                    "--attention-backend fa3 is NOT supported here; use the transformers path"
                )
        else:
            cuda["reason"] = "torch is installed but reports no CUDA device"
    except ImportError as exc:
        cuda["reason"] = f"torch not importable: {exc}"
    report["cuda"] = cuda

    return report


def resolve_backend(requested: str) -> str:
    """Pick a backend, preferring the local Apple-Silicon path, and explain any refusal."""
    available = detect_available_backends()
    if requested != "auto":
        if not available.get(requested, {}).get("available"):
            reason = available.get(requested, {}).get("reason") or "unavailable"
            raise SystemExit(f"[unlimited-ocr] backend {requested!r} is not usable here: {reason}")
        return requested
    for candidate in ("mlx", "cuda"):
        if available[candidate]["available"]:
            return candidate
    raise SystemExit(
        "[unlimited-ocr] no usable backend. Run `unlimited_ocr.py doctor` for per-backend reasons."
    )


def import_optional_backend_module(module_name: str) -> Any:
    """
    Import a heavy, backend-specific dependency at call time.

    WHY THESE ARE NOT TOP-LEVEL `import` STATEMENTS. `mlx_vlm`, `torch`, `transformers`, `fitz` and
    `PIL` are declared in this file's PEP 723 header and installed by `uv run --script` into a
    throwaway environment. They are NOT dependencies of the cc-skills repository and never will be
    — installing torch into a documentation repo to satisfy a static checker would be absurd.

    Importing them dynamically states the real contract: each is optional, selected at run time by
    which backend the machine actually has. A static `import torch` would claim this file needs
    torch to run, which is false on the Apple-Silicon path, where it needs mlx-vlm and nothing else.

    (It also sidesteps a genuine tooling trap: a PEP 723 header makes `ty` treat the script as its
    own project root, so a repository-level `ty.toml` override does NOT apply to it. Verified on
    ty 0.0.64 — the same file with and without the header behaves differently. See
    references/PITFALLS.md.)
    """
    return importlib.import_module(module_name)


class UnlimitedOcrRunner:
    """Loads the model once and answers many images. Loading dominates a single-image run."""

    def __init__(self, backend: str, model_identifier: str | None, verbose: bool = False) -> None:
        self.backend = backend
        self.verbose = verbose
        self.model_identifier = model_identifier or (
            DEFAULT_MLX_MODEL_IDENTIFIER if backend == "mlx" else DEFAULT_CUDA_MODEL_IDENTIFIER
        )
        self._loaded: Any = None

    def _log(self, message: str) -> None:
        if self.verbose:
            print(f"[unlimited-ocr] {message}", file=sys.stderr)

    def _load(self) -> Any:
        """
        Load the model, keeping its console chatter OFF stdout.

        THIS REDIRECTION IS A CORRECTNESS REQUIREMENT, NOT TIDINESS. Loading prints half a dozen
        tokenizer lines ("Add pad token = …", "Added chat tokens") and mlx-vlm writes them to
        STDOUT. With `--format json` that text lands in front of the JSON document and every
        downstream `json.load` fails on `Expecting value: line 1 column 1`. A CLI whose
        machine-readable mode is corrupted by its own progress logging is not machine-readable, so
        everything the loader says is rerouted to stderr, where progress belongs.
        """
        if self._loaded is not None:
            return self._loaded
        started = time.time()
        with contextlib.redirect_stdout(sys.stderr):
            self._loaded = self._load_backend()
        self._log(f"model loaded in {time.time() - started:.1f}s ({self.model_identifier})")
        return self._loaded

    def _load_backend(self) -> Any:
        if self.backend == "mlx":
            load = import_optional_backend_module("mlx_vlm").load
            load_config = import_optional_backend_module("mlx_vlm.utils").load_config

            model, processor = load(self.model_identifier)
            self._loaded = (model, processor, load_config(self.model_identifier))
        else:
            torch = import_optional_backend_module("torch")
            transformers = import_optional_backend_module("transformers")
            AutoModel = transformers.AutoModel
            AutoTokenizer = transformers.AutoTokenizer

            tokenizer = AutoTokenizer.from_pretrained(
                self.model_identifier, trust_remote_code=True
            )
            model = AutoModel.from_pretrained(
                self.model_identifier,
                trust_remote_code=True,
                use_safetensors=True,
                torch_dtype=torch.bfloat16,
            )
            self._loaded = (model.eval().cuda(), tokenizer, None)
        return self._loaded

    def transcribe_image(
        self,
        image_path: Path,
        prompt_mode: str,
        max_tokens: int,
        repetition_penalty: float,
    ) -> str:
        prompt_text = PROMPT_MODES[prompt_mode]
        if self.backend == "mlx":
            generate = import_optional_backend_module("mlx_vlm").generate
            apply_chat_template = import_optional_backend_module(
                "mlx_vlm.prompt_utils"
            ).apply_chat_template

            model, processor, config = self._load()
            # The chat template is NOT optional: passing the bare prompt string changes the
            # decode trajectory and is one of the ways this model falls into a repetition loop.
            prompt = apply_chat_template(processor, config, prompt_text, num_images=1)
            output = generate(
                model,
                processor,
                prompt=prompt,
                image=str(image_path),
                max_tokens=max_tokens,
                temperature=0.0,
                repetition_penalty=repetition_penalty,
                verbose=False,
            )
            return decode_byte_level_bpe_surface_form(getattr(output, "text", str(output)))

        model, tokenizer, _ = self._load()
        with tempfile.TemporaryDirectory() as output_dir:
            result = model.infer(
                tokenizer,
                prompt=f"<image>{prompt_text}",
                image_file=str(image_path),
                output_path=output_dir,
                base_size=1024,
                image_size=640,
                crop_mode=True,
                max_length=max_tokens,
                no_repeat_ngram_size=35,
                ngram_window=128,
                save_results=False,
            )
        return decode_byte_level_bpe_surface_form(result if isinstance(result, str) else str(result))


# ─────────────────────────────────────────────────────────────── input handling


def render_pdf_pages_to_images(
    pdf_path: Path, output_dir: Path, dpi: int, page_range: str | None
) -> list[Path]:
    """Rasterise a PDF at `dpi`. See DEFAULT_PDF_RENDER_DPI for why the default is not negotiable."""
    fitz = import_optional_backend_module("fitz")

    document = fitz.open(pdf_path)
    selected = _select_page_indices(page_range, document.page_count)
    output_dir.mkdir(parents=True, exist_ok=True)
    matrix = fitz.Matrix(dpi / 72, dpi / 72)

    rendered: list[Path] = []
    for index in selected:
        destination = output_dir / f"page_{index + 1:04d}.png"
        document.load_page(index).get_pixmap(matrix=matrix).save(destination)
        rendered.append(destination)
    document.close()
    return rendered


def _select_page_indices(page_range: str | None, page_count: int) -> list[int]:
    """Parse `--pages` (`3`, `2-7`, `1,4,9-11`) into zero-based indices, clamped to the document."""
    if not page_range:
        return list(range(page_count))
    indices: list[int] = []
    for part in page_range.split(","):
        part = part.strip()
        if not part:
            continue
        if "-" in part:
            start_text, _, end_text = part.partition("-")
            start, end = int(start_text), int(end_text)
            indices.extend(range(start - 1, end))
        else:
            indices.append(int(part) - 1)
    return [i for i in sorted(set(indices)) if 0 <= i < page_count]


def collect_input_images(
    input_path: Path, workspace: Path, dpi: int, page_range: str | None
) -> list[tuple[Path, str, str]]:
    """
    Normalise any input into a list of (image path, human label, output filename stem).

    THE STEM IS CARRIED SEPARATELY, NOT DERIVED FROM THE LABEL. Deriving it once produced silently
    wrong filenames: a PDF page labelled `paper.pdf#page_0001` has, by Path's rules, the suffix
    `.pdf#page_0001` and therefore the stem `paper` — so every page of a PDF wrote to the same
    file and only the last one survived. A label is for humans and may contain anything; a filename
    stem is a separate concern and is now chosen explicitly.
    """
    if input_path.is_dir():
        images = sorted(
            p for p in input_path.iterdir() if p.suffix.lower() in IMAGE_SUFFIXES
        )
        return [(p, p.name, p.stem) for p in images]
    if input_path.suffix.lower() == ".pdf":
        pages = render_pdf_pages_to_images(
            input_path, workspace / f"{input_path.stem}_pages", dpi, page_range
        )
        return [(p, f"{input_path.name}#{p.stem}", p.stem) for p in pages]
    return [(input_path, input_path.name, input_path.stem)]


# ─────────────────────────────────────────────────────────────── subcommands


def command_parse(args: argparse.Namespace) -> int:
    withheld_reason = PROMPT_MODES_WITHHELD_BY_DEFAULT.get(args.prompt_mode)
    if withheld_reason is not None and not args.allow_withheld_prompt_mode:
        print(
            f"[unlimited-ocr] REFUSED: prompt mode {args.prompt_mode!r} "
            f"({PROMPT_MODES[args.prompt_mode]!r})\n"
            f"    {withheld_reason}\n"
            "    Use --prompt-mode free-ocr, or --allow-withheld-prompt-mode to force it anyway.",
            file=sys.stderr,
        )
        return 2

    backend = resolve_backend(args.backend)
    input_path = Path(args.input).expanduser()
    if not input_path.exists():
        print(f"[unlimited-ocr] no such input: {input_path}", file=sys.stderr)
        return 2

    output_dir = Path(args.output).expanduser() if args.output else None
    if output_dir:
        output_dir.mkdir(parents=True, exist_ok=True)

    workspace = output_dir or Path(os.environ.get("TMPDIR", "/tmp")) / "unlimited-ocr-work"
    workspace.mkdir(parents=True, exist_ok=True)

    images = collect_input_images(input_path, workspace, args.dpi, args.pages)
    if not images:
        print(f"[unlimited-ocr] nothing to parse under {input_path}", file=sys.stderr)
        return 2

    runner = UnlimitedOcrRunner(backend, args.model, verbose=not args.quiet)
    results: list[ParseResult] = []

    for image_path, label, output_stem in images:
        started = time.time()
        raw = runner.transcribe_image(
            image_path, args.prompt_mode, args.max_tokens, args.repetition_penalty
        )
        elapsed = time.time() - started

        text = raw
        if args.collapse_math_spacing:
            text = collapse_math_character_spacing(text)
        markdown = strip_detection_markers(text) if args.strip_det else text
        if args.table_format == "pipe":
            markdown = convert_html_tables_to_pipe_markdown(markdown)

        # An unreadable image costs only the PIXEL boxes; the normalised boxes and all text
        # survive, so this degrades rather than fails. Narrowed to the errors PIL actually
        # raises (UnidentifiedImageError subclasses OSError) instead of catching everything —
        # a broad except here would swallow a genuine bug in region parsing.
        size: tuple[int, int] | None = None
        try:
            Image = import_optional_backend_module("PIL.Image")

            with Image.open(image_path) as handle:
                size = handle.size
        except (OSError, ValueError) as exc:
            if not args.quiet:
                print(
                    f"[unlimited-ocr] {label}: no pixel boxes ({exc})",
                    file=sys.stderr,
                )

        result = ParseResult(
            source_path=str(image_path),
            backend=backend,
            model_identifier=runner.model_identifier,
            prompt_mode=args.prompt_mode,
            raw_text=raw,
            markdown=markdown,
            regions=parse_detected_regions(text, size),
            elapsed_seconds=round(elapsed, 3),
            degenerate_repetition_suspected=looks_like_degenerate_repetition(raw),
        )
        results.append(result)

        if not args.quiet:
            flag = "  ⚠ REPETITION SUSPECTED" if result.degenerate_repetition_suspected else ""
            print(
                f"[unlimited-ocr] {label}: {len(result.regions)} region(s), "
                f"{len(markdown)} chars, {elapsed:.1f}s{flag}",
                file=sys.stderr,
            )

        if output_dir:
            (output_dir / f"{output_stem}.md").write_text(markdown, encoding="utf-8")

    if args.format == "json":
        print(json.dumps([r.to_json() for r in results], ensure_ascii=False, indent=2))
    elif args.format == "raw":
        print("\n\n".join(r.raw_text for r in results))
    else:
        print("\n\n".join(r.markdown for r in results))

    if output_dir:
        (output_dir / "parse_report.json").write_text(
            json.dumps([r.to_json() for r in results], ensure_ascii=False, indent=2),
            encoding="utf-8",
        )

    return 1 if any(r.degenerate_repetition_suspected for r in results) else 0


def command_segment(args: argparse.Namespace) -> int:
    """
    Crop one image into its detected layout regions.

    THIS EXISTS BECAUSE THE MODEL WILL NOT DESCRIBE A CHART. It localises one and emits no text.
    On a nine-panel figure that is nine perfect boxes and zero characters — useless as a
    transcription, excellent as a segmentation. Cropping each region and handing the pieces to a
    model that DOES describe images turns the limitation into a pre-processing step: a describer
    given one chart at a time beats the same describer given a nine-panel collage.
    """
    Image = import_optional_backend_module("PIL.Image")

    backend = resolve_backend(args.backend)
    image_path = Path(args.input).expanduser()
    if not image_path.exists():
        print(f"[unlimited-ocr] no such image: {image_path}", file=sys.stderr)
        return 2

    output_dir = Path(args.output).expanduser()
    output_dir.mkdir(parents=True, exist_ok=True)

    runner = UnlimitedOcrRunner(backend, args.model, verbose=not args.quiet)
    raw = runner.transcribe_image(
        image_path, args.prompt_mode, args.max_tokens, args.repetition_penalty
    )

    with Image.open(image_path) as handle:
        size = handle.size
        regions = parse_detected_regions(raw, size)

        wanted = (
            {c.strip() for c in args.categories.split(",")} if args.categories else None
        )
        manifest: list[dict[str, Any]] = []
        kept = 0

        for index, region in enumerate(regions):
            if wanted and region.category not in wanted:
                continue
            if not region.pixel_bbox:
                continue
            x0, y0, x1, y1 = region.pixel_bbox
            # Grow the box before clamping. The model's boxes hug the plotted area and routinely
            # clip axis tick labels and captions sitting just outside it — verified on a
            # nine-panel figure where every crop lost its x-axis labels at padding 0. Those labels
            # are exactly what a downstream describer needs to read the chart, so a few pixels of
            # slack is worth far more than a pixel-exact box.
            x0, x1 = x0 - args.pad_pixels, x1 + args.pad_pixels
            y0, y1 = y0 - args.pad_pixels, y1 + args.pad_pixels
            x0, x1 = max(0, min(x0, x1)), min(size[0], max(x0, x1))
            y0, y1 = max(0, min(y0, y1)), min(size[1], max(y0, y1))
            width, height = x1 - x0, y1 - y0
            if width < args.min_pixels or height < args.min_pixels:
                continue

            destination = output_dir / f"{image_path.stem}_{index:03d}_{region.category}.png"
            handle.crop((x0, y0, x1, y1)).save(destination)
            kept += 1
            manifest.append(
                {
                    "index": index,
                    "category": region.category,
                    "normalized_bbox": list(region.normalized_bbox or ()),
                    "pixel_bbox": [x0, y0, x1, y1],
                    "path": str(destination),
                    "text": region.text,
                }
            )

    (output_dir / "segments.json").write_text(
        json.dumps(
            {
                "source": str(image_path),
                "source_size": list(size),
                "backend": backend,
                "regions_detected": len(regions),
                "regions_written": kept,
                "segments": manifest,
            },
            ensure_ascii=False,
            indent=2,
        ),
        encoding="utf-8",
    )

    if not args.quiet:
        print(
            f"[unlimited-ocr] {len(regions)} region(s) detected, {kept} written to {output_dir}",
            file=sys.stderr,
        )
    print(json.dumps(manifest, ensure_ascii=False, indent=2))
    return 0


def command_doctor(args: argparse.Namespace) -> int:
    report = detect_available_backends()
    if args.format == "json":
        print(json.dumps(report, indent=2))
    else:
        print("unlimited-ocr backend report")
        print("=" * 60)
        for name, info in report.items():
            state = "AVAILABLE" if info["available"] else "unavailable"
            print(f"  {name:<6} {state}")
            if info.get("reason"):
                print(f"         reason: {info['reason']}")
            for key, value in (info.get("details") or {}).items():
                print(f"         {key}: {value}")
    return 0 if any(i["available"] for i in report.values()) else 1


def command_spec(args: argparse.Namespace) -> int:
    """Emit the CLI contract as JSON — the machine-readable SSoT an agent introspects."""
    spec = {
        "$schema": "https://json-schema.org/draft/2020-12/schema",
        "name": "unlimited_ocr",
        "version": SCRIPT_VERSION,
        "description": "Document parsing with baidu/Unlimited-OCR on a local backend.",
        "model_identifiers": {
            "mlx": DEFAULT_MLX_MODEL_IDENTIFIER,
            "cuda": DEFAULT_CUDA_MODEL_IDENTIFIER,
        },
        "prompt_modes": PROMPT_MODES,
        "prompt_modes_withheld_by_default": PROMPT_MODES_WITHHELD_BY_DEFAULT,
        "detection_coordinate_space": DETECTION_COORDINATE_SPACE,
        "defaults": {
            "pdf_render_dpi": DEFAULT_PDF_RENDER_DPI,
            "repetition_penalty": DEFAULT_REPETITION_PENALTY,
            "max_tokens": DEFAULT_MAX_TOKENS,
        },
        "subcommands": {
            "parse": {
                "summary": "Parse an image, PDF or directory into markdown plus layout regions.",
                "flags": {
                    "--input": "path to an image, a PDF, or a directory of images (required)",
                    "--output": "directory for per-input .md files and parse_report.json",
                    "--backend": "auto | mlx | cuda",
                    "--model": "override the HuggingFace model identifier",
                    "--prompt-mode": " | ".join(PROMPT_MODES),
                    "--max-tokens": "decode ceiling per image",
                    "--repetition-penalty": "MLX-only scalar loop defence",
                    "--dpi": "PDF rasterisation DPI; 300 is a correctness setting",
                    "--pages": "page selection for PDFs, e.g. 1,4,9-11",
                    "--format": "markdown | json | raw",
                    "--strip-det": "remove <|det|> markers, keeping block structure",
                    "--collapse-math-spacing": "rejoin 'c u r p d f' into 'curpdf' inside math",
                    "--table-format": "pipe | html (default: pipe); convert HTML <table> to pipe-markdown",
                    "--allow-withheld-prompt-mode": "force a measured-broken prompt mode",
                    "--quiet": "suppress progress on stderr",
                },
                "exit_codes": {
                    "0": "parsed, no degenerate repetition detected",
                    "1": "parsed, but repetition suspected in at least one output",
                    "2": "usage or input error, including a withheld prompt mode",
                },
            },
            "segment": {
                "summary": "Crop an image into its detected layout regions.",
                "flags": {
                    "--input": "image path (required)",
                    "--output": "directory for crops and segments.json (required)",
                    "--categories": "comma-separated filter, e.g. chart,table",
                    "--min-pixels": "discard crops narrower or shorter than this",
                    "--pad-pixels": "grow each crop on all sides before clamping (default 12)",
                },
            },
            "doctor": {"summary": "Report usable backends and why the others are not."},
            "spec": {"summary": "Emit this contract as JSON."},
        },
    }
    print(json.dumps(spec, ensure_ascii=False, indent=2))
    return 0


# ─────────────────────────────────────────────────────────────── entry point


def build_argument_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="unlimited_ocr.py",
        description="Document parsing with baidu/Unlimited-OCR (MLX on Apple Silicon, CUDA on NVIDIA).",
    )
    parser.add_argument("--version", action="version", version=SCRIPT_VERSION)
    subparsers = parser.add_subparsers(dest="command", required=True)

    def add_shared_model_flags(target: argparse.ArgumentParser) -> None:
        target.add_argument("--backend", default="auto", choices=["auto", "mlx", "cuda"])
        target.add_argument("--model", default=None, help="override the model identifier")
        target.add_argument(
            "--prompt-mode", default="free-ocr", choices=sorted(PROMPT_MODES), dest="prompt_mode"
        )
        target.add_argument("--max-tokens", type=int, default=DEFAULT_MAX_TOKENS, dest="max_tokens")
        target.add_argument(
            "--repetition-penalty",
            type=float,
            default=DEFAULT_REPETITION_PENALTY,
            dest="repetition_penalty",
        )
        target.add_argument("--quiet", action="store_true")

    parse_cmd = subparsers.add_parser("parse", help="parse an image, PDF, or directory")
    parse_cmd.add_argument("--input", required=True)
    parse_cmd.add_argument("--output", default=None)
    parse_cmd.add_argument("--dpi", type=int, default=DEFAULT_PDF_RENDER_DPI)
    parse_cmd.add_argument("--pages", default=None)
    parse_cmd.add_argument("--format", default="markdown", choices=["markdown", "json", "raw"])
    parse_cmd.add_argument("--strip-det", action="store_true", dest="strip_det")
    parse_cmd.add_argument(
        "--collapse-math-spacing", action="store_true", dest="collapse_math_spacing"
    )
    parse_cmd.add_argument(
        "--allow-withheld-prompt-mode",
        action="store_true",
        dest="allow_withheld_prompt_mode",
        help="force a prompt mode that measurement showed to be broken (see spec for the reason)",
    )
    parse_cmd.add_argument(
        "--table-format",
        default="pipe",
        choices=["pipe", "html"],
        dest="table_format",
        help="convert HTML <table> markup to pipe-markdown (pipe) or leave as HTML (html)",
    )
    add_shared_model_flags(parse_cmd)
    parse_cmd.set_defaults(handler=command_parse)

    segment_cmd = subparsers.add_parser("segment", help="crop an image into layout regions")
    segment_cmd.add_argument("--input", required=True)
    segment_cmd.add_argument("--output", required=True)
    segment_cmd.add_argument("--categories", default=None)
    segment_cmd.add_argument("--min-pixels", type=int, default=16, dest="min_pixels")
    segment_cmd.add_argument(
        "--pad-pixels",
        type=int,
        default=DEFAULT_SEGMENT_PADDING_PIXELS,
        dest="pad_pixels",
        help="grow each crop on all sides before clamping, to keep axis labels and captions",
    )
    add_shared_model_flags(segment_cmd)
    segment_cmd.set_defaults(handler=command_segment)

    doctor_cmd = subparsers.add_parser("doctor", help="report usable backends")
    doctor_cmd.add_argument("--format", default="text", choices=["text", "json"])
    doctor_cmd.set_defaults(handler=command_doctor)

    spec_cmd = subparsers.add_parser("spec", help="emit the machine-readable CLI contract")
    spec_cmd.set_defaults(handler=command_spec)

    return parser


def main(argv: Iterable[str] | None = None) -> int:
    args = build_argument_parser().parse_args(list(argv) if argv is not None else None)
    return args.handler(args)


if __name__ == "__main__":
    raise SystemExit(main())
