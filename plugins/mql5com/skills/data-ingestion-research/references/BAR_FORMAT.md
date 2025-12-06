**Skill**: [MQL5 Data Ingestion Research (UNVALIDATED)](/skills/mql5-data-ingestion-research/SKILL.md)

# MT5 M1 Bar Format Specification (UNVALIDATED)

**Status**: 🔬 Research | ⚠️ Not Tested
**Source**: [CustomRatesUpdate() Documentation](https://www.mql5.com/en/docs/customsymbols/customratesupdate)

______________________________________________________________________

## When to Use Bars vs Ticks

### Use M1 Bars When:

- Tick-level data not available
- Dataset too large (>100M ticks)
- Only need OHLC for strategy backtesting

### Use Ticks When:

- Testing strategies sensitive to bid/ask spread
- Need sub-minute granularity
- Want "Every tick based on real ticks" tester mode

**Recommendation**: If exness-data-preprocess provides ticks, prefer tick import. MT5 can build bars from ticks.

______________________________________________________________________

## CSV Format for CustomRatesUpdate()

### Required Format

```csv
Date,Time,Open,High,Low,Close,TickVolume,Volume,Spread
2024.01.02,00:00:00,1.10024,1.10136,1.10024,1.10070,18,54000000,44
2024.01.02,00:01:00,1.10071,1.10085,1.10065,1.10078,12,36000000,42
2024.01.02,00:02:00,1.10079,1.10092,1.10075,1.10088,15,45000000,43
```

**Critical Constraint**: All bars MUST be **M1 (1-minute) resolution**

______________________________________________________________________

## MqlRates Structure Mapping

### C++ Structure (Reference)

```cpp
struct MqlRates {
   datetime time;         // Bar open time (M1 only)
   double   open;         // Open price
   double   high;         // High price
   double   low;          // Low price
   double   close;        // Close price
   long     tick_volume;  // Tick count in bar
   int      spread;       // Spread in points
   long     real_volume;  // Trade volume
};
```

### Field Requirements

| Field         | Required | Type     | Constraints                 | Notes                          |
|---------------|----------|----------|-----------------------------|--------------------------------|
| `time`        | ✅ YES    | datetime | M1 open time, no duplicates | Format: `YYYY.MM.DD HH:MM:SS`  |
| `open`        | ✅ YES    | double   | > 0                         | First price in minute          |
| `high`        | ✅ YES    | double   | ≥ max(open, close, low)     | Highest price in minute        |
| `low`         | ✅ YES    | double   | ≤ min(open, close, high)    | Lowest price in minute         |
| `close`       | ✅ YES    | double   | > 0                         | Last price in minute           |
| `tick_volume` | ✅ YES    | long     | ≥ 0                         | Number of price changes        |
| `spread`      | ❌ NO     | int      | ≥ 0, in points (not pips)   | Set 0 if unknown               |
| `real_volume` | ❌ NO     | long     | ≥ 0                         | Trade volume, set 0 if unknown |

______________________________________________________________________

## Why M1 Only?

From official documentation:

> "The custom symbol history consists of 1-minute bars. The bars of other periods are built automatically based on the minute history."

**Implications**:

1. **Do not** generate H1, H4, D1 bars manually
1. MT5 aggregates M1 → H1 → D1 automatically
1. Attempting to insert non-M1 bars causes `CustomRatesUpdate()` to fail

**Source**: [CustomRatesUpdate() Documentation](https://www.mql5.com/en/docs/customsymbols/customratesupdate)

______________________________________________________________________

## Generating M1 Bars from Ticks (Unvalidated)

### Python Example (Exness Ticks → M1)

```python
import pandas as pd

# Load tick data
df_ticks = processor.query_ticks("EURUSD", variant="raw_spread", start_date="2024-01-01")

# Assuming df_ticks has: timestamp, bid, ask
df_ticks['mid'] = (df_ticks['bid'] + df_ticks['ask']) / 2
df_ticks['minute'] = df_ticks['timestamp'].dt.floor('1min')

# Aggregate to M1 OHLC
m1_bars = df_ticks.groupby('minute').agg({
    'mid': ['first', 'max', 'min', 'last'],  # open, high, low, close
    'timestamp': 'count'  # tick_volume
}).reset_index()

m1_bars.columns = ['time', 'open', 'high', 'low', 'close', 'tick_volume']
m1_bars['spread'] = 0  # Unknown, set to 0
m1_bars['real_volume'] = 0  # Forex OTC has no volume

# Export
m1_bars.to_csv('eurusd_m1.csv', index=False)
```

**Caveat**: Using `mid = (bid+ask)/2` loses spread information. If available, use `last` trade prices instead.

______________________________________________________________________

## Validation Rules (Pre-Import)

### Rule 1: M1 Resolution

```python
def validate_m1_resolution(df: pd.DataFrame) -> bool:
    """Returns True if all bars are exactly 1 minute apart."""
    df['time'] = pd.to_datetime(df['time'])
    time_diffs = df['time'].diff().dropna()
    return (time_diffs == pd.Timedelta(minutes=1)).all()
```

**Why**: `CustomRatesUpdate()` expects M1, rejects other periods

### Rule 2: OHLC Consistency

```python
def validate_ohlc(df: pd.DataFrame) -> bool:
    """Returns True if High ≥ max(O,C) and Low ≤ min(O,C)."""
    valid_high = (df['high'] >= df[['open', 'close']].max(axis=1)).all()
    valid_low = (df['low'] <= df[['open', 'close']].min(axis=1)).all()
    return valid_high and valid_low
```

### Rule 3: No Duplicate Times

```python
def validate_no_duplicates(df: pd.DataFrame) -> bool:
    """Returns True if no duplicate bar open times."""
    return not df['time'].duplicated().any()
```

**Why**: MT5 rejects bars with duplicate timestamps

### Rule 4: Chronological Order

```python
def validate_chronological(df: pd.DataFrame) -> bool:
    """Returns True if bars are in ascending time order."""
    df['time'] = pd.to_datetime(df['time'])
    return df['time'].is_monotonic_increasing
```

______________________________________________________________________

## MQL5 Import Script (Illustrative, Unvalidated)

```mq5
//+------------------------------------------------------------------+
//|                                              LoadBars.mq5        |
//| Load M1 bars from CSV into custom symbol                         |
//+------------------------------------------------------------------+
#property script_show_inputs
input string Sym      = "EURUSD.EXNESS";
input string Group    = "Lab";
input string CsvName  = "eurusd_m1.csv";  // in Common\Files
input bool   HasHeader = true;

void OnStart() {
  // Create symbol if doesn't exist
  if(!SymbolExist(Sym, false)) {
    if(!CustomSymbolCreate(Sym, "Custom\\"+Group, NULL)) {
      Print("CustomSymbolCreate failed: ", GetLastError());
      return;
    }
  }
  SymbolSelect(Sym, true);

  // Open CSV
  int h = FileOpen(CsvName, FILE_READ|FILE_CSV|FILE_COMMON, ',', CP_UTF8);
  if(h == INVALID_HANDLE) {
    Print("FileOpen failed: ", GetLastError());
    return;
  }

  // Skip header
  if(HasHeader) {
    string dummy;
    for(int i=0; i<9; i++) dummy = FileReadString(h);
  }

  // Read bars
  MqlRates rates[];
  int count = 0;
  const int MAX_BARS = 1000000;  // Reasonable limit
  ArrayResize(rates, MAX_BARS);

  while(!FileIsEnding(h) && count < MAX_BARS) {
    string date_str = FileReadString(h);
    string time_str = FileReadString(h);
    datetime bar_time = StringToTime(date_str + " " + time_str);

    MqlRates r;
    r.time = bar_time;
    r.open = FileReadNumber(h);
    r.high = FileReadNumber(h);
    r.low = FileReadNumber(h);
    r.close = FileReadNumber(h);
    r.tick_volume = (long)FileReadNumber(h);
    r.real_volume = (long)FileReadNumber(h);
    r.spread = (int)FileReadNumber(h);

    rates[count++] = r;

    // Skip to end of line
    while(!FileIsLineEnding(h) && !FileIsEnding(h))
      FileReadString(h);
  }

  FileClose(h);
  ArrayResize(rates, count);

  // Import
  int imported = CustomRatesUpdate(Sym, rates);
  if(imported <= 0) {
    Print("CustomRatesUpdate failed: ", GetLastError());
  } else {
    PrintFormat("Imported %d M1 bars into %s", imported, Sym);
  }
}
```

**Status**: Illustrative only, not tested in live MT5

______________________________________________________________________

## Alternative: Use Exness OHLC Query

Instead of ticks, query pre-aggregated bars:

```python
# Query M1 bars directly
df = processor.query_ohlc("EURUSD", timeframe="1m", start_date="2024-01-01")

# Transform to MT5 format
df['tick_volume'] = 0  # Unknown
df['spread'] = 0       # Unknown
df['real_volume'] = 0  # Forex has no volume

df[['time', 'open', 'high', 'low', 'close', 'tick_volume', 'real_volume', 'spread']].to_csv(
    'eurusd_m1.csv',
    index=False
)
```

**Advantage**: Avoids tick-to-bar aggregation step

**Disadvantage**: Cannot test strategies in "Every tick based on real ticks" mode

______________________________________________________________________

## Performance Considerations (Unvalidated)

### Batch Size

`CustomRatesUpdate()` can handle large arrays, but practical limits:

- **Test with**: 10K bars (~1 week M1 data)
- **Production**: Up to 1M bars (~2 years M1 data)

**Rationale** (from community patterns, not tested):

- M1 bars are smaller than ticks (~24 bytes vs ~56 bytes)
- Less frequent updates than tick imports

### Memory Footprint

- 1 week M1 = ~10,080 bars = ~242 KB
- 1 year M1 = ~525,600 bars = ~12.6 MB

______________________________________________________________________

## Edge Cases (Require Testing)

### Edge Case 1: Market Gaps (Weekends)

**Question**: Do we need continuous M1 bars, or can we skip weekends?

**Hypothesis**: Can skip; MT5 handles gaps

**Test**: Import Mon-Fri only, check if weekend gap causes issues

### Edge Case 2: Missing Minutes

**Question**: What if a minute has no ticks (very illiquid pair)?

**Hypothesis**: Skip that minute; MT5 interpolates

**Test**: Create synthetic data with 5-minute gap

### Edge Case 3: Duplicate Bar Times

**Question**: If CSV has duplicate M1 timestamps, does import fail?

**Hypothesis**: Yes, based on "no duplicates" constraint

**Test**: Intentionally duplicate a bar, observe error

______________________________________________________________________

## Comparison: Ticks vs M1 Bars

| Aspect           | Tick Import                      | M1 Bar Import      |
|------------------|----------------------------------|--------------------|
| **Data Size**    | Large (100s MB)                  | Moderate (10s MB)  |
| **Import Speed** | Slower (500K chunks)             | Faster             |
| **Tester Mode**  | "Every tick based on real ticks" | "1 minute OHLC"    |
| **Spread Info**  | Preserved (bid/ask)              | Lost (only OHLC)   |
| **Use Case**     | Scalping, HFT strategies         | Swing, day trading |
| **Source**       | `query_ticks()`                  | `query_ohlc()`     |

______________________________________________________________________

## Changelog

**2025-10-27**: Initial specification

- Documented M1 bar CSV format
- Explained "M1-only" constraint
- Created 4 validation rules
- Provided Python aggregation example (unvalidated)
