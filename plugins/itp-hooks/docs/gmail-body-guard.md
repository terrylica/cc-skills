# Gmail draft body guard

**Hook**: `pretooluse-gmail-body-guard.ts` (PreToolUse, matcher `Bash`)
**Detector SSoT**: `hooks/lib/gmail-body-detector.ts` (pure, dependency-free)
**Shared libs consumed**: `hooks/lib/markdown-fence-scanner.ts` (fence mask), `hooks/lib/shell-arg-extractor.ts` (`--body`/`--body-file` extraction)
**Tests**: `hooks/pretooluse-gmail-body-guard.test.ts` (24 bun tests)
**Escape hatch**: `GMAIL-BODY-OK` anywhere in the command
**Doctrine**: `plugins/gmail-commander/skills/gmail-access/SKILL.md`, Evolution Log **2026-07-10** / **2026-07-22**

## Why it exists (incident 2026-07-22)

Vendor-outreach drafts sent via the `gmail` CLI came out **visually chopped** and with raw markdown
showing literally. Root cause is how the CLI builds the message body in
`plugins/gmail-commander/scripts/gmail-cli/lib/gmail-drafts.ts`:

- `toHtmlBody()` joins **every authored newline with `<br>`** — deliberately, so intended breaks (list
  items, a `Best,\nname` sign-off) survive. The corollary: a body **hard-wrapped at a fixed column**
  gets a literal `<br>` at every wrap, so the paragraph renders as a column of short lines instead of
  reflowing to the reader's window.
- The CLI **HTML-escapes** the body and does **not** render markdown, so `**bold**`, `` `code` ``,
  `[text](url)`, `#` headings and pipe-delimited tables reach the recipient as raw source characters.

The skill already documented the rule (single-line paragraphs, plain prose) but nothing enforced it.
This PreToolUse guard blocks a bad `gmail draft` / `draft-update` **before** the draft is created.

## What it inspects

- `--body "<inline>"` — via the shared `shell-arg-extractor` (single/double/`$'…'`/bare quoting).
- `--body-file <path>` — read from disk; `~` and cwd-relative paths resolved (cwd → `CLAUDE_PROJECT_DIR`
  → `process.cwd()`). A missing/unreadable file is **skipped**, never blocked.

Only `gmail draft` / `draft-update` invocations are considered (CLI referenced as `gmail`, `$GMAIL_CLI`,
or a `.../gmail` path **and** a `draft`/`draft-update` subcommand). `gmail list`/`search`/`read` and any
non-Bash tool are ignored.

## Detection

### Hard-wrap (`detectHardWraps`)

A mid-sentence line break inside a prose paragraph. Bodies split into paragraph blocks (fenced code
skipped via the shared fence scanner); an adjacent pair `(A, B)` flags a wrap at A when **all** hold:

- **A is prose** — not a table row, ATX heading, or thematic break.
- **A ends "open"** — A's last non-space char is not in `.!?:;` (a trailing comma / hyphen / word = an
  unfinished clause continued on the next line).
- **A is wide** — A's trimmed length ≥ `minWrapWidth` (default **50**), so short salutations and
  sign-offs are exempt.
- **B continues prose** — after `trimStart`, B does not begin a new list item / heading / blockquote /
  table.

Single-line-per-paragraph (the desired form) makes each block one line → no pair → clean. Wrapped
list-item bodies (indented continuations) are still caught — desired, since `<br>` chops those too.

### Literal markdown (`detectLiteralMarkdown`)

High-signal, low-false-positive set (fenced code skipped):

- **bold** — `**…**` (any); `__…__` **only** when the inner is not a bare identifier (so `__init__` is
  exempt).
- **code** — `` `…` `` paired single backticks.
- **link** — `[text](url)`; the `](` pivot is highly markdown-specific.
- **heading** — an ATX heading (`#{1,6}` + space) at line start.
- **table** — a pipe-delimited row (starts with a pipe, ≥2 pipes on the line).

Single-char `*italic*` / `_italic_` are intentionally **not** flagged — lone `*`/`_` appear constantly
in prose, math, filenames, emails and URLs, so they would false-positive.

## Output & failure model

- On detection → PreToolUse **`deny`** with a `[GMAIL-BODY-GUARD]` reason that lists the hard-wrap
  line(s) and/or raw-markdown construct(s) per source and the single fix (author each paragraph as one
  unbroken line; send plain prose).
- **Fail-open everywhere**: any parse/read/logic error → `allow` (never blocks real work), via
  `trackHookError` + `allow()` in the top-level `catch`.

## Related

- Shares the fenced-code scanner with the [markdown-table guard](./markdown-table-guard.md).
- Shares the `--body`/`--body-file` extraction with the [release-notes](./release-notes-extensiveness-guard.md)
  and sred guards via `hooks/lib/shell-arg-extractor.ts`.
- Command-guard structure (allow/deny/parseStdinOrAllow/fail-open) mirrors
  [git-worktree-guard](./git-worktree-guard.md).
