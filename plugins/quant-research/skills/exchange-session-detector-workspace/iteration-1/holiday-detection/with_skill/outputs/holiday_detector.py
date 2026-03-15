"""
Holiday detection for crypto feature engineering pipelines.

Adds is_us_holiday, is_uk_holiday, and is_major_holiday columns to time-series
DataFrames using the `exchange_calendars` library (no manual holiday lists).

The exchange_calendars library bundles calendar data for 50+ exchanges and is
maintained by the community. Holiday schedules are updated with each library
release — no network calls at runtime, no manual list maintenance.

Architecture:
    exchange_calendars (XNYS, XLON)
        -> regular_holidays + adhoc_holidays
        -> set-based date lookup (O(1) per row)
        -> vectorized .isin() or .map() on DataFrame

Usage:
    from holiday_detector import HolidayDetector

    detector = HolidayDetector()

    # Add holiday columns to any DataFrame with a UTC timestamp column
    df = detector.add_holiday_flags(df, ts_column="timestamp")

    # Or check a single date
    detector.is_us_holiday(date(2024, 12, 25))  # True (Christmas)
    detector.is_uk_holiday(date(2024, 12, 25))  # True (Christmas)
    detector.is_major_holiday(date(2024, 12, 25))  # True (both closed)

    detector.is_us_holiday(date(2024, 8, 26))  # False
    detector.is_uk_holiday(date(2024, 8, 26))  # True (UK Summer Bank Holiday)
    detector.is_major_holiday(date(2024, 8, 26))  # False (NYSE open)

Dependencies:
    pip install exchange_calendars pandas
    # exchange_calendars is ~10MB, no heavy deps beyond pandas/numpy
    # Calendar data is bundled — no network calls at runtime

Why exchange_calendars over manual lists:
    1. Covers ALL official NYSE/LSE closures including ad-hoc (e.g., state funerals)
    2. Forward-looking: future holidays are pre-computed by calendar rules
    3. Maintained upstream — new releases pick up schedule changes
    4. ISO 10383 MIC codes (XNYS, XLON) — unambiguous exchange identification
"""

from __future__ import annotations

from datetime import date
from typing import Set

import exchange_calendars as xcals
import pandas as pd


class HolidayDetector:
    """
    Detect US (NYSE) and UK (LSE) holidays for feature engineering.

    Uses exchange_calendars library with ISO 10383 MIC codes:
        - XNYS: New York Stock Exchange (US holidays)
        - XLON: London Stock Exchange (UK holidays)

    Holiday sets include both regular holidays (recurring annual) and
    ad-hoc holidays (one-off closures like state funerals, weather events).

    The "major holiday" flag fires when BOTH NYSE and LSE are closed on the
    same date — these days tend to have measurably lower crypto volume and
    wider spreads since institutional market makers are offline on both sides
    of the Atlantic.
    """

    def __init__(self) -> None:
        self._nyse_cal = xcals.get_calendar("XNYS")
        self._lse_cal = xcals.get_calendar("XLON")

    def _get_holidays(
        self, calendar: xcals.ExchangeCalendar, start: date, end: date
    ) -> Set[date]:
        """
        Collect all holidays (regular + ad-hoc) for a calendar in date range.

        Regular holidays: recurring annual closures (Christmas, Thanksgiving, etc.)
        Ad-hoc holidays: one-off closures (state funerals, weather, etc.)

        Both are needed for complete coverage. Weekend dates are excluded —
        these sets contain only dates that WOULD be trading days but are closed.
        """
        holidays: Set[date] = set()

        # Regular holidays (rule-based, recurring)
        regular = calendar.regular_holidays.holidays(
            start=start, end=end, return_name=False
        )
        holidays.update(pd.to_datetime(h).date() for h in regular)

        # Ad-hoc holidays (one-off closures)
        for adhoc_date in calendar.adhoc_holidays:
            d = pd.to_datetime(adhoc_date).date()
            if start <= d <= end:
                holidays.add(d)

        return holidays

    def get_us_holidays(self, start: date, end: date) -> Set[date]:
        """Get all NYSE closure dates in range (excludes weekends)."""
        return self._get_holidays(self._nyse_cal, start, end)

    def get_uk_holidays(self, start: date, end: date) -> Set[date]:
        """Get all LSE closure dates in range (excludes weekends)."""
        return self._get_holidays(self._lse_cal, start, end)

    def get_major_holidays(self, start: date, end: date) -> Set[date]:
        """Get dates where BOTH NYSE and LSE are closed."""
        return self.get_us_holidays(start, end) & self.get_uk_holidays(start, end)

    def is_us_holiday(self, d: date) -> bool:
        """Check if a single date is a NYSE holiday."""
        return d in self._get_holidays(self._nyse_cal, d, d)

    def is_uk_holiday(self, d: date) -> bool:
        """Check if a single date is an LSE holiday."""
        return d in self._get_holidays(self._lse_cal, d, d)

    def is_major_holiday(self, d: date) -> bool:
        """Check if a single date is a holiday for BOTH NYSE and LSE."""
        return self.is_us_holiday(d) and self.is_uk_holiday(d)

    def add_holiday_flags(
        self,
        df: pd.DataFrame,
        ts_column: str = "timestamp",
    ) -> pd.DataFrame:
        """
        Add is_us_holiday, is_uk_holiday, and is_major_holiday columns.

        Args:
            df: DataFrame with a UTC timestamp column (timezone-aware or naive).
                Works with any granularity (tick, second, minute, hourly, daily).
            ts_column: Name of the timestamp column. Must be datetime-like.

        Returns:
            Same DataFrame with three new integer columns (0 or 1):
                - is_us_holiday: 1 if the date is an NYSE closure
                - is_uk_holiday: 1 if the date is an LSE closure
                - is_major_holiday: 1 if BOTH NYSE and LSE are closed

        Notes:
            - Weekend dates are NOT flagged as holidays (they are simply
              non-trading days). Only official exchange closures on weekdays
              are flagged. This is intentional — for crypto, weekends have
              their own volume patterns distinct from holidays.
            - For crypto feature engineering, the date is extracted in UTC.
              If your timestamps are timezone-naive, they are assumed UTC.

        Example:
            >>> df = pd.DataFrame({
            ...     "timestamp": pd.to_datetime([
            ...         "2024-12-25 14:30:00",  # Christmas
            ...         "2024-12-26 14:30:00",  # Boxing Day (UK only)
            ...         "2024-12-27 14:30:00",  # Normal day
            ...     ]),
            ... })
            >>> df = detector.add_holiday_flags(df)
            >>> df[["is_us_holiday", "is_uk_holiday", "is_major_holiday"]].values
            array([[1, 1, 1],   # Christmas: both closed
                   [0, 1, 0],   # Boxing Day: UK only
                   [0, 0, 0]])  # Normal trading day
        """
        ts = df[ts_column]
        dates = ts.dt.date

        start_date = dates.min()
        end_date = dates.max()

        # Pre-compute holiday sets for entire date range (O(1) per lookup)
        us_holidays = self.get_us_holidays(start_date, end_date)
        uk_holidays = self.get_uk_holidays(start_date, end_date)

        # Vectorized flag assignment
        df["is_us_holiday"] = dates.map(lambda d: int(d in us_holidays))
        df["is_uk_holiday"] = dates.map(lambda d: int(d in uk_holidays))
        df["is_major_holiday"] = (
            (df["is_us_holiday"] == 1) & (df["is_uk_holiday"] == 1)
        ).astype(int)

        return df


