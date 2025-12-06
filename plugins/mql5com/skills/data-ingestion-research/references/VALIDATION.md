**Skill**: [MQL5 Data Ingestion Research (UNVALIDATED)](../SKILL.md)

# Data Validation Checklist (UNVALIDATED)

**Status**: 🔬 Research | ⚠️ Not Tested in MT5
**Purpose**: Pre-import validation to catch format errors before MT5 ingestion

---

## Validation Philosophy

**Fail Fast**: Detect errors in CSV before MT5 import to avoid:

- Silent partial imports (MT5 stops at first error)
- Corrupted custom symbol data
- Wasted import time

**Validation Stages**:

1. **Format validation**: CSV structure, column types
1. **Data quality**: Value ranges, consistency checks
1. **MT5 compatibility**: Specific MT5 constraints
1. **Smoke test**: Small dataset trial import

---

## Stage 1: Format Validation

### CSV Structure

```python
import pandas as pd

def validate_csv_structure(filepath: str, format_type: str) -> tuple[bool, str]:
    """
    Validate CSV has correct columns.

    Args:
        filepath: Path to CSV file
        format_type: 'ticks' or 'bars'

    Returns:
        (is_valid, error_message)
    """
    try:
        df = pd.read_csv(filepath, nrows=5)  # Check first 5 rows only
    except Exception as e:
        return False, f"Failed to read CSV: {e}"

    if format_type == 'ticks':
        required_cols = ['unix_ms', 'bid', 'ask', 'last', 'volume_real']
    elif format_type == 'bars':
        required_cols = ['Date', 'Time', 'Open', 'High', 'Low', 'Close',
                         'TickVolume', 'Volume', 'Spread']
    else:
        return False, f"Unknown format_type: {format_type}"

    missing = set(required_cols) - set(df.columns)
    if missing:
        return False, f"Missing columns: {missing}"

    return True, "OK"
```

**Validation**: Column names match expected format

---

## Stage 2: Data Quality Checks

### Tick Data Validation

```python
import numpy as np

def validate_tick_data(df: pd.DataFrame) -> list[str]:
    """
    Run all tick data quality checks.

    Returns:
        List of error messages (empty if valid)
    """
    errors = []

    # Check 1: Time ordering
    if not df['unix_ms'].is_monotonic_increasing:
        errors.append("CRITICAL: unix_ms not strictly ascending")
        # Show first violation
        violations = df[df['unix_ms'].diff() <= 0].head(3)
        errors.append(f"First violations:\n{violations[['unix_ms']]}")

    # Check 2: Bid/Ask sanity
    mask = (df['bid'] > 0) & (df['ask'] > 0)
    if mask.any():
        invalid = df[mask & (df['bid'] > df['ask'])]
        if not invalid.empty:
            errors.append(f"Bid > Ask in {len(invalid)} rows")
            errors.append(f"Examples:\n{invalid[['unix_ms', 'bid', 'ask']].head(3)}")

    # Check 3: Non-empty ticks
    empty_mask = (df['bid'] <= 0) & (df['ask'] <= 0) & (df['last'] <= 0)
    if empty_mask.any():
        errors.append(f"Empty ticks (all prices ≤ 0): {empty_mask.sum()} rows")

    # Check 4: Finite values
    for col in ['unix_ms', 'bid', 'ask', 'last', 'volume_real']:
        if not np.isfinite(df[col]).all():
            nan_count = df[col].isna().sum()
            inf_count = np.isinf(df[col]).sum()
            errors.append(f"{col}: {nan_count} NaN, {inf_count} Inf values")

    # Check 5: Reasonable time range (Unix ms should be ~13 digits)
    if df['unix_ms'].min() < 1_000_000_000_000:  # Before year 2001 in ms
        errors.append(f"Suspicious unix_ms min: {df['unix_ms'].min()} (maybe seconds, not ms?)")

    # Check 6: Reasonable price range (forex pairs typically 0.5 to 200)
    price_cols = ['bid', 'ask', 'last']
    for col in price_cols:
        valid_prices = df[df[col] > 0][col]
        if not valid_prices.empty:
            if valid_prices.max() > 1000:
                errors.append(f"{col}: max={valid_prices.max():.6f} (unusually high)")
            if valid_prices.min() < 0.001:
                errors.append(f"{col}: min={valid_prices.min():.6f} (unusually low)")

    return errors
```

### M1 Bar Validation

