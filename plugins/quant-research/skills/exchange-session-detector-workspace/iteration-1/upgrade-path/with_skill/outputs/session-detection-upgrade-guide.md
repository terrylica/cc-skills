# Session Detection Upgrade Guide: opendeviationbar-py

Upgrade plan from Tier 1 (fixed hour-range `zoneinfo`) to Tier 2 (production-grade `exchange_calendars`) for exchange session detection in the opendeviationbar-py project.

---

## Current State Analysis

### What exists today

Three files form the session detection pipeline:

| File                                                                  | Role                                                                 | Limitation                              |
| --------------------------------------------------------------------- | -------------------------------------------------------------------- | --------------------------------------- |
| `python/opendeviationbar/ouroboros.py`                                | `EXCHANGE_SESSION_HOURS` dict + `get_active_exchange_sessions()`     | Fixed hours, no holidays/lunch/sub-hour |
| `python/opendeviationbar/orchestration/open_deviation_bars_enrich.py` | `enrich_exchange_sessions()` — vectorized via hourly bucketing       | Inherits all `ouroboros.py` limitations |
| `python/opendeviationbar/clickhouse/migrations.py`                    | `_SESSION_UPDATES` + `migrate_exchange_sessions()` — server-side SQL | Hour-range only, no holidays            |

Plus one constant in `constants.py`:

```python
EXCHANGE_SESSION_COLUMNS: tuple[str, ...] = (
    "exchange_session_sydney",
    "exchange_session_tokyo",
    "exchange_session_london",
    "exchange_session_newyork",
)
```

And four ClickHouse columns in `schema.sql`:

```sql
exchange_session_sydney UInt8 DEFAULT 0,
exchange_session_tokyo UInt8 DEFAULT 0,
exchange_session_london UInt8 DEFAULT 0,
exchange_session_newyork UInt8 DEFAULT 0,
```

### Specific accuracy gaps

| Gap                            | Impact                                              | Example                                                                  |
| ------------------------------ | --------------------------------------------------- | ------------------------------------------------------------------------ |
| NYSE opens at 9:30, not 10:00  | 30 min/day misclassified (~126 bars/day at 250dbps) | Bar at 13:45 UTC marked `newyork=0` when NYSE is open                    |
| LSE closes at 16:30, not 17:00 | 30 min/day misclassified                            | Bar at 16:35 London time marked `london=1` when LSE is closed            |
| No holiday detection           | ~10 NYSE holidays/year, ~8 LSE holidays/year        | Christmas Day bar marked `newyork=1`                                     |
| No lunch breaks                | Tokyo 11:30-12:30 JST, ~250 trading days/year       | Bar at 02:45 UTC (11:45 JST) marked `tokyo=1` when TSE is on lunch break |
| No early closes                | NYSE closes at 13:00 on day before Thanksgiving     | Bar at 18:30 UTC marked `newyork=1` on half-day                          |
| Tokyo schedule change          | Extended to 15:30 on Nov 5, 2024                    | Post-change bars between 15:00-15:30 JST marked `tokyo=0`                |
| Only 4 exchanges               | No SIX, Frankfurt, Toronto, NZX, HKEX, SGX          | Cannot analyze European/Asian session overlap patterns                   |

---

## Upgrade Plan

### Phase 1: Add `exchange_calendars` dependency

**Effort**: 5 minutes. **Risk**: None (additive).

Add to `pyproject.toml` under `[project.dependencies]` (or `[project.optional-dependencies]` under a `sessions` extra if you want to keep it optional):

```toml
[project.optional-dependencies]
sessions = ["exchange_calendars>=4.5"]
```

The library is ~10MB installed, depends only on pandas and numpy (both already in the project), bundles all calendar data (no network calls at runtime), and covers 50+ exchanges via ISO 10383 MIC codes.

### Phase 2: Create `ExchangeConfig` registry

**Effort**: 30 minutes. **Risk**: None (new file, no changes to existing code).

Create `python/opendeviationbar/exchanges.py`:

