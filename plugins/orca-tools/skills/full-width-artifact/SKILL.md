---
name: full-width-artifact
description: Publish a Markdown or HTML file as an Orca artifact (share.onorca.dev link) that uses the FULL browser width, with no fixed-width column and no hard line breaks. Orca renders a Markdown artifact through its own template, which caps the page at a fixed pixel width, so a bare `orca artifacts share report.md` always gives a narrow page. The script renders Markdown to full-width HTML with pandoc, repairs uploaded HTML, publishes (keeping the same link when re-published), then fetches the served page to prove it is still full width. Use for any report, explainer or page shared through Orca artifacts. TRIGGERS - orca artifact, share an artifact, share.onorca.dev, publish a report to Orca, orca artifacts share, artifact full width, artifact narrow column, artifact too narrow, page width, no hard wrap.
allowed-tools: Bash, Read
---

# Full-width Orca artifacts

> **Self-Evolving Skill**: This skill improves through use. If Orca's artifact pages change, a measured fact below no longer holds, or a workaround was needed: fix this file and the script immediately, don't defer. Only update for real, reproducible issues.

**Rule (operator, 2026-10-28/29):** every Orca artifact uses the full width of the browser. No fixed-width column, and no hard line breaks in any text on the page. Text follows the reader's window.

## Why a bare `orca artifacts share` is not enough (measured 2026-10-29)

- A **Markdown** artifact is rendered by Orca's own template. Its stylesheet caps the body at 820 px and centres it, so the text is a narrow column with wide empty margins at any window size. Nothing in your Markdown file can change that.
- The **share page** around the artifact is not the limit: it shows the artifact in an iframe that is 100% wide.
- An **HTML** artifact is served as uploaded. So the fix is to upload HTML whose stylesheet sets no fixed content width.
- The share page's header shows the **uploaded file's name**, so the file should carry a clean, readable name.

## Use

```bash
S="$(cc-plugin-root orca-tools)/skills/full-width-artifact/scripts/orca-artifact-share"
bun "$S" report.md                 # Markdown -> full-width HTML, publish, verify the served page
bun "$S" page.html                 # HTML: fixed widths rewritten, marker added, publish, verify
bun "$S" report.md --dry-run       # render and lint only
bun "$S" --check <share-url>       # audit an artifact that is already published
bun "$S" --lint page.html          # lint a local page
```

stdout is one JSON object, for example `{"ok":true,"url":"https://share.onorca.dev/a/…","html":"…","problems":[]}`. Exit codes: 0 ok, 1 the page or the served page is not full width, 2 usage, 3 pandoc or Orca failed. `ORCA_CLI` names Orca's CLI explicitly; `ORCA_ARTIFACT_DIR` moves the rendered HTML (default `~/.local/share/orca-artifact/<hash>/<name>.html`).

- **Same link on re-publish.** The HTML for a given source always lands at the same path, and the script tries `orca artifacts update` before `share`, so fixing a report and re-running it keeps the link you already sent. It falls back to `share` **only** when Orca answers that the file was never shared from this profile. Any other update failure (a cloud `429` from publishing many times in a row, a network error, Orca signed out) exits 3 and leaves the link alone: `share` would mint a new link and overwrite the old edit token in Orca's `artifact-shares.json`, and the link readers already have could then never be updated again. On exit 3 from a 429, wait and re-run; do not publish in a tight loop.
- **Verified after publishing.** The script fetches the share page, follows its iframe to the served content, and lints what is actually served. If Orca ever starts narrowing HTML artifacts too, the run exits 1 with the reason instead of reporting success.
- **Requires** `pandoc` for Markdown (macOS `brew install pandoc`, Debian/Ubuntu `apt install pandoc`) and Orca's CLI, found the same way as the other orca-tools scripts (never a bare `orca`, which on Linux desktops is often the screen reader).

## What "full width" means here

