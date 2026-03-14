#!/usr/bin/env python3
# /// script
# requires-python = ">=3.13"
# dependencies = ["iterm2"]
# ///
"""
Cron Countdown Status Bar Component for iTerm2

Real-time countdown to next Claude Code cron job execution.
Reads ~/.claude/state/active-crons.json (written by cron-tracker.ts hook).
Refreshes every 1 second via iTerm2 Python API.

Format:  5f8a3ada(*/30 * * * *) → 14m32s
Urgency: ⚠ prefix when < 1 min remaining, disappears when no active crons.

Installation:
  ln -s /path/to/cc-skills/plugins/statusline-tools/scripts/iterm2-cron-countdown.py \
        ~/Library/Application\ Support/iTerm2/Scripts/AutoLaunch/cron-countdown.py

Requirements:
  iTerm2 Python API enabled: Preferences > General > Magic > Enable Python API
  Active crons in: ~/.claude/state/active-crons.json
"""

from __future__ import annotations

import asyncio
import json
import re
from datetime import datetime
from pathlib import Path

import iterm2

CRON_STATE_FILE = Path.home() / ".claude" / "state" / "active-crons.json"
COMPONENT_ID = "com.example.cron-countdown"


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
            return ""

        parts = []
        for job in crons:
            job_id = (job.get("id") or "?")[:8]
            schedule = job.get("schedule", "")
            secs = next_cron_secs(schedule)
            if secs is None:
                parts.append(f"{job_id}({schedule}) → ?")
            else:
                cd = format_countdown(secs)
                prefix = "⚠ " if secs < 60 else ""
                parts.append(f"{prefix}{job_id}({schedule}) → {cd}")

        return "  |  ".join(parts)

    await component.async_register(connection, cron_countdown)


iterm2.run_forever(main)
