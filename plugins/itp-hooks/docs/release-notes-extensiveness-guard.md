# Release-Notes Extensiveness Guard

**Hook**: `pretooluse-release-notes-extensiveness-guard.ts` (matcher `Bash`)
**Classifier**: `release-notes-extensiveness-patterns.ts` (pure, unit-tested)
**Doctrine SSoT**: `~/.claude/release-notes-doctrine-CLAUDE.md`
**ADR**: [/docs/adr/2026-07-21-release-notes-extensiveness-guard.md](/docs/adr/2026-07-21-release-notes-extensiveness-guard.md)

## Policy

Every semantic-release release — any repo, any bump — must ship notes that carry
**both** a narrative paragraph (the _why_) **and** a point-form list (the _what_).
Terse commit-dump releases (a bare `Bug Fixes` / `Features` one-liner list) are
blocked. Full rationale + mandatory format live in the doctrine SSoT.

## Interception points and criteria

| Command                                                                 | Measured                                        | Blocked when                                                              |
| ----------------------------------------------------------------------- | ----------------------------------------------- | ------------------------------------------------------------------------- |
| `gh release create` / `gh release edit`                                 | `--notes` / `-n` / `--notes-file` / `-F` text   | missing a narrative paragraph OR fewer than 4 bullets, or no notes at all |
| `git tag -a/-s/-m/-F <semver>`                                          | the annotated-tag message                       | same narrative + point-form bar                                           |
| `semantic-release`, `npx/bunx semantic-release`, `mise run release[:*]` | releasable commit **bodies** since the last tag | bodies collectively thin (see thresholds)                                 |

For semantic-release, "releasable" = commits whose subject is `feat`/`fix`/`perf`
(optional scope, optional `!`) or whose body carries a `BREAKING CHANGE:` footer.
Notes are derived from those bodies, so that is what the guard measures.

## Thresholds (tunable — top of the patterns file)

| Constant                          | Default | Meaning                                         |
| --------------------------------- | ------- | ----------------------------------------------- |
| `NARRATIVE_MIN_CHARS`             | 240     | longest prose paragraph must reach this         |
| `NARRATIVE_MIN_SENTENCES`         | 3       | …and hold this many sentence terminators        |
| `POINT_FORM_MIN_BULLETS`          | 4       | minimum bullet items                            |
| `COMMIT_AGGREGATE_MIN_CHARS`      | 400     | sum of releasable commit body chars             |
| `COMMIT_RICH_PARAGRAPH_MIN_CHARS` | 160     | at least one commit body must reach this        |
| `COMMIT_THIN_BODY_CHARS`          | 160     | a releasable commit shorter than this is "thin" |

## Allowed / fail-open

- Not a release/tag command → allow (fast-path keyword gate: `gh`/`git`/`release`).
- Notes value is a `$(…)` command substitution, backticks, or `$VAR` → allow
  (cannot prove thinness).
- `--notes-file` path unreadable, or any git/parse error → allow (fail-open).
- `gh release … --notes-from-tag` → allow here (the tag message is measured on
  the `git tag` path instead).
- No releasable commits for the semantic-release path → allow (semantic-release
  would no-op anyway).

## Escape hatch

`RELEASE-NOTES-OK: <≥10-char reason>` anywhere in the command — for a genuinely
un-narratable release (pure dependency/chore bump, re-tag). Reason-gated so the
bypass is deliberate. Registered in the iter-111 canonical marker registry
(CASE_SENSITIVE, FILE_WIDE, ≥10-char reason).

## Tests

`pretooluse-release-notes-extensiveness-guard.test.ts` — pure classifier +
measurers + subprocess wiring (block/allow/escape/fail-open, semantic-release
commit inspection via an injected git runner).