```python
"""Exchange registry for session detection.

ISO 10383 MIC code registry for 10 global exchanges. Single source of truth --
adding a new exchange requires only one dict entry. The SessionDetector,
ClickHouse schema generation, and column naming all propagate automatically.
"""

from __future__ import annotations

from dataclasses import dataclass


@dataclass(frozen=True)
class ExchangeConfig:
    """Immutable configuration for a single exchange.

    Attributes
    ----------
    code : str
        ISO 10383 MIC code (e.g., "XNYS" for NYSE).
    name : str
        Full exchange name.
    currency : str
        Primary currency.
    timezone : str
        IANA timezone (DST handled by exchange_calendars).
    country : str
        Country name.
    open_hour : int
        Trading start hour in local time (24h format).
    open_minute : int
        Trading start minute.
    close_hour : int
        Trading close hour in local time (24h format).
    close_minute : int
        Trading close minute.
    """

    code: str
    name: str
    currency: str
    timezone: str
    country: str
    open_hour: int
    open_minute: int
    close_hour: int
    close_minute: int


EXCHANGES: dict[str, ExchangeConfig] = {
    "nyse": ExchangeConfig(
        code="XNYS",
        name="New York Stock Exchange",
        currency="USD",
        timezone="America/New_York",
        country="United States",
        open_hour=9, open_minute=30,
        close_hour=16, close_minute=0,
    ),
    "lse": ExchangeConfig(
        code="XLON",
        name="London Stock Exchange",
        currency="GBP",
        timezone="Europe/London",
        country="United Kingdom",
        open_hour=8, open_minute=0,
        close_hour=16, close_minute=30,
    ),
    "xswx": ExchangeConfig(
        code="XSWX",
        name="SIX Swiss Exchange",
        currency="CHF",
        timezone="Europe/Zurich",
        country="Switzerland",
        open_hour=9, open_minute=0,
        close_hour=17, close_minute=30,
    ),
    "xfra": ExchangeConfig(
        code="XFRA",
        name="Frankfurt Stock Exchange",
        currency="EUR",
        timezone="Europe/Berlin",
        country="Germany",
        open_hour=9, open_minute=0,
        close_hour=17, close_minute=30,
    ),
    "xtse": ExchangeConfig(
        code="XTSE",
        name="Toronto Stock Exchange",
        currency="CAD",
        timezone="America/Toronto",
        country="Canada",
        open_hour=9, open_minute=30,
        close_hour=16, close_minute=0,
    ),
    "xnze": ExchangeConfig(
        code="XNZE",
        name="New Zealand Exchange",
        currency="NZD",
        timezone="Pacific/Auckland",
        country="New Zealand",
        open_hour=10, open_minute=0,
        close_hour=16, close_minute=45,
    ),
    "xtks": ExchangeConfig(
        code="XTKS",
        name="Tokyo Stock Exchange",
        currency="JPY",
        timezone="Asia/Tokyo",
        country="Japan",
        open_hour=9, open_minute=0,
        close_hour=15, close_minute=0,
        # Lunch break: 11:30-12:30 JST (handled by exchange_calendars)
    ),
    "xasx": ExchangeConfig(
        code="XASX",
        name="Australian Securities Exchange",
        currency="AUD",
        timezone="Australia/Sydney",
        country="Australia",
        open_hour=10, open_minute=0,
        close_hour=16, close_minute=0,
    ),
    "xhkg": ExchangeConfig(
        code="XHKG",
        name="Hong Kong Stock Exchange",
        currency="HKD",
        timezone="Asia/Hong_Kong",
        country="Hong Kong",
        open_hour=9, open_minute=30,
        close_hour=16, close_minute=0,
        # Lunch break: 12:00-13:00 HKT (handled by exchange_calendars)
    ),
    "xses": ExchangeConfig(
        code="XSES",
        name="Singapore Exchange",
        currency="SGD",
        timezone="Asia/Singapore",
        country="Singapore",
        open_hour=9, open_minute=0,
        close_hour=17, close_minute=0,
        # Lunch break: 12:00-13:00 SGT (handled by exchange_calendars)
    ),
}


def get_exchange_names() -> list[str]:
    """Get all registry keys."""
    return list(EXCHANGES.keys())


def get_exchange_config(name: str) -> ExchangeConfig:
    """Lookup by name. Raises ValueError on miss."""
    if name not in EXCHANGES:
        available = ", ".join(EXCHANGES.keys())
        msg = f"Unknown exchange: {name}. Available: {available}"
        raise ValueError(msg)
    return EXCHANGES[name]
```

### Phase 3: Create `SessionDetector` class

**Effort**: 1 hour. **Risk**: Low (new file).

Create `python/opendeviationbar/session_detector.py`:

```python
"""Production-grade exchange session detection.

Uses exchange_calendars library for DST-aware, holiday-aware, lunch-break-aware
session detection across 10 global exchanges. Pre-computes trading minutes for
O(1) vectorized lookup.

Replaces the simplified hour-range approach in ouroboros.py.
"""

from __future__ import annotations

import logging
from datetime import date
from typing import Any

import exchange_calendars as xcals
import pandas as pd

from opendeviationbar.exchanges import EXCHANGES

logger = logging.getLogger(__name__)


class SessionDetector:
    """Detect trading sessions and holidays for global exchanges.

    Lunch Breaks (automatically handled by exchange_calendars):
    - Tokyo (XTKS): 11:30-12:30 JST
    - Hong Kong (XHKG): 12:00-13:00 HKT
    - Singapore (XSES): 12:00-13:00 SGT

    Usage
    -----
    >>> detector = SessionDetector()
    >>> df = detector.detect_sessions_and_holidays(dates_df)
    """

    def __init__(self) -> None:
        self.calendars: dict[str, Any] = {}
        for exchange_name, exchange_config in EXCHANGES.items():
            self.calendars[exchange_name] = xcals.get_calendar(
                exchange_config.code
            )

    def _precompute_trading_minutes(
        self, start_date: date, end_date: date
    ) -> dict[str, set[pd.Timestamp]]:
        """Pre-compute trading minutes for all exchanges in date range.

        Returns dict mapping exchange_name to set of trading minutes
        (timezone-aware UTC timestamps). Enables vectorized .isin() lookup.

        Uses calendar.is_open_on_minute() during pre-computation to respect:
        - Lunch breaks (Tokyo, Hong Kong, Singapore)
        - Trading hour changes (e.g., Tokyo extended to 15:30 on Nov 5, 2024)
        - Holidays and weekends (automatically excluded)
        """
        trading_minutes: dict[str, set[pd.Timestamp]] = {}

        for exchange_name, calendar in self.calendars.items():
            minutes_set: set[pd.Timestamp] = set()
            sessions = calendar.sessions_in_range(start_date, end_date)

            for session_date in sessions:
                market_open = calendar.session_open(session_date)
                market_close = calendar.session_close(session_date)

                current_minute = market_open
                while current_minute <= market_close:
                    if calendar.is_open_on_minute(current_minute):
                        minutes_set.add(current_minute)
                    current_minute += pd.Timedelta(minutes=1)

            trading_minutes[exchange_name] = minutes_set
            logger.debug(
                "Pre-computed %d trading minutes for %s",
                len(minutes_set),
                exchange_name,
            )

        return trading_minutes

    def detect_sessions_and_holidays(
        self, dates_df: pd.DataFrame
    ) -> pd.DataFrame:
        """Add holiday and session columns to dates DataFrame.

        Parameters
        ----------
        dates_df : pd.DataFrame
            DataFrame with 'ts' column (timezone-aware UTC timestamps).

        Returns
        -------
        pd.DataFrame
            Same DataFrame with added columns:
            - is_us_holiday: 1 if NYSE closed (excludes weekends)
            - is_uk_holiday: 1 if LSE closed (excludes weekends)
            - is_major_holiday: 1 if both NYSE and LSE closed
            - is_{exchange}_session: 1 if during trading hours
        """
        start_date = dates_df["ts"].min().date()
        end_date = dates_df["ts"].max().date()

        # Holiday detection
        nyse_holidays = {
            pd.to_datetime(h).date()
            for h in self.calendars["nyse"].regular_holidays.holidays(
                start=start_date, end=end_date, return_name=False
            )
        }
        lse_holidays = {
            pd.to_datetime(h).date()
            for h in self.calendars["lse"].regular_holidays.holidays(
                start=start_date, end=end_date, return_name=False
            )
        }

        dates_df["is_us_holiday"] = dates_df["ts"].dt.date.apply(
            lambda d: int(d in nyse_holidays)
        )
        dates_df["is_uk_holiday"] = dates_df["ts"].dt.date.apply(
            lambda d: int(d in lse_holidays)
        )
        dates_df["is_major_holiday"] = (
            (dates_df["is_us_holiday"] == 1)
            & (dates_df["is_uk_holiday"] == 1)
        ).astype(int)

        # Session detection via pre-computed minutes
        trading_minutes = self._precompute_trading_minutes(
            start_date, end_date
        )

        for exchange_name in self.calendars:
            col_name = f"is_{exchange_name}_session"
            dates_df[col_name] = (
                dates_df["ts"]
                .isin(trading_minutes[exchange_name])
                .astype(int)
            )

        return dates_df

    def is_open(
        self, exchange_name: str, timestamp_utc: pd.Timestamp
    ) -> bool:
        """Check if a single exchange is open at a specific UTC time.

        This is the single-timestamp equivalent of detect_sessions_and_holidays.
        For bulk lookups, use detect_sessions_and_holidays() instead.
        """
        calendar = self.calendars.get(exchange_name)
        if calendar is None:
            msg = f"Unknown exchange: {exchange_name}"
            raise ValueError(msg)
        return calendar.is_open_on_minute(timestamp_utc)
```