# ---------------------------------------------------------------------------
# Standalone demonstration
# ---------------------------------------------------------------------------

if __name__ == "__main__":
    print("Holiday Detector — exchange_calendars-based\n")

    detector = HolidayDetector()

    # --- Single-date checks ---
    test_dates = [
        (date(2024, 1, 1), "New Year's Day"),
        (date(2024, 1, 15), "MLK Day (US only)"),
        (date(2024, 3, 29), "Good Friday (US + UK)"),
        (date(2024, 5, 6), "Early May Bank Holiday (UK only)"),
        (date(2024, 5, 27), "Spring Bank Holiday (UK only)"),
        (date(2024, 7, 4), "US Independence Day"),
        (date(2024, 8, 26), "UK Summer Bank Holiday"),
        (date(2024, 11, 28), "US Thanksgiving"),
        (date(2024, 12, 25), "Christmas Day"),
        (date(2024, 12, 26), "Boxing Day (UK only)"),
    ]

    print("Single-date checks:")
    print(f"{'Date':<12} {'Description':<30} {'US':>4} {'UK':>4} {'Major':>6}")
    print("-" * 60)
    for d, desc in test_dates:
        us = detector.is_us_holiday(d)
        uk = detector.is_uk_holiday(d)
        major = detector.is_major_holiday(d)
        print(f"{d}  {desc:<30} {int(us):>4} {int(uk):>4} {int(major):>6}")

    # --- DataFrame demonstration ---
    print("\n\nDataFrame demonstration (2024 full year, minute-level):")

    # Simulate crypto OHLCV data at 1-hour intervals for one year
    timestamps = pd.date_range("2024-01-01", "2024-12-31 23:00", freq="1h", tz="UTC")
    df = pd.DataFrame({
        "timestamp": timestamps,
        "close": 42000.0,  # placeholder
    })

    df = detector.add_holiday_flags(df)

    # Summary statistics
    daily = df.groupby(df["timestamp"].dt.date).first()
    us_count = daily["is_us_holiday"].sum()
    uk_count = daily["is_uk_holiday"].sum()
    major_count = daily["is_major_holiday"].sum()

    print(f"  Total days:      {len(daily)}")
    print(f"  US holidays:     {us_count}")
    print(f"  UK holidays:     {uk_count}")
    print(f"  Major holidays:  {major_count} (both NYSE + LSE closed)")

    # Show all major holidays
    major_days = daily[daily["is_major_holiday"] == 1].index
    print(f"\n  Major holidays in 2024 (both NYSE and LSE closed):")
    for d in major_days:
        print(f"    {d}")

    # Show US-only and UK-only holidays
    us_only = daily[(daily["is_us_holiday"] == 1) & (daily["is_uk_holiday"] == 0)].index
    uk_only = daily[(daily["is_uk_holiday"] == 1) & (daily["is_us_holiday"] == 0)].index
    print(f"\n  US-only holidays ({len(us_only)}):")
    for d in us_only:
        print(f"    {d}")
    print(f"\n  UK-only holidays ({len(uk_only)}):")
    for d in uk_only:
        print(f"    {d}")
