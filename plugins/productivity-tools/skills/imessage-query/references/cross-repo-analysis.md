**Skill**: [iMessage Query](../SKILL.md)

# Cross-Repository Analysis: iMessage Decoder Implementations

Comparative analysis of 5 open-source iMessage `attributedBody` decoders, conducted 2026-02-14. Used to inform the v3 decoder upgrade for this skill.

---

## Repositories Studied

All repositories forked to `~/fork-tools/` under [terrylica](https://github.com/terrylica) for analysis.

### 1. imessage-exporter (Rust)

| Field        | Value                                                                       |
| ------------ | --------------------------------------------------------------------------- |
| **Repo**     | [ReagentX/imessage-exporter](https://github.com/ReagentX/imessage-exporter) |
| **Language** | Rust                                                                        |
| **Stars**    | ~2.5k                                                                       |
| **Decoder**  | `crabstep` crate (proper typedstream deserialization) + legacy fallback     |
| **Tests**    | 70+ unit tests with real binary fixtures                                    |
| **Status**   | Actively maintained, most comprehensive tool                                |

**Decoder approach**: Uses the `crabstep` crate for native Apple typedstream deserialization. Has a legacy regex-based fallback for older message formats. The Rust type system provides strong guarantees on binary parsing correctness.

**What we learned**: Confirmed that proper typedstream deserialization is the gold standard approach. The dual-strategy pattern (proper parser + legacy fallback) influenced our 3-tier design.

**What we adopted**: The philosophy of having a proper deserializer as tier 1 with fallbacks for edge cases.

**What we did NOT adopt**: The Rust implementation itself (wrong language for our Python skill). The `crabstep` crate is Rust-only with no Python bindings.

---

### 2. macos-messages (Python)

| Field        | Value                                                                             |
| ------------ | --------------------------------------------------------------------------------- |
| **Repo**     | [bettercallsean/macos-messages](https://github.com/bettercallsean/macos-messages) |
| **Language** | Python                                                                            |
| **Stars**    | ~50                                                                               |
| **Decoder**  | Multi-format binary length-prefix parsing (4 format variants)                     |
| **Tests**    | Comprehensive pytest suite with parametrized binary fixtures                      |
| **Status**   | Active, AI-analysis focused                                                       |

**Decoder approach**: The most thorough pure-binary parser found in any Python repo. The `_extract_text_from_attributed_body()` function in `src/messages/db.py` handles 4 distinct binary encoding formats:

1. **0x2B (+) marker** — Variable-length encoding:
   - `< 0x80`: 1-byte length (direct)
   - `0x81`: 2-byte little-endian length
   - `0x82`: 3-byte little-endian length
   - `0x83`: 4-byte little-endian length
2. **0x4F marker** — Extended encoding with size markers:
   - `0x10`: 1-byte length
   - `0x11`: 2-byte big-endian length
   - `0x12`: 4-byte big-endian length
3. **0x49 (I) marker** — Legacy 4-byte big-endian length
4. **Heuristic fallback** — Regex for readable text sequences after NSString marker

**What we adopted**: The entire multi-format binary decoder was ported as tier 2 in our v3 decoder (`_decode_via_multiformat()`). This provides zero-dependency decoding for messages that pytypedstream can't handle, covering format variants we'd never encountered in our own testing.

**What we did NOT adopt**: Their overall architecture (AI-first analysis pipeline, conversation grouping, sentiment analysis). Out of scope for a decode-focused skill.

---

### 3. imessage-conversation-analyzer (Python)

| Field        | Value                                                                                                                               |
| ------------ | ----------------------------------------------------------------------------------------------------------------------------------- |
| **Repo**     | [my-other-github-account/imessage-conversation-analyzer](https://github.com/my-other-github-account/imessage-conversation-analyzer) |
| **Language** | Python                                                                                                                              |
| **Stars**    | ~30                                                                                                                                 |
| **Decoder**  | `pytypedstream` (Unarchiver) — proper Apple typedstream deserialization                                                             |
| **Tests**    | 7 analysis modules (word clouds, sentiment, response times, etc.)                                                                   |
| **Status**   | Maintained, analytics-focused                                                                                                       |

**Decoder approach**: Uses the `pytypedstream` package for proper Apple typedstream binary deserialization. The decode function at `ica/core.py:111-124` is only 6 lines:

```python
from typedstream import Unarchiver

def decode_message_attributedbody(blob):
    result = Unarchiver.from_data(blob).decode_all()
    # Navigate result → GenericArchivedObject → contents → NSMutableString.value
```

This is the most reliable approach because it uses the actual Apple binary format specification rather than pattern matching on byte sequences.

**What we adopted**: The `pytypedstream` dependency and `Unarchiver.from_data().decode_all()` approach as tier 1 in our v3 decoder (`_decode_via_typedstream()`). We expanded the text extraction to handle more object graph variations (both `val.value` for NSMutableString wrappers and direct `str` values).

**What we did NOT adopt**: Their analytics pipeline (pandas, DuckDB, word clouds, sentiment analysis). Different purpose than our decode-and-search skill. Also did not adopt their `TypedStreamReader` — that class doesn't exist in the current pytypedstream API; the correct entry point is `Unarchiver`.

**API discovery note**: The pip package is `pytypedstream` but it installs as the `typedstream` module. The `Unarchiver` class is the correct entry point, not `TypedStreamReader` (which appears in some older documentation but doesn't exist).

---

### 4. imessage_tools (Python)

| Field        | Value                                                                       |
| ------------ | --------------------------------------------------------------------------- |
| **Repo**     | [janfreyberg/imessage_tools](https://github.com/janfreyberg/imessage_tools) |
| **Language** | Python                                                                      |
| **Stars**    | ~10                                                                         |
| **Decoder**  | Hardcoded byte-offset slice `[6:-12]`                                       |
| **Tests**    | None                                                                        |
| **Status**   | Abandoned (~2020), fragile                                                  |

**Decoder approach**: `content[6:-12].decode("utf-8")` — a fixed-offset slice that works only for messages of a specific length range. No length-prefix parsing, no format detection, no error handling.

**Why we skipped this**: The `[6:-12]` slice is brittle — it silently truncates or corrupts messages of unusual lengths. Bare `except:` clauses mask errors. No tests, no maintenance. This is the anti-pattern our v1 decoder was already better than.

**What we learned**: Confirmed that hardcoded byte offsets are the worst possible approach to typedstream decoding. Any format variation (longer messages, emoji, different iOS versions) breaks silently.

---

### 5. pymessage-lite (Python)

| Field        | Value                                                                         |
| ------------ | ----------------------------------------------------------------------------- |
| **Repo**     | [mattmajestic/pymessage-lite](https://github.com/mattmajestic/pymessage-lite) |
| **Language** | Python                                                                        |
| **Stars**    | ~5                                                                            |
| **Decoder**  | None — `text` column only                                                     |
| **Tests**    | None                                                                          |
| **Status**   | 74 lines, Python 2 era code, SQL injection vulnerable                         |

**Why we skipped this**: No `attributedBody` decoding at all. Uses string formatting for SQL queries (injection risk). Python 2 style code. Nothing to learn from this repo beyond confirming what not to do.

---

## Capability Comparison Matrix

| Capability            | Our Skill (v3)      | imessage-exporter   | macos-messages    | imessage-conv-analyzer        | imessage_tools    | pymessage-lite    |
| --------------------- | ------------------- | ------------------- | ----------------- | ----------------------------- | ----------------- | ----------------- |
| attributedBody decode | 3-tier              | crabstep + legacy   | 4-format binary   | pytypedstream                 | `[6:-12]` slice   | None              |
| Short message decode  | Yes                 | Yes                 | Yes               | Yes                           | Fragile           | N/A               |
| Emoji support         | Yes                 | Yes                 | Yes               | Yes                           | Partial           | N/A               |
| Keyword search        | `--search`          | Full-text export    | N/A               | N/A                           | N/A               | N/A               |
| Context windows       | `--context N`       | N/A                 | N/A               | N/A                           | N/A               | N/A               |
| NDJSON export         | `--export`          | HTML/TXT export     | N/A               | N/A                           | N/A               | N/A               |
| Stats mode            | `--stats`           | Full statistics     | Summary stats     | 7 analysis types              | N/A               | N/A               |
| Date filtering        | `--after/--before`  | Full range          | Full range        | Full range                    | N/A               | N/A               |
| Sender filtering      | `--sender`          | Per-contact         | Per-contact       | Per-contact                   | N/A               | N/A               |
| Group chat support    | Via chat_identifier | Full                | Full              | Full                          | Partial           | Basic             |
| Attachment handling   | Metadata only       | Full (images, etc.) | Metadata          | Metadata                      | Basic             | None              |
| External deps         | pytypedstream       | crabstep (Rust)     | None              | pytypedstream, pandas, DuckDB | None              | None              |
| SQL injection safe    | Yes (parameterized) | N/A (Rust)          | Yes               | Yes                           | No                | No                |
| Zero-config           | Yes                 | Yes (binary)        | Needs pip install | Needs pip install             | Needs pip install | Needs pip install |

---

## Selection Criteria

### What we optimized for

1. **Decode reliability** — Must decode all messages including short ones, emoji, and rich formatting
2. **Graceful degradation** — Must work even if pytypedstream is not installed (falls through to pure-binary tiers)
3. **Zero-config for basic use** — Tiers 2 and 3 are stdlib-only, tier 1 requires one `pip install`
4. **Search-first workflow** — `--search` with `--context` is unique to our skill and critical for investigation work
5. **Minimal scope** — We're a decode-and-search tool, not an analytics platform

### What we adopted and why

| Source                         | What                                 | Why                                                                                            |
| ------------------------------ | ------------------------------------ | ---------------------------------------------------------------------------------------------- |
| imessage-conversation-analyzer | `pytypedstream` Unarchiver as tier 1 | Proper typedstream deserialization — handles all message formats correctly                     |
| macos-messages                 | Multi-format binary parser as tier 2 | Most thorough pure-Python binary parser found — covers 4 format variants we hadn't encountered |
| imessage-exporter              | Tiered fallback philosophy           | Confirmed that "proper parser + fallbacks" is the right architecture                           |

### What we kept from our own implementation

| Feature                                  | Why                                                                |
| ---------------------------------------- | ------------------------------------------------------------------ |
| NSString marker + length-prefix (tier 3) | Simplest last-resort decoder for unusual blob formats              |
| `--search` with `--context N`            | Unique to our skill — no other tool does contextual keyword search |
| `--export` NDJSON                        | Enables export-once-analyze-many workflow                          |
| `--stats` mode                           | Quick conversation profiling before deep analysis                  |
| Pipe-delimited stdout format             | Machine-readable, grep-friendly, zero overhead                     |

### What we did NOT adopt and why

| Source                         | What                             | Why skipped                                                         |
| ------------------------------ | -------------------------------- | ------------------------------------------------------------------- |
| imessage-exporter              | Rust crate (crabstep)            | Wrong language — no Python bindings available                       |
| imessage-exporter              | Full export pipeline (HTML, TXT) | Out of scope — we're a search tool, not an archiver                 |
| macos-messages                 | AI analysis pipeline             | Out of scope — sentiment analysis, conversation grouping not needed |
| imessage-conversation-analyzer | pandas/DuckDB analytics          | Out of scope — word clouds, response time analysis not needed       |
| imessage-conversation-analyzer | `TypedStreamReader` API          | Doesn't exist — `Unarchiver` is the correct API                     |
| imessage_tools                 | `[6:-12]` byte slice             | Fragile, silently corrupts messages of unusual lengths              |
| pymessage-lite                 | Anything                         | SQL injection, no decode, Python 2 era, nothing useful              |

---

## Complementary Tool Recommendations

These tools serve different purposes and can be used alongside our skill:

| Tool                               | Use case                         | When to reach for it                                                                                        |
| ---------------------------------- | -------------------------------- | ----------------------------------------------------------------------------------------------------------- |
| **imessage-exporter**              | Full conversation archival       | When you need complete HTML/TXT exports of entire message history including images, videos, and attachments |
| **macos-messages**                 | AI-powered conversation analysis | When you need sentiment analysis, conversation grouping, or topic extraction beyond keyword search          |
| **imessage-conversation-analyzer** | Statistical analysis             | When you need word clouds, response time distribution, or message frequency analytics                       |

Our skill remains the best choice for:

- Quick keyword searches with conversational context (`--search` + `--context`)
- Building sourced timelines with precise timestamps
- Export-once-analyze-many workflows with NDJSON
- Claude Code integration (pipe-delimited output, stderr summaries)

---

## Technical Notes

### pytypedstream API

```python
# Correct usage (verified 2026-02-14):
from typedstream import Unarchiver

result = Unarchiver.from_data(blob).decode_all()
# Returns: list[TypedValue]
# Navigate: TypedValue.value → GenericArchivedObject.contents → NSMutableString.value → str
```

**Gotchas**:

- Package name: `pip install pytypedstream` (PyPI)
- Module name: `import typedstream` (NOT `pytypedstream`)
- Entry point: `Unarchiver` (NOT `TypedStreamReader`)
- Method: `.decode_all()` returns a list (Unarchiver itself is NOT iterable)

### Multi-format binary encoding (from macos-messages)

The `attributedBody` binary format uses different length-encoding schemes depending on iOS version and message content:

```
0x2B (+) marker:
  byte < 0x80  → 1-byte length (direct value)
  byte == 0x81 → next 2 bytes = length (little-endian)
  byte == 0x82 → next 3 bytes = length (little-endian)
  byte == 0x83 → next 4 bytes = length (little-endian)

0x4F marker:
  0x10 → next 1 byte = length
  0x11 → next 2 bytes = length (big-endian)
  0x12 → next 4 bytes = length (big-endian)

0x49 (I) marker:
  next 4 bytes = length (big-endian)
```

All extraction follows the pattern: split on `NSString`, split on `NSDictionary`, find marker, read length, extract UTF-8 text.
