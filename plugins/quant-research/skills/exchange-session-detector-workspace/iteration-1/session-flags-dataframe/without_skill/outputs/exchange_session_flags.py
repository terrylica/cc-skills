"""
Add exchange session boolean columns to a BTCUSDT trades DataFrame.

Handles DST transitions correctly for NYSE, LSE, and Tokyo (TSE).
Excludes Tokyo's lunch break (11:30-12:30 JST).
Vectorized implementation -- no per-row .apply().

Usage:
    import pandas as pd
    df = pd.read_parquet("btcusdt_trades_2024.parquet")  # must have 'ts' column (UTC)
    df = add_session_flags(df)
    # New columns: is_nyse, is_lse, is_tse
"""

from __future__ import annotations

import pandas as pd


def add_session_flags(df: pd.DataFrame, ts_col: str = "ts") -> pd.DataFrame:
    """
    Add boolean session columns (is_nyse, is_lse, is_tse) to a DataFrame.

    Parameters
    ----------
    df : pd.DataFrame
        Must contain a UTC timestamp column (datetime64 or tz-aware UTC).
    ts_col : str
        Name of the timestamp column. Default: 'ts'.

    Returns
    -------
    pd.DataFrame
        The input DataFrame with three new boolean columns appended.

    Notes
    -----
    Session definitions (local times, regular trading hours only):

    - **NYSE**: 09:30-16:00 America/New_York (Mon-Fri)
      DST begins 2nd Sunday of March, ends 1st Sunday of November.

    - **LSE**: 08:00-16:30 Europe/London (Mon-Fri)
      DST begins last Sunday of March, ends last Sunday of October.

    - **TSE (Tokyo)**: 09:00-11:30 and 12:30-15:00 Asia/Tokyo (Mon-Fri)
      Japan does not observe DST. Lunch break 11:30-12:30 excluded.

    The approach: convert the UTC timestamp column to each exchange's local
    timezone, then use vectorized .dt accessors to check day-of-week, hour,
    and minute. This avoids per-row Python calls entirely.
    """
    ts = df[ts_col]

    # Ensure we have a proper datetime series in UTC
    if ts.dtype == "object":
        ts = pd.to_datetime(ts, utc=True)
    elif not hasattr(ts.dt, "tz") or ts.dt.tz is None:
        ts = ts.dt.tz_localize("UTC")

    # --- NYSE (America/New_York) ---
    ny = ts.dt.tz_convert("America/New_York")
    ny_weekday = ny.dt.weekday  # 0=Mon .. 4=Fri
    ny_time = ny.dt.hour * 60 + ny.dt.minute  # minutes since midnight
    # 09:30 = 570, 16:00 = 960 (exclusive -- last trade at 15:59)
    df["is_nyse"] = (ny_weekday < 5) & (ny_time >= 570) & (ny_time < 960)

    # --- LSE (Europe/London) ---
    ldn = ts.dt.tz_convert("Europe/London")
    ldn_weekday = ldn.dt.weekday
    ldn_time = ldn.dt.hour * 60 + ldn.dt.minute
    # 08:00 = 480, 16:30 = 990
    df["is_lse"] = (ldn_weekday < 5) & (ldn_time >= 480) & (ldn_time < 990)

    # --- TSE / Tokyo (Asia/Tokyo, no DST) ---
    tyo = ts.dt.tz_convert("Asia/Tokyo")
    tyo_weekday = tyo.dt.weekday
    tyo_time = tyo.dt.hour * 60 + tyo.dt.minute
    # Morning session: 09:00 (540) - 11:30 (690)
    # Afternoon session: 12:30 (750) - 15:00 (900)
    tyo_morning = (tyo_time >= 540) & (tyo_time < 690)
    tyo_afternoon = (tyo_time >= 750) & (tyo_time < 900)
    df["is_tse"] = (tyo_weekday < 5) & (tyo_morning | tyo_afternoon)

    return df


# ---------------------------------------------------------------------------
# Self-contained demo / smoke test
# ---------------------------------------------------------------------------
if __name__ == "__main__":
    import numpy as np

    # Generate ~500K minute-level timestamps covering all of 2024
    rng = pd.date_range("2024-01-01", "2024-12-31 23:59", freq="min", tz="UTC")
    np.random.seed(42)
    idx = np.sort(np.random.choice(len(rng), size=500_000, replace=False))
    df = pd.DataFrame({"ts": rng[idx], "price": np.random.uniform(40_000, 70_000, 500_000)})

    print(f"Input shape: {df.shape}")
    df = add_session_flags(df)
    print(f"Output shape: {df.shape}")
    print(f"\nSession counts:")
    print(f"  NYSE active: {df['is_nyse'].sum():,}")
    print(f"  LSE  active: {df['is_lse'].sum():,}")
    print(f"  TSE  active: {df['is_tse'].sum():,}")

    # --- DST sanity checks ---
    # 2024 US DST: clocks spring forward 2024-03-10, fall back 2024-11-03
    # 2024 UK DST: clocks spring forward 2024-03-31, fall back 2024-10-27

    # NYSE opens at 14:30 UTC in winter, 13:30 UTC in summer
    winter_open = df[df["ts"] == "2024-01-15 14:30:00+00:00"]
    summer_open = df[df["ts"] == "2024-07-15 13:30:00+00:00"]
    if len(winter_open):
        assert winter_open["is_nyse"].iloc[0], "NYSE should be open at 14:30 UTC in Jan (09:30 ET)"
    if len(summer_open):
        assert summer_open["is_nyse"].iloc[0], "NYSE should be open at 13:30 UTC in Jul (09:30 ET)"

    # LSE opens at 08:00 UTC in winter, 07:00 UTC in summer (BST)
    winter_lse = df[df["ts"] == "2024-01-15 08:00:00+00:00"]
    summer_lse = df[df["ts"] == "2024-07-15 07:00:00+00:00"]
    if len(winter_lse):
        assert winter_lse["is_lse"].iloc[0], "LSE should be open at 08:00 UTC in Jan"
    if len(summer_lse):
        assert summer_lse["is_lse"].iloc[0], "LSE should be open at 07:00 UTC in Jul (08:00 BST)"

    # Tokyo lunch break: 11:45 JST = 02:45 UTC (JST = UTC+9, no DST)
    lunch_check = df[df["ts"] == "2024-06-03 02:45:00+00:00"]  # Monday
    if len(lunch_check):
        assert not lunch_check["is_tse"].iloc[0], "TSE should be closed during lunch (11:45 JST)"

    # Tokyo afternoon session: 13:00 JST = 04:00 UTC
    afternoon_check = df[df["ts"] == "2024-06-03 04:00:00+00:00"]
    if len(afternoon_check):
        assert afternoon_check["is_tse"].iloc[0], "TSE should be open at 13:00 JST"

    # Weekend check (2024-01-06 is Saturday)
    sat_rows = df[df["ts"].dt.date == pd.Timestamp("2024-01-06").date()]
    if len(sat_rows):
        assert not sat_rows["is_nyse"].any(), "NYSE closed on Saturday"
        assert not sat_rows["is_lse"].any(), "LSE closed on Saturday"
        assert not sat_rows["is_tse"].any(), "TSE closed on Saturday"

    print("\nAll DST and session boundary checks passed.")