### Phase 4: Integrate into `enrich_exchange_sessions()`

**Effort**: 1 hour. **Risk**: Medium (modifies existing enrichment pipeline). Requires careful testing.

This is the key integration point. The current `enrich_exchange_sessions()` in `open_deviation_bars_enrich.py` calls `get_active_exchange_sessions()` from `ouroboros.py`. Replace it with the `SessionDetector` pattern.

**Backward compatibility approach**: Use `exchange_calendars` when available, fall back to existing `ouroboros.py` implementation otherwise. This way users who do not install the `sessions` extra still get the existing behavior.

```python
# In open_deviation_bars_enrich.py

def enrich_exchange_sessions(bars_df: pd.DataFrame) -> pd.DataFrame:
    """Add exchange session flags to bars.

    Uses exchange_calendars for production-grade detection (holidays,
    lunch breaks, sub-hour precision) when available. Falls back to
    simplified hour-range detection from ouroboros.py otherwise.
    """
    if bars_df.empty:
        return bars_df

    try:
        return _enrich_sessions_xcals(bars_df)
    except ImportError:
        # exchange_calendars not installed; fall back to Tier 1
        return _enrich_sessions_legacy(bars_df)


def _enrich_sessions_xcals(bars_df: pd.DataFrame) -> pd.DataFrame:
    """Tier 2: exchange_calendars-based session detection."""
    from opendeviationbar.session_detector import SessionDetector

    index = bars_df.index
    if index.tzinfo is None:
        index_utc = index.tz_localize("UTC")
    else:
        index_utc = index.tz_convert("UTC")

    # Floor to minute resolution (exchange_calendars works at minute granularity)
    minute_index = index_utc.floor("1min")

    # Build a temporary DataFrame for the detector
    detector = SessionDetector()
    start_date = minute_index.min().date()
    end_date = minute_index.max().date()

    # Pre-compute trading minutes for the date range
    trading_minutes = detector._precompute_trading_minutes(start_date, end_date)

    # Map old column names to new exchange names for backward compatibility
    # Old: exchange_session_sydney, exchange_session_tokyo, etc.
    # New: is_xasx_session, is_xtks_session, etc.
    column_mapping = {
        "exchange_session_sydney":  "xasx",   # ASX
        "exchange_session_tokyo":   "xtks",   # TSE/JPX
        "exchange_session_london":  "lse",    # LSE
        "exchange_session_newyork": "nyse",   # NYSE
    }

    for old_col, exchange_name in column_mapping.items():
        if exchange_name in trading_minutes:
            bars_df[old_col] = minute_index.isin(
                trading_minutes[exchange_name]
            ).astype(int)

    # Add new exchange columns (SIX, Frankfurt, Toronto, NZX, HKEX, SGX)
    new_exchanges = {
        k: v for k, v in trading_minutes.items()
        if k not in column_mapping.values()
    }
    for exchange_name, minutes_set in new_exchanges.items():
        col_name = f"exchange_session_{exchange_name}"
        bars_df[col_name] = minute_index.isin(minutes_set).astype(int)

    # Holiday columns
    nyse_holidays = {
        pd.to_datetime(h).date()
        for h in detector.calendars["nyse"].regular_holidays.holidays(
            start=start_date, end=end_date, return_name=False
        )
    }
    lse_holidays = {
        pd.to_datetime(h).date()
        for h in detector.calendars["lse"].regular_holidays.holidays(
            start=start_date, end=end_date, return_name=False
        )
    }

    bar_dates = minute_index.date
    bars_df["is_us_holiday"] = pd.array(
        [int(d in nyse_holidays) for d in bar_dates], dtype="Int8"
    )
    bars_df["is_uk_holiday"] = pd.array(
        [int(d in lse_holidays) for d in bar_dates], dtype="Int8"
    )
    bars_df["is_major_holiday"] = (
        (bars_df["is_us_holiday"] == 1) & (bars_df["is_uk_holiday"] == 1)
    ).astype(int)

    return bars_df


def _enrich_sessions_legacy(bars_df: pd.DataFrame) -> pd.DataFrame:
    """Tier 1 fallback: existing hour-range detection from ouroboros.py."""
    # ... existing enrich_exchange_sessions() logic unchanged ...
```

