# Markdown hard-wrap reminder (net-new)

**Hook**: [`posttooluse-markdown-hard-wrap-reminder.ts`](../hooks/posttooluse-markdown-hard-wrap-reminder.ts) — subhook `markdown-hard-wrap-reminder` of the [PostToolUse Write/Edit orchestrator](./posttooluse-write-edit-orchestrator.md) · **Escape hatch**: `<!-- MD-HARD-WRAP-OK -->` — an HTML comment; merely naming the token does not suppress · **Hub**: [itp-hooks CLAUDE.md](../CLAUDE.md)

Reminds Claude when a `Write`/`Edit` of a `.md` file **introduces** prose broken mid-sentence at a fixed column, instead of authored as one line the renderer reflows.

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

Three cover the **publish** boundary. The authoring boundary is covered three ways, because Markdown is authored three ways: by the Write/Edit tools (this hook), by a shell command (a heredoc, `python3 - <<EOF`, a generator script), and finally by the commit that every path ends in. Until 2026-10-01 only the first existed, and a session rewrote dozens of `.md` files through Bash and Python, all hard-wrapped, with this reminder enabled and silent throughout: its matcher is `Write|Edit`, and a Bash command is not a file edit.

| Boundary                           | Mechanism                                                                                                               | Escape hatch      |
| ---------------------------------- | ----------------------------------------------------------------------------------------------------------------------- | ----------------- |
| `gh release \| issue \| pr \| api` | [`pretooluse-github-hard-wrap-guard.ts`](../hooks/pretooluse-github-hard-wrap-guard.ts) — denies                        | `GH-HARD-WRAP-OK` |
| semantic-release → GitHub Releases | `release.config.cjs` → `reflowCommitBodyForGfm()` → `scripts/reflow-release-notes.ts` — auto-reflows                    | —                 |
| Gmail draft bodies                 | [`pretooluse-gmail-body-guard.ts`](../hooks/pretooluse-gmail-body-guard.ts) — denies                                    | `GMAIL-BODY-OK`   |
| **Authoring a `.md`** (Write/Edit) | **this hook — reminds**                                                                                                 | `MD-HARD-WRAP-OK` |
| Authoring a `.md` (Bash)           | [`posttooluse-bash-markdown-hard-wrap-reminder.ts`](../hooks/posttooluse-bash-markdown-hard-wrap-reminder.ts) — reminds | `MD-HARD-WRAP-OK` |
| `git commit` of a `.md`            | [`pretooluse-markdown-commit-hard-wrap-guard.ts`](../hooks/pretooluse-markdown-commit-hard-wrap-guard.ts) — denies      | `MD-HARD-WRAP-OK` |

All of them share the one detector, [`lib/hard-wrap-detector.ts`](../hooks/lib/hard-wrap-detector.ts). The three authoring surfaces also share the net-new layer above it, [`lib/markdown-net-new-hard-wraps.ts`](../hooks/lib/markdown-net-new-hard-wraps.ts): the joiner filter, the shape signature, the multiset diff, the escape marker and the repair command, so they cannot disagree about what counts as a new wrap.

### The Bash and commit surfaces

**Bash reminder.** A PostToolUse hook sees only what is on disk after the command, not what the command wrote. So it checks the `.md` paths the command names (resolved against the cwd and every `cd` / `git -C` target) plus the Markdown `git status` reports modified or untracked in those repositories, keeps files modified in the last 15 minutes, and compares each against its `HEAD` version. A file with no `HEAD` version counts every wrap, as a Write does. A dirty file stays dirty across many Bash calls, so each (file, content hash) is judged once per session in a cache under the OS temp dir; this hook writes the same cache, so a file an Edit already reported is not reported again by the next Bash call. Measured cost: 50–80 ms per Bash call warm in a repository of several thousand files.

**Commit guard.** The one boundary no authoring path avoids. It compares what the commit will record against `HEAD`, whole file, net-new only: a plain `git commit` reads the index, `-a`/`-am` and `git commit <paths>` read the working tree. It follows `cd dir &&` and `git -C dir`, so it checks the repository the commit lands in. It **denies**, unlike the two reminders, because by commit time a reminder has nowhere left to land. Legacy wraps the commit does not touch never block it; rewording a wrapped paragraph changes its shape and is reported, which is the moment to reflow it. The commit message is out of scope (git objects are not GFM). The marker anywhere in the command passes a whole commit; the HTML comment in a file exempts that file.

Nothing else was watching authoring, and nothing was going to fix it later either: [`stop-markdown-lint.ts`](../hooks/stop-markdown-lint.ts) runs `prettier --write --prose-wrap preserve`, so a wrap written into a `.md` is **preserved forever**.

## Why net-new only

Measured over this repo's 1,114 tracked `.md` files at the time the hook was added: **193 files (17%) were already hard-wrapped**, 3,389 wrap points in total. A hook that fired whenever an edited file _contained_ a wrap would nag on every one of those files, every time, for debt the current edit did not create — and a guard that cries wolf gets disabled.

