**Skill**: [MQL5 Data Ingestion Research (UNVALIDATED)](/skills/mql5-data-ingestion-research/SKILL.md)


### Gap 1: Exness Tick Structure Compatibility

**Question**: Does `exness-data-preprocess` "raw_spread" variant provide:

- Separate `bid` and `ask` columns? (Required)
- Microsecond or nanosecond timestamps? (Need millisecond)
- Volume per tick? (Optional but preferred)

**Validation Needed**: Inspect actual output schema

### Gap 2: Performance at Scale

**Question**: How many ticks can `CustomTicksReplace()` handle per call?

- ChatGPT suggests 500K chunks
- No empirical testing completed

**Validation Needed**: Benchmark with real data

### Gap 3: Custom Symbol Properties

**Question**: What symbol properties must be set for forex custom symbols?

- Digits (5 for EURUSD)
- Contract size
- Tick size
- Sessions

**Validation Needed**: Test default vs explicit configuration

______________________________________________________________________

## Migration Path: Research → Production

When validated, this content should migrate to:

**New Operational Skill**: `~/.claude/skills/mql5-data-ingestion/`

**Structure**:

```
mql5-data-ingestion/
├── SKILL.md                    # Validated procedures
├── converters/
│   └── exness_to_mt5.py       # Production converter
├── validators/
│   └── tick_format.py         # Production validator
└── mql5_loaders/
    └── LoadTicks.mq5          # Tested MQL5 loader
```

**Graduation Checklist**:

- [ ] MT5 environment setup completed
- [ ] Test import with 1M+ ticks
- [ ] Backtest runs without errors
- [ ] Format validator tested on edge cases
- [ ] Documentation reviewed by MT5 expert
- [ ] Performance benchmarks documented

