**Skill**: [MQL5 Data Ingestion Research (UNVALIDATED)](/skills/mql5-data-ingestion-research/SKILL.md)

# MT5 Tick Data Format Specification (UNVALIDATED)

**Status**: 🔬 Research | ⚠️ Not Tested
**Source**: [MqlTick Structure](https://www.mql5.com/en/docs/constants/structures/mqltick)

______________________________________________________________________

## CSV Format for CustomTicksReplace()

### Minimal Format (Recommended)

```csv
unix_ms,bid,ask,last,volume_real
1688342627212,1.14175,1.14210,0,0
1688342627312,1.14176,1.14211,0,0
1688342627412,1.14175,1.14210,0,0
```

**Columns**:

1. `unix_ms` (int64): Unix timestamp in **milliseconds** since epoch
1. `bid` (double): Bid price (0 if not applicable)
1. `ask` (double): Ask price (0 if not applicable)
1. `last` (double): Last trade price (0 if not applicable)
1. `volume_real` (double): Trade volume (0 if not applicable)

### Field Requirements

| Field         | Required       | Type   | Constraints                         | Default if Missing     |
|---------------|----------------|--------|-------------------------------------|------------------------|
| `unix_ms`     | ✅ YES          | int64  | > 0, strictly ascending             | N/A (import fails)     |
| `bid`         | ⚠️ Conditional | double | ≥ 0, if >0 then `ask` should be set | 0 (MT5 infers no bid)  |
| `ask`         | ⚠️ Conditional | double | ≥ 0, if >0 then `bid` ≤ `ask`       | 0 (MT5 infers no ask)  |
| `last`        | ⚠️ Conditional | double | ≥ 0                                 | 0 (MT5 infers no last) |
| `volume_real` | ❌ NO           | double | ≥ 0                                 | 0                      |

**Conditional Logic**:

- At least ONE of `bid`, `ask`, or `last` MUST be > 0 per tick
- If both `bid` and `ask` > 0, then `bid ≤ ask` must hold

______________________________________________________________________

## MqlTick Structure Mapping

### C++ Structure (Reference)

```cpp
struct MqlTick {
   datetime      time;          // Time of last price update (seconds)
   long          time_msc;      // Time in milliseconds (PRIMARY)
   double        bid;           // Current Bid price
   double        ask;           // Current Ask price
   double        last;          // Price of last deal (Last)
   ulong         volume;        // Volume for current Last price (deprecated)
   long          time_msc;      // Time of tick in milliseconds
   uint          flags;         // Tick flags (auto-inferred by MT5)
   double        volume_real;   // Volume for current Last price with greater accuracy
};
```

**Key Insights**:

- `time_msc` is **primary**; `time` is derived as `time_msc / 1000`
- `flags` are **auto-generated** by MT5 based on which prices are non-zero
- `volume_real` supersedes deprecated `volume` field

### Flag Auto-Inference (MT5 Internal)

When you provide ticks via `CustomTicksReplace()`, MT5 sets flags:

| Condition         | Flag Set           | Meaning                    |
|-------------------|--------------------|----------------------------|
| `bid > 0`         | `TICK_FLAG_BID`    | Bid price changed          |
| `ask > 0`         | `TICK_FLAG_ASK`    | Ask price changed          |
| `last > 0`        | `TICK_FLAG_LAST`   | Last price (trade) changed |
| `volume_real > 0` | `TICK_FLAG_VOLUME` | Volume present             |

**Source**: Inferred from [CustomTicksAdd() behavior](https://www.mql5.com/en/book/advanced/custom_symbols/custom_symbols_ticks)

______________________________________________________________________

## Forex Tick Data Specifics (Exness Use Case)

### Raw Spread Variant (Preferred)

Exness provides "raw_spread" data with **separate bid and ask**:

```python
df = processor.query_ticks("EURUSD", variant="raw_spread", start_date="2024-01-01")
```

**Expected Columns** (hypothesis, needs validation):

```
timestamp, bid, ask, [spread], [volume]
```

**Transformation to MT5 Format**:

```python
import pandas as pd

# Assuming 'timestamp' is datetime64[ns]
df['unix_ms'] = (df['timestamp'].astype('int64') // 10**6)  # nanoseconds → milliseconds

# Ensure bid ≤ ask (data quality check)
assert (df['bid'] <= df['ask']).all(), "Bid > Ask detected"

# Sort by time (CRITICAL)
df = df.sort_values('unix_ms')

# Export
df[['unix_ms', 'bid', 'ask']].to_csv(
    'exness_eurusd_ticks.csv',
    index=False,
    columns=['unix_ms', 'bid', 'ask', 'last', 'volume_real'],
    header=True
)
```

**Notes**:

- Set `last=0` if no trade data (forex is OTC, trades may not exist)
- Set `volume_real=0` if volume not available

### Standard Variant (Alternative)

Exness "standard" variant provides **mid-price** (bid+ask)/2:

```python
df = processor.query_ticks("EURUSD", variant="standard", start_date="2024-01-01")
```

**Problem**: MT5 expects bid/ask, not mid-price

**Workaround** (lossy):

```python
# Assume fixed spread (e.g., 1 pip for EURUSD)
spread = 0.00010  # 1 pip
df['bid'] = df['price'] - spread/2
df['ask'] = df['price'] + spread/2
df['last'] = 0
```

**Caveat**: This **manufactures** spread and loses true bid/ask dynamics. Use raw_spread variant if available.

______________________________________________________________________

## Validation Rules (Pre-Import)

### Rule 1: Time Ordering

```python
def validate_time_order(df: pd.DataFrame) -> bool:
    """Returns True if unix_ms is strictly ascending."""
    return (df['unix_ms'].diff().dropna() > 0).all()
```

**Why**: `CustomTicksReplace()` stops at first out-of-order tick

### Rule 2: Bid/Ask Sanity

```python
def validate_bid_ask(df: pd.DataFrame) -> bool:
    """Returns True if bid ≤ ask when both > 0."""
    mask = (df['bid'] > 0) & (df['ask'] > 0)
    return (df.loc[mask, 'bid'] <= df.loc[mask, 'ask']).all()
```

### Rule 3: No Empty Ticks

```python
def validate_non_empty(df: pd.DataFrame) -> bool:
    """Returns True if each row has at least one price."""
    return ((df['bid'] > 0) | (df['ask'] > 0) | (df['last'] > 0)).all()
```

### Rule 4: No NaN/Inf

```python
import numpy as np

def validate_finite(df: pd.DataFrame) -> bool:
    """Returns True if all numeric fields are finite."""
    cols = ['unix_ms', 'bid', 'ask', 'last', 'volume_real']
    return df[cols].applymap(np.isfinite).all().all()
```

______________________________________________________________________

## Performance Considerations (Unvalidated)

### Chunk Size Recommendation

From ChatGPT dialogue (source: community patterns, not tested):

- **500,000 ticks per `CustomTicksReplace()` call**
- Rationale: Balance between memory usage and call overhead

**Implementation Pattern**:

```mq5
const int CHUNK_SIZE = 500000;
MqlTick buffer[];
ArrayResize(buffer, CHUNK_SIZE);

int fill = 0;
long chunk_start_ms = -1, chunk_end_ms = -1;

while(reading_csv) {
  buffer[fill++] = current_tick;
  if(chunk_start_ms < 0) chunk_start_ms = current_tick.time_msc;
  chunk_end_ms = current_tick.time_msc;

  if(fill == CHUNK_SIZE) {
    CustomTicksReplace(symbol, chunk_start_ms, chunk_end_ms, buffer, fill);
    fill = 0;
    chunk_start_ms = -1;
  }
}

// Flush remaining
if(fill > 0) {
  CustomTicksReplace(symbol, chunk_start_ms, chunk_end_ms, buffer, fill);
}
```

### Memory Footprint

`sizeof(MqlTick)` ≈ 56 bytes (8 fields × 8 bytes, with padding)

- 500K ticks = ~28 MB RAM per chunk
- 1M ticks CSV ≈ 50 MB disk (uncompressed)

**Validation Needed**: Measure actual memory usage in MT5

______________________________________________________________________

## Edge Cases (Require Testing)

### Edge Case 1: Sub-Millisecond Ticks

**Question**: If multiple ticks occur within same millisecond, how does MT5 handle?

**Hypothesis**: Last tick wins (overwrites previous)

**Test**: Create synthetic data with duplicate `unix_ms` values

### Edge Case 2: Large Time Gaps

**Question**: Does MT5 handle multi-year gaps in tick data?

**Example**: Import Jan 2020 data, then Jan 2024 data (4-year gap)

**Hypothesis**: Should work (each `CustomTicksReplace` call is independent)

### Edge Case 3: Zero Prices During Market Close

**Question**: What if bid=ask=last=0 during market close?

**Hypothesis**: Invalid tick (violates "at least one price" rule)

**Recommendation**: Filter out closed-market ticks before import

______________________________________________________________________

## GUI Import Alternative (Manual Testing)

For small datasets, use MT5 GUI instead of MQL5 scripts:

1. **Create Custom Symbol**:

   - Symbols → Create Custom Symbol
   - Set name: `EURUSD.EXNESS`
   - Set properties: Digits=5, Contract Size=100000

1. **Prepare CSV** (same format):

   ```csv
   Date,Time,Bid,Ask,Last,Volume
   2024.01.02,00:00:01.234,1.10456,1.10458,0,0
   ```

1. **Import via GUI**:

   - Select symbol → Ticks tab → Import Ticks
   - Map columns: Date+Time → Time, Bid → Bid, etc.
   - Click Import

**Limitation**: GUI is manual; not suitable for millions of ticks

______________________________________________________________________

## Changelog

**2025-10-27**: Initial specification

- Documented CSV structure from ChatGPT dialogue
- Mapped to MqlTick structure fields
- Created 4 validation rules
- Identified 3 edge cases requiring testing
