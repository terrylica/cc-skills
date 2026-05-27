#!/usr/bin/env python3
# /// script
# requires-python = ">=3.14"
# dependencies = ["iterm2"]
# ///
"""
Cron Countdown Status Bar Component for iTerm2

Real-time countdown to next Claude Code cron job execution.
Reads ~/.claude/state/active-crons.json (written by cron-tracker.ts hook).
Refreshes every 1 second via iTerm2 Python API.

Format:  5f8a3ada(*/30 * * * *) → 14m32s
Urgency: ⚠ prefix when < 1 min remaining, disappears when no active crons.

Sound alerts (fire once per cron cycle, reset after execution):
  5 min  → Ping  × 1  (heads-up)
  1 min  → Glass × 2  (urgent)
  30 sec → Basso × 3  (critical)

Installation:
  ln -s /path/to/cc-skills/plugins/statusline-tools/scripts/iterm2-cron-countdown.py \
        "$HOME/Library/Application Support/iTerm2/Scripts/AutoLaunch/cron-countdown.py"

Requirements:
  iTerm2 Python API enabled: Preferences > General > Magic > Enable Python API
  Active crons in: ~/.claude/state/active-crons.json
"""

from __future__ import annotations

import asyncio
import json
import re
import subprocess
from datetime import datetime
from pathlib import Path
from threading import Thread

import iterm2

CRON_STATE_FILE = Path.home() / ".claude" / "state" / "active-crons.json"
COMPONENT_ID = "com.terryli.cron-countdown"

# Sound files for each urgency level
SOUNDS = {
    "5min":  ("/System/Library/Sounds/Ping.aiff",  1, 0.0),   # file, count, gap_secs
    "1min":  ("/System/Library/Sounds/Glass.aiff", 2, 0.5),
    "30sec": ("/System/Library/Sounds/Basso.aiff", 3, 0.3),
}

# Thresholds in seconds — must match SOUNDS keys
THRESHOLDS = [
    (300, "5min"),
    (60,  "1min"),
    (30,  "30sec"),
]

# Per-job alert state: job_id → set of threshold keys already fired this cycle
_alerted: dict[str, set[str]] = {}


def next_cron_secs(schedule: str) -> int | None:
    """Return seconds until next execution for simple minute-based cron expressions.

    Supports: */N, M, M1,M2, * in minute field.
    Requires hour/dom/month/dow to all be wildcards.
    Returns None for unsupported expressions (e.g. specific hours/days).
    """
    parts = schedule.strip().split()
    if len(parts) != 5:
        return None
    min_field, hour_field, dom_field, mon_field, dow_field = parts
    if not all(f == "*" for f in [hour_field, dom_field, mon_field, dow_field]):
        return None

    now = datetime.now()
    elapsed = now.minute * 60 + now.second

    # */N — every N minutes
    m = re.match(r"^\*/(\d+)$", min_field)
    if m:
        n = int(m.group(1))
        interval = n * 60
        return interval - (elapsed % interval)

    # M or M1,M2,... — specific minute(s)
    if re.match(r"^[\d,]+$", min_field):
        targets = [int(t) for t in min_field.split(",")]
        best: int | None = None
        for t in targets:
            diff = (t - now.minute) * 60 - now.second
            if diff <= 0:
                diff += 3600
            if best is None or diff < best:
                best = diff
        return best

    # * — every minute
    if min_field == "*":
        return 60 - now.second

    return None


def format_countdown(secs: int) -> str:
    h, remainder = divmod(secs, 3600)
    m, s = divmod(remainder, 60)
    if h > 0:
        return f"{h}h{m}m{s:02d}s"
    return f"{m}m{s:02d}s"


def read_active_crons() -> list[dict]:
    try:
        data = CRON_STATE_FILE.read_text()
        return json.loads(data)
    except (FileNotFoundError, json.JSONDecodeError):
        return []


def play_sound_bg(sound_file: str, count: int, gap: float) -> None:
    """Play a sound file N times with a gap, in a background thread (non-blocking)."""
    def _play() -> None:
        for i in range(count):
            if i > 0 and gap > 0:
                import time
                time.sleep(gap)
            subprocess.run(["afplay", sound_file], check=False)
    Thread(target=_play, daemon=True).start()


async def main(connection: iterm2.Connection) -> None:
    component = iterm2.StatusBarComponent(
        short_description="Cron Countdown",
        detailed_description="Real-time countdown to next Claude Code cron job execution",
        exemplar="5f8a3ada(*/30 * * * *) → 14m32s",
        update_cadence=1,
        identifier=COMPONENT_ID,
        knobs=[],
    )

    @iterm2.StatusBarRPC
    async def cron_countdown(knobs):
        crons = read_active_crons()
        if not crons:
            _alerted.clear()
            return ""

        parts = []
        active_ids = {(job.get("id") or "")[:8] for job in crons}

        # Drop state for crons that no longer exist
        for stale in set(_alerted) - active_ids:
            del _alerted[stale]

        for job in crons:
            job_id = (job.get("id") or "?")[:8]
            schedule = job.get("schedule", "")
            secs = next_cron_secs(schedule)

            if secs is None:
                parts.append(f"{job_id}({schedule}) → ?")
                continue

            cd = format_countdown(secs)
            prefix = "⚠ " if secs < 60 else ""
            parts.append(f"{prefix}{job_id}({schedule}) → {cd}")

            # Reset alerts when countdown is well above the highest threshold
            # (means the cron just fired and the cycle restarted)
            if secs > THRESHOLDS[0][0] + 10:
                _alerted.pop(job_id, None)

            alerted = _alerted.setdefault(job_id, set())

            # Check each threshold in descending order; fire only once per cycle
            for threshold_secs, key in THRESHOLDS:
                if secs <= threshold_secs and key not in alerted:
                    alerted.add(key)
                    sound_file, count, gap = SOUNDS[key]
                    play_sound_bg(sound_file, count, gap)
                    break  # only one threshold fires per second

        return "  |  ".join(parts)

    await component.async_register(connection, cron_countdown)


iterm2.run_forever(main)
