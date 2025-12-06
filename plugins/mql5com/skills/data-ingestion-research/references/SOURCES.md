**Skill**: [MQL5 Data Ingestion Research (UNVALIDATED)](../SKILL.md)

# Official MQL5 Documentation Sources

**Last Verified**: 2025-10-27
**Domain**: mql5.com (official MetaQuotes documentation)

⚠️ **User Responsibility**: Verify these URLs are current before relying on information

---

## Core Custom Symbol Functions

### 1. CustomSymbolCreate()

**URL**: https://www.mql5.com/en/docs/customsymbols/customsymbolcreate

**What it documents**:

- Function to create custom trading symbols
- Parameters: symbol name, path, base symbol
- Return values and error codes
- Usage examples

**Relevance**: Required for creating forex custom symbols before importing tick/bar data

---

### 2. CustomTicksReplace()

**URL**: https://www.mql5.com/en/docs/customsymbols/customticksreplace

**What it documents**:

- Batch loading tick data (preferred method)
- Parameters: symbol, from_ms, to_ms, ticks[] array
- Time ordering requirement (ascending time_msc)
- Chunk loading strategy

**Key Finding**: "The ticks must be arranged in order of their time. The function will stop working at the first tick with a time not greater than the time of the previous tick."

**Relevance**: Primary method for importing tick data in batches

---

### 3. CustomTicksAdd()

**URL**: https://www.mql5.com/en/docs/customsymbols/customticksadd

**What it documents**:

- Streaming tick data addition
- Requires symbol in Market Watch
- Difference from CustomTicksReplace()
- Use cases (real-time vs historical)

**Key Finding**: Symbol must be selected in Market Watch, otherwise function fails

**Relevance**: Alternative to Replace for streaming data (not batch import)

---

### 4. CustomRatesUpdate()

**URL**: https://www.mql5.com/en/docs/customsymbols/customratesupdate

**What it documents**:

- Loading M1 (1-minute) OHLC bars
- Parameters: symbol, rates[] array (MqlRates structure)
- **M1-only constraint**: Higher timeframes auto-generated
- Return value: number of bars inserted

**Key Finding**: "The custom symbol history consists of 1-minute bars. The bars of other periods are built automatically based on the minute history."

**Relevance**: Primary method for importing bar data (alternative to ticks)

---

## Data Structures

### 5. MqlTick Structure

**URL**: https://www.mql5.com/en/docs/constants/structures/mqltick

**What it documents**:

- Tick data structure fields
- time vs time_msc (milliseconds primary)
- bid, ask, last, volume_real fields
- flags field (auto-inferred by MT5)

**Key Finding**: time_msc is primary; time is derived. Flags are set automatically based on which prices are non-zero.

**Relevance**: Defines CSV → MqlTick mapping for tick imports

---

### 6. MqlRates Structure

**URL**: https://www.mql5.com/en/docs/constants/structures/mqlrates

**What it documents**:

- OHLC bar structure fields
- time, open, high, low, close, tick_volume, spread, real_volume
- Field data types and constraints

**Relevance**: Defines CSV → MqlRates mapping for bar imports

---

## File Operations

### 7. FileOpen()

**URL**: https://www.mql5.com/en/docs/files/fileopen

**What it documents**:

- File opening flags: FILE_READ, FILE_WRITE, FILE_CSV, FILE_COMMON
- FILE_COMMON behavior: shared folder for terminal + tester
- Path conventions: Terminal\\Common\\Files
- Encoding options (CP_UTF8)

**Key Finding**: FILE_COMMON places files in shared location accessible to both live terminal and Strategy Tester

**Relevance**: Required for MQL5 CSV import scripts

---

## Workflow Documentation

### 8. Custom Symbols Overview

**URL**: https://www.mql5.com/en/docs/customsymbols

**What it documents**:

- Complete custom symbol API reference
- Workflow: create → load data → test
- Data storage location: bases\\Custom...
- Symbol property management

**Relevance**: High-level overview of custom symbol ecosystem

---

### 9. Custom Symbols Tutorial (Book)