| Tool    | Rule                                                                               | Rationale                                                                         |
| ------- | ---------------------------------------------------------------------------------- | --------------------------------------------------------------------------------- |
| `Edit`  | fire iff `detectHardWraps(new_string).length > detectHardWraps(old_string).length` | rewording inside an already-wrapped paragraph leaves the count unchanged → silent |
| `Write` | fire on **any** wrap in `content`                                                  | the one non-strict arm — see below                                                |

### The comparison runs on the whole file, not the edit fragment

An `Edit` fragment lifted from **inside a fenced code block carries no ``markers**. Scanning that fragment on its own therefore reads shell commands as wrapped prose — two `bun scripts/reflow-release-notes.ts …` lines in a``bash block were a measured false positive, and updating a command example is one of the most common `.md` edits there is.

So the hook reads the post-edit file from disk (PostToolUse fires after the write, so the file **is** the after-state) and reconstructs the before-state by undoing the replacement — `content.replace(new_string, old_string)`. `String.replace` with a string pattern rewrites the first match only, which is exactly `Edit`'s own uniqueness contract.

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

### Bulk reflow: not every `.md` is prose

Reflowing a whole repository is safe only for authored prose. Measured 2026-10-01, across six repositories: content-preservation held on every file, and the reflow still broke two gates, because a `.md` file can be something other than a document. Leave these classes alone:

- **Model prompts** (`prompts/*.md`, `.claude/commands/`, skills under eval). They are runtime inputs. Code cites them by line number (`extract.system.v23.md:616-623`), and a prompt-version test failed once their bytes changed.
- **Generated files.** A gate compares them byte for byte against their generator, so reflow the generator's output format instead; a generator that writes wrapped prose will also trip the commit guard whenever it adds lines.
- **Verbatim records**: email threads, chat logs, transcripts, contracts, raw exports. Their line breaks are part of the record.
- **Test fixtures and frozen trees** (`archive/`, `tmp/`, `data/`).

Prove the result twice: per file before writing, and with `git diff --word-diff=porcelain --word-diff-regex='[^[:space:]]+'` afterwards. The only non-whitespace change allowed is a dropped blockquote `>` continuation marker. Then run the repository's own gate before committing, because it knows which `.md` files are not prose. A whitespace check does not.

## Escape hatch — invoking it, not naming it

Put the marker in an **HTML comment, in live markdown**:

```markdown
<!-- MD-HARD-WRAP-OK: verbatim quoted email, the line breaks are the content -->
```

`CASE_SENSITIVE`, `FILE_WIDE` (one invocation exempts the whole file), no reason required though one is polite; registered in the [canonical marker registry](../hooks/lib/escape-hatch-marker-registry-iter111.ts). Pre-existing wraps never fire, so the marker is only needed for wrapping you are adding on purpose.

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

