# Markdown hard-wrap reminder (net-new)

**Hook**: [`posttooluse-markdown-hard-wrap-reminder.ts`](../hooks/posttooluse-markdown-hard-wrap-reminder.ts) — inlined subhook of the iter-93 PostToolUse orchestrator · **Escape hatch**: `<!-- MD-HARD-WRAP-OK -->` — an HTML comment; merely naming the token no longer suppresses · **Hub**: [itp-hooks CLAUDE.md](../CLAUDE.md)

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

## Only the wraps the joiner would actually repair (issue #106 finding 3)

The detector and the joiner ask different questions. The detector asks "does this line break mid-sentence at a fixed column"; [`lib/gfm-unwrap.ts`](../hooks/lib/gfm-unwrap.ts) asks "may I safely join it". They disagree on **hand-aligned indented blocks** — a quoted price schedule, a citation footer, an aligned `key    value` list inside a bullet. Two spaces is not a code fence, so the detector reads each row as prose; the joiner's `ALIGNED_BLOCK_LINE` recognises the alignment and refuses to touch it. Reporting a wrap whose recommended remedy would not change it is a false positive by construction, so the hook now filters those out.

**Per wrap, not per file.** The issue proposed the file-level rule "if the joiner would make zero joins, do not report at all". Measured across all 1,094 tracked `.md` files, the number with detector wraps > 0 **and** joins == 0 is **zero** — that rule would not have changed a single report, because a file containing an aligned block essentially always contains a joinable paragraph beside it. The per-wrap form silences **28 of 5,078** wraps (0.55%): 24 in `CHANGELOG.md` (aligned evidence tables quoted from commit bodies) and 4 in `docs/self-custody-secrets.md` (indented `vault …   # comment` command lists inside a bullet). Same intuition, different granularity, and only one of the two is real.

The filter is one code path with the joiner, not a second predicate that predicts it: `computeJoinedWithNextLineMask()` runs the joiner's own cursor walk and reports which breaks it removed. A prediction that could drift from the joiner is the very disagreement this fixes. If that scan ever throws, the hook reports the **unfiltered** wraps — a broken joiner must not be able to silence the detector.

## Fixing a file

```bash
bun "$(cc-plugin-root itp-hooks)/scripts/gfm-unwrap.ts" file.md            # rewrite in place
bun "$(cc-plugin-root itp-hooks)/scripts/gfm-unwrap.ts" --check file.md    # exit 1 if it would change
```

