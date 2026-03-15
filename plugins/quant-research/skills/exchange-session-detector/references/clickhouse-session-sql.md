# ClickHouse Session Detection SQL

Server-side session detection using ClickHouse's `toTimezone()` for DST-aware hour extraction.

## How It Works

ClickHouse's `toTimezone()` accepts IANA timezone names and handles DST transitions automatically, matching Python's `zoneinfo` behavior. This means the same session logic can run server-side without round-tripping data to Python.

## SQL Pattern: ALTER TABLE UPDATE

Used by `opendeviationbar-py` to backfill session columns on existing data:

```python
_SESSION_UPDATES = [
    {"column": "exchange_session_sydney",  "tz": "Australia/Sydney",  "start": "10", "end": "16"},
    {"column": "exchange_session_tokyo",   "tz": "Asia/Tokyo",        "start": "9",  "end": "15"},
    {"column": "exchange_session_london",  "tz": "Europe/London",     "start": "8",  "end": "17"},
    {"column": "exchange_session_newyork", "tz": "America/New_York",  "start": "10", "end": "16"},
]

def _build_session_update_sql(session, *, symbol=None):
    col, tz = session["column"], session["tz"]
    start, end = session["start"], session["end"]

    ts_local = f"toTimezone(toDateTime(intDiv(close_time_ms, 1000)), '{tz}')"
    condition = (
        f"toHour({ts_local}) >= {start} "
        f"AND toHour({ts_local}) < {end} "
        f"AND toDayOfWeek({ts_local}) <= 5"
    )

    where = f"symbol = '{symbol}'" if symbol else "1 = 1"

    return (
        f"ALTER TABLE opendeviationbar_cache.open_deviation_bars "
        f"UPDATE {col} = if({condition}, 1, 0) "
        f"WHERE {where}"
    )
```

## Generated SQL Example

```sql
ALTER TABLE opendeviationbar_cache.open_deviation_bars
UPDATE exchange_session_newyork = if(
    toHour(toTimezone(toDateTime(intDiv(close_time_ms, 1000)), 'America/New_York')) >= 10
    AND toHour(toTimezone(toDateTime(intDiv(close_time_ms, 1000)), 'America/New_York')) < 16
    AND toDayOfWeek(toTimezone(toDateTime(intDiv(close_time_ms, 1000)), 'America/New_York')) <= 5,
    1, 0
) WHERE 1 = 1
```

## Limitations vs Python exchange_calendars

| Feature            | ClickHouse `toTimezone()`     | Python `exchange_calendars`    |
| ------------------ | ----------------------------- | ------------------------------ |
| DST transitions    | Automatic (IANA)              | Automatic (IANA)               |
| Weekend exclusion  | `toDayOfWeek() <= 5`          | `is_open_on_minute()`          |
| Holiday detection  | Manual (needs calendar table) | Built-in `regular_holidays`    |
| Lunch breaks       | Manual (compound condition)   | Built-in `is_open_on_minute()` |
| Early closes       | Manual                        | Built-in                       |
| Sub-hour precision | Possible but verbose          | Built-in                       |

For production accuracy with holidays and lunch breaks, the recommended approach is:

1. Compute session flags in Python using `exchange_calendars`
2. Write flags back to ClickHouse as columns
3. Use ClickHouse `toTimezone()` only for simple hour-range checks where holidays don't matter

## Holiday Table Pattern (Advanced)

If you need server-side holiday detection without Python:

```sql
-- Create holiday calendar table
CREATE TABLE exchange_holidays (
    exchange String,
    holiday_date Date,
    holiday_name String
) ENGINE = MergeTree()
ORDER BY (exchange, holiday_date);

-- Insert holidays from exchange_calendars (one-time Python script)
-- Then join in queries:
SELECT *
FROM my_table t
LEFT JOIN exchange_holidays h
    ON h.exchange = 'NYSE'
    AND h.holiday_date = toDate(toTimezone(toDateTime(intDiv(t.close_time_ms, 1000)), 'America/New_York'))
WHERE h.holiday_date IS NULL  -- Not a holiday
```

## Source

Canonical: `~/eon/opendeviationbar-py/python/opendeviationbar/clickhouse/migrations.py`
