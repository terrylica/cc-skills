# Exchange Registry Pattern

Frozen dataclass registry for exchange configuration. Single source of truth — adding a new exchange requires only one dict entry.

## ExchangeConfig Dataclass

```python
from dataclasses import dataclass
from typing import Dict


@dataclass(frozen=True)
class ExchangeConfig:
    """
    Immutable configuration for a single exchange.

    Attributes:
        code: ISO 10383 MIC code (e.g., "XNYS" for NYSE)
        name: Full exchange name
        currency: Primary currency
        timezone: IANA timezone (DST handled by exchange_calendars)
        country: Country name
        open_hour: Trading start hour in local time (24h)
        open_minute: Trading start minute
        close_hour: Trading close hour in local time (24h)
        close_minute: Trading close minute
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
```

## Registry (10 Exchanges)

```python
EXCHANGES: Dict[str, ExchangeConfig] = {
    "nyse": ExchangeConfig(
        code="XNYS", name="New York Stock Exchange",
        currency="USD", timezone="America/New_York", country="United States",
        open_hour=9, open_minute=30, close_hour=16, close_minute=0,
    ),
    "lse": ExchangeConfig(
        code="XLON", name="London Stock Exchange",
        currency="GBP", timezone="Europe/London", country="United Kingdom",
        open_hour=8, open_minute=0, close_hour=16, close_minute=30,
    ),
    "xswx": ExchangeConfig(
        code="XSWX", name="SIX Swiss Exchange",
        currency="CHF", timezone="Europe/Zurich", country="Switzerland",
        open_hour=9, open_minute=0, close_hour=17, close_minute=30,
    ),
    "xfra": ExchangeConfig(
        code="XFRA", name="Frankfurt Stock Exchange",
        currency="EUR", timezone="Europe/Berlin", country="Germany",
        open_hour=9, open_minute=0, close_hour=17, close_minute=30,
    ),
    "xtse": ExchangeConfig(
        code="XTSE", name="Toronto Stock Exchange",
        currency="CAD", timezone="America/Toronto", country="Canada",
        open_hour=9, open_minute=30, close_hour=16, close_minute=0,
    ),
    "xnze": ExchangeConfig(
        code="XNZE", name="New Zealand Exchange",
        currency="NZD", timezone="Pacific/Auckland", country="New Zealand",
        open_hour=10, open_minute=0, close_hour=16, close_minute=45,
    ),
    "xtks": ExchangeConfig(
        code="XTKS", name="Tokyo Stock Exchange",
        currency="JPY", timezone="Asia/Tokyo", country="Japan",
        open_hour=9, open_minute=0, close_hour=15, close_minute=0,
        # Lunch break: 11:30-12:30 JST (handled by exchange_calendars)
    ),
    "xasx": ExchangeConfig(
        code="XASX", name="Australian Securities Exchange",
        currency="AUD", timezone="Australia/Sydney", country="Australia",
        open_hour=10, open_minute=0, close_hour=16, close_minute=0,
    ),
    "xhkg": ExchangeConfig(
        code="XHKG", name="Hong Kong Stock Exchange",
        currency="HKD", timezone="Asia/Hong_Kong", country="Hong Kong",
        open_hour=9, open_minute=30, close_hour=16, close_minute=0,
        # Lunch break: 12:00-13:00 HKT (handled by exchange_calendars)
    ),
    "xses": ExchangeConfig(
        code="XSES", name="Singapore Exchange",
        currency="SGD", timezone="Asia/Singapore", country="Singapore",
        open_hour=9, open_minute=0, close_hour=17, close_minute=0,
        # Lunch break: 12:00-13:00 SGT (handled by exchange_calendars)
    ),
}
```

## Helper Functions

```python
def get_exchange_names() -> list[str]:
    """Get all registry keys: ["nyse", "lse", "xswx", ...]"""
    return list(EXCHANGES.keys())

def get_exchange_config(name: str) -> ExchangeConfig:
    """Lookup by name. Raises ValueError with available list on miss."""
    if name not in EXCHANGES:
        available = ", ".join(EXCHANGES.keys())
        raise ValueError(f"Unknown exchange: {name}. Available: {available}")
    return EXCHANGES[name]
```

## Adding a New Exchange

1. Find the ISO 10383 MIC code (e.g., `XBOM` for BSE India)
2. Verify `exchange_calendars` supports it: `xcals.get_calendar("XBOM")`
3. Add one entry to `EXCHANGES` dict
4. Everything else propagates: SessionDetector picks it up, columns are named `is_xbom_session`

## Source

Canonical: `~/eon/exness-data-preprocess/src/exness_data_preprocess/exchanges.py`