**The stripping is per LINE, and that is load-bearing.** The obvious implementation — strip inline-code spans across the whole file, then look for the marker — is a trap. A whole-file stripper re-pairs backticks across the entire document, so the moment a file carries an **odd** number of backticks (19 of this repo's 1,094 tracked `.md` files do; one stray tick in prose is enough) it eats from that tick through the first backtick inside a legitimate escape comment, deleting the `<!--` opener and the marker with it — silently un-suppressing a file the operator deliberately exempted. `~/eon/relay-monitor`'s `PROVENANCE.md` is exactly that shape: a multi-line escape comment whose interior quotes `git check-ignore -v` in backticks. Per-line stripping cannot cross a line boundary, so a stray tick can corrupt at most its own line. There is a regression test for the whole fixture, including an assertion that the naive whole-file transform destroys the opener.

**Residual limit, stated accurately.** It is not merely "a raw token in live prose still suppresses" — that no longer suppresses at all. It is that **any** raw `<!-- MD-HARD-WRAP-OK -->` sequence outside a fence, outside an inline-code span and outside an indented code block **does** suppress, whatever the surrounding prose claims. A document wanting to show a live-looking comment must fence it, indent it, or wrap it in backticks — which is how you show markup anyway. There is no way to write a genuinely raw comment "as an example" and have it not count, because at that point it is indistinguishable from an opt-out.

Verified against every file on this machine that names the marker: the five genuine opt-outs (two `PROVENANCE.md` copies, two `<private-docs-repo>` files, one `<automation-repo>` ADR — all HTML comments, one of them multi-line with the marker on its own line) still suppress; the four cc-skills documentation files stop.

## Guarantees

- **Never blocks.** `additional_context` folded into the orchestrator's aggregated `{decision: "block", reason}`, which for PostToolUse is context injection, not rejection.
- **Fail-open.** Any parse or logic error → `noop`. Malformed input, missing `tool_input`, unknown tool → silent.
- **Cheap, but it does read the file.** No subprocess; every scan is a linear in-process pass, and registry position is last behind an O(1) extension pre-filter. The classifier reads the post-edit file from disk on every eligible edit (`detectNetNewMarkdownHardWraps` takes a `fileContentAfterEdit` parameter), which is what gives the fence scanner whole-file context. On an idle machine that costs about 9 ms per edit on `docs/HOOKS.md` (273 KB) and about 50 ms on the 1.4 MB `CHANGELOG.md`.

Those figures are wall-clock on an idle machine, so treat them as an order of magnitude, not a threshold, and do not turn them into a gate: wall-clock assertions are load-sensitive. If the hook ever needs a performance gate, count work (scans, passes, allocations) rather than timing it — the approach [`tasks/tests/test-iter174-commits-toolkit-perf-baseline.sh`](../../../tasks/tests/test-iter174-commits-toolkit-perf-baseline.sh) takes with its load-invariant fork count.

- **Temp-scratch exempt** via the shared helper in [`lib/shared-temp-dir-edit-path-detection-iter124.ts`](../hooks/lib/shared-temp-dir-edit-path-detection-iter124.ts) — `/tmp/notes.md` is never nudged. The exemption is **absolute paths under `/tmp`, `/private/tmp`, `/var/folders`, `/private/var/folders`, `/dev/shm` and the live `$TMPDIR`** — a per-machine set, not a per-repo one. A **gitignored `tmp/` inside a repo is NOT exempt** and will be nudged. That is deliberate and stays: the helper is shared by every PostToolUse lint subhook, so teaching it to treat a repo-relative `tmp/` as scratch would change ty, tsc, oxlint, biome and vale at the same time, and "it is gitignored" is a weaker signal than it looks — a scratch brief in `tmp/` is still routinely lifted into an issue body, which is the surface this reminder exists for. Put throwaway markdown under `$TMPDIR` if you want silence, or invoke the escape hatch.
- **Out of scope**: git commit and annotated tag messages. 72-column wrapping is correct there; the reflow belongs at the publish boundary, which the sibling guards own.

## Tests

[`posttooluse-markdown-hard-wrap-reminder.test.ts`](../hooks/posttooluse-markdown-hard-wrap-reminder.test.ts). Six tests are load-bearing:

- _"stays SILENT when an Edit rewords inside an already-wrapped paragraph"_ — if it regresses, the hook nags on 169 files.
- _"does NOT flag two shell lines edited inside a bash fence"_ — if it regresses, the hook fires on every command-example edit.
- _"fires on a Write of hard-wrapped sub-bullets"_ — if it regresses, the nested-bullet blind spot is back.
- _"does NOT suppress a file that merely NAMES the token in prose"_ — the issue #106 defect itself.
- _"suppresses through a code span INSIDE the comment, despite an unmatched backtick earlier"_ — if it regresses, a deliberately exempted file silently stops being exempt. Carries its own negative control: it asserts that the naive whole-file strip destroys the `<!--` opener.
- _"reports the joinable paragraph and NOT the aligned block in the same file"_ — a mixed fixture on purpose. An aligned-only fixture passes both for a correct filter and for one that silenced the detector outright, so it cannot tell them apart.

The escape-hatch tests build the marker literal at run time (`["MD-HARD-WRAP", "OK"].join("-")`) rather than spelling it, because a test file for a suppression token is not where you want to discover that spelling it suppresses something.

[`lib/hard-wrap-detector.test.ts`](../hooks/lib/hard-wrap-detector.test.ts) — covers the badge rows, the nested/third-level/ordered sub-bullets, and the two cases that must STAY code (an indented block with no list context, and one after a dedent to column zero).

[`lib/escape-hatch-marker-detection-iter107.test.ts`](../hooks/lib/escape-hatch-marker-detection-iter107.test.ts) — the marker grammar itself: the four real-world opt-out shapes (one-line, reasoned, marker-on-its-own-line, multi-line with an interior code span), nine mention shapes that must NOT suppress, and the knobs (case sensitivity, minimum-reason gate, CRLF). Every mention case also asserts that a plain whole-file substring match _would_ fire on it, which is why that match is not used for documents.

[`lib/gfm-unwrap.test.ts`](../hooks/lib/gfm-unwrap.test.ts) — the joiner, now including four tests pinning `computeJoinedWithNextLineMask` to the joiner it is derived from: its true-count must equal `joinsPerformed`, and the removed breaks must match the output's line count exactly. The mask cannot drift from the joiner without one of those failing.

## Adversarial-review fixes

A 16-agent adversarial review confirmed two defects, both fixed and regression-tested:

| Defect                                     | Consequence                                                                                                                                            | Fix                                                                                 |
| ------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------ | ----------------------------------------------------------------------------------- |
| `replace_all` ignored when undoing an edit | `replace_all` rewrote every occurrence but only the first was undone, leaving new text in the reconstructed before-state and under-reporting the delta | `extractEditPairs` carries the flag; `replaceAll` is used when set                  |
| No `isFile()` gate before reading the file | `Bun.file().text()` on a FIFO blocks until a writer appears, hanging the subhook until the orchestrator timeout on every edit                          | `statSync(filePath).isFile()` gate, matching `pretooluse-github-hard-wrap-guard.ts` |

The same review found **no false positives** across 57 adversarial cases (tilde fences, nested fences, front matter, HTML blocks, setext headings, CJK prose, long URLs, ASCII diagrams), measured `detectHardWraps` at 13 ms on a 1.3 MB file and 58 ms on a synthetic 10 MB one — both far inside the 2 s budget — and found no ReDoS in `isLinkOnlyLine`.
