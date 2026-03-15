# Exchange Session Detection: Upgrade Plan

## Current State Assessment

The session detection in `ouroboros.py` uses a fixed-hour-range approach:

```python
EXCHANGE_SESSION_HOURS = {
    "sydney":   {"tz": "Australia/Sydney",   "start": 10, "end": 16},  # ASX
    "tokyo":    {"tz": "Asia/Tokyo",         "start": 9,  "end": 15},  # TSE
    "london":   {"tz": "Europe/London",      "start": 8,  "end": 17},  # LSE
    "newyork":  {"tz": "America/New_York",   "start": 10, "end": 16},  # NYSE
}
```

This is consumed in three places:

1. **Python-side enrichment** (`orchestration/open_deviation_bars_enrich.py`): `get_active_exchange_sessions()` called per unique hour, flags mapped onto DataFrame.
2. **ClickHouse migration SQL** (`clickhouse/migrations.py`): `_build_session_update_sql()` generates `ALTER TABLE UPDATE` using `toTimezone()` + `toHour()` with the same fixed ranges.
3. **ClickHouse schema** (`clickhouse/schema.sql`): Four `UInt8 DEFAULT 0` columns stored per bar.

### What Works

- DST is handled correctly (both `zoneinfo` in Python and `toTimezone()` in ClickHouse use IANA tz databases that include DST rules).
- Weekend exclusion is present (weekday check in both paths).
- Hourly deduplication in the enrichment function keeps it fast (~24 unique-hour lookups per day instead of per-bar).
- Python and ClickHouse paths produce identical results for the same inputs (verified by test suite).

### What Does Not Work

| Gap                                     | Impact                                                                        | Example                                                              |
| --------------------------------------- | ----------------------------------------------------------------------------- | -------------------------------------------------------------------- |
| Integer hour granularity only           | NYSE opens at 9:30 ET, not 10:00                                              | Bars between 9:30-10:00 ET are misclassified as outside-session      |
| No holiday calendar                     | Christmas Day flagged as "session active" if it falls on a weekday            | Misleading ML features; cross-session volume analysis contaminated   |
| No lunch breaks                         | TSE has a lunch break 11:30-12:30 JST; currently marked as continuous session | Crypto bars during TSE lunch misclassified as in-session             |
| No pre-market / after-hours distinction | All hours within the range treated equally                                    | Cannot distinguish regular-hours vs extended-hours liquidity regimes |
| No half-days / early closes             | NYSE closes at 1:00 PM ET on the day after Thanksgiving                       | Afternoon bars on early-close days misclassified                     |
| Four exchanges only                     | No CME, HKEX, SSE, BSE, KRX, SGX, etc.                                        | Crypto correlations with Asian/commodity sessions missed             |

---

## Upgrade Plan: Three Phases

### Phase 1: Sub-Hour Precision + Lunch Breaks (Low Risk, High Impact)

**Goal**: Fix the most egregious factual errors (NYSE 9:30, TSE lunch break) without adding external dependencies.

#### 1.1 Change the session definition format

Replace integer hours with `(hour, minute)` tuples. This is backward-compatible with the ClickHouse path because `toHour()` + `toMinute()` are both native ClickHouse functions.

```python
# ouroboros.py — proposed replacement

@dataclass(frozen=True)
class SessionWindow:
    """A single contiguous trading window within a session day."""
    start_hour: int
    start_minute: int
    end_hour: int
    end_minute: int

@dataclass(frozen=True)
class ExchangeSessionDef:
    """Full definition for one exchange session."""
    tz: str                      # IANA timezone
    windows: tuple[SessionWindow, ...]  # One or more windows per day

EXCHANGE_SESSIONS: dict[str, ExchangeSessionDef] = {
    "sydney": ExchangeSessionDef(
        tz="Australia/Sydney",
        windows=(SessionWindow(10, 0, 16, 0),),  # ASX continuous
    ),
    "tokyo": ExchangeSessionDef(
        tz="Asia/Tokyo",
        windows=(
            SessionWindow(9, 0, 11, 30),   # TSE morning session
            SessionWindow(12, 30, 15, 0),  # TSE afternoon session
        ),
    ),
    "london": ExchangeSessionDef(
        tz="Europe/London",
        windows=(SessionWindow(8, 0, 16, 30),),  # LSE continuous
    ),
    "newyork": ExchangeSessionDef(
        tz="America/New_York",
        windows=(SessionWindow(9, 30, 16, 0),),  # NYSE regular hours
    ),
}
```

