# HTML measure guard

> Spoke of [itp-hooks CLAUDE.md](../CLAUDE.md). Source: [`hooks/pretooluse-html-measure-guard.ts`](../hooks/pretooluse-html-measure-guard.ts), detector [`hooks/lib/html-text-measure-detector.ts`](../hooks/lib/html-text-measure-detector.ts).

Text on an HTML page follows the browser window. On 2026-10-28 the operator ruled that there should be no hard wrapping of lines in anything presented as HTML or Markdown, and made it a forced convention for every Orca artifact and HTML page. The Markdown half was already guarded (the hard-wrap reminders and [the commit guard](./markdown-hard-wrap-reminder.md)). This guard is the HTML half.

## Why CSS is the HTML form of a hard wrap

A page rarely contains literal line breaks inside its paragraphs. What fixes where its lines end is CSS. The case that prompted the rule was a stylesheet that stopped prose at `max-width:72em` (about 1,150 px) inside a `max-width:1560px` page. On a wide screen the paragraphs ended well short of the tables beside them, and widening the window changed nothing. That is the same defect as a paragraph hard-wrapped at 100 columns: the author's line length wins over the reader's window.

## What it flags

| Rule                    | Example                                                                                       | Why                                                                          |
| ----------------------- | --------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------- |
| A text measure          | `p{max-width:72em}`, `max-width:60ch`, `max-width:min(100%,70ch)`, `width:66ch`               | A length tied to the font ends every line at a fixed number of characters    |
| A page-width cap        | `body{max-width:1560px}`, `main{max-width:1180px}`, `.inner{…}`, `<body style="max-width:…">` | The whole page stops growing, so text cannot use a wider window              |
| Pre whitespace on prose | `p{white-space:pre-line}`, `<div style="white-space:pre-wrap">`                               | The source's own line breaks are rendered, so a wrapped source stays wrapped |

Page containers are `body`, `main`, `article`, `.inner`, `.topin`, `.wrap`, `.container`, `.page`, `.content`, `.viz-root` and `.explain`.

## What it leaves alone

- `@media (max-width: …)` conditions and the inner `min(100%, 1100px)` of an image rule.
- Images (`img{max-width:100%}`), charts, tooltips (`.tip{max-width:320px}`) and small banners: they are not text columns.
- Table columns (`td{min-width:22em}`). Give a wide table its own `overflow-x:auto` box instead of narrowing the page.
- Code: `pre`, `code`, `kbd`, `samp`, `textarea`, `.code` and `.mono` may keep their lines.
- Markdown files, which the hard-wrap guards cover.

## Where it runs

1. **Write and Edit**, as a subhook of the [Write|Edit orchestrator](./pretooluse-write-edit-orchestrator.md), on pages, stylesheets and the sources that build them (`.html .css .scss .py .ts .tsx .js .mjs .vue .svelte .astro .sh` and template formats). For an Edit the whole file after the edit is compared with the file before it, so only findings the edit adds are denied, and a page with an old cap can still be edited elsewhere.
2. **Bash**, as an entry of the [Bash guard orchestrator](./pretooluse-bash-guard-orchestrator.md), on `orca artifacts share|update FILE` (it reads the file) and `wrangler pages deploy DIR` (it reads every page under DIR). This catches pages written by generator scripts, which the Write|Edit surface never sees. A path that does not exist on this machine, such as one inside an `ssh` command, is skipped.

## Escape hatch

`HTML-MEASURE-OK` anywhere in the file (a comment), in the proposed text, or in the command. Use it only for a page that must stay as it is, such as an outside page archived verbatim. For your own page, delete the declaration so the text fills the window.

## Build-time copies

A repository can enforce the same rule when it builds pages: its page builders refuse to write a page with a fixed text width, and its check task scans every tracked builder and page. That catches pages no agent touches. Such a copy should pass the FLAGGED and ALLOWED vectors in [`pretooluse-html-measure-guard.test.ts`](../hooks/pretooluse-html-measure-guard.test.ts); change the guard and the copies together.
