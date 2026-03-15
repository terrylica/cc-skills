"""
Holiday detection for crypto time-series feature engineering.

Adds is_us_holiday, is_uk_holiday, and is_major_holiday columns to a
DataFrame indexed or columned by date/datetime. No manual holiday lists
-- stays current via two maintained libraries:

  - exchange_calendars: actual NYSE (XNYS) and LSE (XLON) closure days,
    including ad-hoc closures (e.g., 2025-01-09 National Day of Mourning).
  - holidays: US/UK statutory public holidays for weekend-aware features.

Recommended approach: use exchange_calendars for the primary flags, because
exchange closures are what actually affect trading volume and liquidity
(which is what matters for crypto prediction -- TradFi session overlap drives
crypto volume patterns). The holidays library is included as a complementary
source for statutory public holidays that may fall on weekends.

Dependencies:
    pip install exchange-calendars holidays pandas

Usage:
    import pandas as pd
    from holiday_detection import add_holiday_features

    df = pd.DataFrame({
        "timestamp": pd.date_range("2024-01-01", "2024-12-31", freq="h"),
        "price": ...,
    })
    df = add_holiday_features(df, date_column="timestamp")
"""

from __future__ import annotations

import functools
from datetime import date
from typing import Literal

import pandas as pd


# ---------------------------------------------------------------------------
# Core: exchange_calendars (recommended for trading features)
# ---------------------------------------------------------------------------

@functools.lru_cache(maxsize=4)
def _get_exchange_calendar(exchange: str):
    """Cached calendar instantiation. exchange_calendars objects are heavy."""
    import exchange_calendars as xcals
    return xcals.get_calendar(exchange)


def get_exchange_holidays(
    exchange: str,
    start: str | date,
    end: str | date,
) -> pd.DatetimeIndex:
    """
    Return business days when the exchange is closed (holidays only,
    excluding regular weekends).

    Parameters
    ----------
    exchange : str
        MIC code. 'XNYS' for NYSE, 'XLON' for LSE.
    start, end : str or date
        Date range (inclusive).

    Returns
    -------
    pd.DatetimeIndex
        Dates when the exchange is closed on what would otherwise be a
        business day.
    """
    cal = _get_exchange_calendar(exchange)
    start_ts = pd.Timestamp(start)
    end_ts = pd.Timestamp(end)
    sessions = cal.sessions_in_range(start_ts, end_ts)
    all_bdays = pd.bdate_range(start_ts, end_ts)
    return all_bdays.difference(sessions)


def get_exchange_early_closes(
    exchange: str,
    start: str | date,
    end: str | date,
) -> pd.DatetimeIndex:
    """
    Return dates with early (shortened) trading sessions.

    Useful as a secondary feature: early-close days often show reduced
    volume in the afternoon session, which bleeds into crypto markets.

    Examples for NYSE: July 3, Black Friday, Christmas Eve.
    """
    cal = _get_exchange_calendar(exchange)
    ec = cal.early_closes
    start_ts = pd.Timestamp(start)
    end_ts = pd.Timestamp(end)
    return ec[(ec >= start_ts) & (ec <= end_ts)]


# ---------------------------------------------------------------------------
# Complementary: holidays library (statutory public holidays)
# ---------------------------------------------------------------------------

def get_statutory_holidays(
    country: Literal["US", "UK"],
    start: str | date,
    end: str | date,
) -> dict[date, str]:
    """
    Return {date: holiday_name} for statutory public holidays.

    This covers ALL public holidays including those on weekends (which
    exchange_calendars omits since the exchange is already closed).
    Useful when you want a weekend holiday flag too.
    """
    import holidays as hol

    start_d = pd.Timestamp(start).date()
    end_d = pd.Timestamp(end).date()

    year_start = start_d.year
    year_end = end_d.year
    years = range(year_start, year_end + 1)

    if country == "US":
        cal = hol.US(years=years)
    elif country == "UK":
        cal = hol.UK(years=years)
    else:
        raise ValueError(f"Unsupported country: {country}")

    return {d: name for d, name in sorted(cal.items()) if start_d <= d <= end_d}


# ---------------------------------------------------------------------------
# Main API: add_holiday_features()
# ---------------------------------------------------------------------------

