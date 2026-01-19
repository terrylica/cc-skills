# Crypto Market Considerations

## Annualization: sqrt(7) and sqrt(365)

**CRITICAL**: Crypto trades 24/7, 365 days/year.

```python
# CORRECT for crypto
DAYS_PER_WEEK_CRYPTO = 7
DAYS_PER_YEAR_CRYPTO = 365

weekly_sharpe = daily_sharpe * np.sqrt(DAYS_PER_WEEK_CRYPTO)  # sqrt(7) = 2.65
annual_sharpe = daily_sharpe * np.sqrt(DAYS_PER_YEAR_CRYPTO)  # sqrt(365) = 19.1

# WRONG for crypto (equity assumptions)
# weekly_sharpe = daily_sharpe * np.sqrt(5)  # DON'T DO THIS
# annual_sharpe = daily_sharpe * np.sqrt(252)  # DON'T DO THIS
```

## Session Definitions (UTC)

```yaml
sessions:
  asia:
    start: "00:00"
    end: "08:00"
    characteristics: "Lower volume, mean-reversion tendency"

  europe:
    start: "08:00"
    end: "16:00"
    characteristics: "Increasing volume, momentum starts"

  americas:
    start: "14:00"
    end: "22:00"
    characteristics: "Highest volume, trend continuation"

  london_ny_overlap:
    start: "14:00"
    end: "16:00"
    characteristics: "Peak liquidity, best for execution"

  overnight:
    start: "22:00"
    end: "08:00"
    characteristics: "Lowest liquidity, higher spreads"
```

## Session Filter Implementation

```python
from datetime import time
from zoneinfo import ZoneInfo

LONDON_TZ = ZoneInfo("Europe/London")
NY_TZ = ZoneInfo("America/New_York")

def is_tradeable_hour(ts: pd.Timestamp) -> bool:
    """London 08:00 to NY 16:00 filter.

    Use for institutional-hours evaluation.
    """
    london_time = ts.astimezone(LONDON_TZ)
    ny_time = ts.astimezone(NY_TZ)

    # After London open AND before NY close
    after_london = london_time.time() >= time(8, 0)
    before_ny_close = ny_time.time() < time(16, 0)

    # Not weekend
    weekday = ts.weekday()
    is_weekday = weekday < 5

    return after_london and before_ny_close and is_weekday


def compute_tradeable_mask(timestamps: np.ndarray) -> np.ndarray:
    """Boolean mask for tradeable bars."""
    return np.array([
        is_tradeable_hour(pd.Timestamp(ts, tz="UTC"))
        for ts in timestamps
    ])
```

## Weekend/Weekday Split

Research shows distinct characteristics:

```python
def compute_weekend_weekday_split(
    pnl: np.ndarray,
    timestamps: np.ndarray
) -> dict:
    """Separate metrics for weekends vs weekdays.

    Empirical findings (Bitcoin 2014-2024):
    - Weekend volume: 60-70% of weekday
    - Weekend volatility: Lower
    - Weekend momentum: Higher returns (Monday effect)
    """
    df = pd.DataFrame({
        "pnl": pnl,
        "ts": pd.to_datetime(timestamps, utc=True)
    })
    df["is_weekend"] = df["ts"].dt.dayofweek >= 5

    weekday_pnl = df[~df["is_weekend"]]["pnl"].values
    weekend_pnl = df[df["is_weekend"]]["pnl"].values

    def safe_sharpe(arr):
        if len(arr) < 2 or np.std(arr) < 1e-10:
            return 0.0
        return float(np.mean(arr) / np.std(arr))

    return {
        "sharpe_weekday": safe_sharpe(weekday_pnl),
        "sharpe_weekend": safe_sharpe(weekend_pnl),
        "n_weekday_bars": len(weekday_pnl),
        "n_weekend_bars": len(weekend_pnl),
        "pnl_frac_weekend": (
            weekend_pnl.sum() / (weekday_pnl.sum() + weekend_pnl.sum())
            if (weekday_pnl.sum() + weekend_pnl.sum()) != 0 else 0.0
        )
    }
```

## Funding Rate Exposure

For perpetual futures strategies:

```python
def estimate_funding_impact(
    positions: np.ndarray,
    timestamps: np.ndarray,
    avg_funding_rate_8h: float = 0.0001  # 1 bp per 8h
) -> float:
    """Estimate funding cost/income for perpetuals.

    Funding settles every 8 hours (00:00, 08:00, 16:00 UTC).
    Long pays short when rate > 0.

    Args:
        positions: Position sizes (positive = long)
        timestamps: Position timestamps
        avg_funding_rate_8h: Average 8h funding rate (positive = longs pay)

    Returns:
        Total funding PnL (negative = cost)
    """
    df = pd.DataFrame({
        "position": positions,
        "ts": pd.to_datetime(timestamps, utc=True)
    })

    # Funding times
    df["hour"] = df["ts"].dt.hour
    df["is_funding"] = df["hour"].isin([0, 8, 16])

    # Funding impact: -position * rate (longs pay when rate > 0)
    funding_events = df[df["is_funding"]]
    total_funding = -(funding_events["position"] * avg_funding_rate_8h).sum()

    return float(total_funding)
```

## UTC Day Boundaries

```python
def group_by_utc_day(
    pnl: np.ndarray,
    timestamps: np.ndarray
) -> pd.DataFrame:
    """Group by UTC calendar day.

    CRITICAL: Always use UTC for crypto aggregation.
    """
    df = pd.DataFrame({
        "pnl": pnl,
        "ts": pd.to_datetime(timestamps, utc=True)  # Explicit UTC
    })
    df["date"] = df["ts"].dt.date

    return df.groupby("date").agg({
        "pnl": "sum",
        "ts": "count"  # Bar count per day
    }).rename(columns={"ts": "n_bars"})
```

## Dual-View Evaluation

For comprehensive analysis:

```yaml
dual_view:
  session_filtered:
    purpose: "Strategy performance evaluation"
    filter: "London 08:00 to NY 16:00, weekdays only"
    use_for:
      - "Primary Sharpe calculation"
      - "Risk metrics"
      - "Go/no-go decisions"

  all_bars:
    purpose: "Regime detection and data quality"
    filter: "None (all bars)"
    use_for:
      - "Bar count stability diagnostic"
      - "Weekend/weekday comparison"
      - "Volatility regime detection"
```

```python
def compute_dual_view_metrics(
    predictions: np.ndarray,
    actuals: np.ndarray,
    timestamps: np.ndarray
) -> dict:
    """Compute metrics for both views."""
    from rangebar_metrics import evaluate_fold  # Your metrics function

    # All bars view
    all_bars = evaluate_fold(predictions, actuals, None, timestamps)

    # Session-filtered view
    mask = compute_tradeable_mask(timestamps)
    filtered = evaluate_fold(predictions, actuals, mask, timestamps)

    return {
        "oos_metrics": filtered,      # Primary
        "oos_metrics_all": all_bars   # Diagnostic
    }
```
