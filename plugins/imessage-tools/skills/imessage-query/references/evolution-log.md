**Skill**: [iMessage Query](../SKILL.md)

# Evolution Log

Reverse chronological record of changes to this skill.

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
