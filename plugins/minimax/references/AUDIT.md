# Aggregation Audit Findings

This file tracks issues discovered during the Phase B/D aggregation + audit work. The campaign cannot close while any unresolved finding remains.

**Status as of iter-4 (Phase A close)**: ✅ No findings yet — Phase A integrity check passed (cross-reference scan: 21 internal links, all resolve; 1 false positive in LOOP_CONTRACT.md noted below).

---

## Finding format

Each finding gets one entry:

```markdown
### F<N> — <one-line summary>

**Discovered**: iter-<N>, <YYYY-MM-DD HH:MM UTC>
**Source artifact**: <path>
**Destination artifact**: <path>
**Severity**: BLOCKER | MAJOR | MINOR | NOTE
**Status**: OPEN | RESOLVED-iter-<N>

**Issue**: <what was found>
**Resolution** (if RESOLVED): <how it was fixed>
```

---

## Active findings

(none — Phase A clean)

## Resolved findings

(none yet)

## Tooling notes

- **iter-4 cross-reference scan false positive**: the audit script's markdown-link regex matches link-shaped patterns inside backtick-wrapped inline code. Real markdown renderers don't follow links inside backticks, so this is benign — but iter-19's mechanical audit should add code-fence-aware parsing (strip triple-backtick blocks AND single-backtick inline regions before scanning) to avoid false positives at scale. iter-4 patched the audit script accordingly: 14 inline-code matches were filtered after the patch, leaving 11 real relative links checked.

## Cross-references

- Coverage matrix: [`INDEX.md`](./INDEX.md)
- Campaign contract: [`../LOOP_CONTRACT.md`](../LOOP_CONTRACT.md)
