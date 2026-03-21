#!/usr/bin/env python3
"""Supertonic TTS helper — reads text from stdin, synthesizes via M3 voice, plays via afplay.

Usage:
    echo "Hello world" | TTS_SPEED=1.25 python3 tts_supertonic_speak.py
    pbpaste | uv run --python 3.13 --with supertonic python3 tts_supertonic_speak.py

Environment variables:
    TTS_SPEED  - Speech speed multiplier (default: 1.25, range: 0.5-3.0)
"""

import contextlib
import os
import subprocess
import sys
import tempfile


def main():
    text = sys.stdin.read().strip()
    if not text:
        sys.exit(0)

    speed = float(os.environ.get("TTS_SPEED", "1.25"))

    from supertonic import TTS

    tts = TTS(auto_download=True)
    style = tts.get_voice_style("M3")
    wav, _duration = tts.synthesize(text, style, speed=speed)

    with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as f:
        tmp_path = f.name
    try:
        tts.save_audio(wav, tmp_path)
        subprocess.run(["afplay", tmp_path], check=True)
    finally:
        with contextlib.suppress(OSError):
            os.unlink(tmp_path)


if __name__ == "__main__":
    main()