### Phase 5: Update ClickHouse schema and migrations

**Effort**: 2 hours. **Risk**: Medium (schema change on production table).

#### 5a. Add new columns to `schema.sql`

```sql
-- New exchange session columns (Phase 5)
exchange_session_xswx UInt8 DEFAULT 0,
exchange_session_xfra UInt8 DEFAULT 0,
exchange_session_xtse UInt8 DEFAULT 0,
exchange_session_xnze UInt8 DEFAULT 0,
exchange_session_xtks UInt8 DEFAULT 0,  -- replaces tokyo (different hours)
exchange_session_xasx UInt8 DEFAULT 0,  -- replaces sydney (same hours, different name)
exchange_session_xhkg UInt8 DEFAULT 0,
exchange_session_xses UInt8 DEFAULT 0,

-- Holiday flags
is_us_holiday UInt8 DEFAULT 0,
is_uk_holiday UInt8 DEFAULT 0,
is_major_holiday UInt8 DEFAULT 0,
```

#### 5b. Update `migrations.py` for hybrid approach

The current `toTimezone()` SQL approach handles DST and weekends but cannot handle holidays or lunch breaks server-side. The recommended strategy is a two-tier approach:

**Tier A (server-side, fast, approximate)**: Keep `toTimezone()` for the 4 original columns. These remain useful for quick filtering where holiday precision is not critical.

**Tier B (Python-computed, exact)**: Write exact session flags from Python after computing via `exchange_calendars`. This handles holidays, lunch breaks, early closes, and schedule changes.

```python
# In migrations.py, add a new function:

def migrate_exchange_sessions_v2(
    client: clickhouse_connect.driver.Client,
    *,
    symbol: str | None = None,
    start_date: str | None = None,
    end_date: str | None = None,
    batch_size: int = 50_000,
) -> int:
    """Populate exchange session columns using exchange_calendars (Tier 2).

    Reads close_time_ms from ClickHouse, computes session flags in Python
    via exchange_calendars (with holidays, lunch breaks, early closes),
    and writes flags back.

    For the 4 original columns (sydney/tokyo/london/newyork), this
    produces more accurate results than the toTimezone() SQL approach.
    For the 6 new columns (xswx/xfra/xtse/xnze/xhkg/xses), this is
    the only way to populate them.
    """
    from opendeviationbar.session_detector import SessionDetector

    # 1. Read close_time_ms values from ClickHouse
    where_parts = []
    if symbol:
        where_parts.append(f"symbol = '{symbol}'")
    if start_date:
        where_parts.append(
            f"close_time_ms >= toUnixTimestamp(toDate('{start_date}')) * 1000"
        )
    if end_date:
        where_parts.append(
            f"close_time_ms < toUnixTimestamp(toDate('{end_date}') + 1) * 1000"
        )
    where_clause = " AND ".join(where_parts) if where_parts else "1 = 1"

    result = client.query(
        f"SELECT first_agg_trade_id, close_time_ms "
        f"FROM opendeviationbar_cache.open_deviation_bars FINAL "
        f"WHERE {where_clause} "
        f"ORDER BY first_agg_trade_id"
    )

    if not result.result_rows:
        logger.info("No rows to migrate")
        return 0

    # 2. Convert to timestamps and compute session flags
    import pandas as pd

    df = pd.DataFrame(
        result.result_rows,
        columns=["first_agg_trade_id", "close_time_ms"],
    )
    df["ts"] = pd.to_datetime(df["close_time_ms"], unit="ms", utc=True)

    detector = SessionDetector()
    df = detector.detect_sessions_and_holidays(df)

    # 3. Write flags back in batches via ALTER TABLE UPDATE
    # (per-row UPDATE is impractical; batch via temporary table + JOIN)
    # ... batch write logic ...

    return len(df)
```

#### 5c. ClickHouse holiday table (optional, for pure server-side queries)

