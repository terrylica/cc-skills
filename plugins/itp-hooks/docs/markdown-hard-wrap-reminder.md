# Markdown hard-wrap reminder (net-new)

**Hook**: [`posttooluse-markdown-hard-wrap-reminder.ts`](../hooks/posttooluse-markdown-hard-wrap-reminder.ts) — inlined subhook of the iter-93 PostToolUse orchestrator · **Escape hatch**: `MD-HARD-WRAP-OK` · **Hub**: [itp-hooks CLAUDE.md](../CLAUDE.md)

Reminds Claude when a `Write`/`Edit`/`MultiEdit` of a `.md` file **introduces** prose broken mid-sentence at a fixed column, instead of authored as one line the renderer reflows.

## The surface split — what hard wrapping actually breaks

This is the fact the reminder is built on, and the one it must not overstate. Per [GFM spec §6.13](https://github.github.com/gfm/#soft-line-breaks) a soft line break renders as a **space**; GitHub enables hard-break rendering only on comment-shaped surfaces.

| Surface                                          | A single newline inside a paragraph renders as | Hard wrapping is                                  |
| ------------------------------------------------ | ---------------------------------------------- | ------------------------------------------------- |
| Repository `.md` files (README, CLAUDE.md, docs) | a space — the paragraph reflows correctly      | cosmetically harmless, but noisy in diffs         |
| Release notes                                    | `<br>`                                         | **broken** — a column of short mid-sentence lines |
| Issue bodies, PR bodies, issue/PR comments       | `<br>`                                         | **broken**                                        |
| Gmail (the CLI's `toHtmlBody`)                   | `<br>`                                         | **broken**                                        |

Sources: [GFM §6.13](https://github.github.com/gfm/#soft-line-breaks), [community discussion #35750](https://github.com/orgs/community/discussions/35750) (release notes vs README, reproduced side by side), [#64221](https://github.com/orgs/community/discussions/64221) (files vs comments).

**So a hard-wrapped `.md` does not render broken on GitHub, and the reminder never claims it does.** The two harms it does claim are real:

1. **It breaks on arrival.** This marketplace's markdown is routinely lifted into release notes and issue bodies, where newlines become `<br>`. The prose is authored once and rendered on several surfaces; only the hard-wrapped shape is surface-dependent.
2. **Diff noise, always.** Rewording one sentence in a hard-wrapped paragraph re-flows every following line, so `git diff` and `git blame` attribute the whole paragraph to the edit.

## Where this sits among the sibling guards

The other three cover the **publish** boundary. This one covers the **authoring** boundary, which was the only unguarded surface.

| Boundary                           | Mechanism                                                                                            | Escape hatch      |
| ---------------------------------- | ---------------------------------------------------------------------------------------------------- | ----------------- |
| `gh release \| issue \| pr \| api` | [`pretooluse-github-hard-wrap-guard.ts`](../hooks/pretooluse-github-hard-wrap-guard.ts) — denies     | `GH-HARD-WRAP-OK` |
| semantic-release → GitHub Releases | `release.config.cjs` → `reflowCommitBodyForGfm()` → `scripts/reflow-release-notes.ts` — auto-reflows | —                 |
| Gmail draft bodies                 | [`pretooluse-gmail-body-guard.ts`](../hooks/pretooluse-gmail-body-guard.ts) — denies                 | `GMAIL-BODY-OK`   |
| **Authoring a `.md`**              | **this hook — reminds**                                                                              | `MD-HARD-WRAP-OK` |

All four share the one detector, [`lib/hard-wrap-detector.ts`](../hooks/lib/hard-wrap-detector.ts).

Nothing else was watching authoring, and nothing was going to fix it later either: [`stop-markdown-lint.ts`](../hooks/stop-markdown-lint.ts) runs `prettier --write --prose-wrap preserve`, so a wrap written into a `.md` is **preserved forever**.

## Why net-new only

Measured over this repo's 1,114 tracked `.md` files at the time the hook was added: **193 files (17%) were already hard-wrapped**, 3,389 wrap points in total. A hook that fired whenever an edited file _contained_ a wrap would nag on every one of those files, every time, for debt the current edit did not create — and a guard that cries wolf gets disabled.

| Tool        | Rule                                                                               | Rationale                                                                         |
| ----------- | ---------------------------------------------------------------------------------- | --------------------------------------------------------------------------------- |
| `Edit`      | fire iff `detectHardWraps(new_string).length > detectHardWraps(old_string).length` | rewording inside an already-wrapped paragraph leaves the count unchanged → silent |
| `MultiEdit` | same comparison per `edits[]` pair; fire on the first that increases               | one wrapped addition among clean edits still surfaces                             |
| `Write`     | fire on **any** wrap in `content`                                                  | the one non-strict arm — see below                                                |

### The comparison runs on the whole file, not the edit fragment

An `Edit` fragment lifted from **inside a fenced code block carries no ``markers**. Scanning that fragment on its own therefore reads shell commands as wrapped prose — two `bun scripts/reflow-release-notes.ts …` lines in a``bash block were a measured false positive, and updating a command example is one of the most common `.md` edits there is.

So the hook reads the post-edit file from disk (PostToolUse fires after the write, so the file **is** the after-state) and reconstructs the before-state by undoing each replacement — `content.replace(new_string, old_string)`, applied in **reverse** order for `MultiEdit` because a later edit may have landed inside text an earlier one produced. `String.replace` with a string pattern rewrites the first match only, which is exactly `Edit`'s own uniqueness contract.

Added wraps are then identified by **shape** (`width` + continuation preview), not line number: undoing an edit shifts every subsequent line, so a line-number join would report the whole tail of the file as new. The reminder reports only the wraps the edit actually added, at their real whole-file line numbers.

If the file cannot be read (deleted, unreadable, synthetic input) the hook falls back to the per-fragment comparison. That fallback is best-effort and _will_ misread a fence interior — it is a degradation, not an equivalent, and is covered by its own test.

### Why the `Write` arm differs

The `Write` arm is deliberately not net-new. PostToolUse fires _after_ the write, so the previous content is already gone from disk and there is no before-state to compare against. Firing on any hit is the right default regardless: a whole-file `Write` **is** authoring, and freshly authored prose should not arrive pre-wrapped. This mirrors [`posttooluse-invented-fallback-reminder.ts`](../hooks/posttooluse-invented-fallback-reminder.ts), whose net-new pattern this hook follows.

## Detector accuracy, and the one false-positive class fixed

Classifying every one of the 3,389 detections on this corpus:

| Class                                          | Share    | Verdict                                                                                   |
| ---------------------------------------------- | -------- | ----------------------------------------------------------------------------------------- |
| Plain wrapped prose paragraphs                 | 59%      | true positive                                                                             |
| Wrapped list-item continuations                | 18%      | true positive — `reflowMarkdown()` joins these on purpose                                 |
| Wrapped list items                             | 14%      | true positive — a wrapped bullet renders as a mid-sentence `<br>` in GFM comment surfaces |
| Prose containing arrows/box-drawing characters | 5%       | true positive (prose, not diagrams — fenced and 4-space-indented art is already skipped)  |
| **Consecutive badge / link-only rows**         | **2.6%** | **false positive — fixed**                                                                |

Badge rows were the only systematic false positive: each is wide, ends on `)` rather than a clause terminator, and is followed by another badge row, so every "prose that wraps" heuristic fired on a construct containing no prose. `isLinkOnlyLine()` in the shared detector now treats a line whose _entire_ visible content is inline links/images as structural. A prose line that merely _contains_ a link is still measured. Corpus effect: 193 → 169 files, no true positives lost. Because the predicate lives in the shared lib, the `gh` and Gmail guards got the same fix.

### The nested-bullet blind spot (the bigger find)

The false-**negative** side turned out to matter more, and was caught from a real published release page whose sub-bullets rendered as a column of short lines.

A sub-bullet's wrapped tail is indented four or more spaces:

```text
  - `github_release` is now tri-state. A 2xx or an AUTHENTICATED 4xx is an
    observation; an unauthenticated 401/403/404, any 5xx, or a transport
    failure is not, and is marked `indeterminate`.
```

`isIndentedCodeBlock()` matches any line indented four or more spaces, so **every line of a nested bullet was read as an indented code block and skipped**. Top-level bullets (two-space continuation) were caught; nested ones were invisible — to all four consumers, including the `gh release` guard. That is precisely how hard-wrapped sub-bullets reached a published GitHub release.

`computeListContinuationLineMask()` now tracks list context: inside a list item, content indented to the item's content column is a continuation paragraph, not code — which is also what CommonMark says. Genuine indented code (no enclosing list, or after a dedent back to column zero) is still treated as code, and fenced code was never affected. The mask marks list **marker** lines too, because a third-level bullet (`- text`) is itself indented four spaces and would otherwise be skipped before its own wrap was measured.

Corpus effect: +91 previously-invisible nested-bullet wraps. Net across both fixes: **169 files, 3,411 wrap points** (from 193 / 3,389).

Two files score **0** and are the reference shape for this repo's prose: `plugins/itp-hooks/CLAUDE.md` and `docs/LESSONS.md`.

## Fixing a file

```bash
bun scripts/reflow-release-notes.ts < file.md > file.new.md && mv file.new.md file.md
bun scripts/reflow-release-notes.ts --check < file.md   # exit 1 if it would change
```

`reflowMarkdown()` preserves fenced code, tables, headings, blockquote markers, and explicit two-space hard breaks; it joins wrapped prose and wrapped list items. **Known hazard**: it does not recognise 4-space-**indented** (non-fenced) code blocks and will join them as prose. Check the diff on any file that uses them. This is also why the Stop-hook formatter was left on `--prose-wrap preserve` rather than switched to auto-reflow — silently rewriting every edited `.md` has a blast radius that a reminder does not.

## Escape hatch

Add `MD-HARD-WRAP-OK` anywhere in the file (any comment style, e.g. `<!-- MD-HARD-WRAP-OK -->`) when the wrapping is deliberate — a verbatim quoted email, a fixed-width sample, prose whose line breaks are themselves the content. `CASE_SENSITIVE`, `FILE_WIDE`, no reason required; registered in the [iter-111 canonical registry](../hooks/lib/marketplace-wide-escape-hatch-producer-marker-canonical-registry-cross-plugin-iter111.ts).

Pre-existing wraps never fire, so the marker is only needed for wrapping you are adding on purpose.

## Guarantees

- **Never blocks.** `additional_context` folded into the orchestrator's aggregated `{decision: "block", reason}`, which for PostToolUse is context injection, not rejection.
- **Fail-open.** Any parse or logic error → `noop`. Malformed input, missing `tool_input`, unknown tool → silent.
- **Cheap.** Pure single-pass scan of the edited fragment; no subprocess, no file read. Registry position last, behind an O(1) extension pre-filter.
- **Temp-scratch exempt** via the shared iter-124 helper — `/tmp/notes.md` is never nudged.
- **Out of scope**: git commit and annotated tag messages. 72-column wrapping is correct there; the reflow belongs at the publish boundary, which the sibling guards own.

## Tests

[`posttooluse-markdown-hard-wrap-reminder.test.ts`](../hooks/posttooluse-markdown-hard-wrap-reminder.test.ts) — 32 tests. Three are load-bearing:

- _"stays SILENT when an Edit rewords inside an already-wrapped paragraph"_ — if it regresses, the hook nags on 169 files.
- _"does NOT flag two shell lines edited inside a bash fence"_ — if it regresses, the hook fires on every command-example edit.
- _"fires on a Write of hard-wrapped sub-bullets"_ — if it regresses, the nested-bullet blind spot is back.

[`lib/hard-wrap-detector.test.ts`](../hooks/lib/hard-wrap-detector.test.ts) — 35 tests, covering the badge rows, the nested/third-level/ordered sub-bullets, and the two cases that must STAY code (an indented block with no list context, and one after a dedent to column zero).

## Adversarial-review fixes

A 16-agent adversarial review confirmed two defects, both fixed and regression-tested:

| Defect                                     | Consequence                                                                                                                                            | Fix                                                                                 |
| ------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------ | ----------------------------------------------------------------------------------- |
| `replace_all` ignored when undoing an edit | `replace_all` rewrote every occurrence but only the first was undone, leaving new text in the reconstructed before-state and under-reporting the delta | `extractEditPairs` carries the flag; `replaceAll` is used when set                  |
| No `isFile()` gate before reading the file | `Bun.file().text()` on a FIFO blocks until a writer appears, hanging the subhook until the orchestrator timeout on every edit                          | `statSync(filePath).isFile()` gate, matching `pretooluse-github-hard-wrap-guard.ts` |

The same review found **no false positives** across 57 adversarial cases (tilde fences, nested fences, front matter, HTML blocks, setext headings, CJK prose, long URLs, ASCII diagrams), measured `detectHardWraps` at 13 ms on a 1.3 MB file and 58 ms on a synthetic 10 MB one — both far inside the 2 s budget — and found no ReDoS in `isLinkOnlyLine`.