**URL**: https://www.mql5.com/en/book/advanced/custom_symbols/custom_symbols_ticks

**What it documents**:

- Step-by-step tutorials
- Tick data loading best practices
- Performance considerations
- Real-world examples

**Relevance**: Practical guidance beyond API reference

---

## Additional Resources

### 10. Strategy Tester Tick Generation

**URL**: https://www.metatrader5.com/en/terminal/help/algotrading/tick_generation

**What it documents**:

- Difference between "Every tick based on real ticks" vs "1 minute OHLC"
- How MT5 generates ticks when real ticks unavailable
- Testing mode selection

**Relevance**: Understanding tester behavior with custom data

---

### 11. Custom Instruments GUI (MetaTrader 5 Help)

**URL**: https://www.metatrader5.com/en/terminal/help/trading_advanced/custom_instruments

**What it documents**:

- GUI method for creating custom symbols
- Manual tick/bar import via CSV
- Column mapping interface
- Symbol properties configuration

**Relevance**: Alternative to programmatic import (good for testing)

---

### 12. FileOpen() Function Reference

**URL**: https://www.mql5.com/en/docs/files/fileopen

**What it documents** (duplicate entry, see #7):

- Complete file I/O function reference
- Additional file operations: FileClose, FileIsEnding, FileReadString

**Relevance**: Comprehensive file handling documentation

---

## Community Resources (Unofficial)

### 13. MQL5 Forum: Custom Symbol Data Import

**URL**: https://www.mql5.com/en/forum/374107

**What it documents** (forum thread):

- User experiences with custom symbol imports
- Performance benchmarks
- Troubleshooting common issues
- Community workarounds

**Status**: Community-contributed, not official documentation

**Caveat**: Validate forum advice against official docs

---

### 14. MQL5 Article: Advanced Custom Symbol Techniques

**URL**: https://www.mql5.com/en/articles/3540

**What it documents**:

- Custom symbol creation strategies
- Data import optimization techniques
- Integration with external data sources

**Status**: Community article, not official API docs

**Relevance**: Advanced patterns beyond basic import

---

### 15. MQL5 Community Logging Framework

**URL**: https://www.mql5.com/en/articles/17933

**What it documents**:

- Logging best practices for MQL5 scripts
- Debug output strategies
- File-based logging patterns

**Relevance**: Debugging data import scripts

---

## Documentation Version Notes

### MT5 Build Compatibility

**Current Stable**: MetaTrader 5 Build 4600+ (as of 2024)

**API Stability**:

- Custom symbol functions introduced: ~2019 (Build 2200+)
- CustomTicksReplace() recommended over CustomTicksAdd() since ~2020

**Recommendation**: Always check "Updated" date on mql5.com documentation pages

---

## Verification Checklist

When using this skill, verify:

- [ ] URL is on mql5.com or metatrader5.com (official domains)
- [ ] Documentation page shows recent "Updated" date
- [ ] Function signatures match code examples
- [ ] Constraints (e.g., "M1-only", "ascending order") are explicit
- [ ] Example code runs without modification

**If documentation is outdated**:

1. Search mql5.com for updated article
1. Check MetaEditor built-in help (F1)
1. Post in MQL5 forum for clarification

---

## Missing Documentation (Known Gaps)

### Gap 1: Performance Benchmarks

**What's missing**: Official guidance on:

- Optimal chunk size for CustomTicksReplace()
- Memory limits for large tick arrays
- Import speed expectations (rows/sec)

**Workaround**: Community reports suggest 500K ticks/chunk (unvalidated)

### Gap 2: Error Code Reference

**What's missing**: Complete error code list for custom symbol functions

**Workaround**: Use GetLastError() and forum search

### Gap 3: Data Quality Requirements

**What's missing**: Explicit validation rules beyond "ascending time"

**Workaround**: Inferred rules documented in [VALIDATION.md](./VALIDATION.md)

---

## Source Changelog

**2025-10-27**: Initial documentation

- Compiled 15 official/community sources
- Verified URLs accessible
- Noted 3 documentation gaps
- Added MT5 build compatibility notes

**User Action Required**: Manually verify each URL before use