```python
def validate_bar_data(df: pd.DataFrame) -> list[str]:
    """
    Run all M1 bar quality checks.

    Returns:
        List of error messages (empty if valid)
    """
    errors = []

    # Parse datetime
    try:
        df['datetime'] = pd.to_datetime(df['Date'] + ' ' + df['Time'])
    except Exception as e:
        errors.append(f"Failed to parse Date+Time: {e}")
        return errors

    # Check 1: M1 resolution
    time_diffs = df['datetime'].diff().dropna()
    non_m1 = time_diffs[time_diffs != pd.Timedelta(minutes=1)]
    if not non_m1.empty:
        errors.append(f"Non-M1 intervals detected: {len(non_m1)} violations")
        errors.append(f"Examples:\n{df.loc[non_m1.index, ['Date', 'Time']].head(3)}")

    # Check 2: OHLC consistency
    invalid_high = df['High'] < df[['Open', 'Close']].max(axis=1)
    if invalid_high.any():
        errors.append(f"High < max(Open, Close): {invalid_high.sum()} rows")

    invalid_low = df['Low'] > df[['Open', 'Close']].min(axis=1)
    if invalid_low.any():
        errors.append(f"Low > min(Open, Close): {invalid_low.sum()} rows")

    # Check 3: No duplicates
    duplicates = df['datetime'].duplicated()
    if duplicates.any():
        errors.append(f"Duplicate bar times: {duplicates.sum()} rows")
        errors.append(f"Examples:\n{df[duplicates][['Date', 'Time']].head(3)}")

    # Check 4: Chronological order
    if not df['datetime'].is_monotonic_increasing:
        errors.append("CRITICAL: Bars not in chronological order")

    # Check 5: Positive volumes
    if (df['TickVolume'] < 0).any():
        errors.append(f"Negative TickVolume: {(df['TickVolume'] < 0).sum()} rows")

    return errors
```

---

## Stage 3: MT5-Specific Compatibility

### Symbol Properties Check

```python
def check_symbol_compatibility(pair: str, df: pd.DataFrame) -> list[str]:
    """
    Check if data matches expected symbol properties.

    Args:
        pair: e.g., 'EURUSD'
        df: Tick or bar dataframe
    """
    errors = []

    # Digit precision (EURUSD = 5, USDJPY = 3)
    expected_digits = {'EURUSD': 5, 'GBPUSD': 5, 'USDJPY': 3, 'XAUUSD': 2}

    if pair in expected_digits:
        digits = expected_digits[pair]

        # Check if prices have appropriate precision
        price_cols = ['bid', 'ask', 'last'] if 'bid' in df.columns else ['Open', 'High', 'Low', 'Close']

        for col in price_cols:
            if col in df.columns:
                prices = df[df[col] > 0][col]
                if not prices.empty:
                    # Count decimal places
                    decimals = prices.apply(lambda x: len(str(x).split('.')[-1]) if '.' in str(x) else 0)
                    if decimals.max() > digits:
                        errors.append(f"{col}: precision {decimals.max()} exceeds {pair} digits={digits}")

    return errors
```

### File Size Sanity

```python
import os

def check_file_size(filepath: str, format_type: str) -> list[str]:
    """Warn if file size is unusually large."""
    errors = []
    size_mb = os.path.getsize(filepath) / (1024**2)

    if format_type == 'ticks':
        if size_mb > 500:  # > 500 MB ticks
            errors.append(f"WARNING: Large tick file ({size_mb:.1f} MB). Consider chunking.")
    elif format_type == 'bars':
        if size_mb > 50:  # > 50 MB bars
            errors.append(f"WARNING: Large bar file ({size_mb:.1f} MB). Verify timeframe is M1.")

    return errors
```

---

## Stage 4: Smoke Test (Small Dataset)

### Test Import Strategy

```python
def create_smoke_test_csv(df: pd.DataFrame, format_type: str, output_path: str) -> str:
    """
    Create a small test CSV (first 10,000 rows) for trial import.

    Returns:
        Path to smoke test CSV
    """
    df_small = df.head(10000).copy()
    df_small.to_csv(output_path, index=False)
    return output_path
```

**Workflow**:

1. Validate full dataset (Stages 1-3)
1. Export first 10K rows as `test_import.csv`
1. Import via MT5 GUI or script
1. Verify in Strategy Tester
1. If successful, import full dataset

---

## Complete Validation Script

