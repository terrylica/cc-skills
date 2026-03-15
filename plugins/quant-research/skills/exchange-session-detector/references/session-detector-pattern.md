# SessionDetector Pattern

Complete implementation pattern for DST-aware, holiday-aware, lunch-break-aware session detection.

## Class Structure

```python
"""
Exchange calendar operations and session/holiday detection.

Uses exchange_calendars library to determine trading hours, holidays, and
lunch breaks for 10 global exchanges.

Handles:
- Exchange calendar initialization from EXCHANGES registry
- Holiday detection for NYSE and LSE (official closures only)
- Major holiday detection (both NYSE and LSE closed)
- Trading session detection with lunch break support
  (Tokyo 11:30-12:30 JST, Hong Kong 12:00-13:00 HKT, Singapore 12:00-13:00 SGT)

Performance:
- Pre-computes trading minutes for vectorized lookup (2.2x speedup)
- Preserves accuracy via exchange_calendars.is_open_on_minute()
"""

from datetime import date
from typing import Any, Dict, Set

import exchange_calendars as xcals
import pandas as pd

from exchanges import EXCHANGES


class SessionDetector:
    """
    Detect trading sessions and holidays for global exchanges.

    Lunch Breaks (automatically handled by exchange_calendars):
    - Tokyo (XTKS): 11:30-12:30 JST
    - Hong Kong (XHKG): 12:00-13:00 HKT
    - Singapore (XSES): 12:00-13:00 SGT
    """

    def __init__(self):
        self.calendars: Dict[str, Any] = {}
        for exchange_name, exchange_config in EXCHANGES.items():
            self.calendars[exchange_name] = xcals.get_calendar(exchange_config.code)

    def _precompute_trading_minutes(
        self, start_date: date, end_date: date
    ) -> Dict[str, Set[pd.Timestamp]]:
        """
        Pre-compute trading minutes for all exchanges in date range.

        Returns dict mapping exchange_name to set of trading minutes
        (timezone-aware UTC timestamps). Enables vectorized .isin() lookup.

        Uses calendar.is_open_on_minute() during pre-computation to respect:
        - Lunch breaks (Tokyo, Hong Kong, Singapore)
        - Trading hour changes (e.g., Tokyo extended to 15:30 on Nov 5, 2024)
        - Holidays and weekends (automatically excluded)
        """
        trading_minutes: Dict[str, Set[pd.Timestamp]] = {}

        for exchange_name, calendar in self.calendars.items():
            minutes_set: Set[pd.Timestamp] = set()

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

        return trading_minutes

    def detect_sessions_and_holidays(self, dates_df: pd.DataFrame) -> pd.DataFrame:
        """
        Add holiday and session columns to dates DataFrame.

        Args:
            dates_df: DataFrame with 'ts' column (timezone-aware UTC) and 'date' column

        Returns:
            DataFrame with added columns:
                - is_us_holiday: 1 if NYSE closed (excludes weekends)
                - is_uk_holiday: 1 if LSE closed (excludes weekends)
                - is_major_holiday: 1 if both NYSE and LSE closed
                - is_{exchange}_session: 1 if during trading hours (excludes lunch)
        """
        start_date = dates_df["ts"].min().date()
        end_date = dates_df["ts"].max().date()

        # Holiday detection — NYSE and LSE only
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
            (dates_df["is_us_holiday"] == 1) & (dates_df["is_uk_holiday"] == 1)
        ).astype(int)

        # Session detection — pre-compute then vectorize
        trading_minutes = self._precompute_trading_minutes(start_date, end_date)

        for exchange_name in self.calendars.keys():
            col_name = f"is_{exchange_name}_session"
            dates_df[col_name] = (
                dates_df["ts"].isin(trading_minutes[exchange_name]).astype(int)
            )

        return dates_df
```

## Usage Example

```python
import pandas as pd

detector = SessionDetector()

# Build a DataFrame with minute-level timestamps
dates_df = pd.DataFrame({
    "ts": pd.date_range("2024-01-01", "2024-12-31", freq="1min", tz="UTC"),
})
dates_df["date"] = dates_df["ts"].dt.date

result = detector.detect_sessions_and_holidays(dates_df)

# Result columns:
# is_us_holiday, is_uk_holiday, is_major_holiday,
# is_nyse_session, is_lse_session, is_xswx_session, is_xfra_session,
# is_xtse_session, is_xnze_session, is_xtks_session, is_xasx_session,
# is_xhkg_session, is_xses_session
```

## Performance Notes

- **Pre-computation cost**: ~2-5 seconds for 1 year of data across 10 exchanges
- **Lookup cost**: O(1) per timestamp via set `.isin()`
- **Speedup**: 2.2x vs per-timestamp `.apply(calendar.is_open_on_minute)`
- **Memory**: ~500K timestamps per exchange per year (trading minutes only)

## Key API from exchange_calendars

```python
cal = xcals.get_calendar("XNYS")

# Session queries
cal.sessions_in_range(start_date, end_date)  # Trading days (DatetimeIndex)
cal.session_open(session_date)               # Market open (Timestamp, UTC)
cal.session_close(session_date)              # Market close (Timestamp, UTC)
cal.is_open_on_minute(timestamp)             # Respects lunch breaks + holidays

# Holiday queries
cal.regular_holidays.holidays(start, end)    # Official closure dates
cal.adhoc_holidays                           # One-off closures
```

## Source

Canonical: `~/eon/exness-data-preprocess/src/exness_data_preprocess/session_detector.py`