def add_holiday_features(
    df: pd.DataFrame,
    date_column: str | None = None,
    include_early_close: bool = True,
    include_statutory: bool = False,
    include_holiday_names: bool = False,
) -> pd.DataFrame:
    """
    Add holiday feature columns to a DataFrame.

    Columns added:
        is_us_holiday     : bool - NYSE closed on this business day
        is_uk_holiday     : bool - LSE closed on this business day
        is_major_holiday  : bool - BOTH NYSE and LSE closed (same day)
        is_us_early_close : bool - NYSE has shortened session (if include_early_close=True)
        is_uk_early_close : bool - LSE has shortened session (if include_early_close=True)
        us_holiday_name   : str  - name of US statutory holiday (if include_holiday_names=True)
        uk_holiday_name   : str  - name of UK statutory holiday (if include_holiday_names=True)
        is_us_statutory   : bool - US public holiday per law (if include_statutory=True)
        is_uk_statutory   : bool - UK public holiday per law (if include_statutory=True)

    Parameters
    ----------
    df : pd.DataFrame
        Input DataFrame. Must have either a DatetimeIndex or a column
        specified by date_column containing dates/datetimes.
    date_column : str or None
        Column name containing dates. If None, uses the DataFrame index.
    include_early_close : bool
        Whether to add early-close flags (default True).
    include_statutory : bool
        Whether to add statutory holiday flags from the holidays library.
        These differ from exchange closures: statutory holidays include
        days like Veterans Day and Columbus Day where NYSE is open.
    include_holiday_names : bool
        Whether to add string columns with holiday names.

    Returns
    -------
    pd.DataFrame
        Copy of input with holiday columns added.

    Examples
    --------
    >>> df = pd.DataFrame({"ts": pd.date_range("2025-01-01", "2025-01-31", freq="h"), "v": 1})
    >>> result = add_holiday_features(df, date_column="ts")
    >>> result[result["is_us_holiday"]]["ts"].dt.date.unique()
    array([datetime.date(2025, 1, 1), datetime.date(2025, 1, 9),
           datetime.date(2025, 1, 20)])
    """
    df = df.copy()

    # Extract dates
    if date_column is not None:
        dates = pd.to_datetime(df[date_column])
    elif isinstance(df.index, pd.DatetimeIndex):
        dates = df.index
    else:
        raise ValueError(
            "Provide date_column or use a DatetimeIndex. "
            f"Got index type: {type(df.index)}"
        )

    date_only = dates.dt.normalize() if hasattr(dates, "dt") else dates.normalize()
    start = date_only.min()
    end = date_only.max()

    # --- Exchange closures (the primary signal) ---
    nyse_holidays = get_exchange_holidays("XNYS", start, end)
    lse_holidays = get_exchange_holidays("XLON", start, end)

    nyse_set = set(nyse_holidays.normalize())
    lse_set = set(lse_holidays.normalize())

    df["is_us_holiday"] = date_only.isin(nyse_set)
    df["is_uk_holiday"] = date_only.isin(lse_set)
    df["is_major_holiday"] = df["is_us_holiday"] & df["is_uk_holiday"]

    # --- Early closes ---
    if include_early_close:
        nyse_early = get_exchange_early_closes("XNYS", start, end)
        lse_early = get_exchange_early_closes("XLON", start, end)
        df["is_us_early_close"] = date_only.isin(set(nyse_early.normalize()))
        df["is_uk_early_close"] = date_only.isin(set(lse_early.normalize()))

    # --- Statutory holidays (from holidays library) ---
    if include_statutory or include_holiday_names:
        us_stat = get_statutory_holidays("US", start, end)
        uk_stat = get_statutory_holidays("UK", start, end)

        if include_statutory:
            us_stat_dates = {pd.Timestamp(d) for d in us_stat}
            uk_stat_dates = {pd.Timestamp(d) for d in uk_stat}
            df["is_us_statutory"] = date_only.isin(us_stat_dates)
            df["is_uk_statutory"] = date_only.isin(uk_stat_dates)

        if include_holiday_names:
            us_map = {pd.Timestamp(d): name for d, name in us_stat.items()}
            uk_map = {pd.Timestamp(d): name for d, name in uk_stat.items()}
            df["us_holiday_name"] = [us_map.get(d, "") for d in date_only]
            df["uk_holiday_name"] = [uk_map.get(d, "") for d in date_only]

    return df


# ---------------------------------------------------------------------------
# Standalone utility: holiday calendar summary
# ---------------------------------------------------------------------------

