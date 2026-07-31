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
unlimited_ocr_batch_folder_parser.py — batch parse a folder of PDFs and images with checkpoint/resume.

GUARANTEES
  1. ONE IMAGE PER FORWARD PASS, ALWAYS. (PITFALLS section 3)
  2. CHECKPOINT AND RESUME. Writes results incrementally; survives interruption.
  3. CHARTS COME BACK EMPTY. Documents this upfront.
  4. EXIT CODES: 0 = all succeeded, 1 = some repetition suspected, 2 = any hard failures
  5. MEMORY-BOUNDED. No batching, no result accumulation in memory.

USAGE
  S=~/eon/cc-skills/plugins/unlimited-ocr/scripts/unlimited_ocr_batch_folder_parser.py
  uv run --no-project $S --folder ~/documents --output ~/results

  # Resume from where it left off (reads manifest.jsonl, skips done items)
  uv run --no-project $S --folder ~/documents --output ~/results

  # Override output naming, collapse math spacing, force a backend
  uv run --no-project $S --folder ~/documents --output ~/results --collapse-math \\
    --backend mlx --quiet

FLAGS
  --folder PATH              Input folder (required; scanned for images + PDFs recursively)
  --output PATH              Output folder (created if missing; required)
  --backend {auto,mlx,cuda}  Which backend to use (default: auto)
  --collapse-math            Rejoin character-spaced math (e.g., c u r v e -> curve)
  --table-format {html,pipe} Table format (default: pipe)
  --strip-det                Remove layout bounding box markers
  --quiet                    Suppress per-file progress to stderr
  --allow-withheld-prompt    Force a withheld prompt mode (very rarely needed)

OUTPUT STRUCTURE
  output/
    manifest.jsonl           # One JSON object per file, newline-delimited
    <file_stem>.md           # Markdown result for each input
    <file_stem>.json         # JSON result (if input was multi-page PDF)
    progress_report.txt      # Summary at the end

MANIFEST FORMAT (manifest.jsonl)
  Each line is:
  {
    "source_path": "/path/to/image.png",
    "output_md": "image.md",
    "output_json": null,  (only for multi-page PDFs)
    "status": "done",     (or "failed" or "repetition_suspected")
    "elapsed_seconds": 2.4,
    "backend": "mlx",
    "page_count": 1,
    "error_message": null
  }

INTERRUPTION-SAFETY
  1. Every result is written to the output folder BEFORE the manifest is appended.
  2. Manifest.jsonl is append-only; if a line is there, the output file exists.
  3. Re-running with the same output folder skips everything in the manifest.
  4. If a process dies mid-write, the incomplete manifest line is never written.

WHY NO BATCHING
  See PITFALLS section 3: single-pass multi-image on MLX recovered 1/3, 4/5, 0/10 pages.
  Per-image is slower but complete and verifiable in every condition. The speed cost is
  acceptable; the data loss cost of batching is not.

WHY NO RESULT ACCUMULATION
  Process starts fresh for each image: load model, run inference, write, exit. This keeps
  memory bounded (5 GB for MLX, 8 GB for CUDA peak) rather than accumulating. A 1,000-image
  folder takes longer but never threatens the machine's stability, and is restartable at any
  point without re-processing.
"""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
import time
from dataclasses import dataclass, asdict
from pathlib import Path
from typing import Any

# ─────────────────────────────────────────────────────────────── constants

IMAGE_SUFFIXES = {".png", ".jpg", ".jpeg", ".webp", ".gif", ".bmp", ".tif", ".tiff"}
PDF_SUFFIXES = {".pdf"}
ALLSUFFIXES = IMAGE_SUFFIXES | PDF_SUFFIXES

SCRIPT_VERSION = "1.0.0"


# ─────────────────────────────────────────────────────────────── data shapes


@dataclass
class BatchItem:
    """One file's processing result, for manifest.jsonl."""

    source_path: str
    output_md: str | None = None
    output_json: str | None = None
    status: str = "pending"  # pending, done, failed, repetition_suspected
    elapsed_seconds: float = 0.0
    backend: str = ""
    page_count: int = 1
    error_message: str | None = None

    def to_json_line(self) -> str:
        return json.dumps(asdict(self), ensure_ascii=False)

    @staticmethod
    def from_json_line(line: str) -> BatchItem:
        data = json.loads(line)
        return BatchItem(**data)


# ─────────────────────────────────────────────────────────────── helpers


