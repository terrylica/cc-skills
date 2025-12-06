**Skill**: [MQL5 Data Ingestion Research (UNVALIDATED)](../SKILL.md)

## Recommended Workflow (Unvalidated)

### Phase 1: Data Preparation

1. Export tick data from `exness-data-preprocess`:

   ```python
   df = processor.query_ticks("EURUSD", variant="raw_spread", start_date="2024-01-01")
   ```

1. Transform to MT5 CSV format:

   ```python
   # Convert to unix_ms, ensure bid/ask/last columns
   df['unix_ms'] = (df['timestamp'].astype('int64') // 10**6)  # ns → ms
   df = df.sort_values('unix_ms')  # CRITICAL: ascending order
   df[['unix_ms', 'bid', 'ask', 'last', 'volume']].to_csv('ticks.csv', index=False)
   ```

1. Validate format (see [VALIDATION.md](./VALIDATION.md))

### Phase 2: MT5 Import (Requires Validation)

```mq5
// WARNING: Illustrative only, not tested
CustomSymbolCreate("EURUSD.EXNESS", "Custom\\Exness", NULL);
SymbolSelect("EURUSD.EXNESS", true);

// Load via script (see ChatGPT dialogue for full validator)
CustomTicksReplace("EURUSD.EXNESS", from_ms, to_ms, ticks_array);
```

### Phase 3: Strategy Tester Setup

1. Open Strategy Tester
1. Select custom symbol: `EURUSD.EXNESS`
1. Choose: "Every tick based on real ticks"
1. Run backtest

---
