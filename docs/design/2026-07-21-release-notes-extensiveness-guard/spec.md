# Design Spec: Release-Notes Extensiveness Guard

**ADR**: [/docs/adr/2026-07-21-release-notes-extensiveness-guard.md](/docs/adr/2026-07-21-release-notes-extensiveness-guard.md)
**Plugin**: `itp-hooks` · **Event**: PreToolUse · **Matcher**: `Bash`
**Doctrine SSoT**: `~/.claude/release-notes-doctrine-CLAUDE.md`

## Goal

Hard-block any release/tag-publishing command whose notes are not extensive and
human-readable — a narrative paragraph **and** a point-form list — so every
semantic-release release (any repo, any bump) is documented for humans, not as a
raw commit dump. Global by construction (ships in the always-installed
`itp-hooks` plugin).

## Files

| File                                                                           | Role                                        |
| ------------------------------------------------------------------------------ | ------------------------------------------- |
| `plugins/itp-hooks/hooks/release-notes-extensiveness-patterns.ts`              | Pure classifier + measurers + deny builders |
| `plugins/itp-hooks/hooks/pretooluse-release-notes-extensiveness-guard.ts`      | Thin stdin/stdout driver                    |
| `plugins/itp-hooks/hooks/pretooluse-release-notes-extensiveness-guard.test.ts` | 27 unit + subprocess tests                  |
| `plugins/itp-hooks/hooks/hooks.json`                                           | Registration (before `pueue-wrap-guard`)    |
| `plugins/itp-hooks/hooks/lib/…-registry-…-iter111.ts`                          | `RELEASE-NOTES-OK` marker entry             |
| `.mise/tasks/…escape-hatch-marker-detection-inventory…`                        | iter-110 consumer cohort membership         |
| `plugins/itp-hooks/docs/release-notes-extensiveness-guard.md`                  | Spoke                                       |
| `~/.claude/release-notes-doctrine-CLAUDE.md`                                   | Doctrine SSoT + hub row                     |

## Control flow (driver)

```
parseStdinOrAllow → not Bash / empty → allow
fast-path: command lacks gh|git|release → allow
isException (echo/printf/#/grep OR RELEASE-NOTES-OK: <≥10 chars>) → allow
classifyReleaseCommand(command):
  ├─ semantic-release / mise run release[:*]
  │     inspectReleasableCommitBodies(cwd) → ok ? allow : deny(commit msg)
  ├─ gh release create|edit  (whole-command notes extraction)
  └─ git tag -a/-s/-m/-F <semver>  (message extraction)
       notesUnmeasurable ($(…)/$VAR/backtick)      → allow
       notesAbsent (no --notes/--notes-file)       → deny(absent msg)
       notesFile (literal path)  → read file; unreadable → allow
       measureNotesExtensiveness(text) → ok ? allow : deny(notes msg)
main().catch → trackHookError → allow          # fail-open everywhere
```

Detection runs over the **whole command** (not per-newline segments) so multi-line
`--notes "…"` / `-m "…"` bodies are never fragmented.

## Extensiveness criteria

**Notes text** (`measureNotesExtensiveness`): split into lines; count bullet lines
(`-`/`*`/`+`/`N.`/`N)`); accumulate contiguous non-bullet, non-heading prose
into paragraphs; the longest paragraph is the "narrative". Pass requires:

- narrative ≥ `NARRATIVE_MIN_CHARS` (240) **and** ≥ `NARRATIVE_MIN_SENTENCES` (3), **and**
- bullets ≥ `POINT_FORM_MIN_BULLETS` (4).

**Commit bodies** (`analyzeCommitBodies`): releasable = subject `feat`/`fix`/`perf`
(optional scope, optional `!`) or body has `BREAKING CHANGE:`. Pass requires
aggregate body chars ≥ `COMMIT_AGGREGATE_MIN_CHARS` (400) **and** the richest body
≥ `COMMIT_RICH_PARAGRAPH_MIN_CHARS` (160). Zero releasable commits → pass
(semantic-release would no-op). Bodies < `COMMIT_THIN_BODY_CHARS` (160) are listed
by short hash in the deny message.

All six thresholds are named exports at the top of the patterns file (tunable).

## Interfaces (reused)

- `allow` / `deny` / `parseStdinOrAllow` / `trackHookError` — `pretooluse-helpers.ts`
- `hasFileWideEscapeHatchMarkerInContent` — iter-107 shared escape-hatch helper
  (config: `RELEASE-NOTES-OK`, CASE_SENSITIVE, FILE_WIDE, ≥10-char reason)
- `git` IO via `Bun.spawnSync` behind an injectable `GitRunner` (tests pass a stub)

## Fail-open & false-positive policy

Block only measurable thinness. Any parse/IO/git error, or a notes value that
cannot be statically resolved (`$(…)`, backticks, `$VAR`, unreadable
`--notes-file`), resolves to `allow`. `gh release … --notes-from-tag` is allowed
here (the tag message is measured on the `git tag` path).

## Placement invariant

Registered as the penultimate PreToolUse Bash entry — immediately before
`pretooluse-pueue-wrap-guard.ts`, which must remain last (iter-61 audit /
GitHub #15897 updatedInput aggregation). Timeout 8000 ms (allows the
`git log` shell-out on the semantic-release path).

## Test matrix

Classifier (gh/git-tag/semantic-release detection, absent/unmeasurable/file
branches), measurers (narrative-only, bullets-only, terse, rich pass),
commit-body analyzer (rich pass, thin block + hash list, chore-only pass,
BREAKING footer, log round-trip, injected-runner fail-open), and subprocess
wiring (deny/allow/escape/non-Bash/fast-path). 27 tests, all green.