The reminder emits that exact form, resolved through [`cc-plugin-root`](../../../scripts/cc-plugin-root). It used to emit a bare `bun scripts/reflow-release-notes.ts …`, which resolves **only from inside cc-skills** — and the near-miss is what makes it dangerous rather than merely broken: a consumer repo with its own `scripts/reflow-commit-body.cjs` invites an agent to substitute a publish-boundary-only tool for an authoring-boundary one (issue #106 finding 2).

`gfm-unwrap` preserves fenced code, **4-space-indented code**, hand-aligned blocks, tables, headings, blockquote markers, and explicit two-space hard breaks; it joins wrapped prose, wrapped list items and wrapped blockquotes. It refuses to write anything if the transformation would change a single non-whitespace character (`assertContentPreserved`). The older `scripts/reflow-release-notes.ts` remains the semantic-release publish-boundary reflow; it does **not** understand indented code blocks, which is one reason the reminder no longer points at it. The Stop-hook formatter is still `--prose-wrap preserve` rather than auto-reflow — silently rewriting every edited `.md` has a blast radius a reminder does not.

## Escape hatch — invoking it, not naming it

Put the marker in an **HTML comment, in live markdown**:

```markdown
<!-- MD-HARD-WRAP-OK: verbatim quoted email, the line breaks are the content -->
```

`CASE_SENSITIVE`, `FILE_WIDE` (one invocation exempts the whole file), no reason required though one is polite; registered in the [iter-111 canonical registry](../hooks/lib/marketplace-wide-escape-hatch-producer-marker-canonical-registry-cross-plugin-iter111.ts). Pre-existing wraps never fire, so the marker is only needed for wrapping you are adding on purpose.

### Why it is not a plain substring match any more (issue #106 finding 1)

Until 2026-09-03 suppression was a bare regex over the whole file, so a document that merely **wrote the token down** — a CLAUDE.md explaining the hatch, a README documenting the hook, a CHANGELOG entry naming it — permanently disabled the reminder for itself. Documenting a hook is exactly when you hit this, and it is not hypothetical: all four tracked `.md` files in this repo containing the marker were documentation, none was an opt-out, and **all four were silently exempt** — this spoke among them. The operator's global `CLAUDE.md` worked around it by never spelling the token in full, which is a workaround for a bug living in the file that is supposed to be the authority.

Four things must now hold for the marker to suppress. Anything else is a mention:

| Where the marker sits                      | Suppresses | Why                                       |
| ------------------------------------------ | ---------- | ----------------------------------------- |
| Inside `<!-- … -->`, single- or multi-line | **yes**    | the only shape that means "switch it off" |
| Bare in prose (`Override: add MD-HARD-…`)  | no         | naming a token is not invoking it         |
| Inside an inline-code span                 | no         | quoting the syntax                        |
| Inside a fenced code block                 | no         | showing an example                        |
| Inside a 4-space / tab-indented code block | no         | same                                      |

**The stripping is per LINE, and that is load-bearing.** The obvious implementation — strip inline-code spans across the whole file, then look for the marker — is a trap. A whole-file stripper re-pairs backticks across the entire document, so the moment a file carries an **odd** number of backticks (19 of this repo's 1,094 tracked `.md` files do; one stray tick in prose is enough) it eats from that tick through the first backtick inside a legitimate escape comment, deleting the `<!--` opener and the marker with it — silently un-suppressing a file the operator deliberately exempted. `~/eon/ccmax-monitor`'s `PROVENANCE.md` is exactly that shape: a multi-line escape comment whose interior quotes `git check-ignore -v` in backticks. Per-line stripping cannot cross a line boundary, so a stray tick can corrupt at most its own line. There is a regression test for the whole fixture, including an assertion that the naive whole-file transform destroys the opener.

**Residual limit, stated accurately.** It is not merely "a raw token in live prose still suppresses" — that no longer suppresses at all. It is that **any** raw `<!-- MD-HARD-WRAP-OK -->` sequence outside a fence, outside an inline-code span and outside an indented code block **does** suppress, whatever the surrounding prose claims. A document wanting to show a live-looking comment must fence it, indent it, or wrap it in backticks — which is how you show markup anyway. There is no way to write a genuinely raw comment "as an example" and have it not count, because at that point it is indistinguishable from an opt-out.

Verified against every file on this machine that names the marker: the five genuine opt-outs (two `PROVENANCE.md` copies, two `legal-docs-source` files, one `amonic` ADR — all HTML comments, one of them multi-line with the marker on its own line) still suppress; the four cc-skills documentation files stop.

## Guarantees

- **Never blocks.** `additional_context` folded into the orchestrator's aggregated `{decision: "block", reason}`, which for PostToolUse is context injection, not rejection.
- **Fail-open.** Any parse or logic error → `noop`. Malformed input, missing `tool_input`, unknown tool → silent.
- **Cheap, but it does read the file.** No subprocess; every scan is a linear in-process pass, and registry position is last behind an O(1) extension pre-filter. This bullet used to claim "pure single-pass scan of the edited fragment; no subprocess, **no file read**", and the second half was never true — `detectNetNewMarkdownHardWraps` takes a `fileContentAfterEdit` parameter and the classifier reads the post-edit file from disk on every eligible edit, which is exactly what gives the fence scanner whole-file context. The behaviour was right; the sentence describing it was not (issue #106 finding 5). Measured cost of adding the joiner pass and the markdown-aware hatch scan, on `docs/HOOKS.md` (273 KB, 10 runs): **5.5 → 8.9 ms per edit**; on the 1.4 MB `CHANGELOG.md`, 48.5 ms. Do not compare against `CHANGELOG.md`'s old 0.7 ms — that number existed only because the file names the escape token, so the buggy substring match short-circuited the whole hook.

Those three figures were taken on an **idle machine**, and they are wall-clock, so treat them as an order of magnitude and not as a threshold. Do not turn them into a gate. The lesson is one the `iter-174` perf harness in this repo learned the expensive way and wrote down in its own header: wall-clock assertions are load-sensitive, and its scenario A6 was converted to gate on a **fork count** instead — which read exactly 23 on an idle box, at load average 46, and under 12-way fork contention, while A6's own wall clock swung 646 → 1364 ms in the same runs. Same process, same instant: the counted quantity never moved, the timed one nearly doubled. If the hard-wrap hook ever needs a performance gate, count work (scans, passes, allocations), don't time it.

- **Temp-scratch exempt** via the shared iter-124 helper — `/tmp/notes.md` is never nudged. The exemption is **absolute paths under `/tmp`, `/private/tmp`, `/var/folders`, `/private/var/folders`, `/dev/shm` and the live `$TMPDIR`** — a per-machine set, not a per-repo one. A **gitignored `tmp/` inside a repo is NOT exempt** and will be nudged (issue #106 finding 4). That is deliberate and stays: the helper is shared by every PostToolUse lint subhook, so teaching it to treat a repo-relative `tmp/` as scratch would change ty, tsc, oxlint, biome and vale at the same time, and "it is gitignored" is a weaker signal than it looks — a scratch brief in `tmp/` is still routinely lifted into an issue body, which is the surface this reminder exists for. Put throwaway markdown under `$TMPDIR` if you want silence, or invoke the escape hatch.
- **Out of scope**: git commit and annotated tag messages. 72-column wrapping is correct there; the reflow belongs at the publish boundary, which the sibling guards own.

## Tests

[`posttooluse-markdown-hard-wrap-reminder.test.ts`](../hooks/posttooluse-markdown-hard-wrap-reminder.test.ts) — 44 tests. Six are load-bearing:

- _"stays SILENT when an Edit rewords inside an already-wrapped paragraph"_ — if it regresses, the hook nags on 169 files.
- _"does NOT flag two shell lines edited inside a bash fence"_ — if it regresses, the hook fires on every command-example edit.
- _"fires on a Write of hard-wrapped sub-bullets"_ — if it regresses, the nested-bullet blind spot is back.
- _"does NOT suppress a file that merely NAMES the token in prose"_ — the issue #106 defect itself.
- _"suppresses through a code span INSIDE the comment, despite an unmatched backtick earlier"_ — if it regresses, a deliberately exempted file silently stops being exempt. Carries its own negative control: it asserts that the naive whole-file strip destroys the `<!--` opener.
- _"reports the joinable paragraph and NOT the aligned block in the same file"_ — a mixed fixture on purpose. An aligned-only fixture passes both for a correct filter and for one that silenced the detector outright, so it cannot tell them apart.

The escape-hatch tests build the marker literal at run time (`["MD-HARD-WRAP", "OK"].join("-")`) rather than spelling it, because a test file for a suppression token is not where you want to discover that spelling it suppresses something.

[`lib/hard-wrap-detector.test.ts`](../hooks/lib/hard-wrap-detector.test.ts) — 35 tests, covering the badge rows, the nested/third-level/ordered sub-bullets, and the two cases that must STAY code (an indented block with no list context, and one after a dedent to column zero).

[`lib/shared-escape-hatch-marker-detection-helper-…-iter107.test.ts`](../hooks/lib/shared-escape-hatch-marker-detection-helper-cross-pretooluse-and-posttooluse-iter107.test.ts) — 22 tests on the marker grammar itself: the four real-world opt-out shapes (one-line, reasoned, marker-on-its-own-line, multi-line with an interior code span), nine mention shapes that must NOT suppress, and the knobs (case sensitivity, minimum-reason gate, CRLF). Every mention case also asserts that the OLD whole-file substring match _does_ fire on it, so the file is a permanent record of the defect.

[`lib/gfm-unwrap.test.ts`](../hooks/lib/gfm-unwrap.test.ts) — the joiner, now including four tests pinning `computeJoinedWithNextLineMask` to the joiner it is derived from: its true-count must equal `joinsPerformed`, and the removed breaks must match the output's line count exactly. The mask cannot drift from the joiner without one of those failing.

## Adversarial-review fixes

A 16-agent adversarial review confirmed two defects, both fixed and regression-tested:

| Defect                                     | Consequence                                                                                                                                            | Fix                                                                                 |
| ------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------ | ----------------------------------------------------------------------------------- |
| `replace_all` ignored when undoing an edit | `replace_all` rewrote every occurrence but only the first was undone, leaving new text in the reconstructed before-state and under-reporting the delta | `extractEditPairs` carries the flag; `replaceAll` is used when set                  |
| No `isFile()` gate before reading the file | `Bun.file().text()` on a FIFO blocks until a writer appears, hanging the subhook until the orchestrator timeout on every edit                          | `statSync(filePath).isFile()` gate, matching `pretooluse-github-hard-wrap-guard.ts` |

The same review found **no false positives** across 57 adversarial cases (tilde fences, nested fences, front matter, HTML blocks, setext headings, CJK prose, long URLs, ASCII diagrams), measured `detectHardWraps` at 13 ms on a 1.3 MB file and 58 ms on a synthetic 10 MB one — both far inside the 2 s budget — and found no ReDoS in `isLinkOnlyLine`.