```python
#!/usr/bin/env python3
"""
Validate exness tick/bar data for MT5 import.

Usage:
    python validate_mt5_data.py ticks_data.csv --type ticks --pair EURUSD
    python validate_mt5_data.py bars_data.csv --type bars --pair GBPUSD
"""

import sys
import pandas as pd
import numpy as np
from pathlib import Path

def validate_all(filepath: str, format_type: str, pair: str) -> bool:
    """Run all validation stages."""

    print(f"=== MT5 Data Validation ===")
    print(f"File: {filepath}")
    print(f"Type: {format_type}")
    print(f"Pair: {pair}\n")

    # Stage 1: Format
    print("Stage 1: Format Validation")
    valid, msg = validate_csv_structure(filepath, format_type)
    if not valid:
        print(f"❌ {msg}")
        return False
    print(f"✅ {msg}\n")

    # Load full dataset
    print("Loading dataset...")
    df = pd.read_csv(filepath)
    print(f"Loaded {len(df):,} rows\n")

    # Stage 2: Data Quality
    print("Stage 2: Data Quality Checks")
    if format_type == 'ticks':
        errors = validate_tick_data(df)
    else:
        errors = validate_bar_data(df)

    if errors:
        print(f"❌ Found {len(errors)} issues:")
        for err in errors:
            print(f"  - {err}")
        return False
    print("✅ All quality checks passed\n")

    # Stage 3: MT5 Compatibility
    print("Stage 3: MT5 Compatibility")
    errors = check_symbol_compatibility(pair, df)
    errors += check_file_size(filepath, format_type)

    if errors:
        print(f"⚠️  Warnings:")
        for err in errors:
            print(f"  - {err}")
    else:
        print("✅ No compatibility issues\n")

    # Stage 4: Smoke Test Prep
    print("Stage 4: Smoke Test Preparation")
    smoke_test_path = filepath.replace('.csv', '_smoke_test.csv')
    create_smoke_test_csv(df, format_type, smoke_test_path)
    print(f"✅ Created smoke test: {smoke_test_path}")
    print(f"   Import this file first to verify format\n")

    print("=== Validation Complete ===")
    print("✅ Dataset is ready for MT5 import")
    print("\nNext steps:")
    print("1. Import smoke test file via MT5 GUI/script")
    print("2. Verify in Strategy Tester")
    print("3. If successful, import full dataset")

    return True

if __name__ == "__main__":
    if len(sys.argv) < 4:
        print(__doc__)
        sys.exit(1)

    filepath = sys.argv[1]
    format_type = sys.argv[2].replace('--type=', '').replace('--type', '')
    pair = sys.argv[3].replace('--pair=', '').replace('--pair', '')

    if format_type not in ['ticks', 'bars']:
        print(f"Error: --type must be 'ticks' or 'bars', got '{format_type}'")
        sys.exit(1)

    success = validate_all(filepath, format_type, pair)
    sys.exit(0 if success else 1)
```

**Usage Example**:

```bash
# Validate tick data
python validate_mt5_data.py exness_eurusd_2024.csv --type ticks --pair EURUSD

# Validate M1 bars
python validate_mt5_data.py gbpusd_m1_2024.csv --type bars --pair GBPUSD
```

---

## Common Errors and Fixes

### Error 1: "unix_ms not strictly ascending"

**Cause**: Ticks not sorted or contain duplicates

**Fix**:

```python
df = df.sort_values('unix_ms')
df = df.drop_duplicates(subset='unix_ms', keep='first')
```

### Error 2: "Bid > Ask detected"

**Cause**: Data corruption or incorrect column mapping

**Fix**:

```python
# Swap if columns mislabeled
if (df['bid'] > df['ask']).mean() > 0.5:  # More than 50% inverted
    df[['bid', 'ask']] = df[['ask', 'bid']]
```

### Error 3: "Non-M1 intervals detected"

**Cause**: Missing bars or incorrect aggregation

**Fix**:

```python
# Resample to ensure M1 continuity
df = df.set_index('datetime').resample('1min').last().dropna().reset_index()
```

### Error 4: "High < max(Open, Close)"

**Cause**: OHLC calculation error

**Fix**:

```python
# Recalculate High/Low
df['High'] = df[['Open', 'High', 'Close']].max(axis=1)
df['Low'] = df[['Open', 'Low', 'Close']].min(axis=1)
```

---

## Validation Status Tracking

After validation, document results:

```yaml
# validation_report_EURUSD_2024-01-01.yaml
dataset:
  file: exness_eurusd_2024_ticks.csv
  format: ticks
  rows: 15_234_876
  size_mb: 456.2
  date_range: 2024-01-01 to 2024-12-31

validation:
  format: PASS
  data_quality: PASS
  mt5_compat: PASS
  smoke_test: NOT_RUN

issues:
  - type: WARNING
    message: "File size 456 MB, consider chunking"
    severity: low

ready_for_import: true
validated_by: Terry Li
validated_at: 2025-10-27 20:00:00 UTC
```

---

## Changelog

**2025-10-27**: Initial validation framework

- Created 4-stage validation process
- Provided complete Python validation script
- Documented common errors and fixes
- Added validation report template
