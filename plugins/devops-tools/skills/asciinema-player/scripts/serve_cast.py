#!/usr/bin/env python3
# /// script
# dependencies = []
# ///
"""
Generate asciinema player HTML and start local HTTP server.

Usage:
    uv run serve_cast.py <cast_file> [--port 8000] [--speed 1] [--theme monokai]

Example:
    uv run serve_cast.py ~/recordings/session.cast
    uv run serve_cast.py recording.cast --port 8080 --speed 1.5
"""
import argparse
import os
import socket
import subprocess
import sys
from pathlib import Path


def find_template() -> Path:
    """Find player-template.html relative to this script."""
    script_dir = Path(__file__).parent.parent
    template = script_dir / "assets" / "player-template.html"
    if not template.exists():
        # Fallback to CLAUDE_PLUGIN_ROOT if available
        plugin_root = os.environ.get("CLAUDE_PLUGIN_ROOT")
        if plugin_root:
            template = Path(plugin_root) / "skills" / "asciinema-player" / "assets" / "player-template.html"
        if not template.exists():
            raise FileNotFoundError(f"Template not found: {template}")
    return template


def is_port_in_use(port: int) -> bool:
    """Check if port is already in use."""
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        return s.connect_ex(("localhost", port)) == 0


def generate_player_html(
    cast_file: Path,
    output_dir: Path,
    speed: float = 1.0,
    idle_limit: int = 2,
    theme: str = "monokai",
) -> Path:
    """Generate player.html from template."""
    template = find_template()
    template_content = template.read_text()

    # Calculate relative path from output_dir to cast_file
    cast_relative = os.path.relpath(cast_file, output_dir)
    recording_name = cast_file.name

    html_content = (
        template_content.replace("{{RECORDING_NAME}}", recording_name)
        .replace("{{CAST_FILE}}", cast_relative)
        .replace("{{SPEED}}", str(speed))
        .replace("{{IDLE_TIME_LIMIT}}", str(idle_limit))
        .replace("{{THEME}}", theme)
    )

    output_file = output_dir / "player.html"
    output_file.write_text(html_content)
    return output_file


def start_server(directory: Path, port: int) -> None:
    """Start HTTP server in background."""
    # Start in background using nohup
    cmd = f"cd {directory} && nohup python3 -m http.server {port} > /dev/null 2>&1 &"
    subprocess.run(cmd, shell=True)
    print(f"Started HTTP server on port {port}")


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Generate asciinema player and start local server"
    )
    parser.add_argument("cast_file", help="Path to .cast file")
    parser.add_argument("--port", type=int, default=8000, help="HTTP server port")
    parser.add_argument("--speed", type=float, default=1.0, help="Playback speed")
    parser.add_argument("--idle-limit", type=int, default=2, help="Max idle seconds")
    parser.add_argument("--theme", default="monokai", help="Color theme")
    parser.add_argument(
        "--output-dir", help="Output directory (default: same as cast file)"
    )

    args = parser.parse_args()

    cast_path = Path(args.cast_file).resolve()
    if not cast_path.exists():
        print(f"Error: Cast file not found: {cast_path}", file=sys.stderr)
        return 1

    if cast_path.suffix != ".cast":
        print(f"Warning: File does not have .cast extension: {cast_path}")

    output_dir = Path(args.output_dir) if args.output_dir else cast_path.parent
    output_dir = output_dir.resolve()

    # Generate player.html
    print(f"Generating player for: {cast_path.name}")
    player_html = generate_player_html(
        cast_path, output_dir, args.speed, args.idle_limit, args.theme
    )
    print(f"Created: {player_html}")

    # Check/start server
    if is_port_in_use(args.port):
        print(f"HTTP server already running on port {args.port}")
    else:
        start_server(output_dir, args.port)

    # Output clickable URL
    url = f"http://localhost:{args.port}/player.html"
    print()
    print("=" * 50)
    print(f"Open in browser: {url}")
    print("=" * 50)

    return 0


if __name__ == "__main__":
    sys.exit(main())
