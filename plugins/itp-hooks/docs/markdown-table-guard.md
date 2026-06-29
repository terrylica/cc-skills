# Markdown table guard

Per-edit detection of GFM tables that won't render on GitHub / VS Code preview,
plus a Stop-hook safety gate and a manual repo-wide sweep. Added 2026-06-28.

## The problem (why a guard, not just a formatter)

GFM ignores whitespace between pipes, so **misalignment never breaks a table** —
the cause is **structural**, overwhelmingly an **unescaped `|` inside a cell**.
GFM's tokenizer treats `|` as a column delimiter _even inside a `` `code span` ``_,
so a regex/code cell inflates that row's cell count and the whole block silently
becomes a paragraph. The fix — escaping the pipe as `\|` — changes meaning, so
**no formatter can apply it safely**; Prettier actively corrupts such tables
(prettier#10164 / #11410). Hence the design: **detect → remind → Claude escapes
the pipes**, while alignment/blank-lines stay the formatter's job.

## Three layers

| Layer          | File                                        | Role                                                                                                                                                                                                                |
| -------------- | ------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Per-edit guard | `hooks/posttooluse-markdown-table-guard.ts` | On `.md`/`.markdown` Write/Edit/MultiEdit, reads the file and emits `{decision:block,reason}` (Claude-visible, non-blocking) when a render-breaking ERROR is found.                                                 |
| Detection SSoT | `hooks/lib/markdown-table-detector.ts`      | Pure, dependency-free `detectBrokenTables` / `hasTableErrors` / `buildTableReminder`. Shared by the guard and the gate.                                                                                             |
| Prettier gate  | `hooks/stop-markdown-lint.ts`               | At session exit, partitions changed `.md` into clean vs broken-table; runs prettier + `markdownlint --fix` on **clean files only**, and reports skipped broken files (so prettier can't bake in a corrupted split). |

A manual, repo-wide counterpart ships as the `doc-tools:markdown-table-validator`
skill (`scan_markdown_tables.ts`, with opt-in `--fix`) — same algorithm, used to
clean **existing** docs in bulk.

## What fires (errors) vs what stays silent (info)

| Code                     | Severity | Auto-fixable?               | Behavior                                      |
| ------------------------ | -------- | --------------------------- | --------------------------------------------- |
| `column-overflow`        | error    | no (changes meaning)        | Guard reminds.                                |
| `header-mismatch`        | error    | no                          | Guard reminds.                                |
| `indented-table`         | error    | no                          | Guard reminds.                                |
| `alignment-colon-in-row` | error    | no                          | Guard reminds.                                |
| `short-row`              | info     | yes (`markdownlint --fix`)  | Detected but the per-edit guard stays silent. |
| `missing-blank-line`     | info     | yes (prettier/markdownlint) | Detected but the per-edit guard stays silent. |

The per-edit guard nags **only on errors** to keep the signal high; the manual
sweep reports every severity.

## Detection notes

- Cell counting splits on `/(?<!\\)\|/` after stripping one outer pipe each side
  — GFM-accurate, deliberately _not_ code-span-aware (that is the bug we catch).
- A delimiter row must contain at least one `|`, so a bare `---` (thematic break /
  setext underline) is never mistaken for a table.
- Fenced code blocks (` ``` ` / `~~~`) are skipped, so example broken tables shown
  inside docs don't trip the guard.

## Escape hatch

A comment containing `MD-TABLE-OK` anywhere in the file silences the per-edit
reminder (iter-111 canonical registry, CASE_SENSITIVE / FILE_WIDE). It does
**not** make prettier format a broken table — the Stop-hook gate still skips it
to avoid corruption.

## Tests

- `hooks/tests/markdown-table-detector.test.ts` — detector corpus (the real
  gh-fine-grained-pat bug, escaped-`\|` valid tables, fenced-code skip, setext /
  prose false-positive guards, info-vs-error severity).
- `hooks/posttooluse-markdown-table-guard.test.ts` — pure gate/eval + spawned
  end-to-end (broken→block, clean→silent, temp-scratch exempt, non-md skip).
