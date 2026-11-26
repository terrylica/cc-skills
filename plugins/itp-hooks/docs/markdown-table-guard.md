# Markdown table guard

Per-edit detection of GFM tables that won't render on GitHub / VS Code preview, plus a Stop-hook safety gate and a manual repo-wide sweep. Added 2026-06-28.

## The problem (why a guard, not just a formatter)

GFM ignores whitespace between pipes, so **misalignment never breaks a table** — the cause is **structural**, overwhelmingly an **unescaped `|` inside a cell**. GFM's tokenizer treats `|` as a column delimiter _even inside a `` `code span` ``_, so a regex/code cell inflates that row's cell count and the whole block silently becomes a paragraph. The fix — escaping the pipe as `\|` — changes meaning, so **no formatter can apply it safely**; Prettier actively corrupts such tables (prettier#10164 / #11410). Hence the design: **detect → remind → Claude escapes the pipes**, while alignment/blank-lines stay the formatter's job.

## Three layers

| Layer          | File                                        | Role                                                                                                                                                                                                                |
| -------------- | ------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Per-edit guard | `hooks/posttooluse-markdown-table-guard.ts` | On `.md`/`.markdown` Write/Edit, reads the file and emits `{decision:block,reason}` (Claude-visible, non-blocking) when a render-breaking ERROR is found.                                                           |
| Detection SSoT | `hooks/lib/markdown-table-detector.ts`      | Pure, dependency-free `detectBrokenTables` / `hasTableErrors` / `buildTableReminder`. Shared by the guard and the gate.                                                                                             |
| Prettier gate  | `hooks/stop-markdown-lint.ts`               | At session exit, partitions changed `.md` into clean vs broken-table; runs prettier + `markdownlint --fix` on **clean files only**, and reports skipped broken files (so prettier can't bake in a corrupted split). |

A manual, repo-wide counterpart ships as the `doc-tools:markdown-table-validator` skill (`scan_markdown_tables.ts`, with opt-in `--fix`) — same algorithm, used to clean **existing** docs in bulk.

## What fires (errors) vs what stays silent (info)

| Code                     | Severity | Auto-fixable?               | Behavior                                      |
| ------------------------ | -------- | --------------------------- | --------------------------------------------- |
| `column-overflow`        | error    | no (changes meaning)        | Guard reminds.                                |
| `header-mismatch`        | error    | no                          | Guard reminds.                                |
| `indented-table`         | error    | no                          | Guard reminds.                                |
| `alignment-colon-in-row` | error    | no                          | Guard reminds.                                |
| `short-row`              | info     | yes (`markdownlint --fix`)  | Detected but the per-edit guard stays silent. |
| `missing-blank-line`     | info     | yes (prettier/markdownlint) | Detected but the per-edit guard stays silent. |

The per-edit guard nags **only on errors** to keep the signal high; the manual sweep reports every severity.

## Detection notes

- Cell counting splits on `/(?<!\\)\|/` after stripping one outer pipe each side — GFM-accurate, deliberately _not_ code-span-aware (that is the bug we catch).
- A delimiter row must contain at least one `|`, so a bare `---` (thematic break / setext underline) is never mistaken for a table.
- Fenced code blocks (` ``` ` / `~~~`) are skipped, so example broken tables shown inside docs don't trip the guard.

## Escape hatch

A comment containing `MD-TABLE-OK` anywhere in the file silences the per-edit reminder (canonical marker registry, CASE_SENSITIVE / FILE_WIDE). It does **not** make prettier format a broken table — the Stop-hook gate still skips it to avoid corruption.

## What the Stop hook leaves unformatted

`hooks/stop-markdown-lint.ts` runs at every stop over each `.md` with uncommitted changes: `prettier --write --prose-wrap preserve`, then `markdownlint-cli2 --fix`. Three kinds of file are left exactly as they were, withheld from both formatters, and named in the hook's report:

| Left alone when                                     | Why                                                                                                                            | Report line                                                      |
| --------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------ | ---------------------------------------------------------------- |
| It has a render-breaking table error                | Prettier would bake in the wrong column split (above)                                                                          | `SKIPPED auto-format — broken table at L…`                       |
| The repository's `.prettierignore` lists it         | The repository said never to format it; markdownlint has no ignore file of its own, so the hook filters the file list for both | `ignore: skipped N file(s) per .prettierignore`                  |
| Formatting would blow it up by padding a wide table | Next section                                                                                                                   | `SKIPPED auto-format — prettier would grow it from X to Y bytes` |

The report goes to stderr through the Stop orchestrator ([stop-hooks.md](./stop-hooks.md)), so it is in the transcript without keeping the session running.

### Wide-table padding guard

Prettier aligns a table by padding every cell to the widest cell of its column, so a table with a few very long cells becomes mostly spaces. With `--prose-wrap preserve` it always prints the aligned form, and nothing bounds the result. Measured: a file holding one table of about 275 rows went from 161,149 to 1,322,925 bytes in a single run of the hook while 9 lines of content had changed. It later reached 1.69 MB, 83% of it padding; unpadded, the same content is 318 KB, which prettier would turn into 3.6 MB.

The hook leaves a file unchanged when formatting would do both of these:

- **at least double it** (`OVERSIZE_GROWTH_RATIO = 2`): more than half of the formatted file would be padding added by that one run;
- **add at least 32 KiB** (`OVERSIZE_MIN_GROWTH_BYTES`): small files double all the time and harmlessly (a 62-byte table becomes 92 bytes), so the ratio alone must not decide.

The measured case clears the ratio 4 times over and the byte floor 35 times over. On the other side, with every table in this repository's 1,034 tracked `.md` files stripped of its padding, formatting them back trips the rule for none: the largest growth is 27,508 bytes at 1.37x, and the largest ratio is 2.69x at 17,421 bytes.

The decision is measured, not estimated: the hook formats the file to a buffer with the same options and compares sizes, and nothing is written. To keep that off the ordinary path, a cheap upper bound runs first (`tablePaddingGrowthUpperBound`: for each table, rows × the sum of its longest lines, which no column split can exceed). A file whose bound is under the byte floor cannot trip the rule and goes straight to the usual single `prettier --write` call; in this repository 36 of the 1,034 files are over it. A file over the bound that prettier cannot format to a buffer is also left unchanged and reported.

What to do when a file is reported:

- **Never format it:** list it in the repository's `.prettierignore`. That is the permanent opt-out, it applies to markdownlint too, and it ends the measurement, which otherwise repeats at every stop while the file has uncommitted changes.
- **Accept the padding:** run prettier on the file by hand.
- **Shrink the table:** move the long cells out of it (a footnote, a list under the table, a linked file).

## Tests

- `hooks/stop-markdown-lint.test.ts` — thresholds (the measured case, small files that double, large files that grow modestly), the upper bound against prettier's real output, and the spawned hook in a scratch repository: a wide-table file stays byte-identical and is reported, small and medium tables are still formatted, a `.prettierignore` entry is still skipped.
- `hooks/tests/markdown-table-detector.test.ts` — detector corpus (the real gh-fine-grained-pat bug, escaped-`\|` valid tables, fenced-code skip, setext / prose false-positive guards, info-vs-error severity).
- `hooks/posttooluse-markdown-table-guard.test.ts` — pure gate/eval + spawned end-to-end (broken→block, clean→silent, temp-scratch exempt, non-md skip).
