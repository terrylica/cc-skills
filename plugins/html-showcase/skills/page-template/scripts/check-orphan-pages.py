#!/usr/bin/env python3
"""Orphan-page detector for static HTML mini-sites.

Walks every ``*.html`` under a given directory, parses ``<a href>`` links,
builds a directed reachability graph, and reports any HTML file not reachable
from the entry-point ``index.html``. Designed to complement Lychee, which
catches broken links but does not flag unreferenced files.

Usage::

    python scripts/check-orphan-pages.py docs/contractor-site/

Exit codes:
    0  No orphans (all HTML reachable from index.html)
    1  One or more orphan files detected
    2  Bad invocation (missing arg, no index.html, etc.)

Implementation notes:
    Pure stdlib only (html.parser) so it has no install footprint and works
    against any clean Python 3.10+ environment. Run-time on a 100-page site
    is well under a second.
"""

from __future__ import annotations

import argparse
import sys
from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import urlparse


class _AnchorExtractor(HTMLParser):
    """Collect every ``href`` value from ``<a>`` tags in document order."""

    def __init__(self) -> None:
        super().__init__()
        self.hrefs: list[str] = []

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        if tag.lower() != "a":
            return
        for name, value in attrs:
            if name.lower() == "href" and value:
                self.hrefs.append(value)


def _is_local_html(href: str) -> bool:
    """True if href targets a local HTML file (not an absolute URL or anchor only)."""
    parsed = urlparse(href)
    if parsed.scheme in {"http", "https", "mailto", "tel", "javascript"}:
        return False
    path = parsed.path
    if not path:
        return False  # anchor-only ('#section') doesn't claim ownership of a file
    return path.endswith(".html") or path.endswith("/")


def _resolve(source: Path, href: str, root: Path) -> Path | None:
    """Resolve ``href`` (relative to ``source``) to an absolute path inside ``root``.

    Returns None if the resolved path escapes ``root`` or doesn't end in .html
    after directory-index normalization.
    """
    parsed = urlparse(href)
    raw_path = parsed.path or ""
    if raw_path.startswith("/"):
        # Treat absolute paths as rooted at site root
        target = (root / raw_path.lstrip("/")).resolve()
    else:
        target = (source.parent / raw_path).resolve()

    # Directory references default to /index.html
    if target.is_dir() or raw_path.endswith("/"):
        target = target / "index.html"

    try:
        target.relative_to(root.resolve())
    except ValueError:
        return None  # escaped the site root

    return target if target.suffix == ".html" else None


def _collect_html_files(root: Path) -> set[Path]:
    return {p.resolve() for p in root.rglob("*.html") if p.is_file()}


def _build_outgoing(html_files: set[Path], root: Path) -> dict[Path, set[Path]]:
    out: dict[Path, set[Path]] = {p: set() for p in html_files}
    for source in html_files:
        try:
            text = source.read_text(encoding="utf-8")
        except UnicodeDecodeError:
            text = source.read_text(encoding="utf-8", errors="replace")
        parser = _AnchorExtractor()
        parser.feed(text)
        for href in parser.hrefs:
            if not _is_local_html(href):
                continue
            target = _resolve(source, href, root)
            if target and target in html_files:
                out[source].add(target)
    return out


def _walk_reachable(
    entry: Path,
    outgoing: dict[Path, set[Path]],
) -> set[Path]:
    reachable: set[Path] = {entry}
    stack: list[Path] = [entry]
    while stack:
        node = stack.pop()
        for child in outgoing.get(node, ()):
            if child not in reachable:
                reachable.add(child)
                stack.append(child)
    return reachable


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n", 1)[0])
    parser.add_argument(
        "directory",
        type=Path,
        help="Site root containing index.html and other *.html pages",
    )
    parser.add_argument(
        "--entry",
        default="index.html",
        help="Entry file relative to <directory> (default: index.html)",
    )
    args = parser.parse_args()

    root = args.directory.resolve()
    if not root.is_dir():
        print(f"FATAL: {root} is not a directory", file=sys.stderr)
        return 2

    entry = (root / args.entry).resolve()
    if not entry.is_file():
        print(f"FATAL: entry file not found: {entry}", file=sys.stderr)
        return 2

    html_files = _collect_html_files(root)
    if not html_files:
        print(f"No HTML files under {root}", file=sys.stderr)
        return 0

    outgoing = _build_outgoing(html_files, root)
    reachable = _walk_reachable(entry, outgoing)
    orphans = sorted(html_files - reachable)

    print(f"Checked {len(html_files)} HTML file(s) under {root}")
    print(f"Entry: {entry.relative_to(root)}")
    print(f"Reachable: {len(reachable)}")

    if orphans:
        print(f"\nORPHAN PAGES ({len(orphans)}):")
        for o in orphans:
            print(f"  - {o.relative_to(root)}")
        print(
            "\nFix: add an <a href> from at least one reachable page, or "
            "delete the orphan file.",
            file=sys.stderr,
        )
        return 1

    print("\nOK — every HTML file is reachable from the entry page.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