#### 1.2 Update the Python detection function

```python
def _time_in_minutes(hour: int, minute: int) -> int:
    """Convert (hour, minute) to minutes-since-midnight."""
    return hour * 60 + minute

def is_in_session(session: ExchangeSessionDef, timestamp_utc: datetime) -> bool:
    """Check if a UTC timestamp falls within any window of the session."""
    import zoneinfo
    tz = zoneinfo.ZoneInfo(session.tz)
    local_time = timestamp_utc.astimezone(tz)

    # Weekend exclusion
    if local_time.weekday() >= 5:
        return False

    local_minutes = local_time.hour * 60 + local_time.minute
    return any(
        _time_in_minutes(w.start_hour, w.start_minute)
        <= local_minutes
        < _time_in_minutes(w.end_hour, w.end_minute)
        for w in session.windows
    )
```

#### 1.3 Update the ClickHouse SQL generator

The key change: replace `toHour(ts) >= N AND toHour(ts) < M` with minute-level precision.

```python
def _build_session_update_sql(
    session_name: str,
    session_def: ExchangeSessionDef,
    *,
    symbol: str | None = None,
) -> str:
    """Build ALTER TABLE UPDATE SQL for one exchange session column.

    Supports multiple windows (e.g., TSE morning + afternoon)
    and sub-hour precision (e.g., NYSE 9:30 open).
    """
    col = f"exchange_session_{session_name}"
    tz = session_def.tz

    ts_local = f"toTimezone(toDateTime(intDiv(close_time_ms, 1000)), '{tz}')"
    # minutes since midnight in local time
    local_minutes = f"(toHour({ts_local}) * 60 + toMinute({ts_local}))"

    window_conditions = []
    for w in session_def.windows:
        start_min = w.start_hour * 60 + w.start_minute
        end_min = w.end_hour * 60 + w.end_minute
        window_conditions.append(
            f"({local_minutes} >= {start_min} AND {local_minutes} < {end_min})"
        )

    time_condition = " OR ".join(window_conditions)
    weekday_condition = f"toDayOfWeek({ts_local}) <= 5"
    full_condition = f"({time_condition}) AND {weekday_condition}"

    where = f"symbol = '{symbol}'" if symbol else "1 = 1"

    return (
        f"ALTER TABLE opendeviationbar_cache.open_deviation_bars "
        f"UPDATE {col} = if({full_condition}, 1, 0) "
        f"WHERE {where}"
    )
```

#### 1.4 Migration strategy

- The ClickHouse columns are already `UInt8 DEFAULT 0`.
- Run `migrate_exchange_sessions()` once with the new SQL to recompute all ~42M rows.
- The `ALTER TABLE ... UPDATE` is a lightweight mutation in ClickHouse (processed in background, no downtime).
- Before/after counts via `check_exchange_session_coverage()` will show the shift (NYSE active count drops slightly because 9:30-10:00 bars were previously included; TSE active count drops because lunch-break bars are excluded).

#### 1.5 Backward compatibility

Keep the old `EXCHANGE_SESSION_HOURS` dict as a deprecated shim for any external consumers:

```python
# Backward compat shim (deprecated, remove in v15)
EXCHANGE_SESSION_HOURS = {
    name: {"tz": defn.tz, "start": defn.windows[0].start_hour, "end": defn.windows[-1].end_hour}
    for name, defn in EXCHANGE_SESSIONS.items()
}
```

