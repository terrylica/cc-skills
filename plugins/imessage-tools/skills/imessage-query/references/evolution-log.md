**Skill**: [iMessage Query](../SKILL.md)

# Evolution Log

Reverse chronological record of changes to this skill.

---

## 2026-02-15 — v4 Native Pitfall Protections + Full Metadata Extraction

**Context**: After correcting the "voice message" misconception (actually retracted messages — pitfall #14) and discovering that `thread_originator_guid` provides inline quote context for 291 messages in the Phoebe chat, we upgraded the script to natively handle every known pitfall deterministically rather than relying on contextual documentation alone. Cross-referenced all 5 forked OSS repos and the full 92-column `message` schema to identify missing attributes.

**Changes**:

1. **Retracted message exclusion (pitfall #14)** — Messages with `date_retracted > 0` are deterministically excluded from both stdout and NDJSON export. Also handles older iOS pattern where Undo Send set `date_edited` instead of `date_retracted` (detected when `date_edited > 0` + empty text/attributedBody).

2. **Edited message flagging** — Messages with `date_edited > 0` that still have content are included but flagged with `[edited]` in stdout and `"edited": true` in NDJSON.

3. **Audio message identification (pitfall #9 correction)** — Uses `is_audio_message` column (definitive) instead of heuristic guessing from NULL text + attachments. Audio messages emit `[audio message]` placeholder instead of being silently dropped.

4. **Inline quote resolution** — Builds GUID→message index via `_build_guid_index()`. Messages with `thread_originator_guid` get their `reply_to` field populated with the quoted message's `{ts, sender, text}`. Shown as `[replying to sender: "quoted text"]` in stdout and `"reply_to": {...}` in NDJSON.

5. **Attachment surfacing** — Messages with no text but `cache_has_attachments = 1` now emit `[attachment: filename]` or `[attachment: mime_type]` instead of being silently dropped. LEFT JOINs to `attachment` table via `message_attachment_join`.

6. **Message effects** — `expressive_send_style_id` decoded to human-readable names (slam, loud, gentle, invisible_ink). Shown as `[slam]` in stdout and `"effect": "slam"` in NDJSON.

7. **Service type** — `service` column distinguishes iMessage from SMS. Non-iMessage messages flagged with `[SMS]` in stdout and `"service": "SMS"` in NDJSON.

8. **Enhanced stats** — `--stats` now shows retracted, edited, audio, threaded replies, SMS counts, and adjusted coverage (excluding retracted).

9. **Row deduplication** — LEFT JOIN to attachment table can produce duplicate rows for multi-attachment messages. Dedup key `(ts, is_from_me, text)` prevents duplicates in output.

**SQL query changes**:

- Added columns: `m.date_retracted`, `m.date_edited`, `m.is_audio_message`, `m.service`, `m.expressive_send_style_id`, `m.cache_has_attachments`, `a.transfer_name`, `a.mime_type`
- Added JOINs: `LEFT JOIN message_attachment_join`, `LEFT JOIN attachment`
- New function: `_build_guid_index()` for GUID→message resolution

**NDJSON schema v2**:

```json
{
  "ts": "2026-02-14 07:16:22",
  "sender": "them",
  "is_from_me": false,
  "text": "I was not trying to loop around you...",
  "decoded": false,
  "type": "text",
  "edited": true,
  "service": "SMS",
  "effect": "slam",
  "reply_to": {
    "ts": "2026-02-13 23:30:00",
    "sender": "me",
    "text": "Original message..."
  }
}
```

Fields `edited`, `service`, `effect`, `reply_to` are optional — only present when applicable.

**Informed by**: macos-messages (columns: `date_edited`, `date_retracted`, `expressive_send_style_id`, `thread_originator_guid`), imessage-exporter (attachment handling), full `PRAGMA table_info(message)` audit (92 columns).

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
