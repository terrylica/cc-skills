**Skill**: [MQL5 Data Ingestion Research (UNVALIDATED)](../SKILL.md)

## Key Research Findings

### Finding 1: Tick Data Must Use Millisecond Timestamps

```csv
unix_ms,bid,ask,last,volume_real
1688342627212,1.14175,1.14210,0.00000,0
```

**Why**: `MqlTick.time_msc` is primary; `time` is derived. Using seconds loses sub-second ticks.

**Source**: [`MqlTick` Structure Documentation](https://www.mql5.com/en/docs/constants/structures/mqltick)

### Finding 2: Time MUST Be Strictly Ascending

MT5's `CustomTicksReplace()` **stops processing** at first out-of-order timestamp.

**Implication**: Sort by `unix_ms` BEFORE import, or partial import occurs silently.

**Source**: [`CustomTicksReplace()` Documentation](https://www.mql5.com/en/docs/customsymbols/customticksreplace)

### Finding 3: M1 Bars Only for `CustomRatesUpdate()`

Higher timeframes (M5, H1, D1) are **automatically aggregated** by MT5 from M1 bars.

**Implication**: Don't generate H1 bars manually; provide M1 and let MT5 build the rest.

**Source**: [`CustomRatesUpdate()` Documentation](https://www.mql5.com/en/docs/customsymbols/customratesupdate)

### Finding 4: `FILE_COMMON` for Tester Compatibility

Files in `Terminal\Common\Files` are accessible to both:

- Live terminal
- Strategy Tester

**Implication**: Always use `FILE_COMMON` flag when creating import scripts.

**Source**: [`FileOpen()` Documentation](https://www.mql5.com/en/docs/files/fileopen)