If you need holiday detection in ClickHouse without round-tripping to Python:

```sql
CREATE TABLE IF NOT EXISTS opendeviationbar_cache.exchange_holidays (
    exchange String,
    holiday_date Date,
    holiday_name String
) ENGINE = MergeTree()
ORDER BY (exchange, holiday_date);
```

Populate once from Python:

```python
def populate_holiday_table(
    client, start_year: int = 2018, end_year: int = 2027
) -> int:
    """One-time population of exchange_holidays from exchange_calendars."""
    import exchange_calendars as xcals

    rows = []
    for mic, label in [("XNYS", "NYSE"), ("XLON", "LSE")]:
        cal = xcals.get_calendar(mic)
        holidays = cal.regular_holidays.holidays(
            start=f"{start_year}-01-01",
            end=f"{end_year}-12-31",
            return_name=True,
        )
        for date_val, name in holidays.items():
            rows.append((label, date_val.date(), name))

    client.insert(
        "opendeviationbar_cache.exchange_holidays",
        rows,
        column_names=["exchange", "holiday_date", "holiday_name"],
    )
    return len(rows)
```

Then use in ClickHouse queries:

```sql
-- Session detection with holiday exclusion (server-side)
SELECT *
FROM opendeviationbar_cache.open_deviation_bars t
WHERE toHour(toTimezone(
    toDateTime(intDiv(t.close_time_ms, 1000)), 'America/New_York'
  )) >= 9
  AND toHour(toTimezone(
    toDateTime(intDiv(t.close_time_ms, 1000)), 'America/New_York'
  )) < 16
  AND toDayOfWeek(toTimezone(
    toDateTime(intDiv(t.close_time_ms, 1000)), 'America/New_York'
  )) <= 5
  AND NOT EXISTS (
    SELECT 1
    FROM opendeviationbar_cache.exchange_holidays h
    WHERE h.exchange = 'NYSE'
      AND h.holiday_date = toDate(toTimezone(
        toDateTime(intDiv(t.close_time_ms, 1000)), 'America/New_York'
      ))
  )
```

### Phase 6: Update `constants.py` and `ouroboros.py`

**Effort**: 30 minutes. **Risk**: Low.

Update `EXCHANGE_SESSION_COLUMNS` in `constants.py` to include all 10 exchanges plus holiday flags:

```python
EXCHANGE_SESSION_COLUMNS: tuple[str, ...] = (
    # Original 4 (backward compatible)
    "exchange_session_sydney",
    "exchange_session_tokyo",
    "exchange_session_london",
    "exchange_session_newyork",
    # New 6 (Phase 5)
    "exchange_session_xswx",
    "exchange_session_xfra",
    "exchange_session_xtse",
    "exchange_session_xnze",
    "exchange_session_xhkg",
    "exchange_session_xses",
)

HOLIDAY_COLUMNS: tuple[str, ...] = (
    "is_us_holiday",
    "is_uk_holiday",
    "is_major_holiday",
)
```

Deprecate `EXCHANGE_SESSION_HOURS` in `ouroboros.py` with a comment pointing to `exchanges.py`:

```python
# DEPRECATED: Use opendeviationbar.exchanges.EXCHANGES instead.
# Kept for backward compatibility with existing ClickHouse toTimezone() SQL.
EXCHANGE_SESSION_HOURS = { ... }
```

### Phase 7: Backfill existing ClickHouse data

**Effort**: Variable (depends on row count). **Risk**: Low (additive columns, existing data unchanged).

Run on bigblack after deploying the new code:

```bash
# 1. Add columns (idempotent)
mise run db:migrate-sessions-v2

# 2. Backfill flags for all ~42M bars
# This reads close_time_ms, computes flags in Python, writes back.
# Expect ~30 min for 42M rows at 50K/batch.
mise run db:backfill-session-flags
```

The original 4 `exchange_session_*` columns remain populated by the existing `toTimezone()` migration for fast approximate queries. The new columns provide exact flags.

---

## Test Plan

### Unit tests to add

