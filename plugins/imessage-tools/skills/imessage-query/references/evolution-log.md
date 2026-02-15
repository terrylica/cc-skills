**Skill**: [iMessage Query](../SKILL.md)

# Evolution Log

Reverse chronological record of changes to this skill.

---

## 2026-02-14 — v3 Decoder: 3-Tier with pytypedstream + Cross-Repo Analysis

**Context**: After the v2 fix (NSString marker + length-prefix), conducted a cross-repo analysis of 5 open-source iMessage decoder implementations to find the best-in-class approaches. Forked and studied: imessage-exporter (Rust), macos-messages (Python), imessage-conversation-analyzer (Python), imessage_tools (Python), pymessage-lite (Python). Full analysis in [cross-repo-analysis.md](./cross-repo-analysis.md).

**Verdict**: Learn from the best, keep our unique features (`--search`, `--context`, `--export`), upgrade the decoder with external dependency (`pytypedstream`).

**Changes**:

1. **3-tier decoder architecture** — Replaced single-function decoder with tiered fallback:
   - **Tier 1**: `_decode_via_typedstream()` — `pytypedstream` Unarchiver (proper Apple typedstream deserialization). Adopted from [imessage-conversation-analyzer](https://github.com/my-other-github-account/imessage-conversation-analyzer). Handles all message lengths, emoji, rich formatting.
   - **Tier 2**: `_decode_via_multiformat()` — Multi-format binary parser with 0x2B/0x4F/0x49 length-prefix variants + heuristic fallback. Ported from [macos-messages](https://github.com/bettercallsean/macos-messages) `_extract_text_from_attributed_body()`. Zero external deps.
   - **Tier 3**: `_decode_via_nsstring_marker()` — v2 legacy NSString split + length-prefix (LangChain approach). Kept as last resort.

2. **Graceful degradation** — `_HAS_TYPEDSTREAM` flag allows script to work without pytypedstream installed (skips tier 1, falls through to tiers 2/3).

3. **PEP 723 inline script metadata** — Added `# dependencies = ["pytypedstream"]` for tools that support it (e.g., `uv run --script`).

**Additions**:

- `re` import (for heuristic fallback in tier 2)
- `from typedstream import Unarchiver` (conditional, with graceful ImportError handling)
- 3 new decode functions (`_decode_via_typedstream`, `_decode_via_multiformat`, `_decode_via_nsstring_marker`)

**API discovery (pytypedstream)**:

- Package: `pip install pytypedstream` (PyPI name)
- Module: `import typedstream` (NOT `pytypedstream`)
- Entry point: `Unarchiver.from_data(blob).decode_all()` (NOT `TypedStreamReader`)
- Unarchiver is NOT iterable — must call `.decode_all()` first

**New reference**: [cross-repo-analysis.md](./cross-repo-analysis.md) — Full comparison of all 5 repos with selection criteria, adoption decisions, and technical notes.

---

## 2026-02-14 — v2 Decoder + Context & Export Features

**Context**: During analysis of the Tiemar recruitment case, the v1 decoder (null-byte split + NS framework class filter) failed to extract 23+ messages including critical evidence like "The current office gave her a glaring reference" and "She gave me these references" + phone numbers. This caused multiple wasted search attempts and missed evidence that took hours to find manually via screenshots.

**Root cause**: The v1 `any(cls in chunk for cls in NS_FRAMEWORK_CLASSES)` filter discards chunks containing both message text AND framework class names. For short messages, the actual text and NSString/NSDictionary markers always land in the same null-delimited chunk — so the filter throws out the message with the metadata.

**Changes**:

1. **Replaced `decode_attributed_body()` with NSString marker + length-prefix algorithm** — Same approach as [LangChain's iMessage loader](https://github.com/langchain-ai/langchain/blob/master/libs/community/langchain_community/chat_loaders/imessage.py). Splits on `b"NSString"`, skips 5-byte preamble, reads length-prefix (single byte or 0x81 + 2-byte little-endian), extracts exact text. No filtering needed.

2. **Added `--context N` flag** — When used with `--search`, shows N messages before and after each match. Solves the "isolated keyword match loses conversational meaning" problem. Uses `--- context ---` separators between non-contiguous groups and `[match]` markers on actual matches.

3. **Added `--export <path.jsonl>` flag** — Exports conversation to NDJSON file for offline analysis. Format: `{"ts", "sender", "is_from_me", "text", "decoded"}` per line. Enables export-once-analyze-many workflow instead of repeated SQLite queries.

**Removals**:

- `NS_FRAMEWORK_CLASSES` frozenset (no longer needed)
- `re` import (no longer needed)
- Null-byte split logic
- `iI` cleanup regex (length-prefix extraction doesn't include trailing artifacts)
- `+.` cleanup regex (same reason)

**Anti-patterns documented**:

1. Searching multiple chat identifiers for the same person without first checking `--stats`
2. Keyword search without context — always use `--context 5` with `--search`
3. Repeated narrow-window SQLite queries — export first, then grep

---

## 2026-02-07 — Initial Creation

**Context**: During iMessage retrieval work, discovered that 20-60% of messages in real conversations have NULL `text` columns but contain valid, recoverable text in `attributedBody` (NSAttributedString binary blobs). Without documented knowledge of this pattern, every future session would rediscover the same workaround from scratch.

**Created**:

- `SKILL.md` — Main skill with YAML frontmatter, workflow instructions, quick start queries
- `scripts/decode_attributed_body.py` — Python script (stdlib only) for decoding NSAttributedString binary blobs from `attributedBody` column
- `references/schema-reference.md` — Core table documentation (message, chat, handle, attachment, joins)
- `references/query-patterns.md` — 8 reusable SQL templates for common operations
- `references/known-pitfalls.md` — 10 documented pitfalls with symptoms and solutions
- `references/evolution-log.md` — This file

**Key discoveries codified**:

1. `text` vs `attributedBody` problem (critical — causes messages to appear empty)
2. NSAttributedString binary decode technique (null-byte split, framework class filtering)
3. Tapback reaction filtering (`associated_message_type = 0`)
4. Apple epoch date formula with localtime conversion
5. zsh shell escaping for `!=` operator
6. Voice message vs dictated text differentiation (`cache_has_attachments` flag)
