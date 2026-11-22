# publishing-standard Evolution Log

Reverse-chronological log of skill improvements.

---

## 2026-11-15: Initial skill creation

**Source**: The operator found the "last updated" line on a published index poorly presented: hand-written relative words, one flat colour for every age, and no age at all on a second index. He asked for the age to be rendered in the browser with a heat colour scale and the lightest possible tooling. He also asked that every page carry its provenance and a way back to its index, that a sitemap link every site together, and that each published link have a single source of truth.

**Decisions**: the must-haves (live age marker, exact moment, version and commit, source, way back); `Intl.RelativeTimeFormat` with no library; nine pre-computed OKLCH heat steps as hex values (older engines lack `color-mix()`); exact moments written at build time, because a browser's time-zone database can predate a rule change; one `published.v1` registry per publishing repository, aggregated by the sitemap (federated, never copied); the audience rule for linking a sitemap. A reminder hook in itp-hooks points at this skill once per session, before a publish command and after an HTML page is written.