```python
import pytest
import pandas as pd


class TestSessionDetectorAccuracy:
    """Verify exchange_calendars fixes all known gaps."""

    def test_nyse_opens_at_930_not_1000(self):
        """NYSE opens at 9:30 ET, not 10:00."""
        detector = SessionDetector()
        # 13:45 UTC = 9:45 ET (during DST) -- NYSE IS open
        ts = pd.Timestamp("2024-07-15 13:45", tz="UTC")
        assert detector.is_open("nyse", ts) is True

    def test_nyse_closed_on_christmas(self):
        """NYSE is closed on December 25."""
        detector = SessionDetector()
        # Christmas 2024 (Wednesday) at 14:30 UTC = 9:30 ET
        ts = pd.Timestamp("2024-12-25 14:30", tz="UTC")
        assert detector.is_open("nyse", ts) is False

    def test_nyse_early_close_before_thanksgiving(self):
        """NYSE closes at 13:00 ET day before Thanksgiving."""
        detector = SessionDetector()
        # Nov 29, 2024 (day before Thanksgiving) at 18:30 UTC = 13:30 ET
        ts = pd.Timestamp("2024-11-29 18:30", tz="UTC")
        assert detector.is_open("nyse", ts) is False

    def test_tokyo_lunch_break(self):
        """Tokyo is closed during lunch 11:30-12:30 JST."""
        detector = SessionDetector()
        # 02:45 UTC = 11:45 JST (lunch break)
        ts = pd.Timestamp("2024-07-15 02:45", tz="UTC")
        assert detector.is_open("xtks", ts) is False

    def test_tokyo_open_before_lunch(self):
        """Tokyo is open at 11:00 JST (before lunch)."""
        detector = SessionDetector()
        ts = pd.Timestamp("2024-07-15 02:00", tz="UTC")  # 11:00 JST
        assert detector.is_open("xtks", ts) is True

    def test_lse_closes_at_1630_not_1700(self):
        """LSE closes at 16:30, not 17:00."""
        detector = SessionDetector()
        # 16:35 London time (BST) = 15:35 UTC (summer)
        ts = pd.Timestamp("2024-07-15 15:35", tz="UTC")
        assert detector.is_open("lse", ts) is False

    def test_dst_transition_spring_forward(self):
        """Session boundaries shift correctly at DST transitions."""
        detector = SessionDetector()
        # NYSE: March 10, 2024 (spring forward)
        # Before DST: 9:30 ET = 14:30 UTC
        # After DST:  9:30 ET = 13:30 UTC
        ts_before = pd.Timestamp("2024-03-08 14:30", tz="UTC")  # Friday
        ts_after = pd.Timestamp("2024-03-11 13:30", tz="UTC")   # Monday
        assert detector.is_open("nyse", ts_before) is True
        assert detector.is_open("nyse", ts_after) is True

    def test_hong_kong_lunch_break(self):
        """HKEX is closed during lunch 12:00-13:00 HKT."""
        detector = SessionDetector()
        # 04:30 UTC = 12:30 HKT (lunch break)
        ts = pd.Timestamp("2024-07-15 04:30", tz="UTC")
        assert detector.is_open("xhkg", ts) is False
```

### Integration test: compare Tier 1 vs Tier 2

```python
def test_tier1_vs_tier2_divergence():
    """Quantify exactly where Tier 1 and Tier 2 disagree."""
    from opendeviationbar.ouroboros import get_active_exchange_sessions

    detector = SessionDetector()

    # One week of minute-level data
    ts_range = pd.date_range("2024-07-01", "2024-07-07", freq="1min", tz="UTC")
    divergences = {"nyse": 0, "lse": 0, "xtks": 0, "xasx": 0}

    for ts in ts_range:
        tier1 = get_active_exchange_sessions(ts.to_pydatetime())
        tier2_nyse = detector.is_open("nyse", ts)
        tier2_lse = detector.is_open("lse", ts)

        if tier1.newyork != tier2_nyse:
            divergences["nyse"] += 1
        if tier1.london != tier2_lse:
            divergences["lse"] += 1

    # Expect divergences due to sub-hour precision and July 4th
    assert divergences["nyse"] > 0, "Should find NYSE divergences"
    print(f"Divergences in 1 week: {divergences}")
```

---

## ClickHouse `toTimezone()` Compatibility

The existing `toTimezone()` SQL approach in `migrations.py` remains valid for the original 4 columns as a fast approximate filter. Here is how the two approaches coexist:

| Feature            | `toTimezone()` SQL (Tier A)   | `exchange_calendars` Python (Tier B) |
| ------------------ | ----------------------------- | ------------------------------------ |
| DST                | Automatic (IANA)              | Automatic (IANA)                     |
| Weekends           | `toDayOfWeek() <= 5`          | Built-in                             |
| Holidays           | Not supported                 | Built-in `regular_holidays`          |
| Lunch breaks       | Not supported                 | Built-in `is_open_on_minute()`       |
| Early closes       | Not supported                 | Built-in                             |
| Sub-hour precision | Possible but verbose          | Built-in                             |
| Speed (42M rows)   | ~5 seconds (server-side)      | ~30 min (round-trip)                 |
| Use case           | Fast filtering, WHERE clauses | Exact ML features                    |

**Recommendation**: Keep both. Use `toTimezone()` columns for fast ClickHouse `WHERE` clauses (e.g., "give me all bars during approximate NYSE hours"). Use `exchange_calendars`-computed columns for ML features where holiday/lunch accuracy matters.

### Updated ClickHouse SQL with sub-hour precision

If you want to improve the server-side SQL without `exchange_calendars` (e.g., for the original 4 columns), you can add minute-level precision:

```sql
-- NYSE: 9:30-16:00 ET (sub-hour precision, no holidays)
ALTER TABLE opendeviationbar_cache.open_deviation_bars
UPDATE exchange_session_newyork = if(
    (
        (toHour(toTimezone(toDateTime(intDiv(close_time_ms, 1000)), 'America/New_York')) > 9
         OR (toHour(toTimezone(toDateTime(intDiv(close_time_ms, 1000)), 'America/New_York')) = 9
             AND toMinute(toTimezone(toDateTime(intDiv(close_time_ms, 1000)), 'America/New_York')) >= 30))
        AND toHour(toTimezone(toDateTime(intDiv(close_time_ms, 1000)), 'America/New_York')) < 16
    )
    AND toDayOfWeek(toTimezone(toDateTime(intDiv(close_time_ms, 1000)), 'America/New_York')) <= 5,
    1, 0
) WHERE 1 = 1;
```

This is verbose but correct for sub-hour boundaries. The `exchange_calendars` approach avoids this complexity entirely.

---

## Migration Timeline

| Phase                            | Work           | Blocking?          | Backward Compatible?     |
| -------------------------------- | -------------- | ------------------ | ------------------------ |
| 1. Add dependency                | 5 min          | No                 | Yes                      |
| 2. ExchangeConfig registry       | 30 min         | No                 | Yes (new file)           |
| 3. SessionDetector class         | 1 hr           | No                 | Yes (new file)           |
| 4. Integrate into enrichment     | 1 hr           | **Yes** (deploy)   | Yes (fallback to legacy) |
| 5. ClickHouse schema + migration | 2 hr           | No                 | Yes (additive columns)   |
| 6. Update constants              | 30 min         | No                 | Yes                      |
| 7. Backfill production data      | 30 min runtime | **Yes** (bigblack) | Yes                      |

**Total implementation effort**: ~5 hours of coding + 30 min backfill runtime.

**Recommended approach**: Ship Phases 1-3 first as a standalone PR (no production impact). Then Phase 4 in a separate PR with the try/except fallback. Then Phases 5-7 after validation on dev.

---

## Key Files Modified (Summary)

| File                                                                  | Change                                                                |
| --------------------------------------------------------------------- | --------------------------------------------------------------------- |
| `pyproject.toml`                                                      | Add `exchange_calendars` to optional deps                             |
| `python/opendeviationbar/exchanges.py`                                | **NEW**: ExchangeConfig registry (10 exchanges)                       |
| `python/opendeviationbar/session_detector.py`                         | **NEW**: SessionDetector with pre-computed minutes                    |
| `python/opendeviationbar/orchestration/open_deviation_bars_enrich.py` | Replace `get_active_exchange_sessions()` calls with `SessionDetector` |
| `python/opendeviationbar/clickhouse/schema.sql`                       | Add 6 new exchange columns + 3 holiday columns                        |
| `python/opendeviationbar/clickhouse/migrations.py`                    | Add `migrate_exchange_sessions_v2()`                                  |
| `python/opendeviationbar/constants.py`                                | Extend `EXCHANGE_SESSION_COLUMNS`, add `HOLIDAY_COLUMNS`              |
| `python/opendeviationbar/ouroboros.py`                                | Deprecation comment on `EXCHANGE_SESSION_HOURS` (keep for compat)     |
| `tests/test_session_detector.py`                                      | **NEW**: Accuracy tests for holidays, lunch breaks, DST, sub-hour     |
