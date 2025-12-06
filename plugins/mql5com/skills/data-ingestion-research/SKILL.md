---
name: data-ingestion-research
description: Researches MQL5 data ingestion methods and documentation. Use when exploring MetaTrader 5 data sources, historical data APIs, or investigating MQL5 data structures.
---

# MQL5 Data Ingestion Research (UNVALIDATED)

**Skill Type**: Research Documentation
**Status**: RESEARCHED | NOT VALIDATED
**Last Updated**: 2025-10-27
**Research Context**: Exness tick data - MetaTrader 5 ingestion pipeline

---

## CRITICAL: VALIDATION STATUS

**THIS SKILL CONTAINS UNVALIDATED RESEARCH**

- **NOT tested** in live MetaTrader 5 environment
- **NOT validated** with real tick data imports
- **NOT benchmarked** for performance or correctness
- **Based on** official MQL5 documentation (URLs provided)

**User Responsibility**:

- Validate all specifications before production use
- Test with small datasets first
- Verify official MQL5 documentation currency
- Author assumes NO liability for data loss or trading errors

**When to Graduate This Skill**:

- After successful MT5 test environment setup
- After validation with real exness-data-preprocess output
- After community review of format compliance
- Move validated content to operational skill: `mql5-data-ingestion`

---

## Purpose

This skill documents research findings for converting forex tick data (specifically from `exness-data-preprocess` package) into MetaTrader 5-compatible formats for:

1. **Backtesting** trading strategies on historical tick data
2. **Custom symbol creation** with real tick-level granularity
3. **Strategy Tester** execution with "Every tick based on real ticks" mode

---

## Activation Context

This skill activates when discussing:

- Converting tick data to MT5 format
- `exness-data-preprocess` output transformation
- MetaTrader 5 custom symbol data requirements
- CSV format for `CustomTicksReplace()` or `CustomRatesUpdate()`
- Tick data validation before MT5 import

**Cross-References**:

- Official TICK documentation: `/Users/terryli/eon/mql5/mql5_articles/tick_data/official_docs/`
- Research documentation: `/Users/terryli/eon/mql5/docs/tick_research/`

**Does NOT activate for**:

- Live trading operations (use validated operational skills)
- Production data pipelines (validate first)
- MQL5 indicator/EA development (use `mql5-article-extractor` skill)

---

## Support & Contributions

**Questions**: Post in research notes, NOT production channels

**Validation Results**: Document findings in `VALIDATION.md` with:

- Test environment details
- Dataset characteristics (date range, tick count)
- Success/failure outcomes
- Performance metrics

**Found Errors**: Update `SOURCES.md` with corrected documentation URLs

---

## Related Skills

- `article-extractor`: Extract MQL5 community articles AND official Python MT5 API documentation
- `python-api-documentation`: Pydantic model documentation (for exness-data-preprocess)

---

## Reference Documentation

For detailed specifications, see:

- [Tick Data Format](./references/TICK_FORMAT.md) - Field definitions and validation rules
- [Bar Data Format](./references/BAR_FORMAT.md) - OHLC structure and timeframes
- [Data Sources](./references/SOURCES.md) - Official documentation links
- [Validation Requirements](./references/VALIDATION.md) - Quality gates and checks
- [Key Findings](./references/key-findings.md) - 4 critical research findings with official sources
- [Workflow](./references/workflow.md) - Unvalidated end-to-end workflow (preparation, import, testing)
- [Known Gaps](./references/known-gaps.md) - Compatibility questions and migration path to production

---

## Changelog

**2025-10-27**: Initial research documentation

- Extracted MT5 tick format requirements from ChatGPT dialogue
- Documented 9 official MQL5 documentation URLs
- Created validation rules based on `CustomTicksReplace()` constraints
- Identified 4 critical findings (millisecond timestamps, ascending order, M1-only bars, FILE_COMMON)