**Estimated effort**: 1-2 hours. No new dependencies. Fully testable with existing test patterns.

---

### Phase 2: Holiday Calendars (Medium Risk, High Impact)

**Goal**: Exclude public holidays so that Christmas/New Year's/national holidays are not flagged as active sessions.

#### 2.1 Library evaluation

| Library                      | Holiday Support                                | Maintenance                 | Size   | Notes                                                     |
| ---------------------------- | ---------------------------------------------- | --------------------------- | ------ | --------------------------------------------------------- |
| `exchange_calendars`         | Full (250+ exchanges, early closes, half-days) | Active (Quantopian lineage) | ~15 MB | Gold standard for quant; includes ad-hoc closures         |
| `pandas_market_calendars`    | Good (40+ exchanges)                           | Active                      | ~5 MB  | pandas-native, lighter                                    |
| `holidays` (python-holidays) | Country-level only                             | Active                      | ~2 MB  | No exchange-specific calendars; would need manual mapping |
| `trading_calendars`          | Deprecated                                     | Dead                        | -      | Original Quantopian; superseded by `exchange_calendars`   |
| Custom TOML/JSON             | Manual maintenance                             | You                         | ~50 KB | Full control but error-prone for rolling holidays         |

**Recommendation**: `exchange_calendars`. It is the most complete, actively maintained, and already the de facto standard in the quant Python ecosystem. It handles:

- Fixed holidays (Christmas, New Year's)
- Rolling holidays (Easter, Golden Week, lunar calendar dates)
- Ad-hoc closures (weather events, national mourning days)
- Early closes / half-days (e.g., NYSE day-before-Independence-Day closes at 1:00 PM)
- Pre-calculated through 2099

#### 2.2 Mapping our sessions to exchange_calendars

```python
# session_calendar.py — new module

import exchange_calendars as xcals
from datetime import datetime

# Map our session names to exchange_calendars exchange codes
SESSION_TO_EXCHANGE = {
    "sydney":   "XASX",  # ASX
    "tokyo":    "XTKS",  # Tokyo Stock Exchange
    "london":   "XLON",  # London Stock Exchange
    "newyork":  "XNYS",  # New York Stock Exchange
}

# Lazy-loaded calendar cache (each calendar is ~1-2 MB in memory)
_calendar_cache: dict[str, xcals.ExchangeCalendar] = {}

def _get_calendar(session_name: str) -> xcals.ExchangeCalendar:
    """Get or create cached exchange calendar."""
    if session_name not in _calendar_cache:
        code = SESSION_TO_EXCHANGE[session_name]
        _calendar_cache[session_name] = xcals.get_calendar(code)
    return _calendar_cache[session_name]

def is_session_active(
    session_name: str,
    timestamp_utc: datetime,
) -> bool:
    """Check if a UTC timestamp falls within an exchange's trading hours.

    Uses exchange_calendars for:
    - Exact open/close times (sub-hour precision built in)
    - Holiday exclusion
    - Early-close / half-day handling
    - Lunch breaks (e.g., XTKS)
    """
    cal = _get_calendar(session_name)
    ts = timestamp_utc if timestamp_utc.tzinfo else timestamp_utc.replace(tzinfo=UTC)

    # exchange_calendars uses pd.Timestamp internally
    import pandas as pd
    pd_ts = pd.Timestamp(ts)

    # is_open_on_minute checks if the exchange is open at this exact minute.
    # It handles holidays, early closes, and lunch breaks.
    return cal.is_open_on_minute(pd_ts)
```

#### 2.3 Performance considerations

`exchange_calendars.is_open_on_minute()` is more expensive than a simple hour comparison (~50 us vs ~2 us per call). The existing hourly-dedup optimization in `enrich_exchange_sessions()` already limits calls to ~24 per day, so the total overhead per day is ~24 _4 sessions_ 50 us = ~5 ms. Negligible.

For the ClickHouse path, holidays cannot be expressed as a pure SQL function. Two options:

**Option A: Materialized holiday table (recommended)**

```sql
-- Pre-populate a holiday table from exchange_calendars
CREATE TABLE opendeviationbar_cache.exchange_holidays (
    exchange_code String,
    holiday_date Date,
    early_close_time Nullable(String)  -- e.g., '13:00' for NYSE half-days
) ENGINE = MergeTree() ORDER BY (exchange_code, holiday_date);

-- Then the session update SQL becomes:
-- ... AND toDate(ts_local) NOT IN (
--     SELECT holiday_date FROM opendeviationbar_cache.exchange_holidays
--     WHERE exchange_code = 'XNYS' AND early_close_time IS NULL
-- )
```

**Option B: Python-side recomputation only**

Skip the ClickHouse SQL holiday check entirely. Recompute session columns from Python using `migrate_exchange_sessions()` after every schema change. This is simpler but slower for bulk backfills (42M rows need Python-side processing vs. server-side mutation).

**Recommendation**: Option A for new data (holiday table is cheap and fast), Option B for the initial backfill of historical data (one-time cost, then the holiday table handles ongoing inserts).

#### 2.4 Early-close handling

`exchange_calendars` provides `session_close()` for each trading date, which returns the actual close time (e.g., 13:00 on NYSE half-days). The `is_open_on_minute()` method already accounts for this, so no extra code is needed on the Python side.

For ClickHouse, the holiday table approach (Option A) can store `early_close_time`:

```sql
-- For bars on early-close days, override the session end time
-- This requires the session update SQL to join against the holiday table
-- and use COALESCE(early_close_time, default_close_time) as the end boundary
```

#### 2.5 Holiday table population script

```python
# scripts/populate_holiday_table.py

import exchange_calendars as xcals
import clickhouse_connect
from datetime import date

EXCHANGES = {
    "sydney":   "XASX",
    "tokyo":    "XTKS",
    "london":   "XLON",
    "newyork":  "XNYS",
}

def populate_holidays(
    client: clickhouse_connect.driver.Client,
    start_year: int = 2017,
    end_year: int = 2030,
):
    """Populate exchange_holidays table from exchange_calendars."""
    rows = []
    for session_name, code in EXCHANGES.items():
        cal = xcals.get_calendar(code)
        # Get all sessions (trading days) in range
        start = date(start_year, 1, 1)
        end = date(end_year, 12, 31)

        # exchange_calendars provides .holidays() method
        # which returns holidays within its valid range
        all_dates = set(
            d.date()
            for d in cal.sessions_in_range(
                start.isoformat(), end.isoformat()
            )
        )

        # Every weekday NOT in all_dates is a holiday
        current = start
        from datetime import timedelta
        while current <= end:
            if current.weekday() < 5 and current not in all_dates:
                rows.append((code, current.isoformat(), None))
            current += timedelta(days=1)

        # Early closes
        for session_date in cal.early_closes_in_range(
            start.isoformat(), end.isoformat()
        ):
            close_time = cal.session_close(session_date)
            rows.append((
                code,
                session_date.strftime("%Y-%m-%d"),
                close_time.strftime("%H:%M"),
            ))

    client.insert(
        "opendeviationbar_cache.exchange_holidays",
        rows,
        column_names=["exchange_code", "holiday_date", "early_close_time"],
    )
```

**Estimated effort**: 3-4 hours. Adds `exchange_calendars` dependency (~15 MB). Requires one-time backfill migration of 42M rows.

---

### Phase 3: Extended Session Types + More Exchanges (Lower Priority)

**Goal**: Add pre-market, after-hours, and additional exchange sessions (CME, HKEX, SSE, etc.).

#### 3.1 Session type taxonomy

```python
from enum import Enum

class SessionType(str, Enum):
    """Trading session type for granular analysis."""
    PRE_MARKET = "pre_market"      # e.g., NYSE 4:00-9:30 ET
    REGULAR = "regular"            # e.g., NYSE 9:30-16:00 ET
    AFTER_HOURS = "after_hours"    # e.g., NYSE 16:00-20:00 ET
    LUNCH_BREAK = "lunch_break"    # e.g., TSE 11:30-12:30 JST (not trading)
    AUCTION = "auction"            # Opening/closing auctions
```

This would change the column schema from boolean flags to categorical values:

```sql
-- New: session type column per exchange (replaces UInt8 boolean)
exchange_session_newyork Enum8(
    'closed' = 0,
    'pre_market' = 1,
    'regular' = 2,
    'after_hours' = 3,
    'auction' = 4
) DEFAULT 'closed'
```

**Trade-off**: More expressive but breaks the current boolean interface. Could keep booleans for backward compat and add new `_type` columns alongside:

```sql
-- Keep existing (backward compat)
exchange_session_newyork UInt8 DEFAULT 0,  -- 1 if regular hours

-- Add new (Phase 3)
exchange_session_newyork_type Enum8(...) DEFAULT 'closed',
```

#### 3.2 Additional exchanges

```python
# Phase 3 additions
EXTENDED_EXCHANGES = {
    "cme":       "XCME",   # CME (Chicago) — futures, 23h near-continuous
    "hongkong":  "XHKG",   # HKEX
    "shanghai":  "XSHG",   # SSE
    "shenzhen":  "XSHE",   # SZSE
    "korea":     "XKRX",   # KRX (Seoul)
    "singapore": "XSES",   # SGX
    "mumbai":    "XBOM",   # BSE
    "frankfurt": "XFRA",   # Frankfurt (Xetra)
}
```

Each new exchange adds one `UInt8` column to ClickHouse (~1 byte per row; at 42M rows that is ~42 MB per exchange -- trivial).

#### 3.3 CME special case

CME is nearly 23-hour continuous. For crypto analysis, the relevant signal is usually "CME equity futures pit session" (8:30-15:15 CT) or "CME globex electronic" (17:00-16:00+1 CT). `exchange_calendars` supports `XCME` but the session boundaries need care. The `break_start` / `break_end` attributes on the calendar handle the 15:15-15:30 CT settlement break.

#### 3.4 ClickHouse column proliferation management

With 12+ exchanges, column count grows. Consider a different storage approach for Phase 3:

```sql
-- Alternative: single JSONB column (ClickHouse 24.1+ has JSON type)
exchange_sessions JSON DEFAULT '{}'

-- Or: Map column
exchange_sessions Map(String, UInt8) DEFAULT map()

-- Query: exchange_sessions['newyork'] = 1
```

The `Map(String, UInt8)` approach is flexible but loses the ability to use skip indexes on individual session columns. For most analytics queries (which filter by one session at a time), a materialized column per session is more performant.

**Recommendation**: Stick with explicit columns for the 4 primary sessions (Phase 1-2). Use `Map` type for Phase 3 extended sessions, with materialized columns added on-demand for frequently-queried exchanges.

---

## ClickHouse Pipeline Compatibility

### Current ClickHouse flow

```
close_time_ms (Int64, epoch ms)
    -> intDiv(close_time_ms, 1000) -> toDateTime()
    -> toTimezone('America/New_York')
    -> toHour() -> compare against integer range
```

### Phase 1 ClickHouse flow (sub-hour)

```
close_time_ms (Int64, epoch ms)
    -> intDiv(close_time_ms, 1000) -> toDateTime()
    -> toTimezone('America/New_York')
    -> (toHour() * 60 + toMinute()) -> compare against minute ranges
```

The `toMinute()` function is native ClickHouse and adds negligible cost. The `toTimezone()` call (which handles DST) is the expensive part, and it is already present.

### Phase 2 ClickHouse flow (holidays)

```
-- Same as Phase 1, plus:
AND toDate(ts_local) NOT IN (
    SELECT holiday_date
    FROM opendeviationbar_cache.exchange_holidays
    WHERE exchange_code = 'XNYS'
      AND early_close_time IS NULL
)
```

The subquery is a small lookup (~300 rows per exchange for 2017-2030). ClickHouse optimizes `IN (subquery)` as a hash set. The `ALTER TABLE UPDATE` mutation processes rows in bulk, so the holiday lookup cost is amortized.

For **ongoing inserts** (sidecar streaming path), session flags are computed in Python (via `enrich_exchange_sessions()`) before INSERT, so the ClickHouse holiday table is only needed for backfill migrations.

### Key invariant

**Python and ClickHouse must agree.** After any change to session definitions, run `migrate_exchange_sessions()` to recompute all ClickHouse session columns, then verify with `check_exchange_session_coverage()`. The test `test_session_definitions_match_ouroboros` in `test_exchange_sessions.py` enforces structural parity.

---

## Testing Strategy

### Phase 1 tests

```python
class TestSubHourSessions:
    def test_nyse_opens_at_930(self):
        """NYSE should be active at 9:35 ET but not 9:25 ET."""
        # 9:25 ET in winter = 14:25 UTC
        ts_before = datetime(2024, 1, 15, 14, 25, tzinfo=UTC)
        assert not is_in_session(EXCHANGE_SESSIONS["newyork"], ts_before)

        # 9:35 ET in winter = 14:35 UTC
        ts_after = datetime(2024, 1, 15, 14, 35, tzinfo=UTC)
        assert is_in_session(EXCHANGE_SESSIONS["newyork"], ts_after)

    def test_tse_lunch_break(self):
        """TSE lunch break (11:30-12:30 JST) should be inactive."""
        # 12:00 JST = 03:00 UTC
        ts_lunch = datetime(2024, 1, 15, 3, 0, tzinfo=UTC)
        assert not is_in_session(EXCHANGE_SESSIONS["tokyo"], ts_lunch)

    def test_tse_morning_session(self):
        """TSE morning session (09:00-11:30 JST) should be active."""
        # 10:00 JST = 01:00 UTC
        ts_morning = datetime(2024, 1, 15, 1, 0, tzinfo=UTC)
        assert is_in_session(EXCHANGE_SESSIONS["tokyo"], ts_morning)

    def test_tse_afternoon_session(self):
        """TSE afternoon session (12:30-15:00 JST) should be active."""
        # 13:00 JST = 04:00 UTC
        ts_afternoon = datetime(2024, 1, 15, 4, 0, tzinfo=UTC)
        assert is_in_session(EXCHANGE_SESSIONS["tokyo"], ts_afternoon)

    def test_lse_close_at_1630(self):
        """LSE closes at 16:30, not 17:00."""
        # 16:45 GMT = 16:45 UTC (winter)
        ts_after_close = datetime(2024, 1, 15, 16, 45, tzinfo=UTC)
        assert not is_in_session(EXCHANGE_SESSIONS["london"], ts_after_close)

    def test_clickhouse_sql_uses_minutes(self):
        """Generated SQL should use toMinute() for sub-hour precision."""
        sql = _build_session_update_sql("newyork", EXCHANGE_SESSIONS["newyork"])
        assert "toMinute" in sql
        assert "570" in sql  # 9*60+30 = 570
        assert "960" in sql  # 16*60+0 = 960
```

### Phase 2 tests

```python
class TestHolidayExclusion:
    def test_christmas_day_inactive(self):
        """No exchange should be active on Christmas Day."""
        # Dec 25, 2024 is a Wednesday
        ts = datetime(2024, 12, 25, 15, 0, tzinfo=UTC)  # 10 AM ET
        assert not is_session_active("newyork", ts)
        assert not is_session_active("london", ts)

    def test_japanese_new_year(self):
        """TSE closed Jan 1-3."""
        ts = datetime(2024, 1, 2, 1, 0, tzinfo=UTC)  # 10 AM JST
        assert not is_session_active("tokyo", ts)

    def test_nyse_early_close_day_after_thanksgiving(self):
        """NYSE closes at 1:00 PM ET on Black Friday."""
        # Nov 29, 2024 (Friday after Thanksgiving)
        # 13:30 ET = 18:30 UTC
        ts = datetime(2024, 11, 29, 18, 30, tzinfo=UTC)
        assert not is_session_active("newyork", ts)

    def test_regular_weekday_still_active(self):
        """Normal trading day should still work."""
        ts = datetime(2024, 6, 10, 15, 0, tzinfo=UTC)  # Monday 10 AM ET
        assert is_session_active("newyork", ts)
```

---

## Rollout Checklist

### Phase 1

- [ ] Update `ExchangeSessionDef` and `EXCHANGE_SESSIONS` in `ouroboros.py`
- [ ] Update `is_in_session()` / `get_active_exchange_sessions()` in `ouroboros.py`
- [ ] Update `_build_session_update_sql()` in `clickhouse/migrations.py`
- [ ] Add backward-compat shim for `EXCHANGE_SESSION_HOURS`
- [ ] Update `test_exchange_sessions.py` and `test_ouroboros.py`
- [ ] Run `migrate_exchange_sessions()` on bigblack to recompute 42M rows
- [ ] Verify with `check_exchange_session_coverage()` (NYSE count should decrease slightly)
- [ ] Update `enrich_exchange_sessions()` if its hourly-dedup needs sub-hour granularity (it does -- floor to 30 min instead of 1 hour for TSE lunch break boundary)

### Phase 2

- [ ] Add `exchange_calendars` to `pyproject.toml` (dev + runtime dependency)
- [ ] Create `session_calendar.py` module
- [ ] Create `exchange_holidays` ClickHouse table
- [ ] Write `scripts/populate_holiday_table.py`
- [ ] Update `is_in_session()` to delegate to `exchange_calendars.is_open_on_minute()`
- [ ] Update ClickHouse SQL to join against holiday table
- [ ] Run one-time backfill migration on bigblack
- [ ] Add holiday-specific tests
- [ ] Schedule annual re-population of holiday table (or populate through 2099 upfront)

### Phase 3

- [ ] Design `SessionType` enum and column schema
- [ ] Add extended exchange definitions
- [ ] Decide column strategy (explicit vs. Map type)
- [ ] Implement pre-market / after-hours detection
- [ ] Migration for new columns

---

## Risk Assessment

| Phase | Risk                                                                  | Mitigation                                                                                               |
| ----- | --------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------- |
| 1     | Session flag values change for existing bars                          | One-time `migrate_exchange_sessions()` recomputes all; no data loss                                      |
| 1     | Consumers rely on exact flag values                                   | Session flags are enrichment columns, not used in bar construction; ML models should be retrained anyway |
| 2     | `exchange_calendars` dependency adds weight                           | Library is well-maintained (Quantopian lineage); pin version                                             |
| 2     | Holiday data becomes stale                                            | Populate through 2099 upfront; `exchange_calendars` updates annually                                     |
| 2     | `is_open_on_minute()` returns different results than our custom logic | Phase 2 replaces Phase 1 logic entirely; run comparison test on 1 year of data before cutover            |
| 3     | Column proliferation in ClickHouse                                    | Use Map type for extended sessions; keep explicit columns only for primary 4                             |

---

## Summary

| Phase | What Changes                     | Dependency           | Effort    | Impact                                         |
| ----- | -------------------------------- | -------------------- | --------- | ---------------------------------------------- |
| 1     | Sub-hour precision, lunch breaks | None                 | 1-2 hours | Fixes NYSE 9:30, TSE lunch break               |
| 2     | Holiday calendars, early closes  | `exchange_calendars` | 3-4 hours | Eliminates all false-positive holiday flags    |
| 3     | Pre/after-hours, 12+ exchanges   | Same                 | 4-6 hours | Full session taxonomy for multi-asset analysis |

Phase 1 should be done immediately -- it fixes factual errors with zero new dependencies. Phase 2 is the production-grade solution and should follow within the same release cycle. Phase 3 is a research-driven expansion that can be prioritized based on which exchange correlations prove most valuable for the trading signals being developed.