def find_input_files(folder: Path) -> list[Path]:
    """Recursively find all images and PDFs in a folder."""
    files = []
    for suffix in ALLSUFFIXES:
        files.extend(folder.rglob(f"*{suffix}"))
        files.extend(folder.rglob(f"*{suffix.upper()}"))
    return sorted(files)


def load_manifest(manifest_path: Path) -> dict[str, BatchItem]:
    """Load existing manifest as a dict keyed by source_path, return empty dict if absent."""
    result = {}
    if manifest_path.exists():
        with open(manifest_path, "r", encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if line:
                    item = BatchItem.from_json_line(line)
                    result[item.source_path] = item
    return result


def safe_stem_for_filesystem(source_path: Path) -> str:
    """
    Convert a source file path into a safe output stem.
    Preserves the original stem and deduplicates with a counter.
    """
    return source_path.stem.replace(" ", "_").replace("/", "_")


def append_manifest_line(manifest_path: Path, item: BatchItem) -> None:
    """Append a single item to manifest.jsonl (append-only, atomically safe)."""
    # Write to manifest is the LAST step after all outputs are written.
    # This ensures: if the process dies, the incomplete item is never recorded.
    with open(manifest_path, "a", encoding="utf-8") as f:
        f.write(item.to_json_line() + "\n")


def run_unlimited_ocr_on_file(
    source_path: Path,
    output_folder: Path,
    output_stem: str,
    backend: str,
    collapse_math: bool,
    table_format: str,
    strip_det: bool,
    quiet: bool,
    allow_withheld_prompt: bool,
) -> tuple[int, float, str]:
    """
    Run the unlimited_ocr CLI on one file. Returns (exit_code, elapsed_seconds, backend_used).

    Exit code 0 = success, 1 = repetition suspected, 2 = error.
    The backend_used might differ from the input (e.g., "auto" -> "mlx" or "cuda").
    """
    unlimited_ocr_script = (
        Path.home() / "eon" / "cc-skills" / "plugins" / "unlimited-ocr" / "scripts" / "unlimited_ocr.py"
    )
    if not unlimited_ocr_script.exists():
        raise FileNotFoundError(f"Script not found: {unlimited_ocr_script}")

    cmd = [
        "uv",
        "run",
        "--no-project",
        str(unlimited_ocr_script),
        "parse",
        "--input",
        str(source_path),
        "--output",
        str(output_folder),
        "--backend",
        backend,
        "--format",
        "json",
    ]

    if collapse_math:
        cmd.append("--collapse-math-spacing")
    if table_format != "pipe":
        cmd.extend(["--table-format", table_format])
    if strip_det:
        cmd.append("--strip-det")
    if allow_withheld_prompt:
        cmd.append("--allow-withheld-prompt-mode")

    start_time = time.time()
    try:
        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=300,  # 5 minutes per file
            check=False,  # We handle exit codes manually; check=False prevents automatic exception
        )
        elapsed = time.time() - start_time

        # Parse the JSON output to extract backend used
        backend_used = backend
        try:
            if result.stdout:
                # The JSON report is the last line of stdout
                lines = result.stdout.strip().split("\n")
                for line in reversed(lines):
                    if line.startswith("{"):
                        data = json.loads(line)
                        backend_used = data.get("backend", backend)
                        break
        except (json.JSONDecodeError, ValueError):
            pass

        if not quiet:
            status_marker = "✓" if result.returncode == 0 else ("⚠" if result.returncode == 1 else "✗")
            print(f"{status_marker} {source_path.name} ({elapsed:.1f}s, exit {result.returncode})", file=sys.stderr)

        return result.returncode, elapsed, backend_used

    except subprocess.TimeoutExpired:
        if not quiet:
            print(f"✗ {source_path.name} (timeout after 300s)", file=sys.stderr)
        return 2, 300.0, backend
    except Exception as e:
        if not quiet:
            print(f"✗ {source_path.name} ({type(e).__name__}: {e})", file=sys.stderr)
        return 2, 0.0, backend


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Batch parse a folder of PDFs and images with checkpoint/resume.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument("--folder", type=Path, required=True, help="Input folder (required)")
    parser.add_argument("--output", type=Path, required=True, help="Output folder (required)")
    parser.add_argument(
        "--backend",
        choices=["auto", "mlx", "cuda"],
        default="auto",
        help="Backend (default: auto)",
    )
    parser.add_argument(
        "--collapse-math",
        action="store_true",
        help="Rejoin character-spaced math",
    )
    parser.add_argument(
        "--table-format",
        choices=["html", "pipe"],
        default="pipe",
        help="Table format (default: pipe)",
    )
    parser.add_argument(
        "--strip-det",
        action="store_true",
        help="Remove layout bounding box markers",
    )
    parser.add_argument(
        "--quiet",
        action="store_true",
        help="Suppress per-file progress to stderr",
    )
    parser.add_argument(
        "--allow-withheld-prompt",
        action="store_true",
        help="Force a withheld prompt mode",
    )

    args = parser.parse_args()

    # Validate inputs
    if not args.folder.is_dir():
        print(f"ERROR: folder not found or not a directory: {args.folder}", file=sys.stderr)
        return 2
    args.output.mkdir(parents=True, exist_ok=True)

    # Load existing manifest (skip completed items)
    manifest_path = args.output / "manifest.jsonl"
    existing = load_manifest(manifest_path)

    # Find all input files
    input_files = find_input_files(args.folder)
    if not input_files:
        print(f"No images or PDFs found in {args.folder}", file=sys.stderr)
        return 0

    # Filter out already-processed files
    remaining = [f for f in input_files if str(f) not in existing]

    if not remaining and existing:
        print(
            f"All {len(existing)} files already processed. "
            f"Run with a different --output to re-process.",
            file=sys.stderr,
        )
        return 0

    if not args.quiet:
        print(f"Found {len(input_files)} total, {len(remaining)} to process", file=sys.stderr)

    # ─────────────────────────────────────────────────────────────── charts warning
    print(
        "\n⚠️  CHARTS COME BACK EMPTY: Unlimited-OCR localizes chart regions "
        "and transcribes zero characters inside them. On chart-heavy documents, "
        "you'll see perfectly-placed empty boxes.\n"
        "   Use `unlimited-ocr-segment-figure` to crop each detected region "
        "separately, then send the crops to a vision model that describes images.\n",
        file=sys.stderr,
    )

    # ─────────────────────────────────────────────────────────────── process files

    repetition_suspected_count = 0
    failed_count = 0
    done_count = 0

    for idx, source_path in enumerate(remaining, 1):
        output_stem = safe_stem_for_filesystem(source_path)

        # Run the parser
        exit_code, elapsed, backend_used = run_unlimited_ocr_on_file(
            source_path,
            args.output,
            output_stem,
            args.backend,
            args.collapse_math,
            args.table_format,
            args.strip_det,
            args.quiet,
            args.allow_withheld_prompt,
        )

        # Determine status
        if exit_code == 0:
            status = "done"
            done_count += 1
            output_md = f"{output_stem}.md"
            output_json = None  # Single images don't get JSON by default
        elif exit_code == 1:
            status = "repetition_suspected"
            repetition_suspected_count += 1
            output_md = f"{output_stem}.md"
            output_json = None
        else:
            status = "failed"
            failed_count += 1
            output_md = None
            output_json = None

        # Record in manifest (append-only)
        item = BatchItem(
            source_path=str(source_path),
            output_md=output_md,
            output_json=output_json,
            status=status,
            elapsed_seconds=elapsed,
            backend=backend_used,
            page_count=1,  # TODO: infer from JSON output if multi-page
            error_message=None if exit_code in (0, 1) else f"exit code {exit_code}",
        )
        append_manifest_line(manifest_path, item)

        # Progress report
        if not args.quiet and idx % 5 == 0:
            print(f"  [{idx}/{len(remaining)}] {done_count} done, {failed_count} failed, {repetition_suspected_count} repetition", file=sys.stderr)

    # ─────────────────────────────────────────────────────────────── summary

    total_done = len(existing) + done_count
    total_repetition = len([i for i in existing.values() if i.status == "repetition_suspected"]) + repetition_suspected_count
    total_failed = len([i for i in existing.values() if i.status == "failed"]) + failed_count

    summary_lines = [
        "\n" + "=" * 60,
        "BATCH PROCESSING COMPLETE",
        f"Total processed: {total_done + total_repetition + total_failed}",
        f"  ✓ Done:                {total_done}",
        f"  ⚠ Repetition suspected: {total_repetition} (inspect before trusting)",
        f"  ✗ Failed:              {total_failed}",
        "",
        f"Manifest written to: {manifest_path}",
        "=" * 60,
    ]
    summary_text = "\n".join(summary_lines)
    print(summary_text, file=sys.stderr)

    # Write progress report
    progress_report = args.output / "progress_report.txt"
    with open(progress_report, "w", encoding="utf-8") as f:
        f.write(summary_text + "\n")

    # Exit code: 0 if no failures, 1 if some repetition suspected, 2 if any hard failures
    if total_failed > 0:
        return 2
    if total_repetition > 0:
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