The lint is a copy of itp-hooks' html-measure rule (`plugins/itp-hooks/hooks/lib/html-text-measure-detector.ts`): no `max-width` in em, ch or rem; no `width` in ch; no pixel `max-width` on a page container (`body`, `main`, `article`, `.container`, `.page`, …); no `white-space: pre*` on prose. Images, charts, tooltips, `@media` conditions and code blocks are left alone. On top of that it requires the layout marker `<meta name="orca-artifact-layout" content="full-width/v1">` and rejects a `<br>` inside a paragraph. Wide tables get their own horizontal scroll box instead of narrowing the page. The copy and the original are tested against the same vectors (`plugins/itp-hooks/hooks/lib/html-text-measure-vectors.ts`), so they cannot drift apart.

## Tables: columns are fitted, never squeezed (measured 2026-11-07)

- **Cause.** Under automatic table layout a browser gives each column at least its min-content width and shares the rest by max-content width. With `overflow-wrap:anywhere` on cells (this template before 2026-11-07) min-content is one character, so a short column beside long prose shrank until its header broke into one letter per line.
- **CSS.** Cells use `overflow-wrap:break-word` (a whole word is the narrowest a column gets), `text-wrap:pretty`, headers `text-wrap:balance`; only links and code inside cells may break anywhere, so a long URL cannot force the table wide. Uploaded HTML gets the same cell rules in its override.
- **Script.** Each page with a table carries a small inline script (`data-orca-table-fit`; Orca's content frame allows inline scripts). It measures every cell's one-line width once (again after fonts load), then sets `<col>` widths with `table-layout:fixed` on every resize: first LaTeX `tabulary`'s rule (a column whose longest cell fits in an equal share stays on one line), then width goes step by step to whichever column shortens the table most. On a narrow screen the comfortable minimum (7 em) gives way first; a whole word never does, and the table scrolls in its own box. Tables with `colspan`/`rowspan`, nested tables, the author's own `<col>` widths and anything inside `[data-fit=off]` are left to the browser. A table that is hidden at load (a closed tab or `<details>`) is fitted when it appears. In uploaded HTML without a scrolling parent, each table is wrapped in an `overflow-x:auto` box first. The planner, `planColumns`, is pure and unit-tested.
- **Result.** On a 1300 px window an eight-column test table kept every header whole and needed about a quarter less height.

## Enforcement

itp-hooks' html-measure guard denies `orca artifacts share|update FILE.md` and points here, and denies publishing an HTML page with a fixed text width. Its escape, `HTML-MEASURE-OK` in the command, is for a deliberate exception only.

## Verified

| Date       | Platform          | What ran                                                                                                                                                                                                                                                                                                                                                                     |
| ---------- | ----------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 2026-10-29 | macOS, Orca 1.4.x | A bilingual (Chinese/English) report with six tables: the Markdown artifact was the 820 px column. Published through this script, the same report filled an 1800 px headless-Chrome window; re-publishing kept the link; `--check` passed on the new link and failed on the old Markdown one (body capped at 820 px, header cells forced onto one line). `bun test` 26 pass. |
| 2026-11-01 | macOS, Orca CLI    | About 30 re-publishes of one page in four hours: `orca artifacts update` returned `orca_cloud_request_failed_429`, the old fallback ran `share`, and a second artifact was created; the first link's edit token was overwritten and not recoverable, so that link froze. Fixed: re-share only on Orca's "has not been shared from the active Orca profile" answer (local, no network); tests cover 429, no JSON, and ok without a URL. `bun test` 31 pass. |

## Post-Execution Reflection

0. **Did a table look squeezed or lopsided?** Screenshot it in headless Chrome at desktop and narrow widths, and adjust `planColumns` with a test that reproduces the case.

1. **Did the published page fill the window?** If a reader saw a narrow column or hard breaks, the lint missed a rule: add it to the shared vectors and the detector, then here.
2. **Did `--check` or the after-publish check fail?** Orca changed how it serves artifacts; record what changed above, with the date, before working around it.
3. **Did re-publishing give a new link?** The stable-path rule or Orca's `update` changed; fix the script and the "Same link" line.