def holiday_summary(year: int) -> pd.DataFrame:
    """
    Generate a summary table of all NYSE and LSE holidays for a given year.

    Useful for eyeballing and verification.

    Returns
    -------
    pd.DataFrame with columns: date, weekday, nyse_closed, lse_closed,
        both_closed, us_holiday_name, uk_holiday_name
    """
    start = f"{year}-01-01"
    end = f"{year}-12-31"

    nyse_holidays = get_exchange_holidays("XNYS", start, end)
    lse_holidays = get_exchange_holidays("XLON", start, end)

    all_dates = nyse_holidays.union(lse_holidays).sort_values()

    us_stat = get_statutory_holidays("US", start, end)
    uk_stat = get_statutory_holidays("UK", start, end)

    rows = []
    for d in all_dates:
        dd = d.date()
        rows.append({
            "date": dd,
            "weekday": dd.strftime("%A"),
            "nyse_closed": d in nyse_holidays,
            "lse_closed": d in lse_holidays,
            "both_closed": d in nyse_holidays and d in lse_holidays,
            "us_name": us_stat.get(dd, ""),
            "uk_name": uk_stat.get(dd, ""),
        })

    return pd.DataFrame(rows)


# ---------------------------------------------------------------------------
# Demo / self-test
# ---------------------------------------------------------------------------

if __name__ == "__main__":
    print("=" * 72)
    print("Holiday Detection for Crypto Feature Engineering")
    print("=" * 72)

    # --- 1. Summary table for 2025 ---
    print("\n--- 2025 Exchange Holiday Summary ---\n")
    summary = holiday_summary(2025)
    print(summary.to_string(index=False))

    # --- 2. Apply to hourly time-series ---
    print("\n--- Feature engineering on hourly data (Jan 2025) ---\n")
    df = pd.DataFrame({
        "timestamp": pd.date_range("2025-01-01", "2025-01-31", freq="h"),
        "price": range(721),
    })
    df = add_holiday_features(df, date_column="timestamp", include_holiday_names=True)

    # Show rows where any holiday flag is True
    mask = df["is_us_holiday"] | df["is_uk_holiday"]
    holiday_rows = df[mask].groupby(df["timestamp"].dt.date).first()
    cols = [
        "is_us_holiday", "is_uk_holiday", "is_major_holiday",
        "is_us_early_close", "is_uk_early_close",
        "us_holiday_name", "uk_holiday_name",
    ]
    print(holiday_rows[cols].to_string())

    # --- 3. Verify major holidays (both closed) ---
    print("\n--- Major holidays (both NYSE + LSE closed) in 2025 ---")
    both = summary[summary["both_closed"]]
    for _, row in both.iterrows():
        us = row["us_name"] or "(exchange-only closure)"
        uk = row["uk_name"] or "(exchange-only closure)"
        print(f"  {row['date']}  {row['weekday']:10s}  US: {us}  |  UK: {uk}")

    # --- 4. Note on exchange_calendars vs holidays library ---
    print("\n--- Key difference: exchange_calendars vs holidays ---")
    print("""
    exchange_calendars tracks actual exchange closures, including:
      - Ad-hoc closures (e.g., 2025-01-09 National Day of Mourning)
      - Exchange-specific holidays (NYSE closes but not a federal holiday)

    holidays tracks statutory public holidays, including:
      - Veterans Day (Nov 11) -- NYSE is OPEN
      - Columbus Day (Oct 13) -- NYSE is OPEN
      - Weekend holidays (exchange_calendars omits these)

    For crypto prediction, exchange_calendars is the better primary signal
    because TradFi session overlaps directly drive crypto volume patterns.
    The holidays library is useful as a supplementary feature, especially
    for weekend effects.
    """)

    # --- 5. Difference illustration ---
    print("--- Days where statutory != exchange closure (2025) ---\n")
    us_statutory = get_statutory_holidays("US", "2025-01-01", "2025-12-31")
    nyse_closed = set(get_exchange_holidays("XNYS", "2025-01-01", "2025-12-31").date)

    stat_only = {d for d in us_statutory if d not in nyse_closed and d.weekday() < 5}
    exch_only = {d for d in nyse_closed if d not in us_statutory}

    if stat_only:
        print("  US statutory holiday but NYSE OPEN:")
        for d in sorted(stat_only):
            print(f"    {d} {d.strftime('%A'):10s} -- {us_statutory[d]}")

    if exch_only:
        print("  NYSE closed but NOT a US statutory holiday:")
        for d in sorted(exch_only):
            print(f"    {d} {d.strftime('%A'):10s} -- (exchange-specific closure)")
